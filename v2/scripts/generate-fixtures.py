#!/usr/bin/env python3
"""Generates the smoke test's image fixtures into apps/example/fixtures/.

The fixtures are committed, so this only needs to run when one changes. They
are generated rather than downloaded so the repository carries no third-party
artwork, and so every size the smoke scenarios assert is stated here.

Standard library only for PNG, APNG, GIF and SVG. Two formats need a tool:
JPEG uses `sips` (macOS) and animated WebP uses `img2webp` (libwebp).

Usage: python3 scripts/generate-fixtures.py
"""

import pathlib
import struct
import subprocess
import tempfile
import zlib

OUT = pathlib.Path(__file__).resolve().parent.parent / "apps/example/fixtures"

# --- PNG and APNG -----------------------------------------------------------


def chunk(kind: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))


def ihdr(width: int, height: int) -> bytes:
    # 8-bit RGB, no interlace.
    return chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))


def scanlines(rows: list[bytes]) -> bytes:
    # Filter type 0 (none) on every row: simple, and zlib does the rest.
    return zlib.compress(b"".join(b"\x00" + row for row in rows), 9)


def png(width: int, height: int, rows: list[bytes]) -> bytes:
    return b"\x89PNG\r\n\x1a\n" + ihdr(width, height) + chunk(b"IDAT", scanlines(rows)) + chunk(b"IEND", b"")


def apng(width: int, height: int, frames: list[list[bytes]], delay_ms: int) -> bytes:
    out = b"\x89PNG\r\n\x1a\n" + ihdr(width, height)
    out += chunk(b"acTL", struct.pack(">II", len(frames), 0))  # 0 = loop forever
    sequence = 0
    for index, rows in enumerate(frames):
        # Full-frame, no blending: each frame replaces the previous one.
        out += chunk(b"fcTL", struct.pack(">IIIIIHHBB", sequence, width, height, 0, 0, delay_ms, 1000, 0, 0))
        sequence += 1
        if index == 0:
            # The first frame doubles as the still image for plain PNG readers.
            out += chunk(b"IDAT", scanlines(rows))
        else:
            out += chunk(b"fdAT", struct.pack(">I", sequence) + scanlines(rows))
            sequence += 1
    return out + chunk(b"IEND", b"")


# --- GIF --------------------------------------------------------------------


def lzw(indices: bytes, min_code_size: int) -> bytes:
    """GIF's variable-width LZW, codes packed least significant bit first."""
    clear, end = 1 << min_code_size, (1 << min_code_size) + 1
    out, acc, bits = bytearray(), 0, 0

    def emit(code: int, size: int) -> None:
        nonlocal acc, bits
        acc |= code << bits
        bits += size
        while bits >= 8:
            out.append(acc & 0xFF)
            acc >>= 8
            bits -= 8

    table: dict[tuple[int, int], int] = {}
    next_code, size = end + 1, min_code_size + 1
    emit(clear, size)
    prefix = indices[0]
    for k in indices[1:]:
        if (prefix, k) in table:
            prefix = table[(prefix, k)]
            continue
        emit(prefix, size)
        table[(prefix, k)] = next_code
        next_code += 1
        # The decoder widens its codes one entry later than it learns them,
        # which is exactly when the code just assigned no longer fits.
        if next_code > (1 << size) and size < 12:
            size += 1
        # Well short of the 4096-entry limit, so the width rule above never
        # meets the 12-bit cap.
        if next_code == 4000:
            emit(clear, size)
            table.clear()
            next_code, size = end + 1, min_code_size + 1
        prefix = k
    emit(prefix, size)
    emit(end, size)
    if bits:
        out.append(acc & 0xFF)
    return bytes(out)


def gif(width: int, height: int, palette: list[tuple[int, int, int]], frames: list[bytes], delay_cs: int) -> bytes:
    bits = max(2, (len(palette) - 1).bit_length())
    table = b"".join(bytes(c) for c in palette) + b"\x00\x00\x00" * ((1 << bits) - len(palette))
    out = b"GIF89a" + struct.pack("<HHBBB", width, height, 0x80 | (bits - 1), 0, 0) + table
    out += b"\x21\xff\x0bNETSCAPE2.0\x03\x01\x00\x00\x00"  # loop forever
    for indices in frames:
        out += b"\x21\xf9\x04\x04" + struct.pack("<H", delay_cs) + b"\x00\x00"  # disposal: keep
        out += b"\x2c" + struct.pack("<HHHHB", 0, 0, width, height, 0) + bytes([bits])
        data = lzw(indices, bits)
        for i in range(0, len(data), 255):
            block = data[i : i + 255]
            out += bytes([len(block)]) + block
        out += b"\x00"
    return out + b"\x3b"


# --- pictures ---------------------------------------------------------------


def photo_rows(width: int, height: int) -> list[bytes]:
    """A smooth two-way gradient with soft bands: photo-like for a JPEG."""
    rows = []
    for y in range(height):
        g = 255 * y // (height - 1)
        band = 24 if (y * 16 // height) % 2 else 0
        rows.append(bytes(v for x in range(width) for v in (255 * x // (width - 1), g, 160 - band + (x * 8 // width) * 8)))
    return rows


PALETTE = [(24, 32, 56), (240, 196, 64), (230, 57, 70), (255, 255, 255)]


def ball_frame(width: int, height: int, step: int, steps: int) -> bytes:
    """Palette indices: a ball moving left to right over a striped floor."""
    radius = height // 5
    cx = radius + (width - 2 * radius) * step // (steps - 1)
    cy = height // 2
    out = bytearray()
    for y in range(height):
        for x in range(width):
            if (x - cx) ** 2 + (y - cy) ** 2 <= radius * radius:
                out.append(2 if (x - cx) + (y - cy) < 0 else 3)
            elif y > height * 4 // 5:
                out.append(1)
            else:
                out.append(0)
    return bytes(out)


def rgb_rows(width: int, indices: bytes) -> list[bytes]:
    flat = b"".join(bytes(PALETTE[i]) for i in indices)
    return [flat[i : i + width * 3] for i in range(0, len(flat), width * 3)]


GLYPHS = {
    "T": "11111 00100 00100 00100 00100 00100 00100",
    "U": "10001 10001 10001 10001 10001 10001 01110",
    "R": "11110 10001 10001 11110 10100 10010 10001",
    "B": "11110 10001 10001 11110 10001 10001 11110",
    "O": "01110 10001 10001 10001 10001 10001 01110",
    "I": "11111 00100 00100 00100 00100 00100 11111",
    "M": "10001 11011 10101 10101 10001 10001 10001",
    "A": "01110 10001 10001 11111 10001 10001 10001",
    "G": "01111 10000 10000 10111 10001 10001 01111",
    "E": "11111 10000 10000 11110 10000 10000 11111",
    "L": "10000 10000 10000 10000 10000 10000 11111",
    "V": "10001 10001 10001 10001 10001 01010 00100",
    "X": "10001 10001 01010 00100 01010 10001 10001",
    " ": "00000 00000 00000 00000 00000 00000 00000",
}


def text_rows(width: int, height: int, lines: list[str], scale: int) -> list[bytes]:
    """Black block capitals on white, for the Live Text scenario to find."""
    pixels = [[255] * width for _ in range(height)]
    line_height = 7 * scale + 3 * scale
    top = (height - line_height * len(lines) + 3 * scale) // 2
    for row, line in enumerate(lines):
        left = (width - len(line) * 6 * scale + scale) // 2
        for column, char in enumerate(line):
            for gy, bits in enumerate(GLYPHS[char].split()):
                for gx, bit in enumerate(bits):
                    if bit == "1":
                        for dy in range(scale):
                            y = top + row * line_height + gy * scale + dy
                            x = left + (column * 6 + gx) * scale
                            pixels[y][x : x + scale] = [0] * scale
    return [bytes(v for p in row for v in (p, p, p)) for row in pixels]


SVG = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 80">
  <rect width="120" height="80" fill="#182038"/>
  <circle cx="40" cy="40" r="24" fill="#e63946"/>
  <path d="M70 60 L90 20 L110 60 Z" fill="#f0c440"/>
</svg>
"""


def to_jpeg(png_bytes: bytes, name: str) -> None:
    with tempfile.NamedTemporaryFile(suffix=".png") as source:
        source.write(png_bytes)
        source.flush()
        subprocess.run(
            ["sips", "-s", "format", "jpeg", "-s", "formatOptions", "85", source.name, "--out", str(OUT / name)],
            check=True, stdout=subprocess.DEVNULL)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)

    to_jpeg(png(600, 400, photo_rows(600, 400)), "photo-600x400.jpg")
    to_jpeg(png(3000, 2000, photo_rows(3000, 2000)), "photo-3000x2000.jpg")
    (OUT / "text-600x400.png").write_bytes(png(600, 400, text_rows(600, 400, ["TURBOIMAGE", "LIVE TEXT"], 8)))
    (OUT / "logo.svg").write_text(SVG)

    steps = 8
    (OUT / "anim-120x120.gif").write_bytes(
        gif(120, 120, PALETTE, [ball_frame(120, 120, s, steps) for s in range(steps)], delay_cs=10))
    (OUT / "anim-100x100.png").write_bytes(
        apng(100, 100, [rgb_rows(100, ball_frame(100, 100, s, steps)) for s in range(steps)], delay_ms=100))

    with tempfile.TemporaryDirectory() as frames_dir:
        frames = []
        for s in range(steps):
            frame = pathlib.Path(frames_dir) / f"{s}.png"
            frame.write_bytes(png(160, 120, rgb_rows(160, ball_frame(160, 120, s, steps))))
            frames.append(str(frame))
        subprocess.run(
            ["img2webp", "-loop", "0", "-d", "100", "-lossless", *frames, "-o", str(OUT / "anim-160x120.webp")],
            check=True, stdout=subprocess.DEVNULL)

    for path in sorted(OUT.iterdir()):
        print(f"{path.stat().st_size:>8}  {path.name}")


if __name__ == "__main__":
    main()
