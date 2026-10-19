"""Build App/Assets.xcassets/AppIcon.appiconset/icon-1024.png from ~/face.png.

The sticker has a near-black backdrop that the hair almost matches, so the
matte is built by thresholding the difference from the backdrop colour,
sealing the outline with a morphological closing, and flood-filling the true
background from the image corners (everything unreached is foreground).
"""
import sys
from PIL import Image, ImageChops, ImageDraw, ImageFilter

SRC = sys.argv[1] if len(sys.argv) > 1 else '/Users/lbouma/face.png'
OUT = 'App/Assets.xcassets/AppIcon.appiconset/icon-1024.png'
PREVIEW = sys.argv[2] if len(sys.argv) > 2 else None

im = Image.open(SRC).convert('RGB')
W, H = im.size
bg = (23, 25, 21)

diff = ImageChops.difference(im, Image.new('RGB', im.size, bg)).convert('L')
mask = diff.point(lambda v: 255 if v > 10 else 0)
ImageDraw.Draw(mask).rectangle((370, 0, W, H), fill=0)       # off-colour strip
sealed = mask.filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.MinFilter(9))
flood = sealed.copy()
for seed in [(0, 0), (W-1, 0), (0, H-1), (W-1, H-1), (0, H//2), (W-1, H//2)]:
    if flood.getpixel(seed) == 0:
        ImageDraw.floodfill(flood, seed, 128)
alpha = flood.point(lambda v: 0 if v == 128 else 255)
alpha = alpha.filter(ImageFilter.MinFilter(3))                # erode 1px: drop dark fringe
alpha = alpha.filter(ImageFilter.GaussianBlur(0.8))
cut = im.convert('RGBA'); cut.putalpha(alpha)

# Square crop with the sticker's hard cut on the left edge, framing eyes + mouth.
x0, x1, y0 = 97, 376, 62
side = x1 - x0
crop = cut.crop((x0, y0, x1, y0 + side)).resize((1024, 1024), Image.LANCZOS)

# White -> pale cool grey diagonal gradient.
grad = Image.new('RGB', (1024, 1024)); px = grad.load()
top, bot = (255, 255, 255), (222, 228, 236)
for y in range(1024):
    for x in range(1024):
        t = (x + y) / 2046
        px[x, y] = tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3))
icon = grad.copy(); icon.paste(crop, (0, 0), crop)
icon.save(OUT, optimize=True)

if PREVIEW:
    def rounded(img, size, radius):
        img = img.resize((size, size), Image.LANCZOS)
        m = Image.new('L', (size, size), 0)
        ImageDraw.Draw(m).rounded_rectangle((0, 0, size-1, size-1), radius=radius, fill=255)
        out = Image.new('RGBA', (size, size), (0, 0, 0, 0)); out.paste(img, (0, 0), m); return out
    prev = Image.new('RGB', (520, 260), (235, 235, 240))
    ImageDraw.Draw(prev).rectangle((260, 0, 520, 260), fill=(30, 30, 34))
    tile = rounded(icon, 180, 40)
    prev.paste(tile, (40, 40), tile); prev.paste(tile, (300, 40), tile)
    prev.save(PREVIEW)
print('wrote', OUT)
