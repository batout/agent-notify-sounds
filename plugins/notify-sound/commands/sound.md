---
description: Choose, preview, or mute the Claude Code notification sounds
argument-hint: "[list | preview <theme> | set <theme> | mute | unmute | volume <0-1> | status]"
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/soundctl.sh:*)
---

The user wants to manage the notify-sound plugin. The control script is:

`${CLAUDE_PLUGIN_ROOT}/scripts/soundctl.sh`

User arguments: `$ARGUMENTS`

Do this:

1. If arguments were given, map them to a subcommand and run it directly:
   - `list` / `themes` → `soundctl.sh list`
   - `sounds` / `files` / `all` → `soundctl.sh sounds [theme]` (the full sound inventory)
   - `preview` / `preview <theme>` → `soundctl.sh preview [theme]`
   - `set <theme>` / just a bare theme name → `soundctl.sh set <theme>`
   - `mute` / `unmute` / `status` / `volume <n>` → the matching subcommand
   - `off <event>` / `on <event>` where event is `done`, `attention`, or `plan`
   - `stop` → `soundctl.sh stop` (silences a clip that is playing right now)

2. If no arguments were given, run `soundctl.sh status` and `soundctl.sh list`,
   then ask the user which theme they want using the AskUserQuestion tool with
   these options (mention that you can play each one first if they'd like):
   - **zaghlalah** (default) — short radio beeps spelling DO / NE / PL in morse
   - **jersey** — overdriven bass riff with a little swagger
   - **marimba** — warm wooden mallets, soft and short
   - **system** — macOS built-ins: Glass, Submarine, Hero

   Run `soundctl.sh list` first — themes are drop-in directories, so the user
   may have added their own beyond these four.

   Then apply their choice with `soundctl.sh set <theme>`.

3. Report the result in one short line. Do not paste the raw script output
   unless the user asked for `status` or `sounds` — those two are tables meant to
   be shown verbatim in a code block.

Reference — the three cues in every theme:

| Cue | Plays when |
|-----|-----------|
| `done` | Claude finished the turn / the work is complete |
| `attention` | Claude is waiting on you — a question or a tool permission |
| `plan` | A plan is on screen waiting for your approval |

Settings live in `~/.claude/notify-sound.conf` and take effect immediately —
no restart needed.
