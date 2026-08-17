#!/usr/bin/env bash
# agent-notify-sound manual installer.
#
#   ./install.sh cursor              wire the hooks into ~/.cursor/hooks.json
#   ./install.sh codex               wire the hooks into ~/.codex/config.toml
#   ./install.sh --uninstall cursor  take them out again
#   ./install.sh --uninstall codex
#
# Use this if your build has no plugin support, or you would rather not install
# a plugin. It writes absolute paths to this checkout, so moving or deleting
# the directory afterwards breaks the hooks. Installing the plugin instead is
# the maintained path; see the README.
#
# Every existing file is backed up next to itself before it is touched.

set -eu

ROOT="$(cd "$(dirname "$0")" && pwd)"
PLUGIN="$ROOT/plugins/agent-notify-sound"
MARK="$PLUGIN/scripts/mark.sh"
PLAY="$PLUGIN/scripts/play.sh"
MARKER_OPEN="# >>> agent-notify-sound >>>"
MARKER_CLOSE="# <<< agent-notify-sound <<<"

UNINSTALL=0
TARGET=""
for a in "$@"; do
  case "$a" in
    --uninstall|-u) UNINSTALL=1 ;;
    cursor|codex)   TARGET="$a" ;;
    -h|--help|'')   TARGET="" ;;
    *) echo "unknown argument: $a" >&2; exit 2 ;;
  esac
done

usage() {
  awk 'NR>1{ if (/^#/) { sub(/^# ?/,""); print } else exit }' "$0"
  exit "${1:-0}"
}
[ -n "$TARGET" ] || usage 1

[ -x "$PLAY" ] || chmod +x "$PLAY" "$MARK" 2>/dev/null || true

backup() {
  [ -f "$1" ] || return 0
  cp "$1" "$1.bak.$(date +%Y%m%d%H%M%S)"
  echo "  backed up $1"
}

need_python() {
  command -v python3 >/dev/null 2>&1 && return 0
  echo "python3 is needed to edit JSON safely. Paste examples/cursor-hooks.json" >&2
  echo "into ~/.cursor/hooks.json by hand instead." >&2
  exit 1
}

# ------------------------------------------------------------------ cursor --
cursor_file="$HOME/.cursor/hooks.json"

cursor_install() {
  need_python
  mkdir -p "$(dirname "$cursor_file")"
  backup "$cursor_file"
  MARK="$MARK" PLAY="$PLAY" FILE="$cursor_file" python3 - <<'PY'
import json, os

path, mark, play = os.environ["FILE"], os.environ["MARK"], os.environ["PLAY"]
wanted = {
    "beforeSubmitPrompt": f'"{mark}" --host cursor',
    "stop":               f'"{play}" --host cursor done',
    "subagentStop":       f'"{play}" --host cursor subagent',
    "beforeShellExecution": f'"{play}" --host cursor attention',
    "beforeMCPExecution":   f'"{play}" --host cursor attention',
}

cfg = {}
if os.path.exists(path):
    with open(path) as fh:
        text = fh.read().strip()
    if text:
        cfg = json.loads(text)

cfg.setdefault("version", 1)
hooks = cfg.setdefault("hooks", {})
added = 0
for event, command in wanted.items():
    entries = hooks.setdefault(event, [])
    if any(e.get("command") == command for e in entries if isinstance(e, dict)):
        continue
    entries.append({"command": command})
    added += 1

with open(path, "w") as fh:
    json.dump(cfg, fh, indent=2)
    fh.write("\n")
print(f"  wrote {added} hook(s) into {path}")
PY
  echo "Restart Cursor, then finish a turn to hear it."
  echo "The attention cue stays silent until you run:"
  echo "  $PLUGIN/scripts/soundctl.sh cursor-attention on"
}

cursor_uninstall() {
  need_python
  [ -f "$cursor_file" ] || { echo "nothing to remove: $cursor_file"; return 0; }
  backup "$cursor_file"
  PLUGIN="$PLUGIN" FILE="$cursor_file" python3 - <<'PY'
import json, os

path, plugin = os.environ["FILE"], os.environ["PLUGIN"]
with open(path) as fh:
    cfg = json.load(fh)

removed = 0
for event, entries in list(cfg.get("hooks", {}).items()):
    keep = [e for e in entries
            if not (isinstance(e, dict) and plugin in str(e.get("command", "")))]
    removed += len(entries) - len(keep)
    if keep:
        cfg["hooks"][event] = keep
    else:
        del cfg["hooks"][event]

with open(path, "w") as fh:
    json.dump(cfg, fh, indent=2)
    fh.write("\n")
print(f"  removed {removed} hook(s) from {path}")
PY
}

# ------------------------------------------------------------------- codex --
codex_file="$HOME/.codex/config.toml"

codex_install() {
  mkdir -p "$(dirname "$codex_file")"
  if [ -f "$codex_file" ] && grep -qF "$MARKER_OPEN" "$codex_file"; then
    echo "already installed in $codex_file, run --uninstall first to refresh"
    return 0
  fi
  backup "$codex_file"
  {
    printf '\n%s\n' "$MARKER_OPEN"
    codex_block
    printf '%s\n' "$MARKER_CLOSE"
  } >> "$codex_file"
  echo "  appended the hook tables to $codex_file"
  echo "TOML puts plain keys before tables, so if you add a top level setting"
  echo "later, put it above this block."
}

codex_block() {
  cat <<TOML
[[hooks.UserPromptSubmit]]
[[hooks.UserPromptSubmit.hooks]]
type = "command"
command = '"$MARK" --host codex'
timeout = 5

[[hooks.Stop]]
[[hooks.Stop.hooks]]
type = "command"
command = '"$PLAY" --host codex done'
timeout = 5

[[hooks.SubagentStop]]
[[hooks.SubagentStop.hooks]]
type = "command"
command = '"$PLAY" --host codex subagent'
timeout = 5

[[hooks.PermissionRequest]]
[[hooks.PermissionRequest.hooks]]
type = "command"
command = '"$PLAY" --host codex attention'
timeout = 5

[[hooks.PreToolUse]]
matcher = "ExitPlanMode"
[[hooks.PreToolUse.hooks]]
type = "command"
command = '"$PLAY" --host codex plan'
timeout = 5
TOML
}

codex_uninstall() {
  [ -f "$codex_file" ] || { echo "nothing to remove: $codex_file"; return 0; }
  grep -qF "$MARKER_OPEN" "$codex_file" || { echo "no block of ours in $codex_file"; return 0; }
  backup "$codex_file"
  tmp="$(mktemp)"
  # `close` is an awk builtin, so the markers travel under other names.
  awk -v marker_open="$MARKER_OPEN" -v marker_close="$MARKER_CLOSE" '
    $0 == marker_open { skip = 1; next }
    $0 == marker_close { skip = 0; next }
    !skip { print }
  ' "$codex_file" > "$tmp"
  mv "$tmp" "$codex_file"
  echo "  removed our block from $codex_file"
}

# --------------------------------------------------------------------- run --
case "$TARGET:$UNINSTALL" in
  cursor:0) cursor_install ;;
  cursor:1) cursor_uninstall ;;
  codex:0)  codex_install ;;
  codex:1)  codex_uninstall ;;
esac
