from PIL import Image

from image_processor.blur import apply_blur_mask
from image_processor.mask import apply_black_mask, clip_box
from image_processor.mosaic import apply_mosaic_mask
from schemas.models import Box


def _solid_image(size: tuple[int, int] = (200, 100), color: tuple[int, ...] = (255, 0, 0)) -> Image.Image:
    """Helper: create a solid-color test image."""
    return Image.new("RGB", size, color)


def _checkered_image(size: tuple[int, int] = (200, 100)) -> Image.Image:
    """Helper: create a checkered pattern to verify masking changes pixels."""
    img = Image.new("RGB", size, (255, 255, 255))
    for y in range(0, size[1], 10):
        for x in range(0, size[0], 10):
            if (x // 10 + y // 10) % 2 == 0:
                for dy in range(10):
                    for dx in range(10):
                        if x + dx < size[0] and y + dy < size[1]:
                            img.putpixel((x + dx, y + dy), (0, 0, 0))
    return img


class TestClipBox:
    def test_clip_inside_image(self) -> None:
        image = _solid_image()
        box = Box(x=10, y=10, width=50, height=30)
        left, top, right, bottom = clip_box(box, image)
        assert left == 10
        assert top == 10
        assert right == 60
        assert bottom == 40

    def test_clip_partially_outside(self) -> None:
        image = _solid_image()
        box = Box(x=-10, y=-5, width=100, height=200)
        left, top, right, bottom = clip_box(box, image)
        assert left == 0
        assert top == 0
        assert right == 90
        assert bottom == 100  # clipped to image height

    def test_clip_fully_outside(self) -> None:
        image = _solid_image()
        box = Box(x=300, y=300, width=10, height=10)
        left, top, right, bottom = clip_box(box, image)
        # All clamped to image bounds, resulting in zero-area rect
        assert left == 200  # min(200, 300)
        assert top == 100
        assert right == 200  # max(200, 200+10) but clamped
        assert bottom == 100


class TestBlackMask:
    def test_black_mask_replaces_pixels(self) -> None:
        image = _checkered_image()
        box = Box(x=10, y=10, width=30, height=30)
        result = apply_black_mask(image, [box])
        # Check that pixels in the masked area are now very dark
        pixel = result.getpixel((20, 20))
        assert pixel == (8, 13, 23)

    def test_black_mask_preserves_unmasked_area(self) -> None:
        image = _checkered_image()
        box = Box(x=10, y=10, width=30, height=30)
        result = apply_black_mask(image, [box])
        # Far corner should remain unchanged
        assert result.getpixel((190, 90)) == image.getpixel((190, 90))

    def test_black_mask_empty_boxes(self) -> None:
        image = _solid_image()
        result = apply_black_mask(image, [])
        assert result.tobytes() == image.tobytes()


class TestBlurMask:
    def test_blur_changes_pixels_in_region(self) -> None:
        """Blur should produce different pixels in the masked region."""
        image = _checkered_image()
        box = Box(x=10, y=10, width=30, height=30)
        result = apply_blur_mask(image, [box])
        # Pixels in blurred region should differ from original
        original_pixel = image.getpixel((20, 20))
        blurred_pixel = result.getpixel((20, 20))
        assert blurred_pixel != original_pixel

    def test_blur_preserves_unmasked_area(self) -> None:
        image = _checkered_image()
        box = Box(x=10, y=10, width=30, height=30)
        result = apply_blur_mask(image, [box])
        assert result.getpixel((190, 90)) == image.getpixel((190, 90))

    def test_blur_empty_boxes(self) -> None:
        image = _solid_image()
        result = apply_blur_mask(image, [])
        assert result.tobytes() == image.tobytes()


class TestMosaicMask:
    def test_mosaic_changes_pixels_in_region(self) -> None:
        image = _checkered_image()
        box = Box(x=10, y=10, width=40, height=40)
        result = apply_mosaic_mask(image, [box])
        original_pixel = image.getpixel((20, 20))
        mosaic_pixel = result.getpixel((20, 20))
        assert mosaic_pixel != original_pixel

    def test_mosaic_preserves_unmasked_area(self) -> None:
        image = _checkered_image()
        box = Box(x=10, y=10, width=30, height=30)
        result = apply_mosaic_mask(image, [box])
        assert result.getpixel((190, 90)) == image.getpixel((190, 90))

    def test_mosaic_empty_boxes(self) -> None:
        image = _solid_image()
        result = apply_mosaic_mask(image, [])
        assert result.tobytes() == image.tobytes()
