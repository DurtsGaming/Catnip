"""Generate Catnip's textures as 32-bit TGA files in media/.

Textures are white with the shape in the alpha channel, so they can be tinted in-game
with SetVertexColor. Shape functions take (distance from centre, dx, dy) and return alpha,
or (alpha, brightness) for shaded textures. Run from the repo root:  py tools/make_textures.py
"""
import math
import os
import struct

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "media")


def clamp01(v):
    return max(0.0, min(1.0, v))


def as_pair(result):
    """Normalise a shape's result to (alpha, (r, g, b)). Brightness b means the grey (b, b, b)."""
    a, colour = result if isinstance(result, tuple) else (result, 1.0)
    return a, colour if isinstance(colour, tuple) else (colour, colour, colour)


def write_tga(path, size, shape):
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, size, size, 32, 0x28)
    pixels = bytearray()
    c = (size - 1) / 2
    for y in range(size):
        for x in range(size):
            dx, dy = x - c, y - c
            a, (r, g, b) = as_pair(shape(math.hypot(dx, dy), dx, dy))
            r, g, b = (round(clamp01(v) * 255) for v in (r, g, b))
            pixels += bytes((b, g, r, round(clamp01(a) * 255)))  # TGA stores BGRA
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


def ring_bar(size, thickness):
    """A thick ring, brightest along the middle of the band for a rounded look."""
    r = size / 2 - 1
    def shade(d, *_):
        alpha = min(r - d + 0.5, d - (r - thickness) + 0.5)
        u = max(0.0, min(1.0, (r - d) / thickness))
        return alpha, 0.7 + 0.3 * math.sin(math.pi * u)
    return shade


def ring_bar_half(size, thickness):
    """The left half of ring_bar, on a full-size canvas so it rotates around the ring's centre."""
    full = ring_bar(size, thickness)
    def shade(d, dx, dy):
        alpha, value = full(d)
        return min(alpha, -dx + 0.5), value
    return shade


def ring_tube_half(size, thickness, edge=0.35):
    """The left half of a thin ring shaded like a tube: full brightness along the middle of the band,
    `edge` at its rims, on a full-size canvas so it rotates around the ring's centre."""
    r = size / 2 - 1
    full = ring(size, thickness)
    def shade(d, dx, dy):
        u = clamp01((r - d) / thickness)
        return min(full(d), -dx + 0.5), edge + (1 - edge) * math.sin(math.pi * u) ** 0.7
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


# Power fills: the WoW Forever power bars, measured from screenshots, stood on their end. Unlike the
# textures above these carry their own colour and are drawn untinted.
# Along the bar, empty end -> full end (the fill's bottom -> top), sampled every 18px on its middle row.
# Energy and rage pale toward white at the full end; mana doesn't, it just brightens and levels off.
FOREVER_ENERGY = [(157, 132, 0), (165, 143, 0), (177, 157, 0), (189, 173, 1), (203, 189, 4), (216, 206, 11),
                  (229, 223, 20), (241, 236, 32), (250, 249, 45), (254, 255, 57), (254, 255, 66), (254, 255, 73)]
FOREVER_MANA = [(0, 61, 139), (1, 66, 149), (2, 73, 164), (4, 83, 182), (6, 93, 201), (8, 102, 219),
                (9, 110, 234), (10, 114, 242), (10, 114, 242), (10, 114, 242), (10, 114, 242), (10, 114, 242)]
FOREVER_RAGE = [(160, 0, 0), (169, 0, 0), (179, 0, 0), (190, 1, 1), (203, 7, 4), (215, 17, 10),
                (227, 29, 18), (238, 47, 28), (247, 65, 41), (254, 85, 53), (255, 98, 62), (255, 110, 69)]


def sample(values, t):
    """Linear interpolation through evenly spaced values (numbers or tuples), t in 0..1."""
    x = clamp01(t) * (len(values) - 1)
    i = min(len(values) - 2, int(x))
    f = x - i
    a, b = values[i], values[i + 1]
    if isinstance(a, tuple):
        return tuple(p + (q - p) * f for p, q in zip(a, b))
    return a + (b - a) * f


def forever_colour(t, stops):
    """Colour at `t` along the bar (0 empty end, 1 full end). `stops` is a measured bar, or an (r, g, b)
    for a bar we haven't measured: darkened toward the empty end the way the mana bar is, no paling."""
    if isinstance(stops, list):
        return tuple(v / 255 for v in sample(stops, t))
    brightness = sample(FOREVER_MANA, t)[2] / 242
    return tuple(c * brightness for c in stops)


def soft_tube(u):
    """The bar's rounded shading, run across the circle: brightest down the middle, 65% at both sides."""
    return 0.65 + 0.35 * math.sin(math.pi * clamp01(u)) ** 0.6


def power_fill(size, stops):
    """Resource fill (the StatusBar texture): the colour gradient bottom to top, the tube shading across."""
    c = (size - 1) / 2
    def colour(d, dx, dy):
        u, v = (dx + c + 0.5) / size, (dy + c + 0.5) / size
        shade = soft_tube(u)
        return 1.0, tuple(ch * shade for ch in forever_colour(1 - v, stops))
    return colour


def combo_fill(size):
    """A combo point: the full energy fill cut to circle_hard's shape (the dots are always full)."""
    fill, circle = power_fill(size, FOREVER_ENERGY), circle_hard(size)
    return lambda d, dx, dy: (circle(d), fill(d, dx, dy)[1])


TEXTURES = {
    # name: (size, shape)  -- numbers match docs/design.md
    "circle_hard": (256, circle_hard(256)),                 # 1
    "circle_soft": (256, circle_soft(256)),                 # 2
    "circle_feather": (256, circle_feather(256)),           # 1, soft-edged: resource fill mask, GCD, Enrage
    "crescent_line": (256, crescent_line(256)),             # Clearcasting: bright arc inside the top rim
    "crescent_bloom": (256, crescent_bloom(256)),           # Clearcasting: glow and rays under the arc
    "crescent_shadow": (256, crescent_shadow(256)),         # Clearcasting: dark backing under the glow
    "crescent_edge": (256, crescent_edge(256)),             # Clearcasting: dark line under the arc
    "ring_thin": (256, ring(256, 10)),                      # 3, for the big circle; same band as ring_mana_half
    "ring_small": (64, ring(64, 3)),                        # combo point borders
    "ring_rip": (128, ring(128, 16)),                       # 5, DoT timers around combo points 4 and 5
    "ring_mana_half": (256, ring_tube_half(256, 10)),       # five-second rule: shaded left half, rotated into view; same band as ring_thin
    "ring_glow": (256, ring_glow(256)),                     # 4
    "ring_bar": (256, ring_bar(256, 20)),                   # 7
    "ring_bar_half": (256, ring_bar_half(256, 20)),         # 7, cast bar: left half, rotated into view
    # Coloured, drawn untinted.
    "fill_energy": (128, power_fill(128, FOREVER_ENERGY)),  # 1, resource fill in Cat Form
    "fill_rage": (128, power_fill(128, FOREVER_RAGE)),      # 1, resource fill in Bear Form
    "fill_mana": (128, power_fill(128, FOREVER_MANA)),      # 1, resource fill otherwise
    "combo_fill": (128, combo_fill(128)),                   # 1, combo points
}

if __name__ == "__main__":
    os.makedirs(OUT_DIR, exist_ok=True)
    for name, (size, shape) in TEXTURES.items():
        path = os.path.join(OUT_DIR, name + ".tga")
        write_tga(path, size, shape)
        print("wrote", os.path.normpath(path))
