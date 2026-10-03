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


# Shifting Power arc (ShiftingPower.lua): four segments on a circle under the swing ring, centred on
# 6 o'clock. Measured in HUD units on a canvas SP_CANVAS units across, centred on the HUD's centre;
# keep these in step with the constants in ShiftingPower.lua.
SP_CANVAS = 164
SP_RADIUS = 74            # centre line of the band: inner edge (with outline) ~2.5 outside the swing ring's band
SP_HALF_WIDTH = 3         # band is 6 units thick
SP_SPAN = 180 / 4.2       # degrees either side of 6 o'clock
SP_GAP = math.degrees(6.5 / SP_RADIUS)  # 6.5 units between segments (and trimmed off both outer ends)
SP_OUTLINE = 1.5          # outline thickness, just outside each segment; leaves 3.5 units clear between outlines
SP_YELLOW_FROM = 0.6      # where along the energy bar segment 4 starts (saturated yellow, not the dark end)


def sp_colour(t):
    """The arc's colour at t (0-1, left to right), segment by segment: blue (the Forever mana bar,
    empty to full end), blue to white, white to yellow, yellow (the energy bar's bright end), so
    segments 2 and 3 meet in white."""
    def mix(a, b, f):
        return tuple(p + (q - p) * f for p, q in zip(a, b))
    white = (1.0, 1.0, 1.0)
    i = min(3, int(t * 4))
    local = clamp01(t * 4 - i)
    if i == 0:
        return forever_colour(local, FOREVER_MANA)
    if i == 1:
        return mix(forever_colour(1, FOREVER_MANA), white, local)
    if i == 2:
        return mix(white, forever_colour(SP_YELLOW_FROM, FOREVER_ENERGY), local)
    return forever_colour(SP_YELLOW_FROM + (1 - SP_YELLOW_FROM) * local, FOREVER_ENERGY)


def sp_arc_geometry(size):
    """Shape of the arc: returns f(d, dx, dy) -> (alpha, t along the arc 0-1 left to right, u across
    the band 0-1, px inside the nearest segment's edge (negative outside))."""
    scale = size / SP_CANVAS
    radius, half = SP_RADIUS * scale, SP_HALF_WIDTH * scale
    start, end = 270 - SP_SPAN, 270 + SP_SPAN
    seg = (end - start) / 4

    def shape(d, dx, dy):
        angle = math.degrees(math.atan2(-dy, dx)) % 360  # maths angle, y up; 270 is straight down
        if not start - 10 < angle < end + 10 or d < 1:
            return 0.0, 0.0, 0.0, -1e9
        i = min(3, max(0, int((angle - start) // seg)))
        s0, s1 = start + i * seg + SP_GAP / 2, start + (i + 1) * seg - SP_GAP / 2
        along = math.radians(min(angle - s0, s1 - angle)) * d
        across = half - abs(d - radius)
        inside = min(along, across)
        t = clamp01((angle - start) / (end - start))
        u = clamp01((d - (radius - half)) / (2 * half))
        return clamp01(inside + 0.5), t, u, inside
    return shape


def sp_arc_outline(size):
    """A thin line around each segment, just outside its edge, in the segment's own colours; the
    inside is clear."""
    geometry = sp_arc_geometry(size)
    width = SP_OUTLINE * size / SP_CANVAS
    def colour(d, dx, dy):
        _, t, _, inside = geometry(d, dx, dy)
        return min(clamp01(inside + width + 0.5), clamp01(0.5 - inside)), sp_colour(t)
    return colour


def sp_arc(size):
    """The arc in colour (sp_colour), with the resource fill's tube shading across the band."""
    geometry = sp_arc_geometry(size)
    def colour(d, dx, dy):
        a, t, u, _ = geometry(d, dx, dy)
        shade = soft_tube(u)
        return a, tuple(ch * shade for ch in sp_colour(t))
    return colour


def sp_orb(size):
    """Shifting Power mana counter orb: circle_hard's disc blending diagonally from the mana bar's
    blue (top left) to the energy bar's yellow (bottom right), slightly darker toward the rim."""
    disc = circle_hard(size)
    r = size / 2 - 1
    blue = forever_colour(1, FOREVER_MANA)
    yellow = forever_colour(SP_YELLOW_FROM, FOREVER_ENERGY)
    def colour(d, dx, dy):
        t = clamp01(0.5 + (dx + dy) / (2.4 * r))  # dy grows downward: 0 top left, 1 bottom right
        t = t * t * (3 - 2 * t)
        shade = 1 - 0.25 * clamp01(d / r) ** 3
        return disc(d), tuple((b + (y - b) * t) * shade for b, y in zip(blue, yellow))
    return colour


def half_plane(size):
    """The canvas's left half, hard edge through the centre; rotated to sweep across an arc."""
    return lambda d, dx, dy: -dx + 0.5


def rim_glow(size):
    """Light along the inside edge of a circle: rising from 74% of the radius to a peak at 95%,
    easing to 70% at the rim, then cut off with circle_hard's edge."""
    r = size / 2 - 1
    def alpha(d, *_):
        if d < 0.74 * r:
            return 0.0
        if d < 0.95 * r:
            t = (d - 0.74 * r) / (0.21 * r)
            a = t * t * (3 - 2 * t)
        else:
            a = 1 - 0.3 * clamp01((d - 0.95 * r) / (0.05 * r))
        return a * clamp01(r - d + 0.5)
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
    "ring_thin": (256, ring(256, 10)),                      # 3, for the big circle; same band as ring_mana_half
    "ring_small": (64, ring(64, 3)),                        # combo point borders
    "ring_rip": (128, ring(128, 16)),                       # 5, DoT timers around combo points 4 and 5
    "ring_mana_half": (256, ring_tube_half(256, 10)),       # five-second rule: shaded left half, rotated into view; same band as ring_thin
    "ring_glow": (256, ring_glow(256)),                     # 4
    "ring_bar": (256, ring_bar(256, 20)),                   # 7
    "ring_bar_half": (256, ring_bar_half(256, 20)),         # 7, cast bar: left half, rotated into view
    "half_plane": (256, half_plane(256)),                  # Shifting Power: rotated mask, shows only the filled part of the arc
    "rim_glow": (256, rim_glow(256)),                       # Shifting Power ready: light inside the resource circle's rim
    # Coloured, drawn untinted.
    "sp_arc": (256, sp_arc(256)),                           # Shifting Power: the four segments, blue to white to yellow
    "sp_arc_outline": (256, sp_arc_outline(256)),           # Shifting Power: line around each segment, in its colours
    "sp_orb": (64, sp_orb(64)),                             # Shifting Power mana counter orb, blue to yellow
    "fill_energy": (128, power_fill(128, FOREVER_ENERGY)),  # 1, resource fill in Cat Form
    "fill_rage": (128, power_fill(128, FOREVER_RAGE)),      # 1, resource fill in Bear Form
    "fill_mana": (128, power_fill(128, FOREVER_MANA)),      # 1, resource fill otherwise
    "combo_fill": (128, combo_fill(128)),                   # 1, combo points
}

def write_tga_pixels(path, width, height, pixel):
    """Like write_tga, for any canvas: pixel(x, y) returns alpha (white), x right and y down."""
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, width, height, 32, 0x28)
    pixels = bytearray()
    for y in range(height):
        for x in range(width):
            pixels += bytes((255, 255, 255, round(clamp01(pixel(x, y)) * 255)))
    with open(path, "wb") as f:
        f.write(header + pixels)


def square_dashed_flipbook(frame, grid, count, thickness, duty=0.5):
    """A FlipBook: grid x grid frames, each a thin square border broken into `count` dashes (each
    `duty` of its spacing long). Frame by frame the dashes move clockwise by 1/(grid*grid) of their
    spacing, so looping the frames makes them run around the square. Returns (width, height, pixel)."""
    inset = 1 + thickness / 2  # centre line of the border, from the frame edge
    lo, hi = inset, frame - inset
    side = hi - lo
    spacing = 4 * side / count
    dash = spacing * duty
    frames = grid * grid

    def nearest(px, py):
        """(distance to the border's centre line, distance along it clockwise from the top-left)."""
        cx, cy = min(max(px, lo), hi), min(max(py, lo), hi)
        candidates = [
            (math.hypot(px - cx, py - lo), cx - lo),               # top, left to right
            (math.hypot(px - hi, py - cy), side + cy - lo),        # right, top to bottom
            (math.hypot(px - cx, py - hi), 2 * side + hi - cx),    # bottom, right to left
            (math.hypot(px - lo, py - cy), 3 * side + hi - cy),    # left, bottom to top
        ]
        return min(candidates)

    def pixel(x, y):
        k = (y // frame) * grid + x // frame
        d, s = nearest(x % frame + 0.5, y % frame + 0.5)
        u = (s - k * spacing / frames) % spacing  # position within this dash's period
        across = thickness / 2 - d + 0.5
        if u < dash:  # inside a dash: soft ends
            along = min(u, dash - u) + 0.5
        else:  # in a gap: fades to nothing half a pixel from either dash
            along = 0.5 - min(u - dash, spacing - u)
        return min(clamp01(across), clamp01(along))

    return frame * grid, frame * grid, pixel


# Canvases that aren't one centred shape: name -> (width, height, pixel).
FLIPBOOKS = {
    # cooldown widget: thin dashes running around an icon while its buff is up (4x4 frames of 64px)
    "square_dashed": square_dashed_flipbook(64, 4, 12, 2),
}


# Settings window art, coloured to match WoW Forever's Professions frame (colours sampled from a
# screenshot, 0-255). The borders are nine-slice sources: Options.lua cuts them into corners and
# stretched edges, so only the corners need drawing. Pixel functions return (alpha, (r, g, b)).

def write_tga_rgba(path, width, height, pixel):
    """Like write_tga_pixels, but coloured: pixel(x, y) returns (alpha 0-1, (r, g, b) 0-255)."""
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, width, height, 32, 0x28)
    pixels = bytearray()
    for y in range(height):
        for x in range(width):
            a, (r, g, b) = pixel(x, y)
            pixels += bytes((round(b), round(g), round(r), round(clamp01(a) * 255)))
    with open(path, "wb") as f:
        f.write(header + pixels)


def supersampled(sample, n=4):
    """Antialias: average sample(px, py) -> (alpha, rgb) over n x n points in each pixel."""
    def pixel(x, y):
        a_sum, rgb_sum = 0.0, [0.0, 0.0, 0.0]
        for i in range(n):
            for j in range(n):
                a, rgb = sample(x + (i + 0.5) / n, y + (j + 0.5) / n)
                a_sum += a
                for k in range(3):
                    rgb_sum[k] += a * rgb[k]
        if a_sum == 0:
            return 0.0, (0, 0, 0)
        return a_sum / (n * n), tuple(v / a_sum for v in rgb_sum)
    return pixel


def chamfer_depth(px, py, size, cut):
    """How far (px, py) is inside a size x size square with its corners cut off at 45 degrees
    (`cut` pixels along each side), and which edge is nearest: 0 left, 1 top, 2 right, 3 bottom,
    4-7 the top-left, top-right, bottom-left, bottom-right cuts."""
    rx, by = size - px, size - py
    s = math.sqrt(2)
    return min((d, i) for i, d in enumerate((
        px, py, rx, by,
        (px + py - cut) / s, (rx + py - cut) / s, (px + by - cut) / s, (rx + by - cut) / s)))


# The window frame's bevel, outermost pixel first, then a black line before the ground.
FRAME_BANDS = [(30, 22, 10), (110, 80, 40), (150, 112, 70), (112, 86, 55),
               (48, 30, 9), (66, 41, 12), (38, 23, 7), (0, 0, 0)]


def frame_border(size, cut):
    """The window's edge: FRAME_BANDS following the cut corners; transparent outside and inside."""
    def sample(px, py):
        d, _ = chamfer_depth(px, py, size, cut)
        if d < 0 or d >= len(FRAME_BANDS):
            return 0.0, (0, 0, 0)
        return 1.0, FRAME_BANDS[int(d)]
    return supersampled(sample)


GROUND = (12, 10, 8)  # behind the panels; Options.lua's GROUND must match
PANEL_EDGE = (85, 63, 41)
PANEL_LINE_TOP_LEFT = (35, 19, 10)
PANEL_LINE_BOTTOM_RIGHT = (47, 29, 17)


def panel_border(size, cut):
    """A panel's edge: a light line, then a dark line (warmer on the bottom and right). The cut-off
    corners are painted the ground colour (opaque) so they hide the panel fill drawn under them."""
    mid = tuple((a + b) / 2 for a, b in zip(PANEL_LINE_TOP_LEFT, PANEL_LINE_BOTTOM_RIGHT))
    line = {0: PANEL_LINE_TOP_LEFT, 1: PANEL_LINE_TOP_LEFT, 4: PANEL_LINE_TOP_LEFT,
            2: PANEL_LINE_BOTTOM_RIGHT, 3: PANEL_LINE_BOTTOM_RIGHT, 7: PANEL_LINE_BOTTOM_RIGHT,
            5: mid, 6: mid}

    def sample(px, py):
        d, edge = chamfer_depth(px, py, size, cut)
        if d < 0:
            return 1.0, GROUND
        if d < 1:
            return 1.0, PANEL_EDGE
        if d < 2:
            return 1.0, line[edge]
        return 0.0, (0, 0, 0)
    return supersampled(sample)


# The title bar, top row first (28 rows): dark brown strip, a gold underline, then dark rows.
TITLE_ROWS = [(19, 11, 6), (29, 17, 10), (33, 18, 11)] + [(37, 21, 12)] * 15 + [
    (32, 19, 10), (22, 13, 7), (11, 7, 4), (103, 69, 30), (122, 90, 48),
    (48, 26, 2), (37, 13, 0), (35, 20, 4), (13, 10, 8), (2, 1, 1)]


def title_strip(x, y):
    return (1.0, TITLE_ROWS[y]) if y < len(TITLE_ROWS) else (0.0, (0, 0, 0))


def fade(height):
    """White, opaque at the top fading linearly to clear at the bottom; tinted for gradients."""
    return lambda x, y: (1 - y / (height - 1), (255, 255, 255))


# The portrait's rim in screen pixels from the outside in, for a 72px portrait.
PORTRAIT_SIZE = 72
RING_BANDS = [(16, 13, 8), (166, 120, 75), (142, 102, 61), (104, 72, 39),
              (67, 42, 18), (63, 42, 23), (55, 37, 23), (5, 2, 4)]


def portrait_ring(size):
    """A copper ring, bright outside and dark inside, for a round portrait; clear in the middle."""
    scale = size / PORTRAIT_SIZE

    def sample(px, py):
        d = (size / 2 - math.hypot(px - size / 2, py - size / 2)) / scale  # screen px in from the rim
        if d < 0 or d >= len(RING_BANDS):
            return 0.0, (0, 0, 0)
        return 1.0, RING_BANDS[int(d)]
    return supersampled(sample)


# A bookmark tab, sampled from the profession card's top edge where a tab joins it: three border
# lines, outermost first, and a fill fading from a lighter top to the card's colour just inside its
# edge, so a selected tab reaching over the card's edge blends into it.
TAB_BANDS = [(93, 68, 45), (55, 35, 21), (35, 20, 10)]
TAB_FILL_TOP = (38, 29, 21)
TAB_FILL_BOTTOM = (27, 22, 17)


def tab(size, radius):
    """Rounded top corners, straight sides, no bottom edge (the panel below supplies it)."""
    def sample(px, py):
        cx = radius if px < radius else size - radius if px > size - radius else None
        if cx is not None and py < radius:
            d = radius - math.hypot(px - cx, py - radius)
        else:
            d = min(px, size - px, py)
        if d < 0:
            return 0.0, (0, 0, 0)
        if d < len(TAB_BANDS):
            return 1.0, TAB_BANDS[int(d)]
        t = py / size
        return 1.0, tuple(a + (b - a) * t for a, b in zip(TAB_FILL_TOP, TAB_FILL_BOTTOM))
    return supersampled(sample)


# name -> (width, height, pixel)
UI_TEXTURES = {
    "ui_tab": (64, 64, tab(64, 6)),                # bookmark tab, nine-slice with 8px corners
    "ui_frame": (64, 64, frame_border(64, 6)),     # window edge, nine-slice with 16px corners
    "ui_panel": (32, 32, panel_border(32, 5)),     # panel edge, nine-slice with 8px corners
    "ui_title": (8, 32, title_strip),              # title bar, the top 28 rows used
    "ui_fade": (8, 64, fade(64)),                  # vertical gradients and inner shadows
    "ui_portrait_ring": (128, 128, portrait_ring(128)),
}

if __name__ == "__main__":
    os.makedirs(OUT_DIR, exist_ok=True)
    for name, (size, shape) in TEXTURES.items():
        path = os.path.join(OUT_DIR, name + ".tga")
        write_tga(path, size, shape)
        print("wrote", os.path.normpath(path))
    for name, (width, height, pixel) in FLIPBOOKS.items():
        path = os.path.join(OUT_DIR, name + ".tga")
        write_tga_pixels(path, width, height, pixel)
        print("wrote", os.path.normpath(path))
    for name, (width, height, pixel) in UI_TEXTURES.items():
        path = os.path.join(OUT_DIR, name + ".tga")
        write_tga_rgba(path, width, height, pixel)
        print("wrote", os.path.normpath(path))
