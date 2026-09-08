import unittest
import importlib.util
from pathlib import Path
from PIL import Image

spec = importlib.util.spec_from_file_location("chest_cutout", Path(__file__).with_name("prepare-map-marker-chest.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
cutout = module.cutout


class ChestCutoutTests(unittest.TestCase):
    def test_enclosed_white_and_all_colored_pixels_are_preserved(self):
        image = Image.new("RGBA", (5, 5), "white")
        for x in range(1, 4):
            for y in range(1, 4):
                image.putpixel((x, y), (0, 0, 0, 255))
        image.putpixel((2, 2), (255, 255, 255, 255))
        result, box, removed, visible = cutout(image)
        self.assertEqual(box, (1, 1, 4, 4))
        self.assertEqual(removed, 16)
        self.assertEqual(visible, 9)
        self.assertEqual(result.tobytes(), image.crop(box).tobytes())
        self.assertEqual(result.getpixel((1, 1)), (255, 255, 255, 255))

    def test_near_white_antialias_and_yellow_at_exterior_are_never_recolored(self):
        image = Image.new("RGBA", (4, 4), "white")
        image.putpixel((1, 1), (254, 254, 254, 255))
        image.putpixel((2, 1), (255, 240, 120, 255))
        result, _, removed, visible = cutout(image)
        self.assertEqual(removed, 14)
        self.assertEqual(visible, 2)
        self.assertEqual([result.getpixel((x, 0)) for x in range(2)], [(254, 254, 254, 255), (255, 240, 120, 255)])


if __name__ == "__main__":
    unittest.main()
