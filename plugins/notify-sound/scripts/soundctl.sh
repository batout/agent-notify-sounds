#!/usr/bin/env bash
# notify-sound control CLI.
#
#   soundctl.sh status              show current settings
#   soundctl.sh list                list the themes
#   soundctl.sh sounds [theme]      list every sound file: format, length, size
#   soundctl.sh preview [theme]     play all three cues of a theme
#   soundctl.sh set [--here] <theme>  switch theme (--here = this project only)
#   soundctl.sh volume <0.0-1.0>    set playback volume
#   soundctl.sh mute | unmute       toggle all sounds
#   soundctl.sh on|off <event>      per-event toggle (done|attention|plan|subagent)
#   soundctl.sh min-turn <seconds>  only ring "done" past this turn length (0 = always)
#   soundctl.sh focus on|off        skip "done" while your terminal is frontmost (macOS)
#   soundctl.sh test <event>        play one cue
#   soundctl.sh stop                stop whatever is playing right now

set -u
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

NS_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"

label() {
  case "$1" in
    zaghlalah) printf '%-9s — short radio beeps, morse DO / NE / PL' "$1" ;;
    jersey)    printf '%-9s — overdriven bass riff with a little swagger' "$1" ;;
    marimba)   printf '%-9s — warm wooden mallets, soft and short' "$1" ;;
    system)    printf '%-9s — OS built-ins: Glass / Submarine / Hero' "$1" ;;
    *)         printf '%-9s — custom theme, sounds/%s/' "$1" "$1" ;;
  esac
}

event_label() {
  case "$1" in
    done)      printf 'the task or the answer is finished' ;;
    attention) printf 'waiting on you — question or permission' ;;
    plan)      printf 'plan ready for approval' ;;
    subagent)  printf 'a background agent finished' ;;
  esac
}

# "0.7 (user)" — so it's obvious when a project file is overriding you.
cfg_show() { printf '%s (%s)' "$(cfg_get "$1" "$2")" "$(cfg_source "$1")"; }

cmd_status() {
  local t pf mt
  t="$(current_theme)"
  echo "notify-sound"
  echo "  theme      : $t ($(cfg_source theme))"
  echo "  volume     : $(cfg_show volume 0.7)"
  echo "  muted      : $(cfg_show mute 0)"
  printf '  events     :'
  for e in $EVENTS; do printf ' %s=%s' "$e" "$(cfg_get "$e" 1)"; done
  echo
  mt="$(cfg_get min_turn_ms 15000)"
  if [ "$mt" = "0" ]; then
    echo "  done rule  : always rings"
  else
    echo "  done rule  : only after turns longer than $(awk -v m="$mt" 'BEGIN{printf "%.0fs", m/1000}') (min_turn_ms=$mt)"
  fi
  echo "               silent for $(awk -v m="$(cfg_get done_suppress_ms 10000)" 'BEGIN{printf "%.0fs", m/1000}') after a plan or permission cue"
  [ "$(cfg_get focus_aware 0)" = "1" ] && echo "               skipped while ${TERM_PROGRAM:-your terminal} is frontmost"
  echo "  player     : $(player_name)"
  is_remote && echo "  remote     : SSH session, mode=$(cfg_get remote bell)"
  echo "  config     : $CONFIG_FILE"
  pf="$(project_config_file 2>/dev/null)" || pf=""
  [ -n "$pf" ] && [ -f "$pf" ] && echo "               $pf (project, wins)"
  echo "  resolved   :"
  for e in $EVENTS; do
    printf '    %-10s %s\n' "$e" "$(resolve_sound "$t" "$e" || printf '—')"
  done
}

cmd_list() {
  local cur; cur="$(current_theme)"
  for t in $THEMES; do
    if [ "$t" = "$cur" ]; then printf '  * %s\n' "$(label "$t")"
    else printf '    %s\n' "$(label "$t")"; fi
  done
  echo
  echo "  * = active.  Each theme has a distinct cue per event:"
  for e in $EVENTS; do printf '      %-10s %s\n' "$e" "$(event_label "$e")"; done
}

# Duration in seconds, best effort — ffprobe, macOS afinfo, or the WAV header.
sound_duration() {
  local f="$1" d=""
  [ -n "$f" ] && [ -r "$f" ] || return 0
  if command -v ffprobe >/dev/null 2>&1; then
    d="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$f" 2>/dev/null)"
  elif command -v afinfo >/dev/null 2>&1; then
    d="$(afinfo "$f" 2>/dev/null | awk '/estimated duration/{print $3; exit}')"
  elif command -v python3 >/dev/null 2>&1 && [ "${f##*.}" = "wav" ]; then
    d="$(python3 -c 'import wave,sys
w=wave.open(sys.argv[1]);print(w.getnframes()/w.getframerate())' "$f" 2>/dev/null)"
  fi
  [ -n "$d" ] && awk -v d="$d" 'BEGIN{printf "%.2fs", d}'
}

sound_size() {
  local b
  [ -n "${1:-}" ] || return 0
  b="$(wc -c < "$1" 2>/dev/null | tr -d ' ')"
  [ -n "$b" ] && awk -v b="$b" 'BEGIN{printf "%.0fK", b/1024}'
}

cmd_sounds() {
  local only="${1:-}" cur t f fmt shared
  [ -n "$only" ] && only="$(normalize_theme "$only")"
  cur="$(current_theme)"
  printf '  %-10s %-10s %-26s %-6s %8s %7s\n' THEME CUE FILE FORMAT LENGTH SIZE
  printf '  %s\n' "$(printf '%.0s-' $(seq 1 72))"
  for t in $THEMES; do
    [ -n "$only" ] && [ "$t" != "$only" ] && continue
    for e in $EVENTS; do
      f="$(resolve_sound "$t" "$e")" || f=""
      if [ "$t" = "system" ]; then
        printf '  %-10s %-10s %-26s %-6s %8s %7s\n' \
          "$t$([ "$t" = "$cur" ] && printf '*')" "$e" "(OS built-in)" "-" "-" "-"
        continue
      fi
      # A cue with no file of its own borrows another one — flag it.
      # ASCII on purpose: printf pads %-26s by bytes, so a multibyte marker
      # would shift every column after it.
      shared=""
      theme_file "$t" "$e" >/dev/null 2>&1 || shared=" <-"
      fmt="$(printf '%s' "${f##*.}" | tr '[:upper:]' '[:lower:]')"
      printf '  %-10s %-10s %-26s %-6s %8s %7s\n' \
        "$t$([ "$t" = "$cur" ] && printf '*')" "$e" \
        "$([ -n "$f" ] && basename "$f" || printf '—')$shared" \
        "${fmt:--}" "$(sound_duration "$f")" "$(sound_size "$f")"
    done
  done
  echo
  echo "  * = active theme.   <- = borrowed, that theme ships no file for the cue."
  echo "  Play any one with:  soundctl.sh test <cue>"
  echo "  Sound files live in: $SOUNDS_DIR"
}

cmd_preview() {
  local t="${1:-$(current_theme)}"
  t="$(normalize_theme "$t")"
  case " $THEMES " in *" $t "*) ;; *) echo "unknown theme: $t"; return 1 ;; esac
  echo "previewing theme: $t"
  local f d w
  for e in $EVENTS; do
    printf '  %-10s %s\n' "$e" "$(event_label "$e")"
    f="$(resolve_sound "$t" "$e")" || continue
    play_file "$f"
    # Wait out the actual clip instead of guessing, so long custom sounds
    # aren't cut off by the next one.
    d="$(sound_duration "$f" | tr -d 's')"
    w="$(awk -v d="${d:-1}" 'BEGIN{v=d+0.6; if(v<1.2)v=1.2; if(v>9)v=9; printf "%.2f", v}')"
    sleep "$w"
  done
}

cmd_set() {
  local scope=user t
  if [ "${1:-}" = "--here" ] || [ "${1:-}" = "--project" ]; then scope=project; shift; fi
  t="$(normalize_theme "${1:-}")"
  case " $THEMES " in
    *" $t "*) ;;
    *) echo "usage: set [--here] <$(echo $THEMES | tr ' ' '|')>"; return 1 ;;
  esac
  cfg_set theme "$t" "$scope" || { echo "no project directory to write to"; return 1; }
  if [ "$scope" = "project" ]; then
    echo "theme set to: $t (this project only — $(project_config_file))"
  else
    echo "theme set to: $t"
  fi
  play_file "$(resolve_sound "$t" done)"
}

cmd_min_turn() {
  local s="${1:-}" ms
  case "$s" in ''|*[!0-9.]*) echo "usage: min-turn <seconds>  (0 = always ring)"; return 1 ;; esac
  ms="$(awk -v s="$s" 'BEGIN{printf "%d", s*1000}')"
  cfg_set min_turn_ms "$ms"
  if [ "$ms" = "0" ]; then echo "done now rings on every turn"
  else echo "done now rings only after turns longer than ${s}s"; fi
}

case "${1:-status}" in
  status)  cmd_status ;;
  stop)    stop_playing --all; echo "stopped" ;;
  list)    cmd_list ;;
  sounds|files|ls) cmd_sounds "${2:-}" ;;
  preview) cmd_preview "${2:-}" ;;
  set)     shift; cmd_set "$@" ;;
  volume)  cfg_set volume "${2:-0.7}"; echo "volume set to ${2:-0.7}"
           play_file "$(resolve_sound "$(current_theme)" done)" "${2:-0.7}" ;;
  mute)    cfg_set mute 1; echo "sounds muted" ;;
  unmute)  cfg_set mute 0; echo "sounds unmuted"
           play_file "$(resolve_sound "$(current_theme)" done)" ;;
  on)      cfg_set "${2:?event}" 1; echo "${2} sound enabled" ;;
  off)     cfg_set "${2:?event}" 0; echo "${2} sound disabled" ;;
  min-turn) cmd_min_turn "${2:-}" ;;
  focus)   case "${2:-}" in
             on)  cfg_set focus_aware 1; echo "done is skipped while your terminal is frontmost" ;;
             off) cfg_set focus_aware 0; echo "focus check off" ;;
             *)   echo "usage: focus on|off"; exit 1 ;;
           esac ;;
  test)    play_file "$(resolve_sound "$(current_theme)" "${2:-done}")"; echo "played ${2:-done}" ;;
  *)       awk 'NR>1{ if (/^#/) { sub(/^# ?/,""); print } else exit }' "$0" ;;
esac
