"""Tiny 8-bit / Bosca-Ceol-style synth used to render the game's music, ambience and SFX.

Only needs numpy + an ffmpeg binary on PATH (for loudness measurement and ogg encoding).
Everything here is original code written for this project.

Key ideas
- Song: a fixed-length circular buffer. Notes/echo/reverb that run past the end wrap to
  the start, so the rendered file loops seamlessly.
- Instruments are plain dicts (wave, duty, ADSR, vibrato, volume, pan).
- Melodies are written as compact strings: "E5:4 F5:2 -:2" = note:length-in-steps, '-' rest.
"""
import os
import re
import subprocess
import tempfile
import wave

import numpy as np

SR = 44100
RNG = np.random.default_rng(1234)

NOTE_INDEX = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def note_to_midi(name):
    """'E4' -> 64, 'D#5' -> 75, 'Bb3' -> 58."""
    m = re.fullmatch(r"([A-G])([#b]?)(-?\d)", name)
    if not m:
        raise ValueError(name)
    n = NOTE_INDEX[m.group(1)] + {"#": 1, "b": -1, "": 0}[m.group(2)]
    return 12 * (int(m.group(3)) + 1) + n


def midi_hz(m):
    return 440.0 * 2.0 ** ((m - 69) / 12.0)


def parse_line(text):
    """'E5:4 F5:2 -:2' -> [(step_offset, length, midi or None), ...]"""
    out, t = [], 0
    for tok in text.split():
        name, ln = tok.split(":")
        ln = float(ln)
        out.append((t, ln, None if name == "-" else note_to_midi(name)))
        t += ln
    return out, t


# ---------------------------------------------------------------- oscillators

def osc(kind, freq, n, duty=0.5, seed=None):
    """freq: scalar or array (Hz). Naive (aliased) waveforms on purpose -> chip grit."""
    f = np.broadcast_to(np.asarray(freq, dtype=np.float64), (n,))
    phase = np.cumsum(f / SR)
    frac = phase % 1.0
    if kind == "pulse":
        return np.where(frac < duty, 1.0, -1.0)
    if kind == "tri":  # NES-like 4-bit stepped triangle
        tri = 2.0 * np.abs(2.0 * frac - 1.0) - 1.0
        return np.round(tri * 7.5) / 7.5
    if kind == "sine":
        return np.sin(2 * np.pi * phase)
    if kind == "saw":
        return 2.0 * frac - 1.0
    if kind == "noise":  # sample & hold noise, 'freq' = hold rate
        rng = np.random.default_rng(seed) if seed is not None else RNG
        idx = np.floor(phase).astype(np.int64)
        vals = rng.choice([-1.0, 1.0], size=idx[-1] + 2) * rng.uniform(0.6, 1.0, idx[-1] + 2)
        return vals[idx - idx[0]]
    raise ValueError(kind)


def adsr(n, a=0.005, d=0.05, s=0.7, r=0.05, gate=None):
    """Envelope of n samples; note held for 'gate' seconds then released for r seconds."""
    t = np.arange(n) / SR
    gate = n / SR - r if gate is None else gate
    env = np.where(t < a, t / max(a, 1e-6), 1.0)
    dec = np.clip((t - a) / max(d, 1e-6), 0, 1)
    env = np.where(t >= a, 1.0 - (1.0 - s) * dec, env)
    rel = np.clip((t - gate) / max(r, 1e-6), 0, 1)
    env = env * np.where(t > gate, 1.0 - rel, 1.0)
    return np.clip(env, 0, 1)


def exp_decay(n, tau):
    return np.exp(-np.arange(n) / SR / tau)


def quantize(x, bits=8):
    q = 2 ** (bits - 1)
    return np.round(x * q) / q


def sample_hold(x, factor):
    if factor <= 1:
        return x
    idx = (np.arange(len(x)) // factor) * factor
    return x[idx]


# --------------------------------------------------------- spectral helpers

def fft_filter(x, lo=None, hi=None, slope=4.0):
    """Smooth band-pass in the frequency domain (circular -> loop safe)."""
    n = len(x)
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(n, 1 / SR)
    g = np.ones_like(f)
    if lo:
        g *= 1.0 / (1.0 + (lo / np.maximum(f, 1e-3)) ** slope)
    if hi:
        g *= 1.0 / (1.0 + (f / hi) ** slope)
    return np.fft.irfft(X * g, n)


def colored_noise(n, lo=None, hi=None, tilt=0.0, seed=0):
    """Periodic noise (length n loops perfectly). tilt<0 -> darker (-1 pink, -2 brown)."""
    rng = np.random.default_rng(seed)
    f = np.fft.rfftfreq(n, 1 / SR)
    mag = np.ones_like(f)
    mag[1:] = (f[1:] / 1000.0) ** (tilt / 2.0)
    mag[0] = 0
    if lo:
        mag *= 1.0 / (1.0 + (lo / np.maximum(f, 1e-3)) ** 4)
    if hi:
        mag *= 1.0 / (1.0 + (f / hi) ** 4)
    spec = mag * np.exp(2j * np.pi * rng.random(len(f)))
    y = np.fft.irfft(spec, n)
    return y / (np.abs(y).max() + 1e-12)


def circular_reverb(x, seconds=1.6, mix=0.25, damp_hz=3500, seed=7):
    """Circular convolution with a decaying-noise impulse response (wraps for loops)."""
    n = len(x)
    ln = min(int(seconds * SR), n)
    rng = np.random.default_rng(seed)
    ir = rng.standard_normal(ln) * np.exp(-np.arange(ln) / SR / (seconds / 6.9))
    ir = fft_filter(np.pad(ir, (0, max(0, 4096))), hi=damp_hz)[:ln]
    ir[: int(0.012 * SR)] *= np.linspace(0, 1, int(0.012 * SR))  # pre-delay-ish
    ir /= np.sqrt((ir ** 2).sum()) + 1e-12
    full = np.zeros(n)
    full[:ln] = ir
    wet = np.fft.irfft(np.fft.rfft(x) * np.fft.rfft(full), n)
    return x * (1 - mix * 0.5) + wet * mix


def linear_reverb(x, seconds=1.6, mix=0.25, damp_hz=3500, seed=7):
    """Same, but non-circular (pads the tail). For one-shot sounds."""
    pad = int(seconds * SR)
    y = np.concatenate([x, np.zeros(pad)])
    return circular_reverb(y, seconds, mix, damp_hz, seed)


def circular_delay(x, delay_s, feedback=0.4, mix=0.3, taps=8, damp=0.85):
    d = int(delay_s * SR)
    wet = np.zeros_like(x)
    cur = x.copy()
    for k in range(1, taps + 1):
        cur = np.roll(cur, d) * feedback
        if damp < 1.0:
            cur = fft_filter(cur, hi=6000 * damp ** k) if k <= 3 else cur
        wet += cur
    return x + wet * mix


# ------------------------------------------------------------------ Song

class Song:
    """Circular stereo buffer measured in steps (16th notes by default)."""

    def __init__(self, bpm, bars, steps_per_bar=16, steps_per_beat=4, loop=True, tail_s=0.0):
        self.bpm = bpm
        self.bars = bars
        self.spb = steps_per_bar
        self.step_s = 60.0 / bpm / steps_per_beat
        self.length_s = bars * steps_per_bar * self.step_s
        self.n = int(round(self.length_s * SR)) + (0 if loop else int(tail_s * SR))
        self.loop = loop
        self.buses = {}

    def bus(self, name):
        if name not in self.buses:
            self.buses[name] = np.zeros((2, self.n))
        return self.buses[name]

    def _mix(self, sig, start_s, vol, pan, bus):
        buf = self.bus(bus)
        i0 = int(round(start_s * SR))
        l = vol * np.sqrt(0.5 * (1 - pan))
        r = vol * np.sqrt(0.5 * (1 + pan))
        idx = np.arange(i0, i0 + len(sig))
        if self.loop:
            idx %= self.n
        else:
            keep = idx < self.n
            idx, sig = idx[keep], sig[keep]
        if len(sig) <= self.n:  # indices unique -> fast path
            buf[0][idx] += sig * l
            buf[1][idx] += sig * r
        else:
            np.add.at(buf[0], idx, sig * l)
            np.add.at(buf[1], idx, sig * r)

    def tone(self, start_step, len_steps, midi, inst, bus="main", vel=1.0):
        dur = len_steps * self.step_s
        rel = inst.get("r", 0.05)
        n = int((dur + rel) * SR)
        t = np.arange(n) / SR
        f = midi_hz(midi + inst.get("transpose", 0)) * np.ones(n)
        if inst.get("vib"):
            depth, rate, delay = inst["vib"]
            ramp = np.clip((t - delay) / 0.15, 0, 1)
            f *= 2 ** (depth / 12 * np.sin(2 * np.pi * rate * t) * ramp)
        if inst.get("slide"):  # semitones over first 'slide_t' seconds
            st, sl_t = inst["slide"]
            f *= 2 ** (st / 12 * np.clip(1 - t / sl_t, 0, 1))
        if inst.get("arp"):  # chiptune chord arpeggio offsets, speed in Hz
            offs, rate = inst["arp"]
            k = (np.floor(t * rate).astype(int)) % len(offs)
            f *= 2 ** (np.asarray(offs)[k] / 12)
        sig = osc(inst["wave"], f, n, inst.get("duty", 0.5))
        if inst.get("duty_sweep"):
            d0, d1 = inst["duty_sweep"]
            duty = d0 + (d1 - d0) * np.clip(t / max(dur, 1e-3), 0, 1)
            ph = np.cumsum(f / SR) % 1
            sig = np.where(ph < duty, 1.0, -1.0)
        env = adsr(n, inst.get("a", 0.005), inst.get("d", 0.08), inst.get("s", 0.7), rel, gate=dur)
        if inst.get("trem"):
            depth, rate = inst["trem"]
            env = env * (1 - depth * 0.5 * (1 + np.sin(2 * np.pi * rate * t)))
        self._mix(sig * env, start_step * self.step_s, inst.get("vol", 0.3) * vel, inst.get("pan", 0.0), bus)

    def line(self, bar, text, inst, bus="main", vel=1.0, octave=0):
        notes, _ = parse_line(text)
        base = bar * self.spb
        for off, ln, m in notes:
            if m is not None:
                self.tone(base + off, ln, m + 12 * octave, inst, bus, vel)

    def drum(self, step, kind, vol=1.0, bus="drums", pan=0.0):
        sig = drum_hit(kind)
        self._mix(sig, step * self.step_s, vol, pan, bus)

    def raw(self, start_s, sig, vol=1.0, pan=0.0, bus="main"):
        self._mix(np.asarray(sig, dtype=np.float64), start_s, vol, pan, bus)

    def render(self, bus_fx=None):
        out = np.zeros((2, self.n))
        for name, buf in self.buses.items():
            b = buf
            if bus_fx and name in bus_fx:
                b = np.stack([bus_fx[name](b[0]), bus_fx[name](b[1])])
            out += b
        return out


def drum_hit(kind, seed=None):
    if kind == "kick":
        n = int(0.16 * SR)
        t = np.arange(n) / SR
        f = 45 + 110 * np.exp(-t / 0.025)
        s = osc("tri", f, n) * exp_decay(n, 0.06)
        s[: int(0.004 * SR)] += osc("noise", 8000, int(0.004 * SR), seed=1) * 0.5
        return s * 0.9
    if kind == "softkick":
        n = int(0.22 * SR)
        t = np.arange(n) / SR
        f = 40 + 50 * np.exp(-t / 0.03)
        return osc("sine", f, n) * exp_decay(n, 0.08) * 0.9
    if kind == "snare":
        n = int(0.18 * SR)
        nz = osc("noise", 11000, n, seed=2) * exp_decay(n, 0.05)
        tone = osc("tri", 190 * np.exp(-np.arange(n) / SR / 0.08), n) * exp_decay(n, 0.04)
        return (nz * 0.7 + tone * 0.5) * 0.8
    if kind == "hat":
        n = int(0.04 * SR)
        nz = osc("noise", 22000, n, seed=3)
        nz = np.diff(nz, prepend=0) * 0.5
        return nz * exp_decay(n, 0.012) * 0.5
    if kind == "ohat":
        n = int(0.16 * SR)
        nz = np.diff(osc("noise", 22000, n, seed=4), prepend=0) * 0.5
        return nz * exp_decay(n, 0.06) * 0.4
    if kind == "tick":
        n = int(0.03 * SR)
        return osc("pulse", 2400, n, 0.25) * exp_decay(n, 0.006) * 0.3
    raise ValueError(kind)


# --------------------------------------------------------- loudness / IO

def write_wav(path, stereo, sr=SR):
    x = np.asarray(stereo)
    if x.ndim == 1:
        x = x[None, :]
    data = (np.clip(x.T, -1, 1) * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(x.shape[0])
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(data.tobytes())


def measure_lufs(stereo):
    with tempfile.TemporaryDirectory() as td:
        p = os.path.join(td, "m.wav")
        write_wav(p, np.clip(stereo, -1, 1))
        r = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", p, "-af", "ebur128=framelog=quiet",
                            "-f", "null", "-"], capture_output=True, text=True)
    m = re.findall(r"I:\s+(-?[\d.]+) LUFS", r.stderr)
    return float(m[-1]) if m else -70.0


def normalize_lufs(stereo, target, peak_db=-1.0):
    x = np.asarray(stereo, dtype=np.float64)
    pk = np.abs(x).max() + 1e-12
    x = x / pk * 0.5  # pre-scale so measurement isn't clipped
    for _ in range(3):
        cur = measure_lufs(x)
        x = x * 10 ** ((target - cur) / 20)
    lim = 10 ** (peak_db / 20)
    over = np.abs(x) > lim * 0.8
    if over.any():  # gentle soft-knee limiter on peaks only
        knee = lim * 0.8
        s = np.sign(x)
        a = np.abs(x)
        x = np.where(over, s * (knee + (lim - knee) * np.tanh((a - knee) / (lim - knee))), x)
    return x


def normalize_peak(x, peak_db=-3.0):
    x = np.asarray(x, dtype=np.float64)
    return x / (np.abs(x).max() + 1e-12) * 10 ** (peak_db / 20)


def save_ogg(path, stereo, quality=5):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with tempfile.TemporaryDirectory() as td:
        p = os.path.join(td, "t.wav")
        write_wav(p, stereo)
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", p, "-c:a", "libvorbis", "-q:a", str(quality), path],
                       check=True)


def save_sfx(path, mono, peak_db=-3.0, crush=None):
    """crush=(hold_factor, bits) for a light pixel-art bitcrush."""
    x = np.asarray(mono, dtype=np.float64)
    thr = np.abs(x).max() * 10 ** (-54 / 20)  # trim inaudible tail
    last = int(np.nonzero(np.abs(x) > thr)[0][-1]) if (np.abs(x) > thr).any() else len(x) - 1
    x = x[: min(len(x), last + int(0.01 * SR))].copy()
    if crush:
        x = quantize(sample_hold(x, crush[0]), crush[1])
    fade = min(len(x), int(0.004 * SR))
    x[-fade:] *= np.linspace(1, 0, fade)
    x = normalize_peak(x, peak_db)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    write_wav(path, x)


def repo_root():
    return os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
