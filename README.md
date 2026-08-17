# claude-code-sounds

A Claude Code plugin marketplace for audio feedback.

Claude Code is silent. Start something long, switch to another window, and the
only way to know it finished is to keep going back and looking. Worse is when it
stopped four minutes ago to ask you a yes/no question and has been sitting there
ever since. This fixes that.

## Install

```
/plugin marketplace add batout/claude-code-sounds
/plugin install notify-sound@claude-code-sounds
```

Then run `/sound` to pick a theme.

## Plugins

### notify-sound

Plays a short sound whenever Claude Code stops and wants you.

| Cue | Fires when |
|-----|-----------|
| done | Claude finished responding and the turn ended |
| attention | Claude is waiting on you: a question, or a tool asking permission |
| plan | A plan is on screen waiting for your approval |

The three cues are different sounds, so you can tell which one happened without
turning around.

| Theme | Sound |
|-------|-------|
| `zaghlalah` | Radio beeps keying `DO` / `NE` / `PL` in morse. Default. |
| `jersey` | Overdriven bass riff with a bit of swagger |
| `marimba` | Warm wooden mallets, soft and short |
| `system` | macOS built-ins: Glass, Submarine, Hero |

The [plugin README](plugins/notify-sound/README.md) covers the rest: per-cue
toggles, volume, mute, and how to drop in your own sounds.

## Rolling it out to a team

Check this into your project's `.claude/settings.json` and anyone who clones the
repo gets it without running `/plugin install` themselves:

```json
{
  "extraKnownMarketplaces": {
    "claude-code-sounds": {
      "source": { "source": "github", "repo": "batout/claude-code-sounds" }
    }
  },
  "enabledPlugins": {
    "notify-sound@claude-code-sounds": true
  }
}
```

There's a copy in [`examples/settings.json`](examples/settings.json).

One thing to know first. This plugin is shell scripts that run at the end of
every turn. Your teammates accept them through the normal folder-trust prompt,
and after that the hooks run without asking again. The scripts are short and
readable, which is why they're kept that way. They live in
`plugins/notify-sound/scripts/`.

## Contributing a theme

A theme is a directory with three sound files in it. No code changes:

```
plugins/notify-sound/sounds/<your-theme>/
├── done.wav
├── attention.wav
└── plan.wav
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
