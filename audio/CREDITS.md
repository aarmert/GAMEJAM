# Audio credits & licensing

## Third-party sounds

| Files in this repo | Source | Author | License |
|---|---|---|---|
| `audio/footsteps/grass_0..4.wav` | `footstep_grass_000..004.ogg` from **Impact Sounds** (v1.0): https://kenney.nl/assets/impact-sounds | Kenney (www.kenney.nl) | CC0 1.0: http://creativecommons.org/publicdomain/zero/1.0/ |
| `audio/footsteps/stone_0..4.wav` | `footstep_concrete_000..004.ogg` from **Impact Sounds** (v1.0): https://kenney.nl/assets/impact-sounds | Kenney (www.kenney.nl) | CC0 1.0 |

The footsteps were edited with `tools/audio/process_footsteps.py`: trimmed to 0.12–0.20 s, band-limited,
stone pitched down about 12 %, held at 14.7 kHz and quantised to 8-bit (light bitcrush), then peak-normalised.
CC0 does not require attribution; we credit Kenney anyway.

## Original audio (made for this game)

Everything else under `audio/` is original. It was synthesised from scratch with the numpy scripts in
`tools/audio/`, with no samples involved:

| File | Generator | Notes |
|---|---|---|
| `music/menu_theme.ogg` | `make_music.py` (`menu`) | 80 bpm, E minor/Phrygian, 48 s loop |
| `music/forest_theme.ogg` | `make_music.py` (`forest`) | 120 bpm, E Phrygian/minor, 64 s loop (3_part + level2) |
| `music/lantern_cave.ogg` | `make_music.py` (`lantern_cave`) | 60 bpm, E pedal, 64 s loop (level1_2) |
| `music/ending_sting.ogg` | `make_music.py` (`ending`) | 9 s one-shot, F → E major resolution |
| `ambient/forest_ambient.ogg` | `make_ambient.py` | wind, crickets, owl, birds, distant growl (60 s loop) |
| `ambient/cave_ambient.ogg` | `make_ambient.py` | drone, rumble, drips, pebbles (60 s loop) |
| `sfx/*.wav` | `make_sfx.py` | jump, orb_jump, land, dash, orb_dash, hurt, death, heal, checkpoint, pickup, lantern_pickup, lantern_on/off/empty, ui_hover/click/start, whoosh |

### Tracks based on the team's chase music (canavar_escape)

The chase music `music_sound_gamejam/music/canavar_escape.wav` was made by the team in Bosca Ceol.
Its project file is kept at `tools/audio/reference/canavar_escape.ceol`, and
`tools/audio/parse_ceol.py` dumps its contents. The new tracks borrow its material:

- tempo 120 bpm: the forest theme uses the same tempo, the menu 2/3 of it (80) and the lantern cave half (60)
- lead motif `E F D# . E . G# D` (16th notes):
  - **forest_theme** plays it literally as its hook
  - **menu_theme** plays it augmented (stretched in time)
  - **lantern_cave** plays it 16× slower, in fragments
  - **ending_sting** opens with an F–E / D#–E variation
- half-step pad swing B ↔ C, and the E–F rub:
  - forest bass line (E→F neighbour note)
  - lantern-cave drone (E–F, C–B)
  - the death SFX (ends on an E/F cluster)

## Re-rendering

```
python3 tools/audio/make_music.py        # or: make_music.py forest
python3 tools/audio/make_ambient.py
python3 tools/audio/make_sfx.py
python3 tools/audio/process_footsteps.py /path/to/kenney_impact-sounds/Audio
```

You need Python 3, numpy and ffmpeg (with libvorbis). Music is normalised to about -17 LUFS (lantern cave -18,
sting -16), ambience to -27 LUFS, and SFX are peak-normalised. Mix levels are set in
`scripts/audio/audio_manager.gd` and on the Music/SFX/Ambient buses in `default_bus_layout.tres`.

## Not used

The older files in `music_sound_gamejam/sounds/` (`running_on_grass.mp3`, `running_on_stone ...mp3`,
`heavy-walking.mp3`) have no recorded source or license, so the new system does not use them.
