#!/usr/bin/env python3
"""
Placeholder graphics generator for pylon-transformers.
Generates entity sprites, icons, and technology icons for every
kind x tier x size combination, matching config.lua naming exactly.

Run from your mod's root directory:
    python generate_placeholders.py
"""

from PIL import Image, ImageDraw, ImageFont
import os

# ---- Must match config.lua ----
KINDS = ["up", "down"]
SIZES = ["small", "medium", "large"]
TIER_COUNT = 6

# ---- Output paths (relative to mod root) ----
ENTITY_DIR = "graphics/entity"
ICON_DIR = "graphics/icons"
TECH_DIR = "graphics/technology"

# ---- Image dimensions (must match transformers.lua) ----
ENTITY_SIZE = (256, 128)
ICON_SIZE = (64, 64)
TECH_SIZE = (128, 128)

# ---- Color scheme ----
# Kind controls hue family: up = warm (orange/red), down = cool (blue/cyan)
KIND_BASE_COLOR = {
    "up":   (200, 90, 40),   # orange-red
    "down": (40, 110, 200),  # blue
}

# Size controls brightness/saturation multiplier (small=darker, large=brighter)
SIZE_BRIGHTNESS = {
    "small":  0.65,
    "medium": 0.85,
    "large":  1.05,
}

# Tier controls a secondary accent stripe color, cycling through a palette
TIER_ACCENT = [
    (255, 215, 0),   # tier 1 - gold
    (192, 192, 192), # tier 2 - silver
    (205, 127, 50),  # tier 3 - bronze
    (0, 200, 150),   # tier 4 - teal
    (180, 0, 200),   # tier 5 - purple
    (255, 255, 255), # tier 6 - white
]


def clamp(v, lo=0, hi=255):
    return max(lo, min(hi, int(v)))


def shade_color(base, factor):
    return tuple(clamp(c * factor) for c in base)


def get_font(size):
    """Try to load a system font; fall back to default bitmap font."""
    candidates = [
        "arial.ttf", "DejaVuSans-Bold.ttf", "Arial.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "C:\\Windows\\Fonts\\arialbd.ttf",
    ]
    for path in candidates:
        try:
            return ImageFont.truetype(path, size)
        except (OSError, IOError):
            continue
    return ImageFont.load_default()


def draw_centered_text(draw, text, box, font, fill):
    """Draw text centered within box = (x0, y0, x1, y1)."""
    x0, y0, x1, y1 = box
    bbox = draw.textbbox((0, 0), text, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    cx = x0 + (x1 - x0 - tw) / 2 - bbox[0]
    cy = y0 + (y1 - y0 - th) / 2 - bbox[1]
    draw.text((cx, cy), text, font=font, fill=fill)


def make_entity_sprite(kind, tier, size):
    base = KIND_BASE_COLOR[kind]
    factor = SIZE_BRIGHTNESS[size]
    fill_color = shade_color(base, factor)
    accent = TIER_ACCENT[tier - 1]

    img = Image.new("RGBA", ENTITY_SIZE, (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    w, h = ENTITY_SIZE
    margin = 10
    # Main body rectangle
    draw.rounded_rectangle(
        [margin, margin, w - margin, h - margin],
        radius=12,
        fill=fill_color + (255,),
        outline=(20, 20, 20, 255),
        width=4,
    )

    # Accent stripe (tier indicator) along the top
    draw.rectangle(
        [margin, margin, w - margin, margin + 14],
        fill=accent + (255,),
    )

    # Direction arrow: up = pointing right-up, down = pointing right-down
    # (crude visual cue distinguishing step-up vs step-down)
    arrow_color = (255, 255, 255, 255)
    cx, cy = w // 2, h // 2 + 10
    if kind == "up":
        draw.polygon([(cx - 20, cy + 15), (cx + 20, cy + 15), (cx, cy - 15)], fill=arrow_color)
    else:
        draw.polygon([(cx - 20, cy - 15), (cx + 20, cy - 15), (cx, cy + 15)], fill=arrow_color)

    # Label text: KIND / SIZE / Txx
    font_big = get_font(22)
    font_small = get_font(16)
    label_top = f"{kind.upper()} - {size.upper()}"
    label_bottom = f"TIER {tier}"

    draw_centered_text(draw, label_top, (margin, margin + 18, w - margin, h // 2), font_small, (255, 255, 255, 255))
    draw_centered_text(draw, label_bottom, (margin, h // 2 + 20, w - margin, h - margin), font_big, (255, 255, 255, 255))

    return img


def make_icon(kind, tier, size):
    """Icons are just entity sprites cropped/resized to square, simplified."""
    base = KIND_BASE_COLOR[kind]
    factor = SIZE_BRIGHTNESS[size]
    fill_color = shade_color(base, factor)
    accent = TIER_ACCENT[tier - 1]

    img = Image.new("RGBA", ICON_SIZE, (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    w, h = ICON_SIZE
    margin = 4

    draw.rounded_rectangle(
        [margin, margin, w - margin, h - margin],
        radius=8,
        fill=fill_color + (255,),
        outline=(20, 20, 20, 255),
        width=2,
    )
    draw.rectangle([margin, margin, w - margin, margin + 8], fill=accent + (255,))

    font = get_font(14)
    label = f"{size[0].upper()}{tier}"  # e.g. "L4", "S1"
    draw_centered_text(draw, label, (margin, margin + 8, w - margin, h - margin), font, (255, 255, 255, 255))

    return img


def make_tech_icon(tier):
    accent = TIER_ACCENT[tier - 1]
    img = Image.new("RGBA", TECH_SIZE, (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    w, h = TECH_SIZE
    margin = 8

    draw.ellipse(
        [margin, margin, w - margin, h - margin],
        fill=(60, 60, 60, 255),
        outline=accent + (255,),
        width=6,
    )

    font = get_font(36)
    draw_centered_text(draw, f"T{tier}", (margin, margin, w - margin, h - margin), font, accent + (255,))

    return img


def main():
    os.makedirs(ENTITY_DIR, exist_ok=True)
    os.makedirs(ICON_DIR, exist_ok=True)
    os.makedirs(TECH_DIR, exist_ok=True)

    count = 0

    for kind in KINDS:
        for tier in range(1, TIER_COUNT + 1):
            for size in SIZES:
                shell_name = f"pt-{kind}-{size}-t{tier}"

                entity_img = make_entity_sprite(kind, tier, size)
                entity_path = os.path.join(ENTITY_DIR, f"{shell_name}.png")
                entity_img.save(entity_path)
                count += 1

                icon_img = make_icon(kind, tier, size)
                icon_path = os.path.join(ICON_DIR, f"{shell_name}.png")
                icon_img.save(icon_path)
                count += 1

    for tier in range(1, TIER_COUNT + 1):
        tech_img = make_tech_icon(tier)
        tech_path = os.path.join(TECH_DIR, f"pt-tier-{tier}.png")
        tech_img.save(tech_path)
        count += 1

    print(f"Generated {count} placeholder images:")
    print(f"  - {len(KINDS) * TIER_COUNT * len(SIZES)} entity sprites in {ENTITY_DIR}/")
    print(f"  - {len(KINDS) * TIER_COUNT * len(SIZES)} icons in {ICON_DIR}/")
    print(f"  - {TIER_COUNT} technology icons in {TECH_DIR}/")


if __name__ == "__main__":
    main()