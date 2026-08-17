#!/usr/bin/env bash
# notify-sound control CLI.
#
#   soundctl.sh status              show current settings
#   soundctl.sh list                list the themes
#   soundctl.sh sounds [theme]      list every sound file: format, length, size
#   soundctl.sh preview [theme]     play all three cues of a theme
#   soundctl.sh set <theme>         switch theme (see: soundctl.sh list)
#   soundctl.sh volume <0.0-1.0>    set playback volume
#   soundctl.sh mute | unmute       toggle all sounds
#   soundctl.sh on|off <event>      per-event toggle (done|attention|plan)
#   soundctl.sh test <event>        play one cue
#   soundctl.sh stop                stop whatever is playing right now

set -u
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

label() {
  case "$1" in
    zaghlalah) printf '%-9s — short radio beeps, morse DO / NE / PL' "$1" ;;
    jersey)    printf '%-9s — overdriven bass riff with a little swagger' "$1" ;;
    marimba)   printf '%-9s — warm wooden mallets, soft and short' "$1" ;;
    system)    printf '%-9s — macOS built-ins: Glass / Submarine / Hero' "$1" ;;
    *)         printf '%-9s — custom theme, sounds/%s/' "$1" "$1" ;;
  esac
}

event_label() {
  case "$1" in
    done)      printf 'work finished / turn ended' ;;
    attention) printf 'waiting on you — question or permission' ;;
    plan)      printf 'plan ready for approval' ;;
  esac
}

cmd_status() {
  local t; t="$(current_theme)"
  echo "notify-sound"
  echo "  theme      : $t"
  echo "  volume     : $(current_volume)"
  echo "  muted      : $(cfg_get mute 0)"
  echo "  events     : done=$(cfg_get done 1)  attention=$(cfg_get attention 1)  plan=$(cfg_get plan 1)"
  echo "  player     : $(player_name)"
  echo "  config     : $CONFIG_FILE"
  echo "  resolved   :"
  for e in $EVENTS; do
    printf '    %-10s %s\n' "$e" "$(resolve_sound "$t" "$e")"
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
  [ -r "$f" ] || return 0
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
  b="$(wc -c < "$1" 2>/dev/null | tr -d ' ')"
  [ -n "$b" ] && awk -v b="$b" 'BEGIN{printf "%.0fK", b/1024}'
}

cmd_sounds() {
  local only="${1:-}" cur t f fmt
  [ -n "$only" ] && only="$(normalize_theme "$only")"
  cur="$(current_theme)"
  printf '  %-10s %-10s %-26s %-6s %8s %7s\n' THEME CUE FILE FORMAT LENGTH SIZE
  printf '  %s\n' "$(printf '%.0s-' $(seq 1 72))"
  for t in $THEMES; do
    [ -n "$only" ] && [ "$t" != "$only" ] && continue
    for e in $EVENTS; do
      f="$(resolve_sound "$t" "$e")"
      if [ "$t" = "system" ] && ! is_macos; then
        printf '  %-10s %-10s %-26s %-6s %8s %7s\n' \
          "$t$([ "$t" = "$cur" ] && printf '*')" "$e" "(macOS built-in)" "-" "-" "-"
        continue
      fi
      fmt="$(printf '%s' "${f##*.}" | tr '[:upper:]' '[:lower:]')"
      printf '  %-10s %-10s %-26s %-6s %8s %7s\n' \
        "$t$([ "$t" = "$cur" ] && printf '*')" "$e" "$(basename "${f:-—}")" \
        "${fmt:--}" "$(sound_duration "$f")" "$(sound_size "$f")"
    done
  done
  echo
  echo "  * = active theme.  Play any one with:  soundctl.sh test <cue>"
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
    f="$(resolve_sound "$t" "$e")"
    play_file "$f"
    # Wait out the actual clip instead of guessing, so long custom sounds
    # aren't cut off by the next one.
    d="$(sound_duration "$f" | tr -d 's')"
    w="$(awk -v d="${d:-1}" 'BEGIN{v=d+0.6; if(v<1.2)v=1.2; if(v>9)v=9; printf "%.2f", v}')"
    sleep "$w"
  done
}

cmd_set() {
  local t="${1:-}"
  t="$(normalize_theme "$t")"
  case " $THEMES " in *" $t "*) ;; *) echo "usage: set <$(echo $THEMES | tr ' ' '|')>"; return 1 ;; esac
  cfg_set theme "$t"
  echo "theme set to: $t"
  play_file "$(resolve_sound "$t" done)"
}

case "${1:-status}" in
  status)  cmd_status ;;
  stop)    stop_playing; echo "stopped" ;;
  list)    cmd_list ;;
  sounds|files|ls) cmd_sounds "${2:-}" ;;
  preview) cmd_preview "${2:-}" ;;
  set)     cmd_set "${2:-}" ;;
  volume)  cfg_set volume "${2:-0.7}"; echo "volume set to ${2:-0.7}"
           play_file "$(resolve_sound "$(current_theme)" done)" "${2:-0.7}" ;;
  mute)    cfg_set mute 1; echo "sounds muted" ;;
  unmute)  cfg_set mute 0; echo "sounds unmuted"
           play_file "$(resolve_sound "$(current_theme)" done)" ;;
  on)      cfg_set "${2:?event}" 1; echo "${2} sound enabled" ;;
  off)     cfg_set "${2:?event}" 0; echo "${2} sound disabled" ;;
  test)    play_file "$(resolve_sound "$(current_theme)" "${2:-done}")"; echo "played ${2:-done}" ;;
  *)       awk 'NR>1{ if (/^#/) { sub(/^# ?/,""); print } else exit }' "$0" ;;
esac
