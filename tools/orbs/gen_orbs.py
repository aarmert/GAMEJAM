#!/usr/bin/env python3
"""Generate the pixel-art "soul wisp" orb sprite sheets (no PIL needed).

Run from the repo root:  python3 tools/orbs/gen_orbs.py
Writes assets/orbs/orb_dash.png and assets/orbs/orb_double_jump.png.

Sheet layout (32x32 frames, 8 columns x 2 rows):
  row 0: 0-5 idle shimmer, 6-7 unused
  row 1: 8 spent (dim outline), 9-10 respawn pop, 11-15 pickup burst
1 art pixel = 1 world pixel (same density as the player sprites, scale 1).
"""
import math, os, struct, sys, zlib

F = 32            # frame size
COLS, ROWS = 8, 2
CX, CY = 16, 18   # body centre inside a frame
R = 6.6           # body radius

def hexc(h, a=255):
    h = h.lstrip('#')
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)

PALETTES = {
    # cool cyan-teal spirit, outline leans to the cave's indigo
    "dash": dict(
        outline=hexc('#1f2a4d'), dark=hexc('#2c6f8e'), mid=hexc('#47aec2'),
        light=hexc('#8be3dc'), core=hexc('#effff9'), halo=hexc('#6fd6d6'),
        spent=hexc('#5b7d96'),
    ),
    # warm pale gold spirit, outline leans to plum so it sits on violet rock
    "double_jump": dict(
        outline=hexc('#47263f'), dark=hexc('#b07a4c'), mid=hexc('#e8c06e'),
        light=hexc('#f8e4a8'), core=hexc('#fffbea'), halo=hexc('#f5d88c'),
        spent=hexc('#9a8270'),
    ),
}

# inner symbols ('#' = core colour, '+' = light rim) centred on the body
SYMBOLS = {
    # forward streak: speed line + arrow head
    "dash": [
        "...#...",
        "....#..",
        "######.",
        "....#..",
        "...#...",
    ],
    # stacked upward chevrons (double jump)
    "double_jump": [
        "..#..",
        ".#.#.",
        "#...#",
        "..#..",
        ".#.#.",
        "#...#",
    ],
}

# ------------------------------------------------------------------ png
def write_png(path, w, h, px):
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        for x in range(w):
            raw.extend(px[y * w + x])
    def chunk(t, d):
        c = struct.pack('>I', len(d)) + t + d
        return c + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    data = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0))
    data += chunk(b'IDAT', zlib.compress(bytes(raw), 9)) + chunk(b'IEND', b'')
    with open(path, 'wb') as f:
        f.write(data)

# ------------------------------------------------------------------ shapes
def wisp_mask(sway, tip_y, r=R):
    """Set of (x,y) inside a teardrop wisp: round body + flame tip curling by `sway`."""
    m = set()
    for y in range(F):
        for x in range(F):
            px, py = x + 0.5, y + 0.5
            if (px - CX) ** 2 + (py - CY) ** 2 <= r * r:
                m.add((x, y)); continue
            if tip_y <= py < CY:
                t = (CY - py) / (CY - tip_y)          # 0 at centre .. 1 at tip
                half = r * (1 - t) ** 1.6
                cx = CX + sway * t * t
                if abs(px - cx) <= half:
                    m.add((x, y))
    return m

def outline_of(m):
    o = set()
    for (x, y) in m:
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            q = (x + dx, y + dy)
            if q not in m:
                o.add(q)
    return o

def ring(radius, thick=1.0):
    s = set()
    for y in range(F):
        for x in range(F):
            d = math.hypot(x + 0.5 - CX, y + 0.5 - CY)
            if radius - thick < d <= radius:
                s.add((x, y))
    return s

class Frame:
    def __init__(self):
        self.p = {}
    def put(self, xy, c):
        x, y = xy
        if 0 <= x < F and 0 <= y < F:
            self.p[(x, y)] = c
    def put_if_empty(self, xy, c):
        if xy not in self.p:
            self.put(xy, c)

def with_alpha(c, a):
    return (c[0], c[1], c[2], a)

def draw_symbol(fr, kind, pal, dy=0, colour=None):
    sym = SYMBOLS[kind]
    h, w = len(sym), len(sym[0])
    ox = CX - w // 2
    oy = CY - h // 2 + dy
    for j, row in enumerate(sym):
        for i, ch in enumerate(row):
            if ch == '#':
                fr.put((ox + i, oy + j), colour or pal['core'])

def draw_wisp(fr, kind, pal, sway, tip_y, phase):
    m = wisp_mask(sway, tip_y)
    o = outline_of(m)
    # soft round pixel halo (pulses with the shimmer phase); never on top of the body
    a1 = [70, 95, 110, 85][phase]
    for (x, y) in ring(R + 2.6, 1.2):
        fr.put((x, y), with_alpha(pal['halo'], a1))
    for (x, y) in ring(R + 3.8, 1.0):
        if (x + y + phase) % 3 == 0:
            fr.put((x, y), with_alpha(pal['halo'], a1 // 2))
    # body gets the dark outline; the flame tip gets a soft glowing edge instead,
    # so it reads as a flickering wisp flame, not a stem
    tip_cut = CY - R + 1.5
    for q in o:
        if q[1] + 0.5 < tip_cut:
            fr.put(q, with_alpha(pal['mid'], 150))
        else:
            fr.put(q, pal['outline'])
    lx, ly = CX - 2.5, CY - 3.5           # light from upper left
    for (x, y) in m:
        d_light = math.hypot(x + 0.5 - lx, y + 0.5 - ly)
        d_edge = R - math.hypot(x + 0.5 - CX, y + 0.5 - CY)
        if y + 0.5 < CY - R + 0.5:      # flame tip pixels
            t = (CY - (y + 0.5)) / (CY - tip_y)
            c = pal['light'] if t < 0.55 else pal['core']
        elif d_edge < 1.3 and (x + 0.5 > CX - 1 or y + 0.5 > CY + 1):
            c = pal['dark']
        elif d_light < 3.2:
            c = pal['light']
        else:
            c = pal['mid']
        fr.put((x, y), c)
    # specular glint (upper left), blinks on shimmer frames
    fr.put((CX - 4, CY - 4), pal['core'])
    if phase in (1, 2):
        fr.put((CX - 3, CY - 5), pal['core'])
    # light rim around the symbol so it reads at small size
    draw_symbol(fr, kind, pal)

def draw_mote(fr, pal, x, y, big=False):
    fr.put((x, y), pal['core'] if big else pal['light'])

def frame_idle(kind, pal, i):
    fr = Frame()
    sway = [0, 2, 3, 2, 0, -2][i]
    tip = [4, 3, 3, 4, 5, 4][i]
    draw_wisp(fr, kind, pal, sway, tip, i % 4)
    # two motes drifting up around the wisp
    mx = [CX + 8, CX + 8, CX + 9, CX + 9, CX + 8, CX + 8][i]
    my = [CY + 3, CY + 1, CY - 1, CY - 3, CY - 5, CY - 7][i]
    draw_mote(fr, pal, mx, my, big=(i < 3))
    j = (i + 3) % 6
    mx2 = [CX - 9, CX - 9, CX - 10, CX - 10, CX - 9, CX - 9][j]
    my2 = [CY + 3, CY + 1, CY - 1, CY - 3, CY - 5, CY - 7][j]
    draw_mote(fr, pal, mx2, my2, big=(j < 3))
    return fr

def frame_spent(kind, pal):
    fr = Frame()
    m = wisp_mask(0, 9, r=R)
    o = outline_of(m)
    for (x, y) in o:
        fr.put((x, y), with_alpha(pal['spent'], 235))
    for (x, y) in m:   # very faint fill so it is a "hollow shell"
        fr.put((x, y), with_alpha(pal['outline'], 70))
    draw_symbol(fr, kind, pal, colour=with_alpha(pal['spent'], 150))
    return fr

def frame_pop(kind, pal, i):
    fr = Frame()
    if i == 0:   # bright seed + cross sparkle
        for q in wisp_mask(0, 13, r=3.4):
            fr.put(q, pal['core'])
        for q in outline_of(wisp_mask(0, 13, r=3.4)):
            fr.put(q, pal['light'])
        for d in (6, 7):
            for dx, dy in ((d, 0), (-d, 0), (0, d), (0, -d)):
                fr.put((CX + dx, CY + dy), pal['light'] if d == 6 else with_alpha(pal['halo'], 140))
    else:        # full flash silhouette, slightly oversized, fading to wisp next frame
        m = wisp_mask(0, 5, r=R + 1)
        for q in outline_of(m):
            fr.put(q, with_alpha(pal['halo'], 150))
        for q in m:
            fr.put(q, pal['light'])
        for q in wisp_mask(0, 9, r=R - 2):
            fr.put(q, pal['core'])
        draw_symbol(fr, kind, pal, colour=pal['mid'])
    return fr

def frame_burst(kind, pal, i):
    """Pickup burst, drawn on its own layer over the (spent) wisp."""
    fr = Frame()
    radius = [5, 8, 11, 13, 14][i]
    cols = [pal['core'], pal['core'], pal['light'], pal['mid'], with_alpha(pal['mid'], 150)]
    c = cols[i]
    for (x, y) in ring(radius, 1.0 if i < 4 else 0.8):
        ang = math.atan2(y + 0.5 - CY, x + 0.5 - CX)
        seg = int((ang + math.pi) / (2 * math.pi) * 16)
        if i >= 2 and seg % 2 == 1:
            continue                       # ring breaks into dashes as it grows
        fr.put((x, y), c)
    if i == 0:
        for q in wisp_mask(0, 10, r=R - 1):
            fr.put(q, pal['light'])
    # 8 sparks flying out on the diagonals / axes
    sr = [3, 6, 9, 12, 14][i]
    for k in range(8):
        a = k * math.pi / 4 + math.pi / 8
        x = int(round(CX + math.cos(a) * sr - 0.5))
        y = int(round(CY + math.sin(a) * sr - 0.5))
        if i < 4:
            fr.put((x, y), pal['core'] if i < 2 else pal['light'])
    return fr

def build(kind):
    pal = PALETTES[kind]
    W, H = F * COLS, F * ROWS
    img = [(0, 0, 0, 0)] * (W * H)
    frames = {}
    for i in range(6):
        frames[i] = frame_idle(kind, pal, i)
    frames[8] = frame_spent(kind, pal)
    frames[9] = frame_pop(kind, pal, 0)
    frames[10] = frame_pop(kind, pal, 1)
    for i in range(5):
        frames[11 + i] = frame_burst(kind, pal, i)
    for idx, fr in frames.items():
        ox, oy = (idx % COLS) * F, (idx // COLS) * F
        for (x, y), c in fr.p.items():
            img[(oy + y) * W + ox + x] = c
    return W, H, img

def main():
    root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
    out = os.path.join(root, 'assets', 'orbs')
    os.makedirs(out, exist_ok=True)
    for kind in PALETTES:
        W, H, img = build(kind)
        p = os.path.join(out, 'orb_%s.png' % kind)
        write_png(p, W, H, img)
        print('wrote', p)
    # optional upscaled preview for eyeballing: python3 gen_orbs.py --preview DIR
    if '--preview' in sys.argv:
        d = sys.argv[sys.argv.index('--preview') + 1]
        os.makedirs(d, exist_ok=True)
        for kind in PALETTES:
            W, H, img = build(kind)
            s = 8
            bg = [hexc('#5d5a8a'), hexc('#1c2a1e')]   # cave lavender / dark forest
            big = []
            for yy in range(H * s * 2):
                y = (yy // s) % H
                b = bg[(yy // s) // H]
                for xx in range(W * s):
                    c = img[y * W + xx // s]
                    a = c[3] / 255
                    big.append(tuple(int(c[k] * a + b[k] * (1 - a)) for k in range(3)) + (255,))
            write_png(os.path.join(d, 'preview_%s.png' % kind), W * s, H * s * 2, big)

if __name__ == '__main__':
    main()
