"""Makes graphics/icons/pt-pylon.png (128x128) from the first frame of the pylon sprite sheet.

The sheet graphics/entity/pt-pylon.png has four 148x420 frames; the first one is the view from the
front. The icon is that frame, cropped to its visible part and fitted into 120x120 px. Run from the
mod folder: python3 make_pylon_icon.py
"""
from PIL import Image

sheet = Image.open("graphics/entity/pt-pylon.png").convert("RGBA")
frame = sheet.crop((0, 0, sheet.width // 4, sheet.height))
frame = frame.crop(frame.getbbox())
scale = min(120 / frame.width, 120 / frame.height)
frame = frame.resize((max(1, round(frame.width * scale)), max(1, round(frame.height * scale))), Image.LANCZOS)
icon = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
icon.paste(frame, ((128 - frame.width) // 2, (128 - frame.height) // 2), frame)
icon.save("graphics/icons/pt-pylon.png")
print("graphics/icons/pt-pylon.png", icon.size)
