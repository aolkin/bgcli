#!/usr/bin/env python3
"""Generate all macOS app icon sizes for Daemonic.

Requires: pip install Pillow

Usage: python3 generate_icon.py
"""

from PIL import Image, ImageDraw, ImageFont
import math
import os

SIZE = 1024
OUTPUT_DIR = os.path.join(
    os.path.dirname(__file__),
    "daemonic", "Assets.xcassets", "AppIcon.appiconset",
)

SIZES = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2),
]


def generate_icon():
    img = Image.new("RGBA", (SIZE, SIZE), (13, 13, 26, 255))
    draw = ImageDraw.Draw(img)

    # Background: dark gradient (fully opaque)
    for y in range(SIZE):
        t = y / SIZE
        r = int(30 * (1 - t) + 13 * t)
        g = int(30 * (1 - t) + 13 * t)
        b = int(58 * (1 - t) + 26 * t)
        draw.line([(0, y), (SIZE, y)], fill=(r, g, b, 255))

    # Subtle radial glow in center
    glow_img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow_img)
    cx, cy = SIZE // 2, SIZE // 2
    max_radius = 400
    for radius in range(max_radius, 0, -1):
        t = radius / max_radius
        alpha = int(40 * (1 - t * t))
        glow_draw.ellipse(
            [cx - radius, cy - radius, cx + radius, cy + radius],
            fill=(80, 60, 160, alpha),
        )
    img = Image.alpha_composite(img, glow_img)
    draw = ImageDraw.Draw(img)

    # Terminal window
    margin = 140
    term_left = margin
    term_top = margin + 40
    term_right = SIZE - margin
    term_bottom = SIZE - margin + 40
    corner_r = 48

    draw.rounded_rectangle(
        [term_left, term_top, term_right, term_bottom],
        radius=corner_r,
        fill=(22, 22, 44, 255),
        outline=(60, 60, 120, 180),
        width=3,
    )

    # Title bar
    titlebar_height = 56
    draw.rounded_rectangle(
        [term_left, term_top, term_right, term_top + titlebar_height + corner_r],
        radius=corner_r,
        fill=(35, 35, 65, 255),
    )
    draw.rectangle(
        [term_left, term_top + titlebar_height, term_right, term_top + titlebar_height + corner_r],
        fill=(35, 35, 65, 255),
    )
    draw.line(
        [(term_left, term_top + titlebar_height), (term_right, term_top + titlebar_height)],
        fill=(60, 60, 120, 180),
        width=2,
    )

    # Traffic light dots
    dot_y = term_top + titlebar_height // 2
    dot_start_x = term_left + 40
    dot_spacing = 36
    dot_r = 10
    for i, color in enumerate([(255, 95, 86), (255, 189, 46), (39, 201, 63)]):
        x = dot_start_x + i * dot_spacing
        draw.ellipse([x - dot_r, dot_y - dot_r, x + dot_r, dot_y + dot_r], fill=color)

    # Prompt area
    prompt_cx = (term_left + term_right) // 2
    prompt_cy = (term_top + titlebar_height + term_bottom) // 2
    teal = (0, 220, 170, 255)

    # "$" symbol
    font = None
    font_paths = [
        "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationMono-Bold.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
        "/Library/Fonts/SF-Mono-Bold.otf",
    ]
    for fp in font_paths:
        if os.path.exists(fp):
            font = ImageFont.truetype(fp, 280)
            break
    if font is None:
        font = ImageFont.load_default()

    dollar_x = prompt_cx - 110
    dollar_y = prompt_cy - 10
    bbox = draw.textbbox((0, 0), "$", font=font)
    text_w = bbox[2] - bbox[0]
    text_h = bbox[3] - bbox[1]
    draw.text(
        (dollar_x - text_w // 2, dollar_y - text_h // 2 - bbox[1]),
        "$",
        fill=teal,
        font=font,
    )

    # Infinity symbol
    inf_cx = prompt_cx + 100
    inf_cy = prompt_cy - 5
    scale_x = 90
    scale_y = 55

    points = []
    for t_deg in range(360):
        t = math.radians(t_deg)
        denom = 1 + math.sin(t) ** 2
        x = scale_x * math.cos(t) / denom
        y = scale_y * math.sin(t) * math.cos(t) / denom
        points.append((inf_cx + x, inf_cy + y))

    for i in range(len(points) - 1):
        draw.line([points[i], points[i + 1]], fill=teal, width=20)
    draw.line([points[-1], points[0]], fill=teal, width=20)

    # Flatten to RGB (fully opaque, no border artifacts on macOS)
    final = Image.new("RGB", (SIZE, SIZE), (13, 13, 26))
    final.paste(img, mask=img.split()[3])

    return final


def main():
    final = generate_icon()

    os.makedirs(OUTPUT_DIR, exist_ok=True)

    for base_size, scale in SIZES:
        pixel_size = base_size * scale
        filename = f"icon_{base_size}x{base_size}@{scale}x.png"
        resized = final.resize((pixel_size, pixel_size), Image.LANCZOS)
        resized.save(os.path.join(OUTPUT_DIR, filename), "PNG")
        print(f"Generated {filename} ({pixel_size}x{pixel_size})")

    print("Done!")


if __name__ == "__main__":
    main()
