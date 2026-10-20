#!/usr/bin/env python3
"""Validate legacy icon records, plist resolution and Apple's iconset decoding."""
import pathlib
import plistlib
import struct
import subprocess
import sys
import tempfile

app = pathlib.Path(sys.argv[1]).resolve()
with (app / "Contents/Info.plist").open("rb") as handle:
    info = plistlib.load(handle)
assert info["CFBundleIconFile"] == "MuguangIcon-v021.icns"
icon = app / "Contents/Resources" / info["CFBundleIconFile"]
data = icon.read_bytes()
assert data[:4] == b"icns" and struct.unpack(">I", data[4:8])[0] == len(data)
records = []
offset = 8
while offset < len(data):
    kind, length = struct.unpack(">4sI", data[offset:offset + 8])
    assert length >= 8 and offset + length <= len(data)
    records.append((kind, length, data[offset + 8:offset + length]))
    offset += length
assert offset == len(data)
by_kind = {kind: (length, payload) for kind, length, payload in records}
assert len(records) == len(by_kind), "Duplicate records"
for required in (b"TOC ", b"is32", b"s8mk", b"il32", b"l8mk", b"ic11", b"ic12", b"ic07", b"ic08", b"ic09", b"ic10", b"ic13", b"ic14"):
    assert required in by_kind, "Missing legacy/Retina record: {!r}".format(required)
assert len(by_kind[b"s8mk"][1]) == 16 * 16
assert len(by_kind[b"l8mk"][1]) == 32 * 32
assert min(by_kind[b"s8mk"][1]) == 0 and max(by_kind[b"s8mk"][1]) == 255
assert min(by_kind[b"l8mk"][1]) == 0 and max(by_kind[b"l8mk"][1]) == 255
expected_toc = b"".join(struct.pack(">4sI", kind, length) for kind, length, payload in records if kind != b"TOC ")
assert by_kind[b"TOC "][1] == expected_toc
print("PASS: plist reference, ICNS table of contents, legacy RGB and alpha masks")

with tempfile.TemporaryDirectory(prefix="muguang-icon-check-") as temporary:
    decoded = pathlib.Path(temporary) / "decoded.iconset"
    subprocess.check_call(["iconutil", "-c", "iconset", str(icon), "-o", str(decoded)])
    for size in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            filename = "icon_{}x{}{}.png".format(size, size, "@2x" if scale == 2 else "")
            png = (decoded / filename).read_bytes()
            assert png[:8] == b"\x89PNG\r\n\x1a\n"
            assert struct.unpack(">II", png[16:24]) == (size * scale, size * scale), filename
    print("PASS: system icon decoder recovered all 10 standard/Retina sizes")
