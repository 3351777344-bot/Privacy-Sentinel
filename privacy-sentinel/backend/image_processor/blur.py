from PIL import Image, ImageFilter

from image_processor.mask import clip_box
from schemas.models import Box


def apply_blur_mask(image: Image.Image, boxes: list[Box]) -> Image.Image:
    output = image.copy().convert("RGB")
    for box in boxes:
        rect = clip_box(box, output)
        if rect[2] <= rect[0] or rect[3] <= rect[1]:
            continue
        region = output.crop(rect).filter(ImageFilter.GaussianBlur(radius=14))
        output.paste(region, rect)
    return output
