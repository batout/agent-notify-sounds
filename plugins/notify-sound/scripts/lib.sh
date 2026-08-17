#!/usr/bin/env bash
# Shared helpers for the notify-sound plugin.
# Sourced by play.sh and soundctl.sh.

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SOUNDS_DIR="$PLUGIN_ROOT/sounds"
CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CONFIG_FILE="$CONFIG_DIR/notify-sound.conf"

EVENTS="done attention plan"
DEFAULT_THEME="zaghlalah"   # also the fallback when "system" isn't available

# Themes are drop-in: every sounds/<name>/ directory is a theme, no code change
# needed to add one. Default first, the rest alphabetically, "system" last.
discover_themes() {
  local d n rest=""
  for d in "$SOUNDS_DIR"/*/; do
    [ -d "$d" ] || continue
    n="${d%/}"; n="${n##*/}"
    case "$n" in "$DEFAULT_THEME"|system) continue ;; esac
    rest="$rest $n"
  done
  printf '%s%s system' "$DEFAULT_THEME" "$rest"
}
THEMES="$(discover_themes)"

# ---------------------------------------------------------------- config --
# Simple key=value file so we never need jq. Missing file == defaults.
cfg_get() {
  local key="$1" default="$2" val=""
  if [ -f "$CONFIG_FILE" ]; then
    val=$(grep -E "^[[:space:]]*${key}[[:space:]]*=" "$CONFIG_FILE" 2>/dev/null \
          | tail -n 1 | cut -d= -f2- | tr -d '"'"'"' \r' | xargs 2>/dev/null)
  fi
  [ -n "$val" ] && printf '%s' "$val" || printf '%s' "$default"
}

cfg_set() {
  local key="$1" val="$2" tmp
  mkdir -p "$CONFIG_DIR"
  [ -f "$CONFIG_FILE" ] || printf '# notify-sound plugin settings\n' > "$CONFIG_FILE"
  tmp="$(mktemp)"
  grep -vE "^[[:space:]]*${key}[[:space:]]*=" "$CONFIG_FILE" > "$tmp" 2>/dev/null
  printf '%s=%s\n' "$key" "$val" >> "$tmp"
  mv "$tmp" "$CONFIG_FILE"
}

is_macos() { [ "$(uname -s 2>/dev/null)" = "Darwin" ]; }

normalize_theme() {   # accept the old names from 0.1.x
  case "$1" in chime|morse) printf 'zaghlalah' ;; *) printf '%s' "$1" ;; esac
}

current_theme() {
  local t
  t="$(normalize_theme "${CLAUDE_SOUND_THEME:-$(cfg_get theme "")}")"
  [ -n "$t" ] || t="$DEFAULT_THEME"
  case " $THEMES " in *" $t "*) ;; *) t="$DEFAULT_THEME" ;; esac
  printf '%s' "$t"
}

current_volume() { cfg_get volume "0.7"; }

# ------------------------------------------------------------ resolution --
# macOS system sounds used by the "system" theme.
macos_sound_for() {
  case "$1" in
    done)      printf '/System/Library/Sounds/Glass.aiff' ;;
    attention) printf '/System/Library/Sounds/Submarine.aiff' ;;
    plan)      printf '/System/Library/Sounds/Hero.aiff' ;;
  esac
}

# Echoes the absolute path of the file to play for <theme> <event>.
resolve_sound() {
  local theme event f
  theme="$(normalize_theme "$1")"; event="$2"
  if [ "$theme" = "system" ]; then
    f="$(macos_sound_for "$event")"
    if is_macos && [ -r "$f" ]; then printf '%s' "$f"; return 0; fi
    theme="$DEFAULT_THEME"   # fall back to the bundled set off macOS
  fi
  # Themes may ship .wav (synthesized) or .mp3 (audio clips).
  for ext in wav mp3 m4a aiff ogg flac; do
    f="$SOUNDS_DIR/$theme/$event.$ext"
    [ -r "$f" ] && { printf '%s' "$f"; return 0; }
  done
}

# ---------------------------------------------------------------- player --
PIDFILE="${TMPDIR:-/tmp}/.claude-notify-sound.pid"


# Echoes the best available player for a given file, or nothing.
pick_player() {
  local ext order p
  ext="$(printf '%s' "${1##*.}" | tr '[:upper:]' '[:lower:]')"
  case "$ext" in
    wav|aiff|aif) order="afplay paplay aplay ffplay mpg123 powershell.exe" ;;
    *)            order="afplay ffplay mpg123 mpv cvlc" ;;   # compressed formats
  esac
  for p in $order; do
    command -v "$p" >/dev/null 2>&1 && { printf '%s' "$p"; return 0; }
  done
  return 1
}

# Stops whatever this plugin is currently playing (clips can run several seconds).
stop_playing() {
  local pid
  [ -f "$PIDFILE" ] || return 0
  pid="$(cat "$PIDFILE" 2>/dev/null)"
  case "$pid" in ''|*[!0-9]*) return 0 ;; esac
  kill "$pid" 2>/dev/null
  rm -f "$PIDFILE" 2>/dev/null
  return 0
}

# Plays a file. Returns immediately; audio finishes in the background.
play_file() {
  local f="$1" vol="${2:-$(current_volume)}" p pv wf
  [ -n "$f" ] && [ -r "$f" ] || return 0
  p="$(pick_player "$f")" || { printf '\a' >/dev/tty 2>/dev/null; return 0; }

  stop_playing

  case "$p" in
    afplay)  nohup afplay -v "$vol" "$f" >/dev/null 2>&1 </dev/null & ;;
    paplay)  pv=$(awk -v v="$vol" 'BEGIN{printf "%d", (v*65536)}' 2>/dev/null)
             nohup paplay --volume="${pv:-46000}" "$f" >/dev/null 2>&1 </dev/null & ;;
    ffplay)  nohup ffplay -nodisp -autoexit -loglevel quiet \
               -volume "$(awk -v v="$vol" 'BEGIN{printf "%d", (v*100)}')" \
               "$f" >/dev/null 2>&1 </dev/null & ;;
    mpg123)  nohup mpg123 -q -f "$(awk -v v="$vol" 'BEGIN{printf "%d", (v*32768)}')" \
               "$f" >/dev/null 2>&1 </dev/null & ;;
    mpv)     nohup mpv --no-video --really-quiet \
               --volume="$(awk -v v="$vol" 'BEGIN{printf "%d", (v*100)}')" \
               "$f" >/dev/null 2>&1 </dev/null & ;;
    cvlc)    nohup cvlc --intf dummy --play-and-exit --quiet \
               --gain "$vol" "$f" >/dev/null 2>&1 </dev/null & ;;
    aplay)   nohup aplay -q "$f" >/dev/null 2>&1 </dev/null & ;;
    powershell.exe)
             wf="$f"
             command -v wslpath >/dev/null 2>&1 && wf="$(wslpath -w "$f")"
             nohup powershell.exe -NoProfile -c \
               "(New-Object Media.SoundPlayer '$wf').PlaySync()" \
               >/dev/null 2>&1 </dev/null & ;;
  esac
  printf '%s' "$!" > "$PIDFILE" 2>/dev/null
  disown 2>/dev/null || true
  return 0
}

have_player() { pick_player "x.wav" >/dev/null 2>&1; }

player_name() {
  local w m
  w="$(pick_player "x.wav" 2>/dev/null)"
  m="$(pick_player "x.mp3" 2>/dev/null)"
  if [ -z "$w" ] && [ -z "$m" ]; then printf 'none (terminal bell)'; return 0; fi
  if [ "$w" = "$m" ] || [ -z "$m" ]; then printf '%s' "${w:-none}"
  else printf '%s (wav) / %s (mp3)' "${w:-none}" "$m"; fi
}
