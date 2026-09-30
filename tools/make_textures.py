"""Generate Catnip's textures as 32-bit TGA files in media/.

Textures are white with the shape in the alpha channel, so they can be tinted in-game
with SetVertexColor. Shape functions take (distance from centre, dx, dy) and return alpha,
or (alpha, brightness) for shaded textures. Run from the repo root:  py tools/make_textures.py
"""
import math
import os
import struct

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "media")


def as_pair(result):
    return result if isinstance(result, tuple) else (result, 1.0)


def write_tga(path, size, shape):
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, size, size, 32, 0x28)
    pixels = bytearray()
    c = (size - 1) / 2
    for y in range(size):
        for x in range(size):
            dx, dy = x - c, y - c
            a, b = as_pair(shape(math.hypot(dx, dy), dx, dy))
            a = max(0.0, min(1.0, a))
            v = round(max(0.0, min(1.0, b)) * 255)
            pixels += bytes((v, v, v, round(a * 255)))
    with open(path, "wb") as f:
        f.write(header + pixels)


def circle_hard(size):
    r = size / 2 - 1
    return lambda d, *_: r - d + 0.5


def circle_soft(size, solid=0.7):
    r = size / 2 - 1
    def alpha(d, *_):
        if d <= r * solid:
            return 1.0
        t = min(1.0, (d - r * solid) / (r * (1 - solid)))
        return (1 - t) ** 2
    return alpha


def ring(size, thickness):
    r = size / 2 - 1
    return lambda d, *_: min(r - d + 0.5, d - (r - thickness) + 0.5)


def half_ring(size, thickness):
    """The left half of a ring, on a full-size canvas so it rotates around the ring's centre."""
    full = ring(size, thickness)
    return lambda d, dx, dy: min(full(d), -dx + 0.5)


def ring_bar(size, thickness):
    """A thick ring, brightest along the middle of the band for a rounded look."""
    r = size / 2 - 1
    def shade(d, *_):
        alpha = min(r - d + 0.5, d - (r - thickness) + 0.5)
        u = max(0.0, min(1.0, (r - d) / thickness))
        return alpha, 0.7 + 0.3 * math.sin(math.pi * u)
    return shade


def ring_glow(size, center=0.78, width=0.07):
    """A soft band. Its centre sits at `center` of the radius, so Lua scales it up to line up with ring_bar."""
    r = size / 2 - 1
    return lambda d, *_: math.exp(-(((d - center * r) / (width * r)) ** 2) / 2)


def circle_feather(size, feather=8):
    """A circle whose edge fades out over `feather` px (~3px at the 100px resource size), for soft edges."""
    r = size / 2 - 1
    def alpha(d, *_):
        t = max(0.0, min(1.0, (r + 0.5 - d) / feather))
        return t * t * (3 - 2 * t)  # smoothstep
    return alpha


def top_window(dx, dy, max_angle, power=1.0):
    """1 at 12 o'clock, easing to 0 at `max_angle` radians either side. Image y grows downward."""
    a = abs(math.atan2(dx, -dy))
    return 0.0 if a >= max_angle else math.cos(math.pi / 2 * a / max_angle) ** power


def gauss(x, sigma):
    return math.exp(-(x * x) / (2 * sigma * sigma))


def crescent_line(size):
    """Clearcasting: a thin bright arc just inside the top of circle_feather, thinning toward its ends."""
    r = size / 2 - 1
    circle = circle_feather(size)
    return lambda d, dx, dy: circle(d) * gauss(d - 0.93 * r, 0.026 * r) * top_window(dx, dy, math.radians(72), 1.4)


def crescent_edge(size):
    """Clearcasting: a thin band just inside crescent_line, tinted black, to give the arc a crisp
    lower edge on any fill."""
    r = size / 2 - 1
    circle = circle_feather(size)
    return lambda d, dx, dy: circle(d) * gauss(d - 0.86 * r, 0.018 * r) * top_window(dx, dy, math.radians(72), 1.4)


def crescent_bloom(size):
    """Clearcasting: a glow hugging the inside of the top rim, plus light spilling downward in soft rays
    from a point just under 12 o'clock."""
    r = size / 2 - 1
    circle = circle_feather(size)
    def alpha(d, dx, dy):
        rim = math.exp(-((r - d) / r) / 0.13) * top_window(dx, dy, math.radians(83), 1.2) * 0.95
        px, py = dx, dy + 0.9 * r  # from the light source; angle 0 is straight down
        q = math.hypot(px, py) / r
        angle = math.atan2(px, py)
        rays = 0.6 + 0.4 * (0.5 + 0.5 * math.cos(angle * 15)) ** 2
        down = 0.0 if abs(angle) >= math.radians(95) else math.cos(math.pi / 2 * abs(angle) / math.radians(95))
        spill = math.exp(-q / 0.32) * rays * down * 1.1
        return circle(d) * min(1.0, rim + spill)
    return alpha


def crescent_shadow(size):
    """Clearcasting: a soft, slightly larger version of crescent_bloom without rays, tinted black
    under the light so it has something dark to shine on (a bright fill otherwise washes it out)."""
    r = size / 2 - 1
    circle = circle_feather(size)
    def alpha(d, dx, dy):
        rim = math.exp(-((r - d) / r) / 0.2) * top_window(dx, dy, math.radians(95), 1.0)
        px, py = dx, dy + 0.9 * r
        q = math.hypot(px, py) / r
        angle = math.atan2(px, py)
        down = 0.0 if abs(angle) >= math.radians(105) else math.cos(math.pi / 2 * abs(angle) / math.radians(105))
        spill = math.exp(-q / 0.42) * down
        return circle(d) * min(1.0, rim + spill)
    return alpha


TEXTURES = {
    # name: (size, shape)  -- numbers match docs/design.md
    "circle_hard": (256, circle_hard(256)),                 # 1
    "circle_soft": (256, circle_soft(256)),                 # 2
    "circle_feather": (256, circle_feather(256)),           # 1, soft-edged: resource fill mask, GCD, Enrage
    "crescent_line": (256, crescent_line(256)),             # Clearcasting: bright arc inside the top rim
    "crescent_bloom": (256, crescent_bloom(256)),           # Clearcasting: glow and rays under the arc
    "crescent_shadow": (256, crescent_shadow(256)),         # Clearcasting: dark backing under the glow
    "crescent_edge": (256, crescent_edge(256)),             # Clearcasting: dark line under the arc
    "ring_thin": (256, ring(256, 6)),                       # 3, for the big circle
    "ring_small": (64, ring(64, 3)),                        # combo point borders
    "ring_rip": (128, ring(128, 16)),                       # 5, DoT timers around combo points 4 and 5
    "ring_mana_half": (256, half_ring(256, 10)),            # five-second rule: left half, rotated into view
    "ring_glow": (256, ring_glow(256)),                     # 4
    "ring_bar": (256, ring_bar(256, 20)),                   # 7
}

if __name__ == "__main__":
    os.makedirs(OUT_DIR, exist_ok=True)
    for name, (size, shape) in TEXTURES.items():
        path = os.path.join(OUT_DIR, name + ".tga")
        write_tga(path, size, shape)
        print("wrote", os.path.normpath(path))
