#!/usr/bin/env bash
# Entrypoint for Codex's older `notify` key, which has no hooks behind it.
#
#   notify = ["bash", "/path/to/scripts/notify-codex.sh"]
#
# Codex appends the event JSON as the last argument and gives the process no
# stdin, so hand that argument to play.sh. One event exists on this path,
# agent-turn-complete, which means the turn ended.

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PAYLOAD=""
[ "$#" -gt 0 ] && PAYLOAD="${!#}"

exec "$DIR/play.sh" --payload-arg "$PAYLOAD"
