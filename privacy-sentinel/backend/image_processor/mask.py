from PIL import Image, ImageDraw

from schemas.models import Box


def clip_box(box: Box, image: Image.Image) -> tuple[int, int, int, int]:
    """Clip a box to the image bounds and return Pillow rectangle coordinates."""
    width, height = image.size
    left = max(0, min(width, box.x))
    top = max(0, min(height, box.y))
    right = max(left, min(width, box.x + box.width))
    bottom = max(top, min(height, box.y + box.height))
    return left, top, right, bottom


def apply_black_mask(image: Image.Image, boxes: list[Box]) -> Image.Image:
    output = image.copy().convert("RGB")
    draw = ImageDraw.Draw(output)
    for box in boxes:
        draw.rectangle(clip_box(box, output), fill=(8, 13, 23))
    return output
