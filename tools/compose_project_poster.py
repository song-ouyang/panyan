from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
SOURCE = Path('/Users/guoba/.codex/generated_images/019f6164-006c-73c2-93b7-1796a1b312e6/exec-14a49828-f8ef-4496-ae5e-484a380145ff.png')
OUT = ROOT / 'output' / '完攀日记-项目宣传海报.jpg'
OUT.parent.mkdir(parents=True, exist_ok=True)

image = Image.open(SOURCE).convert('RGB')
draw = ImageDraw.Draw(image)
font_path = '/System/Library/Fonts/STHeiti Medium.ttc'
font_light = '/System/Library/Fonts/STHeiti Light.ttc'

def font(size, light=False):
    return ImageFont.truetype(font_light if light else font_path, size)

coral = '#FF684A'
purple = '#8D62E8'
ink = '#24211F'
muted = '#746A63'

# Brand pill
draw.rounded_rectangle((72, 80, 300, 140), radius=30, fill=coral)
draw.text((101, 92), '室内抱石社区', font=font(28), fill='white')

# Main headline
draw.text((72, 184), '完攀日记', font=font(92), fill=ink)
draw.rounded_rectangle((74, 300, 280, 316), radius=8, fill=coral)
draw.rounded_rectangle((292, 300, 356, 316), radius=8, fill='#FFC83D')
draw.text((72, 354), '记录每一次上墙', font=font(47), fill=ink)
draw.text((72, 418), '看见每一步成长', font=font(47), fill=purple)

# Product description
draw.text((74, 516), '找线路  ·  记完攀  ·  看成长  ·  约岩友', font=font(29), fill=muted)

# Feature chips
chips = [('线路查询', coral), ('视频打卡', purple), ('成长统计', '#E0A100'), ('积分排行', coral)]
x, y = 72, 586
for label, color in chips:
    width = draw.textbbox((0, 0), label, font=font(25))[2] + 50
    draw.rounded_rectangle((x, y, x + width, y + 56), radius=18, fill='white', outline=color, width=3)
    draw.text((x + 25, y + 12), label, font=font(25), fill=color)
    x += width + 16

# Footer brand line
draw.rounded_rectangle((64, 1460, 568, 1510), radius=25, fill=(255, 248, 238))
draw.text((88, 1471), '让每一次完攀，都成为成长的答案', font=font(24), fill=ink)

image.save(OUT, 'JPEG', quality=88, optimize=True, progressive=True)
print(OUT)
