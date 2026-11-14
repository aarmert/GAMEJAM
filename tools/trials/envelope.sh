#!/bin/bash
# tools/trials/envelope.sh : measures the Trials movement envelope (headless) and prints a Markdown table
cd "$(dirname "$0")/../.." || exit 2
timeout 300 ~/tools/godot/godot --headless --path . --audio-driver Dummy --fixed-fps 60 -s tools/trials/envelope.gd -- "$@" 2>&1 | grep -E '^\||^Constants|SCRIPT ERROR|Parse Error'
exit "${PIPESTATUS[0]}"
