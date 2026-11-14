#!/bin/bash
# tools/trials/replay.sh <chapter file> [--replay file] [--room id] [--trace N]
#   headless, deterministic (--fixed-fps 60). Exit code 0 = every room cleared.
# Screenshots of a replay: TRIALS_DISPLAY=<n> tools/trials/replay.sh <chapter> --shots /tmp/dir --every 20
cd "$(dirname "$0")/../.." || exit 2
if [[ " $* " == *" --shots "* ]]; then
  D=${TRIALS_DISPLAY:-95}
  timeout 600 ~/tools/gjtools/xrun.sh "$D" ~/tools/godot/godot --path . --rendering-driver opengl3 --audio-driver Dummy \
    --resolution 1152x648 --fixed-fps 60 -s tools/trials/replay.gd -- "$@" 2>&1 | grep -E '^(room|RESULT|REPLAY|ERROR|NOTE|    \[)|SCRIPT ERROR|Parse Error'
else
  timeout 600 ~/tools/godot/godot --headless --path . --audio-driver Dummy --fixed-fps 60 -s tools/trials/replay.gd -- "$@" 2>&1 \
    | grep -E '^(room|RESULT|REPLAY|ERROR|NOTE|    \[)|SCRIPT ERROR|Parse Error|at: '
fi
exit "${PIPESTATUS[0]}"
