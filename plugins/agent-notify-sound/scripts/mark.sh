#!/usr/bin/env bash
# agent-notify-sound turn-start stamp.
#   usage: mark.sh [--host claude|cursor|codex]
#          (wired to UserPromptSubmit, or beforeSubmitPrompt in Cursor)
# Records when this turn started so play.sh can tell a long turn you walked
# away from apart from a two-second answer you watched land. Always exits 0.

set -u
# shellcheck source=lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

trap 'exit 0' EXIT

while [ "$#" -gt 0 ]; do
  case "$1" in
    --host) NS_HOST="$(printf '%s' "${2:-claude}" | tr -cd 'a-z-')"; shift 2 || break ;;
    *)      shift ;;
  esac
done
[ -n "$NS_HOST" ] || NS_HOST="claude"

if [ ! -t 0 ]; then NS_PAYLOAD="$(cat 2>/dev/null || true)"; fi
NS_SID="$(sanitize_sid "$(json_first_str session_id conversation_id 2>/dev/null || true)")"

state_init
now_ms > "$(state_path start)" 2>/dev/null || true
exit 0
