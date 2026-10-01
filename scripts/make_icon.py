# Generates the 1024x1024 app icon (run locally with Pillow).
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import os

S = 1024
img = Image.new("RGB", (S, S), (15, 17, 21))
d = ImageDraw.Draw(img)
for y in range(S):  # subtle vertical gradient
    t = y / S
    c = tuple(int(a + (b - a) * t) for a, b in zip((29, 33, 42), (12, 13, 17)))
    d.line([(0, y), (S, y)], fill=c)

# glow
glow = Image.new("L", (S, S), 0)
ImageDraw.Draw(glow).ellipse([212, 212, 812, 812], fill=120)
glow = glow.filter(ImageFilter.GaussianBlur(90))
img.paste(Image.new("RGB", (S, S), (201, 169, 97)), (0, 0), glow)

d = ImageDraw.Draw(img)
gold, light = (201, 169, 97), (236, 214, 158)
d.ellipse([232, 232, 792, 792], fill=gold)
d.ellipse([262, 262, 762, 762], outline=light, width=10)
try:
    f = ImageFont.truetype("seguibl.ttf", 300)
except OSError:
    f = ImageFont.truetype("arialbd.ttf", 300)
d.text((512, 500), "TT", font=f, fill=(23, 19, 10), anchor="mm")
out = os.path.join(os.path.dirname(__file__), "..", "TingTing", "Resources", "Assets.xcassets", "AppIcon.appiconset", "icon.png")
img.save(out)
print("saved", out)
