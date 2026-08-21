#!/usr/bin/env python3
"""Generator for the enhanced cartridge's weapon icons.

The pak has art for its own 31 weapons and none for the sixteen this cartridge
adds (mods/enhanced/weapons.lua), so they are drawn here:

    mods/enhanced/assets/weapons/enhanced/*.png        77x38, the pak's size
    mods/enhanced/assets-1080p/weapons/enhanced/*.png  129x64, its hi-res twin

Both are found ahead of the pak by src/engine/assets.lua, which searches
`mods/<name>/assets` first and its `assets-1080p` twin when the display is
dense enough. They are the sizes and the paths the original's own icons use,
which is the point: a hand-painted or model-generated replacement dropped at
the same path wins with no code change at all. Nothing here is load-bearing
beyond "there is a picture of this gun".

Generated rather than painted for the same reason the tower-defence mounts are
(tools/make_td_art.py): art with a source in the repo can be regenerated when
the palette moves, and art that arrived as a binary blob cannot. The family
tints below are `data.FAMILY_COLOR` (mods/vanilla/game/data.lua) in 8-bit,
which is the same table the bolt in the air, the light it throws and the drop
plate on the ground all read -- so a Tesla Arc's icon is the colour its rounds
will be.

The drawings are silhouettes, not portraits: a receiver, a barrel whose length
and bore come from the weapon's own numbers, and one piece of family furniture
(coils, rails, a drum, a canister, a magazine). At 77x38 on a plate that is
what survives anyway.

Run:  python3 tools/make_enhanced_art.py
"""
import math
import os

from PIL import Image, ImageDraw, ImageFilter

# Supersample, then resample down. Cheapest way to get clean diagonals out of
# PIL, and the same trick make_td_art.py uses.
SS = 4

# The drawing space. 129x64 is the pak's hi-res icon size; the 77x38 base twin
# is the same picture resampled, exactly as the original ships it.
W, H = 129, 64
OUT_HI = (129, 64)
OUT_LO = (77, 38)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIR_LO = os.path.join(ROOT, "mods", "enhanced", "assets", "weapons", "enhanced")
DIR_HI = os.path.join(ROOT, "mods", "enhanced", "assets-1080p", "weapons", "enhanced")

# Gunmetal, in the same cold register as the tower-defence pit so a mod's art
# looks like one hand drew it.
STEEL = (74, 78, 86)
STEEL_LO = (46, 49, 55)
STEEL_HI = (112, 118, 128)
EDGE = (12, 12, 14)
GRIP = (52, 42, 34)

# data.FAMILY_COLOR, 8-bit. Each weapon wears the colour of the round it fires.
FAMILY = {
    "bullet": (217, 204, 153),
    "rocket": (255, 153, 89),
    "flame": (255, 140, 51),
    "ion": (51, 153, 255),
}


def box(d, x0, y0, x1, y1, fill, outline=EDGE, width=1.0):
    """A rectangle in drawing-space pixels."""
    d.rectangle([x0 * SS, y0 * SS, x1 * SS, y1 * SS], fill=fill,
                outline=outline, width=max(1, int(width * SS)))


def disc(d, cx, cy, r, fill=None, outline=None, width=1.0):
    d.ellipse([(cx - r) * SS, (cy - r) * SS, (cx + r) * SS, (cy + r) * SS],
              fill=fill, outline=outline, width=max(1, int(width * SS)))


def line(d, x0, y0, x1, y1, colour, width=1.0):
    d.line([x0 * SS, y0 * SS, x1 * SS, y1 * SS], fill=colour,
           width=max(1, int(width * SS)))


# ------------------------------------------------------------------ furniture
#
# One decoration per family. It is what tells two guns of the same length apart
# at plate size, so each is a shape rather than a colour: rings, parallel bars,
# a fat cylinder, a bottle, a box.


def coils(d, x0, x1, mid, tint, count=4):
    """Tesla: rings clamped round the barrel, brightest at the muzzle."""
    for i in range(count):
        x = x0 + (x1 - x0) * (i + 0.6) / count
        k = 0.45 + 0.55 * (i + 1) / count
        colour = tuple(int(c * k) for c in tint)
        box(d, x - 1.6, mid - 6.5, x + 1.6, mid + 6.5, colour, EDGE, 0.75)


def rails(d, x0, x1, mid, tint):
    """Rail: two charged bars the slug runs between."""
    for dy in (-4.0, 4.0):
        box(d, x0, mid + dy - 1.2, x1, mid + dy + 1.2, tint, EDGE, 0.75)
    line(d, x0 + 2, mid, x1 - 2, mid, tuple(min(255, c + 40) for c in tint), 0.9)


def drum(d, cx, mid, tint):
    """Ordnance: a fat cylinder of things to throw."""
    disc(d, cx, mid + 1.5, 9.0, STEEL, EDGE, 0.9)
    disc(d, cx, mid + 1.5, 5.0, tuple(int(c * 0.55) for c in tint), EDGE, 0.75)


def canister(d, cx, mid, tint):
    """Acid: a bottle slung under the receiver, and a hose to the gun."""
    box(d, cx - 7, mid + 2, cx + 7, mid + 13, tuple(int(c * 0.5) for c in tint),
        EDGE, 0.9)
    box(d, cx - 4, mid + 4, cx + 4, mid + 11, tint, None)
    line(d, cx + 7, mid + 5, cx + 15, mid - 1, STEEL_LO, 1.4)


def magazine(d, cx, mid, tint):
    """Kinetic: a box magazine, raked forward the way every real one is."""
    d.polygon([((cx - 5) * SS, (mid + 3) * SS), ((cx + 6) * SS, (mid + 3) * SS),
               ((cx + 9) * SS, (mid + 15) * SS), ((cx - 2) * SS, (mid + 15) * SS)],
              fill=STEEL_LO, outline=EDGE, width=SS)


FURNITURE = {
    "coils": coils, "rails": rails, "drum": drum,
    "canister": canister, "magazine": magazine,
}

# ----------------------------------------------------------------------- marks
#
# Family furniture tells a tesla weapon from a rail. It does not tell one rail
# from another, and the first draft of these icons proved it: six rails came
# out as six copies of the same picture, which is exactly the "false variety"
# this arsenal was built to answer -- in the art this time instead of the code.
#
# So every weapon also gets one shape of its own, chosen to say what the weapon
# *does* rather than to be different: a scope on the one that rewards distance,
# a spool on the one that fires from a planted anchor, capacitor cans on the
# two that store a charge, a prism on the one that splits.


def scope(d, x0, x1, mid, tint):
    """It pays off at range, so it has something to see with."""
    cx = x0 + (x1 - x0) * 0.35
    box(d, cx - 9, mid - 13, cx + 11, mid - 8, STEEL, EDGE, 0.9)
    for x in (cx - 6, cx + 6):
        box(d, x - 0.9, mid - 14, x + 0.9, mid - 7, STEEL_LO, None)


def brake(d, x0, x1, mid, tint):
    """Two shots and a shove: a muzzle brake big enough to explain both."""
    box(d, x1 - 9, mid - 8, x1 + 1, mid + 8, STEEL, EDGE, 1.0)
    for dy in (-5.0, 0.0, 5.0):
        box(d, x1 - 7, mid + dy - 0.8, x1 - 1, mid + dy + 0.8, EDGE, None)


def cans(d, x0, x1, mid, tint):
    """Stored charge, sitting where a player can see how much of it there is."""
    cx = x0 + (x1 - x0) * 0.25
    for i in range(2):
        x = cx + i * 11
        box(d, x, mid - 15, x + 8, mid - 8, tuple(int(c * 0.7) for c in tint),
            EDGE, 0.9)
        line(d, x + 1.5, mid - 13.5, x + 6.5, mid - 13.5, tint, 0.9)


def prism(d, x0, x1, mid, tint):
    """The beam leaves as one and arrives as three."""
    d.polygon([((x1 - 2) * SS, (mid - 9) * SS), ((x1 + 7) * SS, mid * SS),
               ((x1 - 2) * SS, (mid + 9) * SS)],
              fill=tuple(int(c * 0.8) for c in tint), outline=EDGE, width=SS)


def fins(d, x0, x1, mid, tint):
    """It leaves the path burning, so the barrel has somewhere to put the heat."""
    n = 6
    for i in range(n):
        x = x0 + (x1 - x0) * (i + 0.5) / n
        box(d, x - 0.8, mid - 11, x + 0.8, mid - 4, STEEL_LO, EDGE, 0.5)


def spool(d, x0, x1, mid, tint):
    """The shot starts at an anchor, and something had to pay it out."""
    cx = x0 + (x1 - x0) * 0.3
    disc(d, cx, mid + 9, 7.0, STEEL, EDGE, 0.9)
    disc(d, cx, mid + 9, 2.6, tuple(int(c * 0.6) for c in tint), EDGE, 0.6)


def darts(d, x0, x1, mid, tint):
    """A rack of the things it plants in people."""
    for i in range(5):
        x = x0 + i * 5.5
        d.polygon([(x * SS, (mid - 9) * SS), ((x + 3) * SS, (mid - 9) * SS),
                   ((x + 1.5) * SS, (mid - 15) * SS)],
                  fill=tint, outline=EDGE, width=SS)


def horn(d, x0, x1, mid, tint):
    """It gathers a crowd rather than piercing one, so it opens out."""
    d.polygon([((x1 - 8) * SS, (mid - 5) * SS), ((x1 + 5) * SS, (mid - 13) * SS),
               ((x1 + 5) * SS, (mid + 13) * SS), ((x1 - 8) * SS, (mid + 5) * SS)],
              fill=tuple(int(c * 0.55) for c in tint), outline=EDGE, width=SS)


MARKS = {
    "scope": scope, "brake": brake, "cans": cans, "prism": prism,
    "fins": fins, "spool": spool, "darts": darts, "horn": horn,
}


# --------------------------------------------------------------------- weapons
#
# Per weapon: the family whose colour it wears, its furniture, and three
# proportions -- how far the barrel reaches, how thick it is, and how much
# receiver is behind it. They are the same three things the tower-defence
# mounts read off the live weapon (plots.lua); here they are written down,
# because an icon is drawn once and a mount head is drawn every frame.
#
# `stock` is the shoulder end: a heavy weapon has something to brace against.

WEAPONS = {
    "bouncer-smg":     dict(family="bullet", furniture="magazine", reach=0.74, bore=2.6, body=30, stock=True),
    "tesla-arc":       dict(family="ion",    furniture="coils",    reach=0.70, bore=3.4, body=34, stock=False),
    "nail-grenade":    dict(family="rocket", furniture="drum",     reach=0.62, bore=6.5, body=26, stock=True),
    "acid-sprayer":    dict(family="flame",  furniture="canister", reach=0.66, bore=3.8, body=30, stock=False),
    "sniper-rail":     dict(family="bullet", furniture="rails",    reach=0.96, bore=2.2, body=36, stock=True,  mark="scope"),
    "node-gun":        dict(family="ion",    furniture="coils",    reach=0.72, bore=2.8, body=30, stock=False, mark="darts"),
    "flak-cannon":     dict(family="rocket", furniture="drum",     reach=0.70, bore=7.5, body=30, stock=True,  mark="brake"),
    "prism-rail":      dict(family="bullet", furniture="rails",    reach=0.88, bore=3.0, body=32, stock=True,  mark="prism"),
    "arc-lasso":       dict(family="ion",    furniture="coils",    reach=0.58, bore=4.6, body=28, stock=False, mark="horn"),
    "tracer-rail":     dict(family="bullet", furniture="rails",    reach=0.90, bore=2.8, body=32, stock=True,  mark="fins"),
    "rail-spike":      dict(family="bullet", furniture="rails",    reach=0.94, bore=3.6, body=38, stock=True,  mark="cans"),
    "capacitor-rifle": dict(family="ion",    furniture="coils",    reach=0.78, bore=3.2, body=34, stock=True,  mark="cans"),
    "ball-lightning":  dict(family="ion",    furniture="drum",     reach=0.56, bore=8.0, body=28, stock=False),
    "tether-rail":     dict(family="bullet", furniture="rails",    reach=0.86, bore=3.0, body=34, stock=True,  mark="spool"),
    "storm-ring":      dict(family="ion",    furniture="coils",    reach=0.34, bore=9.0, body=30, stock=False, mark="horn"),
    "rail-cannon":     dict(family="bullet", furniture="rails",    reach=0.92, bore=5.0, body=40, stock=True,  mark="brake"),
}


def draw_weapon(spec):
    img = Image.new("RGBA", (W * SS, H * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    tint = FAMILY[spec["family"]]
    mid = H * 0.46          # the bore line, a little above centre: the grip
    left = 8                # and the magazine hang below it
    body = spec["body"]
    muzzle = left + (W - left - 6) * spec["reach"]
    bore = spec["bore"]

    # Stock first, so the receiver is drawn over where they meet.
    if spec["stock"]:
        d.polygon([(left * SS, (mid - 5) * SS), ((left + 10) * SS, (mid - 5) * SS),
                   ((left + 10) * SS, (mid + 7) * SS), ((left - 4) * SS, (mid + 11) * SS)],
                  fill=GRIP, outline=EDGE, width=SS)

    # Barrel, then receiver over its root.
    box(d, left + body * 0.6, mid - bore, muzzle, mid + bore, STEEL, EDGE, 0.9)
    box(d, left + 2, mid - 7, left + body, mid + 6, STEEL, EDGE, 1.0)
    box(d, left + 3, mid - 6, left + body - 1, mid - 3, STEEL_HI, None)
    box(d, left + 3, mid + 3, left + body - 1, mid + 5, STEEL_LO, None)

    # Grip, under the back of the receiver.
    d.polygon([((left + 9) * SS, (mid + 5) * SS), ((left + 16) * SS, (mid + 5) * SS),
               ((left + 14) * SS, (mid + 17) * SS), ((left + 6) * SS, (mid + 17) * SS)],
              fill=GRIP, outline=EDGE, width=SS)

    # Furniture that lives along the barrel spans it; furniture that hangs off
    # the gun sits just ahead of the receiver, clear of the grip -- the first
    # draft put a magazine and a canister on top of it and both disappeared.
    if spec["furniture"] in ("coils", "rails"):
        FURNITURE[spec["furniture"]](d, left + body * 0.65, muzzle - 2, mid, tint)
    else:
        FURNITURE[spec["furniture"]](d, left + body + 8, mid, tint)

    if spec.get("mark"):
        MARKS[spec["mark"]](d, left + body * 0.7, muzzle, mid, tint)

    # The muzzle glows in the family's colour -- the one place on a 77px plate
    # where the weapon says what it fires rather than what it is made of.
    glow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([(muzzle - bore - 3) * SS, (mid - bore - 3) * SS,
                (muzzle + bore + 3) * SS, (mid + bore + 3) * SS],
               fill=tint + (170,))
    glow = glow.filter(ImageFilter.GaussianBlur(radius=2.2 * SS))
    img = Image.alpha_composite(img, glow)
    return img


def main():
    os.makedirs(DIR_LO, exist_ok=True)
    os.makedirs(DIR_HI, exist_ok=True)
    for name, spec in WEAPONS.items():
        img = draw_weapon(spec)
        img.resize(OUT_HI, Image.LANCZOS).save(os.path.join(DIR_HI, name + ".png"))
        img.resize(OUT_LO, Image.LANCZOS).save(os.path.join(DIR_LO, name + ".png"))
    print("wrote %d icons to %s (and its hi-res twin)" % (len(WEAPONS), DIR_LO))


if __name__ == "__main__":
    main()
