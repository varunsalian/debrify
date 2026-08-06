#!/usr/bin/env python3
"""Inline the mock's artwork as data URIs (Artifact CSP blocks external hosts)."""
import base64, json, pathlib, sys

HERE = pathlib.Path(__file__).parent
SRC = pathlib.Path("/Users/varunbsalian/Documents/Projects/debrify/tv_home_layouts_mockup/index.html")
OUT = HERE / "tv_home_layouts.html"

mime = {".jpg": "image/jpeg", ".png": "image/png"}
imgs = {}
for f in sorted((HERE / "small").iterdir()):
    if f.suffix not in mime:
        continue
    imgs[f.stem] = f"data:{mime[f.suffix]};base64," + base64.b64encode(f.read_bytes()).decode()

html = SRC.read_text()
if "__IMG_MAP__" not in html:
    sys.exit("token __IMG_MAP__ missing from source")
html = html.replace("__IMG_MAP__", json.dumps(imgs))
OUT.write_text(html)
print(f"{len(imgs)} images -> {OUT} ({OUT.stat().st_size/1_000_000:.2f} MB)")
