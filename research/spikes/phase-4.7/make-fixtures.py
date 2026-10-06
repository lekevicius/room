#!/usr/bin/env python3
"""Phase 4.7a fixtures: sample.pdf (three US-letter pages of text, the word
"zebracorn" twice on page 2 and once on page 3 for find) and swatch.png (a
240 x 120 orange image with a blue band, for Save Page and the capture
checks: its pixels are never white). Standard library only; rerun to
regenerate (the output is deterministic)."""
import struct
import zlib
from pathlib import Path

HERE = Path(__file__).resolve().parent


def pdf() -> bytes:
    pages = [
        ["Room PDF fixture", "Page 1 of 3", "Phase 4.7a: Chrome's PDF viewer on a Room page."],
        ["Page 2 of 3", "The zebracorn appears here,", "and the zebracorn appears again."],
        ["Page 3 of 3", "One last zebracorn.", "End of the fixture."],
    ]
    objects = []  # index i -> object number i + 1

    def add(body: bytes) -> int:
        objects.append(body)
        return len(objects)

    font = add(b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>")
    pages_id = len(objects) + 1 + 2 * len(pages)  # placeholder number, fixed below
    page_ids = []
    for lines in pages:
        text = "BT /F1 24 Tf 72 700 Td 30 TL " + " ".join(
            "(" + line.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)") + ") Tj T*" for line in lines
        ) + " ET"
        stream = text.encode("latin-1")
        content = add(b"<< /Length %d >>\nstream\n" % len(stream) + stream + b"\nendstream")
        page_ids.append(add(b"PAGE %d" % content))  # patched once the Pages id is known
    pages_id = add(b"")
    kids = " ".join("%d 0 R" % p for p in page_ids)
    objects[pages_id - 1] = ("<< /Type /Pages /Kids [%s] /Count %d >>" % (kids, len(page_ids))).encode()
    for p in page_ids:
        content = int(objects[p - 1].split()[1])
        objects[p - 1] = (
            "<< /Type /Page /Parent %d 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 %d 0 R >> >> /Contents %d 0 R >>"
            % (pages_id, font, content)
        ).encode()
    catalog = add(b"<< /Type /Catalog /Pages %d 0 R >>" % pages_id)
    info = add(b"<< /Title (Room PDF fixture) /Producer (make-fixtures.py) >>")
    out = bytearray(b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n")
    offsets = []
    for number, body in enumerate(objects, start=1):
        offsets.append(len(out))
        out += b"%d 0 obj\n" % number + body + b"\nendobj\n"
    xref = len(out)
    out += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objects) + 1)
    for offset in offsets:
        out += b"%010d 00000 n \n" % offset
    out += b"trailer\n<< /Size %d /Root %d 0 R /Info %d 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objects) + 1, catalog, info, xref)
    return bytes(out)


def png(width: int = 240, height: int = 120) -> bytes:
    rows = bytearray()
    for y in range(height):
        rows.append(0)
        for _ in range(width):
            rows += bytes((40, 90, 220)) if 50 <= y < 70 else bytes((240, 140, 20))
    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(bytes(rows), 9)) + chunk(b"IEND", b"")


if __name__ == "__main__":
    (HERE / "sample.pdf").write_bytes(pdf())
    (HERE / "swatch.png").write_bytes(png())
    print("wrote sample.pdf, swatch.png")
