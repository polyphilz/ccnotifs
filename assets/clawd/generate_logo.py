"""Generate animated Clawd logo GIF with shimmer effect."""

import math
from PIL import Image, ImageDraw

# Clawd pixel grid (1 = body, 0 = transparent)
GRID = [
    [0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0],
    [0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0],
    [0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0],
    [0, 0, 1, 1, 2, 1, 1, 1, 1, 1, 1, 2, 1, 1, 0, 0],
    [0, 0, 1, 1, 2, 1, 1, 1, 1, 1, 1, 2, 1, 1, 0, 0],
    [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
    [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
    [0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0],
    [0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0],
    [0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0],
    [0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0],
]

ROWS = len(GRID)
COLS = len(GRID[0])
PIXEL_SIZE = 30
PADDING = 0

WIDTH = COLS * PIXEL_SIZE + PADDING * 2
HEIGHT = ROWS * PIXEL_SIZE + PADDING * 2

# Colors
BASE = (215, 119, 87)
SHIMMER = (245, 149, 117)
EYE_COLOR = (30, 30, 30)
BG_COLOR = (30, 30, 30)

NUM_FRAMES = 24
FRAME_DURATION = 80  # ms


def lerp_color(c1, c2, t):
    return tuple(int(a + (b - a) * t) for a, b in zip(c1, c2))


def generate_frame(phase):
    img = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    for row in range(ROWS):
        for col in range(COLS):
            cell = GRID[row][col]
            if cell == 0:
                continue

            x = PADDING + col * PIXEL_SIZE
            y = PADDING + row * PIXEL_SIZE

            if cell == 2:
                color = EYE_COLOR
            else:
                # Shimmer: sine wave moving left to right
                wave = math.sin(phase + col * 0.6 + row * 0.3)
                t = (wave + 1) / 2  # normalize to 0-1
                color = lerp_color(BASE, SHIMMER, t)

            draw.rectangle([x, y, x + PIXEL_SIZE - 1, y + PIXEL_SIZE - 1], fill=color)

    return img


def main():
    frames = []
    for i in range(NUM_FRAMES):
        phase = (2 * math.pi * i) / NUM_FRAMES
        frames.append(generate_frame(phase))

    output = "../clawd-shimmer.gif"
    frames[0].save(
        output,
        save_all=True,
        append_images=frames[1:],
        duration=FRAME_DURATION,
        loop=0,
        disposal=2,
        transparency=0,
    )
    print(f"Saved {output} ({WIDTH}x{HEIGHT}, {NUM_FRAMES} frames)")


if __name__ == "__main__":
    main()
