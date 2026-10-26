#!/usr/bin/env python3
"""
Original art for the radiator (nothing is taken from another mod).

Writes, relative to the mod folder:
    graphics/entity/pt-radiator.png          160 x 192 px, hi-res (scale 0.5): the 2x2 radiator
    graphics/entity/pt-radiator-shadow.png   shadow of it
    graphics/icons/pt-radiator.png           128 x 128 px item icon

Run from the mod folder (needs Pillow and numpy):  python3 make_radiator_graphics.py
Entity centre in the sprite: (80, 128), so the prototype uses shift = { 0, -0.5 }.
"""
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

S = 4                      # supersampling
W, H = 160, 192
CX, CY = 80, 128


def rgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def gradient_rect(img, box, top, bottom, horizontal=False):
    """Fill box (in final px) with a linear gradient."""
    x0, y0, x1, y1 = [int(v * S) for v in box]
    arr = np.zeros((y1 - y0, x1 - x0, 3), dtype=np.uint8)
    n = (x1 - x0) if horizontal else (y1 - y0)
    for i in range(n):
        c = lerp(top, bottom, i / max(1, n - 1))
        if horizontal:
            arr[:, i, :] = c
        else:
            arr[i, :, :] = c
    img.paste(Image.fromarray(arr, "RGB"), (x0, y0))


def rect(d, box, fill, outline=None, radius=0, width=1):
    b = [v * S for v in box]
    if radius:
        d.rounded_rectangle(b, radius * S, fill=fill, outline=outline, width=width * S)
    else:
        d.rectangle(b, fill=fill, outline=outline, width=width * S)


def make_body():
    img = Image.new("RGB", (W * S, H * S), (0, 0, 0))
    alpha = Image.new("L", (W * S, H * S), 0)
    d = ImageDraw.Draw(img)
    da = ImageDraw.Draw(alpha)

    steel_hi, steel_lo = rgb("#9aa3ab"), rgb("#4a5259")
    dark = rgb("#262b30")
    copper_hi, copper_lo = rgb("#e08a4a"), rgb("#8a4220")

    # plinth: top face and front face
    gradient_rect(img, (16, 72, 144, 184), rgb("#6d757c"), rgb("#4e555b"))
    rect(d, (16, 72, 144, 184), None, outline=rgb("#2f3439"), radius=4, width=2)
    gradient_rect(img, (16, 184, 144, 192), rgb("#3a4046"), rgb("#1f2327"))
    da.rounded_rectangle([16 * S, 72 * S, 144 * S, 192 * S], 4 * S, fill=255)

    # heat connection stubs (one per perimeter tile), drawn on the plinth edge
    stubs = [(-48, -32), (-48, 32), (48, -32), (48, 32)]
    for ox, oy in stubs:
        x, y = CX + ox, CY + oy
        gradient_rect(img, (x - 10, y - 7, x + 10, y + 7), copper_hi, copper_lo)
        rect(d, (x - 10, y - 7, x + 10, y + 7), None, outline=rgb("#5a2a14"), radius=2, width=1)
        da.rounded_rectangle([(x - 10) * S, (y - 7) * S, (x + 10) * S, (y + 7) * S], 2 * S, fill=255)
    for ox, oy in [(-32, -48), (32, -48), (-32, 48), (32, 48)]:
        x, y = CX + ox, CY + oy
        gradient_rect(img, (x - 7, y - 8, x + 7, y + 8), copper_hi, copper_lo, horizontal=True)
        rect(d, (x - 7, y - 8, x + 7, y + 8), None, outline=rgb("#5a2a14"), radius=2, width=1)
        da.rounded_rectangle([(x - 7) * S, (y - 8) * S, (x + 7) * S, (y + 8) * S], 2 * S, fill=255)

    # fin block: front face (fin ends) and top face (fins seen from above)
    bx0, bx1, by0, by1, height = 28, 132, 84, 172, 52
    # front face
    gradient_rect(img, (bx0, by1 - height, bx1, by1), steel_hi, steel_lo)
    # top face (slots between the fins are dark)
    gradient_rect(img, (bx0, by0 - height, bx1, by1 - height), rgb("#c4cbd1"), rgb("#8a939a"))
    fins = 10
    pitch = (bx1 - bx0) / fins
    for i in range(fins):
        x0 = bx0 + i * pitch + 1.5
        x1 = bx0 + (i + 1) * pitch - 1.5
        # slot between this fin and the next on the top face and on the front face
        if i < fins - 1:
            rect(d, (x1, by0 - height + 2, x1 + 3, by1 - height - 1), dark)
            rect(d, (x1, by1 - height + 1, x1 + 3, by1 - 3), dark)
        # fin highlight on the top face
        rect(d, (x0, by0 - height + 2, x0 + 2, by1 - height - 1), rgb("#e4e9ec"))
        # fin end on the front face, a little shaded towards the bottom
        gradient_rect(img, (x0, by1 - height + 1, x1, by1 - 3), rgb("#b6bec5"), rgb("#4b5259"))
    # warm glow in the lower front: the fins are where the heat goes
    glow = Image.new("RGB", (W * S, H * S), (0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.rectangle([bx0 * S, (by1 - 22) * S, bx1 * S, (by1 - 3) * S], fill=rgb("#ff8a2a"))
    glow = glow.filter(ImageFilter.GaussianBlur(7 * S))
    img = Image.fromarray(np.clip(np.asarray(img, dtype=np.int16) + (np.asarray(glow, dtype=np.int16) * 0.55), 0, 255).astype(np.uint8), "RGB")
    d = ImageDraw.Draw(img)
    # block outline and lower collector pipe on the front
    rect(d, (bx0, by0 - height, bx1, by1), None, outline=rgb("#2b3035"), radius=2, width=2)
    gradient_rect(img, (bx0 - 4, by1 - 12, bx1 + 4, by1 - 4), copper_hi, copper_lo)
    d = ImageDraw.Draw(img)
    rect(d, (bx0 - 4, by1 - 12, bx1 + 4, by1 - 4), None, outline=rgb("#5a2a14"), radius=3, width=1)
    rect(d, (bx0 - 2, by1 - 11, bx1 + 2, by1 - 9), rgb("#ffc08a"))
    # end caps of the collector pipe
    for x in (bx0 - 6, bx1 + 6):
        d.ellipse([(x - 4) * S, (by1 - 13) * S, (x + 4) * S, (by1 - 3) * S], fill=rgb("#b0b8bf"), outline=rgb("#2b3035"), width=S)

    da.rectangle([bx0 * S, (by0 - height) * S, bx1 * S, (by1 - 2) * S], fill=255)
    da.rounded_rectangle([(bx0 - 10) * S, (by1 - 13) * S, (bx1 + 10) * S, (by1 - 3) * S], 3 * S, fill=255)

    body = img.resize((W, H), Image.LANCZOS).convert("RGBA")
    body.putalpha(alpha.resize((W, H), Image.LANCZOS))
    return body


def make_shadow():
    sh = Image.new("L", (W * S, H * S), 0)
    d = ImageDraw.Draw(sh)
    # the block and plinth thrown to the lower right
    d.polygon([(30 * S, 170 * S), (134 * S, 170 * S), (176 * S, 188 * S), (72 * S, 188 * S)], fill=140)
    d.rectangle([20 * S, 150 * S, 140 * S, 186 * S], fill=90)
    sh = sh.filter(ImageFilter.GaussianBlur(2 * S)).resize((W, H), Image.LANCZOS)
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    out.putalpha(sh)
    return out


def main():
    os.makedirs("graphics/entity", exist_ok=True)
    os.makedirs("graphics/icons", exist_ok=True)
    body = make_body()
    body.save("graphics/entity/pt-radiator.png")
    make_shadow().save("graphics/entity/pt-radiator-shadow.png")
    box = body.getbbox()
    crop = body.crop(box)
    side = max(crop.size)
    icon = Image.new("RGBA", (side + 8, side + 8), (0, 0, 0, 0))
    icon.paste(crop, ((side + 8 - crop.size[0]) // 2, (side + 8 - crop.size[1]) // 2), crop)
    icon.resize((128, 128), Image.LANCZOS).save("graphics/icons/pt-radiator.png")
    print("radiator graphics written")


if __name__ == "__main__":
    main()
