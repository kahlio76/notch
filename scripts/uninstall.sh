#!/bin/bash
# Removes the app, its hooks from settings.json, and ~/.notch.
set -uo pipefail
cd "$(dirname "$0")/.."
pkill -x Notch 2>/dev/null
python3 -I "$PWD/scripts/hooks.py" uninstall
rm -rf /Applications/Notch.app ~/.notch
