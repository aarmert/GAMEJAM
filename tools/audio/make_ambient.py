"""Render seamless ambient beds to res://audio/ambient/*.ogg (fully synthesized, original).

    python3 tools/audio/make_ambient.py

forest_ambient : wind gusts (periodic FFT noise), crickets, distant owl, birds, low creature growl
cave_ambient   : low drone + rumble, water drips with echo, rare distant rock shifts
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from synth import (SR, adsr, circular_delay, circular_reverb, colored_noise, exp_decay, fft_filter,  # noqa: E402
                   normalize_lufs, osc, repo_root, save_ogg)

OUT = os.path.join(repo_root(), "audio", "ambient")
AMBIENT_LUFS = -27.0


def add_wrapped(buf, start, sig, pan=0.0, vol=1.0):
    n = buf.shape[1]
    idx = (np.arange(len(sig)) + int(start)) % n
    l = vol * np.sqrt(0.5 * (1 - pan))
    r = vol * np.sqrt(0.5 * (1 + pan))
    np.add.at(buf[0], idx, sig * l)
    np.add.at(buf[1], idx, sig * r)


def lfo(n, cycles, phase=0.0):
    """Sine LFO with an integer number of cycles over the loop -> seamless."""
    t = np.arange(n) / n
    return 0.5 + 0.5 * np.sin(2 * np.pi * (cycles * t + phase))


def forest(length_s=60.0, seed=21):
    rng = np.random.default_rng(seed)
    n = int(length_s * SR)
    buf = np.zeros((2, n))
    # --- wind: two noise bands with independent gust LFOs, slightly different per channel
    for ch in range(2):
        low = colored_noise(n, lo=80, hi=600, tilt=-1.5, seed=100 + ch)
        high = colored_noise(n, lo=500, hi=2500, tilt=-1.0, seed=200 + ch)
        g1 = 0.35 + 0.65 * lfo(n, 5, 0.1 * ch) ** 2 * lfo(n, 2, 0.3)
        g2 = 0.2 + 0.8 * lfo(n, 7, 0.5 + 0.13 * ch) ** 3 * lfo(n, 3, 0.7)
        buf[ch] += low * g1 * 0.5 + high * g2 * 0.18
    # --- crickets: chirp trains (~4.6 kHz) in 2 spots, come and go
    for k, (pan, f0) in enumerate(((-0.6, 4600), (0.55, 4250))):
        t = 0.0
        while t < length_s:
            burst = int(rng.uniform(0.25, 0.45) * SR)
            tt = np.arange(burst) / SR
            car = osc("sine", f0 + rng.uniform(-60, 60), burst)
            am = (np.sin(2 * np.pi * 28 * tt) > 0.2).astype(float)
            sig = car * am * adsr(burst, 0.02, 0.05, 0.9, 0.05)
            amp = 0.045 * (0.5 + 0.5 * np.sin(2 * np.pi * (t / length_s * 2 + k * 0.4)))
            add_wrapped(buf, t * SR, sig, pan, amp)
            t += rng.uniform(0.6, 1.4)
    # --- distant owl: "hoo... hoo-hoo" (sine + slight vibrato), heavily reverbed
    for t0, pan in ((9.0, -0.4), (33.5, 0.5), (51.0, -0.2)):
        for dt, ln, f in ((0.0, 0.45, 390), (0.75, 0.22, 360), (1.05, 0.5, 370)):
            m = int(ln * SR)
            tt = np.arange(m) / SR
            fr = f * (1 + 0.04 * np.sin(np.pi * tt / ln)) * (1 + 0.004 * np.sin(2 * np.pi * 6 * tt))
            sig = osc("sine", fr, m) * adsr(m, 0.06, 0.1, 0.8, 0.12)
            add_wrapped(buf, (t0 + dt) * SR, fft_filter(sig, hi=900), pan, 0.06)
    # --- a few birds: fast chirps (pitch sweeps)
    for _ in range(9):
        t0 = rng.uniform(0, length_s)
        pan = rng.uniform(-0.8, 0.8)
        f_hi = rng.uniform(2500, 4200)
        for j in range(rng.integers(2, 5)):
            m = int(rng.uniform(0.05, 0.09) * SR)
            tt = np.arange(m) / m
            fr = f_hi * (1 - 0.35 * tt) if j % 2 == 0 else f_hi * (0.7 + 0.3 * tt)
            sig = osc("sine", fr, m) * np.sin(np.pi * tt) ** 2
            add_wrapped(buf, (t0 + j * 0.11) * SR, sig, pan, 0.025)
    # --- something big and far away growls (low filtered noise swell), twice per loop
    for t0 in (20.0, 44.0):
        m = int(3.0 * SR)
        g = colored_noise(m, lo=40, hi=220, tilt=-2, seed=int(t0))
        g *= np.sin(np.pi * np.arange(m) / m) ** 2 * (1 + 0.5 * np.sin(2 * np.pi * 7 * np.arange(m) / SR))
        add_wrapped(buf, t0 * SR, g, 0.0, 0.12)
    buf = np.stack([circular_reverb(c, 2.5, 0.3, damp_hz=4000) for c in buf])
    return buf


def drip(rng):
    m = int(0.12 * SR)
    t = np.arange(m) / SR
    f0 = rng.uniform(900, 1700)
    fr = f0 * (1 + 0.9 * (1 - np.exp(-t / 0.02)))  # quick upward 'plink'
    s = osc("sine", fr, m) * exp_decay(m, 0.025)
    s[: int(0.002 * SR)] += osc("noise", 15000, int(0.002 * SR)) * 0.3
    return s


def cave(length_s=60.0, seed=33):
    rng = np.random.default_rng(seed)
    n = int(length_s * SR)
    buf = np.zeros((2, n))
    # --- low drone: E1/B1-ish sine stack with very slow beating + brown-noise rumble
    t = np.arange(n) / SR
    for ch in range(2):
        drone = (np.sin(2 * np.pi * 41.2 * t + ch) * 0.5 + np.sin(2 * np.pi * 61.75 * t) * 0.25 +
                 np.sin(2 * np.pi * 82.6 * t + 0.3 * ch) * 0.12)
        drone *= 0.6 + 0.4 * lfo(n, 3, 0.25 * ch)
        rumble = colored_noise(n, lo=25, hi=180, tilt=-2.0, seed=300 + ch) * (0.5 + 0.5 * lfo(n, 4, 0.6))
        air = colored_noise(n, lo=300, hi=1500, tilt=-1.0, seed=400 + ch) * (0.3 + 0.7 * lfo(n, 2, 0.1 + 0.2 * ch))
        buf[ch] += drone * 0.35 + rumble * 0.5 + air * 0.06
    # --- drips: a couple of 'regular' drip spots + random ones
    for spot_pan, period in ((-0.5, 2.7), (0.6, 4.1)):
        tt = rng.uniform(0, period)
        while tt < length_s:
            add_wrapped(buf, tt * SR, drip(rng), spot_pan, 0.22)
            tt += period * rng.uniform(0.9, 1.1)
    for _ in range(10):
        add_wrapped(buf, rng.uniform(0, length_s) * SR, drip(rng), rng.uniform(-0.9, 0.9), 0.15)
    # --- distant rock shifts / pebbles
    for t0 in (17.0, 41.0):
        for k in range(rng.integers(4, 8)):
            m = int(0.05 * SR)
            s = osc("noise", rng.uniform(2000, 5000), m, seed=k) * exp_decay(m, 0.012)
            add_wrapped(buf, (t0 + k * rng.uniform(0.05, 0.18)) * SR, fft_filter(s, hi=2500), rng.uniform(-0.3, 0.3), 0.12)
    wet = np.stack([circular_delay(c, 0.31, 0.35, 0.4, taps=6) for c in buf])
    return np.stack([circular_reverb(c, 3.8, 0.5, damp_hz=2200) for c in wet])


if __name__ == "__main__":
    for name, fn, lufs in (("forest_ambient", forest, AMBIENT_LUFS), ("cave_ambient", cave, AMBIENT_LUFS)):
        a = normalize_lufs(fn(), lufs, peak_db=-6.0)
        p = os.path.join(OUT, name + ".ogg")
        save_ogg(p, a, quality=4)
        print(f"{name}: {a.shape[1] / SR:.1f} s -> {p}")
