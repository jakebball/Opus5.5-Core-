"""Finishes an /itemicon render: trims to the item, pads it square, adds an outline and resizes.

python finish.py <in.png> <out.png> <size> <margin> <outline px> <outline hex>
The outline is the item's own silhouette grown by <outline px> and filled with <outline hex>, laid under the item, so
it reads like the UI's black UIStroke. <margin> is the share of the square left empty round the item.
"""
import sys

from PIL import Image, ImageFilter

source, target, size, margin, outline, colour = sys.argv[1], sys.argv[2], int(sys.argv[3]), float(sys.argv[4]), int(sys.argv[5]), sys.argv[6]

image = Image.open(source).convert("RGBA")
box = image.getchannel("A").point(lambda alpha: 255 if alpha > 8 else 0).getbbox()
if box is None:
    raise SystemExit(f"{source}: the render is empty")
item = image.crop(box)

# Work at the render's own resolution, then scale the finished square down once.
work = max(item.width, item.height)
pad = round(work * margin / (1 - 2 * margin))
grow = round(outline * (work + 2 * pad) / size)
side = work + 2 * pad + 2 * grow
canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
canvas.alpha_composite(item, ((side - item.width) // 2, (side - item.height) // 2))

if grow > 0:
    silhouette = canvas.getchannel("A").point(lambda alpha: 255 if alpha > 8 else 0)
    for _ in range(max(1, grow // 3)):
        silhouette = silhouette.filter(ImageFilter.MaxFilter(7))
    silhouette = silhouette.filter(ImageFilter.GaussianBlur(0.8))
    red, green, blue = (int(colour[index:index + 2], 16) for index in (0, 2, 4))
    stroke = Image.new("RGBA", canvas.size, (red, green, blue, 255))
    stroke.putalpha(silhouette)
    stroke.alpha_composite(canvas)
    canvas = stroke

canvas.resize((size, size), Image.LANCZOS).save(target)
print(f"finished {target} {size}x{size}")
