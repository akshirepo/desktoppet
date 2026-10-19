"""Builds Assets/AppIcon/AppIcon-1024.png: the sheep's face (from the idle sprite) on a rounded-square background."""
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "Assets/Packs/SheepPack/idle/0001.png"
OUT = ROOT / "Assets/AppIcon/AppIcon-1024.png"
FACE_BOX = (112, 40, 308, 214)   # head, ears and cap on the 420x320 idle canvas

def build():
    face = Image.open(SRC).convert("RGBA").crop(FACE_BOX)
    face = face.crop(face.getchannel("A").point(lambda v: 255 if v > 40 else 0).getbbox())
    size = 1024
    icon = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    # macOS icon grid: an 824px rounded square centered on a 1024 canvas.
    body = Image.new("RGBA", (824, 824), (0, 0, 0, 0))
    grad = Image.new("RGBA", (824, 824))
    top, bottom = (196, 228, 255), (140, 196, 160)
    for y in range(824):
        f = y / 823
        grad.paste(tuple(int(top[i] + (bottom[i] - top[i]) * f) for i in range(3)) + (255,), (0, y, 824, y + 1))
    mask = Image.new("L", (824, 824), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, 823, 823), radius=186, fill=255)
    body.paste(grad, (0, 0), mask)
    # a soft grass hill at the bottom
    hill = Image.new("L", (824, 824), 0)
    ImageDraw.Draw(hill).ellipse((-200, 600, 1024, 1200), fill=255)
    hill_layer = Image.new("RGBA", (824, 824), (110, 170, 120, 255))
    body.paste(hill_layer, (0, 0), Image.composite(hill, Image.new("L", (824, 824), 0), mask))
    # face, scaled with hard pixel edges
    scale = 600 / max(face.size)
    face = face.resize((round(face.width * scale), round(face.height * scale)), Image.NEAREST)
    body.alpha_composite(face, ((824 - face.width) // 2, (824 - face.height) // 2 + 30))
    icon.alpha_composite(body, (100, 100))
    OUT.parent.mkdir(parents=True, exist_ok=True)
    icon.save(OUT)
    return OUT

if __name__ == "__main__":
    print(build())
