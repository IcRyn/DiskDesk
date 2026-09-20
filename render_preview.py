"""Render the SVG emitted by the terminal mock to PNG. Requires Pillow."""
from pathlib import Path
import xml.etree.ElementTree as ET
from PIL import Image, ImageDraw, ImageFont

directory = Path(__file__).parent
root = ET.parse(directory / 'preview.svg').getroot()
image = Image.new('RGB', (816, 456), '#f0f0f0')
draw = ImageDraw.Draw(image)
font = ImageFont.truetype('C:/Windows/Fonts/consola.ttf', 20)
for element in root.iter():
    tag = element.tag.split('}')[-1]
    x, y = int(element.get('x', 0)), int(element.get('y', 0))
    if tag == 'rect':
        draw.rectangle((x, y, x + int(element.get('width')) - 1,
                        y + int(element.get('height')) - 1), fill=element.get('fill'))
    elif tag == 'text':
        draw.text((x, y), element.text or '', font=font, fill=element.get('fill'), anchor='ls')
image.save(directory / 'preview.png')
