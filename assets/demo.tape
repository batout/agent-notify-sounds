# Records assets/demo.gif. Run it from the repo root:
#
#   vhs assets/demo.tape
#
# Everything it shows is the real control CLI. HOME is pointed at a scratch
# directory first, so recording the demo cannot touch your own settings, and
# the volume is set to 0 so it records silently.

Output assets/demo.gif

Set Shell bash
Set FontSize 15
Set Width 1000
Set Height 420
Set Padding 24
Set Theme "Catppuccin Mocha"
Set TypingSpeed 40ms

Hide
# A copy under a short path, so the recording shows readable paths rather than
# a wrapped home directory.
Type "rm -rf /tmp/ans /tmp/ans-home && cp -R $PWD/plugins/agent-notify-sound /tmp/ans" Enter
# Private themes are gitignored, so the copy drops them and the recording shows
# what a fresh install shows.
Type "rm -rf /tmp/ans/sounds/sopranos /tmp/ans/sounds/local-*" Enter
Type "export HOME=/tmp/ans-home && export XDG_CONFIG_HOME=$HOME/.config" Enter
Type "mkdir -p $XDG_CONFIG_HOME/notify-sound && printf 'volume=0\n' > $XDG_CONFIG_HOME/notify-sound/config" Enter
Type "cd /tmp/ans && alias sound=./scripts/soundctl.sh" Enter
Type "export PS1='\$ ' && clear" Enter
Show

Sleep 800ms
Type "sound status" Sleep 400ms Enter
Sleep 3s

Type "clear" Enter
Sleep 300ms
Type "sound list" Sleep 400ms Enter
Sleep 3s

Type "sound set jersey" Sleep 400ms Enter
Sleep 2s

Type "clear" Enter
Sleep 300ms
Type "sound sounds jersey" Sleep 400ms Enter
Sleep 3500ms

Type "sound min-turn 60" Sleep 400ms Enter
Sleep 2500ms
