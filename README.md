# agent-notify-sounds

[![tests](https://github.com/batout/agent-notify-sounds/actions/workflows/test.yml/badge.svg)](https://github.com/batout/agent-notify-sounds/actions/workflows/test.yml)

Audio feedback for coding agents. Works in Claude Code, Codex CLI and Cursor.

Agents are silent. Start something long, switch to another window, and the only
way to know it finished is to keep going back and looking. Worse is when it
stopped four minutes ago to ask you a yes/no question and has been sitting there
ever since. This fixes that.

## What's new in 2.1.0

[Released today](https://github.com/batout/agent-notify-sounds/releases/tag/v2.1.0),
and it is the release that stops this being a Claude Code plugin:

- **Codex CLI and Cursor** run the same scripts, shipped as native plugins for
  each. Codex hook events line up with Claude's closely enough to need no
  changes; Cursor gets its own hooks file for its different schema.
- **Windows** plays through PowerShell on Git Bash and WSL, wav and mp3, volume
  included, with `C:\Windows\Media` behind the `system` theme.
- **One config** at `~/.config/notify-sound/config`, so the theme you pick in
  one agent is the theme the other two use.
- **A test suite** of 40 assertions, run on macOS, Linux and Windows in CI.

Coming from 1.x, the ids changed. See [upgrading](#upgrading-from-1x).

## Install

Claude Code:

```
/plugin marketplace add batout/agent-notify-sounds
/plugin install agent-notify-sound@agent-notify-sounds
```

Codex CLI:

```
codex plugin marketplace add batout/agent-notify-sounds
```

then `/plugins` and install `agent-notify-sound`.

Cursor: `/add-plugin batout/agent-notify-sounds`, or add the repo as a
marketplace source and install `agent-notify-sound` from it.

Then run `/sound` to pick a theme. In Codex, ask for the sound skill or run
`scripts/soundctl.sh` directly.

If your build has no plugin support, clone the repo and run the installer, which
writes absolute paths into your own config:

```bash
git clone https://github.com/batout/agent-notify-sounds.git
cd agent-notify-sounds
./install.sh cursor      # merges into ~/.cursor/hooks.json
./install.sh codex       # appends to ~/.codex/config.toml
```

`./install.sh --uninstall cursor` takes it back out, and every file it touches is
backed up first.

## Setup by platform

macOS, Linux and Windows all work. What differs is which program ends up
playing the file, and `/sound status` names the one it picked. The test suite
runs on all three in CI, so the differences stay honest; `bash tests/run-tests.sh`
runs it locally.

### macOS

Nothing to install. `afplay` ships with the system and handles every format in
the repo, volume included.

The `system` theme plays Glass, Submarine, Hero and Pop out of
`/System/Library/Sounds`. `/sound focus on` is macOS only: it asks `lsappinfo`
which app is frontmost and skips `done` while you are looking at the terminal
that fired it.

### Linux

The bundled themes are `.wav`, so a PCM player is enough:

```bash
sudo apt install pulseaudio-utils     # paplay, on most desktops already there
sudo apt install alsa-utils           # aplay, the fallback
```

For an `.mp3` or `.ogg` theme of your own, install one of `ffplay` (ffmpeg),
`mpg123`, `mpv` or `cvlc`. Volume works with all of them.

The `system` theme uses the freedesktop sounds in
`/usr/share/sounds/freedesktop/stereo/`, from the `sound-theme-freedesktop`
package. Without it, `system` falls back to the bundled `zaghlalah`.

Headless boxes and containers usually have no audio device at all. Over SSH the
sound would come out of the wrong machine anyway, so the plugin rings your local
terminal bell instead, and `remote=play` overrides that if the remote box really
does have speakers.

### Windows

The scripts are bash, so run your agent from **Git Bash** or **WSL**. Both are
supported and neither needs anything else installed: playback goes through
PowerShell's `MediaPlayer`, which handles wav and mp3 and honours the volume
setting. If the WPF assembly is missing, and it can be under PowerShell 7
without the desktop runtime, it falls back to `SoundPlayer` for wav.

In WSL the sound still comes out of Windows, which is the machine you are
sitting at, so it is treated as local rather than as a remote session.

The `system` theme plays `chimes`, `notify`, `chord` and `ding` from
`C:\Windows\Media`.

The hooks run the scripts as `bash "<path>/play.sh"`, so a host that shells out
through `cmd.exe` still works as long as Git Bash is on your `PATH`. If the
plugin install does not fire, wire it up from Git Bash or WSL instead:

```bash
./install.sh cursor
./install.sh codex
```

That writes Windows paths (`bash "C:\...\play.sh" --host cursor done`) into your
config, so it works no matter which shell the agent uses.

`focus_aware` does nothing outside macOS. `min_turn_ms` is the setting to reach
for on Windows and Linux when `done` fires more often than you want.

## What you hear

| Cue | Fires when |
|-----|-----------|
| done | The agent finished the task or the answer |
| attention | It is waiting on you: a question, or a tool asking permission |
| plan | A plan is on screen waiting for your approval |
| subagent | A background agent finished |

Every cue is a different sound, so you can tell which one happened without
turning around. `done` means finished, so it stays quiet when the agent stopped
to ask you something, which already made its own noise, and on turns short
enough that you were clearly still watching.

## What each agent can actually tell you

The cues you get depend on which events the agent exposes. Nothing here is
emulated or guessed at.

| Cue | Claude Code | Codex CLI | Cursor |
|-----|-------------|-----------|--------|
| done | `Stop` | `Stop` | `stop`, completed turns only |
| attention | `Notification` | `PermissionRequest` | optional, off by default |
| plan | `ExitPlanMode` | wired, quiet until Codex exposes it | not available |
| subagent | `SubagentStop` | `SubagentStop` | `subagentStop` |

Cursor has no notification event. The closest thing is the hook that runs before
a shell or MCP call, which fires whether or not you are actually asked for
permission, so it ships turned off. Turn it on with
`scripts/soundctl.sh cursor-attention on` if you would rather have the false
positives than miss a prompt.

## Themes

| Theme | Sound |
|-------|-------|
| `zaghlalah` | Radio beeps keying `DO` / `NE` / `PL` in morse. Default. |
| `jersey` | Overdriven bass riff with a bit of swagger |
| `marimba` | Warm wooden mallets, soft and short |
| `system` | OS built-ins: Glass / Submarine / Hero on macOS, freedesktop on Linux |

The [plugin README](plugins/agent-notify-sound/README.md) covers the rest:
per-cue toggles, volume, mute, per-project themes, and how to drop in your own
sounds.

## Roadmap

Shipped in 2.1.0: Claude Code, Codex CLI and Cursor, one config shared by all
three, Windows playback through PowerShell on both Git Bash and WSL, and a test
suite that runs on all three platforms.

Still open:

- A real attention cue in Cursor, if Cursor ever adds a notification event.
- The plan cue in Codex, which is wired to `ExitPlanMode` and stays silent until
  Codex exposes plan approval to hooks.
- A focus check outside macOS, so `done` can stay quiet while you are watching
  the window.
- Zed and Gemini CLI once their hook surfaces settle.

## Upgrading from 1.x

Everything is called `agent-notify-sounds` now, marketplace and plugin included,
because it stopped being Claude-only in 2.0. The ids changed with it, so a 1.x
install needs replacing rather than updating. Remove the old marketplace and its
plugin first, whatever you had them registered as, then:

```
/plugin marketplace add batout/agent-notify-sounds
/plugin install agent-notify-sound@agent-notify-sounds
```

Your settings survive. They now live in `~/.config/notify-sound/config`, and the
old `~/.claude/notify-sound.conf` is still read for anything the new file does
not set. `/sound status` shows which layer each value came from.

## Rolling it out to a team

Check this into your project's `.claude/settings.json` and anyone who clones the
repo gets it without running `/plugin install` themselves:

```json
{
  "extraKnownMarketplaces": {
    "agent-notify-sounds": {
      "source": { "source": "github", "repo": "batout/agent-notify-sounds" }
    }
  },
  "enabledPlugins": {
    "agent-notify-sound@agent-notify-sounds": true
  }
}
```

There's a copy in [`examples/settings.json`](examples/settings.json), along with
paste-ready [`cursor-hooks.json`](examples/cursor-hooks.json) and
[`codex-config.toml`](examples/codex-config.toml).

One thing to know first. This plugin is shell scripts that run at the end of
every turn. Your teammates accept them through the normal folder-trust prompt,
and after that the hooks run without asking again. The scripts are short and
readable, which is why they're kept that way. They live in
`plugins/agent-notify-sound/scripts/`.

## Contributing a theme

A theme is a directory with three sound files in it. No code changes:

```
plugins/agent-notify-sound/sounds/<your-theme>/
├── done.wav
├── attention.wav
├── plan.wav
└── subagent.wav   (optional, falls back to done.wav)
```

`.wav`, `.mp3`, `.m4a`, `.aiff`, `.ogg`, and `.flac` all work. The theme shows
up in `/sound list` the next time the plugin loads.

Keep the cues short, ideally under a second and a half. The `done` cue fires on
every single turn, and anything longer than that wears out its welcome by the
third or fourth time you hear it.

Only submit audio you have the rights to. Everything in this repo is either
synthesized from scratch or supplied by the operating system, and each theme
folder includes the `generate.py` that produced its sounds. Please don't send
clips from music, films, or TV, however short.

To keep a theme private instead, name the folder `local-something` and git will
ignore it.

## License

MIT, see [LICENSE](LICENSE). The `zaghlalah`, `jersey`, and `marimba` sounds were
synthesized for this project and fall under the same license. The `system` theme
plays macOS's own files and bundles nothing.
