#!/usr/bin/env bash
# agent-notify-sound test suite. Runs on macOS, Linux and Windows (Git Bash or
# WSL), and needs no audio device: every assertion is about which cue the
# scripts decide to play, not about hearing it.
#
#   tests/run-tests.sh
#
# Exits non-zero on the first failing group's total, and prints a summary.

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/.." && pwd)/plugins/agent-notify-sound"
SCRIPTS="$PLUGIN/scripts"

PASS=0
FAIL=0

ok()   { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2:-}"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$3], got [$2]"; fi; }

# A clean HOME, config and state directory per case, so nothing leaks between
# assertions or into the machine running the tests.
SANDBOX="$(mktemp -d 2>/dev/null || mktemp -d -t ansound)"
trap 'rm -rf "$SANDBOX"' EXIT

fresh_env() {
  rm -rf "$SANDBOX/home"
  mkdir -p "$SANDBOX/home/.config/notify-sound" "$SANDBOX/home/tmp"
  export HOME="$SANDBOX/home"
  export XDG_CONFIG_HOME="$SANDBOX/home/.config"
  export TMPDIR="$SANDBOX/home/tmp"
  export CLAUDE_PROJECT_DIR=""
  unset NOTIFY_SOUND_THEME NOTIFY_SOUND_MUTE CLAUDE_SOUND_THEME CLAUDE_SOUND_MUTE
  # volume 0 keeps a CI machine with speakers quiet; min_turn 0 takes the
  # "short turn" rule out of the way of the cue assertions.
  printf 'volume=0\nmin_turn_ms=0\n' > "$XDG_CONFIG_HOME/notify-sound/config"
  STATE="$TMPDIR/agent-notify-sound"
}

# Runs play.sh and answers whether it decided to play something.
played() {   # <state key> ; e.g. claude-abc
  [ -f "$STATE/$1.last" ] && printf 'yes' || printf 'no'
}

say() { printf '\n== %s\n' "$1"; }

# --------------------------------------------------------------- platform --
say "platform"
. "$SCRIPTS/lib.sh"
UNAME="$(uname -s 2>/dev/null)"
printf '   uname=%s player=%s\n' "$UNAME" "$(player_name)"

case "$UNAME" in
  Darwin)                 EXPECT_WIN=no ;;
  MINGW*|MSYS*|CYGWIN*)   EXPECT_WIN=yes ;;
  *) if grep -qi microsoft /proc/version 2>/dev/null; then EXPECT_WIN=yes; else EXPECT_WIN=no; fi ;;
esac
check "detects the platform" "$(is_windows && printf yes || printf no)" "$EXPECT_WIN"

if [ "$EXPECT_WIN" = "yes" ]; then
  WP="$(win_path "$SCRIPTS/play.sh")"
  case "$WP" in
    *:*|*\\*) ok "win_path returns a Windows path ($WP)" ;;
    *)        bad "win_path returns a Windows path" "got [$WP]" ;;
  esac
  case "$WP" in *$'\r'*) bad "win_path strips CR" "got a CR" ;; *) ok "win_path strips CR" ;; esac

  case "$(pick_player x.wav)" in
    pwsh*|powershell*) ok "picks PowerShell for wav" ;;
    *) bad "picks PowerShell for wav" "got [$(pick_player x.wav)]" ;;
  esac
  case "$(pick_player x.mp3)" in
    pwsh*|powershell*) ok "picks PowerShell for mp3" ;;
    *) bad "picks PowerShell for mp3" "got [$(pick_player x.mp3)]" ;;
  esac

  SYS="$(system_sound_for done)"
  if [ -n "$SYS" ] && [ -r "$SYS" ]; then
    ok "system theme resolves on Windows ($SYS)"
  else
    bad "system theme resolves on Windows" "got [$SYS]"
  fi

  # The one-liner has to survive PowerShell's parser and exit clean, with or
  # without an audio device on the machine.
  PS="$(pick_player x.wav)"
  CMD="$(ps_play_command "$(win_path "$PLUGIN/sounds/zaghlalah/done.wav")" 0)"
  if "$PS" -NoProfile -NonInteractive -Command "$CMD" >/dev/null 2>&1; then
    ok "the PowerShell player runs and exits 0"
  else
    bad "the PowerShell player runs and exits 0" "exit $?"
  fi
else
  check "does not pick PowerShell off Windows" \
    "$(pick_player x.wav | grep -c 'powershell\|pwsh' || true)" "0"
fi

# ------------------------------------------------------------------- cues --
say "cue decisions"
fresh_env
echo '{"session_id":"c1","cwd":"/tmp"}' | bash "$SCRIPTS/play.sh" --host claude done
check "claude: a finished turn rings" "$(played claude-c1)" "yes"

echo '{"conversation_id":"u1","status":"completed"}' | bash "$SCRIPTS/play.sh" --host cursor done
check "cursor: a completed turn rings" "$(played cursor-u1)" "yes"

echo '{"conversation_id":"u2","status":"aborted"}' | bash "$SCRIPTS/play.sh" --host cursor done
check "cursor: an aborted turn stays quiet" "$(played cursor-u2)" "no"

echo '{"conversation_id":"u3","status":"error"}' | bash "$SCRIPTS/play.sh" --host cursor done
check "cursor: an errored turn stays quiet" "$(played cursor-u3)" "no"

echo '{"conversation_id":"u4"}' | bash "$SCRIPTS/play.sh" --host cursor attention
check "cursor: attention is off by default" "$(played cursor-u4)" "no"

printf 'cursor_attention=1\n' >> "$XDG_CONFIG_HOME/notify-sound/config"
echo '{"conversation_id":"u5"}' | bash "$SCRIPTS/play.sh" --host cursor attention
check "cursor: attention rings once enabled" "$(played cursor-u5)" "yes"

echo '{"session_id":"x1"}' | bash "$SCRIPTS/play.sh" --host codex attention
check "codex: a permission request rings" "$(played codex-x1)" "yes"

bash "$SCRIPTS/notify-codex.sh" '{"type":"agent-turn-complete"}'
check "codex: the legacy notify key rings" "$(played codex-cli)" "yes"

fresh_env   # so the assertion below cannot pass on the previous cue's file
bash "$SCRIPTS/play.sh" --payload-arg '{"type":"something-else"}'
check "codex: an unknown notify event stays quiet" "$(played codex-cli)" "no"

# ------------------------------------------------------------ suppression --
say "done suppression"
fresh_env
echo '{"session_id":"s1"}' | bash "$SCRIPTS/play.sh" --host claude plan
echo '{"session_id":"s1"}' | bash "$SCRIPTS/play.sh" --host claude done
LAST="$(cat "$STATE/claude-s1.last" 2>/dev/null | cut -d' ' -f2)"
check "the done behind a plan is dropped" "$LAST" "plan"

fresh_env
printf 'min_turn_ms=600000\n' >> "$XDG_CONFIG_HOME/notify-sound/config"
echo '{"session_id":"s2"}' | bash "$SCRIPTS/mark.sh" --host claude
echo '{"session_id":"s2"}' | bash "$SCRIPTS/play.sh" --host claude done
check "a short turn stays quiet" "$(played claude-s2)" "no"

fresh_env
printf 'mute=1\n' >> "$XDG_CONFIG_HOME/notify-sound/config"
echo '{"session_id":"s3"}' | bash "$SCRIPTS/play.sh" --host claude done
check "mute silences everything" "$(played claude-s3)" "no"

# --------------------------------------------------------------- sessions --
say "session and host keys"
fresh_env
echo '{"session_id":"same"}' | bash "$SCRIPTS/play.sh" --host claude done
echo '{"conversation_id":"same"}' | bash "$SCRIPTS/play.sh" --host cursor subagent
check "claude and cursor keep separate state" \
  "$([ -f "$STATE/claude-same.last" ] && [ -f "$STATE/cursor-same.last" ] && printf yes || printf no)" "yes"

# ----------------------------------------------------------------- stdout --
say "silence on stdout"
fresh_env
OUT="$(echo '{"conversation_id":"o1"}' | bash "$SCRIPTS/play.sh" --host cursor attention 2>/dev/null)"
check "cursor attention prints nothing" "${#OUT}" "0"
OUT="$(echo '{"session_id":"o2"}' | bash "$SCRIPTS/play.sh" --host claude done 2>/dev/null)"
check "claude done prints nothing" "${#OUT}" "0"
OUT="$(echo '{"session_id":"o3"}' | bash "$SCRIPTS/mark.sh" --host claude 2>/dev/null)"
check "mark prints nothing" "${#OUT}" "0"

# ----------------------------------------------------------------- config --
say "config layers"
fresh_env
mkdir -p "$SANDBOX/proj/.claude" "$SANDBOX/proj/.cursor" "$HOME/.claude"
printf 'theme=marimba\n' > "$HOME/.claude/notify-sound.conf"
check "the 1.x config is still read" \
  "$(cd "$SANDBOX" && CLAUDE_PROJECT_DIR="$SANDBOX/proj" bash "$SCRIPTS/soundctl.sh" status | awk '/theme /{print $3, $4}')" \
  "marimba (legacy)"

printf 'theme=jersey\n' > "$XDG_CONFIG_HOME/notify-sound/config"
check "the user config wins over 1.x" \
  "$(CLAUDE_PROJECT_DIR="$SANDBOX/proj" bash "$SCRIPTS/soundctl.sh" status | awk '/theme /{print $3, $4}')" \
  "jersey (user)"

printf 'theme=zaghlalah\n' > "$SANDBOX/proj/.cursor/notify-sound.conf"
check "a project file wins over both" \
  "$(CLAUDE_PROJECT_DIR="$SANDBOX/proj" bash "$SCRIPTS/soundctl.sh" --host cursor status | awk '/theme /{print $3, $4}')" \
  "zaghlalah (project)"

check "one agent reads another's project file" \
  "$(CLAUDE_PROJECT_DIR="$SANDBOX/proj" bash "$SCRIPTS/soundctl.sh" --host codex status | awk '/theme /{print $3, $4}')" \
  "zaghlalah (project)"

# ---------------------------------------------------------------- themes ---
say "themes"
fresh_env
for t in zaghlalah jersey marimba; do
  for e in done attention plan subagent; do
    f="$(resolve_sound "$t" "$e" || true)"
    if [ -n "$f" ] && [ -r "$f" ]; then ok "$t/$e resolves"; else bad "$t/$e resolves" "got [$f]"; fi
  done
done
f="$(resolve_sound system done || true)"
if [ -n "$f" ] && [ -r "$f" ]; then ok "system/done resolves or falls back"; else bad "system/done resolves or falls back" "got [$f]"; fi

# --------------------------------------------------------------- summary ---
printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
