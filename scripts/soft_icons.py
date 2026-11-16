"""Draws the in-scene icons (hearts, Zzz, drops, need icons) in the soft sticker style of the speech bubble:
flat pastel fill, white border, a faint dark edge, a little shine. Output: 96x96 PNGs.

  soft_icons.py <out dir> <Fredoka.ttf>"""
import sys, os, math
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageChops
S = 384
out, fredoka = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)

def blank(): return Image.new('L', (S, S), 0)
def soften(m, r=7): return m.filter(ImageFilter.GaussianBlur(r)).point(lambda v: 255 if v > 127 else 0)
def grow(m, r): return m.filter(ImageFilter.GaussianBlur(r * 0.5)).point(lambda v: 255 if v > 18 else 0) if r else m

def poly(points, r=7):
    m = blank(); ImageDraw.Draw(m).polygon(points, fill=255); return soften(m, r)
def ellipse(cx, cy, rx, ry):
    m = blank(); ImageDraw.Draw(m).ellipse((cx - rx, cy - ry, cx + rx, cy + ry), fill=255); return m
def union(*ms):
    m = blank()
    for x in ms: m = ImageChops.lighter(m, x)
    return m
def place(m, scale=1.0, dx=0, dy=0, rot=0):
    w = int(S * scale); x = m.resize((w, w), Image.LANCZOS).rotate(rot, resample=Image.BICUBIC)
    o = blank(); o.paste(x, ((S - w) // 2 + dx, (S - w) // 2 + dy)); return o.point(lambda v: 255 if v > 127 else 0)

def heart():
    pts = []
    for i in range(200):
        t = 2 * math.pi * i / 200
        x = 16 * math.sin(t) ** 3; y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        pts.append((S / 2 + x * 8.6, S / 2 - 10 - y * 8.6))
    return poly(pts, 5)
def star(points=5, inner=0.5, R=150):
    pts = []
    for i in range(points * 2):
        a = -math.pi / 2 + math.pi * i / points; r = R if i % 2 == 0 else R * inner
        pts.append((S / 2 + r * math.cos(a), S / 2 + 8 + r * math.sin(a)))
    return poly(pts, 12)
def sparkle(R=160):
    pts = []
    for i in range(160):
        a = 2 * math.pi * i / 160
        c, s = math.cos(a), math.sin(a)
        pts.append((S / 2 + R * abs(c) ** 3 * (1 if c >= 0 else -1), S / 2 + R * abs(s) ** 3 * (1 if s >= 0 else -1)))
    return poly(pts, 6)
def drop():
    m = union(ellipse(S / 2, S / 2 + 50, 92, 92), poly([(S / 2, 40), (S / 2 - 86, S / 2 + 20), (S / 2 + 86, S / 2 + 20)], 2))
    return soften(m, 9)
def moon():
    m = ellipse(S / 2 - 6, S / 2, 138, 138)
    cut = ellipse(S / 2 + 62, S / 2 - 40, 118, 118)
    return soften(ImageChops.subtract(m, cut), 8)
def text(s, size, weight='Bold'):
    f = ImageFont.truetype(fredoka, size); f.set_variation_by_name(weight)
    m = blank(); d = ImageDraw.Draw(m); box = d.textbbox((0, 0), s, font=f)
    d.text(((S - (box[2] - box[0])) / 2 - box[0], (S - (box[3] - box[1])) / 2 - box[1]), s, font=f, fill=255); return m
def paw():
    return union(ellipse(S / 2, S / 2 + 46, 78, 66), ellipse(S / 2 - 92, S / 2 - 28, 34, 42), ellipse(S / 2 - 34, S / 2 - 84, 34, 44),
                 ellipse(S / 2 + 34, S / 2 - 84, 34, 44), ellipse(S / 2 + 92, S / 2 - 28, 34, 42))

EDGE = (52, 40, 78, 84)
def icon(name, layers, shine=None, border=20):
    """layers: [(mask, (r, g, b))] bottom to top."""
    base = union(*[m for m, _ in layers])
    img = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    img.paste(Image.new('RGBA', (S, S), EDGE), (0, 0), grow(base, border + 9).filter(ImageFilter.GaussianBlur(1.5)))
    img.paste(Image.new('RGBA', (S, S), (255, 255, 255, 255)), (0, 0), grow(base, border).filter(ImageFilter.GaussianBlur(1.2)))
    for m, c in layers:
        img.paste(Image.new('RGBA', (S, S), c + (255,)), (0, 0), m.filter(ImageFilter.GaussianBlur(1.2)))
    if shine:
        cx, cy, rx, ry = shine
        hl = Image.new('RGBA', (S, S), (0, 0, 0, 0))
        ImageDraw.Draw(hl).ellipse((cx - rx, cy - ry, cx + rx, cy + ry), fill=(255, 255, 255, 150))
        img = Image.alpha_composite(img, hl.filter(ImageFilter.GaussianBlur(2)))
    img.resize((96, 96), Image.LANCZOS).save(os.path.join(out, name + '.png'))

PINK, BLUE, PALE, GOLD, BUTTER, PLUM, CORAL, TAN = (255, 122, 142), (112, 190, 245), (170, 218, 250), (255, 208, 92), (255, 222, 130), (112, 96, 150), (255, 138, 92), (201, 138, 94)
h = heart()
icon('heart', [(h, PINK)], shine=(136, 118, 30, 18))
icon('hearts', [(place(h, 0.72, -52, 30), PINK), (place(h, 0.5, 86, -76, -12), (255, 160, 176))])
icon('star', [(star(), GOLD)], shine=(150, 130, 22, 12))
big, small = place(sparkle(), 0.74, -40, 34), place(sparkle(), 0.42, 100, -92)
icon('sparkles', [(big, GOLD), (small, BUTTER)])
icon('refreshed-sparkle', [(big, (126, 214, 190)), (small, (170, 232, 214))])
d = drop()
icon('water-droplet', [(d, BLUE)], shine=(150, 206, 20, 34))
icon('teardrop', [(place(d, 0.8), PALE)], shine=(160, 206, 16, 26))
icon('sweat-drops', [(place(d, 0.5, -70, 40, 28), BLUE), (place(d, 0.38, 62, -56, -24), PALE), (place(d, 0.3, 96, 84, -40), PALE)], border=16)
m = moon()
icon('moon', [(m, BUTTER)]); icon('moon-small', [(place(m, 0.86), BUTTER)])
icon('zzz', [(union(place(text('Z', 300), 0.3, -104, 86), place(text('Z', 300), 0.42, 0, 4), place(text('Z', 300), 0.56, 88, -92)), PLUM)], border=16)
icon('exclamation', [(text('!', 330), CORAL)])
p = paw()
icon('paw-prints', [(place(p, 0.56, -62, 56, 14), (224, 150, 130)), (place(p, 0.46, 74, -70, -10), (236, 176, 158))], border=16)
icon('ellipsis', [(union(ellipse(S / 2 - 104, S / 2, 36, 36), ellipse(S / 2, S / 2, 36, 36), ellipse(S / 2 + 104, S / 2, 36, 36)), PLUM)], border=16)
# Food bowl: a mound of kibble in a pink bowl.
bowl = poly([(52, 196), (332, 196), (292, 316), (92, 316)], 14)
food = ImageChops.subtract(ellipse(S / 2, 196, 120, 84), poly([(0, 200), (S, 200), (S, S), (0, S)], 1))
icon('feed', [(food, TAN), (bowl, (255, 150, 170))], shine=(120, 232, 26, 12))
print(sorted(os.listdir(out)))
