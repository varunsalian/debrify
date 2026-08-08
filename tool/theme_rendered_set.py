#!/usr/bin/env python3
"""Rendered-set measurement for a theming surface.

Two naive approaches both give wrong answers, in opposite directions:

* **Directory globs undercount** — they miss the widgets a screen renders.
* **Unbounded import walking overcounts** — every surface in this app launches
  playback, so a plain walk drags the whole player tree into all of them.
  Launching a route is a *navigation* edge, not a *rendering* one.

So this walks local imports from the given roots, **stops at route boundaries**,
keeps only files that paint, and subtracts what phase one already owns. Shared
widgets legitimately appear under more than one surface — the per-surface number
is what that surface must answer for, not a de-duplicated inventory.

    tool/theme_rendered_set.py <label> <root.dart> [root.dart ...]

    LIST=1     also print the resolved file set
    NO_P1=1    do not subtract phase-one-owned files
    RAW=1      do not stop at route boundaries (shows the overcount)

Roots for the surfaces in plan/APP_THEME_PHASE_TWO_PLAN.md — note YouTube and
IPTV need two, because main.dart injects their results view into BrowseScreen
through a callback rather than an import (main.dart:2400, :2416):

    downloads   lib/screens/downloads_screen.dart
    youtube     lib/widgets/youtube/youtube_results_view.dart lib/screens/browse_screen.dart
    playlist    lib/screens/playlist_screen.dart
    stremio_tv  lib/screens/stremio_tv/stremio_tv_screen.dart
    debrify_tv  lib/screens/magic_tv_screen.dart
    iptv        lib/widgets/iptv/iptv_results_view.dart lib/screens/browse_screen.dart
"""
import glob
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MANIFEST = os.path.join(REPO, "tool/theme_surface_manifest.txt")

IMPORT_RE = re.compile(r"""^import\s+['"]([^'"]+)['"]""", re.M)
PAINTS_RE = re.compile(r"Color\(|Colors\.|Theme\.of\(|DetailThemeScope")

# The theme layer is the destination, not a surface needing work.
SKIP_PREFIXES = ("lib/theme/",)

# Route boundaries. Everything below is reached by PUSHING a route, so it is a
# different surface and the walk must stop rather than absorb it:
#   * the player tree — permanently outside the app palette (see the plan's
#     hazard 2), and imported by every surface that can start playback;
#   * Classic details — excluded by product decision, and already inheriting the
#     live theme via plain MaterialPageRoute pushes.
ROUTE_BOUNDARIES = (
    "lib/screens/video_player/",
    "lib/screens/video_player_screen.dart",
    "lib/services/video_player_launcher.dart",
    "lib/screens/catalog_item_detail_screen.dart",
    "lib/screens/episodes_screen.dart",
    "lib/widgets/episodes_panel.dart",
)


def phase_one_files():
    """Files phase one already owns, from its own manifest entries."""
    owned = set()
    for line in open(MANIFEST, encoding="utf-8"):
        line = line.strip()
        if not line or line.startswith("#") or line.startswith("p2_"):
            continue
        for pattern in line.split("=", 1)[1].split():
            for path in glob.glob(os.path.join(REPO, pattern)):
                owned.add(os.path.relpath(path, REPO))
    return owned


def resolve(importer, target, stop_at_boundaries):
    if target.startswith(("dart:", "package:flutter/", "package:flutter_")):
        return None
    if target.startswith("package:debrify/"):
        rel = "lib/" + target[len("package:debrify/"):]
    elif target.startswith("package:"):
        return None
    else:
        rel = os.path.normpath(os.path.join(os.path.dirname(importer), target))
    if not rel.endswith(".dart") or rel.startswith(SKIP_PREFIXES):
        return None
    if stop_at_boundaries and rel.startswith(ROUTE_BOUNDARIES):
        return None
    return rel if os.path.isfile(os.path.join(REPO, rel)) else None


def walk(roots, stop_at_boundaries=True):
    seen, painting, queue = set(), set(), list(roots)
    while queue:
        rel = queue.pop()
        if rel in seen:
            continue
        seen.add(rel)
        try:
            src = open(os.path.join(REPO, rel), encoding="utf-8").read()
        except OSError:
            continue
        if PAINTS_RE.search(src):
            painting.add(rel)
        for target in IMPORT_RE.findall(src):
            nxt = resolve(rel, target, stop_at_boundaries)
            if nxt and nxt not in seen:
                queue.append(nxt)
    return painting


def measure(files):
    lines = sites = white_lines = theme_of = 0
    for rel in files:
        src = open(os.path.join(REPO, rel), encoding="utf-8").read()
        lines += src.count("\n")
        sites += len(re.findall(r"Color\(0x|Colors\.[a-zA-Z]+|withValues", src))
        # LINES containing a white, not occurrences: a line with two counts
        # once. Matches how the plan's table is stated.
        white_lines += sum(
            1 for ln in src.splitlines() if re.search(r"Colors\.white[0-9]*", ln)
        )
        theme_of += len(re.findall(r"\bTheme\.of\(", src))
    return len(files), lines, sites, white_lines, theme_of


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    label, roots = sys.argv[1], sys.argv[2:]
    files = walk(roots, stop_at_boundaries=not os.environ.get("RAW"))
    if not os.environ.get("NO_P1"):
        files -= phase_one_files()
    f, lines, sites, whites, theme_of = measure(sorted(files))
    print(f"{label:<14}{f:>4} files {lines:>7} lines {sites:>5} sites "
          f"{whites:>5} white-lines {theme_of:>4} Theme.of")
    if os.environ.get("LIST"):
        for rel in sorted(files):
            print(f"    {rel}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
