#!/usr/bin/env python3
"""Video-player diagnostic identity/multiplicity guard, including infos.

The inventory is frozen from the original, formatted root, strict original,
and the reviewed rename/receiver probe. Maxima combine runs, never sum them.
"""
import argparse
from collections import Counter
import json
from pathlib import Path
import re
import subprocess

from check_verbatim_moves import ROOT, parse, ensure_parser_package
from dart_move_history import git_text, load_manifest, earlier_manifests

SOURCE = 'lib/screens/video_player_screen.dart'
FEATURE = 'lib/features/video_player'
INVENTORY = 'dev/tool/dart_moves/vplayer_p1_analyzer.json'


def entries(log):
    for line in Path(log).read_text().splitlines():
        match = re.match(r'^\s*(error|warning|info) • (.*?) • (.+?):(\d+):(\d+) • (\S+)\s*$', line)
        if match:
            severity, message, path, ln, col, rule = match.groups()
            yield severity, message, path, int(ln), int(col), rule


def enclosing(unit, offset):
    matches = []
    for node in unit['declarations']:
        if node['start'] <= offset < node['end']:
            matches.append((node['name'], node))
        for member in node['members']:
            if member['start'] <= offset < member['end']:
                suffix = '@set' if member.get('isSetter') else ''
                matches.append((node['name'] + '.' + member['name'] + suffix, member))
    return min(matches, key=lambda pair: pair[1]['end'] - pair[1]['start'])[0] if matches else '@directives'


def declaration_mappings(manifest):
    """Later inventories keep the physical-to-original identities of P1 files."""
    origins, type_origins, reverse = {}, {}, {}
    manifests = [*earlier_manifests(manifest), manifest] if manifest else []
    for row in [r for m in manifests for r in m.get('declarations', [])]:
        if row['fate'] != 'moved':
            continue
        target = row.get('target', row['original'])
        origins[row['destination'], target] = row['original']
        if '.' not in row['original'] and ':' not in row['original']:
            type_origins[row['destination'], target] = row['original']
        reverse[target.split('.')[-1]] = row['original'].split('.')[-1]
    return origins, type_origins, reverse


def collect(log, sources, package, manifest=None, aliases=None):
    parsed = parse(sources, package, ownership=True)
    origins, type_origins, reverse = declaration_mappings(manifest)
    observed, errors = Counter(), []
    for severity, message, path, ln, col, rule in entries(log):
        path = (aliases or {}).get(path, path)
        if path not in sources:
            # Scoped logs must not hide a new video_player file absent from the ledger.
            if path.startswith(FEATURE + '/') or path == SOURCE:
                errors.append('unregistered diagnostic source: ' + path)
            continue
        text = sources[path]
        lines = text.splitlines(keepends=True)
        if not 1 <= ln <= len(lines):
            errors.append('invalid diagnostic location: ' + path)
            continue
        utf16 = lines[ln - 1].encode('utf-16-le')
        if not 1 <= col <= len(utf16) // 2 + 1:
            errors.append('invalid diagnostic column: ' + path)
            continue
        offset = sum(map(len, lines[:ln - 1])) + len(utf16[:(col - 1) * 2].decode('utf-16-le'))
        symbol = '@directives' if rule == 'directives_ordering' else enclosing(parsed[path], offset)
        original = origins.get((path, symbol))
        if original is None:
            owner, _, name = symbol.rpartition('.')
            parent = type_origins.get((path, owner))
            if parent:
                original = parent + '.' + reverse.get(name, name)
            elif symbol == '@directives':
                # A new destination's import lint cannot spend another file's
                # allowance. Directives have no moved declaration identity.
                original = '@directives' if path == SOURCE else path + ':@directives'
            elif path == SOURCE:
                original = '.'.join(reverse.get(part, part) for part in symbol.split('.'))
            else:
                errors.append('unregistered diagnostic declaration: ' + path + ':' + symbol)
                continue
        # Identifier spellings may change by a reviewed declaration rename.
        message = re.sub(r'\b[A-Za-z_]\w*\b', lambda m: reverse.get(m[0], m[0]), message)
        observed[severity, rule, original, message] += 1
    return observed, errors


def encoded(counter):
    return [dict(severity=key[0], rule=key[1], symbol=key[2], message=key[3], maximum=count)
            for key, count in sorted(counter.items())]


def compare(observed, inventory):
    allowed = Counter({(r['severity'], r['rule'], r['symbol'], r['message']): r['maximum']
                       for r in inventory['entries']})
    return ['new/increased diagnostic: ' + str((key, count)) for key, count in (observed - allowed).items()]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('analyzer', type=Path)
    parser.add_argument('--parser-package', type=Path, required=True)
    parser.add_argument('--manifest', type=Path, default=Path('dev/tool/dart_moves/vplayer_p1_retained.json'))
    parser.add_argument('--inventory', type=Path, default=Path(INVENTORY))
    parser.add_argument('--probe', type=Path)
    parser.add_argument('--aliases', type=Path)
    parser.add_argument('--at')
    parser.add_argument('--self-test', action='store_true')
    args = parser.parse_args()
    ensure_parser_package(args.parser_package.parent.parent, args.parser_package)
    if args.self_test:
        base = {'entries': encoded(Counter({('info', 'example', 'State.member', 'message'): 1}))}
        assert not compare(Counter({('info', 'example', 'State.member', 'message'): 1}), base)
        for key in [('info', 'example', 'State.member', 'message'),
                    ('info', 'example', 'State.other', 'message'),
                    ('info', 'example', 'State.member', 'changed message')]:
            assert compare(Counter({key: 2}), base)
        print('Analyzer self-tests: infos, multiplicity, declaration and message negatives rejected')
    app = args.probe or ROOT
    manifest = load_manifest(args.manifest, args.at)
    if args.at:
        if args.probe:
            parser.error('--at and --probe cannot mix revision and working-tree inputs')
        paths = subprocess.check_output(['git', '-C', str(ROOT), 'ls-tree', '-r', '--name-only',
                                         args.at, '--', SOURCE, FEATURE], text=True).splitlines()
        sources = {path: git_text(args.at, path) for path in paths if path.endswith('.dart')}
    else:
        sources = {SOURCE: (app / SOURCE).read_text()}
        sources.update({p.relative_to(app).as_posix(): p.read_text() for p in (app / FEATURE).rglob('*.dart')})
    inventory = (json.loads(git_text(args.at, str(args.inventory)))
                 if args.at else json.loads(args.inventory.read_text()))
    observed, errors = collect(args.analyzer, sources, args.parser_package, manifest,
                               json.loads(args.aliases.read_text()) if args.aliases else None)
    errors.extend(compare(observed, inventory))
    if not observed:
        errors.append('no scoped diagnostics parsed (missing/truncated/wrong log)')
    for error in errors:
        print(error)
    print(f'{"FAIL" if errors else "PASS"}: {sum(observed.values())} scoped diagnostics; {len(errors)} additions')
    return bool(errors)


if __name__ == '__main__':
    raise SystemExit(main())
