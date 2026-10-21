#!/usr/bin/env python3
"""Create the east / south / west entity sprites from the north sprites.

The transformer is drawn facing north: 256x128 px, input on the left, output on the right.
For every graphics/entity/pt-*.png this writes, next to the original,
    <name>-east.png    rotated clockwise 90 degrees  (128x256, input on top)
    <name>-south.png   rotated 180 degrees           (256x128, input on the right)
    <name>-west.png    rotated clockwise 270 degrees (128x256, input at the bottom)
which are the files prototypes/transformers.lua expects.

Usage:  python3 make_rotated_graphics.py <path to the mod folder>
Needs:  pip install pillow
Safe to run again: it only reads the north sprites and overwrites the generated ones.
"""
import sys
from pathlib import Path

from PIL import Image

SUFFIXES = ("-east", "-south", "-west")
NORTH_SIZE = (256, 128)


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2

    entity_dir = Path(sys.argv[1]) / "graphics" / "entity"
    if not entity_dir.is_dir():
        print(f"not found: {entity_dir}")
        return 1

    sources = [p for p in sorted(entity_dir.glob("pt-*.png"))
               if not p.stem.endswith(SUFFIXES)]
    if not sources:
        print(f"no pt-*.png north sprites in {entity_dir}")
        return 1

    for src in sources:
        with Image.open(src) as img:
            if img.size != NORTH_SIZE:
                print(f"skipping {src.name}: size {img.size}, expected {NORTH_SIZE}")
                continue
            # PIL's ROTATE_270 is 270 degrees counter-clockwise = 90 degrees clockwise.
            img.transpose(Image.Transpose.ROTATE_270).save(src.with_name(src.stem + "-east.png"))
            img.transpose(Image.Transpose.ROTATE_180).save(src.with_name(src.stem + "-south.png"))
            img.transpose(Image.Transpose.ROTATE_90).save(src.with_name(src.stem + "-west.png"))

    print(f"done: {len(sources)} sprites rotated in {entity_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
