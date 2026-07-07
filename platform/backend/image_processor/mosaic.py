from PIL import Image

from image_processor.mask import clip_box
from schemas.models import Box


def apply_mosaic_mask(image: Image.Image, boxes: list[Box]) -> Image.Image:
    output = image.copy().convert("RGB")
    for box in boxes:
        rect = clip_box(box, output)
        left, top, right, bottom = rect
        region_width = right - left
        region_height = bottom - top
        if region_width <= 0 or region_height <= 0:
            continue
        small_size = (max(1, region_width // 14), max(1, region_height // 14))
        region = output.crop(rect).resize(small_size, Image.Resampling.BILINEAR)
        region = region.resize((region_width, region_height), Image.Resampling.NEAREST)
        output.paste(region, rect)
    return output
