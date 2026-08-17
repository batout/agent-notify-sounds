# notify-sound

Plays a short sound whenever Claude Code stops and wants you, so you can look
away from the terminal and still catch the moment something needs an answer.

## What triggers a sound

| Cue | Hook event | Plays when |
|-----|-----------|------------|
| done | `Stop` | Claude finished responding, the turn ended |
| attention | `Notification` | Claude is waiting on you: a question, or a tool asking permission |
| plan | `PreToolUse` / `PermissionRequest` matching `ExitPlanMode` | A plan is on screen waiting for approval |

Each cue is a different sound, so you can tell which one happened without
looking. Overlapping events inside a 1.8 second window collapse into one sound.

## The four themes

| Theme | Sounds |
|-------|--------|
| `zaghlalah` | Radio beeps: a CW sidetone keying `DO`, `NE`, and `PL` in morse. Default. |
| `jersey` | Overdriven bass riff with a bit of swagger |
| `marimba` | Warm wooden mallets, soft and short |
| `system` | macOS built-ins: Glass, Submarine, Hero |

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

Run `/hooks` afterward and you should see four entries.

## Using it

```
/sound                     pick a theme interactively
/sound list                show the themes
/sound sounds              every file, with format, length, and size
/sound preview jersey      hear all three cues of a theme
/sound set zaghlalah       switch theme
/sound volume 0.4          quieter
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

### The setting most people end up changing

`done` fires on every turn, including the quick back-and-forths where you're
sitting right there watching it work. If that gets annoying:

```
/sound off done
```

Now it only makes noise when Claude can't proceed without you. `/sound on done`
puts it back.

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
theme=zaghlalah    # any theme directory name, or "system"
volume=0.7         # 0.0 to 1.0
mute=0             # 1 silences everything
done=1             # per-cue on/off
attention=1
plan=1
debounce_ms=1800   # collapse events closer together than this
```

`CLAUDE_SOUND_THEME` and `CLAUDE_SOUND_MUTE=1` override the file.

## How playback works

`scripts/play.sh` picks a player that can handle the file's format. On macOS
that's `afplay`. Elsewhere it tries `ffplay`, `mpg123`, `mpv`, or `cvlc` for
compressed audio, and `paplay`, `aplay`, or `powershell.exe` for PCM. Playback
happens in the background and the script returns in about 30 ms. It tracks the
playing PID so the next event can cut a long sound off.

It always exits 0. A missing player or a missing sound file can't block a turn
or fail one; the worst case is a terminal bell.

## Layout

```
notify-sound/
├── .claude-plugin/plugin.json
├── hooks/hooks.json
├── commands/sound.md
├── scripts/{play.sh,soundctl.sh,lib.sh}
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
