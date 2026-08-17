# notify-sound

Plays a short sound whenever Claude Code stops and wants you, so you can look
away from the terminal and still catch the moment something needs an answer.

## What triggers a sound

| Cue | Hook event | Plays when |
|-----|-----------|------------|
| done | `Stop` | Claude finished the task or the answer — not when it stopped to ask you something |
| attention | `Notification` | Claude is waiting on you: a question, or a tool asking permission |
| plan | `PreToolUse` / `PermissionRequest` matching `ExitPlanMode` | A plan is on screen waiting for approval |
| subagent | `SubagentStop` | A background agent finished |

Each cue is a different sound, so you can tell which one happened without
looking.

Two rules keep `done` from talking over the others:

- **A blocking cue cancels the `done` behind it.** Presenting a plan fires `plan`,
  and the turn then ends, which fires `Stop` a moment later. That second sound is
  not a finished turn, so it's dropped for `done_suppress_ms` (10 s) after any
  `plan` or `attention`. It only works in that direction — an `attention` that
  follows a real `done` still rings.
- **Short turns stay quiet.** `done` only rings past `min_turn_ms` (15 s), on the
  theory that if it came back in four seconds you were sitting right there.
  `/sound min-turn 0` brings back the old always-ring behaviour.

Neither rule touches `attention` or `plan`. Those mean Claude is blocked on you
and they always ring.

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
it's the one that fires when Claude is actually blocked waiting for you.

### jersey

A minor pentatonic bass riff run through a soft-clipped overdrive, with a little
organ under it and a hat on the offbeat. `done` walks down and lands on the
root. `attention` is two hard stabs with no groove at all. `plan` climbs and
stops on the seventh without resolving.

On anything other than macOS, `system` falls back to `zaghlalah`.

## Install

```
/plugin marketplace add batout/claude-code-sounds
/plugin install notify-sound@claude-code-sounds
```

To try it for one session without installing:

```bash
git clone https://github.com/batout/claude-code-sounds.git
claude --plugin-dir claude-code-sounds/plugins/notify-sound
```

Run `/hooks` afterward and you should see six entries.

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

All of it works from a shell too, without Claude:

```bash
./scripts/soundctl.sh sounds
./scripts/soundctl.sh preview jersey
./scripts/soundctl.sh set marimba
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

Stored in `~/.claude/notify-sound.conf` and applied immediately, no restart:

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
debounce_ms=1800       # collapse events closer together than this
remote=bell            # over SSH: bell | play | off
debug=0                # 1 dumps each hook payload into the state dir
```

A project can override any of these in `<project>/.claude/notify-sound.conf`,
which wins over the user file. Give each repo its own theme and the sound tells
you which window wants you. `/sound status` shows the layer every value came
from.

`CLAUDE_SOUND_THEME` and `CLAUDE_SOUND_MUTE=1` override both files.

## How playback works

`scripts/play.sh` picks a player that can handle the file's format. On macOS
that's `afplay`. Elsewhere it tries `ffplay`, `mpg123`, `mpv`, or `cvlc` for
compressed audio, and `paplay`, `aplay`, or `powershell.exe` for PCM. Playback
happens in the background and the script returns in about 30 ms. It tracks the
playing PID so the next event can cut a long sound off.

It always exits 0. A missing player or a missing sound file can't block a turn
or fail one; the worst case is a terminal bell.

Over SSH the sound would come out of the machine Claude is running on, which is
not the one you're sitting at, so the local terminal's bell rings instead. Set
`remote=play` if that box really does have speakers you can hear.

State lives in `$TMPDIR/claude-notify-sound/`, one small file per session keyed
by the hook's `session_id`. That's what keeps two Claude windows from swallowing
each other's cues or cutting each other's clips off; stale files are swept after
a day.

## Layout

```
notify-sound/
├── .claude-plugin/plugin.json
├── hooks/hooks.json
├── commands/sound.md
├── scripts/{play.sh,mark.sh,soundctl.sh,lib.sh}
└── sounds/
    ├── zaghlalah/{done,attention,plan}.wav
    ├── jersey/{done,attention,plan}.wav
    └── marimba/{done,attention,plan}.wav
```

MIT licensed. Every bundled sound was synthesized for this project and none of
it is sampled from an existing recording. Each theme folder ships the
`generate.py` that produced it, so you can check that for yourself or fork a
theme by changing a few numbers. The `system` theme plays macOS's own files and
bundles nothing.
