"""Compose docs/demo.gif from frames recorded by UITests/DemoRecording.swift.

Usage: make_demo_gif.py <frames dir> <out.gif>
Each frame is frame-NN.png (phone screenshot), frame-NN.txt (file text after
the edit) and frame-NN.label (caption). Lines that changed since the previous
frame are highlighted in the text panel.

Layout: a slate gradient background, the phone screenshot inside a dark bezel
on the left, the text file as a white card on the right, both with soft drop
shadows so the two screens read clearly against the backdrop.
"""
import glob, os, sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

frames_dir, out = sys.argv[1], sys.argv[2]
PHONE_H = 600
TEXT_W = 560
PAD = 24
HEADER = 38
BEZEL = 10          # dark frame around the phone screenshot
SCREEN_R = 28       # corner radius of the phone screen
CARD_R = 12
FONT = ImageFont.truetype('/System/Library/Fonts/Menlo.ttc', 13)
HFONT = ImageFont.truetype('/System/Library/Fonts/Helvetica.ttc', 15)
LINE_H = 18

BG_TOP, BG_BOTTOM = (66, 76, 98), (38, 44, 58)
BEZEL_COLOR = (22, 24, 30)
CARD = (255, 255, 255)
CARD_EDGE = (205, 210, 220)
HIGHLIGHT = (255, 240, 170)

def gradient(w, h):
    img = Image.new('RGB', (w, h))
    d = ImageDraw.Draw(img)
    for y in range(h):
        t = y / max(h - 1, 1)
        d.line([(0, y), (w, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(BG_TOP, BG_BOTTOM)))
    return img

def rounded(img, radius):
    m = Image.new('L', img.size, 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, img.width - 1, img.height - 1), radius=radius, fill=255)
    out = Image.new('RGBA', img.size, (0, 0, 0, 0)); out.paste(img, (0, 0), m); return out

def shadow(canvas, box, radius, blur=14, offset=(0, 8), alpha=120):
    """Composite a blurred black rounded rectangle under `box` onto canvas."""
    x0, y0, x1, y1 = box
    layer = Image.new('RGBA', canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).rounded_rectangle(
        (x0 + offset[0], y0 + offset[1], x1 + offset[0], y1 + offset[1]), radius=radius, fill=(0, 0, 0, alpha))
    layer = layer.filter(ImageFilter.GaussianBlur(blur))
    canvas.alpha_composite(layer)

bases = sorted(p[:-4] for p in glob.glob(os.path.join(frames_dir, 'frame-*.png')))
prev_lines = None
composed = []
for base in bases:
    shot = Image.open(base + '.png').convert('RGB')
    screen = shot.resize((round(shot.width * PHONE_H / shot.height), PHONE_H), Image.LANCZOS)
    screen = rounded(screen, SCREEN_R)
    phone = Image.new('RGBA', (screen.width + 2 * BEZEL, screen.height + 2 * BEZEL), (0, 0, 0, 0))
    ImageDraw.Draw(phone).rounded_rectangle((0, 0, phone.width - 1, phone.height - 1),
                                            radius=SCREEN_R + BEZEL, fill=BEZEL_COLOR)
    phone.alpha_composite(screen, (BEZEL, BEZEL))
    lines = open(base + '.txt').read().rstrip('\n').split('\n')
    label = open(base + '.label').read().strip()

    W = PAD + phone.width + PAD + TEXT_W + PAD
    H = HEADER + PAD + phone.height + PAD
    canvas = gradient(W, H).convert('RGBA')
    d = ImageDraw.Draw(canvas)
    d.text((PAD, 11), label, font=HFONT, fill=(240, 242, 248))

    px, py = PAD, HEADER + PAD
    shadow(canvas, (px, py, px + phone.width, py + phone.height), SCREEN_R + BEZEL)
    canvas.alpha_composite(phone, (px, py))

    tx = PAD + phone.width + PAD
    ty = HEADER + PAD
    shadow(canvas, (tx, ty, tx + TEXT_W, ty + phone.height), CARD_R)
    d = ImageDraw.Draw(canvas)
    d.rounded_rectangle((tx, ty, tx + TEXT_W, ty + phone.height), radius=CARD_R, fill=CARD, outline=CARD_EDGE)
    d.text((tx + 12, ty + 8), 'research_TODO.txt', font=HFONT, fill=(120, 120, 130))
    y = ty + 34
    for i, line in enumerate(lines):
        changed = prev_lines is not None and (i >= len(prev_lines) or prev_lines[i] != line)
        if changed:
            d.rectangle((tx + 6, y - 2, tx + TEXT_W - 6, y + LINE_H - 2), fill=HIGHLIGHT)
        d.text((tx + 12, y), line, font=FONT, fill=(20, 20, 20))
        y += LINE_H
    prev_lines = lines
    canvas = canvas.convert('RGB')
    composed.append(canvas)
    canvas.save(base + '-composed.png')

# Palette-quantise each frame for a small, clean gif.
pal = [c.convert('P', palette=Image.ADAPTIVE, colors=256) for c in composed]
durations = [2200] * len(pal)
durations[0] = 1800
pal[0].save(out, save_all=True, append_images=pal[1:], duration=durations, loop=0, optimize=False)
print('wrote', out, len(pal), 'frames', os.path.getsize(out) // 1024, 'KB')
