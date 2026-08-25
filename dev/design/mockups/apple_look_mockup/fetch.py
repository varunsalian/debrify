#!/usr/bin/env python3
"""Pull real Cinemeta + IMDb data and artwork for the Apple-look mock.

Everything here is a public, unauthenticated endpoint — the same two the app
itself uses (Cinemeta for catalog/meta, IMDb's GraphQL for cast photos). No
credential from the installed app is read or needed.
"""
import base64, io, json, os, pathlib, socket, urllib.request, urllib.error, ssl

# metahub advertises an AAAA record that never answers, and urllib has no
# happy-eyeballs: it blocks on the v6 attempt for the FULL timeout before
# falling back to v4. That is 30s of nothing per image (measured: 30.3s vs
# 0.3s). Resolve v4 only.
_getaddrinfo = socket.getaddrinfo
socket.getaddrinfo = lambda *a, **k: [
    x for x in _getaddrinfo(*a, **k) if x[0] == socket.AF_INET]

HERE = pathlib.Path(__file__).parent
ART = HERE / "art"
ART.mkdir(exist_ok=True)
from PIL import Image, ImageFile
# IMDb serves the odd truncated headshot; a short read should cost that one
# portrait, not the whole cast row.
ImageFile.LOAD_TRUNCATED_IMAGES = True

CINE = "https://v3-cinemeta.strem.io"
UA = {"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"}
CTX = ssl.create_default_context()


def get(url, headers=None, data=None):
    req = urllib.request.Request(url, headers={**UA, **(headers or {})}, data=data)
    with urllib.request.urlopen(req, timeout=30, context=CTX) as r:
        return r.read()


def jget(url):
    return json.loads(get(url))


def fetch_img(url, name, box, quality=82):
    """Download, downscale to fit `box`, save as jpg (or png when it has alpha).

    Resumable: an image already on disk is kept, so a re-run costs nothing for
    everything that already landed.
    """
    for ext in (".jpg", ".png"):
        if (ART / f"{name}{ext}").exists():
            return f"{name}{ext}"
    try:
        raw = get(url)
    except Exception as e:
        print("  MISS", name, e)
        return None
    try:
        im = Image.open(io.BytesIO(raw))
    except Exception as e:
        print("  BAD", name, e)
        return None
    try:
        im.thumbnail(box, Image.LANCZOS)
        if im.mode in ("RGBA", "LA", "P") and "logo" in name:
            im = im.convert("RGBA")
            p = ART / f"{name}.png"
            im.save(p, optimize=True)
        else:
            im = im.convert("RGB")
            p = ART / f"{name}.jpg"
            im.save(p, "JPEG", quality=quality, optimize=True)
    except Exception as e:
        print("  BAD", name, e)
        return None
    return p.name


def logo_luma(path):
    """Mean luminance of the logo's opaque pixels, 0..1. Metahub ships some
    BLACK wordmarks, which vanish on ink — the hero must fall back to text."""
    im = Image.open(ART / path).convert("RGBA").resize((64, 64))
    px = list(im.getdata())
    lit = [(r * 0.2126 + g * 0.7152 + b * 0.0722) for r, g, b, a in px if a > 40]
    return (sum(lit) / len(lit) / 255) if lit else 0.0


def left_third(path):
    """Mean luminance of the backdrop's left third — the identity stack's bed.
    Bright means the art has its subject on the left and text will collide."""
    im = Image.open(ART / path).convert("L")
    w, h = im.size
    crop = im.crop((0, int(h * 0.45), int(w * 0.38), h)).resize((32, 32))
    px = list(crop.getdata())
    return sum(px) / len(px) / 255


# ── catalogs ──────────────────────────────────────────────────────────────
cats = {}
for kind, cid in [("series", "top"), ("movie", "top"),
                  ("series", "imdbRating"), ("movie", "imdbRating")]:
    cats[f"{kind}_{cid}"] = jget(f"{CINE}/catalog/{kind}/{cid}.json")["metas"]
    print(f"catalog {kind}/{cid}: {len(cats[f'{kind}_{cid}'])}")

out = {"hero": [], "rows": [], "detail": None}

# ── hero: the top of Popular, series and movies interleaved ───────────────
pool = []
for a, b in zip(cats["series_top"], cats["movie_top"]):
    pool += [("series", a), ("movie", b)]

print("\nhero candidates")
for kind, m in pool[:14]:
    if len(out["hero"]) >= 6:
        break
    iid = m.get("imdb_id") or m.get("id")
    if not (m.get("logo") and m.get("background")):
        continue
    bg = fetch_img(m["background"], f"bg_{iid}", (1400, 800))
    lg = fetch_img(m["logo"], f"logo_{iid}", (520, 260))
    if not bg or not lg:
        continue
    luma = logo_luma(lg)
    lt = left_third(bg)
    print(f"  {m['name'][:32]:34} logo-luma {luma:.2f}  left-third {lt:.2f}")
    if luma < 0.30:
        print("     ^ dark wordmark — excluded, text fallback territory")
        continue
    out["hero"].append({
        "id": iid, "kind": kind, "name": m.get("name"),
        "bg": bg, "logo": lg, "logoLuma": round(luma, 3),
        "leftThird": round(lt, 3),
        "genres": (m.get("genres") or [])[:3],
        "year": str(m.get("releaseInfo") or m.get("year") or ""),
        "desc": (m.get("description") or "").replace("&apos;", "’"),
        "imdb": m.get("imdbRating"),
        "runtime": m.get("runtime") or "",
    })

# ── rows ──────────────────────────────────────────────────────────────────
ROWS = [("Popular Series", "series_top", 1), ("Popular Movies", "movie_top", 1),
        ("Featured", "series_imdbRating", 0)]
for label, key, skip in ROWS:
    items = []
    for m in cats[key][skip:skip + 9]:
        iid = m.get("imdb_id") or m.get("id")
        if not m.get("poster"):
            continue
        p = fetch_img(m["poster"], f"p_{iid}", (300, 450))
        if not p:
            continue
        items.append({"id": iid, "name": m.get("name"), "poster": p,
                      "genre": (m.get("genres") or [""])[0],
                      "year": str(m.get("releaseInfo") or "")})
    out["rows"].append({"label": label, "items": items})
    print(f"row {label}: {len(items)}")

# ── detail subject ────────────────────────────────────────────────────────
# Silo, not House of the Dragon: HotD's metahub logo measures 0.21 luminance —
# a black wordmark, invisible on ink. Exactly the hazard the hero filter catches,
# and it disqualifies a title from the logo-led detail page too.
SUBJ = "tt14688458"
meta = jget(f"{CINE}/meta/series/{SUBJ}.json")["meta"]
d = {
    "id": SUBJ, "name": meta["name"],
    "bg": fetch_img(meta["background"], f"bg_{SUBJ}", (1600, 900)),
    "logo": fetch_img(meta["logo"], f"logo_{SUBJ}", (620, 300)),
    "desc": (meta.get("description") or "").replace("&apos;", "’"),
    "genres": meta.get("genres") or [], "year": str(meta.get("releaseInfo") or ""),
    "imdb": meta.get("imdbRating"), "runtime": meta.get("runtime") or "",
    "seasons": [], "episodes": [], "cast": [],
}
vids = [v for v in (meta.get("videos") or []) if (v.get("season") or 0) > 0]
d["seasons"] = sorted({v["season"] for v in vids})
for v in [v for v in vids if v["season"] == 1][:8]:
    t = fetch_img(v.get("thumbnail"), f"ep_{SUBJ}_{v['episode']}", (500, 282)) \
        if v.get("thumbnail") else None
    d["episodes"].append({
        "n": v["episode"], "name": v.get("name"), "thumb": t,
        "overview": (v.get("overview") or "").replace("&apos;", "’"),
        "released": (v.get("released") or "")[:10],
    })
print(f"episodes: {len(d['episodes'])}")

# ── cast photos, same IMDb GraphQL the app uses ───────────────────────────
# NOT principalCredits. That block is `Stars` — three or four names, which is
# what the app reads today and is far too sparse for a row of portraits. The
# `credits` field filtered to "cast" returns a real ensemble (12 here), each
# with a character and a headshot. One query change in the app, same endpoint.
Q = """query E($id: ID!){ title(id:$id){
 credits(first:12, filter:{categories:["cast"]}){ edges{ node{
 name{ nameText{text} primaryImage{url} }
 ... on Cast { characters{name} } } } } } }"""
try:
    body = json.dumps({"query": Q, "variables": {"id": SUBJ}}).encode()
    r = json.loads(get("https://graphql.imdb.com/", {
        "Content-Type": "application/json", "Referer": "https://www.imdb.com/"}, body))
    if r.get("errors"):
        raise RuntimeError(json.dumps(r["errors"])[:200])
    for e in r["data"]["title"]["credits"]["edges"][:7]:
        try:
            n = e["node"]
            nm = n["name"]["nameText"]["text"]
            img = (n["name"].get("primaryImage") or {}).get("url")
            chars = n.get("characters") or []
            ch = chars[0].get("name") if chars else None
            f = fetch_img(img, "cast_" + nm.lower().replace(" ", "_").replace("'", ""),
                          (240, 240)) if img else None
            d["cast"].append({"name": nm, "character": ch, "photo": f})
        except Exception as ce:
            print("  cast member skipped:", ce)
    print(f"cast: {len(d['cast'])}")
except Exception as e:
    print("cast failed:", e)

# more-like-this row for the detail page
d["more"] = out["rows"][0]["items"][:7]
out["detail"] = d

(HERE / "data.json").write_text(json.dumps(out, indent=1))
total = sum(f.stat().st_size for f in ART.iterdir())
print(f"\n{len(list(ART.iterdir()))} images, {total/1_000_000:.2f} MB -> art/")
print(f"hero: {[h['name'] for h in out['hero']]}")
