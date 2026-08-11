#!/usr/bin/env python3
"""Inline the mock's artwork and data into a single self-contained page.

External hosts are blocked when the page is published as an Artifact, and a
file:// page can't fetch a sibling JSON either — so both the images and the
Cinemeta/IMDb payload are baked in at build time.
"""
import base64, json, pathlib, sys

HERE = pathlib.Path(__file__).parent
SRC = HERE / "index.src.html"
OUT = HERE / "index.html"
ART = HERE / "art"
DATA = HERE / "data.json"

MIME = {".jpg": "image/jpeg", ".png": "image/png", ".webp": "image/webp"}

imgs = {}
for f in sorted(ART.iterdir()):
    if f.suffix not in MIME:
        continue
    imgs[f.stem] = f"data:{MIME[f.suffix]};base64," + base64.b64encode(f.read_bytes()).decode()

html = SRC.read_text()
for token, payload in (("__IMG_MAP__", imgs), ("__DATA__", json.loads(DATA.read_text()))):
    if token not in html:
        sys.exit(f"token {token} missing from {SRC.name}")
    html = html.replace(token, json.dumps(payload))

OUT.write_text(html)
print(f"{len(imgs)} images -> {OUT.name} ({OUT.stat().st_size/1_000_000:.2f} MB)")
