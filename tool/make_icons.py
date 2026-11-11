#!/usr/bin/env python3
"""Рисует иконку приложения (нужен Pillow). Результат — в tool/icons/.

Запускать вручную только если хочется поменять иконку:
  python3 tool/make_icons.py
"""
import json
import math
import pathlib
from PIL import Image, ImageDraw

OUT = pathlib.Path(__file__).resolve().parent / "icons"
C1, C2 = (67, 56, 202), (168, 85, 247)  # индиго → фиолетовый
SS = 4

# Варианты иконки (ключи совпадают с lib/state/app_settings.dart).
VARIANTS = {
    "indigo": ((67, 56, 202), (168, 85, 247)),
    "sunset": ((249, 115, 22), (239, 68, 68)),
    "mint": ((16, 185, 129), (6, 182, 212)),
    "ocean": ((59, 130, 246), (14, 165, 233)),
    "graphite": ((51, 65, 85), (15, 23, 42)),
}


def hexc(c):
    return "#FF%02X%02X%02X" % c


def gradient(size, c1=None, c2=None):
    c1 = c1 or C1
    c2 = c2 or C2
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * size - 2)
            px[x, y] = tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))
    return img


def dot(d, x, y, r, fill):
    d.ellipse([x - r, y - r, x + r, y + r], fill=fill)


def mark(size, scale=1.0, color=(255, 255, 255, 255)):
    """Кольцо прогресса на 3/4 и точка — «цель в движении»."""
    m = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(m)
    c = size / 2
    R = size * 0.28 * scale
    w = size * 0.10 * scale
    a0, a1 = -90, 180
    steps = 900
    for i in range(steps + 1):
        a = math.radians(a0 + (a1 - a0) * i / steps)
        dot(d, c + R * math.cos(a), c + R * math.sin(a), w / 2, color)
    a = math.radians(-90 - 38)
    dot(d, c + R * math.cos(a), c + R * math.sin(a), w * 0.55, color)
    return m


def render(size, rounded, scale=1.0, colors=None):
    big = size * SS
    c1, c2 = colors or (C1, C2)
    img = gradient(big, c1, c2).convert("RGBA")
    img.alpha_composite(mark(big, scale))
    if rounded:
        mask = Image.new("L", (big, big), 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, big - 1, big - 1], radius=int(big * 0.225), fill=255)
        out = Image.new("RGBA", (big, big), (0, 0, 0, 0))
        out.paste(img, (0, 0), mask)
        img = out
    return img.resize((size, size), Image.LANCZOS)


def foreground(size, color=(255, 255, 255, 255)):
    big = size * SS
    return mark(big, scale=0.78, color=color).resize((size, size), Image.LANCZOS)


def main():
    a = OUT / "android"
    for name, legacy, fg in [("mdpi", 48, 108), ("hdpi", 72, 162), ("xhdpi", 96, 216),
                             ("xxhdpi", 144, 324), ("xxxhdpi", 192, 432)]:
        d = a / f"mipmap-{name}"
        d.mkdir(parents=True, exist_ok=True)
        render(legacy, rounded=True).save(d / "ic_launcher.png")
        foreground(fg).save(d / "ic_launcher_foreground.png")
    ios = OUT / "ios"
    ios.mkdir(parents=True, exist_ok=True)
    for s in sorted({20, 29, 40, 48, 50, 55, 57, 58, 60, 64, 66, 72, 76, 80, 87, 88, 92, 100, 102,
                     108, 114, 120, 128, 144, 152, 167, 172, 180, 196, 216, 234, 256, 258, 512, 1024}):
        render(s, rounded=False).convert("RGB").save(ios / f"{s}.png")
    render(512, rounded=True).save(OUT / "preview.png")

    # Альтернативные иконки
    densities = [("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)]
    (a / "drawable").mkdir(parents=True, exist_ok=True)
    (a / "mipmap-anydpi-v26").mkdir(parents=True, exist_ok=True)
    alt_ios = OUT / "ios_alt"
    for key, (c1, c2) in VARIANTS.items():
        if key == "indigo":
            continue
        for name, legacy in densities:
            render(legacy, rounded=True, colors=(c1, c2)).save(a / f"mipmap-{name}" / f"ic_launcher_{key}.png")
        (a / "drawable" / f"ic_launcher_background_{key}.xml").write_text(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">\n'
            f'    <gradient android:type="linear" android:angle="315" android:startColor="{hexc(c1)}" android:endColor="{hexc(c2)}"/>\n'
            '</shape>\n', encoding="utf-8")
        (a / "mipmap-anydpi-v26" / f"ic_launcher_{key}.xml").write_text(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
            f'    <background android:drawable="@drawable/ic_launcher_background_{key}"/>\n'
            '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
            '    <monochrome android:drawable="@mipmap/ic_launcher_foreground"/>\n'
            '</adaptive-icon>\n', encoding="utf-8")
        d = alt_ios / f"AppIcon-{key.capitalize()}.appiconset"
        d.mkdir(parents=True, exist_ok=True)
        render(1024, rounded=False, colors=(c1, c2)).convert("RGB").save(d / "icon.png")
        (d / "Contents.json").write_text(json.dumps({
            "images": [{"filename": "icon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
            "info": {"author": "xcode", "version": 1},
        }, indent=2), encoding="utf-8")
        render(256, rounded=True, colors=(c1, c2)).save(OUT / f"preview_{key}.png")
    print("Иконки готовы:", OUT)


if __name__ == "__main__":
    main()
