"""Render sfxr-style 8-bit sound effects to res://audio/sfx/*.wav (all original / synthesized).

    python3 tools/audio/make_sfx.py
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from synth import SR, adsr, exp_decay, fft_filter, linear_reverb, note_to_midi, midi_hz, osc, repo_root, save_sfx  # noqa: E402

OUT = os.path.join(repo_root(), "audio", "sfx")
CRUSH = (2, 8)  # sample-hold x2 (22 kHz) + 8-bit -> light pixel-art grit


def secs(s):
    return int(s * SR)


def sweep(f0, f1, dur, wave="pulse", duty=0.5, curve=1.0):
    n = secs(dur)
    t = np.linspace(0, 1, n) ** curve
    return osc(wave, f0 * (f1 / f0) ** t, n, duty)


def notes_seq(names, step, wave="pulse", duty=0.5, decay=0.08, overlap=1.0):
    total = secs(step * len(names) + decay * 4)
    out = np.zeros(total)
    for i, nm in enumerate(names):
        n = secs(step * overlap + decay * 3)
        s = osc(wave, midi_hz(note_to_midi(nm)), n, duty) * adsr(n, 0.002, decay, 0.3, decay, gate=step * overlap)
        a = secs(i * step)
        out[a:a + n] += s[: len(out) - a]
    return out


def noise_burst(dur, rate, lo=None, hi=None, tau=None, seed=0):
    n = secs(dur)
    s = osc("noise", rate, n, seed=seed)
    if lo or hi:
        s = fft_filter(s, lo=lo, hi=hi)
    return s * (exp_decay(n, tau) if tau else 1.0)


def jump():
    s = sweep(260, 720, 0.14, duty=0.5, curve=0.6) * adsr(secs(0.14), 0.002, 0.06, 0.6, 0.04)
    return s


def orb_jump():  # double-jump orb: brighter sweep + sparkle arpeggio
    a = sweep(330, 990, 0.12, duty=0.25, curve=0.5) * adsr(secs(0.12), 0.002, 0.05, 0.6, 0.03)
    b = notes_seq(["E6", "G#6", "B6", "E7"], 0.035, duty=0.125, decay=0.04)
    out = np.zeros(max(len(a), len(b) + secs(0.06)))
    out[: len(a)] += a
    out[secs(0.06): secs(0.06) + len(b)] += b * 0.6
    return linear_reverb(out, 0.4, 0.2)


def land():
    n = secs(0.12)
    t = np.arange(n) / SR
    thump = osc("tri", 55 + 90 * np.exp(-t / 0.02), n) * exp_decay(n, 0.04)
    dust = noise_burst(0.12, 6000, hi=2500, tau=0.025, seed=5) * 0.5
    return thump + dust


def dash():
    n = secs(0.26)
    t = np.arange(n) / n
    nz = osc("noise", 14000, n, seed=9)
    # band sweep high->low by mixing two filtered versions
    hi = fft_filter(nz, lo=2500, hi=7000)
    lo = fft_filter(nz, lo=400, hi=2000)
    env = np.sin(np.pi * np.clip(t * 1.3, 0, 1)) ** 0.6 * (1 - t)
    s = (hi * (1 - t) + lo * t) * env
    s += sweep(700, 180, 0.26, duty=0.125) * env * 0.12
    return s


def orb_dash():
    d = dash()
    c = notes_seq(["B5", "E6", "B6"], 0.04, duty=0.25, decay=0.05)
    out = np.zeros(len(d) + secs(0.1))
    out[: len(d)] += d
    out[: len(c)] += c * 0.45
    return out


def hurt():
    n = secs(0.24)
    t = np.arange(n) / SR
    f = 520 * np.exp(-t / 0.12) + 90
    f *= 1 + 0.08 * np.sign(np.sin(2 * np.pi * 30 * t))
    s = osc("pulse", f, n, 0.5) * adsr(n, 0.001, 0.05, 0.7, 0.08)
    s += noise_burst(0.24, 8000, tau=0.04, seed=12) * 0.4
    return s


def death():  # descending E-Phrygian run with tremolo, ends on the low E-F rub
    names = ["E5", "D5", "C5", "B4", "A4", "G4", "F4", "E4"]
    s = notes_seq(names, 0.09, duty=0.5, decay=0.06)
    n = secs(1.0)
    t = np.arange(n) / SR
    rub = (osc("pulse", midi_hz(note_to_midi("E3")), n, 0.25) + osc("pulse", midi_hz(note_to_midi("F3")), n, 0.25))
    rub *= adsr(n, 0.01, 0.2, 0.6, 0.6, gate=0.4) * (0.6 + 0.4 * np.sin(2 * np.pi * 9 * t)) * 0.5
    out = np.zeros(secs(0.09 * 8) + n)
    out[: len(s)] += s
    out[secs(0.09 * 8): secs(0.09 * 8) + n] += rub
    return linear_reverb(out, 0.8, 0.25)


def heal():  # small soft tick-up for each heal tick
    return notes_seq(["B5", "E6"], 0.05, wave="tri", decay=0.07) * 0.9


def checkpoint():  # hopeful E-major arpeggio (the 'safe' version of the canavar E)
    s = notes_seq(["E5", "G#5", "B5", "E6"], 0.07, duty=0.25, decay=0.12, overlap=1.6)
    t = notes_seq(["E4", "B4"], 0.14, wave="tri", decay=0.2, overlap=2)
    out = np.zeros(max(len(s), len(t)))
    out[: len(s)] += s
    out[: len(t)] += t * 0.8
    return linear_reverb(out, 1.0, 0.3)


def pickup():  # skill get fanfare
    s = notes_seq(["B4", "E5", "G#5", "B5", "E6", "G#6"], 0.055, duty=0.5, decay=0.06)
    hold = osc("pulse", midi_hz(note_to_midi("B6")), secs(0.35), 0.25) * adsr(secs(0.35), 0.002, 0.1, 0.5, 0.2)
    out = np.zeros(len(s) + len(hold))
    out[: len(s)] += s * 0.8
    out[secs(0.055 * 6): secs(0.055 * 6) + len(hold)] += hold * 0.6
    return linear_reverb(out, 0.9, 0.25)


def lantern_pickup():  # warmer, slower: lantern found
    s = notes_seq(["E5", "B5", "E6", "F#6", "G#6"], 0.09, wave="tri", decay=0.15, overlap=1.5)
    sh = notes_seq(["E7", "B6", "E7", "G#7"], 0.06, duty=0.125, decay=0.05)
    out = np.zeros(len(s) + secs(0.2))
    out[: len(s)] += s
    out[secs(0.2): secs(0.2) + len(sh)] += sh * 0.25
    return linear_reverb(out, 1.4, 0.35)


def lantern_on():  # click + flame 'fwoomp' rising
    click = noise_burst(0.012, 16000, tau=0.003, seed=20)
    n = secs(0.35)
    t = np.arange(n) / n
    fl = fft_filter(osc("noise", 9000, n, seed=21), lo=300, hi=2500) * np.sin(np.pi * t) ** 1.5 * (0.4 + 0.6 * t)
    tone = sweep(300, 600, 0.35, wave="tri") * np.sin(np.pi * t) * 0.3
    out = np.zeros(n)
    out[: len(click)] += click
    out += fl * 0.6 + tone
    return out


def lantern_off():
    click = noise_burst(0.012, 16000, tau=0.003, seed=22)
    n = secs(0.25)
    t = np.arange(n) / n
    fl = fft_filter(osc("noise", 9000, n, seed=23), lo=200, hi=1500) * (1 - t) ** 2
    tone = sweep(500, 220, 0.25, wave="tri") * (1 - t) * 0.3
    out = np.zeros(n)
    out[: len(click)] += click
    out += fl * 0.5 + tone
    return out


def lantern_empty():  # battery/oil ran out: sputter
    out = np.zeros(secs(0.4))
    for i, a in enumerate((0.0, 0.09, 0.2)):
        b = noise_burst(0.06, 5000, lo=300, hi=2000, tau=0.02, seed=30 + i) * (1 - i * 0.3)
        out[secs(a): secs(a) + len(b)] += b
    out[: secs(0.4)] += sweep(400, 120, 0.4, wave="tri") * exp_decay(secs(0.4), 0.15) * 0.4
    return out


def ui_hover():
    n = secs(0.04)
    return osc("pulse", 1320, n, 0.25) * exp_decay(n, 0.012)


def ui_click():
    n = secs(0.07)
    return osc("pulse", 880, n, 0.5) * adsr(n, 0.001, 0.02, 0.5, 0.03) + \
        np.concatenate([np.zeros(secs(0.025)), osc("pulse", 1320, n - secs(0.025), 0.5) * exp_decay(n - secs(0.025), 0.02)])


def ui_start():
    s = notes_seq(["E5", "B5", "E6"], 0.06, duty=0.5, decay=0.08, overlap=1.4)
    return linear_reverb(s, 0.6, 0.25)


def whoosh():
    n = secs(0.8)
    t = np.arange(n) / n
    nz = osc("noise", 12000, n, seed=40)
    lo = fft_filter(nz, lo=150, hi=900)
    hi = fft_filter(nz, lo=900, hi=4000)
    env = np.sin(np.pi * t) ** 2
    mixk = np.sin(np.pi * t)
    return (lo * (1 - mixk) + hi * mixk) * env


SFX = {
    "jump": (jump, -6), "orb_jump": (orb_jump, -5), "land": (land, -6), "dash": (dash, -5),
    "orb_dash": (orb_dash, -5), "hurt": (hurt, -4), "death": (death, -3), "heal": (heal, -9),
    "checkpoint": (checkpoint, -4), "pickup": (pickup, -3), "lantern_pickup": (lantern_pickup, -3),
    "lantern_on": (lantern_on, -6), "lantern_off": (lantern_off, -7), "lantern_empty": (lantern_empty, -6),
    "ui_hover": (ui_hover, -12), "ui_click": (ui_click, -7), "ui_start": (ui_start, -5), "whoosh": (whoosh, -8),
}

if __name__ == "__main__":
    for name, (fn, pk) in SFX.items():
        x = fn()
        path = os.path.join(OUT, name + ".wav")
        save_sfx(path, x, peak_db=pk, crush=CRUSH)
        print(f"{name}: {len(x) / SR:.2f} s")
