# Notch

A native macOS notch panel: Spotify with live lyrics, weather, volume, brightness, a whole-Mac
dark/light switch, peeks, and Claude Code status with approve/deny.

```bash
scripts/install.sh    # build, install to /Applications, add Claude Code hooks, launch
scripts/uninstall.sh  # remove the app, its hooks and ~/.notch
swift test
.build/debug/Notch --snapshot /tmp/notch   # render every state to PNGs
```

Settings (city, coordinates, units, pinned apps) are in `~/.notch/config.json`; restart Notch after editing.
Lyrics come from lrclib.net and weather from open-meteo.com. Neither needs a key.

`notch-hook` never decides anything on its own. If the app isn't running or nobody answers within
110 s, it exits silently and Claude Code shows its usual prompt.

When Claude asks a multiple-choice question (AskUserQuestion), the notch shows each question with its
options as buttons, also on ⌃⌥1 to ⌃⌥4. Multi-select questions take ⌃⌥↩ to submit. The picks go back
as the tool's `answers`, the same way Claude Code's own prompt fills them in. "In Claude" (⌃⌥N) hands
the question back, for typing an answer that isn't on the list. Questions with more than four options,
and ExitPlanMode, always stay in Claude Code.

The first install keeps the original settings at `~/.claude/settings.json.before-notch`.

## The panel that opened from the wrong place

While using an early build, I noticed the panel sometimes grew from a point in the middle of nowhere instead of out of
the notch. It happened about half the time, which suggested a timing problem.

Recording repeated opens and measuring the shape's edges frame by frame never caught it, so **the cause below is
inferred from the code, not proven**. The shape stayed centered horizontally in every frame, which ruled out the window
drifting sideways.

The likely cause: the window resized to fit each state, on a separate main-thread hop from the SwiftUI update that
animated the shape. When SwiftUI went first, the content was briefly larger than its window, and a hosting view centers
oversized content, so the animation would start from the wrong place. The blur transition also scaled content from the
panel's center.

The fix was to stop resizing:

- The window is now one fixed size that fits the largest panel, so there is nothing to race.
- `sizingOptions = []` stops the hosting view from resizing the window to fit its content.
- The window ignores the mouse outside the drawn shape, so clicks around the notch still reach other apps.
- The transition scales from the top edge instead of the center.

After the change, ten randomized opens all grew from the notch, clicks passed through correctly, and the bug stopped
appearing in normal use. This repo's history was split into feature steps after the fix, so the earlier resizing
version isn't in it.
