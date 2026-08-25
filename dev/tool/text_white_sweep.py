#!/usr/bin/env python3
"""Text-brightness step-2 sweep helper.

Finds opaque `Colors.white` sites in the in-scope files and classifies each:

  AUTO   - `color: Colors.white,` (or `)` ) on its own line, inside a
           TextStyle, no risk flags in context -> safe to delete the line so
           the Text inherits onSurface via the ambient DefaultTextStyle.
  REVIEW - risk flags nearby (focus/selected conditionals, colored fills,
           buttons, gradients, RichText/TextSpan, shadows) -> human decides.
  SKIP   - not a text color (Icon color, Container/BoxDecoration color,
           borders, foregroundColor/backgroundColor, thumb/track...).

Modes:
  inventory [area]  - print counts per file
  review <file>     - print REVIEW/ SKIP sites with context for a file
  apply <file>      - delete the AUTO lines in-place, print what was done
"""
import os
import re
import sys

EXCLUDE_PATH_PARTS = (
    'deprecated',
    'video_player',            # player: excluded by decision
    'stremio_tv',              # TV tuner/player surfaces
    'magic_tv',                # Debrify TV (player-adjacent)
    'iptv',                    # IPTV: excluded by decision
    'player',                  # playlist_player_service etc. keep out
    'initial_setup_flow',      # onboarding: deferred
    'home_theme', 'see_all_theme', 'cloud_theme',  # authored kits
    'screens/settings/',       # done in step 1 (except stremio_addons below)
    'settings_screen',         # done in step 1 pass
)
# settings-area file that is really a content surface; swept despite the dir.
FORCE_INCLUDE = ('stremio_addons_page',)

OPAQUE = re.compile(r'Colors\.white\b(?!\d)(\.\w+)?')
TRANSLUCENT_SUFFIX = {'.withValues', '.withOpacity', '.withAlpha'}

RISK = re.compile(
    r'focused|_focused|hasFocus|selected|isActive|foregroundColor|'
    r'backgroundColor|BoxDecoration|LinearGradient|RadialGradient|gradient|'
    r'Button|badge|Badge|Chip|shadow|Shadow|RichText|TextSpan|'
    r'CircleAvatar|Slider|Switch|thumb|track|indicator|Border|border|'
    r'Icon\(|Container\(|DecoratedBox|Divider|ProgressIndicator|Checkbox|'
    r'Radio|activeColor|checkColor|fillColor|iconColor|AnimatedContainer'
)
STYLE_CTX = re.compile(r'TextStyle\(|style:|labelStyle|hintStyle|titleTextStyle')
NONTEXT_LINE = re.compile(
    r'^\s*(?:color:\s*Colors\.white[,)]?\s*)$'
)

def in_scope(path):
    if not path.endswith('.dart'):
        return False
    if any(k in path for k in FORCE_INCLUDE):
        return True
    return not any(k in path for k in EXCLUDE_PATH_PARTS)

def sites(path):
    lines = open(path, encoding='utf-8', errors='ignore').read().split('\n')
    out = []
    for i, line in enumerate(lines):
        for m in OPAQUE.finditer(line):
            if m.group(1) in TRANSLUCENT_SUFFIX:
                continue
            before = '\n'.join(lines[max(0, i - 6):i + 1])
            after = '\n'.join(lines[i + 1:i + 3])
            ctx = before + '\n' + after
            own_line = NONTEXT_LINE.match(line)
            in_style = bool(STYLE_CTX.search(before))
            risky = bool(RISK.search(ctx))
            if own_line and in_style and not risky:
                cls = 'AUTO'
            elif in_style or 'Text(' in before:
                cls = 'REVIEW'
            else:
                cls = 'SKIP'
            out.append((i + 1, cls, line.rstrip()))
    return out

def walk():
    for root, _, fs in os.walk('lib'):
        for f in fs:
            p = os.path.join(root, f)
            if in_scope(p):
                yield p

def inventory():
    tot = {'AUTO': 0, 'REVIEW': 0, 'SKIP': 0}
    rows = []
    for p in walk():
        s = sites(p)
        if not s:
            continue
        c = {'AUTO': 0, 'REVIEW': 0, 'SKIP': 0}
        for _, cls, _ in s:
            c[cls] += 1
            tot[cls] += 1
        rows.append((sum(c.values()), c, p))
    rows.sort(key=lambda r: r[0], reverse=True)
    for n, c, p in rows:
        print(f"{n:4d}  A:{c['AUTO']:<3d} R:{c['REVIEW']:<3d} S:{c['SKIP']:<3d}  {p}")
    print(f"\nTOTAL auto:{tot['AUTO']} review:{tot['REVIEW']} skip:{tot['SKIP']}")

def review(path):
    lines = open(path, encoding='utf-8', errors='ignore').read().split('\n')
    for ln, cls, _ in sites(path):
        if cls == 'AUTO':
            continue
        print(f"===== {cls} {path}:{ln}")
        for j in range(max(0, ln - 7), min(len(lines), ln + 2)):
            mark = '>' if j == ln - 1 else ' '
            print(f"{mark}{j + 1:5d}  {lines[j]}")

def apply(path):
    src = open(path, encoding='utf-8', errors='ignore').read()
    lines = src.split('\n')
    doomed = [ln for ln, cls, _ in sites(path) if cls == 'AUTO']
    if not doomed:
        print(f"{path}: nothing AUTO")
        return
    kept = [l for j, l in enumerate(lines, 1) if j not in doomed]
    open(path, 'w', encoding='utf-8').write('\n'.join(kept))
    print(f"{path}: deleted {len(doomed)} lines: {doomed}")

def strip(path, line_nos):
    """Remove `color: Colors.white` from the given 1-based lines: delete the
    line when the property is alone on it, else excise it inline."""
    lines = open(path, encoding='utf-8', errors='ignore').read().split('\n')
    out = []
    done = []
    for i, l in enumerate(lines, 1):
        if i in line_nos:
            if re.match(r'^\s*color:\s*Colors\.white,?\s*$', l):
                done.append(i)
                continue  # drop the whole line
            # A color-only style argument: drop the whole argument line.
            if re.match(
                r'^\s*style:\s*(const\s+)?TextStyle\(color:\s*Colors\.white\),?\s*$',
                l,
            ):
                done.append(i)
                continue
            new = re.sub(r'color:\s*Colors\.white,\s*', '', l)
            new = re.sub(r',\s*color:\s*Colors\.white', '', new)
            new = re.sub(
                r'(TextStyle\()color:\s*Colors\.white\)', r'\1)', new)
            if new != l:
                done.append(i)
                # `TextStyle()` left behind when color was the only prop is
                # harmless, but tidy the common single-prop shape.
                new = new.replace('style: const TextStyle(),', '')
                new = new.replace('style: TextStyle(),', '')
                l = new
        out.append(l)
    open(path, 'w', encoding='utf-8').write('\n'.join(out))
    print(f'{path}: stripped {done}')

def plan(path):
    """Propose an action for each REVIEW site using enclosure heuristics.

    SWEEP  - text inside an AlertDialog / bottom sheet / Material screen body
    KEEP   - bare `=> Center(` dialog overlays (no Material ancestor: deleting
             the color yields the debug fallback style), focus borders,
             button foregrounds, conditional focus/selected signals
    ASK    - anything the heuristics can't place
    """
    lines = open(path, encoding='utf-8', errors='ignore').read().split('\n')
    for ln, cls, line in sites(path):
        if cls != 'REVIEW':
            continue
        back = lines[max(0, ln - 25):ln]
        near = '\n'.join(lines[max(0, ln - 8):ln + 1])
        # Nearest route-builder enclosure wins.
        encl = None
        for b in reversed(back):
            if 'AlertDialog(' in b:
                encl = 'dialog'
                break
            if re.search(r'=>\s*(const\s+)?Center\(', b):
                encl = 'bare-center'
                break
        if 'foregroundColor' in line or 'BorderSide' in line:
            act = 'KEEP (button/border)'
        elif re.search(r'(focused|_focused|hasFocus|selected)\b', near) and '?' in near:
            act = 'KEEP (state signal)'
        elif encl == 'bare-center':
            act = 'KEEP (no Material ancestor)'
        elif encl == 'dialog':
            act = 'SWEEP'
        elif re.search(r'(TextField|TvTextField)\(', '\n'.join(back[-10:])):
            act = 'SWEEP (input)'
        else:
            act = 'ASK'
        print(f'{act:28s} {path}:{ln}  {line.strip()[:70]}')

if __name__ == '__main__':
    cmd = sys.argv[1] if len(sys.argv) > 1 else 'inventory'
    if cmd == 'inventory':
        inventory()
    elif cmd == 'review':
        review(sys.argv[2])
    elif cmd == 'apply':
        for f in sys.argv[2:]:
            apply(f)
    elif cmd == 'strip':
        strip(sys.argv[2], {int(x) for x in sys.argv[3:]})
    elif cmd == 'plan':
        for f in sys.argv[2:]:
            plan(f)
