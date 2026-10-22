#!/usr/bin/env python3
"""Draws the arrow images for the plugin (TGA, 32 bit, 36 rotations).

Usage: python3 -I tools/make_images.py
"""

from pathlib import Path

from PIL import Image, ImageDraw

OUT = Path(__file__).resolve().parent.parent / "plugin" / "Pathfinder" / "Route" / "Resources"
SUPERSAMPLE = 4
FRAMES = 36


def arrow(size, fill, outline, notch=0.62):
    """Supersampled arrow pointing up; scaled down after rotating."""
    big = size * SUPERSAMPLE
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    m = big * 0.08
    shape = [
        (big / 2, m),                     # tip
        (big - m * 1.4, big - m),         # right corner
        (big / 2, big * notch),           # notch
        (m * 1.4, big - m),               # left corner
    ]
    draw.polygon(shape, fill=fill, outline=outline, width=max(2, big // 24))
    return img


def save_frames(img, size, stem):
    """The plugin API can't rotate controls, so every 10 degrees gets its own
    image. Frame k is turned k*10 degrees counterclockwise."""
    for k in range(FRAMES):
        frame = img.rotate(k * 360 / FRAMES, resample=Image.BICUBIC)
        frame.resize((size, size), Image.LANCZOS).save(OUT / f"{stem}_{k:02d}.tga")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for old in OUT.glob("*.tga"):
        old.unlink()
    gold = (232, 196, 92, 255)
    dark = (40, 26, 8, 255)
    save_frames(arrow(64, gold, dark), 64, "arrow")
    save_frames(arrow(64, (150, 150, 150, 200), dark), 64, "arrow_stale")
    save_frames(arrow(24, (230, 60, 50, 255), (255, 255, 255, 255), notch=0.7), 24, "player")
    print(f"Bilder in {OUT}")


if __name__ == "__main__":
    main()
