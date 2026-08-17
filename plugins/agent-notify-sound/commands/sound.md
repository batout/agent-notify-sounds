---
description: Choose, preview, or mute the agent notification sounds
argument-hint: "[list | preview <theme> | set <theme> | mute | unmute | volume <0-1> | min-turn <sec> | focus on|off | status]"
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/soundctl.sh:*)
---

The user wants to manage the agent-notify-sound plugin. The control script is:

`${CLAUDE_PLUGIN_ROOT}/scripts/soundctl.sh`

User arguments: `$ARGUMENTS`

Do this:

1. If arguments were given, map them to a subcommand and run it directly:
   - `list` / `themes` → `soundctl.sh list`
   - `sounds` / `files` / `all` → `soundctl.sh sounds [theme]` (the full sound inventory)
   - `preview` / `preview <theme>` → `soundctl.sh preview [theme]`
   - `set <theme>` / just a bare theme name → `soundctl.sh set <theme>`
   - `set --here <theme>` / "this project only" → `soundctl.sh set --here <theme>`
   - `mute` / `unmute` / `status` / `volume <n>` → the matching subcommand
   - `off <event>` / `on <event>` where event is `done`, `attention`, `plan`, or `subagent`
   - `min-turn <seconds>` → `soundctl.sh min-turn <seconds>` (0 = ring on every turn)
   - `focus on` / `focus off` → `soundctl.sh focus on|off`
   - "too noisy" / "fires too often" → raise `min-turn` rather than turning `done` off
   - `stop` → `soundctl.sh stop` (silences a clip that is playing right now)

2. If no arguments were given, run `soundctl.sh status` and `soundctl.sh list`,
   then ask the user which theme they want using the AskUserQuestion tool with
   these options (mention that you can play each one first if they'd like):
   - **zaghlalah** (default), short radio beeps spelling DO / NE / PL in morse
   - **jersey**, an overdriven bass riff with a little swagger
   - **marimba**, warm wooden mallets, soft and short
   - **system**, the OS built-ins: Glass / Submarine / Hero on macOS, freedesktop on Linux

   Run `soundctl.sh list` first. Themes are drop-in directories, so the user
   may have added their own beyond these four.

   Then apply their choice with `soundctl.sh set <theme>`.

3. Report the result in one short line. Do not paste the raw script output
   unless the user asked for `status` or `sounds`. Those two are tables meant to
   be shown verbatim in a code block.

Reference, the cues in every theme:

| Cue | Plays when |
|-----|-----------|
| `done` | The agent finished the task or the answer |
| `attention` | The agent is waiting on you: a question or a tool permission |
| `plan` | A plan is on screen waiting for your approval |
| `subagent` | A background agent finished (falls back to `done` if the theme has no file) |

`done` deliberately stays quiet in two cases: for 10 s after a `plan` or
`attention` cue, because stopping to ask you something is not finishing, and on
turns shorter than `min_turn_ms` (15 s by default), where you were clearly still
watching.

Which cues you get depends on the agent. Claude Code fires all four. Codex has
no notification event, so `attention` rides on its permission requests instead.
Cursor has neither, so it gets `done` and `subagent`, plus an optional
`attention` before every shell or MCP call that ships turned off
(`soundctl.sh cursor-attention on`).

Settings live in `~/.config/notify-sound/config`, overridable per project in
`<project>/.claude/notify-sound.conf` (or `.cursor/`, or `.codex/`), and take
effect immediately with no restart.
