"""Compose docs/demo.gif from frames recorded by UITests/DemoRecording.swift.

Usage: make_demo_gif.py <frames dir> <out.gif>
Each frame is frame-NN.png (phone screenshot), frame-NN.txt (file text after
the edit) and frame-NN.label (caption). Lines that changed since the previous
frame are highlighted in the text panel.
"""
import glob, os, sys
from PIL import Image, ImageDraw, ImageFont

frames_dir, out = sys.argv[1], sys.argv[2]
PHONE_H = 600
TEXT_W = 560
PAD = 20
HEADER = 34
FONT = ImageFont.truetype('/System/Library/Fonts/Menlo.ttc', 13)
HFONT = ImageFont.truetype('/System/Library/Fonts/Helvetica.ttc', 15)
LINE_H = 18

def rounded(img, radius):
    m = Image.new('L', img.size, 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, img.width - 1, img.height - 1), radius=radius, fill=255)
    out = Image.new('RGBA', img.size, (0, 0, 0, 0)); out.paste(img, (0, 0), m); return out

bases = sorted(p[:-4] for p in glob.glob(os.path.join(frames_dir, 'frame-*.png')))
prev_lines = None
composed = []
for base in bases:
    shot = Image.open(base + '.png').convert('RGB')
    phone = shot.resize((round(shot.width * PHONE_H / shot.height), PHONE_H), Image.LANCZOS)
    phone = rounded(phone, 28)
    lines = open(base + '.txt').read().rstrip('\n').split('\n')
    label = open(base + '.label').read().strip()

    W = PAD + phone.width + PAD + TEXT_W + PAD
    H = HEADER + PAD + PHONE_H + PAD
    canvas = Image.new('RGB', (W, H), (250, 250, 252))
    d = ImageDraw.Draw(canvas)
    d.text((PAD, 10), label, font=HFONT, fill=(30, 30, 30))
    canvas.paste(phone, (PAD, HEADER + PAD), phone)

    tx = PAD + phone.width + PAD
    ty = HEADER + PAD
    d.rounded_rectangle((tx, ty, tx + TEXT_W, ty + PHONE_H), radius=12, fill=(255, 255, 255), outline=(220, 220, 225))
    d.text((tx + 12, ty + 8), 'research_TODO.txt', font=HFONT, fill=(120, 120, 130))
    y = ty + 34
    for i, line in enumerate(lines):
        changed = prev_lines is not None and (i >= len(prev_lines) or prev_lines[i] != line)
        if changed:
            d.rectangle((tx + 6, y - 2, tx + TEXT_W - 6, y + LINE_H - 2), fill=(255, 244, 180))
        d.text((tx + 12, y), line, font=FONT, fill=(20, 20, 20))
        y += LINE_H
    prev_lines = lines
    composed.append(canvas)
    canvas.save(base + '-composed.png')

# Palette-quantise each frame for a small, clean gif.
pal = [c.convert('P', palette=Image.ADAPTIVE, colors=128) for c in composed]
durations = [2200] * len(pal)
durations[0] = 1800
pal[0].save(out, save_all=True, append_images=pal[1:], duration=durations, loop=0, optimize=False)
print('wrote', out, len(pal), 'frames', os.path.getsize(out) // 1024, 'KB')
