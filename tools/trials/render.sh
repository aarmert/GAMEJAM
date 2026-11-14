#!/bin/bash
# tools/trials/render.sh <chapter file> <out_dir> [--room id] [--no-grid]
# Renders every room to PNG through a private Xvfb. Set TRIALS_DISPLAY to pick the X display number
# (default 95; use a number nobody else uses).
cd "$(dirname "$0")/../.." || exit 2
D=${TRIALS_DISPLAY:-95}
timeout 300 ~/tools/gjtools/xrun.sh "$D" ~/tools/godot/godot --path . --rendering-driver opengl3 --audio-driver Dummy \
  --resolution 1280x720 -s tools/trials/render.gd -- "$@" 2>&1 | grep -E '^(saved|ERROR|  |SCRIPT ERROR)|Parse Error'
exit "${PIPESTATUS[0]}"
