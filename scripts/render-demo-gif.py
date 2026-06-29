#!/usr/bin/env python3
"""Render the README demo GIF for DPS Meter.

This is intentionally a game-free mock of the in-game overlay: it shows only the
DPS Meter window, animated with plausible multiplayer combat values.
"""
from __future__ import annotations

import math
from pathlib import Path
from typing import Iterable

from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "docs" / "demo.gif"

W, H = 760, 470
FPS = 12
FRAMES_PER_TAB = 28
TABS = ["Meter", "Card Usage", "Received Damage"]
PLAYERS = [
    ("xVc323", "X", (76, 190, 255)),
    ("Mira", "M", (255, 184, 76)),
    ("Theo", "T", (127, 241, 143)),
    ("Alex", "A", (255, 92, 123)),
]

BG = (9, 12, 20)
PANEL = (20, 24, 34, 238)
PANEL_2 = (31, 36, 49, 245)
BORDER = (86, 96, 120, 205)
BORDER_ACTIVE = (255, 206, 96, 245)
TEXT = (238, 242, 250)
MUTED = (155, 165, 184)
YELLOW = (255, 206, 96)
RED = (255, 100, 124)
CYAN = (116, 214, 255)
GREEN = (130, 239, 156)
PINK = (255, 121, 198)


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = [
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf" if bold else "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/System/Library/Fonts/Supplemental/Helvetica Bold.ttf" if bold else "/System/Library/Fonts/Supplemental/Helvetica.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if bold else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    ]
    for path in candidates:
        if path and Path(path).exists():
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()

FONT_TITLE = font(22, True)
FONT_TAB = font(15, True)
FONT_HEAD = font(13, True)
FONT_BODY = font(16, True)
FONT_SMALL = font(12)
FONT_AVATAR = font(18, True)


def ease(x: float) -> float:
    x = max(0.0, min(1.0, x))
    return 0.5 - 0.5 * math.cos(math.pi * x)


def lerp(a: int, b: int, t: float) -> int:
    return int(round(a + (b - a) * t))


def text_size(draw: ImageDraw.ImageDraw, text: str, fnt: ImageFont.ImageFont) -> tuple[int, int]:
    box = draw.textbbox((0, 0), text, font=fnt)
    return box[2] - box[0], box[3] - box[1]


def rounded(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int], radius: int, fill, outline=None, width: int = 1):
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def draw_right(draw: ImageDraw.ImageDraw, xy: tuple[int, int], value: str, fnt, fill):
    x, y = xy
    tw, _ = text_size(draw, value, fnt)
    draw.text((x - tw, y), value, font=fnt, fill=fill)


def pct_values(t: float) -> list[float]:
    raw = [0.39 + 0.03 * math.sin(t * 4.3), 0.27 + 0.02 * math.cos(t * 3.1), 0.21, 0.13]
    total = sum(raw)
    return [v / total for v in raw]


def values_for(frame: int) -> dict[str, list[list[int]]]:
    # One looping combat sample; values drift upward so the GIF feels alive.
    p = ease((frame % FRAMES_PER_TAB) / (FRAMES_PER_TAB - 1))
    pulse = int(18 * math.sin(frame / 3.8))
    return {
        "Meter": [
            [lerp(1840, 2124, p), lerp(420, 517, p), 42 + pulse // 4, lerp(88, 117, p)],
            [lerp(1290, 1478, p), lerp(310, 364, p), 18, lerp(64, 80, p)],
            [lerp(960, 1128, p), lerp(226, 272, p), 27, lerp(48, 63, p)],
            [lerp(690, 806, p), lerp(176, 211, p), 14, lerp(37, 45, p)],
        ],
        "Card Usage": [
            [lerp(38, 45, p), lerp(18, 22, p), lerp(14, 16, p), 3, lerp(2, 4, p)],
            [lerp(33, 38, p), lerp(15, 17, p), lerp(13, 15, p), 4, 1],
            [lerp(29, 34, p), lerp(13, 16, p), lerp(12, 13, p), 2, lerp(2, 3, p)],
            [lerp(24, 29, p), lerp(10, 12, p), lerp(10, 12, p), 1, 2],
        ],
        "Received Damage": [
            [lerp(84, 96, p), lerp(58, 65, p), lerp(26, 31, p), 18, lerp(142, 170, p)],
            [lerp(119, 132, p), lerp(71, 80, p), lerp(48, 52, p), 22, lerp(96, 120, p)],
            [lerp(72, 81, p), lerp(51, 58, p), lerp(21, 23, p), 14, lerp(88, 111, p)],
            [lerp(101, 112, p), lerp(60, 66, p), lerp(41, 46, p), 19, lerp(74, 91, p)],
        ],
    }


def draw_background(img: Image.Image, frame: int) -> None:
    draw = ImageDraw.Draw(img)
    for y in range(H):
        k = y / H
        col = (lerp(8, 18, k), lerp(11, 19, k), lerp(20, 34, k))
        draw.line([(0, y), (W, y)], fill=col)
    # soft decorative glows, not a game scene
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse((-80, -90, 270, 230), fill=(33, 119, 255, 38))
    gd.ellipse((530, 245, 930, 610), fill=(255, 192, 82, 26))
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(32)))
    # subtle dot grid
    for x in range(20, W, 24):
        for y in range(18, H, 24):
            if (x + y + frame) % 3 == 0:
                draw.point((x, y), fill=(255, 255, 255, 13))


def draw_tab(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int], label: str, active: bool) -> None:
    fill = (255, 255, 255, 40) if active else (255, 255, 255, 14)
    outline = BORDER_ACTIVE if active else (76, 86, 108, 150)
    rounded(draw, box, 7, fill=fill, outline=outline, width=2 if active else 1)
    tw, th = text_size(draw, label, FONT_TAB)
    draw.text(((box[0] + box[2] - tw) // 2, (box[1] + box[3] - th) // 2 - 1), label, font=FONT_TAB, fill=TEXT if active else MUTED)


def draw_headers(draw: ImageDraw.ImageDraw, tab: str, x: int, y: int) -> list[int]:
    draw.text((x + 78, y), "Player", font=FONT_HEAD, fill=MUTED)
    if tab == "Meter":
        headers = [("%", 342), ("Total", 430), ("Combat", 522), ("Last", 601), ("Max", 668)]
    elif tab == "Card Usage":
        headers = [("Cards", 348), ("Attack", 430), ("Skill", 510), ("Power", 590), ("Auto", 668)]
    else:
        headers = [("Incoming", 384), ("Blocked", 474), ("HP Lost", 560), ("Max", 630), ("Block+", 700)]
    for label, rx in headers:
        draw_right(draw, (rx, y), label, FONT_HEAD, MUTED)
    return [rx for _, rx in headers]


def draw_player_row(draw: ImageDraw.ImageDraw, idx: int, tab: str, row_values: list[int], total_damage: int, frame: int, x: int, y: int, col_x: list[int]) -> None:
    row_h = 48
    row_y = y + idx * row_h
    if idx % 2 == 0:
        rounded(draw, (x + 10, row_y - 6, x + 650, row_y + 38), 8, fill=(255, 255, 255, 10))
    name, initial, color = PLAYERS[idx]
    avatar = (x + 21, row_y - 2, x + 57, row_y + 34)
    draw.ellipse(avatar, fill=color + (235,), outline=(255, 255, 255, 80), width=1)
    tw, th = text_size(draw, initial, FONT_AVATAR)
    draw.text(((avatar[0] + avatar[2] - tw) // 2, (avatar[1] + avatar[3] - th) // 2 - 2), initial, font=FONT_AVATAR, fill=(12, 16, 24))
    draw.text((x + 70, row_y + 1), name, font=FONT_BODY, fill=TEXT)
    draw.text((x + 70, row_y + 22), "online", font=FONT_SMALL, fill=GREEN if idx != 3 else MUTED)

    if tab == "Meter":
        pct = pct_values(frame / 24)[idx]
        vals: Iterable[tuple[str, tuple[int, int, int]]] = [
            (f"{int(round(pct * 100))}%", YELLOW),
            (f"{row_values[0]:,}", TEXT),
            (f"{row_values[1]:,}", CYAN),
            (str(row_values[2]), MUTED),
            (str(row_values[3]), RED),
        ]
    elif tab == "Card Usage":
        vals = [
            (str(row_values[0]), YELLOW),
            (str(row_values[1]), RED),
            (str(row_values[2]), CYAN),
            (str(row_values[3]), PINK),
            (str(row_values[4]), GREEN),
        ]
    else:
        vals = [
            (str(row_values[0]), YELLOW),
            (str(row_values[1]), CYAN),
            (str(row_values[2]), RED),
            (str(row_values[3]), PINK),
            (str(row_values[4]), GREEN),
        ]
    for rx, (value, color) in zip(col_x, vals):
        draw_right(draw, (rx, row_y + 8), value, FONT_BODY, color)


def render_frame(frame: int) -> Image.Image:
    img = Image.new("RGBA", (W, H), BG + (255,))
    draw_background(img, frame)
    draw = ImageDraw.Draw(img, "RGBA")

    tab_index = (frame // FRAMES_PER_TAB) % len(TABS)
    tab = TABS[tab_index]
    local = frame % FRAMES_PER_TAB
    fade = 1.0

    px, py, pw, ph = 45, 44, 670, 382
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    rounded(sd, (px + 7, py + 10, px + pw + 7, py + ph + 10), 18, fill=(0, 0, 0, 130))
    img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(13)))
    draw = ImageDraw.Draw(img, "RGBA")
    rounded(draw, (px, py, px + pw, py + ph), 18, fill=PANEL, outline=BORDER, width=1)
    rounded(draw, (px + 12, py + 12, px + pw - 12, py + 68), 12, fill=PANEL_2, outline=(255, 255, 255, 25), width=1)

    draw.text((px + 28, py + 27), "DPS Meter", font=FONT_TITLE, fill=TEXT)
    draw.text((px + 153, py + 34), "display-only overlay", font=FONT_SMALL, fill=MUTED)
    rounded(draw, (px + pw - 118, py + 25, px + pw - 30, py + 51), 13, fill=(130, 239, 156, 28), outline=(130, 239, 156, 120))
    draw.text((px + pw - 101, py + 30), "LIVE", font=FONT_TAB, fill=GREEN)

    tab_y = py + 82
    tab_w = 198
    for i, label in enumerate(TABS):
        bx = px + 22 + i * (tab_w + 10)
        draw_tab(draw, (bx, tab_y, bx + tab_w, tab_y + 35), label, i == tab_index)

    body_alpha = int(255 * fade)
    overlay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay, "RGBA")
    col_x = draw_headers(od, tab, px + 4, py + 134)
    od.line((px + 22, py + 157, px + pw - 22, py + 157), fill=(255, 255, 255, 45), width=1)

    data = values_for(frame)[tab]
    totals = [r[0] for r in values_for(frame)["Meter"]]
    for idx, row in enumerate(data):
        draw_player_row(od, idx, tab, row, totals[idx], frame, px + 4, py + 176, col_x)

    # Keep the demo focused on the overlay table; no game scene is simulated.
    if body_alpha < 255:
        alpha = overlay.getchannel("A").point(lambda v: v * body_alpha // 255)
        overlay.putalpha(alpha)
    img.alpha_composite(overlay)

    flattened = Image.new("RGB", img.size, BG)
    flattened.paste(img, mask=img.getchannel("A"))
    return flattened.convert("P", palette=Image.Palette.ADAPTIVE, colors=128)


def main() -> None:
    OUT.parent.mkdir(parents=True, exist_ok=True)
    frames = [render_frame(i) for i in range(FRAMES_PER_TAB * len(TABS))]
    frames[0].save(
        OUT,
        save_all=True,
        append_images=frames[1:],
        duration=int(1000 / FPS),
        loop=0,
        optimize=True,
        disposal=2,
    )
    print(f"Wrote {OUT.relative_to(ROOT)} ({OUT.stat().st_size / 1024:.1f} KiB)")


if __name__ == "__main__":
    main()
