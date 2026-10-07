"""brushes.sheet: labelled contact sheets (a 5x7 pixel font, no image libraries), from Joust Tycoon's stage.py."""

import math

import bpy
import numpy as np

GLYPHS = {
    "A": "01110 10001 10001 11111 10001 10001 10001", "B": "11110 10001 10001 11110 10001 10001 11110",
    "C": "01110 10001 10000 10000 10000 10001 01110", "D": "11110 10001 10001 10001 10001 10001 11110",
    "E": "11111 10000 10000 11110 10000 10000 11111", "F": "11111 10000 10000 11110 10000 10000 10000",
    "G": "01110 10001 10000 10111 10001 10001 01111", "H": "10001 10001 10001 11111 10001 10001 10001",
    "I": "01110 00100 00100 00100 00100 00100 01110", "J": "00111 00010 00010 00010 00010 10010 01100",
    "K": "10001 10010 10100 11000 10100 10010 10001", "L": "10000 10000 10000 10000 10000 10000 11111",
    "M": "10001 11011 10101 10101 10001 10001 10001", "N": "10001 10001 11001 10101 10011 10001 10001",
    "O": "01110 10001 10001 10001 10001 10001 01110", "P": "11110 10001 10001 11110 10000 10000 10000",
    "Q": "01110 10001 10001 10001 10101 10010 01101", "R": "11110 10001 10001 11110 10100 10010 10001",
    "S": "01111 10000 10000 01110 00001 00001 11110", "T": "11111 00100 00100 00100 00100 00100 00100",
    "U": "10001 10001 10001 10001 10001 10001 01110", "V": "10001 10001 10001 10001 10001 01010 00100",
    "W": "10001 10001 10001 10101 10101 10101 01010", "X": "10001 10001 01010 00100 01010 10001 10001",
    "Y": "10001 10001 01010 00100 00100 00100 00100", "Z": "11111 00001 00010 00100 01000 10000 11111",
    "0": "01110 10001 10011 10101 11001 10001 01110", "1": "00100 01100 00100 00100 00100 00100 01110",
    "2": "01110 10001 00001 00010 00100 01000 11111", "3": "11111 00010 00100 00010 00001 10001 01110",
    "4": "00010 00110 01010 10010 11111 00010 00010", "5": "11111 10000 11110 00001 00001 10001 01110",
    "6": "00110 01000 10000 11110 10001 10001 01110", "7": "11111 00001 00010 00100 01000 01000 01000",
    "8": "01110 10001 10001 01110 10001 10001 01110", "9": "01110 10001 10001 01111 00001 00010 01100",
    "-": "00000 00000 00000 11111 00000 00000 00000", "+": "00000 00100 00100 11111 00100 00100 00000",
    ".": "00000 00000 00000 00000 00000 01100 01100", ",": "00000 00000 00000 00000 01100 00100 01000",
    "(": "00010 00100 01000 01000 01000 00100 00010", ")": "01000 00100 00010 00010 00010 00100 01000",
    "/": "00001 00001 00010 00100 01000 10000 10000", ":": "00000 01100 01100 00000 01100 01100 00000",
    "%": "11000 11001 00010 00100 01000 10011 00011", "'": "00100 00100 01000 00000 00000 00000 00000",
}


def read_png(path):
    image = bpy.data.images.load(path)
    width, height = image.size
    pixels = np.empty(width * height * 4, dtype=np.float32)
    image.pixels.foreach_get(pixels)
    bpy.data.images.remove(image)
    return pixels.reshape(height, width, 4)[::-1].copy()


def write_png(path, array):
    height, width = array.shape[:2]
    image = bpy.data.images.new("Out", width, height, alpha=True)
    image.pixels.foreach_set(np.ascontiguousarray(array[::-1]).ravel())
    image.filepath_raw = path
    image.file_format = "PNG"
    image.save()
    bpy.data.images.remove(image)
    return path


def draw_label(array, text, scale=3, pad=8, background=(0.08, 0.09, 0.11, 0.85), colour=(0.95, 0.95, 0.93, 1.0), at=(0, 0)):
    text = text.upper()
    glyph_width = 6 * scale
    width = len(text) * glyph_width + pad * 2
    height = 7 * scale + pad * 2
    top, left = at
    array[top:top + height, left:left + width] = background
    for index, character in enumerate(text):
        rows = GLYPHS.get(character)
        if not rows:
            continue
        for row, bits in enumerate(rows.split()):
            for column, bit in enumerate(bits):
                if bit == "1":
                    y = top + pad + row * scale
                    x = left + pad + index * glyph_width + column * scale
                    array[y:y + scale, x:x + scale] = colour
    return array


def compose(paths, columns, target, labels=None, gap=6, background=(0.10, 0.11, 0.13, 1.0)):
    tiles = [read_png(path) for path in paths]
    if labels:
        for tile, label in zip(tiles, labels):
            if label:
                draw_label(tile, label)
    height = max(tile.shape[0] for tile in tiles)
    width = max(tile.shape[1] for tile in tiles)
    rows = math.ceil(len(tiles) / columns)
    sheet = np.zeros((rows * height + (rows - 1) * gap, columns * width + (columns - 1) * gap, 4), dtype=np.float32)
    sheet[:] = background
    for index, tile in enumerate(tiles):
        row, column = divmod(index, columns)
        top, left = row * (height + gap), column * (width + gap)
        sheet[top:top + tile.shape[0], left:left + tile.shape[1]] = tile
    return write_png(target, sheet)
