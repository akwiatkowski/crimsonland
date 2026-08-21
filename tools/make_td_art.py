#!/usr/bin/env python3
"""Generator for the tower-defence mod's mount art.

The mod ships art the original never had (mods/towerdefence/assets/, found
ahead of the pak by src/engine/assets.lua). The pieces here are the two halves
of a gun pit:

    td/mount-plate.png    128x128, drawn as 64 world px -- the pit itself
    td/mount-collar.png   160x160, drawn as 80 world px -- the tier-2 barbette

They are generated rather than painted so that they stay reproducible: the
palette below is the same bone/brass the HUD uses, and if it moves, one run of
this script moves the art with it. Wear is seeded, so re-running produces the
same bytes.

The *head* -- the gun that turns -- is deliberately not here. It is drawn from
the weapon's own numbers at runtime (mods/towerdefence/game/plots.lua), because
there are 38 weapons and one of them can be bolted to any mount.

Run:  python3 tools/make_td_art.py
"""
import math
import os
import random

from PIL import Image, ImageDraw

# Supersampling factor. Everything is drawn at SS times the final size and
# resampled down, which is the cheapest way to get clean curves out of PIL.
SS = 4

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "mods", "towerdefence", "assets", "td")

# The HUD's palette (mods/towerdefence/game/hud.lua), as 8-bit RGB.
# The pit floor has to sit clearly *above* the terrain (38, 34, 32) and clearly
# below the head that stands in it, or it reads as a hole in the ground -- which
# is the note the base plate was drawn to answer, and the first draft of this
# one earned all over again.
PIT = (58, 60, 66)        # cold steel, cooler than the warm ground
PIT_LO = (40, 42, 47)     # the floor's south-east half, away from the light
WELL = (24, 25, 30)       # the trunnion well the head sits in
BRASS = (217, 174, 71)
WORN = (138, 110, 46)     # brass that has been outside
LIT = (172, 140, 62)      # the rim's north-west edge, catching what light there is
EDGE = (10, 10, 12)       # the hairline that seats a piece on the ground

# One geometry, expressed in world pixels, so the numbers here are the same
# numbers plots.lua reaches with. Both images are drawn at 2 image px per world
# px, which is what makes 128 -> 64 and 160 -> 80.
PX_PER_UNIT = 2
PIT_R = 30.0              # the pit's outer rim
WELL_R = 13.0             # the socket, hidden under the head when one stands here
COLLAR_R = 33.0           # the tier-2 ring
LUG_OUT = 37.0            # how far the buttress lugs reach past it


def canvas(size_units):
    """A transparent square canvas covering `size_units` world px, and a draw
    context whose origin is its centre."""
    px = int(size_units * PX_PER_UNIT * SS)
    img = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img), px / 2


def circle(d, o, r, fill=None, outline=None, width=1.0):
    r *= PX_PER_UNIT * SS
    d.ellipse([o - r, o - r, o + r, o + r], fill=fill, outline=outline,
              width=max(1, int(width * PX_PER_UNIT * SS)))


def arc(d, o, r, a0, a1, colour, width=1.0):
    r *= PX_PER_UNIT * SS
    d.arc([o - r, o - r, o + r, o + r], a0, a1, fill=colour,
          width=max(1, int(width * PX_PER_UNIT * SS)))


def at(o, r, a):
    """Image coordinates of the point `r` world px out along angle `a`."""
    return o + math.cos(a) * r * PX_PER_UNIT * SS, o + math.sin(a) * r * PX_PER_UNIT * SS


def bolt(d, o, r, a):
    """A bolt head: worn brass with a darker socket, so it reads as sunk in
    rather than stuck on."""
    x, y = at(o, r, a)
    s = 2.4 * PX_PER_UNIT * SS
    d.ellipse([x - s, y - s, x + s, y + s], fill=WORN)
    s *= 0.45
    d.ellipse([x - s, y - s, x + s, y + s], fill=EDGE)


def wear(img, o, r_in, r_out, seed, count, light=True):
    """Seeded speckle inside an annulus -- grit, pitting, and the odd bright
    scrape. Deterministic, so regenerating the art does not churn the repo."""
    rng = random.Random(seed)
    d = ImageDraw.Draw(img)
    for _ in range(count):
        a = rng.uniform(0, math.tau)
        r = math.sqrt(rng.uniform((r_in / r_out) ** 2, 1.0)) * r_out
        x, y = at(o, r, a)
        s = rng.uniform(0.4, 1.4) * PX_PER_UNIT * SS
        v = rng.randint(10, 34) * (1 if (light and rng.random() < 0.45) else -1)
        d.ellipse([x - s, y - s, x + s, y + s], fill=(128 + v, 128 + v, 128 + v,
                                                      rng.randint(18, 46)))


def finish(img, size_units, path):
    px = int(size_units * PX_PER_UNIT)
    img = img.resize((px, px), Image.LANCZOS)
    img.save(path)
    print("wrote %s (%dx%d)" % (os.path.relpath(path, ROOT), px, px))


def mount_plate():
    """Tier one: a bolted pit, quiet enough that the gun standing in it is what
    the eye goes to."""
    img, d, o = canvas(64)

    circle(d, o, PIT_R, fill=EDGE)                       # seat
    circle(d, o, PIT_R - 0.8, fill=PIT_LO)               # floor, shaded half
    d.pieslice([o - (PIT_R - 0.8) * PX_PER_UNIT * SS] * 2
               + [o + (PIT_R - 0.8) * PX_PER_UNIT * SS] * 2, 160, 340, fill=PIT)
    circle(d, o, PIT_R - 1.6, outline=WORN, width=1.8)   # rim
    arc(d, o, PIT_R - 1.6, 170, 320, LIT, width=1.8)     # lit north-west edge

    # the well: darker, and rimmed, so the head reads as standing *in* the pit
    circle(d, o, WELL_R + 1.2, fill=(16, 17, 21, 255))
    circle(d, o, WELL_R, fill=WELL)
    arc(d, o, WELL_R + 0.6, 160, 340, (10, 10, 12), width=1.6)

    # two bolts, north and south: the light mount is held down, not armoured
    for a in (-math.pi / 2, math.pi / 2):
        bolt(d, o, 25, a)

    wear(img, o, WELL_R + 2, PIT_R - 2, seed=1101, count=120)
    finish(img, 64, os.path.join(OUT_DIR, "mount-plate.png"))


def mount_collar():
    """Tier two: an armoured barbette dropped over the same pit. It is a ring
    with four buttress lugs, echoing the base's own bearings, and it is the
    reason a reinforced mount is recognisable from the far side of the field
    rather than a shade brighter than a light one."""
    img, d, o = canvas(80)

    circle(d, o, COLLAR_R, outline=EDGE, width=2.8)
    circle(d, o, COLLAR_R, outline=BRASS, width=1.8)
    arc(d, o, COLLAR_R, 170, 320, (240, 205, 120), width=1.8)

    # the lugs go on last: they are what the collar is, and a ring drawn over
    # them turns four buttresses back into one more circle
    for i in range(4):
        a = math.pi / 4 + i * math.pi / 2
        pts = []
        for px, py in ((28, -9.5), (LUG_OUT, -6.0), (LUG_OUT, 6.0), (28, 9.5)):
            c, s = math.cos(a), math.sin(a)
            pts.append((o + (px * c - py * s) * PX_PER_UNIT * SS,
                        o + (px * s + py * c) * PX_PER_UNIT * SS))
        d.polygon(pts, fill=WORN, outline=EDGE, width=SS)
        bolt(d, o, 33, a)

    wear(img, o, 26, LUG_OUT, seed=2202, count=70)
    finish(img, 80, os.path.join(OUT_DIR, "mount-collar.png"))


if __name__ == "__main__":
    os.makedirs(OUT_DIR, exist_ok=True)
    mount_plate()
    mount_collar()
