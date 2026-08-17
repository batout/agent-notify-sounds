---
name: sound
description: Choose, preview, mute or tune the agent-notify-sound notification sounds. Use when the user says "change the sound", "mute the sounds", "which theme is on", "sound is too noisy", "preview the themes", or runs /sound.
---

# Managing the notification sounds

Everything runs through one script:

`$PLUGIN_ROOT/scripts/soundctl.sh --host codex <subcommand>`

If `$PLUGIN_ROOT` is not set, the script also works from its own directory.

## Subcommands

| Ask | Command |
|-----|---------|
| what is active | `status` |
| which themes exist | `list` |
| every sound file, with length and size | `sounds [theme]` |
| hear a theme | `preview [theme]` |
| switch theme | `set <theme>` |
| switch theme for this project only | `set --here <theme>` |
| quieter | `volume 0.4` |
| silence everything | `mute` / `unmute` |
| turn one cue off | `off done` / `on done` |
| ring `done` only past a long turn | `min-turn 30` (0 = every turn) |
| stop a clip that is playing | `stop` |

## How to answer

If the user named a subcommand, run it and report the result in one line. Paste
raw output only for `status` and `sounds`, which are tables.

If they just want a different sound and did not say which, run `list`, ask them
to pick, then run `set <theme>`.

If they say the sound fires too often, raise `min-turn` rather than turning
`done` off, so the long runs still ring.

## The cues in Codex

| Cue | Fires on |
|-----|----------|
| `done` | the `Stop` hook, when a turn ends |
| `attention` | the `PermissionRequest` hook, when Codex asks to run something |
| `subagent` | the `SubagentStop` hook |
| `plan` | wired to `ExitPlanMode`, quiet until Codex exposes it |

Settings live in `~/.config/notify-sound/config` and apply immediately. A
project can override them in `<project>/.codex/notify-sound.conf`.
