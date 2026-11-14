#!/bin/bash
# tools/trials/validate.sh <chapter file> [...] [--strict]   (run from anywhere)
# Exit code 0 = no errors. A GDScript error inside the tool shows as "SCRIPT ERROR" and a timeout.
cd "$(dirname "$0")/../.." || exit 2
timeout 120 ~/tools/godot/godot --headless --path . --audio-driver Dummy -s tools/trials/validate.gd -- "$@" 2>&1 | grep -v -E '^(Godot Engine|$)'
exit "${PIPESTATUS[0]}"
