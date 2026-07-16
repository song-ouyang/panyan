from pathlib import Path
from PIL import Image, ImageDraw

OUT = Path(__file__).resolve().parents[1] / "miniprogram" / "assets" / "icons"
OUT.mkdir(parents=True, exist_ok=True)
SIZE = 96

def canvas(color):
    im = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    return im, ImageDraw.Draw(im)

def line(draw, points, color, width=8, joint="curve"):
    draw.line(points, fill=color, width=width, joint=joint)

def home(d, c):
    line(d, [(18,45),(48,18),(78,45)], c)
    line(d, [(27,40),(27,77),(69,77),(69,40)], c)
    d.rounded_rectangle((42,55,55,77), radius=4, fill=c)

def gym(d, c):
    points = [(21,33),(38,17),(65,22),(78,43),(66,70),(39,78),(18,59),(21,33)]
    line(d, points, c, 8)
    d.ellipse((42,43,54,55), fill=c)

def feed(d, c):
    d.rounded_rectangle((15,22,81,75), radius=16, outline=c, width=8)
    d.polygon([(42,37),(42,61),(63,49)], fill=c)

def trophy(d, c):
    line(d, [(29,24),(67,24),(62,51),(54,61),(42,61),(34,51),(29,24)], c)
    line(d, [(29,32),(16,32),(18,48),(33,52)], c, 7)
    line(d, [(67,32),(80,32),(78,48),(63,52)], c, 7)
    line(d, [(48,61),(48,74),(31,74),(65,74)], c, 8)

def profile(d, c):
    d.ellipse((33,17,63,47), outline=c, width=8)
    d.rounded_rectangle((20,54,76,80), radius=18, outline=c, width=8)

def search(d, c):
    d.ellipse((18,17,61,60), outline=c, width=8)
    line(d, [(57,57),(80,80)], c, 9)

def heart(d, c):
    d.polygon([(48,78),(18,49),(16,32),(25,20),(39,21),(48,32),(57,21),(71,20),(80,32),(78,49)], fill=c)

def fire(d, c):
    d.polygon([(50,82),(28,72),(20,54),(27,35),(41,16),(43,39),(59,24),(72,43),(76,61),(66,76)], fill=c)
    d.ellipse((39,52,59,76), fill=(255,248,238,255))

def friends(d, c):
    d.ellipse((18,22,44,48), outline=c, width=7)
    d.ellipse((52,22,78,48), outline=c, width=7)
    d.arc((6,45,51,84), 185, 355, fill=c, width=8)
    d.arc((45,45,90,84), 185, 355, fill=c, width=8)

def check(d, c):
    line(d, [(18,49),(39,70),(80,25)], c, 10)

icons = {"home":home,"gym":gym,"feed":feed,"ranking":trophy,"profile":profile,
         "search":search,"heart":heart,"fire":fire,"friends":friends,"check":check}

for name, painter in icons.items():
    variants = [("", "#817873"), ("-active", "#F56B52")] if name in {"home","gym","feed","ranking","profile"} else [("", "#F56B52")]
    for suffix, color in variants:
        image, draw = canvas(color)
        painter(draw, color)
        image.save(OUT / f"{name}{suffix}.png", optimize=True)
