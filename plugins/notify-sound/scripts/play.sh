#!/usr/bin/env bash
# notify-sound hook entrypoint.
#   usage: play.sh <done|attention|plan|subagent>
# Reads the hook JSON on stdin, decides whether this event is worth a sound,
# plays it in the background, and always exits 0 so it can never block or fail
# a turn.

set -u
# shellcheck source=lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

EVENT="${1:-done}"

finish() { exit 0; }
trap finish EXIT

# -------------------------------------------------------------- payload ---
# Read stdin fully (so Claude Code's hook writer never blocks on a full pipe)
# and keep it: session_id scopes our state, cwd picks up the project config.
if [ ! -t 0 ]; then NS_PAYLOAD="$(cat 2>/dev/null || true)"; fi
NS_SID="$(sanitize_sid "$(json_str session_id 2>/dev/null || true)")"
if [ -z "$NS_PROJECT_DIR" ]; then
  NS_PROJECT_DIR="$(json_str cwd 2>/dev/null || true)"
fi
state_init

[ "$(cfg_get debug 0)" = "1" ] && \
  printf '%s' "$NS_PAYLOAD" > "$(state_path "payload-$EVENT.json")" 2>/dev/null

# ------------------------------------------------------------- switches ---
[ "${CLAUDE_SOUND_MUTE:-0}" = "1" ] && exit 0
[ "$(cfg_get mute 0)" = "1" ] && exit 0
[ "$(cfg_get "$EVENT" 1)" = "0" ] && exit 0   # per-event on/off

# ------------------------------------------------------------- history ----
# One file per session holding "<ms> <event>" for the last cue we actually
# played. Drives both the debounce and the done-suppression below.
LASTFILE="$(state_path last)"
NOW="$(now_ms)"
LAST_MS=0; LAST_EVENT=""
if [ -r "$LASTFILE" ]; then
  read -r LAST_MS LAST_EVENT < "$LASTFILE" 2>/dev/null || true
fi
is_int "$LAST_MS" || LAST_MS=0
AGE=-1
[ "$LAST_MS" -gt 0 ] && AGE=$((NOW - LAST_MS))

remember() { printf '%s %s' "$NOW" "$EVENT" > "$LASTFILE" 2>/dev/null || true; }

# --------------------------------------------------------- done gating ----
# `done` means the agent finished the task or the answer. Stopping to wait on
# a plan or a permission is not finishing: those fired their own cue moments
# ago and Stop trips right behind them, so the second sound is noise.
if [ "$EVENT" = "done" ] && [ -n "$LAST_EVENT" ]; then
  SUPPRESS_MS="$(cfg_get done_suppress_ms 10000)"
  is_int "$SUPPRESS_MS" || SUPPRESS_MS=10000
  case " $BLOCKING_EVENTS " in
    *" $LAST_EVENT "*)
      [ "$AGE" -ge 0 ] && [ "$AGE" -lt "$SUPPRESS_MS" ] && exit 0 ;;
  esac
fi

# Short turns mean you were sitting there watching. Only `done` is gated;
# attention and plan are blocking and always ring. Missing stamp == play.
if [ "$EVENT" = "done" ]; then
  MIN_TURN_MS="$(cfg_get min_turn_ms 15000)"
  is_int "$MIN_TURN_MS" || MIN_TURN_MS=0
  if [ "$MIN_TURN_MS" -gt 0 ]; then
    START=0
    STARTFILE="$(state_path start)"
    [ -r "$STARTFILE" ] && START="$(cat "$STARTFILE" 2>/dev/null || echo 0)"
    is_int "$START" || START=0
    if [ "$START" -gt 0 ]; then
      ELAPSED=$((NOW - START))
      [ "$ELAPSED" -ge 0 ] && [ "$ELAPSED" -lt "$MIN_TURN_MS" ] && exit 0
    fi
  fi

  # Opt-in: skip `done` while the terminal running this session is frontmost.
  # lsappinfo needs no Automation permission, unlike osascript+System Events.
  if [ "$(cfg_get focus_aware 0)" = "1" ] && is_macos; then
    case "${TERM_PROGRAM:-}" in
      iTerm.app)      WANT="com.googlecode.iterm2" ;;
      Apple_Terminal) WANT="com.apple.Terminal" ;;
      vscode)         WANT="com.microsoft.VSCode" ;;
      ghostty)        WANT="com.mitchellh.ghostty" ;;
      WezTerm)        WANT="com.github.wez.wezterm" ;;
      *)              WANT="" ;;
    esac
    if [ -n "$WANT" ] && command -v lsappinfo >/dev/null 2>&1; then
      FRONT="$(lsappinfo info -only bundleID "$(lsappinfo front 2>/dev/null)" 2>/dev/null)"
      case "$FRONT" in *"$WANT"*) exit 0 ;; esac
    fi
  fi
fi

# ------------------------------------------------------------- debounce ---
# A single user action can trip more than one hook (ExitPlanMode fires both
# PreToolUse and PermissionRequest). First sound within the window wins.
WINDOW_MS="$(cfg_get debounce_ms 1800)"
is_int "$WINDOW_MS" || WINDOW_MS=1800
[ "$AGE" -ge 0 ] && [ "$AGE" -lt "$WINDOW_MS" ] && exit 0

# --------------------------------------------------------------- remote ---
# Over SSH the audio would play on the machine Claude runs on, which nobody is
# sitting next to. Ring the local terminal's bell instead.
if is_remote; then
  case "$(cfg_get remote bell)" in
    off)  exit 0 ;;
    play) : ;;
    *)    printf '\a' >/dev/tty 2>/dev/null; remember; exit 0 ;;
  esac
fi

# ---------------------------------------------------------------- play ----
FILE="$(resolve_sound "$(current_theme)" "$EVENT")" || FILE=""
[ -n "$FILE" ] || exit 0
play_file "$FILE"
remember
reap_state
exit 0
