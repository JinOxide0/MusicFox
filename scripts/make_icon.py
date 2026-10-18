#!/usr/bin/env python3
"""Generate the MusicFox app icon and transparent fox mark.

The design is a geometric, low-poly fox head with a cyan -> violet
neon gradient on a deep space-blue background. Everything is drawn at
4x and downsampled for clean edges.
"""
from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "App" / "Assets.xcassets"
ICON_DIR = ASSETS / "AppIcon.appiconset"
MARK_DIR = ASSETS / "FoxMark.imageset"

S = 4  # supersample factor
W = 1024 * S


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def gradient(size: int, c1: tuple[int, int, int], c2: tuple[int, int, int],
             angle: float = 90.0, alpha: int = 255) -> Image.Image:
    """Linear gradient image of size x size."""
    img = Image.new("RGBA", (size, size))
    px = img.load()
    rad = math.radians(angle)
    dx, dy = math.cos(rad), math.sin(rad)
    # project corners to get the range
    vals = [x * dx + y * dy for x in (0, size) for y in (0, size)]
    lo, hi = min(vals), max(vals)
    for y in range(size):
        for x in range(size):
            t = ((x * dx + y * dy) - lo) / (hi - lo)
            px[x, y] = (
                round(lerp(c1[0], c2[0], t)),
                round(lerp(c1[1], c2[1], t)),
                round(lerp(c1[2], c2[2], t)),
                alpha,
            )
    return img


def poly_mask(size: int, points: list[tuple[float, float]]) -> Image.Image:
    m = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(m)
    d.polygon(points, fill=255)
    return m


def scaled(points: list[tuple[float, float]]) -> list[tuple[float, float]]:
    return [(x * S, y * S) for x, y in points]


def paste_poly(base: Image.Image, points: list[tuple[float, float]],
               c1: tuple[int, int, int], c2: tuple[int, int, int],
               angle: float, alpha: int = 255) -> None:
    mask = poly_mask(base.width, scaled(points))
    grad = gradient(base.width, c1, c2, angle, alpha)
    base.paste(grad, (0, 0), mask)


def paste_poly_color(base: Image.Image, points: list[tuple[float, float]],
                     color: tuple[int, int, int, int]) -> None:
    mask = poly_mask(base.width, scaled(points))
    layer = Image.new("RGBA", base.size, color)
    base.paste(layer, (0, 0), mask)


def glow_layer(base: Image.Image, points: list[tuple[float, float]],
               color: tuple[int, int, int], blur: float, alpha: int) -> None:
    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    mask = poly_mask(base.size[0], scaled(points))
    layer.paste(Image.new("RGBA", base.size, (*color, alpha)), (0, 0), mask)
    layer = layer.filter(ImageFilter.GaussianBlur(blur * S))
    base.alpha_composite(layer)


def main() -> None:
    icon = Image.new("RGBA", (W, W), (5, 7, 15, 255))

    # --- background -----------------------------------------------------
    bg = gradient(W, (11, 18, 38), (4, 5, 12), 115)
    icon.alpha_composite(bg)

    # soft radial aura behind the fox
    aura = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ad = ImageDraw.Draw(aura)
    cx, cy = W // 2, int(W * 0.44)
    for r in range(int(W * 0.46), 0, -8):
        t = 1 - r / (W * 0.46)
        a = int(22 * (t ** 1.7))
        ad.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(0, 180, 255, a))
    aura = aura.filter(ImageFilter.GaussianBlur(30 * S))
    icon.alpha_composite(aura)

    # fine perspective grid
    grid = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    gd = ImageDraw.Draw(grid)
    step = 64 * S
    for i in range(-W, W * 2, step):
        gd.line([(i, 0), (i + W // 2, W)], fill=(90, 170, 255, 10), width=max(1, S // 2))
    for j in range(0, W, step):
        gd.line([(0, j), (W, j)], fill=(90, 170, 255, 7), width=max(1, S // 2))
    grid = grid.filter(ImageFilter.GaussianBlur(1.2 * S))
    icon.alpha_composite(grid)

    # tech ring + tick marks
    ring = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    rd = ImageDraw.Draw(ring)
    rcx, rcy, rr = W // 2, int(W * 0.5), int(W * 0.415)
    rd.ellipse((rcx - rr, rcy - rr, rcx + rr, rcy + rr),
               outline=(70, 200, 255, 26), width=max(2, S))
    for k in range(48):
        ang = math.tau * k / 48
        r1 = rr - 14 * S
        r2 = rr - 30 * S if k % 4 else rr - 44 * S
        x1, y1 = rcx + r1 * math.cos(ang), rcy + r1 * math.sin(ang)
        x2, y2 = rcx + r2 * math.cos(ang), rcy + r2 * math.sin(ang)
        rd.line([(x1, y1), (x2, y2)], fill=(80, 210, 255, 32), width=max(1, S // 2))
    ring = ring.filter(ImageFilter.GaussianBlur(0.6 * S))
    icon.alpha_composite(ring)

    # --- fox geometry ---------------------------------------------------
    # ear tips, face silhouette
    face = [
        (300, 366), (356, 146), (472, 362),
        (512, 424), (552, 362), (668, 146), (724, 366),
        (694, 574), (614, 704), (544, 776), (512, 834),
        (480, 776), (410, 704), (330, 574),
    ]
    left_face = [(300, 366), (472, 362), (512, 424), (512, 834),
                 (480, 776), (410, 704), (330, 574)]
    right_face = [(724, 366), (552, 362), (512, 424), (512, 834),
                  (544, 776), (614, 704), (694, 574)]
    left_ear = [(300, 366), (356, 146), (472, 362), (512, 424)]
    right_ear = [(724, 366), (668, 146), (552, 362), (512, 424)]
    forehead = [(472, 362), (512, 424), (552, 362), (512, 492)]
    left_cheek = [(330, 574), (410, 704), (480, 776), (512, 834),
                  (458, 704), (404, 638)]
    right_cheek = [(694, 574), (614, 704), (544, 776), (512, 834),
                   (566, 704), (620, 638)]
    muzzle = [(478, 652), (512, 672), (546, 652), (512, 756)]
    left_eye = [(376, 522), (454, 538), (446, 560), (368, 546)]
    right_eye = [(648, 522), (570, 538), (578, 560), (656, 546)]
    nose = [(496, 700), (528, 700), (512, 728)]

    # ambient glow behind silhouette
    glow_layer(icon, face, (0, 170, 255), 46, 90)

    # base face facets
    paste_poly(icon, left_face, (0, 224, 255), (40, 92, 255), 118)
    paste_poly(icon, right_face, (60, 120, 255), (146, 64, 255), 62)
    paste_poly(icon, left_ear, (0, 245, 255), (40, 120, 255), 110)
    paste_poly(icon, right_ear, (70, 140, 255), (166, 70, 255), 65)
    paste_poly(icon, left_cheek, (0, 120, 220), (20, 60, 180), 120, 235)
    paste_poly(icon, right_cheek, (50, 80, 220), (110, 40, 200), 60, 235)
    paste_poly(icon, forehead, (120, 250, 255), (60, 140, 255), 90, 245)

    # inner ears (dark magenta)
    paste_poly_color(icon, [(396, 208), (440, 340), (384, 344)], (16, 8, 34, 230))
    paste_poly_color(icon, [(628, 208), (584, 340), (640, 344)], (16, 8, 34, 230))
    paste_poly_color(icon, [(406, 236), (428, 316), (396, 318)], (190, 30, 140, 180))
    paste_poly_color(icon, [(618, 236), (596, 316), (628, 318)], (150, 30, 170, 180))

    # muzzle and chin highlight
    paste_poly(icon, muzzle, (226, 250, 255), (118, 164, 255), 90, 246)
    paste_poly_color(icon, [(478, 652), (512, 672), (512, 700), (486, 676)],
                     (255, 255, 255, 60))
    paste_poly_color(icon, nose, (8, 10, 20, 255))
    paste_poly_color(icon, [(496, 700), (512, 714), (528, 700), (512, 722)],
                     (70, 235, 255, 150))

    # eyes
    glow_layer(icon, left_eye, (0, 255, 255), 18, 180)
    glow_layer(icon, right_eye, (0, 255, 255), 18, 180)
    paste_poly_color(icon, left_eye, (210, 255, 255, 255))
    paste_poly_color(icon, right_eye, (210, 255, 255, 255))
    paste_poly_color(icon, [(378, 531), (446, 543), (443, 553), (374, 543)],
                     (0, 240, 255, 255))
    paste_poly_color(icon, [(646, 531), (578, 543), (581, 553), (650, 543)],
                     (0, 240, 255, 255))

    # facet edge lines
    edges = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ed = ImageDraw.Draw(edges)
    line_pts = [
        [(472, 362), (512, 424), (552, 362)],
        [(472, 362), (512, 492), (552, 362)],
        [(512, 492), (512, 672)],
        [(512, 672), (512, 834)],
        [(330, 574), (478, 652)],
        [(694, 574), (546, 652)],
        [(410, 704), (478, 652)],
        [(614, 704), (546, 652)],
        [(356, 146), (472, 362)],
        [(668, 146), (552, 362)],
    ]
    for pts in line_pts:
        ed.line(scaled(pts), fill=(150, 245, 255, 92), width=max(2, S), joint="curve")
    edges = edges.filter(ImageFilter.GaussianBlur(0.4 * S))
    icon.alpha_composite(edges)

    # subtle top rim light
    rim = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    rd2 = ImageDraw.Draw(rim)
    rd2.line(scaled([(356, 146), (472, 362), (512, 424), (552, 362), (668, 146)]),
             fill=(200, 255, 255, 120), width=max(2, S), joint="curve")
    rim = rim.filter(ImageFilter.GaussianBlur(2.2 * S))
    icon.alpha_composite(rim)

    # small circuit nodes
    nodes = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    nd = ImageDraw.Draw(nodes)
    for (x, y, r, a) in [(250, 712, 7, 110), (774, 712, 7, 110),
                         (236, 506, 5, 80), (788, 506, 5, 80),
                         (512, 906, 6, 90)]:
        nd.ellipse(scaled([(x - r, y - r), (x + r, y + r)]),
                   fill=(90, 230, 255, a))
    nodes = nodes.filter(ImageFilter.GaussianBlur(0.8 * S))
    icon.alpha_composite(nodes)

    # dark vignette to keep edges calm
    vign = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    vd = ImageDraw.Draw(vign)
    for i in range(0, W // 2, 6):
        a = int(110 * (i / (W / 2)) ** 2)
        vd.rectangle((i, i, W - i, W - i), outline=(3, 5, 12, a), width=6)
    vign = vign.filter(ImageFilter.GaussianBlur(60 * S))
    icon.alpha_composite(vign)

    # --- export ---------------------------------------------------------
    icon = icon.resize((1024, 1024), Image.LANCZOS).convert("RGB")
    ICON_DIR.mkdir(parents=True, exist_ok=True)
    MARK_DIR.mkdir(parents=True, exist_ok=True)
    icon.save(ICON_DIR / "AppIcon.png", "PNG")

    # transparent mark: same fox without background, cropped tightly
    mark = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    paste_poly(mark, left_face, (0, 224, 255), (40, 92, 255), 118)
    paste_poly(mark, right_face, (60, 120, 255), (146, 64, 255), 62)
    paste_poly(mark, left_ear, (0, 245, 255), (40, 120, 255), 110)
    paste_poly(mark, right_ear, (70, 140, 255), (166, 70, 255), 65)
    paste_poly(mark, left_cheek, (0, 120, 220), (20, 60, 180), 120, 235)
    paste_poly(mark, right_cheek, (50, 80, 220), (110, 40, 200), 60, 235)
    paste_poly(mark, forehead, (120, 250, 255), (60, 140, 255), 90, 245)
    paste_poly_color(mark, [(396, 208), (440, 340), (384, 344)], (9, 6, 20, 230))
    paste_poly_color(mark, [(628, 208), (584, 340), (640, 344)], (9, 6, 20, 230))
    paste_poly_color(mark, [(406, 236), (428, 316), (396, 318)], (190, 30, 140, 200))
    paste_poly_color(mark, [(618, 236), (596, 316), (628, 318)], (150, 30, 170, 200))
    paste_poly(mark, muzzle, (226, 250, 255), (118, 164, 255), 90, 246)
    paste_poly_color(mark, nose, (8, 10, 20, 255))
    paste_poly_color(mark, left_eye, (220, 255, 255, 255))
    paste_poly_color(mark, right_eye, (220, 255, 255, 255))
    mark = mark.crop((200 * S, 100 * S, 824 * S, 880 * S))
    mark.thumbnail((488, 488), Image.LANCZOS)
    canvas = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
    canvas.alpha_composite(mark, ((512 - mark.width) // 2, (512 - mark.height) // 2))
    canvas.save(MARK_DIR / "FoxMark.png", "PNG")

    print("wrote", ICON_DIR / "AppIcon.png")
    print("wrote", MARK_DIR / "FoxMark.png")


if __name__ == "__main__":
    main()
