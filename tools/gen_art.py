# -*- coding: utf-8 -*-
"""gen_art.py - procedurally generate ALL pixel art for Neon Corridor.

Outputs:  assets/art/atlas_<n>.png  +  assets/art/atlas.json
Usage:    python tools/gen_art.py [--contact]
"""
from __future__ import annotations
import json, math, os, random, sys
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = os.path.join(ROOT, "assets", "art")
random.seed(20260930)


def rgba(h, a=255):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


P = {
    "void":   rgba("0a0a14"), "dark":   rgba("16142c"), "mid":   rgba("2c2852"),
    "steel":  rgba("545278"), "light":  rgba("9292b8"), "white": rgba("eef2ff"),
    "cyan":   rgba("34f0ff"), "cyanD":  rgba("1684b8"), "cyanDD": rgba("0e4a6e"),
    "pink":   rgba("ff3e82"), "pinkD":  rgba("a81c58"),
    "red":    rgba("ff4c3a"), "redD":   rgba("9c221e"),
    "orange": rgba("ff9a30"), "orangeD": rgba("b85c10"),
    "yellow": rgba("ffe460"), "green":  rgba("58f08e"), "greenD": rgba("1a8c5c"),
    "purple": rgba("a25eff"), "purpleD": rgba("5c2aa4"),
    "blue":   rgba("4c86ff"), "blueD":  rgba("223e9c"),
}
CLEAR = (0, 0, 0, 0)


class Canvas:
    __slots__ = ("w", "h", "img", "px")

    def __init__(self, w, h):
        self.w, self.h = w, h
        self.img = Image.new("RGBA", (w, h), CLEAR)
        self.px = self.img.load()

    def p(self, x, y, c):
        if c is None:
            return
        x, y = int(x), int(y)
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[x, y] = c

    def blend(self, x, y, c, a):
        x, y = int(x), int(y)
        if not (0 <= x < self.w and 0 <= y < self.h) or a <= 0:
            return
        r, g, b, al = self.px[x, y]
        cr, cg, cb, _ = c
        self.px[x, y] = (int(r + (cr - r) * a), int(g + (cg - g) * a),
                         int(b + (cb - b) * a), min(255, max(al, int(255 * a))))

    def glow(self, x, y, c, a):
        x, y = int(x), int(y)
        if not (0 <= x < self.w and 0 <= y < self.h) or a <= 0:
            return
        r, g, b, al = self.px[x, y]
        cr, cg, cb, _ = c
        self.px[x, y] = (min(255, int(r + cr * a)), min(255, int(g + cg * a)),
                         min(255, int(b + cb * a)), min(255, max(al, int(255 * min(1, a)))))

    def rect(self, x, y, w, h, c):
        for j in range(int(h)):
            for i in range(int(w)):
                self.p(x + i, y + j, c)

    def rect_out(self, x, y, w, h, c, t=1):
        for k in range(t):
            for i in range(int(w)):
                self.p(x + i, y + k, c)
                self.p(x + i, y + h - 1 - k, c)
            for j in range(int(h)):
                self.p(x + k, y + j, c)
                self.p(x + w - 1 - k, y + j, c)

    def disc(self, cx, cy, r, c):
        r2 = r * r
        for j in range(int(cy - r) - 1, int(cy + r) + 2):
            for i in range(int(cx - r) - 1, int(cx + r) + 2):
                dx, dy = i + 0.5 - cx, j + 0.5 - cy
                if dx * dx + dy * dy <= r2:
                    self.p(i, j, c)

    def glow_disc(self, cx, cy, r, c, a=0.5, falloff=1.0):
        for j in range(int(cy - r) - 1, int(cy + r) + 2):
            for i in range(int(cx - r) - 1, int(cx + r) + 2):
                d = math.hypot(i + 0.5 - cx, j + 0.5 - cy)
                if d <= r:
                    self.glow(i, j, c, a * ((1.0 - d / r) ** falloff))

    def ring(self, cx, cy, r, c, t=1.0):
        for j in range(int(cy - r - t) - 1, int(cy + r + t) + 2):
            for i in range(int(cx - r - t) - 1, int(cx + r + t) + 2):
                d = math.hypot(i + 0.5 - cx, j + 0.5 - cy)
                if r - t * 0.5 <= d <= r + t * 0.5:
                    self.p(i, j, c)

    def line(self, x0, y0, x1, y1, c):
        x0, y0, x1, y1 = int(x0), int(y0), int(x1), int(y1)
        dx, dy = abs(x1 - x0), -abs(y1 - y0)
        sx = 1 if x0 < x1 else -1
        sy = 1 if y0 < y1 else -1
        err = dx + dy
        while True:
            self.p(x0, y0, c)
            if x0 == x1 and y0 == y1:
                break
            e2 = 2 * err
            if e2 >= dy:
                err += dy; x0 += sx
            if e2 <= dx:
                err += dx; y0 += sy

    def poly(self, pts, c):
        if not pts:
            return
        ys = [p[1] for p in pts]
        for y in range(int(min(ys)), int(max(ys)) + 1):
            xs = []
            n = len(pts)
            for k in range(n):
                x0, y0 = pts[k]; x1, y1 = pts[(k + 1) % n]
                if y0 == y1:
                    continue
                if (y >= min(y0, y1)) and (y < max(y0, y1)):
                    t = (y - y0) / (y1 - y0)
                    xs.append(x0 + t * (x1 - x0))
            xs.sort()
            for k in range(0, len(xs) - 1, 2):
                for x in range(int(math.ceil(xs[k])), int(math.floor(xs[k + 1])) + 1):
                    self.p(x, y, c)

    def star(self, cx, cy, r, spikes, c, inner=0.45, phase=0.0):
        pts = []
        for k in range(spikes * 2):
            ang = phase + k * math.pi / spikes
            rr = r if k % 2 == 0 else r * inner
            pts.append((cx + math.cos(ang) * rr, cy + math.sin(ang) * rr))
        self.poly(pts, c)

    def ngon(self, cx, cy, r, n, c, phase=0.0):
        pts = [(cx + math.cos(phase + k * 2 * math.pi / n) * r,
                cy + math.sin(phase + k * 2 * math.pi / n) * r) for k in range(n)]
        self.poly(pts, c)

    def outline(self, c, include_diag=True):
        src = self.img.copy().load()
        offs = [(-1, 0), (1, 0), (0, -1), (0, 1)]
        if include_diag:
            offs += [(-1, -1), (1, -1), (-1, 1), (1, 1)]
        for y in range(self.h):
            for x in range(self.w):
                if src[x, y][3] > 40:
                    continue
                for ox, oy in offs:
                    xx, yy = x + ox, y + oy
                    if 0 <= xx < self.w and 0 <= yy < self.h and src[xx, yy][3] > 128:
                        self.px[x, y] = c
                        break


class Packer:
    def __init__(self, page=2048, pad=2):
        self.page = page; self.pad = pad
        self.pages = []; self.anim = {}
        self._new_page()

    def _new_page(self):
        self.pages.append({"img": Image.new("RGBA", (self.page, self.page), CLEAR),
                           "cx": self.pad, "cy": self.pad, "row": 0})

    def add(self, name, frames):
        if not frames:
            return
        w, h = frames[0].w, frames[0].h
        pg = self.pages[-1]
        if pg["cx"] + w + self.pad > self.page:
            pg["cx"] = self.pad; pg["cy"] += pg["row"] + self.pad; pg["row"] = 0
        if pg["cy"] + h + self.pad > self.page:
            self._new_page(); pg = self.pages[-1]
        regs = []
        for f in frames:
            if pg["cx"] + w + self.pad > self.page:
                pg["cx"] = self.pad; pg["cy"] += pg["row"] + self.pad; pg["row"] = 0
                if pg["cy"] + h + self.pad > self.page:
                    self._new_page(); pg = self.pages[-1]
            pg["img"].paste(f.img, (pg["cx"], pg["cy"]))
            regs.append([pg["cx"], pg["cy"]])
            pg["cx"] += w + self.pad
            pg["row"] = max(pg["row"], h)
        self.anim[name] = {"page": len(self.pages) - 1, "w": w, "h": h, "frames": regs}

    def save(self, outdir):
        os.makedirs(outdir, exist_ok=True)
        files = []
        for i, pg in enumerate(self.pages):
            fn = "atlas_%d.png" % i
            pg["img"].save(os.path.join(outdir, fn))
            files.append(fn)
        meta = {"pages": files, "page_size": self.page, "anim": self.anim}
        with open(os.path.join(outdir, "atlas.json"), "w", encoding="utf-8") as fh:
            json.dump(meta, fh, separators=(",", ":"))
        return files


def build_player():
    out = []
    for f in range(4):
        c = Canvas(24, 24)
        bob = [0, 0, -1, -1][f]
        ox, oy = 12.0, 12.0 + bob
        fl = [3, 4, 5, 4][f]
        for sy in (-4, 4):
            c.glow(ox - 8, oy + sy, P["cyan"], 0.45)
            c.line(ox - 7, oy + sy, ox - 7 - fl, oy + sy, P["cyanD"])
            c.p(ox - 8 - fl, oy + sy, P["cyan"])
        c.ngon(ox, oy, 9.5, 8, P["steel"], math.pi / 8)
        c.ngon(ox, oy, 8.0, 8, P["mid"], math.pi / 8)
        for a in (math.pi * 0.75, math.pi * 1.25):
            c.line(ox + math.cos(a) * 4, oy + math.sin(a) * 4,
                   ox + math.cos(a) * 8, oy + math.sin(a) * 8, P["light"])
        c.poly([(ox + 5, oy - 5), (ox + 12, oy), (ox + 5, oy + 5)], P["light"])
        c.poly([(ox + 6, oy - 3), (ox + 11, oy), (ox + 6, oy + 3)], P["steel"])
        c.glow_disc(ox - 1, oy, 5.5, P["cyan"], 0.5 + 0.35 * (1.0 if f == 2 else 0.0))
        c.disc(ox - 1, oy, 3.2, P["cyan"])
        c.disc(ox - 1, oy, 1.6, P["white"])
        for sy in (-7, 7):
            c.rect(ox - 4, oy + sy - 2, 6, 4, P["mid"])
            c.rect_out(ox - 4, oy + sy - 2, 6, 4, P["steel"])
            c.p(ox + 2, oy + sy, P["cyanD"])
        c.outline(P["void"])
        out.append(c)
    return out


def build_gun():
    out = []
    for f in range(3):
        c = Canvas(16, 10)
        c.rect(2, 3, 10, 4, P["steel"])
        c.rect(3, 4, 8, 2, P["mid"])
        c.rect(11, 3, 3, 4, P["light"])
        if f == 0:
            c.glow(15, 5, P["yellow"], 1.0)
            c.disc(14, 5, 1.6, P["white"])
        c.outline(P["void"])
        out.append(c)
    return out


def build_enemy(kind):
    R = {"grunt": 20, "lancer": 22, "bomber": 22, "splitter": 24,
         "darter": 22, "tank": 30, "flyer": 24, "summoner": 26}[kind]
    col, colD, colL = {
        "grunt":    (P["red"], P["redD"], P["orange"]),
        "lancer":   (P["pink"], P["pinkD"], P["white"]),
        "bomber":   (P["orange"], P["orangeD"], P["yellow"]),
        "splitter": (P["green"], P["greenD"], P["white"]),
        "darter":   (P["yellow"], rgba("8a6a10"), P["white"]),
        "tank":     (P["blue"], P["blueD"], P["cyan"]),
        "flyer":    (P["purple"], P["purpleD"], P["white"]),
        "summoner": (P["yellow"], rgba("8a6a10"), P["orange"]),
    }[kind]
    out = []
    for f in range(4):
        c = Canvas(R, R)
        cx = cy = R / 2.0
        k = f / 4.0 * math.tau
        if kind == "grunt":
            c.star(cx, cy, 8.5 + math.sin(k) * 0.6, 8, colD, 0.42, k * 0.5)
            c.star(cx, cy, 5.5, 8, col, 0.45, k * 0.5)
            c.glow_disc(cx, cy, 5.0, col, 0.22)
            c.disc(cx, cy, 2.2 - 0.3 * math.sin(k), colL)
        elif kind == "lancer":
            c.ngon(cx, cy, 9.5, 6, colD, k * 0.25)
            c.ngon(cx, cy, 7.0, 6, col, k * 0.25)
            c.glow_disc(cx, cy, 6.0, col, 0.3)
            c.rect(cx - 1, cy - 7, 2, 14, colL)
            c.disc(cx, cy, 2.4, colL)
        elif kind == "bomber":
            p = 0.5 + 0.5 * math.sin(k)
            c.disc(cx, cy, 9.0, colD)
            c.disc(cx, cy, 7.5 + p, col)
            c.glow_disc(cx, cy, 6.0 + p * 2, colL, 0.25 + 0.35 * p)
            c.disc(cx, cy, 2.5 + p * 1.5, colL)
            for a in range(4):
                ang = a * math.pi / 2
                c.p(cx + math.cos(ang) * 9.5, cy + math.sin(ang) * 9.5, colL)
        elif kind == "splitter":
            s = 8.5
            c.poly([(cx - s, cy - s), (cx + s, cy - s), (cx + s, cy + s), (cx - s, cy + s)], colD)
            c.poly([(cx - s + 2, cy - s + 2), (cx + s - 2, cy - s + 2),
                    (cx + s - 2, cy + s - 2), (cx - s + 2, cy + s - 2)], col)
            c.line(cx - s + 2, cy, cx + s - 2, cy, colD)
            c.line(cx, cy - s + 2, cx, cy + s - 2, colD)
            c.glow_disc(cx, cy, 5.0 + math.sin(k) * 1.5, col, 0.3)
            c.disc(cx, cy, 2.0, colL)
        elif kind == "darter":
            c.poly([(cx + 10, cy), (cx - 4, cy - 6), (cx - 1, cy), (cx - 4, cy + 6)], colD)
            c.poly([(cx + 8, cy), (cx - 2, cy - 4), (cx, cy), (cx - 2, cy + 4)], col)
            c.glow_disc(cx + 1, cy, 4.5, col, 0.28)
            c.disc(cx + 4, cy, 1.8, colL)
            for a in (0.62, -0.62):
                c.line(cx - 6, cy + math.sin(a) * 7, cx - 11, cy + math.sin(a) * 9, colD)
        elif kind == "tank":
            c.ngon(cx, cy, 13.5, 8, colD, math.pi / 8)
            c.ngon(cx, cy, 11.5, 8, col, math.pi / 8)
            for i in range(4):
                a = math.pi / 4 + i * math.pi / 2
                c.line(cx + math.cos(a) * 6, cy + math.sin(a) * 6,
                       cx + math.cos(a) * 12, cy + math.sin(a) * 12, colL)
            c.glow_disc(cx, cy, 7.0, col, 0.3)
            c.disc(cx, cy, 3.5, colL)
            c.ring(cx, cy, 5.5 + math.sin(k) * 0.5, colL, 1.0)
        elif kind == "flyer":
            flap = math.sin(k) * 2.0
            for s in (-1, 1):
                c.poly([(cx + s * 3, cy), (cx + s * 11, cy - 5 - flap),
                        (cx + s * 9, cy + 1), (cx + s * 11, cy + 5 + flap)], colD)
            c.ngon(cx, cy, 7.0, 4, colD, math.pi / 4)
            c.ngon(cx, cy, 5.0, 4, col, math.pi / 4)
            c.glow_disc(cx, cy, 5.5, col, 0.3)
            c.disc(cx, cy, 2.2, colL)
        elif kind == "summoner":
            c.ring(cx, cy, 10.0, colD, 3.0)
            c.ring(cx, cy, 9.0, col, 2.0)
            c.disc(cx, cy, 4.5, colD)
            c.disc(cx, cy, 3.5, col)
            c.glow_disc(cx, cy, 8.0, col, 0.25)
            for i in range(3):
                a = k * 1.4 + i * math.tau / 3
                ox, oy = cx + math.cos(a) * 10, cy + math.sin(a) * 10
                c.disc(ox, oy, 2.4, colL)
                c.glow_disc(ox, oy, 4.0, col, 0.35)
        c.outline(P["void"])
        out.append(c)
    return out


def build_boss(idx):
    R = 96
    col, colD, colL = {
        0: (P["pink"], P["pinkD"], P["white"]),
        1: (P["purple"], P["purpleD"], P["cyan"]),
        2: (P["red"], P["redD"], P["yellow"]),
    }[idx]
    out = []
    for f in range(6):
        c = Canvas(R, R)
        cx = cy = R / 2.0
        k = f / 6.0 * math.tau
        n = 6 + idx
        for i in range(n):
            a = k * (1 + idx * 0.4) + i * math.tau / n
            x0, y0 = cx + math.cos(a) * 24, cy + math.sin(a) * 24
            x1 = cx + math.cos(a) * (40 + 3 * math.sin(k * 2))
            y1 = cy + math.sin(a) * (40 + 3 * math.sin(k * 2))
            c.line(x0, y0, x1, y1, colD)
            c.glow_disc(x1, y1, 7.0, col, 0.3)
            c.disc(x1, y1, 3.0 + idx, col)
        c.ngon(cx, cy, 32, 8, colD, k * 0.3)
        c.ngon(cx, cy, 28, 8, rgba("1a1a30"), k * 0.3)
        c.ring(cx, cy, 33, col, 2.0)
        c.ring(cx, cy, 22 + math.sin(k) * 2, colD, 3.0)
        c.glow_disc(cx, cy, 22, col, 0.35 + 0.2 * math.sin(k * 2))
        c.disc(cx, cy, 11, col)
        c.disc(cx, cy, 6 + 2 * math.sin(k * 2), colL)
        for i in range(4):
            a = -k * 0.5 + i * math.tau / 4
            px_, py_ = cx + math.cos(a) * 18, cy + math.sin(a) * 18
            c.ngon(px_, py_, 7, 4, colD, a)
            c.ngon(px_, py_, 4.5, 4, col, a)
        if idx == 2:
            c.ring(cx, cy, 40, colL, 1.0)
        c.outline(P["void"])
        out.append(c)
    return out


def build_eye():
    out = []
    for f in range(4):
        c = Canvas(8, 8)
        r = 2.0 + 0.6 * math.sin(f / 4 * math.tau)
        c.glow_disc(4, 4, 4, P["white"], 0.5)
        c.disc(4, 4, r, P["white"])
        c.disc(4, 4, r * 0.5, P["void"])
        c.outline(P["void"], include_diag=False)
        out.append(c)
    return out


def _bolt(w, h, core, halo, shape="diamond", hot=None):
    """弹丸：外发光 + 彩色主色 + 白热核心，保证在敌人群中也看得见"""
    out = []
    for f in range(4):
        c = Canvas(w, h)
        cx, cy = w / 2.0, h / 2.0
        p = 0.9 + 0.1 * math.sin(f / 4 * math.tau)
        if shape == "diamond":
            c.poly([(w - 1, cy), (cx, 0.5), (0.5, cy), (cx, h - 0.5)], halo)
            c.poly([(w - 2, cy), (cx, 1.5), (1.5, cy), (cx, h - 1.5)], core)
        elif shape == "ball":
            c.disc(cx, cy, min(w, h) / 2.0 - 0.5, halo)
            c.disc(cx, cy, (min(w, h) / 2.0 - 0.5) * p, core)
        elif shape == "ring":
            c.ring(cx, cy, min(w, h) / 2.0 - 1.5, halo, 2.5)
            c.ring(cx, cy, min(w, h) / 2.0 - 4.0, core, 1.5)
        elif shape == "shard":
            c.poly([(w - 1, cy), (cx + 1, 1), (1, cy - 2), (cx, cy), (1, cy + 2), (cx + 1, h - 2)], halo)
            c.poly([(w - 3, cy), (cx, 2), (2, cy), (cx, h - 2)], core)
        # 高亮核心：颜色取自武器本身（不是纯白），否则所有子弹都长一个样
        hc = hot if hot is not None else lighten(core, 0.60)
        rc = max(1.0, min(w, h) * 0.20)
        c.glow_disc(cx, cy, rc * 2.2, hc, 0.42)
        c.disc(cx, cy, rc, hc)
        c.glow_disc(cx, cy, min(w, h) / 2.0 + 2.5, halo, 0.5)
        out.append(c)
    return out


def lighten(c, t=0.55):
    return (int(c[0] + (255 - c[0]) * t), int(c[1] + (255 - c[1]) * t),
            int(c[2] + (255 - c[2]) * t), c[3])


def build_muzzles():
    """每种武器一套专属枪口特效 —— 之前所有武器共用同一个黄色小星，看不出区别"""
    a = {}
    # 手枪：小黄星 + 短橙条
    fr = []
    for f in range(3):
        c = Canvas(20, 14)
        t = f / 2.0
        c.line(5, 7, 13 + 7 * (1 - t), 7, P["orange"])
        c.glow_disc(5, 7, 8 * (1 - t) + 2.5, P["yellow"], 0.9 * (1 - t))
        c.star(5, 7, 6.5 * (1 - t) + 2, 4, P["white"], 0.32)
        fr.append(c)
    a["vfx_muzzle_pistol"] = fr
    # 霰弹：宽扇形橙锥 + 火星
    fr = []
    for f in range(3):
        c = Canvas(26, 22)
        t = f / 2.0
        c.poly([(3, 11), (12 + 11 * (1 - t), 2 + 4 * t), (12 + 11 * (1 - t), 20 - 4 * t), (3, 11)],
               P["orange"] if f < 2 else P["orangeD"])
        c.poly([(3, 11), (9 + 9 * (1 - t), 6 + 3 * t), (9 + 9 * (1 - t), 16 - 3 * t), (3, 11)], P["yellow"])
        c.glow_disc(4, 11, 8 * (1 - t) + 3, P["yellow"], 0.85 * (1 - t))
        for i in range(5):
            ang = -0.5 + i * 0.25
            L = (10 + 8 * (1 - t))
            c.line(4, 11, 4 + math.cos(ang) * L, 11 + math.sin(ang) * L, P["white"])
        fr.append(c)
    a["vfx_muzzle_shotgun"] = fr
    # 激光：横向青色镜片光条
    fr = []
    for f in range(3):
        c = Canvas(30, 12)
        t = f / 2.0
        w = 22 * (1 - t) + 6
        c.rect(6 - w * 0.15, 4, w, 4, P["cyan"])
        c.rect(6 - w * 0.15, 5, w, 2, P["white"])
        c.glow_disc(7, 6, 9 * (1 - t) + 3, P["cyan"], 0.8 * (1 - t))
        c.rect(0, 5, 8, 2, P["cyanD"])
        c.rect(4, 2, 2, 8, P["cyan"])
        fr.append(c)
    a["vfx_muzzle_laser"] = fr
    # 回旋镖：绿色扩散环
    fr = []
    for f in range(4):
        c = Canvas(22, 22)
        t = f / 3.0
        c.ring(11, 11, 4 + t * 8, P["green"], 2.2 * (1 - t) + 0.6)
        c.glow_disc(11, 11, 9 * (1 - t) + 2, P["green"], 0.5 * (1 - t))
        fr.append(c)
    a["vfx_muzzle_boomerang"] = fr
    # 电弧球：紫色光晕球
    fr = []
    for f in range(4):
        c = Canvas(24, 24)
        t = f / 3.0
        c.glow_disc(12, 12, 11 * (1 - t) + 3, P["purple"], 0.75 * (1 - t))
        c.disc(12, 12, 6.5 * (1 - t) + 1.5, P["purple"])
        c.disc(12, 12, 3.5 * (1 - t) + 0.8, P["white"])
        c.ring(12, 12, 12 * (1 - t) + 3, P["blue"], 1.4)
        fr.append(c)
    a["vfx_muzzle_orb"] = fr
    # 火箭：橙焰 + 尾烟
    fr = []
    for f in range(4):
        c = Canvas(26, 16)
        t = f / 3.0
        c.poly([(2, 8), (13 + 9 * (1 - t), 3 + 2 * t), (13 + 9 * (1 - t), 13 - 2 * t), (2, 8)], P["orange"])
        c.poly([(2, 8), (10 + 7 * (1 - t), 5 + 2 * t), (10 + 7 * (1 - t), 11 - 2 * t), (2, 8)], P["yellow"])
        c.glow_disc(4, 8, 8 * (1 - t) + 3, P["orange"], 0.85 * (1 - t))
        for i in range(4):
            c.disc(1 - i * 2.2, 8 + (i % 2) * 2 - 1, 2.4 - i * 0.4, rgba("545278", int(150 * (1 - t))))
        fr.append(c)
    a["vfx_muzzle_rocket"] = fr
    return a


def build_glow():
    """32x32 柔光点，用于给弹丸叠一层光晕（可被 modulate 染色）"""
    c = Canvas(64, 64)
    c.glow_disc(32, 32, 32, P["white"], 0.55, falloff=2.4)
    return [c]


def build_projectiles():
    a = {}
    a["glow_soft"] = build_glow()
    a.update(build_muzzles())
    a["proj_pistol"] = _bolt(18, 10, P["yellow"], P["orange"], "shard")
    a["proj_shotgun"] = _bolt(16, 12, P["orange"], P["red"], "ball")
    a["proj_laser"] = _bolt(26, 9, P["cyan"], P["blue"], "shard")
    a["proj_boomerang"] = _bolt(20, 20, P["green"], P["greenD"], "ring")
    a["proj_orb"] = _bolt(22, 22, P["purple"], P["blue"], "ball")
    a["proj_rocket"] = _bolt(22, 13, P["red"], P["orange"], "shard")
    a["eproj_shard"] = _bolt(14, 10, P["pink"], P["pinkD"], "diamond")
    a["eproj_ball"] = _bolt(16, 16, P["orange"], P["red"], "ball")
    a["proj_nail"] = _bolt(13, 7, P["white"], P["cyan"], "shard")
    return a


def build_pickups():
    a = {}
    gem = []
    for f in range(4):
        c = Canvas(14, 14)
        k = f / 4 * math.tau
        g = int(150 + 80 * math.sin(k))
        col = rgba("%02x%02x%02x" % (60, g, 255))
        c.glow_disc(7, 7, 7, col, 0.4)
        c.poly([(7, 0.5), (13.5, 7), (7, 13.5), (0.5, 7)], col)
        c.poly([(7, 3), (11, 7), (7, 11), (3, 7)], P["white"])
        c.poly([(7, 4.5), (9.5, 7), (7, 9.5), (4.5, 7)], col)
        c.outline(P["void"])
        gem.append(c)
    a["pickup_xp"] = gem

    gear = []
    for f in range(4):
        c = Canvas(16, 16)
        c.ngon(8, 8, 6.5, 8, P["yellow"], f / 4 * math.tau * 0.2)
        c.glow_disc(8, 8, 7.5, P["yellow"], 0.35)
        c.disc(8, 8, 4.5, P["orange"])
        c.disc(8, 8, 1.8, P["void"])
        c.outline(P["void"])
        gear.append(c)
    a["pickup_gear"] = gear

    # 医疗包：白箱体 + 红十字 + 提手。之前用的是绿色，和"分裂体"敌人同一套配色，
    # 在满屏绿色敌人里根本认不出来 —— 这是玩家反馈"没有回血道具"的直接原因。
    hp = []
    for f in range(6):
        c = Canvas(20, 20)
        k = f / 6 * math.tau
        pulse = 0.5 + 0.5 * math.sin(k)
        c.glow_disc(10, 10, 9.5, P["red"], 0.22 + 0.28 * pulse)
        c.rect(7, 2, 6, 3, rgba("9aa0b4"))      # 提手
        c.rect(2, 5, 16, 12, rgba("b9bfd0"))    # 箱体描边
        c.rect(3, 6, 14, 10, P["white"])        # 白色箱体
        c.rect(9, 6, 2, 10, P["red"])           # 红十字·竖
        c.rect(5, 10, 10, 2, P["red"])          # 红十字·横
        c.outline(P["void"])
        hp.append(c)
    a["pickup_hp"] = hp

    chest = []
    for f in range(6):
        c = Canvas(26, 22)
        k = f / 6 * math.tau
        c.glow_disc(13, 11, 12, P["yellow"], 0.25 + 0.15 * math.sin(k))
        c.rect(3, 9, 20, 11, P["orangeD"])
        c.rect(5, 11, 16, 7, P["orange"])
        c.poly([(3, 9), (6, 3), (20, 3), (23, 9)], P["yellow"])
        c.rect(3, 8, 20, 2, P["white"])
        c.rect(11, 9, 4, 6, P["yellow"])
        c.rect(12, 11, 2, 2, P["void"])
        c.outline(P["void"])
        chest.append(c)
    a["pickup_chest"] = chest
    return a


def build_vfx():
    a = {}
    frames = []
    for f in range(5):
        c = Canvas(20, 20)
        t = f / 4.0
        r = 2 + t * 8
        for i in range(5 + f):
            ang = i * math.tau / (5 + f) + t
            L = r * (0.6 + 0.5 * random.random())
            c.line(10, 10, 10 + math.cos(ang) * L, 10 + math.sin(ang) * L, P["white"])
        c.glow_disc(10, 10, r, P["yellow"], 0.6 * (1 - t))
        c.disc(10, 10, 2.5 * (1 - t) + 0.5, P["white"])
        frames.append(c)
    a["vfx_hit"] = frames

    frames = []
    for f in range(9):
        c = Canvas(56, 56)
        t = f / 8.0
        r = 4 + t * 24
        for i in range(14):
            ang = i * math.tau / 14 + 0.4
            L = r * (0.75 + 0.45 * random.random())
            c.line(28, 28, 28 + math.cos(ang) * L, 28 + math.sin(ang) * L,
                   P["orange"] if i % 2 else P["yellow"])
        c.glow_disc(28, 28, r + 6, P["orange"], 0.55 * (1 - t))
        c.disc(28, 28, r * 0.75, P["red"])
        c.disc(28, 28, r * 0.45, P["yellow"])
        c.disc(28, 28, max(0.5, r * 0.25 * (1 - t)), P["white"])
        frames.append(c)
    a["vfx_explosion"] = frames

    frames = []
    for f in range(12):
        c = Canvas(128, 128)
        t = f / 11.0
        r = 6 + t * 58
        for i in range(26):
            ang = i * math.tau / 26 + t * 2
            L = r * (0.7 + 0.6 * random.random())
            c.line(64, 64, 64 + math.cos(ang) * L, 64 + math.sin(ang) * L,
                   [P["white"], P["yellow"], P["orange"], P["red"]][i % 4])
        c.glow_disc(64, 64, r + 14, P["red"], 0.5 * (1 - t))
        c.disc(64, 64, r * 0.8, P["orange"])
        c.disc(64, 64, r * 0.5, P["yellow"])
        c.disc(64, 64, max(0.5, r * 0.28 * (1 - t)), P["white"])
        frames.append(c)
    a["vfx_bigboom"] = frames

    frames = []
    for f in range(7):
        c = Canvas(96, 96)
        t = f / 6.0
        r = 3 + t * 44
        c.ring(48, 48, r, P["cyan"], 2.5 * (1 - t) + 0.5)
        c.glow_disc(48, 48, r + 2, P["cyan"], 0.10 * (1 - t))
        frames.append(c)
    a["vfx_shock"] = frames

    frames = []
    for f in range(3):
        c = Canvas(18, 14)
        t = f / 2.0
        c.glow_disc(4, 7, 8 * (1 - t) + 2, P["yellow"], 0.8 * (1 - t))
        c.star(4, 7, 7 * (1 - t) + 2, 4, P["white"], 0.35)
        frames.append(c)
    a["vfx_muzzle"] = frames

    frames = []
    for f in range(7):
        c = Canvas(40, 40)
        t = f / 6.0
        c.ring(20, 20, 15 * (1 - t) + 3, P["red"], 2.0)
        c.ring(20, 20, 18 * (1 - t) + 4, P["pinkD"], 1.0)
        if f >= 5:
            c.glow_disc(20, 20, 8, P["red"], 0.4)
        frames.append(c)
    a["vfx_spawn"] = frames

    frames = []
    for f in range(6):
        c = Canvas(28, 28)
        t = f / 5.0
        rnd = random.Random(1000 + f)
        for i in range(7):
            ox = (rnd.random() - 0.5) * 10 * t
            oy = (rnd.random() - 0.5) * 10 * t
            rr = (2.0 + t * 3.5)
            c.disc(14 + ox, 14 + oy, rr, rgba("545278", int(140 * (1 - t))))
        frames.append(c)
    a["vfx_smoke"] = frames

    frames = []
    for f in range(4):
        c = Canvas(12, 12)
        t = f / 3.0
        c.glow_disc(6, 6, 6, P["cyan"], 0.7 * (1 - t))
        c.disc(6, 6, 2.2 * (1 - t) + 0.4, P["white"])
        frames.append(c)
    a["vfx_trail"] = frames

    frames = []
    for f in range(8):
        c = Canvas(96, 96)
        t = f / 7.0
        for i in range(12):
            ang = i * math.tau / 12
            L = 6 + t * 40
            c.line(48 + math.cos(ang) * 6, 48 + math.sin(ang) * 6,
                   48 + math.cos(ang) * L, 48 + math.sin(ang) * L,
                   P["cyan"] if i % 2 else P["white"])
        c.ring(48, 48, 6 + t * 42, P["cyan"], 2.0 * (1 - t) + 0.5)
        frames.append(c)
    a["vfx_levelup"] = frames

    frames = []
    for f in range(5):
        c = Canvas(24, 24)
        t = f / 4.0
        c.star(12, 12, 9 * (1 - t) + 2, 4, P["white"], 0.28, t)
        c.glow_disc(12, 12, 6, P["cyan"], 0.5 * (1 - t))
        frames.append(c)
    a["vfx_sparkle"] = frames
    return a


THEMES = {
    0: ("3a2050", "ff4ce0", "2a1840"),
    1: ("123040", "34f0ff", "0e2430"),
    2: ("3a1a1a", "ff7a30", "281010"),
}


def build_tiles():
    a = {}
    for ti in sorted(THEMES):
        base, accent, dark = THEMES[ti]
        bc, ac, dc = rgba(base), rgba(accent), rgba(dark)
        for v in range(4):
            c = Canvas(64, 64)
            c.rect(0, 0, 64, 64, bc)
            rnd = random.Random(ti * 10 + v)
            for _ in range(90):
                c.blend(rnd.randint(0, 63), rnd.randint(0, 63), dc, 0.6)
            for _ in range(40):
                c.blend(rnd.randint(0, 63), rnd.randint(0, 63), ac, 0.10)
            for k in range(64):
                c.blend(k, 0, dc, 0.9)
                c.blend(0, k, dc, 0.9)
            if v == 1:
                for k in range(8, 56):
                    c.blend(k, 32, dc, 0.5)
                c.blend(32, 32, ac, 0.35)
            elif v == 2:
                for i in range(4):
                    c.rect(8 + i * 14, 8, 6, 48, dc)
                    for y in range(8, 56, 6):
                        c.blend(8 + i * 14 + 3, y, ac, 0.18)
            elif v == 3:
                c.rect(20, 20, 24, 24, dc)
                c.rect(22, 22, 20, 20, bc)
                c.blend(21, 21, ac, 0.5)
                c.blend(42, 42, ac, 0.5)
            a["floor_%d_%d" % (ti, v)] = [c]

        for v in range(2):
            c = Canvas(64, 32)
            c.rect(0, 0, 64, 32, dc)
            c.rect(0, 0, 64, 6, bc)
            c.rect(0, 6, 64, 2, ac)
            for x in range(0, 64, 16):
                c.rect(x, 8, 2, 24, dc)
            c.rect(0, 30, 64, 2, rgba("000000"))
            for x in range(0, 64, 8):
                c.blend(x, 31, ac, 0.35)
            a["wall_h_%d_%d" % (ti, v)] = [c]

        c = Canvas(32, 64)
        c.rect(0, 0, 32, 64, dc)
        c.rect(0, 0, 6, 64, bc)
        c.rect(6, 0, 2, 64, ac)
        for y in range(0, 64, 16):
            c.rect(8, y, 24, 2, dc)
        a["wall_v_%d" % ti] = [c]

        c = Canvas(48, 48)
        c.glow_disc(24, 24, 22, ac, 0.10)
        c.ngon(24, 24, 21, 8, dc, math.pi / 8)
        c.ngon(24, 24, 18, 8, bc, math.pi / 8)
        c.ring(24, 24, 20, ac, 1.5)
        c.rect(20, 20, 8, 8, dc)
        c.rect(22, 22, 4, 4, ac)
        c.outline(rgba("050508"))
        a["pillar_%d" % ti] = [c]

        c = Canvas(32, 32)
        c.rect(2, 2, 28, 28, dc)
        c.rect(3, 3, 26, 26, bc)
        c.line(3, 3, 28, 28, ac)
        c.line(28, 3, 3, 28, ac)
        c.rect(13, 13, 6, 6, dc)
        c.outline(rgba("050508"))
        a["crate_%d" % ti] = [c]
    return a


def build_ui():
    a = {}

    def nine(name, size, fill, edge, accent=None, thick=2):
        c = Canvas(size, size)
        if fill:
            c.rect(0, 0, size, size, fill)
        if edge:
            c.rect_out(0, 0, size, size, edge, thick)
        if accent:
            c.rect(thick, thick, size - thick * 2, 1, accent)
        a[name] = [c]

    nine("ui_panel", 48, rgba("14122a", 235), P["steel"], P["cyanD"])
    nine("ui_panel_dark", 48, rgba("0a0a16", 245), P["mid"])
    nine("ui_card", 48, rgba("1a1834", 240), P["steel"])
    nine("ui_card_sel", 48, rgba("2b3f6a", 245), P["cyan"], P["cyan"])

    for nm, fill, edge in (("ui_btn", rgba("22203f"), P["steel"]),
                           ("ui_btn_hi", rgba("33325e"), P["cyan"]),
                           ("ui_btn_dn", rgba("12102a"), P["cyanD"])):
        c = Canvas(48, 48)
        c.rect(0, 0, 48, 48, fill)
        c.rect_out(0, 0, 48, 48, edge, 2)
        c.rect(2, 2, 44, 2, rgba("ffffff", 26))
        a[nm] = [c]

    c = Canvas(64, 16)
    c.rect(0, 0, 64, 16, rgba("08080f"))
    c.rect_out(0, 0, 64, 16, P["steel"], 1)
    c.rect(2, 2, 60, 12, rgba("1a1830"))
    a["ui_bar_bg"] = [c]

    def bar(name, col, col2):
        c = Canvas(64, 16)
        c.rect(0, 0, 64, 16, col)
        c.rect(0, 0, 64, 4, col2)
        c.rect(0, 12, 64, 4, rgba("000000", 60))
        a[name] = [c]

    bar("ui_bar_hp", P["red"], rgba("ff8a7a"))
    bar("ui_bar_xp", P["cyan"], rgba("bffaff"))
    bar("ui_bar_boss", P["pink"], rgba("ffa6cd"))

    def icon(name, fn):
        c = Canvas(20, 20)
        fn(c)
        a["icon_" + name] = [c]

    def w_pistol(c):
        c.rect(4, 8, 12, 4, P["steel"]); c.rect(14, 7, 3, 6, P["light"])
        c.rect(4, 9, 10, 2, P["yellow"]); c.rect(6, 12, 3, 4, P["mid"])

    def w_shotgun(c):
        c.rect(3, 6, 12, 3, P["steel"]); c.rect(3, 11, 12, 3, P["steel"])
        c.rect(13, 6, 4, 8, P["orange"]); c.rect(4, 9, 4, 3, P["orangeD"])

    def w_laser(c):
        c.rect(2, 9, 16, 3, P["cyanD"]); c.rect(13, 8, 5, 5, P["cyan"])
        c.rect(4, 7, 4, 6, P["steel"])

    def w_boomerang(c):
        c.poly([(3, 4), (8, 4), (17, 13), (17, 17), (13, 17), (4, 8)], P["green"])
        c.poly([(5, 6), (8, 6), (15, 14), (15, 15), (14, 15), (6, 8)], P["white"])

    def w_orb(c):
        c.glow_disc(10, 10, 9, P["purple"], 0.5)
        c.disc(10, 10, 6, P["purple"]); c.disc(10, 10, 3, P["white"])

    def w_rocket(c):
        c.rect(4, 8, 12, 5, P["redD"]); c.poly([(16, 6), (19, 10.5), (16, 15)], P["red"])
        c.poly([(4, 8), (1, 6), (1, 15), (4, 13)], P["orange"])
        c.rect(6, 9, 6, 3, P["white"])

    icon("w_pistol", w_pistol); icon("w_shotgun", w_shotgun); icon("w_laser", w_laser)
    icon("w_boomerang", w_boomerang); icon("w_orb", w_orb); icon("w_rocket", w_rocket)

    def p_speed(c):
        c.poly([(11, 2), (4, 11), (9, 11), (8, 18), (16, 8), (11, 8)], P["cyan"])

    def p_firerate(c):
        c.rect(8, 2, 4, 10, P["orange"]); c.rect(6, 12, 8, 6, P["orangeD"])
        c.rect(7, 3, 2, 8, P["yellow"])

    def p_damage(c):
        c.poly([(10, 2), (14, 9), (11, 9), (13, 18), (6, 10), (10, 10)], P["red"])

    def p_crit(c):
        c.star(10, 10, 8, 5, P["yellow"], 0.42); c.disc(10, 10, 2, P["white"])

    def p_regen(c):
        c.glow_disc(10, 10, 9, P["green"], 0.35)
        c.rect(4, 8, 12, 4, P["green"]); c.rect(8, 4, 4, 12, P["green"])

    def p_magnet(c):
        c.ring(10, 12, 6.5, P["red"], 3.0)
        c.rect(4, 3, 4, 6, P["steel"]); c.rect(12, 3, 4, 6, P["steel"])

    def p_shield(c):
        c.poly([(10, 2), (17, 5), (17, 11), (10, 18), (3, 11), (3, 5)], P["blue"])
        c.poly([(10, 5), (14, 7), (14, 10), (10, 15), (6, 10), (6, 7)], P["white"])

    def p_xp(c):
        c.rect(3, 3, 14, 14, P["cyanD"]); c.rect(5, 5, 10, 10, P["cyan"])
        c.rect(8, 8, 4, 4, P["white"])

    icon("p_speed", p_speed); icon("p_firerate", p_firerate); icon("p_damage", p_damage)
    icon("p_crit", p_crit); icon("p_regen", p_regen); icon("p_magnet", p_magnet)
    icon("p_shield", p_shield); icon("p_xp", p_xp)

    def m_gear(c):
        c.ngon(10, 10, 8, 8, P["yellow"]); c.disc(10, 10, 5.5, P["orange"]); c.disc(10, 10, 2.2, P["void"])

    def m_heart(c):
        c.poly([(4, 15), (4, 7), (3, 6), (3, 4), (5, 3), (7, 5), (9, 3), (11, 4),
                (11, 6), (10, 7), (10, 15)], P["red"])
        c.rect(4, 7, 6, 8, P["red"])
        c.rect(4, 8, 6, 2, P["white"]); c.rect(5, 6, 2, 6, P["white"])

    def m_skull(c):
        c.disc(10, 8, 6.5, P["white"]); c.rect(5, 12, 10, 5, P["white"])
        c.rect(7, 7, 2.5, 3, P["void"]); c.rect(11, 7, 2.5, 3, P["void"])
        c.rect(9, 11, 2, 2, P["void"])
        c.rect(7, 13, 1.5, 4, P["void"]); c.rect(12, 13, 1.5, 4, P["void"])

    def m_clock(c):
        c.disc(10, 10, 8, P["steel"]); c.disc(10, 10, 6.5, P["dark"])
        c.rect(9, 5, 2, 6, P["white"]); c.rect(10, 9, 5, 2, P["white"])

    def m_lock(c):
        c.rect(4, 9, 12, 9, P["steel"]); c.ring(10, 8, 4.0, P["steel"], 2.0)
        c.rect(4, 9, 12, 2, P["light"]); c.rect(9, 12, 2, 4, P["dark"])

    def m_crown(c):
        c.star(10, 10, 9, 6, P["purple"], 0.5); c.disc(10, 10, 3, P["white"])

    icon("m_gear", m_gear); icon("m_heart", m_heart); icon("m_skull", m_skull)
    icon("m_clock", m_clock); icon("m_lock", m_lock); icon("m_crown", m_crown)

    # ---- 技能图标 ----
    def s_shock(c):
        c.glow_disc(10, 10, 9, P["cyan"], 0.45)
        for r in (3.5, 6.5, 9.0):
            c.ring(10, 10, r, P["cyan"], 1.6)
        c.disc(10, 10, 2.6, P["white"])

    def s_shield(c):
        c.poly([(10, 1.5), (18, 5), (18, 11), (10, 18.5), (2, 11), (2, 5)], P["blue"])
        c.poly([(10, 4.5), (15.5, 7), (15.5, 10.5), (10, 15.5), (4.5, 10.5), (4.5, 7)], P["white"])
        c.poly([(10, 7), (13, 8.5), (13, 10.5), (10, 13.5), (7, 10.5), (7, 8.5)], P["blue"])

    def s_phase(c):
        c.glow_disc(8, 10, 8, P["purple"], 0.4)
        c.poly([(17, 10), (7, 3), (7, 17)], P["white"])
        for k in range(3):
            c.rect(1 + k * 2, 7 + k, 1, 7 - k * 2, rgba("a25eff", 200 - k * 55))

    def s_slow(c):
        c.disc(10, 10, 8, P["steel"])
        c.disc(10, 10, 6.4, P["dark"])
        c.rect(9, 5, 2, 6, P["cyan"])
        c.rect(9, 9, 5, 2, P["cyan"])
        c.ring(10, 10, 9, P["cyan"], 1.2)

    icon("s_shock", s_shock); icon("s_shield", s_shield)
    icon("s_phase", s_phase); icon("s_slow", s_slow)

    # ---- 新道具 ----
    def pack(name, frames):
        a[name] = frames

    # 护盾电池（蓝）
    sh = []
    for f in range(6):
        c = Canvas(20, 20)
        k = f / 6 * math.tau
        c.glow_disc(10, 10, 9.5, P["blue"], 0.22 + 0.28 * (0.5 + 0.5 * math.sin(k)))
        c.poly([(10, 1.5), (17.5, 5), (17.5, 11), (10, 18.5), (2.5, 11), (2.5, 5)], rgba("1a2a6a"))
        c.poly([(10, 3.5), (15.5, 6.2), (15.5, 10.5), (10, 16.2), (4.5, 10.5), (4.5, 6.2)], P["blue"])
        c.poly([(10, 6), (13, 7.6), (13, 10.2), (10, 13.6), (7, 10.2), (7, 7.6)], P["white"])
        c.outline(P["void"])
        sh.append(c)
    pack("pickup_shield", sh)

    # 脉冲炸弹（紫）
    pb = []
    for f in range(6):
        c = Canvas(20, 20)
        k = f / 6.0
        c.glow_disc(10, 11, 8 + 2 * k, P["purple"], 0.35)
        c.disc(10, 11, 6.5, rgba("3a1a6a"))
        c.disc(10, 11, 5.2, P["purple"])
        c.disc(10, 11, 2.4, P["white"])
        c.rect(9, 2, 2, 4, rgba("9aa0b4"))
        c.rect(8, 1, 4, 2, P["orange"])
        for i in range(4):
            ang = i * math.tau / 4 + k * 1.2
            c.disc(10 + math.cos(ang) * 8.5, 11 + math.sin(ang) * 8.5, 1.6, P["white"])
        c.outline(P["void"])
        pb.append(c)
    pack("pickup_pulse", pb)

    # 时缓芯片（青）
    tc = []
    for f in range(6):
        c = Canvas(20, 20)
        k = 0.5 + 0.5 * math.sin(f / 6 * math.tau)
        c.glow_disc(10, 10, 9, P["cyan"], 0.2 + 0.25 * k)
        c.rect(3, 5, 14, 11, rgba("0e3a4a"))
        c.rect(4, 6, 12, 9, P["cyanD"])
        c.rect(5, 7, 10, 7, rgba("06222e"))
        c.rect(9, 7, 2, 7, P["cyan"])
        c.rect(6, 10, 8, 2, P["cyan"])
        for i in range(4):
            c.rect(6 + i * 3, 4, 2, 2, P["white"])
        c.outline(P["void"])
        tc.append(c)
    pack("pickup_timechip", tc)

    # 狂暴剂（红）
    rg = []
    for f in range(6):
        c = Canvas(20, 20)
        k = 0.5 + 0.5 * math.sin(f / 6 * math.tau)
        c.glow_disc(10, 11, 9, P["red"], 0.2 + 0.3 * k)
        c.rect(7, 3, 6, 4, rgba("9aa0b4"))
        c.rect(6, 7, 8, 11, rgba("5a1010"))
        c.rect(7, 8, 6, 9, P["red"])
        c.rect(8, 12, 4, 4, P["white"])
        c.rect(6, 7, 8, 1, P["orange"])
        c.outline(P["void"])
        rg.append(c)
    pack("pickup_rage", rg)
    return a


def build_all():
    a = {}
    a["player"] = build_player()
    a["gun"] = build_gun()
    for k in ("grunt", "lancer", "bomber", "splitter", "darter", "tank", "flyer", "summoner"):
        a["enemy_" + k] = build_enemy(k)
    a["eye"] = build_eye()
    a.update(build_projectiles())
    a.update(build_pickups())
    a.update(build_vfx())
    a.update(build_tiles())
    a.update(build_ui())
    for i in range(3):
        a["boss_%d" % i] = build_boss(i)
    return a


def contact_sheet(path, scale=4, cols=16):
    assets = build_all()
    cells = []
    for name in sorted(assets):
        for i, f in enumerate(assets[name]):
            cells.append(("%s#%d" % (name, i), f))
    cw = max(c[1].w for c in cells) * scale + 8
    ch = max(c[1].h for c in cells) * scale + 20
    rows = (len(cells) + cols - 1) // cols
    sheet = Image.new("RGBA", (cw * cols, ch * rows), rgba("181828"))
    d = ImageDraw.Draw(sheet)
    for i, (nm, f) in enumerate(cells):
        cx = (i % cols) * cw
        cy = (i // cols) * ch
        big = f.img.resize((f.w * scale, f.h * scale), Image.NEAREST)
        sheet.alpha_composite(big, (cx + 4, cy + 16))
        d.text((cx + 4, cy + 3), nm[:24], fill=(210, 220, 255, 255))
    sheet.save(path)
    print("contact sheet ->", path, sheet.size, "cells:", len(cells))


def build_icon():
    """程序生成游戏图标 -> icon.png / icon.ico"""
    S = 256
    c = Canvas(S, S)
    R = 40
    # 圆角底板
    for y in range(S):
        for x in range(S):
            dx = max(0, abs(x - S / 2 + 0.5) - (S / 2 - R))
            dy = max(0, abs(y - S / 2 + 0.5) - (S / 2 - R))
            if dx * dx + dy * dy <= R * R:
                t = y / S
                c.px[x, y] = (int(10 + 14 * t), int(10 + 10 * t), int(22 + 26 * t), 255)
    # 外框
    c.rect_out(18, 18, S - 36, S - 36, P["cyan"], 6)
    c.rect_out(30, 30, S - 60, S - 60, P["cyanD"], 3)
    # 中心核心
    c.glow_disc(S / 2, S / 2, 74, P["cyan"], 0.30)
    c.glow_disc(S / 2, S / 2, 52, P["pink"], 0.45)
    c.disc(S / 2, S / 2, 44, P["pink"])
    c.disc(S / 2, S / 2, 26, P["white"])
    c.disc(S / 2, S / 2, 14, P["pink"])
    # 四角刻度
    for (ax, ay) in ((1, 1), (-1, 1), (1, -1), (-1, -1)):
        for k in range(3):
            x = int(S / 2 + ax * (70 + k * 14))
            y = int(S / 2 + ay * (70 + k * 14))
            c.disc(x, y, 4 - k, P["cyan"])
    img = c.img
    img.save(os.path.join(ROOT, "icon.png"))
    img.resize((256, 256), Image.LANCZOS).save(
        os.path.join(ROOT, "icon.ico"),
        sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    print("icon ->", os.path.join(ROOT, "icon.png"))


def main():
    if "--icon" in sys.argv:
        build_icon()
        return
    if "--contact" in sys.argv:
        contact_sheet(os.path.join(ART, "_contact.png"))
        return
    assets = build_all()
    pk = Packer(page=2048, pad=2)
    for name in sorted(assets):
        pk.add(name, assets[name])
    files = pk.save(ART)
    total = sum(len(v) for v in assets.values())
    print("wrote", len(files), "atlas page(s),", len(assets), "anims,", total, "frames")
    for f in files:
        print("  ", f, os.path.getsize(os.path.join(ART, f)))


if __name__ == "__main__":
    main()
