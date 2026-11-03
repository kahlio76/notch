"""Adds or removes Notch's hook entries in ~/.claude/settings.json, leaving other hooks alone."""
import json, os, shutil, sys

SETTINGS = os.path.expanduser("~/.claude/settings.json")
COMMAND = os.path.expanduser("~/.notch/bin/notch-hook")
EVENTS = ["SessionStart", "UserPromptSubmit", "PostToolUse", "Stop", "SessionEnd", "PermissionRequest"]

def ours(group):
    return any(h.get("command") == COMMAND for h in group.get("hooks", []))

with open(SETTINGS) as f:
    settings = json.load(f)
hooks = settings.setdefault("hooks", {})
for event in EVENTS:
    groups = [g for g in hooks.get(event, []) if not ours(g)]
    if sys.argv[1] == "install":
        hook = {"type": "command", "command": COMMAND}
        group = {"hooks": [hook]}
        if event in ("PostToolUse", "PermissionRequest"):
            group["matcher"] = "*"
        if event == "PermissionRequest":
            hook["timeout"] = 120  # notch-hook gives up at 110 s and defers to Claude's prompt.
        groups.append(group)
    if groups:
        hooks[event] = groups
    else:
        hooks.pop(event, None)

backup = SETTINGS + ".before-notch"
if not os.path.exists(backup):
    shutil.copy2(SETTINGS, backup)
tmp = SETTINGS + ".notch-tmp"
with open(tmp, "w") as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)
    f.write("\n")
os.replace(tmp, SETTINGS)
