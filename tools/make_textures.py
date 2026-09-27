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


def ring_bar(size, thickness):
    """A thick ring, brightest along the middle of the band for a rounded look."""
    r = size / 2 - 1
    def shade(d, *_):
        alpha = min(r - d + 0.5, d - (r - thickness) + 0.5)
        u = max(0.0, min(1.0, (r - d) / thickness))
        return alpha, 0.7 + 0.3 * math.sin(math.pi * u)
    return shade


def ring_outline(size, band, line):
    """Crisp lines along the inner and outer edges of a ring_bar band of the same size."""
    r = size / 2 - 1
    inner = r - band
    def alpha(d, *_):
        outer_edge = min(r - d + 0.5, d - (r - line) + 0.5)
        inner_edge = min(inner + line - d + 0.5, d - inner + 0.5)
        return max(outer_edge, inner_edge)
    return alpha


def ring_glow(size, center=0.78, width=0.07):
    """A soft band. Its centre sits at `center` of the radius, so Lua scales it up to line up with ring_bar."""
    r = size / 2 - 1
    return lambda d, *_: math.exp(-(((d - center * r) / (width * r)) ** 2) / 2)


def claws(size, spacing=0.4, length=0.85, width=0.09, outline=5):
    """Three tapered, parallel white slashes ("///") with a black outline, for the Clearcasting proc."""
    s = size / 2
    half_x, half_y = 0.3 * length * s, 0.5 * length * s
    offsets = [(-spacing * s, 0.05 * s), (0, -0.05 * s), (spacing * s, 0.05 * s)]  # middle claw sits higher
    def shape(d, dx, dy):
        best = -math.inf
        for ox, oy in offsets:
            # from bottom-left to top-right (image y grows downward)
            ax, ay, bx, by = ox - half_x, oy + half_y, ox + half_x, oy - half_y
            vx, vy = bx - ax, by - ay
            t = max(0.0, min(1.0, ((dx - ax) * vx + (dy - ay) * vy) / (vx * vx + vy * vy)))
            dist = math.hypot(dx - (ax + t * vx), dy - (ay + t * vy))
            half_width = width * s * math.sin(math.pi * t) ** 0.6
            best = max(best, half_width - dist)  # > 0 inside a stroke
        stroke = max(0.0, min(1.0, best + 0.5))
        return best + outline + 0.5, stroke  # alpha covers stroke + outline; white only in the stroke
    return shape


def right_half(shape):
    """Only the right half of another shape. The swing timer rotates two of these to draw an arc."""
    def half(d, dx, dy):
        a, b = as_pair(shape(d, dx, dy))
        return a * max(0.0, min(1.0, dx + 0.5)), b
    return half


TEXTURES = {
    # name: (size, shape)  -- numbers match docs/design.md
    "circle_hard": (256, circle_hard(256)),                 # 1
    "circle_soft": (256, circle_soft(256)),                 # 2
    "ring_thin": (256, ring(256, 6)),                       # 3, for the big circle
    "ring_small": (64, ring(64, 8)),                        # combo point borders
    "ring_dot": (256, ring(256, 10)),                       # 5, DoT timer layer outside the swing ring
    "ring_glow": (256, ring_glow(256)),                     # 4
    "ring_bar": (256, ring_bar(256, 20)),                   # 7
    "ring_bar_half": (256, right_half(ring_bar(256, 20))),  # 7, for arc fills
    "ring_bar_outline": (256, ring_outline(256, 20, 5)),    # 7, edge lines drawn over the fill
    "claws": (128, claws(128)),                             # Clearcasting proc
}

if __name__ == "__main__":
    os.makedirs(OUT_DIR, exist_ok=True)
    for name, (size, shape) in TEXTURES.items():
        path = os.path.join(OUT_DIR, name + ".tga")
        write_tga(path, size, shape)
        print("wrote", os.path.normpath(path))
