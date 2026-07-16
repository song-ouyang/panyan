from io import BytesIO
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
from pypdf import PdfReader, PdfWriter
from reportlab.pdfgen import canvas

ROOT = Path(__file__).resolve().parents[1]
SOURCE = Path('/Users/guoba/Downloads/cns_ck.pdf')
OUT = ROOT / 'output' / 'pdf' / 'cns_ck-欧阳松已签字.pdf'
TMP = ROOT / 'tmp' / 'pdfs' / 'signature-ouyangsong.png'
OUT.parent.mkdir(parents=True, exist_ok=True)
TMP.parent.mkdir(parents=True, exist_ok=True)

# Render the authorized name as a compact handwritten-style signature image.
scale = 3
sig = Image.new('RGBA', (330 * scale, 100 * scale), (255, 255, 255, 0))
draw = ImageDraw.Draw(sig)
font = ImageFont.truetype('/System/Library/Fonts/STHeiti Light.ttc', 48 * scale)
draw.text((12 * scale, 2 * scale), '欧阳松', font=font, fill=(20, 25, 32, 255))
sig = sig.rotate(2.2, resample=Image.Resampling.BICUBIC, expand=False)
box = sig.getbbox()
sig = sig.crop(box)
sig.save(TMP)

reader = PdfReader(str(SOURCE))
writer = PdfWriter()
for index, page in enumerate(reader.pages):
    if index == 1:
        width = float(page.mediabox.width)
        height = float(page.mediabox.height)
        packet = BytesIO()
        overlay = canvas.Canvas(packet, pagesize=(width, height))
        overlay.drawImage(str(TMP), 250, 303, width=66, height=22, mask='auto', preserveAspectRatio=True)
        overlay.save()
        packet.seek(0)
        page.merge_page(PdfReader(packet).pages[0])
    writer.add_page(page)

with OUT.open('wb') as target:
    writer.write(target)
print(OUT)
