# Notch

A native macOS notch panel, in progress.

scripts/install.sh    # build, install to /Applications, add Claude Code hooks, launch
scripts/uninstall.sh  # remove the app, its hooks and ~/.notch
swift test
.build/debug/Notch --snapshot /tmp/notch   # render every state to PNGs
```

Settings (city, coordinates, units, pinned apps) are in `~/.notch/config.json`; restart Notch after editing.
Lyrics come from lrclib.net and weather from open-meteo.com. Neither needs a key.

`notch-hook` never decides anything on its own. If the app isn't running or nobody answers within
110 s, it exits silently and Claude Code shows its usual prompt. AskUserQuestion and ExitPlanMode
are always left to Claude Code, because they need more than a yes or no.

The first install keeps the original settings at `~/.claude/settings.json.before-notch`.
