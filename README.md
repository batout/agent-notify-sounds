# agent-notify-sounds

Audio feedback for coding agents. Works in Claude Code, Codex CLI and Cursor.

Agents are silent. Start something long, switch to another window, and the only
way to know it finished is to keep going back and looking. Worse is when it
stopped four minutes ago to ask you a yes/no question and has been sitting there
ever since. This fixes that.

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

Shipped in 2.0.0: Claude Code, Codex CLI, Cursor, one config shared by all
three.

Still open:

- A real attention cue in Cursor, if Cursor ever adds a notification event.
- The plan cue in Codex, which is wired to `ExitPlanMode` and stays silent until
  Codex exposes plan approval to hooks.
- Windows playback past the PowerShell `SoundPlayer` fallback.
- Zed and Gemini CLI once their hook surfaces settle.

## Upgrading from 1.x

The repo, the marketplace and the plugin were all called some version of
`claude-code-sounds` when it only ran in Claude Code. Both ids changed in 2.0.0,
so an existing install needs replacing rather than updating:

```
/plugin uninstall notify-sound@claude-code-sounds
/plugin marketplace remove claude-code-sounds
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
