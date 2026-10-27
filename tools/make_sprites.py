"""Generates flat-cartoon unit portraits as SVGs: art/units/<id>.svg (256x256, facing right).

Placeholder art built from a few body plans (quadruped, bird, reptile, round, seal, upright,
humanoid, serpent) plus features. Replace any file with real art of the same name and the game
picks it up. Enemies are flipped in-game to face left.

    python tools/make_sprites.py
"""
import math
import os

OUT = "art/units"
INK = "#1b1b1b"
SW = 4
G = 236  # ground line


# --- color + svg helpers -------------------------------------------------------------------------

def _rgb(h):
    h = h.lstrip("#")
    return [int(h[i:i + 2], 16) for i in (0, 2, 4)]


def shade(h, f):
    """f < 1 darkens, f > 1 mixes toward white."""
    c = _rgb(h)
    c = [v * f for v in c] if f < 1 else [v + (255 - v) * (f - 1) for v in c]
    return "#%02x%02x%02x" % tuple(max(0, min(255, round(v))) for v in c)


def _st(fill, stroke=True, width=SW):
    s = f'fill="{fill}"'
    if stroke:
        s += f' stroke="{INK}" stroke-width="{width}" stroke-linejoin="round" stroke-linecap="round"'
    return s


def E(cx, cy, rx, ry, fill, rot=0, stroke=True):
    t = f' transform="rotate({rot} {cx:.1f} {cy:.1f})"' if rot else ""
    return f'<ellipse cx="{cx:.1f}" cy="{cy:.1f}" rx="{rx:.1f}" ry="{ry:.1f}" {_st(fill, stroke)}{t}/>'


def C(cx, cy, r, fill, stroke=True):
    return f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="{r:.1f}" {_st(fill, stroke)}/>'


def P(pts, fill, stroke=True):
    return f'<polygon points="{" ".join(f"{x:.1f},{y:.1f}" for x, y in pts)}" {_st(fill, stroke)}/>'


def PATH(d, fill="none", stroke=True, width=SW):
    return f'<path d="{d}" {_st(fill, stroke, width)}/>'


def LINE(d, color, width):
    """A thick colored stroke with an ink outline (tails, legs, antlers)."""
    return (f'<path d="{d}" fill="none" stroke="{INK}" stroke-width="{width + 2 * SW}" stroke-linecap="round" stroke-linejoin="round"/>'
            f'<path d="{d}" fill="none" stroke="{color}" stroke-width="{width}" stroke-linecap="round" stroke-linejoin="round"/>')


def R(x, y, w, h, r, fill, stroke=True):
    return f'<rect x="{x:.1f}" y="{y:.1f}" width="{w:.1f}" height="{h:.1f}" rx="{r:.1f}" {_st(fill, stroke)}/>'


def eye(x, y, r=6, kind="normal"):
    if kind == "red":
        return C(x, y, r + 1, "#ff3020") + C(x, y, r * 0.45, "#ffd0a0", False)
    if kind == "yellow":
        return C(x, y, r + 1, "#ffd030") + E(x + 1, y, r * 0.25, r * 0.8, INK, stroke=False)
    if kind == "dead":
        return C(x, y, r, "#e8f0d0") + C(x + 1, y + 1, r * 0.3, INK, False)
    return C(x, y, r, "white") + C(x + r * 0.3, y, r * 0.55, INK, False) + C(x + r * 0.45, y - r * 0.3, r * 0.2, "white", False)


def svg(body):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">{"".join(body)}</svg>'


# --- quadruped -----------------------------------------------------------------------------------

def quad(color, body=(60, 30), legs=(14, 42), head=24, snout=16, ears="pointy", tail="bushy", neck=0,
         marks=(), extras=(), muzzle=None, eyes="normal", collar=False, tail_color=None, ear_inner="#e9a0a0",
         leg_color=None):
    bw, bh = body
    lw, ll = legs
    cx = 112
    cy = G - ll - bh * 0.55
    dark = shade(color, 0.72)
    light = shade(color, 1.45)
    legc = leg_color or color
    hx, hy = cx + bw * 0.92, cy - bh * 0.6 - neck
    hr = head
    out = []

    if "hump" in extras:
        out.append(E(cx + bw * 0.45, cy - bh * 0.55, bw * 0.45, bh * 0.75, shade(color, 0.85)))
    # far legs
    xs = [cx - bw * 0.62, cx - bw * 0.38, cx + bw * 0.4, cx + bw * 0.64]
    for i in (1, 3):
        out.append(R(xs[i] - lw / 2 - 4, cy + bh * 0.1, lw, G - cy - bh * 0.1, lw / 2, shade(legc, 0.7)))
    # tail
    tx, ty = cx - bw * 0.95, cy - bh * 0.25
    tc = tail_color or color
    if tail == "bushy":
        out.append(E(tx - 20, ty - 12, 28, 13, tc, -30))
        if "tail_tip" in marks:
            out.append(E(tx - 42, ty - 25, 9, 7, "#f4f0e6", -30))
    elif tail == "ringed":
        out.append(E(tx - 20, ty - 10, 30, 12, tc, -25))
        for k in range(3):
            a = math.radians(-25)
            px, py = tx - 6 - k * 13, ty - 4 - k * 6
            out.append(E(px - 10 * math.cos(a), py, 4, 11, INK, -25, stroke=False))
    elif tail == "down":
        out.append(E(tx - 12, ty + 22, 12, 30, tc, 25))
    elif tail == "thin":
        out.append(LINE(f"M{tx + 6},{ty} Q{tx - 40},{ty + 10} {tx - 46},{ty - 30}", tc, 7))
    elif tail == "pink":
        out.append(LINE(f"M{tx + 6},{ty + 4} Q{tx - 30},{ty + 30} {tx - 52},{ty + 10}", "#e8a6a6", 7))
    elif tail == "long":
        out.append(LINE(f"M{tx + 6},{ty} Q{tx - 34},{ty + 50} {tx - 50},{ty + 6}", tc, 10))
        if "tail_dark_tip" in marks:
            out.append(C(tx - 50, ty + 6, 7, INK, False))
    elif tail == "tuft":
        out.append(LINE(f"M{tx + 6},{ty} Q{tx - 30},{ty + 40} {tx - 40},{ty + 20}", tc, 7))
        out.append(E(tx - 42, ty + 22, 8, 10, shade(color, 0.5), 20))
    elif tail == "up":
        out.append(E(tx - 2, ty - 42, 22, 44, tc, -18))
        out.append(E(tx + 2, ty - 46, 7, 36, "#f4f4f4", -18, stroke=False))
    elif tail == "stub":
        out.append(C(tx + 2, ty - 2, 10, tc))
    elif tail == "short":
        out.append(E(tx - 6, ty - 6, 12, 8, tc, -30))
    elif tail == "flat":
        out.append(E(tx - 18, ty + 18, 26, 11, shade(color, 0.8), 15))
    elif tail == "point":
        out.append(P([(tx + 6, ty - 6), (tx - 60, ty + 30), (tx + 6, ty + 14)], tc))
    # body
    out.append(E(cx, cy, bw, bh, color))
    if "shaggy" in marks:
        out.append(E(cx + bw * 0.45, cy - bh * 0.05, bw * 0.55, bh * 1.02, shade(color, 0.75)))
    if "belly" in marks:
        out.append(E(cx + 4, cy + bh * 0.5, bw * 0.75, bh * 0.38, light, stroke=False))
    if "stripes" in marks:
        for k in range(5):
            x = cx - bw * 0.6 + k * bw * 0.3
            out.append(PATH(f"M{x},{cy - bh * 0.95} q8,{bh * 0.5} -2,{bh * 0.9}", "none", True, 6))
    if "spots" in marks:
        for (dx, dy) in [(-0.5, -0.3), (-0.15, -0.5), (0.2, -0.25), (0.5, -0.45), (-0.35, 0.2), (0.05, 0.15), (0.4, 0.2)]:
            out.append(C(cx + dx * bw, cy + dy * bh, 5, shade(color, 0.45)))
    if "back_stripe" in marks:
        out.append(E(cx, cy - bh * 0.62, bw * 0.92, bh * 0.28, "#f4f4f4", stroke=False))
    if "grey_back" in marks:
        out.append(E(cx, cy - bh * 0.5, bw * 0.95, bh * 0.5, "#c9c9c4", stroke=False))
    if "armor" in marks:
        for k in range(4):
            x = cx - bw * 0.45 + k * bw * 0.3
            out.append(PATH(f"M{x},{cy - bh * 0.95} q-8,{bh} 0,{bh * 1.9}", "none", True, 3))
    if "spines" in extras:
        for k in range(7):
            x = cx - bw * 0.75 + k * bw * 0.25
            y = cy - bh * 0.85 + abs(k - 3) * 2
            out.append(P([(x - 7, y + 6), (x, y - 16), (x + 7, y + 6)], shade(color, 0.6)))
    # near legs
    for i in (0, 2):
        out.append(R(xs[i] - lw / 2, cy + bh * 0.1, lw, G - cy - bh * 0.1, lw / 2, legc))
        out.append(E(xs[i] + 3, G - 3, lw * 0.65, 5, shade(legc, 0.6)))
    # neck
    if neck > 0:
        out.append(P([(cx + bw * 0.55, cy - bh * 0.6), (hx - hr * 0.6, hy - hr * 0.2), (hx + hr * 0.3, hy + hr * 0.6),
                      (cx + bw * 0.95, cy + bh * 0.1)], color))
    if "mane" in extras:
        for k in range(5):
            x = cx + bw * 0.25 + k * 9
            y = cy - bh * 0.95 - k * (neck / 5 + 3)
            out.append(P([(x - 6, y + 8), (x - 2, y - 14), (x + 6, y + 8)], shade(color, 0.55)))
    # antlers / horns behind head
    if "antlers" in extras or "antlers_big" in extras:
        big = 1.5 if "antlers_big" in extras else 1.0
        bx, by = hx - hr * 0.2, hy - hr * 0.8
        a = "#e3d2a8"
        out.append(LINE(f"M{bx},{by} q{-14 * big},{-30 * big} {-6 * big},{-60 * big}", a, 6))
        for k in (1, 2, 3):
            px, py = bx - 7 * big + k * 1.5, by - k * 17 * big
            out.append(LINE(f"M{px},{py} l{14 * big},{-12 * big}", a, 5))
    if "palmate" in extras:
        bx, by = hx - hr * 0.3, hy - hr * 0.7
        out.append(P([(bx, by), (bx - 50, by - 22), (bx - 58, by - 46), (bx - 40, by - 38), (bx - 34, by - 54),
                      (bx - 22, by - 40), (bx - 12, by - 56), (bx - 2, by - 34)], "#d9c7a0"))
    if "horns_curved" in extras:
        out.append(LINE(f"M{hx - hr * 0.3},{hy - hr * 0.75} q-10,-18 4,-30", "#3a332c", 8))
    if "horns_goat" in extras:
        out.append(LINE(f"M{hx},{hy - hr * 0.8} q-30,-30 -40,6", "#c8b890", 10))
    if "horns_devil" in extras:
        out.append(P([(hx - 6, hy - hr * 0.7), (hx - 10, hy - hr * 1.7), (hx + 6, hy - hr * 0.85)], "#e6dcc8"))
        out.append(P([(hx + 8, hy - hr * 0.8), (hx + 10, hy - hr * 1.75), (hx + 20, hy - hr * 0.7)], "#e6dcc8"))
    # ears behind head
    if ears == "floppy":
        out.append(E(hx - hr * 0.55, hy + hr * 0.15, hr * 0.32, hr * 0.75, dark, 18))
    if ears == "long":
        out.append(E(hx - hr * 0.5, hy - hr * 1.5, hr * 0.26, hr * 0.95, color, -18))
        out.append(E(hx - hr * 0.1, hy - hr * 1.6, hr * 0.26, hr * 0.95, color, 6))
        out.append(E(hx - hr * 0.1, hy - hr * 1.6, hr * 0.12, hr * 0.7, ear_inner, 6, stroke=False))
    # head
    out.append(C(hx, hy, hr, light if "face_white" in marks else color))
    if "head_stripe" in marks:
        out.append(E(hx + hr * 0.1, hy - hr * 0.45, hr * 0.95, hr * 0.28, "#f4f4f4", -15, stroke=False))
    if "cheeks" in marks:
        out.append(C(hx + hr * 0.3, hy + hr * 0.35, hr * 0.45, light, False))
    if ears in ("pointy", "tufts"):
        out.append(P([(hx - hr * 0.7, hy - hr * 0.45), (hx - hr * 0.5, hy - hr * 1.5), (hx - hr * 0.05, hy - hr * 0.8)], color))
        out.append(P([(hx - hr * 0.6, hy - hr * 0.6), (hx - hr * 0.47, hy - hr * 1.2), (hx - hr * 0.22, hy - hr * 0.78)], ear_inner, False))
        out.append(P([(hx - hr * 0.1, hy - hr * 0.85), (hx + hr * 0.15, hy - hr * 1.55), (hx + hr * 0.45, hy - hr * 0.62)], color))
        if ears == "tufts":
            out.append(LINE(f"M{hx - hr * 0.5},{hy - hr * 1.5} l-2,-12", INK, 3))
            out.append(LINE(f"M{hx + hr * 0.15},{hy - hr * 1.55} l2,-12", INK, 3))
    elif ears == "round":
        out.append(C(hx - hr * 0.55, hy - hr * 0.8, hr * 0.36, color))
        out.append(C(hx - hr * 0.55, hy - hr * 0.8, hr * 0.18, ear_inner, False))
        out.append(C(hx + hr * 0.15, hy - hr * 0.95, hr * 0.34, color))
    elif ears == "big_round":
        out.append(C(hx - hr * 0.7, hy - hr * 0.75, hr * 0.55, color))
        out.append(C(hx - hr * 0.7, hy - hr * 0.75, hr * 0.3, "#f0e0e0", False))
        out.append(C(hx + hr * 0.25, hy - hr * 0.95, hr * 0.5, color))
    elif ears == "small":
        out.append(C(hx - hr * 0.5, hy - hr * 0.85, hr * 0.2, color))
    if "mask" in marks:
        out.append(E(hx + hr * 0.25, hy - hr * 0.12, hr * 0.62, hr * 0.27, INK, -8, stroke=False))
    if "eye_patch" in marks:
        out.append(C(hx + hr * 0.28, hy - hr * 0.18, hr * 0.32, shade(color, 0.4), False))
    # snout
    sx = hx + hr * 0.7
    if snout > 0:
        out.append(E(sx + snout * 0.35, hy + hr * 0.3, snout * 0.75 + hr * 0.25, hr * 0.42, muzzle or color))
        out.append(C(sx + snout * 0.9 + hr * 0.15, hy + hr * 0.18, 5, "#e8a6a6" if "pink_nose" in marks else INK, False))
    if "bill" in extras:
        out.append(E(hx + hr * 1.3, hy + hr * 0.25, hr * 0.85, hr * 0.32, "#3a3530", -4))
    if "tusks" in extras:
        out.append(LINE(f"M{sx + snout * 0.6},{hy + hr * 0.6} q8,-2 6,-18", "#f4efe0", 5))
    if "fangs" in extras:
        out.append(P([(sx + snout * 0.3, hy + hr * 0.62), (sx + snout * 0.4, hy + hr * 0.95), (sx + snout * 0.55, hy + hr * 0.62)], "white"))
        out.append(P([(sx + snout * 0.7, hy + hr * 0.62), (sx + snout * 0.8, hy + hr * 0.9), (sx + snout * 0.95, hy + hr * 0.62)], "white"))
    if "beard" in extras:
        out.append(P([(hx, hy + hr * 0.7), (hx + hr * 0.3, hy + hr * 1.6), (hx + hr * 0.6, hy + hr * 0.7)], shade(color, 0.5)))
    out.append(eye(hx + hr * 0.3, hy - hr * 0.18, max(5, hr * 0.2), eyes))
    if collar:
        out.append(LINE(f"M{hx - hr * 0.7},{hy + hr * 0.55} q{hr * 0.6},{hr * 0.4} {hr * 1.05},{hr * 0.15}", "#d23b3b", 8))
        out.append(C(hx - hr * 0.1, hy + hr * 0.95, 6, "#ffd34d"))
    return out


# --- bird ----------------------------------------------------------------------------------------

def bird(color, beak="short", beak_color="#e8b030", legs="short", neck=0, tail="normal", head_color=None,
         crest=False, wing=None, belly=None, size=1.0, leg_color="#d8a040", marks=()):
    s = size
    long_legs = legs == "long"
    cx, cy = 116, (140 if long_legs else 168)
    hx, hy = cx + 46 * s, cy - 42 * s - neck
    hr = 21 * s
    out = []
    if long_legs:
        for dx in (-6, 8):
            out.append(LINE(f"M{cx + dx},{cy + 20} L{cx + dx + 2},{G}", leg_color, 5))
    else:
        for dx in (-8, 8):
            out.append(LINE(f"M{cx + dx},{cy + 28 * s} L{cx + dx + 4},{G - 2}", leg_color, 5))
        out.append(LINE(f"M{cx - 8},{G - 2} l14,0 M{cx + 8},{G - 2} l14,0", leg_color, 4))
    if tail == "long":
        out.append(P([(cx - 40 * s, cy - 4), (cx - 112 * s, cy - 30 * s), (cx - 106 * s, cy - 14 * s), (cx - 36 * s, cy + 16)], shade(color, 0.75)))
    elif tail == "fan":
        out.append(P([(cx - 40 * s, cy), (cx - 86 * s, cy + 6), (cx - 84 * s, cy + 30 * s), (cx - 34 * s, cy + 18)], shade(color, 0.75)))
        out.append(E(cx - 78 * s, cy + 18 * s, 10, 12, "#c0583a", stroke=False))
    else:
        out.append(P([(cx - 40 * s, cy - 2), (cx - 82 * s, cy + 18 * s), (cx - 70 * s, cy + 30 * s), (cx - 32 * s, cy + 18)], shade(color, 0.75)))
    out.append(E(cx, cy, 50 * s, 32 * s, color, -18))
    if belly:
        out.append(E(cx + 10 * s, cy + 12 * s, 34 * s, 16 * s, belly, -18, stroke=False))
    out.append(E(cx - 8 * s, cy - 4 * s, 38 * s, 20 * s, wing or shade(color, 0.72), -12))
    if neck > 0:
        out.append(LINE(f"M{cx + 30 * s},{cy - 14 * s} Q{hx - 26},{hy + neck * 0.6} {hx},{hy}", head_color if head_color and "neck_head" in marks else color, 15 * s))
    if crest:
        out.append(P([(hx - hr * 0.6, hy - hr * 0.6), (hx - hr * 1.6, hy - hr * 1.5), (hx - hr * 0.2, hy - hr * 0.9)], shade(color, 0.6)))
    out.append(C(hx, hy, hr, head_color or color))
    bx, by = hx + hr * 0.75, hy + hr * 0.05
    if beak == "hook":
        out.append(P([(bx - 4, by - 9), (bx + 18 * s, by - 4), (bx + 16 * s, by + 10), (bx + 6, by + 6), (bx - 4, by + 8)], beak_color))
    elif beak == "long":
        out.append(P([(bx - 4, by - 6), (bx + 64 * s, by + 2), (bx - 4, by + 7)], beak_color))
    elif beak == "huge":
        out.append(PATH(f"M{bx - 6},{by - 14} Q{bx + 50},{by - 26} {bx + 66},{by + 6} Q{bx + 30},{by + 12} {bx - 6},{by + 12} Z", beak_color))
        out.append(PATH(f"M{bx + 50},{by - 12} Q{bx + 64},{by - 4} {bx + 66},{by + 6}", "none", True, 3))
    elif beak == "big":
        out.append(P([(bx - 6, by - 10), (bx + 36 * s, by - 2), (bx + 30 * s, by + 8), (bx - 6, by + 9)], beak_color))
    elif beak == "goose":
        out.append(E(bx + 10 * s, by + 2, 16 * s, 7 * s, beak_color))
    else:
        out.append(P([(bx - 4, by - 7), (bx + 20 * s, by), (bx - 4, by + 7)], beak_color))
    if "white_cheek" in marks:
        out.append(E(hx + hr * 0.2, hy + hr * 0.35, hr * 0.5, hr * 0.3, "#f0ece0", stroke=False))
    out.append(eye(hx + hr * 0.25, hy - hr * 0.2, 6 * s))
    if "eye_stripe" in marks:
        out.append(LINE(f"M{hx - hr * 0.6},{hy - hr * 0.25} L{hx + hr * 0.05},{hy - hr * 0.2}", INK, 4))
    return out


def owl(color, face="#d8c09a"):
    cx, cy = 128, 162
    out = [E(cx, cy, 50, 64, color)]
    out.append(E(cx - 44, cy + 6, 16, 44, shade(color, 0.7), 8))
    out.append(E(cx + 44, cy + 6, 16, 44, shade(color, 0.7), -8))
    out.append(E(cx, cy + 28, 30, 32, shade(color, 1.35), stroke=False))
    for k in range(3):
        out.append(PATH(f"M{cx - 16 + k * 16},{cy + 14} l4,6 l4,-6", "none", True, 3))
    out.append(P([(cx - 40, cy - 66), (cx - 34, cy - 104), (cx - 12, cy - 74)], color))
    out.append(P([(cx + 40, cy - 66), (cx + 34, cy - 104), (cx + 12, cy - 74)], color))
    out.append(C(cx, cy - 46, 40, face))
    for x in (cx - 16, cx + 16):
        out.append(C(x, cy - 50, 13, "#ffcc33"))
        out.append(C(x, cy - 50, 7, INK, False))
        out.append(C(x + 3, cy - 53, 2.5, "white", False))
    out.append(P([(cx - 6, cy - 36), (cx + 6, cy - 36), (cx, cy - 22)], "#3a3530"))
    for x in (cx - 16, cx + 16):
        out.append(LINE(f"M{x},{cy + 62} l-6,8 M{x},{cy + 62} l0,10 M{x},{cy + 62} l6,8", "#d8a040", 4))
    return out


# --- reptile / dragon ------------------------------------------------------------------------------

def reptile(color, snout=40, size=1.0, marks=(), wings=None, raised=False, eyes="normal"):
    s = size
    cx, cy = 116, 200
    dark = shade(color, 0.7)
    out = []
    if wings:
        out.append(P([(cx + 10, cy - 30), (cx - 70, cy - 150), (cx - 40, cy - 100), (cx - 20, cy - 130),
                      (cx - 6, cy - 86), (cx + 18, cy - 116), (cx + 30, cy - 34)], wings))
    out.append(P([(cx - 50 * s, cy - 10 * s), (cx - 122 * s, cy + 24 * s), (cx - 46 * s, cy + 16 * s)], color))
    for dx in (-36, 30):
        out.append(LINE(f"M{cx + dx * s},{cy + 10} l-8,{26 * s}", dark, 12 * s))
    out.append(E(cx, cy, 64 * s, 22 * s, color))
    for dx in (-24, 44):
        out.append(LINE(f"M{cx + dx * s},{cy + 10} l8,{26 * s}", color, 12 * s))
    if "scutes" in marks:
        for k in range(7):
            x = cx - 50 * s + k * 16 * s
            out.append(P([(x - 5, cy - 18 * s), (x, cy - 28 * s), (x + 5, cy - 18 * s)], dark))
    if "beads" in marks:
        for k, (dx, dy) in enumerate([(-40, -6), (-20, 4), (0, -8), (20, 4), (40, -6), (-30, 10), (10, 10)]):
            out.append(E(cx + dx * s, cy + dy * s, 9, 6, "#e0703a" if k % 2 else INK, stroke=False))
    hx, hy = cx + 62 * s, cy - 8 * s
    if raised:
        hx, hy = cx + 70 * s, cy - 80 * s
        out.append(LINE(f"M{cx + 40 * s},{cy - 6} Q{cx + 70 * s},{cy - 30 * s} {hx - 4},{hy + 8}", color, 22 * s))
    out.append(E(hx + snout * 0.5 * s, hy + 2, (20 + snout * 0.5) * s, 13 * s, color))
    out.append(LINE(f"M{hx + 4},{hy + 8 * s} L{hx + (snout + 14) * s},{hy + 6 * s}", INK, 2))
    if "teeth" in marks:
        for k in range(4):
            x = hx + 12 + k * 9 * s
            out.append(P([(x, hy + 7 * s), (x + 3, hy + 13 * s), (x + 6, hy + 7 * s)], "white", False))
    out.append(C(hx - 2, hy - 10 * s, 8 * s, color))
    out.append(eye(hx - 1, hy - 11 * s, 5 * s, eyes))
    return out


# --- round body (hedgehog, armadillo, pangolin, hamster, wombat) --------------------------------

def roundy(color, kind="plain", snout=14, ears="small", collar=False):
    cx, cy = 118, 182
    out = []
    if kind == "pangolin":
        out.append(P([(cx - 60, cy + 10), (cx - 120, cy + 50), (cx - 52, cy + 40)], color))
    for dx in (-36, 40):
        out.append(R(cx + dx - 8, cy + 22, 16, G - cy - 22, 8, shade(color, 0.7)))
    out.append(E(cx, cy, 72, 52 if kind != "hamster" else 56, color))
    if kind == "spines":
        for row in range(3):
            for k in range(7 - row):
                a = math.radians(200 + k * (140 / (6 - row)) + row * 6)
                r = 58 - row * 18
                x, y = cx + math.cos(a) * r, cy + math.sin(a) * (40 - row * 12)
                out.append(P([(x - 8, y + 4), (x + math.cos(a) * 22, y + math.sin(a) * 22), (x + 8, y + 4)], shade(color, 0.55)))
        out.append(E(cx + 50, cy + 18, 30, 24, "#d8c0a0", stroke=False))
    if kind == "armor":
        for k in range(5):
            x = cx - 44 + k * 22
            out.append(PATH(f"M{x},{cy - 46} q-10,46 0,92", "none", True, 3))
    if kind == "pangolin":
        for row in range(3):
            for k in range(5):
                x, y = cx - 50 + k * 24 + row * 6, cy - 34 + row * 22
                out.append(PATH(f"M{x - 12},{y} q12,14 24,0", shade(color, 0.75), True, 3))
    if kind == "hamster":
        out.append(E(cx + 10, cy + 22, 52, 28, "#f6ead8", stroke=False))
    for dx in (-20, 56):
        out.append(R(cx + dx - 8, cy + 26, 16, G - cy - 26, 8, color))
    hx, hy = cx + 62, cy + 2
    if ears == "round":
        out.append(C(hx - 12, hy - 26, 12, color))
        out.append(C(hx - 12, hy - 26, 6, "#e9a0a0", False))
    out.append(C(hx, hy, 24, color if kind != "spines" else "#d8c0a0"))
    if ears == "small":
        out.append(C(hx - 10, hy - 22, 7, color))
    out.append(E(hx + 18, hy + 6, 10 + snout * 0.5, 10, color if kind != "spines" else "#d8c0a0"))
    out.append(C(hx + 24 + snout * 0.5, hy + 4, 5, INK, False))
    out.append(eye(hx + 6, hy - 6, 5))
    if collar:
        out.append(LINE(f"M{hx - 20},{hy + 14} q16,14 30,4", "#d23b3b", 8))
        out.append(C(hx - 4, hy + 24, 6, "#ffd34d"))
    return out


# --- seal / otter --------------------------------------------------------------------------------

def seal(color, otter=False):
    out = []
    out.append(E(56, 222, 30, 10, shade(color, 0.7), -20))
    out.append(E(112, 200, 80, 30, color, -14))
    out.append(E(118, 214, 56, 14, shade(color, 1.3), -10, stroke=False))
    hx, hy = 188, 140 if not otter else 150
    out.append(P([(150, 190), (hx - 22, hy + 10), (hx + 16, hy + 14), (184, 200)], color))
    out.append(E(160, 226, 22, 9, shade(color, 0.7), 20))
    out.append(C(hx, hy, 26, shade(color, 1.4) if otter else color))
    if otter:
        out.append(C(hx - 18, hy - 20, 8, color))
        out.append(C(150, 186, 13, "#9a9a9a"))
    out.append(E(hx + 20, hy + 8, 12, 9, shade(color, 1.4) if otter else color))
    out.append(C(hx + 30, hy + 4, 5, INK, False))
    for k in range(3):
        out.append(LINE(f"M{hx + 22},{hy + 12 + k * 3} l20,{-2 + k * 4}", "#f4f4f4", 1))
    out.append(eye(hx + 6, hy - 6, 6))
    return out


# --- upright animals -----------------------------------------------------------------------------

def kangaroo(color):
    out = [LINE("M100,200 Q40,226 18,232", color, 18)]
    out.append(E(140, G - 4, 44, 9, shade(color, 0.7)))
    out.append(E(112, 186, 34, 40, color, 20))
    out.append(E(126, 138, 30, 52, color, 18))
    out.append(E(138, 150, 16, 34, shade(color, 1.4), 18, stroke=False))
    out.append(LINE("M150,124 q20,8 28,-4", color, 10))
    out.append(C(184, 116, 9, "#c0302a"))
    out.append(E(150, 70, 8, 22, color, -12))
    out.append(E(164, 70, 8, 22, color, 10))
    out.append(C(158, 92, 18, color))
    out.append(E(176, 98, 14, 9, color))
    out.append(C(188, 96, 4, INK, False))
    out.append(eye(162, 88, 5))
    return out


def meerkat(color):
    out = [LINE("M118,206 Q100,226 86,234", shade(color, 0.7), 8)]
    out.append(E(126, 160, 26, 62, color))
    out.append(E(132, 172, 14, 40, shade(color, 1.35), stroke=False))
    out.append(LINE("M134,140 q14,10 4,22", color, 9))
    for dx in (-10, 10):
        out.append(R(124 + dx - 7, 206, 14, 30, 7, color))
    out.append(C(132, 86, 22, color))
    out.append(C(118, 72, 7, INK, False))
    out.append(E(152, 92, 14, 9, color))
    out.append(C(165, 90, 4, INK, False))
    out.append(C(138, 82, 9, shade(color, 0.35), False))
    out.append(eye(138, 82, 5))
    return out


def macaque(color, face="#e0786a"):
    out = [E(118, 184, 52, 46, color)]
    out.append(E(170, 214, 26, 12, color))
    out.append(LINE("M140,170 q28,10 34,34", color, 14))
    out.append(C(148, 112, 34, color))
    out.append(E(160, 118, 22, 20, face))
    out.append(eye(164, 110, 5))
    out.append(C(176, 124, 3, INK, False))
    out.append(PATH("M160,132 q8,4 16,0", "none", True, 3))
    return out


# --- humanoids (zombies, cryptids) ---------------------------------------------------------------

def humanoid(skin, clothes=None, pants="#3a3a46", scale=1.0, lean=6, build="normal", head="zombie",
             wings=None, tail=None, eyes="dead", hair="#2a241e", fur=False, weapon=None, pose="reach",
             horn_light=False, marks=()):
    s = scale
    out = []
    sh = 8 if build == "ape" else 0  # hunch
    hip_y, sh_y = 170, 100 + sh
    tx = 116
    dark = shade(skin, 0.7)
    if wings == "bat":
        wc = shade(skin, 0.6)
        out.append(P([(tx + 4, sh_y + 4), (tx - 96, sh_y - 70), (tx - 70, sh_y - 10), (tx - 100, sh_y + 10),
                      (tx - 60, sh_y + 30), (tx - 76, sh_y + 60), (tx - 6, sh_y + 44)], wc))
    elif wings == "moth":
        out.append(E(tx - 40, sh_y + 6, 66, 40, "#5a4a44", -30))
        out.append(E(tx - 30, sh_y + 56, 46, 30, "#4a3c38", 20))
        out.append(C(tx - 52, sh_y - 4, 12, "#8a6a5a", False))
    if tail:
        out.append(LINE(f"M{tx - 20},{hip_y} Q{tx - 80},{hip_y + 10} {tx - 92},{hip_y - 40}", tail, 7))
        out.append(P([(tx - 100, hip_y - 46), (tx - 86, hip_y - 56), (tx - 84, hip_y - 38)], tail))
    # far leg + arm
    legw = 22 if build in ("muscle", "ape") else 18
    if build == "thin":
        legw = 11
    if pose == "run":
        out.append(LINE(f"M{tx + 8},{hip_y} L{tx - 24},{G - 6}", shade(pants, 0.7), legw))
        out.append(LINE(f"M{tx + 18},{sh_y + 10} L{tx - 10},{sh_y + 50}", shade(skin, 0.7), 14))
    else:
        out.append(R(tx + 6, hip_y - 6, legw, G - hip_y + 6, 8, shade(pants, 0.7)))
        out.append(LINE(f"M{tx + 22},{sh_y + 10} L{tx + 76},{sh_y + 18}", dark, 14 if build != "thin" else 8))
    if build == "skirt":
        out.append(P([(tx - 30, G), (tx + 4, sh_y + 10), (tx + 40, sh_y + 10), (tx + 70, G)], clothes or "#2f4a2f"))
    else:
        # near leg
        if pose == "run":
            out.append(LINE(f"M{tx + 10},{hip_y} L{tx + 40},{G - 10}", pants, legw))
        else:
            out.append(R(tx - 12, hip_y - 6, legw, G - hip_y + 6, 8, pants))
        if "hooves" in marks:
            out.append(R(tx - 14, G - 12, legw + 4, 12, 3, INK))
        # torso
        if build == "bloated":
            out.append(E(tx + 10, (sh_y + hip_y) / 2 + 8, 56, 58, skin))
            for (dx, dy) in [(-20, -10), (26, 6), (0, 30), (30, -26)]:
                out.append(C(tx + 10 + dx, (sh_y + hip_y) / 2 + dy, 9, "#fee761"))
        elif build in ("muscle", "ape"):
            out.append(P([(tx - 30, sh_y - 6), (tx + 56, sh_y - 6), (tx + 40, hip_y), (tx - 16, hip_y)], clothes or skin))
            if fur or build == "ape":
                for k in range(5):
                    x = tx - 20 + k * 16
                    out.append(PATH(f"M{x},{sh_y + 12} l-4,14", "none", True, 3))
        elif build == "thin":
            out.append(E(tx + 10, (sh_y + hip_y) / 2, 20, (hip_y - sh_y) / 2 + 4, clothes or skin))
        else:
            out.append(R(tx - 22, sh_y, 66, hip_y - sh_y + 6, 16, clothes or skin))
            if clothes:
                out.append(P([(tx - 22, hip_y - 6), (tx - 10, hip_y - 20), (tx + 4, hip_y - 4), (tx + 20, hip_y - 18), (tx + 44, hip_y - 4), (tx + 44, hip_y + 6), (tx - 22, hip_y + 6)], shade(clothes, 0.75)))
    # near arm
    aw = 18 if build in ("muscle", "ape") else (8 if build == "thin" else 14)
    if build == "ape":
        out.append(LINE(f"M{tx + 30},{sh_y + 12} Q{tx + 70},{sh_y + 50} {tx + 66},{sh_y + 100}", skin, aw))
        out.append(C(tx + 66, sh_y + 104, 12, shade(skin, 0.8)))
    elif pose == "run":
        out.append(LINE(f"M{tx + 24},{sh_y + 12} L{tx + 62},{sh_y + 40}", skin, aw))
    elif build != "skirt":
        out.append(LINE(f"M{tx + 26},{sh_y + 14} L{tx + 86},{sh_y + 26}", skin, aw))
        out.append(C(tx + 92, sh_y + 27, aw * 0.6, skin))
    if weapon == "axe":
        out.append(LINE(f"M{tx + 90},{sh_y + 60} L{tx + 96},{sh_y - 40}", "#7a5a3a", 8))
        out.append(P([(tx + 94, sh_y - 40), (tx + 130, sh_y - 52), (tx + 126, sh_y - 14), (tx + 96, sh_y - 20)], "#b8bcc0"))
    # head
    hx, hy = tx + 26 + (14 if build == "ape" else 0), sh_y - 28 + (6 if build == "ape" else 0)
    if head == "zombie":
        out.append(C(hx, hy, 26, skin))
        out.append(P([(hx - 26, hy - 4), (hx - 22, hy - 26), (hx - 6, hy - 30), (hx + 4, hy - 22), (hx + 16, hy - 28), (hx + 22, hy - 14), (hx + 4, hy - 16), (hx - 10, hy - 10)], hair))
        out.append(eye(hx + 12, hy - 2, 7, eyes))
        out.append(eye(hx - 4, hy + 2, 5, eyes))
        out.append(PATH(f"M{hx},{hy + 14} l5,-4 l5,5 l5,-4 l5,4", "none", True, 3))
    elif head == "wolf":
        out.append(P([(hx - 18, hy - 12), (hx - 14, hy - 44), (hx, hy - 20)], skin))
        out.append(P([(hx, hy - 20), (hx + 10, hy - 46), (hx + 16, hy - 16)], skin))
        out.append(C(hx, hy, 24, skin))
        out.append(E(hx + 30, hy + 8, 22, 11, skin))
        out.append(C(hx + 50, hy + 4, 5, INK, False))
        out.append(P([(hx + 24, hy + 16), (hx + 28, hy + 26), (hx + 32, hy + 16)], "white", False))
        out.append(P([(hx + 38, hy + 16), (hx + 42, hy + 25), (hx + 46, hy + 16)], "white", False))
        out.append(eye(hx + 8, hy - 6, 6, eyes))
    elif head == "goat":
        out.append(LINE(f"M{hx - 6},{hy - 18} q-34,-30 -40,10", "#d8c8a0", 10))
        out.append(E(hx + 8, hy + 2, 20, 28, skin, -20))
        out.append(P([(hx + 10, hy + 24), (hx + 16, hy + 50), (hx + 24, hy + 24)], shade(skin, 0.5)))
        out.append(eye(hx + 10, hy - 8, 6, eyes))
    elif head == "frog":
        out.append(E(hx + 6, hy + 4, 32, 22, skin))
        out.append(C(hx - 6, hy - 16, 11, skin))
        out.append(C(hx + 18, hy - 16, 11, skin))
        out.append(eye(hx - 4, hy - 16, 7, eyes))
        out.append(eye(hx + 20, hy - 16, 7, eyes))
        out.append(PATH(f"M{hx - 16},{hy + 10} Q{hx + 8},{hy + 22} {hx + 34},{hy + 8}", "none", True, 3))
    elif head == "lizard":
        out.append(C(hx, hy, 22, skin))
        out.append(E(hx + 28, hy + 6, 24, 12, skin))
        out.append(P([(hx - 20, hy - 10), (hx - 34, hy - 30), (hx - 10, hy - 20)], shade(skin, 0.7)))
        out.append(eye(hx + 8, hy - 6, 6, eyes))
    elif head == "alien":
        out.append(LINE(f"M{hx - 4},{hy + 30} L{hx},{hy + 50}", skin, 6))
        out.append(E(hx, hy - 6, 30, 38, skin))
        out.append(E(hx + 12, hy - 4, 9, 12, "#ff9a30"))
        out.append(E(hx - 10, hy - 2, 7, 10, "#ff9a30"))
    elif head == "hood":
        out.append(P([(hx, hy - 60), (hx + 36, hy - 10), (hx + 22, hy + 30), (hx - 22, hy + 30), (hx - 36, hy - 10)], shade(skin, 0.6)))
        out.append(C(hx, hy + 4, 22, "#1a1a1a"))
        out.append(C(hx - 8, hy, 6, "#b8ff60", False))
        out.append(C(hx + 10, hy, 6, "#b8ff60", False))
    elif head == "moth":
        out.append(LINE(f"M{hx},{hy - 18} q-10,-30 -22,-34", "#4a3c38", 4))
        out.append(LINE(f"M{hx + 8},{hy - 18} q8,-30 22,-32", "#4a3c38", 4))
        out.append(E(hx + 4, hy, 24, 26, skin))
        out.append(E(hx - 6, hy - 2, 9, 11, "#ff2a1a"))
        out.append(E(hx + 16, hy - 2, 9, 11, "#ff2a1a"))
        out.append(C(hx - 6, hy - 4, 3, "#ffd0a0", False))
        out.append(C(hx + 16, hy - 4, 3, "#ffd0a0", False))
    elif head == "ape":
        out.append(C(hx, hy, 24, skin))
        out.append(E(hx + 12, hy + 6, 16, 14, shade(skin, 1.35)))
        out.append(LINE(f"M{hx},{hy - 8} L{hx + 22},{hy - 8}", shade(skin, 0.5), 7))
        out.append(eye(hx + 14, hy - 2, 5, eyes))
    elif head == "horned":
        out.append(LINE(f"M{hx - 8},{hy - 20} q-6,-22 -18,-30", "#d8c8a0", 7))
        out.append(LINE(f"M{hx + 8},{hy - 20} q6,-22 18,-30", "#d8c8a0", 7))
        out.append(E(hx + 10, hy, 22, 26, skin, -25))
        out.append(E(hx + 26, hy + 14, 14, 10, skin, -25))
        out.append(eye(hx + 10, hy - 8, 6, eyes))
        if horn_light:
            out.append(C(hx + 2, hy - 36, 10, "#fff2a0"))
            out.append(C(hx + 2, hy - 36, 18, "none", True))
    return [f'<g transform="translate(128 {G}) scale({s}) translate(-128 {-G}) rotate({lean} 128 {G})">'] + out + ["</g>"]


def serpent(color, whale=False):
    out = []
    dark = shade(color, 0.7)
    for (x, r) in [(48, 26), (96, 32)]:
        out.append(PATH(f"M{x - r},{206} A{r},{r * 1.1} 0 0 1 {x + r},{206} Z", color))
        out.append(P([(x - 6, 206 - r * 1.05), (x, 206 - r * 1.45), (x + 8, 206 - r * 1.05)], dark))
    hx, hy = 194, 80
    if whale:
        out.append(PATH(f"M136,206 Q140,100 {hx},{hy} Q240,{hy + 20} 236,140 Q210,170 180,206 Z", color))
        out.append(LINE(f"M180,150 Q200,170 230,150", INK, 2))
        out.append(eye(208, 108, 7, "yellow"))
    else:
        out.append(LINE(f"M146,206 Q132,120 {hx - 10},{hy + 10}", color, 34))
        for k in range(4):
            y = 180 - k * 26
            out.append(P([(134 + k * 6, y), (118 + k * 6, y - 14), (138 + k * 6, y - 10)], dark))
        out.append(E(hx + 12, hy, 34, 20, color, 10))
        out.append(LINE(f"M{hx + 4},{hy + 10} L{hx + 42},{hy + 12}", INK, 2))
        for k in range(3):
            x = hx + 16 + k * 8
            out.append(P([(x, hy + 11), (x + 3, hy + 18), (x + 6, hy + 11)], "white", False))
        out.append(eye(hx + 10, hy - 8, 6, "yellow"))
    out.append(PATH("M0,206 Q32,196 64,206 T128,206 T192,206 T256,206 L256,256 L0,256 Z", "#124e89", True, 3))
    out.append(PATH("M0,224 Q32,214 64,224 T128,224 T192,224 T256,224", "none", True, 2))
    return out


# --- roster ---------------------------------------------------------------------------------------

def canine(color, **kw):
    kw.setdefault("tail", "bushy")
    return quad(color, body=(58, 28), legs=(13, 44), head=23, snout=22, ears="pointy", **kw)


def feline(color, **kw):
    kw.setdefault("tail", "long")
    kw.setdefault("ears", "pointy")
    return quad(color, body=(62, 28), legs=(13, 42), head=23, snout=8, **kw)


def bear(color, **kw):
    kw.setdefault("ears", "round")
    return quad(color, body=(72, 44), legs=(22, 32), head=30, snout=14, tail="stub", **kw)


def deer(color, **kw):
    return quad(color, body=(56, 26), legs=(10, 62), head=19, snout=16, ears="pointy", tail="stub", neck=26, **kw)


SPRITES = {
    # pets (collar marks them as yours)
    "dog": lambda: quad("#c98b4f", body=(58, 30), legs=(14, 40), head=25, snout=18, ears="floppy", tail="thin", marks=("belly",), collar=True),
    "cat": lambda: feline("#8a8f99", marks=("stripes", "belly"), collar=True),
    "bird": lambda: bird("#3fb07a", beak="hook", beak_color="#3a3530", head_color="#e8d040", belly="#f0c040", wing="#2a7fc0", tail="long"),
    "rabbit": lambda: quad("#d8cfc0", body=(46, 32), legs=(14, 26), head=22, snout=8, ears="long", tail="stub", tail_color="white", marks=("pink_nose",), collar=True),
    "lizard": lambda: reptile("#7fa650", snout=18, size=0.85),
    "hamster": lambda: roundy("#e0a96d", kind="hamster", ears="round", snout=6, collar=True),
    # North America
    "raccoon": lambda: quad("#8a8c92", body=(56, 32), legs=(14, 36), head=24, snout=14, ears="round", tail="ringed", marks=("mask", "belly")),
    "opossum": lambda: quad("#c9c2b8", body=(56, 30), legs=(12, 30), head=22, snout=24, ears="round", tail="pink", marks=("face_white", "pink_nose"), ear_inner="#2a2a2a", leg_color="#4a4440"),
    "horned_owl": lambda: owl("#8a6a48"),
    "skunk": lambda: quad("#262626", body=(54, 30), legs=(12, 30), head=22, snout=14, ears="round", tail="up", marks=("back_stripe", "head_stripe")),
    "coyote": lambda: canine("#b8935a", marks=("belly",), muzzle="#e0cba0"),
    "black_bear": lambda: bear("#2f2a26", muzzle="#a08060"),
    "roadrunner": lambda: bird("#8c7a5b", beak="long", beak_color="#3a3530", legs="long", tail="long", crest=True, size=0.85, wing="#5a4a38", marks=("eye_stripe",)),
    "turkey_vulture": lambda: bird("#3a3030", beak="hook", beak_color="#f0e0d0", head_color="#d04040", size=1.1, wing="#4a4040"),
    "red_fox": lambda: canine("#d0682f", marks=("belly", "tail_tip"), muzzle="#f4efe6", leg_color="#3a2a22"),
    "badger": lambda: quad("#8a8a88", body=(64, 30), legs=(16, 24), head=24, snout=18, ears="small", tail="short", marks=("head_stripe",), leg_color="#2a2a2a"),
    "hedgehog": lambda: roundy("#8f7558", kind="spines"),
    "crow": lambda: bird("#262833", beak="big", beak_color="#1a1a1a", wing="#1a1c24"),
    "jaguar": lambda: feline("#d9a441", marks=("spots", "belly")),
    "armadillo": lambda: roundy("#a69684", kind="armor", snout=20, ears="small"),
    "capybara": lambda: quad("#9b6b43", body=(66, 38), legs=(16, 26), head=26, snout=18, ears="small", tail="none"),
    "toucan": lambda: bird("#1e1e22", beak="huge", beak_color="#f08a24", belly="#f6f0d0", wing="#141418"),
    "lioness": lambda: feline("#c9a066", tail="tuft", marks=("belly",)),
    "honey_badger": lambda: quad("#2a2a2a", body=(60, 30), legs=(15, 26), head=23, snout=14, ears="small", tail="short", marks=("grey_back",)),
    "meerkat": lambda: meerkat("#c4a27a"),
    "warthog": lambda: quad("#7a5c4d", body=(60, 32), legs=(13, 34), head=26, snout=20, ears="pointy", tail="thin", extras=("tusks", "mane")),
    "tiger": lambda: feline("#e07b2a", marks=("stripes", "belly")),
    "pangolin": lambda: roundy("#8a7356", kind="pangolin", snout=18, ears="none"),
    "macaque": lambda: macaque("#b59a86"),
    "tanuki": lambda: quad("#6b5a48", body=(54, 32), legs=(12, 30), head=24, snout=14, ears="round", tail="bushy", marks=("mask", "belly")),
    "kangaroo": lambda: kangaroo("#b5774a"),
    "wombat": lambda: roundy("#7c6a58", snout=10, ears="round"),
    "kookaburra": lambda: bird("#8fa0b0", beak="big", beak_color="#3a3530", belly="#f0ece0", wing="#5a7090", head_color="#e0dcd0", marks=("eye_stripe",)),
    "platypus": lambda: quad("#6b5440", body=(56, 24), legs=(10, 18), head=20, snout=0, ears="none", tail="flat", extras=("bill",)),
    "alligator": lambda: reptile("#4d5d3a", snout=50, marks=("scutes", "teeth")),
    "florida_panther": lambda: feline("#b08a5a", marks=("belly",), tail="long"),
    "blue_heron": lambda: bird("#7a8fa6", beak="long", beak_color="#e8c040", legs="long", neck=40, wing="#5a6f86", marks=("eye_stripe",)),
    "bison": lambda: quad("#5a4030", body=(66, 38), legs=(16, 34), head=28, snout=10, ears="small", tail="tuft", marks=("shaggy",), extras=("hump", "horns_curved", "beard")),
    "whitetail_deer": lambda: deer("#a67b52", extras=("antlers",), marks=("belly",)),
    "red_tailed_hawk": lambda: bird("#9c5a3c", beak="hook", beak_color="#e8c040", belly="#f0e6d0", tail="fan"),
    "gila_monster": lambda: reptile("#d0763a", snout=16, marks=("beads",)),
    "cougar": lambda: feline("#b8955f", marks=("belly", "tail_dark_tip")),
    "bald_eagle": lambda: bird("#4a3a2a", beak="hook", beak_color="#f0c030", head_color="#f6f6f2", size=1.1),
    "elk": lambda: deer("#8a6a4a", extras=("antlers_big",)),
    "sea_lion": lambda: seal("#6a5546"),
    "bobcat": lambda: feline("#a08060", tail="short", ears="tufts", marks=("spots", "belly")),
    "sea_otter": lambda: seal("#7a5c48", otter=True),
    "grizzly": lambda: bear("#6b4a30", extras=("hump",), muzzle="#a88060"),
    "gray_wolf": lambda: canine("#8a8a8a", marks=("belly",), muzzle="#d8d8d4"),
    "moose": lambda: quad("#4a3a2a", body=(64, 34), legs=(13, 56), head=26, snout=26, ears="pointy", tail="stub", neck=14, extras=("palmate", "beard")),
    "monk_seal": lambda: seal("#7f7f7a"),
    "mongoose": lambda: quad("#9a7a50", body=(58, 22), legs=(10, 26), head=18, snout=16, ears="small", tail="long"),
    "nene": lambda: bird("#8c7a62", beak="goose", beak_color="#2a2a2a", neck=28, head_color="#2a2a2a", belly="#d8ccb8", marks=("white_cheek",)),
    "wild_boar": lambda: quad("#4f3f35", body=(60, 34), legs=(13, 32), head=26, snout=22, ears="pointy", tail="thin", extras=("tusks", "mane")),
    # zombies
    "shambler": lambda: humanoid("#63c74d", clothes="#4a6a8a", lean=8),
    "runner": lambda: humanoid("#63c74d", clothes="#a04040", build="thin", lean=18, pose="run"),
    "bloater": lambda: humanoid("#9ccf50", clothes=None, build="bloated", lean=0, eyes="dead"),
    "brute": lambda: humanoid("#3e8948", clothes=None, pants="#2a2a30", build="muscle", scale=1.12, lean=4),
    "riot": lambda: humanoid("#63c74d", clothes="#3a4466", pants="#262b44", build="muscle", lean=4, hair="#181425"),
    "plague": lambda: humanoid("#3e8948", clothes="#68386c", build="bloated", lean=2),
    "screamer": lambda: humanoid("#c0cbdc", clothes="#5a6988", build="thin", lean=14, pose="run", eyes="red"),
    # legends
    "mothman": lambda: humanoid("#3a2a2e", pants="#2a2024", build="thin", head="moth", wings="moth", lean=0, pose="stand"),
    "woodbooger": lambda: humanoid("#4a3a28", pants="#4a3a28", build="ape", head="ape", eyes="yellow", scale=1.1, lean=4),
    "flatwoods_monster": lambda: humanoid("#3a5a3a", clothes="#2f4a2f", build="skirt", head="hood", lean=0),
    "wampus_cat": lambda: feline("#3a3030", eyes="yellow", extras=("fangs",)),
    "pope_lick_monster": lambda: humanoid("#8a7a68", pants="#5a4a3a", build="muscle", head="goat", eyes="red", fur=True, marks=("hooves",)),
    "loveland_frogman": lambda: humanoid("#5f8a4a", pants="#4f7a3a", build="thin", head="frog", lean=4, eyes="normal"),
    "jersey_devil": lambda: humanoid("#6a2a22", pants="#4a1f1a", build="thin", head="horned", wings="bat", tail="#6a2a22", eyes="red", marks=("hooves",), lean=6),
    "goatman": lambda: humanoid("#6a5a4a", clothes="#3a3a2a", pants="#5a4a3a", build="muscle", head="goat", eyes="red", weapon="axe", marks=("hooves",)),
    "snallygaster": lambda: reptile("#4a5a6a", snout=34, wings="#3a4050", raised=True, eyes="red", marks=("teeth",)),
    "champ": lambda: serpent("#3a5a5a"),
    "dover_demon": lambda: humanoid("#d8c8a0", build="thin", head="alien", pants="#d8c8a0", lean=0, pose="stand"),
    "dogman": lambda: humanoid("#4a3f34", pants="#4a3f34", build="muscle", head="wolf", eyes="yellow", fur=True, lean=8),
    "beast_of_bray_road": lambda: humanoid("#5a5048", pants="#5a5048", build="muscle", head="wolf", eyes="red", fur=True, lean=10),
    "hodag": lambda: quad("#3a3a32", body=(66, 34), legs=(16, 30), head=30, snout=20, ears="none", tail="point", eyes="red", extras=("spines", "horns_devil", "fangs")),
    "van_meter_visitor": lambda: humanoid("#5a4a3a", pants="#4a3a2a", build="thin", head="horned", wings="bat", eyes="red", horn_light=True, lean=0, pose="stand"),
    "ozark_howler": lambda: feline("#1f1c1a", eyes="red", extras=("horns_devil", "fangs")),
    "fouke_monster": lambda: humanoid("#5a3e28", pants="#5a3e28", build="ape", head="ape", eyes="red", scale=1.1),
    "rougarou": lambda: humanoid("#4a4238", clothes="#3a4a5a", pants="#2a2a30", build="muscle", head="wolf", eyes="yellow", lean=8),
    "lizard_man": lambda: humanoid("#4a6a3a", pants="#3a5a2a", build="muscle", head="lizard", eyes="red", tail="#4a6a3a"),
    "altamaha_ha": lambda: serpent("#4a5a4a"),
    "skunk_ape": lambda: humanoid("#7a6a3a", pants="#7a6a3a", build="ape", head="ape", eyes="yellow", scale=1.1),
    "chupacabra": lambda: quad("#6a6a5a", body=(52, 26), legs=(11, 44), head=22, snout=20, ears="pointy", tail="thin", eyes="red", extras=("spines", "fangs"), ear_inner="#a04040"),
    "mogollon_monster": lambda: humanoid("#6a3e26", pants="#6a3e26", build="ape", head="ape", eyes="red", scale=1.1),
    "bigfoot": lambda: humanoid("#4a3020", pants="#4a3020", build="ape", head="ape", eyes="normal", scale=1.15),
    "tahoe_tessie": lambda: serpent("#2a4a6a"),
    "bear_lake_monster": lambda: serpent("#3a4a3a"),
    "flathead_monster": lambda: serpent("#2a3a4a"),
    "slide_rock_bolter": lambda: serpent("#6a6a66", whale=True),
    "iliamna_monster": lambda: serpent("#4a5a6a", whale=True),
    "black_shuck": lambda: quad("#1f1f1f", body=(64, 32), legs=(15, 48), head=27, snout=22, ears="pointy", tail="bushy", eyes="red", extras=("fangs",)),
    "mokele_mbembe": lambda: serpent("#5a6a4a"),
    "yeti": lambda: humanoid("#e4e8ec", pants="#e4e8ec", build="ape", head="ape", eyes="normal", scale=1.15),
    "drop_bear": lambda: bear("#8a8a8a", ears="big_round", extras=("fangs",), eyes="red", muzzle="#5a5a5a"),
}


def main():
    os.makedirs(OUT, exist_ok=True)
    for unit_id, build in SPRITES.items():
        with open(os.path.join(OUT, unit_id + ".svg"), "w", encoding="utf-8") as f:
            f.write(svg(build()))
    print(f"wrote {len(SPRITES)} sprites to {OUT}/")


if __name__ == "__main__":
    main()
