# -*- coding: utf-8 -*-
"""contact.py - grouped contact sheets for visual inspection."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from PIL import Image, ImageDraw
import gen_art as G

ART = G.ART
A = G.build_all()


def sheet(path, names, scale, cols, label=True):
    cells = []
    for n in names:
        if n not in A:
            continue
        for i, f in enumerate(A[n]):
            cells.append(("%s#%d" % (n, i), f))
    if not cells:
        return
    cw = max(c[1].w for c in cells) * scale + 8
    ch = max(c[1].h for c in cells) * scale + (18 if label else 4)
    rows = (len(cells) + cols - 1) // cols
    img = Image.new("RGBA", (cw * cols, ch * rows), (24, 24, 40, 255))
    d = ImageDraw.Draw(img)
    for i, (nm, f) in enumerate(cells):
        cx = (i % cols) * cw
        cy = (i // cols) * ch
        img.alpha_composite(f.img.resize((f.w * scale, f.h * scale), Image.NEAREST), (cx + 4, cy + 16))
        if label:
            d.text((cx + 4, cy + 3), nm[:26], fill=(210, 220, 255, 255))
    img.save(path)
    print(os.path.basename(path), img.size, len(cells), "cells")


ENEMIES = ["enemy_" + k for k in ("grunt", "lancer", "bomber", "splitter",
                                  "darter", "tank", "flyer", "summoner")]
sheet(os.path.join(ART, "_c_actors.png"), ["player", "gun", "eye"] + ENEMIES, 5, 8)
sheet(os.path.join(ART, "_c_boss.png"), ["boss_0", "boss_1", "boss_2"], 3, 6)
sheet(os.path.join(ART, "_c_proj.png"), [k for k in sorted(A) if k.startswith(("proj_", "eproj_"))], 6, 12)
sheet(os.path.join(ART, "_c_pick.png"), ["pickup_xp", "pickup_gear", "pickup_hp", "pickup_chest"], 6, 8)
sheet(os.path.join(ART, "_c_vfx.png"), [k for k in sorted(A) if k.startswith("vfx_")], 3, 10)
sheet(os.path.join(ART, "_c_tiles.png"), [k for k in sorted(A) if k.startswith(("floor_", "wall_", "pillar_", "crate_"))], 3, 8)
sheet(os.path.join(ART, "_c_ui.png"), [k for k in sorted(A) if k.startswith("ui_")], 3, 4)
sheet(os.path.join(ART, "_c_icons.png"), [k for k in sorted(A) if k.startswith("icon_")], 6, 12)
