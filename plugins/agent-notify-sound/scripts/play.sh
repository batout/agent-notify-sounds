#!/usr/bin/env bash
# agent-notify-sound hook entrypoint.
#   usage: play.sh [--host claude|cursor|codex] <done|attention|plan|subagent>
#          play.sh --payload-arg '<json>'     (Codex's legacy notify key)
# Reads the hook JSON on stdin, decides whether this event is worth a sound,
# plays it in the background, and always exits 0 so it can never block or fail
# a turn. Nothing is ever written to stdout: Cursor reads a before* hook's
# stdout as a permission decision.

set -u
# shellcheck source=lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

finish() { exit 0; }
trap finish EXIT

# ----------------------------------------------------------- arguments ---
EVENT=""
ARGV_PAYLOAD=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --host)        NS_HOST="$(printf '%s' "${2:-claude}" | tr -cd 'a-z-')"; shift 2 || break ;;
    --payload-arg) NS_HOST="codex"; ARGV_PAYLOAD="${2:-}"; shift 2 || break ;;
    --)            shift; break ;;
    *)             EVENT="$1"; shift ;;
  esac
done
[ -n "$NS_HOST" ] || NS_HOST="claude"

# -------------------------------------------------------------- payload ---
# Read stdin fully (so the host's hook writer never blocks on a full pipe) and
# keep it: the session id scopes our state, the working directory picks up the
# project config. Codex's legacy notify hook hands us the JSON on argv instead,
# with no stdin at all.
if [ -n "$ARGV_PAYLOAD" ]; then
  NS_PAYLOAD="$ARGV_PAYLOAD"
elif [ ! -t 0 ]; then
  NS_PAYLOAD="$(cat 2>/dev/null || true)"
fi

# One event type exists on the notify key, and it means the turn ended.
if [ -n "$ARGV_PAYLOAD" ] && [ -z "$EVENT" ]; then
  case "$(json_str type 2>/dev/null || true)" in
    agent-turn-complete|'') EVENT="done" ;;
    *) exit 0 ;;
  esac
fi
[ -n "$EVENT" ] || EVENT="done"

NS_SID="$(sanitize_sid "$(json_first_str session_id conversation_id 2>/dev/null || true)")"
if [ -z "$NS_PROJECT_DIR" ]; then
  NS_PROJECT_DIR="$(json_str cwd 2>/dev/null || true)"
fi
if [ -z "$NS_PROJECT_DIR" ]; then
  NS_PROJECT_DIR="$(json_arr_first workspace_roots 2>/dev/null || true)"
fi
state_init

# --------------------------------------------------------- host quirks ---
# Cursor has no notification event. The nearest thing is the hook that runs
# before a shell or MCP call, which fires whether or not you are actually asked
# for permission, so it stays off unless you turn it on.
if [ "$NS_HOST" = "cursor" ] && [ "$EVENT" = "attention" ]; then
  [ "$(cfg_get cursor_attention 0)" = "1" ] || exit 0
fi

# Cursor's stop hook also fires when a turn is cancelled or errors out. You
# know about those already; only a completed turn is worth a sound.
if [ "$NS_HOST" = "cursor" ] && [ "$EVENT" = "done" ]; then
  case "$(json_str status 2>/dev/null || true)" in
    completed|'') ;;
    *) exit 0 ;;
  esac
fi

[ "$(cfg_get debug 0)" = "1" ] && \
  printf '%s' "$NS_PAYLOAD" > "$(state_path "payload-$EVENT.json")" 2>/dev/null

# ------------------------------------------------------------- switches ---
[ "${NOTIFY_SOUND_MUTE:-${CLAUDE_SOUND_MUTE:-0}}" = "1" ] && exit 0
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
# ago and the stop event trips right behind them, so the second sound is noise.
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
