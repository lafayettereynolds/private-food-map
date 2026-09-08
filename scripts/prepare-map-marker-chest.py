"""Reproduce/verify the approved original PNG's lossless exterior-white cutout.

Only 4-connected, border-reachable exact white becomes transparent. Interior
white and every retained RGBA pixel stay unchanged. No resizing or recoloring.
"""
import argparse
from collections import deque
import hashlib
import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "docs/assets/map-marker-chest/original.png"
OUTPUTS = [ROOT / "public/map-markers/treasure-chest.png",
           ROOT / "ios/TasteMap/TasteMap/Assets.xcassets/MapMarkerTreasureChest.imageset/treasure-chest.png"]
MANIFEST = ROOT / "docs/assets/map-marker-chest/provenance.json"


def cutout(source):
    source = source.convert("RGBA")
    width, height = source.size
    pixels = source.load()
    queue = deque((x, y) for y in range(height) for x in range(width)
                  if x in (0, width - 1) or y in (0, height - 1))
    background = set()
    while queue:
        x, y = queue.popleft()
        if (x, y) in background or pixels[x, y][:3] != (255, 255, 255):
            continue
        background.add((x, y))
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= nx < width and 0 <= ny < height:
                queue.append((nx, ny))
    result = source.copy()
    for x, y in background:
        result.putpixel((x, y), (*pixels[x, y][:3], 0))
    box = result.getchannel("A").getbbox()
    assert box is not None
    result = result.crop(box)
    visible = 0
    for y in range(result.height):
        for x in range(result.width):
            actual = result.getpixel((x, y))
            expected = pixels[x + box[0], y + box[1]]
            assert actual[:3] == expected[:3], "RGB changed"
            if actual[3]:
                assert actual == expected, "non-background pixel changed"
                visible += 1
    return result, box, len(background), visible


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--verify", action="store_true")
    parser.add_argument("--original", type=Path, help="Initial authorized source; original remains untouched")
    args = parser.parse_args()
    if args.original:
        original_bytes = args.original.read_bytes()
        if SOURCE.exists():
            assert SOURCE.read_bytes() == original_bytes, "Refuse to replace a different original"
        else:
            assert not args.verify
            SOURCE.parent.mkdir(parents=True, exist_ok=True)
            SOURCE.write_bytes(original_bytes)
    original_bytes = SOURCE.read_bytes()
    source = Image.open(SOURCE)
    image, box, removed, visible = cutout(source)
    if not args.verify:
        for output in OUTPUTS:
            output.parent.mkdir(parents=True, exist_ok=True)
            image.save(output)
    for output in OUTPUTS:
        saved = Image.open(output)
        assert saved.mode == "RGBA" and saved.size == image.size
        assert saved.tobytes() == image.tobytes()
    assert OUTPUTS[0].read_bytes() == OUTPUTS[1].read_bytes()
    assert SOURCE.read_bytes() == original_bytes
    report = {
        "source": "original.png", "sourceSHA256": hashlib.sha256(original_bytes).hexdigest(),
        "algorithm": "4-connected exterior exact RGB(255,255,255) alpha removal; lossless crop; no resize",
        "sourceSize": list(source.size), "cropBox": list(box), "outputSize": list(image.size),
        "removedBackgroundPixels": removed, "unchangedVisiblePixels": visible, "visibleRGBChanges": 0,
        "outputSHA256": hashlib.sha256(OUTPUTS[0].read_bytes()).hexdigest(),
    }
    if args.verify:
        assert json.loads(MANIFEST.read_text()) == report
    else:
        MANIFEST.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"verified": True, **report}, indent=2))


if __name__ == "__main__":
    main()
