#!/usr/bin/env python3
"""Build index.html from index.src.html — artwork and TVmaze data inlined.

The Artifact CSP blocks every external host, so images ship as data URIs and the
episode/cast data is baked in rather than fetched.
"""
import base64, json, pathlib, re, sys

HERE = pathlib.Path(__file__).parent
SRC = HERE / "index.src.html"
OUT = HERE / "index.html"

MIME = {".jpg": "image/jpeg", ".png": "image/png"}
imgs = {}
for f in sorted((HERE / "art").iterdir()):
    if f.suffix not in MIME:
        continue
    imgs[f.stem] = f"data:{MIME[f.suffix]};base64," + base64.b64encode(f.read_bytes()).decode()

data = json.loads((HERE / "data.json").read_text())

def clean(s: str) -> str:
    s = re.sub(r"<[^>]+>", "", s or "").replace("&amp;", "&").replace("&quot;", '"')
    s = re.sub(r"\s+", " ", s).strip()
    return s

eps = [
    {
        "n": e["n"],
        "name": e["name"],
        "date": e["date"],
        "rating": e["rating"],
        "runtime": e["runtime"],
        "summary": clean(e["summary"]),
    }
    for e in data["episodes"]
]
# "2012-07-15" reads as noise in a UI; the app shows a human date.
MON = "Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split()
for e in eps:
    y, m, d = e["date"].split("-")
    e["date"] = f"{MON[int(m)-1]} {int(d)} {y}"

html = SRC.read_text()
for token, payload in (
    ("__IMG_MAP__", json.dumps(imgs)),
    ("__EPS__", json.dumps(eps)),
    ("__CAST__", json.dumps(data["cast"])),
    ("__MCAST__", json.dumps(data["mcast"])),
    ("__MRECS__", json.dumps(data["mrecs"])),
):
    if token not in html:
        sys.exit(f"token {token} missing from {SRC.name}")
    html = html.replace(token, payload)

OUT.write_text(html)
print(f"{len(imgs)} images, {len(eps)} episodes, {len(data['cast'])} cast "
      f"-> {OUT.name} ({OUT.stat().st_size/1_000_000:.2f} MB)")
