#!/usr/bin/env bash
# notify-sound hook entrypoint.
#   usage: play.sh <done|attention|plan>
# Reads (and ignores) the hook JSON on stdin, plays the right sound in the
# background, and always exits 0 so it can never block or fail a turn.

set -u
# shellcheck source=lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

EVENT="${1:-done}"

# Drain stdin so Claude Code's hook writer never blocks on a full pipe.
if [ ! -t 0 ]; then cat >/dev/null 2>&1 || true; fi

finish() { exit 0; }
trap finish EXIT

# ------------------------------------------------------------- switches ---
[ "${CLAUDE_SOUND_MUTE:-0}" = "1" ] && exit 0
[ "$(cfg_get mute 0)" = "1" ] && exit 0
[ "$(cfg_get "$EVENT" 1)" = "0" ] && exit 0   # per-event on/off

# ------------------------------------------------------------- debounce ---
# A single user action can trip more than one hook (e.g. ExitPlanMode fires
# both PreToolUse and PermissionRequest). First sound within the window wins.
WINDOW_MS="$(cfg_get debounce_ms 1800)"
STAMP="${TMPDIR:-/tmp}/.claude-notify-sound.stamp"

now_ms() {
  if command -v perl >/dev/null 2>&1; then
    perl -MTime::HiRes=time -e 'printf "%d", time()*1000' 2>/dev/null && return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import time;print(int(time.time()*1000))' 2>/dev/null && return 0
  fi
  printf '%s000' "$(date +%s)"
}

NOW="$(now_ms)"
LAST=0
[ -f "$STAMP" ] && LAST="$(cat "$STAMP" 2>/dev/null || echo 0)"
case "$LAST" in ''|*[!0-9]*) LAST=0 ;; esac

if [ "$LAST" -gt 0 ] && [ $((NOW - LAST)) -lt "$WINDOW_MS" ] && [ $((NOW - LAST)) -ge 0 ]; then
  exit 0
fi
printf '%s' "$NOW" > "$STAMP" 2>/dev/null || true

# ---------------------------------------------------------------- play ----
FILE="$(resolve_sound "$(current_theme)" "$EVENT")"
play_file "$FILE"
exit 0
