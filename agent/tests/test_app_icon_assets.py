from __future__ import annotations

import json
import math
import struct
import zlib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
APP_ICON_DIR = ROOT / "ios-watch/Assets.xcassets/AppIcon.appiconset"
WATCH_ICON_DIR = ROOT / "ios-watch/WatchIcons"
PROJECT_FILE = ROOT / "ios-watch/CodingQuota.xcodeproj/project.pbxproj"
WATCH_INFO_PLIST = ROOT / "ios-watch/Config/WatchApp-Info.plist"
SOURCE_BACKGROUND = (244, 241, 234)
SOURCE_LEFT_ARC_GREEN = (22, 201, 73)
SOURCE_RIGHT_ARC_ORANGE = (254, 122, 21)
SOURCE_TERMINAL_BLACK = (22, 24, 29)
WATCH_ICON_FILES = [
    "Icon-Watch-24x24@2x.png",
    "Icon-Watch-27.5x27.5@2x.png",
    "Icon-Watch-29x29@2x.png",
    "Icon-Watch-29x29@3x.png",
    "Icon-Watch-40x40@2x.png",
    "Icon-Watch-44x44@2x.png",
    "Icon-Watch-50x50@2x.png",
    "Icon-Watch-86x86@2x.png",
    "Icon-Watch-98x98@2x.png",
    "Icon-Watch-108x108@2x.png",
    "Icon-Watch-1024x1024@1x.png",
]


def _png_size(path: Path) -> tuple[int, int]:
    data = path.read_bytes()
    assert data.startswith(b"\x89PNG\r\n\x1a\n")
    return struct.unpack(">II", data[16:24])


def _png_rgb_at(path: Path, x_ratio: float, y_ratio: float) -> tuple[int, int, int]:
    data = path.read_bytes()
    assert data.startswith(b"\x89PNG\r\n\x1a\n")

    offset = 8
    width = height = color_type = None
    idat = bytearray()
    while offset < len(data):
        length = struct.unpack(">I", data[offset : offset + 4])[0]
        chunk_type = data[offset + 4 : offset + 8]
        chunk_data = data[offset + 8 : offset + 8 + length]
        offset += length + 12

        if chunk_type == b"IHDR":
            width, height, bit_depth, color_type, _, _, interlace = struct.unpack(">IIBBBBB", chunk_data)
            assert bit_depth == 8
            assert color_type == 2
            assert interlace == 0
        elif chunk_type == b"IDAT":
            idat.extend(chunk_data)
        elif chunk_type == b"IEND":
            break

    assert width is not None and height is not None and color_type == 2
    x = round(width * x_ratio)
    y = round(height * y_ratio)
    stride = width * 3
    raw = zlib.decompress(bytes(idat))
    previous = bytearray(stride)

    for row_index in range(height):
        row_start = row_index * (stride + 1)
        filter_type = raw[row_start]
        row = bytearray(raw[row_start + 1 : row_start + 1 + stride])

        for byte_index in range(stride):
            left = row[byte_index - 3] if byte_index >= 3 else 0
            up = previous[byte_index]
            up_left = previous[byte_index - 3] if byte_index >= 3 else 0
            if filter_type == 1:
                row[byte_index] = (row[byte_index] + left) & 0xFF
            elif filter_type == 2:
                row[byte_index] = (row[byte_index] + up) & 0xFF
            elif filter_type == 3:
                row[byte_index] = (row[byte_index] + ((left + up) // 2)) & 0xFF
            elif filter_type == 4:
                predictor = left + up - up_left
                distances = [
                    abs(predictor - left),
                    abs(predictor - up),
                    abs(predictor - up_left),
                ]
                row[byte_index] = (row[byte_index] + (left, up, up_left)[distances.index(min(distances))]) & 0xFF
            else:
                assert filter_type == 0

        if row_index == y:
            pixel_start = x * 3
            return tuple(row[pixel_start : pixel_start + 3])
        previous = row

    raise AssertionError("pixel not found")


def _color_distance(left: tuple[int, int, int], right: tuple[int, int, int]) -> float:
    return math.sqrt(sum((a - b) ** 2 for a, b in zip(left, right)))


def test_app_icon_assets_exist_and_are_wired_to_targets() -> None:
    contents_path = APP_ICON_DIR / "Contents.json"
    assert contents_path.exists()

    contents = json.loads(contents_path.read_text())
    images = contents["images"]
    assert any(image.get("platform") == "ios" or image.get("idiom") == "iphone" for image in images)
    assert any(image.get("platform") == "watchos" or image.get("idiom") == "watch" for image in images)

    filenames = {image["filename"] for image in images if "filename" in image}
    assert "Icon-App-1024x1024@1x.png" in filenames
    assert "Icon-Watch-1024x1024@1x.png" in filenames

    for filename in filenames:
        icon_path = APP_ICON_DIR / filename
        assert icon_path.exists(), filename
        width, height = _png_size(icon_path)
        assert width == height
        assert width > 0

    assert _png_size(APP_ICON_DIR / "Icon-App-1024x1024@1x.png") == (1024, 1024)
    assert _png_size(APP_ICON_DIR / "Icon-Watch-1024x1024@1x.png") == (1024, 1024)

    project = PROJECT_FILE.read_text()
    watch_info = WATCH_INFO_PLIST.read_text()
    assert project.count("Assets.xcassets in Resources") >= 1
    assert project.count("ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;") >= 2
    assert "CFBundleIcons" in watch_info

    for filename in WATCH_ICON_FILES:
        assert (WATCH_ICON_DIR / filename).exists(), filename
        assert f"{filename} in Resources" in project
        assert filename.removesuffix(".png") in watch_info


def test_app_icon_gauge_matches_source_logo_colors() -> None:
    icon_path = APP_ICON_DIR / "Icon-App-1024x1024@1x.png"

    background = _png_rgb_at(icon_path, 0.08, 0.08)
    left_arc = _png_rgb_at(icon_path, 0.23, 0.75)
    right_arc = _png_rgb_at(icon_path, 0.77, 0.75)
    terminal = _png_rgb_at(icon_path, 0.47, 0.50)

    assert _color_distance(background, SOURCE_BACKGROUND) < 10
    assert _color_distance(left_arc, SOURCE_LEFT_ARC_GREEN) < 45
    assert _color_distance(right_arc, SOURCE_RIGHT_ARC_ORANGE) < 45
    assert _color_distance(terminal, SOURCE_TERMINAL_BLACK) < 10
