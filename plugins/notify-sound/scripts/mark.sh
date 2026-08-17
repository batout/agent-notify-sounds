#!/usr/bin/env bash
# notify-sound turn-start stamp.
#   usage: mark.sh          (wired to the UserPromptSubmit hook)
# Records when this turn started so play.sh can tell a long turn you walked
# away from apart from a two-second answer you watched land. Always exits 0.

set -u
# shellcheck source=lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

trap 'exit 0' EXIT

if [ ! -t 0 ]; then NS_PAYLOAD="$(cat 2>/dev/null || true)"; fi
NS_SID="$(sanitize_sid "$(json_str session_id 2>/dev/null || true)")"

state_init
now_ms > "$(state_path start)" 2>/dev/null || true
exit 0
