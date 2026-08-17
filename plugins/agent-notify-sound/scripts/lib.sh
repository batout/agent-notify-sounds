#!/usr/bin/env bash
# Shared helpers for the agent-notify-sound plugin.
# Sourced by play.sh, mark.sh and soundctl.sh.

# Codex exports PLUGIN_ROOT, Claude Code exports CLAUDE_PLUGIN_ROOT, Cursor
# exports neither, so the last resort is where this file sits.
NS_ROOT="${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}"
[ -n "$NS_ROOT" ] || NS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOUNDS_DIR="$NS_ROOT/sounds"

# Which agent is calling us. Set by the --host flag the hook files pass, so one
# config and one set of scripts serve all three.
NS_HOST="${NS_HOST:-claude}"

# One config for every host. The old Claude-only path is still read so an
# upgrade from 1.x keeps your theme.
CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/notify-sound/config"
LEGACY_CONFIG_FILE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/notify-sound.conf"

EVENTS="done attention plan subagent"
# Cues that mean "Claude stopped and is waiting on you". The `done` that the
# Stop hook fires right behind one of these is not a finished turn, so it gets
# suppressed, see play.sh.
BLOCKING_EVENTS="attention plan"
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

# ----------------------------------------------------------------- state --
# Per session, so two agent windows never share a debounce stamp or kill each
# other's clip. play.sh sets NS_SID from the hook payload; the CLI stays "cli".
# The host is part of the key too, so Claude and Cursor open on the same repo
# stay out of each other's way.
STATE_DIR="${TMPDIR:-/tmp}/agent-notify-sound"
NS_SID="cli"
NS_PAYLOAD=""
NS_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-}"

state_path() { printf '%s/%s-%s.%s' "$STATE_DIR" "$NS_HOST" "$NS_SID" "$1"; }
state_init() { mkdir -p "$STATE_DIR" 2>/dev/null || true; }

# Session ids come off the wire, so they never touch a path unsanitized.
sanitize_sid() {
  local s
  s="$(printf '%s' "${1:-}" | tr -cd 'A-Za-z0-9._-' | cut -c1-64)"
  [ -n "$s" ] && printf '%s' "$s" || printf 'cli'
}

# Old sessions leave a handful of tiny files behind; sweep them in the
# background so a turn never waits on it.
reap_state() {
  [ -d "$STATE_DIR" ] || return 0
  ( find "$STATE_DIR" -type f -mtime +1 -delete >/dev/null 2>&1 & ) 2>/dev/null || true
}

now_ms() {
  if command -v perl >/dev/null 2>&1; then
    perl -MTime::HiRes=time -e 'printf "%d", time()*1000' 2>/dev/null && return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import time;print(int(time.time()*1000))' 2>/dev/null && return 0
  fi
  printf '%s000' "$(date +%s)"
}

is_int() { case "${1:-}" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }

# Pulls a string field out of the hook JSON without needing jq, same spirit as
# the config parser below. Returns empty when the key isn't there.
json_str() {
  local key="$1" p="${2:-$NS_PAYLOAD}"
  [ -n "$p" ] || return 1
  printf '%s' "$p" | tr -d '\n' \
    | sed -n 's/.*"'"$key"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1
}

# The hosts spell the same field differently: session_id in Claude and Codex,
# conversation_id in Cursor. Takes the first key that is actually there.
json_first_str() {
  local key val
  for key in "$@"; do
    val="$(json_str "$key")" || val=""
    [ -n "$val" ] && { printf '%s' "$val"; return 0; }
  done
  return 1
}

# First string in a JSON array field, for Cursor's workspace_roots.
json_arr_first() {
  local key="$1" p="${2:-$NS_PAYLOAD}"
  [ -n "$p" ] || return 1
  printf '%s' "$p" | tr -d '\n' \
    | sed -n 's/.*"'"$key"'"[[:space:]]*:[[:space:]]*\[[[:space:]]*"\([^"]*\)".*/\1/p' \
    | head -n 1
}

# ---------------------------------------------------------------- config --
# Simple key=value files so we never need jq. Project files win over the user
# file, so a repo can have its own theme and you can tell which window beeped.
# Missing files == defaults.

# The config directory each host keeps its project settings in.
host_config_dir() {
  case "${1:-$NS_HOST}" in
    cursor) printf '.cursor' ;;
    codex)  printf '.codex' ;;
    *)      printf '.claude' ;;
  esac
}

# Where `set --here` writes: the calling host's own directory.
project_config_file() {
  [ -n "$NS_PROJECT_DIR" ] || return 1
  printf '%s/%s/notify-sound.conf' "$NS_PROJECT_DIR" "$(host_config_dir)"
}

# Every project file we read, this host's first. A repo that already has a
# theme set from Claude keeps it when you open the same repo in Cursor.
project_config_files() {
  local d mine
  [ -n "$NS_PROJECT_DIR" ] || return 0
  mine="$(host_config_dir)"
  printf '%s/%s/notify-sound.conf\n' "$NS_PROJECT_DIR" "$mine"
  for d in .claude .cursor .codex; do
    [ "$d" = "$mine" ] && continue
    printf '%s/%s/notify-sound.conf\n' "$NS_PROJECT_DIR" "$d"
  done
}

cfg_read_file() {   # <file> <key>; fails when unset
  local val
  [ -f "$1" ] || return 1
  val=$(grep -E "^[[:space:]]*${2}[[:space:]]*=" "$1" 2>/dev/null \
        | tail -n 1 | cut -d= -f2- | tr -d '"'"'"' \r' | xargs 2>/dev/null)
  [ -n "$val" ] || return 1
  printf '%s' "$val"
}

cfg_get() {
  local key="$1" default="${2:-}" val f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if val="$(cfg_read_file "$f" "$key")"; then printf '%s' "$val"; return 0; fi
  done <<EOF
$(project_config_files)
EOF
  if val="$(cfg_read_file "$CONFIG_FILE" "$key")"; then
    printf '%s' "$val"; return 0
  fi
  if val="$(cfg_read_file "$LEGACY_CONFIG_FILE" "$key")"; then
    printf '%s' "$val"; return 0
  fi
  printf '%s' "$default"
}

# Which layer a value came from, shown by `soundctl.sh status`.
cfg_source() {
  local f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if cfg_read_file "$f" "$1" >/dev/null 2>&1; then printf 'project'; return 0; fi
  done <<EOF
$(project_config_files)
EOF
  if cfg_read_file "$CONFIG_FILE" "$1" >/dev/null 2>&1; then printf 'user'; return 0; fi
  if cfg_read_file "$LEGACY_CONFIG_FILE" "$1" >/dev/null 2>&1; then printf 'legacy'; return 0; fi
  printf 'default'
}

# The project file a value actually came from, or nothing.
cfg_project_hit() {
  local f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if cfg_read_file "$f" "$1" >/dev/null 2>&1; then printf '%s' "$f"; return 0; fi
  done <<EOF
$(project_config_files)
EOF
  return 1
}

cfg_set() {   # <key> <value> [project]
  local key="$1" val="$2" scope="${3:-user}" file tmp
  if [ "$scope" = "project" ]; then
    file="$(project_config_file 2>/dev/null)" || return 1
  else
    file="$CONFIG_FILE"
  fi
  mkdir -p "$(dirname "$file")" 2>/dev/null || true
  [ -f "$file" ] || printf '# notify-sound plugin settings\n' > "$file"
  tmp="$(mktemp)"
  grep -vE "^[[:space:]]*${key}[[:space:]]*=" "$file" > "$tmp" 2>/dev/null
  printf '%s=%s\n' "$key" "$val" >> "$tmp"
  mv "$tmp" "$file"
}

is_macos() { [ "$(uname -s 2>/dev/null)" = "Darwin" ]; }
is_remote() { [ -n "${SSH_TTY:-}${SSH_CONNECTION:-}" ]; }

# Git Bash, MSYS2 and Cygwin all report their own kernel name.
is_msys() {
  case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*) return 0 ;; esac
  return 1
}

# WSL is Linux, but the audio device belongs to Windows, so it plays the same
# way Git Bash does.
is_wsl() {
  [ -n "${WSL_DISTRO_NAME:-}${WSL_INTEROP:-}" ] && return 0
  grep -qi microsoft /proc/version 2>/dev/null
}

is_windows() { is_msys || is_wsl; }

# PowerShell wants a Windows path. Git Bash has cygpath, WSL has wslpath, and
# if neither is there the path was probably already fine.
win_path() {
  local p="$1" out=""
  if command -v cygpath >/dev/null 2>&1; then
    out="$(cygpath -w "$p" 2>/dev/null)"
  elif command -v wslpath >/dev/null 2>&1; then
    out="$(wslpath -w "$p" 2>/dev/null)"
  fi
  [ -n "$out" ] || out="$p"
  printf '%s' "$out" | tr -d '\r'   # these tools can hand back CRLF
}

# Where C: is mounted from inside this shell.
win_drive_c() {
  local d
  for d in /mnt/c /c /cygdrive/c; do
    [ -d "$d/Windows" ] && { printf '%s' "$d"; return 0; }
  done
  return 1
}

normalize_theme() {   # accept the old names from 0.1.x
  case "$1" in chime|morse) printf 'zaghlalah' ;; *) printf '%s' "$1" ;; esac
}

current_theme() {
  local t
  t="$(normalize_theme "${NOTIFY_SOUND_THEME:-${CLAUDE_SOUND_THEME:-$(cfg_get theme "")}}")"
  [ -n "$t" ] || t="$DEFAULT_THEME"
  case " $THEMES " in *" $t "*) ;; *) t="$DEFAULT_THEME" ;; esac
  printf '%s' "$t"
}

current_volume() { cfg_get volume "0.7"; }

# ------------------------------------------------------------ resolution --
# Built-in OS sounds used by the "system" theme.
system_sound_for() {
  local event="$1" f c
  if is_macos; then
    case "$event" in
      done)      f='/System/Library/Sounds/Glass.aiff' ;;
      attention) f='/System/Library/Sounds/Submarine.aiff' ;;
      plan)      f='/System/Library/Sounds/Hero.aiff' ;;
      subagent)  f='/System/Library/Sounds/Pop.aiff' ;;
    esac
  elif is_windows; then
    c="$(win_drive_c)" || c=""
    [ -n "$c" ] || return 0
    case "$event" in   # shipped with every Windows since XP
      done)      f="$c/Windows/Media/chimes.wav" ;;
      attention) f="$c/Windows/Media/notify.wav" ;;
      plan)      f="$c/Windows/Media/chord.wav" ;;
      subagent)  f="$c/Windows/Media/ding.wav" ;;
    esac
  else
    case "$event" in   # freedesktop, present on most Linux desktops
      done)      f='/usr/share/sounds/freedesktop/stereo/complete.oga' ;;
      attention) f='/usr/share/sounds/freedesktop/stereo/message.oga' ;;
      plan)      f='/usr/share/sounds/freedesktop/stereo/dialog-information.oga' ;;
      subagent)  f='/usr/share/sounds/freedesktop/stereo/bell.oga' ;;
    esac
  fi
  [ -n "${f:-}" ] && printf '%s' "$f"
}

# A theme may ship only the three original cues. Anything newer falls back to
# a cue every theme has, so no theme ever needs updating to keep working.
cue_fallback() {
  case "$1" in subagent) printf 'done' ;; *) printf '' ;; esac
}

theme_file() {   # <theme> <event>; exact file only, no fallback
  local theme="$1" event="$2" f ext
  for ext in wav mp3 m4a aiff ogg flac; do
    f="$SOUNDS_DIR/$theme/$event.$ext"
    [ -r "$f" ] && { printf '%s' "$f"; return 0; }
  done
  return 1
}

# Echoes the absolute path of the file to play for <theme> <event>.
resolve_sound() {
  local theme event f alt
  theme="$(normalize_theme "$1")"; event="$2"
  if [ "$theme" = "system" ]; then
    f="$(system_sound_for "$event")"
    if [ -n "$f" ] && [ -r "$f" ]; then printf '%s' "$f"; return 0; fi
    theme="$DEFAULT_THEME"   # fall back to the bundled set
  fi
  theme_file "$theme" "$event" && return 0
  alt="$(cue_fallback "$event")"
  [ -n "$alt" ] && theme_file "$theme" "$alt" && return 0
  return 1
}

# ---------------------------------------------------------------- player --
# Echoes the best available player for a given file, or nothing.
pick_player() {
  local ext order p
  ext="$(printf '%s' "${1##*.}" | tr '[:upper:]' '[:lower:]')"
  if is_windows; then
    # Windows Media Player plays wav and mp3 and takes a volume, so it comes
    # first for every format. WSL is included: the sound card is Windows'.
    order="pwsh.exe powershell.exe pwsh powershell ffplay mpv mpg123"
  else
    case "$ext" in
      wav|aiff|aif) order="afplay paplay aplay ffplay mpg123" ;;
      *)            order="afplay ffplay mpg123 mpv cvlc" ;;   # compressed formats
    esac
  fi
  for p in $order; do
    command -v "$p" >/dev/null 2>&1 && { printf '%s' "$p"; return 0; }
  done
  return 1
}

# The PowerShell one-liner behind Windows playback. MediaPlayer handles both
# wav and mp3 and honours a volume, and it needs the process to stay alive for
# the length of the clip, which is fine: we are already in the background and
# the pid file lets the next cue kill it. If the WPF assembly is missing, and
# it can be under PowerShell 7 without the desktop runtime, SoundPlayer takes
# over for wav.
ps_play_command() {   # <windows path> <volume>
  local wf vol
  wf="$(printf '%s' "$1" | sed "s/'/''/g")"
  vol="$2"
  printf '%s' "\$ErrorActionPreference='SilentlyContinue';\
try{Add-Type -AssemblyName presentationCore -EA Stop;\
\$p=New-Object System.Windows.Media.MediaPlayer;\
\$p.Volume=$vol;\$p.Open([uri]'$wf');\
\$d=(Get-Date).AddSeconds(2);\
while(-not \$p.NaturalDuration.HasTimeSpan -and (Get-Date) -lt \$d){Start-Sleep -Milliseconds 20};\
\$p.Play();\
if(\$p.NaturalDuration.HasTimeSpan){Start-Sleep -Milliseconds ([int]\$p.NaturalDuration.TimeSpan.TotalMilliseconds+250)}else{Start-Sleep -Seconds 2};\
\$p.Stop();\$p.Close()}\
catch{(New-Object Media.SoundPlayer '$wf').PlaySync()}"
}

kill_pidfile() {
  local pf="$1" pid
  [ -f "$pf" ] || return 0
  pid="$(cat "$pf" 2>/dev/null)"
  case "$pid" in ''|*[!0-9]*) rm -f "$pf" 2>/dev/null; return 0 ;; esac
  kill "$pid" 2>/dev/null
  rm -f "$pf" 2>/dev/null
  return 0
}

# Stops what this session is playing (clips can run several seconds).
# --all stops every session's, which is what the CLI wants.
stop_playing() {
  local f
  if [ "${1:-}" = "--all" ]; then
    [ -d "$STATE_DIR" ] || return 0
    for f in "$STATE_DIR"/*.pid; do [ -f "$f" ] || continue; kill_pidfile "$f"; done
    return 0
  fi
  kill_pidfile "$(state_path pid)"
}

# Plays a file. Returns immediately; audio finishes in the background.
play_file() {
  local f="$1" vol="${2:-$(current_volume)}" p pv wf
  [ -n "$f" ] && [ -r "$f" ] || return 0
  p="$(pick_player "$f")" || { printf '\a' >/dev/tty 2>/dev/null; return 0; }

  stop_playing
  state_init

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
    pwsh.exe|powershell.exe|pwsh|powershell)
             wf="$(win_path "$f")"
             nohup "$p" -NoProfile -NonInteractive -Command \
               "$(ps_play_command "$wf" "$vol")" \
               >/dev/null 2>&1 </dev/null & ;;
  esac
  printf '%s' "$!" > "$(state_path pid)" 2>/dev/null
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
