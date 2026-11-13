"""Dump a Bosca Ceol (.ceol, v3 text format) project: tempo, instruments, patterns, arrangement.

    python3 tools/audio/parse_ceol.py tools/audio/reference/canavar_escape.ceol

Used to pull the tempo / key / motifs out of the team's chase music (canavar_escape).
Note numbers are printed as Bosca note indexes and as note names (index 0 = C).
"""
import sys

NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]


def main(path):
    d = [int(x) for x in open(path).read().strip().rstrip(",").split(",")]
    it = iter(d)
    r = lambda: next(it)  # noqa: E731
    ver, swing, eff, effv, bpm, plen, blen = [r() for _ in range(7)]
    print(f"version {ver} swing {swing} effect {eff}/{effv} bpm {bpm} pattern_len {plen} bar_len {blen}")
    for k in range(r()):
        ins = [r() for _ in range(6)]
        print(f"instrument {k}: voice={ins[0]} type={ins[1]} palette={ins[2]} cutoff={ins[3]} res={ins[4]} vol={ins[5]}")
    for p in range(r()):
        key, scale, ins, pal, nn = [r() for _ in range(5)]
        notes = sorted(([r() for _ in range(4)] for _ in range(nn)), key=lambda n: n[2])
        if r():
            [r() for _ in range(96)]
        txt = " ".join(f"{n[2]}:{NAMES[n[0] % 12]}{n[0] // 12}(len{n[1]})" for n in notes)
        print(f"pattern {p} key {key} scale {scale} instrument {ins}: {txt}")
    length, loop_start, loop_end = r(), r(), r()
    print(f"arrangement: {length} bars, loop {loop_start}-{loop_end}")
    for bar in range(length):
        print(f"  bar {bar:2d}: {[x for x in (r() for _ in range(8)) if x >= 0]}")


if __name__ == "__main__":
    main(sys.argv[1])
