"""Turn Kenney 'Impact Sounds' (CC0) footsteps into short, lightly bit-crushed game footsteps.

    # 1) download https://kenney.nl/assets/impact-sounds and unzip it somewhere
    # 2) python3 tools/audio/process_footsteps.py /path/to/kenney_impact-sounds/Audio

Output: res://audio/footsteps/{grass,stone}_N.wav
  grass  <- footstep_grass_000..004   (forest grass / dirt = "toprak")
  stone  <- footstep_concrete_000..004 (cave stone = "tas"), pitched down a bit for a rockier feel
"""
import os
import subprocess
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from synth import SR, fft_filter, normalize_peak, quantize, repo_root, sample_hold, write_wav  # noqa: E402

OUT = os.path.join(repo_root(), "audio", "footsteps")

SETS = {
    # out name: (source prefix, keep seconds, resample ratio (<1 = lower pitch), hi-cut Hz, peak dB)
    "grass": ("footstep_grass", 0.20, 1.0, 7000, -6.0),
    "stone": ("footstep_concrete", 0.14, 0.88, 6000, -6.0),
}


def load(path):
    raw = subprocess.run(["ffmpeg", "-v", "quiet", "-i", path, "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.float32).astype(np.float64)


def process(x, keep, ratio, hicut, peak):
    # trim leading silence, keep the transient + short tail
    start = max(0, int(np.argmax(np.abs(x) > 0.02 * np.abs(x).max())) - int(0.002 * SR))
    x = x[start:start + int(keep / ratio * SR)]
    if ratio != 1.0:  # simple resample = pitch + speed change
        src = np.arange(len(x))
        x = np.interp(np.arange(0, len(x) - 1, ratio), src, x)
    x = fft_filter(np.pad(x, (0, 2048)), lo=60, hi=hicut)[: len(x)]
    fade = int(len(x) * 0.5)
    x[-fade:] *= np.linspace(1, 0, fade) ** 2
    x = quantize(sample_hold(x / (np.abs(x).max() + 1e-9), 3), 8)  # 14.7 kHz hold + 8 bit
    return normalize_peak(x, peak)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    src_dir = sys.argv[1]
    os.makedirs(OUT, exist_ok=True)
    for out_name, (prefix, keep, ratio, hicut, peak) in SETS.items():
        files = sorted(f for f in os.listdir(src_dir) if f.startswith(prefix) and f.endswith(".ogg"))
        for i, f in enumerate(files):
            y = process(load(os.path.join(src_dir, f)), keep, ratio, hicut, peak)
            p = os.path.join(OUT, f"{out_name}_{i}.wav")
            write_wav(p, y)
            print(f"{f} -> {p} ({len(y) / SR:.3f} s)")
