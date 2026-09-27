"""Generate Catnip's textures as 32-bit TGA files in media/.

Textures are white with the shape in the alpha channel, so they can be tinted in-game
with SetVertexColor. Run from the repo root:  py tools/make_textures.py
"""
import math
import os
import struct

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "media")


def write_tga(path, size, alpha_fn):
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, size, size, 32, 0x28)
    pixels = bytearray()
    c = (size - 1) / 2
    for y in range(size):
        for x in range(size):
            d = math.hypot(x - c, y - c)
            a = max(0.0, min(1.0, alpha_fn(d)))
            pixels += bytes((255, 255, 255, round(a * 255)))
    with open(path, "wb") as f:
        f.write(header + pixels)


def circle_hard(size):
    r = size / 2 - 1
    return lambda d: r - d + 0.5


def circle_soft(size, solid=0.7):
    r = size / 2 - 1
    def alpha(d):
        if d <= r * solid:
            return 1.0
        t = min(1.0, (d - r * solid) / (r * (1 - solid)))
        return (1 - t) ** 2
    return alpha


def ring(size, thickness):
    r = size / 2 - 1
    return lambda d: min(r - d + 0.5, d - (r - thickness) + 0.5)


TEXTURES = {
    # name: (size, alpha function)  -- numbers match docs/design.md
    "circle_hard": (256, circle_hard(256)),        # 1
    "circle_soft": (256, circle_soft(256)),        # 2
    "ring_thin": (256, ring(256, 6)),              # 3, for the big circle
    "ring_thin_small": (64, ring(64, 4)),          # 3, for combo points
}

if __name__ == "__main__":
    os.makedirs(OUT_DIR, exist_ok=True)
    for name, (size, fn) in TEXTURES.items():
        path = os.path.join(OUT_DIR, name + ".tga")
        write_tga(path, size, fn)
        print("wrote", os.path.normpath(path))
