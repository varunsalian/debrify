#!/usr/bin/env python3
"""Rank the hardcoded light-ink literals that keep the two light themes off.

`d3d78fb` withheld Broadsheet and Concrete because *"screens still carrying
hardcoded light text literals never go through the token layer, so they stay
light-on-light"*, and it was explicit that **green tests are not the signal for
re-enabling** — the contrast audit passes for both, because the bug lives in
literals that bypass the layer it measures.

So this is deliberately NOT a test. A lexical scan cannot be a completeness
check: ink also arrives through locals, `copyWith`, `IconTheme`,
`DefaultTextStyle`, widget defaults and helpers, while a literal in a `color:`
argument is very often a legitimate fill. An allow-list built on that would
become an unreviewable suppression file and a clean run would mean nothing.

What it CAN honestly be is a worklist: turn "1,152 white literals somewhere"
into a ranked, reviewed queue, so the remaining work is a known quantity
instead of a wall. Nothing in `test/` depends on it.

    python3 tool/light_ink_inventory.py            # ranked summary
    python3 tool/light_ink_inventory.py --sites    # every candidate site
    python3 tool/light_ink_inventory.py --file lib/screens/foo.dart
"""
import argparse
import os
import re
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Roles where a light literal is INK — the thing that goes light-on-light.
INK_ROLE = re.compile(
    r'\b(color|foregroundColor|labelColor|unselectedLabelColor|hintColor|'
    r'iconColor|prefixIconColor|suffixIconColor|selectionColor|cursorColor|'
    r'displayColor|bodyColor|dividerColor|indicatorColor)\s*:')

# Light literals: Colors.white and friends, plus near-white hex.
LIGHT = re.compile(
    r'Colors\.white(?:\d{2})?\b'
    r'|Colors\.white\.withValues'
    r'|Color\(0x[0-9A-Fa-f]{2}(?:F[0-9A-Fa-f]|E[0-9A-Fa-f])'
    r'[0-9A-Fa-f]{4}\)')

# Contexts where a light literal is CORRECT and must not be "fixed": it sits on
# artwork, on black glass, or on a filled accent, none of which follow the page.
OK_CONTEXT = re.compile(
    r'onGlass|over artwork|glass|scrim|shadow|Colors\.black|barrier|'
    r'BlendMode|gradient|Shader|blur|veil|inkOn|onFill|onAccent|'
    r'0x[0-9A-Fa-f]{2}0[0-9A-Fa-f]{5}', re.IGNORECASE)

# Surfaces that never follow the app palette.
EXCLUDE = ('lib/screens/deprecated/', 'lib/screens/video_player',
           'lib/widgets/deprecated/', 'lib/widgets/initial_setup_flow.dart')

# The screens a user meets in the first five minutes. Fixing these is what
# would make re-listing the light themes arguable.
PRIMARY = (
    'lib/screens/search_screen.dart',
    'lib/screens/settings',
    'lib/screens/cloud_screen.dart',
    'lib/screens/debrid_downloads_screen.dart',
    'lib/screens/downloads_screen.dart',
    'lib/screens/catalog_item_detail_screen.dart',
    'lib/screens/merged_series_detail_screen.dart',
    'lib/screens/trakt_calendar_screen.dart',
    'lib/screens/see_all',
    'lib/screens/addons',
    'lib/widgets/home',
    'lib/widgets/see_all',
    'lib/widgets/cloud',
)


def dart_files():
    out = subprocess.run(
        ['bash', '-lc', "find lib -name '*.dart' | sort"],
        capture_output=True, text=True, cwd=REPO).stdout.split()
    return [f for f in out if not f.startswith(EXCLUDE)]


def scan(path):
    """-> [(lineno, text)] candidate ink sites."""
    hits = []
    with open(os.path.join(REPO, path)) as fh:
        lines = fh.read().split('\n')
    for i, line in enumerate(lines, 1):
        stripped = line.strip()
        if stripped.startswith('//') or stripped.startswith('///'):
            continue
        if not INK_ROLE.search(line) or not LIGHT.search(line):
            continue
        # Three lines of context, because the reason a white is correct is
        # usually stated just above it.
        ctx = '\n'.join(lines[max(0, i - 4):i + 1])
        if OK_CONTEXT.search(ctx):
            continue
        hits.append((i, stripped))
    return hits


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--sites', action='store_true', help='list every site')
    ap.add_argument('--file', help='one file only')
    args = ap.parse_args()

    files = [args.file] if args.file else dart_files()
    results = {}
    for f in files:
        hits = scan(f)
        if hits:
            results[f] = hits

    total = sum(len(v) for v in results.values())
    primary = {f: v for f, v in results.items() if f.startswith(PRIMARY)}
    primary_total = sum(len(v) for v in primary.values())

    print(f'{total} candidate ink sites in {len(results)} files')
    print(f'{primary_total} of them on PRIMARY surfaces '
          f'({len(primary)} files) — this is the number that gates re-listing '
          f'Broadsheet and Concrete\n')

    print('── primary surfaces, worst first ──')
    for f, v in sorted(primary.items(), key=lambda kv: -len(kv[1]))[:25]:
        print(f'{len(v):5d}  {f}')
    rest = {f: v for f, v in results.items() if f not in primary}
    if rest:
        print('\n── everything else, worst first ──')
        for f, v in sorted(rest.items(), key=lambda kv: -len(kv[1]))[:15]:
            print(f'{len(v):5d}  {f}')

    if args.sites:
        print('\n── sites ──')
        for f, v in sorted(results.items()):
            for lineno, text in v:
                print(f'{f}:{lineno}: {text[:110]}')
    return 0


sys.exit(main())
