# agent-notify-sound

Plays a short sound whenever your coding agent stops and wants you, so you can
look away from the terminal and still catch the moment something needs an
answer. Runs in Claude Code, Codex CLI and Cursor from one set of scripts.

## What triggers a sound

| Cue | Plays when |
|-----|-----------|
| done | The agent finished the task or the answer, not when it stopped to ask you something |
| attention | It is waiting on you: a question, or a tool asking permission |
| plan | A plan is on screen waiting for approval |
| subagent | A background agent finished |

Each cue is a different sound, so you can tell which one happened without
looking.

The hook behind each cue differs by agent:

| Cue | Claude Code | Codex CLI | Cursor |
|-----|-------------|-----------|--------|
| done | `Stop` | `Stop` | `stop`, and only when `status` is `completed` |
| attention | `Notification` | `PermissionRequest` | `beforeShellExecution` and `beforeMCPExecution`, off by default |
| plan | `PreToolUse` / `PermissionRequest` on `ExitPlanMode` | same wiring, silent so far | not available |
| subagent | `SubagentStop` | `SubagentStop` | `subagentStop` |
| turn start | `UserPromptSubmit` | `UserPromptSubmit` | `beforeSubmitPrompt` |

Two things worth knowing about the gaps. Cursor has no notification event at
all, and the hook that runs before a shell or MCP call fires whether or not you
are asked to approve anything, so wiring `attention` to it means sound on every
command the agent runs. It is there, and it ships off:

```
scripts/soundctl.sh cursor-attention on
```

Codex has no notification event either, but it does have `PermissionRequest`,
which is the case you actually care about. Its plan cue is wired to
`ExitPlanMode` and will start working by itself if Codex exposes that tool.

Two rules keep `done` from talking over the others:

- **A blocking cue cancels the `done` behind it.** Presenting a plan fires `plan`,
  and the turn then ends, which fires the stop event a moment later. That second
  sound is not a finished turn, so it's dropped for `done_suppress_ms` (10 s)
  after any `plan` or `attention`. It only works in that direction: an
  `attention` that follows a real `done` still rings.
- **Short turns stay quiet.** `done` only rings past `min_turn_ms` (15 s), on the
  theory that if it came back in four seconds you were sitting right there.
  `/sound min-turn 0` brings back the old always-ring behaviour.

Neither rule touches `attention` or `plan`. Those mean the agent is blocked on
you and they always ring.

## The four themes

| Theme | Sounds |
|-------|--------|
| `zaghlalah` | Radio beeps: a CW sidetone keying `DO`, `NE`, and `PL` in morse. Default. |
| `jersey` | Overdriven bass riff with a bit of swagger |
| `marimba` | Warm wooden mallets, soft and short |
| `system` | OS built-ins: Glass / Submarine / Hero on macOS, freedesktop sounds on Linux |

A theme that ships only the three original cues still works: `subagent` falls
back to that theme's `done` file. `/sound sounds` marks borrowed cues with `<-`.

### zaghlalah

Each cue keys a two-letter abbreviation at its own pitch:

| Cue | Code | Morse | Pitch | Length |
|-----|------|-------|-------|--------|
| done | `DO` for done | `-.. ---` | 620 Hz | 1.14 s |
| attention | `NE` for needs you | `-. .` | 920 Hz | 0.54 s |
| plan | `PL` for plan | `.--. .-..` | 760 Hz | 1.24 s |

Keyed at roughly 24 WPM with standard three-dit letter spacing and 5 ms
raised-cosine edges, so it sounds like a radio rather than a square wave with
sharp corners. `NE` is the shortest of the three, which is convenient, since
it's the one that fires when the agent is actually blocked waiting for you.

### jersey

A minor pentatonic bass riff run through a soft-clipped overdrive, with a little
organ under it and a hat on the offbeat. `done` walks down and lands on the
root. `attention` is two hard stabs with no groove at all. `plan` climbs and
stops on the seventh without resolving.

On anything other than macOS, `system` falls back to `zaghlalah`.

## Install

Claude Code:

```
/plugin marketplace add batout/agent-notify-sounds
/plugin install agent-notify-sound@agent-notify-sounds
```

Codex CLI: `codex plugin marketplace add batout/agent-notify-sounds`, then
install `agent-notify-sound` from `/plugins`.

Cursor: `/add-plugin batout/agent-notify-sounds`, or add the repo as a
marketplace source and install from there.

To try it for one session in Claude Code without installing:

```bash
git clone https://github.com/batout/agent-notify-sounds.git
claude --plugin-dir agent-notify-sounds/plugins/agent-notify-sound
```

Run `/hooks` afterward and you should see six entries.

There is also `../../install.sh`, which writes absolute paths into
`~/.cursor/hooks.json` or `~/.codex/config.toml` for builds without plugin
support.

On Windows, run the agent from Git Bash or WSL. Nothing else to install:
playback goes through PowerShell. The platform notes in the
[repo README](../../README.md) cover what each OS needs.

## Using it

```
/sound                     pick a theme interactively
/sound list                show the themes
/sound sounds              every file, with format, length, and size
/sound preview jersey      hear all the cues of a theme
/sound set zaghlalah       switch theme
/sound set --here marimba  switch theme for this project only
/sound volume 0.4          quieter
/sound min-turn 30         only ring "done" past a 30 second turn (0 = always)
/sound focus on            skip "done" while your terminal is frontmost (macOS)
/sound mute                silence everything
/sound off done            keep only the "needs you" sounds
/sound stop                cut off a sound that's playing
/sound status              what's active right now
```

Claude Code and Cursor both get `/sound`. Codex has no plugin commands, so it
gets the same thing as a skill: ask it to change the sound, or run the script
yourself.

All of it works from a shell too, without any agent:

```bash
./scripts/soundctl.sh sounds
./scripts/soundctl.sh preview jersey
./scripts/soundctl.sh set marimba
./scripts/soundctl.sh --host cursor status
```

### If `done` still fires more than you want

Raise the bar rather than turning it off, so you keep the signal on the long
runs that are the whole point:

```
/sound min-turn 60      only turns over a minute
/sound focus on         and only when you're looking at another window
```

`/sound off done` still works if you want nothing but the "needs you" cues, and
`/sound on done` puts it back.

## Adding your own sounds

A theme is just a directory. Drop one in and it appears in `/sound list`, no
code changes and nothing to register:

```
sounds/my-theme/
├── done.wav
├── attention.wav
└── plan.wav
```

`.wav`, `.mp3`, `.m4a`, `.aiff`, `.ogg`, and `.flac` all work. Compressed
formats need a player that can decode them, which is covered below.

If you'd rather keep a theme to yourself, name the folder `local-something` and
git will ignore it.

Keep the cues short. Past about a second and a half they get tiresome on `done`,
and if one is still playing when the next event fires, the new sound cuts it off
rather than layering on top.

## Settings

Stored in `~/.config/notify-sound/config` and applied immediately, no restart:

```ini
theme=zaghlalah        # any theme directory name, or "system"
volume=0.7             # 0.0 to 1.0
mute=0                 # 1 silences everything
done=1                 # per-cue on/off
attention=1
plan=1
subagent=1
min_turn_ms=15000      # "done" only past this turn length; 0 = always ring
done_suppress_ms=10000 # drop "done" this long after a plan/attention cue
focus_aware=0          # 1 = also skip "done" when your terminal is frontmost
                       #     (macOS only, ignored elsewhere)
cursor_attention=0     # 1 = in Cursor, ring before every shell or MCP call
debounce_ms=1800       # collapse events closer together than this
remote=bell            # over SSH: bell | play | off
debug=0                # 1 dumps each hook payload into the state dir
```

One file covers all three agents, so the theme you pick in Claude Code is the
one Codex and Cursor use.

A project can override any of these in `<project>/.claude/notify-sound.conf`,
and `.cursor/` and `.codex/` work the same way. Whichever agent is running reads
its own directory first and then the other two, so a theme set once applies
wherever you open the repo. Give each repo its own theme and the sound tells you
which window wants you. `/sound status` shows the layer every value came from.

`NOTIFY_SOUND_THEME` and `NOTIFY_SOUND_MUTE=1` override every file.
`CLAUDE_SOUND_THEME` and `CLAUDE_SOUND_MUTE` still work, and so does the 1.x
config at `~/.claude/notify-sound.conf`, which is read for anything the new file
does not set.

## How playback works

`scripts/play.sh` picks a player that can handle the file's format:

| Platform | Player | Notes |
|----------|--------|-------|
| macOS | `afplay` | built in, every format, volume included |
| Linux | `paplay` or `aplay` for wav, `ffplay` / `mpg123` / `mpv` / `cvlc` for compressed | install whichever your distro ships |
| Windows, Git Bash or WSL | `powershell.exe` or `pwsh.exe` | `MediaPlayer` for wav and mp3, with volume; `SoundPlayer` for wav if the WPF assembly is missing |

On Windows the file path is converted with `cygpath` or `wslpath` first, so the
Windows side of PowerShell can find it. Playback happens in the background and
the script returns in about 30 ms. It tracks the playing PID so the next event
can cut a long sound off, which includes the PowerShell process.

It always exits 0 and never writes to stdout. A missing player or a missing
sound file can't block a turn or fail one; the worst case is a terminal bell.
The silent stdout matters in Cursor, where anything a `before*` hook prints is
read as a permission decision.

Over SSH the sound would come out of the machine the agent is running on, which
is not the one you're sitting at, so the local terminal's bell rings instead.
Set `remote=play` if that box really does have speakers you can hear. WSL is not
treated as remote: the audio comes out of the Windows machine in front of you.

The `system` theme resolves per platform, and falls back to `zaghlalah` when the
file is not there:

| Cue | macOS | Linux | Windows |
|-----|-------|-------|---------|
| done | Glass.aiff | complete.oga | chimes.wav |
| attention | Submarine.aiff | message.oga | notify.wav |
| plan | Hero.aiff | dialog-information.oga | chord.wav |
| subagent | Pop.aiff | bell.oga | ding.wav |

State lives in `$TMPDIR/agent-notify-sound/`, one small file per session, keyed
by agent and by the session id from the hook payload (`session_id` in Claude
Code and Codex, `conversation_id` in Cursor). That's what keeps two windows from
swallowing each other's cues or cutting each other's clips off, including two
different agents open on the same repo. Stale files are swept after a day.

## Layout

```
agent-notify-sound/
├── .claude-plugin/plugin.json
├── .codex-plugin/plugin.json
├── .cursor-plugin/plugin.json
├── hooks/{hooks.json,codex-hooks.json,cursor-hooks.json}
├── commands/sound.md          Claude Code and Cursor
├── skills/sound/SKILL.md      Codex
├── scripts/{play.sh,mark.sh,soundctl.sh,lib.sh,notify-codex.sh}
└── sounds/
    ├── zaghlalah/{done,attention,plan}.wav
    ├── jersey/{done,attention,plan}.wav
    └── marimba/{done,attention,plan}.wav
```

The three manifests point at the same scripts. `play.sh --host <agent>` is the
only thing that varies, and it exists so the payload quirks and the per-agent
gates stay in one place.

`notify-codex.sh` covers older Codex builds that only have the `notify` key
rather than hooks. That key fires one event, when a turn ends, so it gets you
`done` and nothing else.

MIT licensed. Every bundled sound was synthesized for this project and none of
it is sampled from an existing recording. Each theme folder ships the
`generate.py` that produced it, so you can check that for yourself or fork a
theme by changing a few numbers. The `system` theme plays macOS's own files and
bundles nothing.
