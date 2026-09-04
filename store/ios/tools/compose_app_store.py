#!/usr/bin/env python3
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[3]
RAW_DIR = ROOT / "store" / "ios" / "screenshots" / "raw"
FINAL_DIR = ROOT / "store" / "ios" / "screenshots" / "final"
FONT_PATH = Path("/System/Library/Fonts/Hiragino Sans GB.ttc")

CANVAS_SIZE = (1284, 2778)
INK = "#24343C"
MUTED = "#69777E"
CREAM = "#FFFDF7"
VANILLA = "#FFF8E9"
CORAL = "#FF6B52"
CORAL_SHADOW = "#D94F3A"
SKY = "#43AED2"
GRAPE = "#9A78E8"
SUNFLOWER = "#FFC943"
CAT_BLACK = "#171A1E"


@dataclass(frozen=True)
class Shot:
    source: str
    output: str
    headline: str
    subhead: str
    background: str
    accent: str
    accent_soft: str
    corner_accent: str


SHOTS = (
    Shot(
        source="01-gyms.png",
        output="01-find-your-route.png",
        headline="今天，想爬哪条线？",
        subhead="找岩馆、筛线路，一键开始打卡",
        background=VANILLA,
        accent=CORAL,
        accent_soft="#FFE2D8",
        corner_accent=SUNFLOWER,
    ),
    Shot(
        source="02-feed.png",
        output="02-share-every-send.png",
        headline="和岩友分享每次完攀",
        subhead="图片、视频、点赞和评论都在这里",
        background="#F2FBFD",
        accent=SKY,
        accent_soft="#CDEFF7",
        corner_accent=CORAL,
    ),
    Shot(
        source="03-calendar.png",
        output="03-see-your-growth.png",
        headline="每一次上墙都有记录",
        subhead="用攀岩日历看见难度成长",
        background="#F8F4FF",
        accent=GRAPE,
        accent_soft="#E4D9FF",
        corner_accent=SUNFLOWER,
    ),
)


def font(size: int, *, bold: bool = False) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(FONT_PATH), size=size, index=2 if bold else 0)


def centered_text(draw: ImageDraw.ImageDraw, y: int, text: str, *, face, fill: str) -> None:
    box = draw.textbbox((0, 0), text, font=face)
    width = box[2] - box[0]
    draw.text(((CANVAS_SIZE[0] - width) / 2, y), text, font=face, fill=fill)


def hold(draw: ImageDraw.ImageDraw, center: tuple[int, int], size: int, color: str, angle: int) -> None:
    cx, cy = center
    points = [
        (-0.50, -0.08),
        (-0.20, -0.46),
        (0.31, -0.38),
        (0.52, 0.02),
        (0.18, 0.44),
        (-0.34, 0.35),
    ]
    import math

    radians = math.radians(angle)
    rotated = []
    for x, y in points:
        px = x * size
        py = y * size
        rotated.append(
            (
                cx + px * math.cos(radians) - py * math.sin(radians),
                cy + px * math.sin(radians) + py * math.cos(radians),
            )
        )
    draw.polygon(rotated, fill=color)
    hole = max(7, size // 11)
    draw.ellipse((cx - hole, cy - hole, cx + hole, cy + hole), fill="#6E5B49")


def draw_brand_pill(draw: ImageDraw.ImageDraw, accent: str) -> None:
    label = "完攀日记"
    label_font = font(34, bold=True)
    pill_width = 262
    pill_height = 70
    left = (CANVAS_SIZE[0] - pill_width) // 2
    top = 60
    draw.rounded_rectangle(
        (left, top, left + pill_width, top + pill_height),
        radius=35,
        fill=CREAM,
        outline=accent,
        width=3,
    )

    head_x = left + 39
    head_y = top + 35
    draw.polygon(
        [
            (head_x - 18, head_y - 15),
            (head_x - 13, head_y - 34),
            (head_x + 1, head_y - 21),
            (head_x + 16, head_y - 34),
            (head_x + 20, head_y - 13),
        ],
        fill=CAT_BLACK,
    )
    draw.ellipse(
        (head_x - 22, head_y - 22, head_x + 22, head_y + 22),
        fill=CAT_BLACK,
    )
    draw.ellipse((head_x - 11, head_y - 6, head_x - 5, head_y), fill="white")
    draw.ellipse((head_x + 5, head_y - 6, head_x + 11, head_y), fill="white")
    draw.text((left + 78, top + 15), label, font=label_font, fill=INK)


def paste_phone(canvas: Image.Image, source: Path, *, accent: str) -> None:
    outer_x = 122
    outer_y = 570
    outer_w = 1040
    inner_x = outer_x + 22
    inner_y = outer_y + 22
    inner_w = outer_w - 44
    inner_h = round(inner_w * CANVAS_SIZE[1] / CANVAS_SIZE[0])
    outer_h = inner_h + 44

    shadow = Image.new("RGBA", CANVAS_SIZE, (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rounded_rectangle(
        (outer_x - 12, outer_y + 16, outer_x + outer_w + 12, outer_y + outer_h + 40),
        radius=126,
        fill=(23, 26, 30, 74),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(28))
    canvas.paste(shadow, (0, 0), shadow)

    frame = Image.new("RGBA", CANVAS_SIZE, (0, 0, 0, 0))
    frame_draw = ImageDraw.Draw(frame)
    frame_draw.rounded_rectangle(
        (outer_x, outer_y, outer_x + outer_w, outer_y + outer_h),
        radius=116,
        fill=CAT_BLACK,
    )
    frame_draw.rounded_rectangle(
        (outer_x + 8, outer_y + 8, outer_x + outer_w - 8, outer_y + outer_h - 8),
        radius=108,
        outline=accent,
        width=4,
    )
    canvas.paste(frame, (0, 0), frame)

    screen = Image.open(source).convert("RGB").resize(
        (inner_w, inner_h), Image.Resampling.LANCZOS
    )
    mask = Image.new("L", (inner_w, inner_h), 0)
    mask_draw = ImageDraw.Draw(mask)
    mask_draw.rounded_rectangle((0, 0, inner_w, inner_h), radius=94, fill=255)
    canvas.paste(screen, (inner_x, inner_y), mask)


def compose(shot: Shot) -> Path:
    canvas = Image.new("RGB", CANVAS_SIZE, shot.background)
    decoration = Image.new("RGBA", CANVAS_SIZE, (0, 0, 0, 0))
    draw = ImageDraw.Draw(decoration)

    draw.ellipse((-210, 1940, 520, 2670), fill=shot.accent_soft)
    draw.ellipse((1010, 390, 1450, 830), fill=shot.accent_soft)
    draw.rounded_rectangle(
        (60, 2200, 260, 2400), radius=76, fill=shot.corner_accent
    )
    hold(draw, (86, 376), 92, shot.corner_accent, -18)
    hold(draw, (1194, 310), 74, shot.accent, 28)
    hold(draw, (1190, 2110), 92, shot.corner_accent, -32)
    canvas.paste(decoration, (0, 0), decoration)

    text_layer = Image.new("RGBA", CANVAS_SIZE, (0, 0, 0, 0))
    text_draw = ImageDraw.Draw(text_layer)
    draw_brand_pill(text_draw, shot.accent)
    centered_text(text_draw, 170, shot.headline, face=font(82, bold=True), fill=INK)

    headline_box = text_draw.textbbox((0, 0), shot.headline, font=font(82, bold=True))
    headline_width = headline_box[2] - headline_box[0]
    underline_width = min(230, max(154, int(headline_width * 0.22)))
    underline_left = (CANVAS_SIZE[0] - underline_width) // 2
    text_draw.rounded_rectangle(
        (underline_left, 294, underline_left + underline_width, 307),
        radius=7,
        fill=shot.accent,
    )
    centered_text(text_draw, 352, shot.subhead, face=font(39), fill=MUTED)
    canvas.paste(text_layer, (0, 0), text_layer)

    paste_phone(canvas, RAW_DIR / shot.source, accent=shot.accent)

    FINAL_DIR.mkdir(parents=True, exist_ok=True)
    output = FINAL_DIR / shot.output
    canvas.save(output, format="PNG", optimize=True)
    return output


def main() -> None:
    for shot in SHOTS:
        output = compose(shot)
        with Image.open(output) as image:
            if image.size != CANVAS_SIZE or image.mode != "RGB":
                raise RuntimeError(f"Invalid output {output}: {image.size} {image.mode}")
        print(output)


if __name__ == "__main__":
    main()
