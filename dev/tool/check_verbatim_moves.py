#!/usr/bin/env python3
"""Compare every manifest leaf with its one owner, including in-place leaves.

Dart's analyzer supplies declaration boundaries and scanner tokens: literals,
annotations, defaults, initializers, comments and statement order are retained.
Only whitespace outside literals, registered symbol renames and the qualifier
of that symbol's registered owner are normalized. Split classes are never
compared whole. Forwarders are independently checked, including signatures and
argument order. Tool-only analyzer 14.3.0 is resolved in git's evidence directory
(or --parser-package); no application dependency is added. Not a CI check:
its default original is git show 204b1011:lib/services/video_player_launcher.dart.

  python3 dev/tool/check_verbatim_moves.py [--self-test]
  python3 dev/tool/check_verbatim_moves.py --baseline REV --source PATH \
      --manifest PATH --feature DIR
"""
from collections import Counter
import argparse
import csv
import difflib
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = 'lib/services/video_player_launcher.dart'
FEATURE = 'lib/features/player_launch'


def parser_package():
    from suite_evidence import evidence_dir
    package = evidence_dir() / 'verbatim-parser'
    config = package / '.dart_tool/package_config.json'
    if not config.exists():
        package.mkdir(parents=True, exist_ok=True)
        (package / 'pubspec.yaml').write_text(
            "name: refactor_verbatim_parser\nenvironment:\n"
            "  sdk: '>=3.12.0 <4.0.0'\ndependencies:\n  analyzer: 14.3.0\n")
        (package / 'pubspec.lock').write_text(
            (ROOT / 'dev/tool/verbatim_parser.pubspec.lock').read_text())
        subprocess.run(['dart', 'pub', 'get', '--enforce-lockfile', '--directory', str(package)],
                       check=True, stdout=subprocess.DEVNULL)
    return config


def parse(sources, package=None):
    package = package or parser_package()
    adapter = ROOT / 'dev/tool/verbatim_ast.dart.txt'
    kernel = package.parent / 'verbatim_ast.dill'
    if not kernel.exists() or kernel.stat().st_mtime < adapter.stat().st_mtime:
        subprocess.run(['dart', 'compile', 'kernel', '--packages=' + str(package),
                        '-o', str(kernel), str(adapter)], check=True,
                       stdout=subprocess.DEVNULL)
    result = subprocess.run(
        ['dart', str(kernel)],
        input=json.dumps(sources), text=True, capture_output=True, check=True)
    parsed = json.loads(result.stdout)
    def complete(node):
        code = [t for t in node['tokens'] if not t['comment']]
        if not code or code[-1]['text'] != node['endTokenText']:
            raise ValueError('Incomplete token parse: ' + node['name'])
        for member in node['members']: complete(member)
    for unit in parsed.values():
        for declaration in unit['declarations']: complete(declaration)
    return parsed


def read_manifest(path):
    with Path(path).open() as file:
        rows = list(csv.DictReader(file, delimiter='\t'))
    if not rows or len({r['original_name'] for r in rows}) != len(rows):
        raise ValueError('Empty manifest or duplicate original names')
    destinations = [(r['destination_file'], r['destination_class'], r['new_name']) for r in rows]
    if len(set(destinations)) != len(destinations):
        raise ValueError('Duplicate destination ownership')
    return rows


def split_names(rows):
    return {r['original_name'].split('.')[0] for r in rows if '.' in r['original_name']}


def original_leaves(declarations, splits):
    leaves = {}
    for d in declarations:
        items = [(d['name'] + '.' + m['name'], m) for m in d['members']] if d['name'] in splits else [(d['name'], d)]
        for name, node in items:
            if name in leaves:
                raise ValueError('Duplicate declaration: ' + name)
            leaves[name] = node
    return leaves


def renames(rows):
    mapping = {r['original_name'].split('.')[-1]: r['new_name'] for r in rows
               if r['original_name'].split('.')[-1] != r['new_name']}
    for row in rows:
        for old, new in re.findall(r'rename:(\w+)=(\w+)', row['expected_difference']):
            mapping[old] = new
    return mapping


def canonical(node, rows, *, static_added=False, normalize_qualifiers=True):
    mapping = renames(rows)
    owner_for = {r['new_name']: r['destination_class'] for r in rows if r['destination_class']}
    origin_owner_for = {r['new_name']: r['original_name'].split('.')[0]
                        for r in rows if '.' in r['original_name']}
    tokens = node['tokens']
    result = []
    i = 0
    while i < len(tokens):
        token = tokens[i]
        value = token['text']
        if token['comment']:
            # Doc links ([name], [Owner.name]) follow the same registered
            # renames and owner qualifiers as code; any other text is exact.
            def link(match):
                parts = match.group(1).split('.')
                name = mapping.get(parts[-1], parts[-1])
                owner = parts[0] if len(parts) == 2 else None
                if owner and (owner == owner_for.get(name)
                              or (owner == origin_owner_for.get(name) and name in owner_for)):
                    return '[' + name + ']'
                return '[' + '.'.join(parts[:-1] + [name]) + ']'
            value = re.sub(r'\[(\w+(?:\.\w+)?)\]', link, value)
            result.append(re.sub(r'\s+', '', value)); i += 1; continue
        value = mapping.get(value, value)
        if (normalize_qualifiers and i + 2 < len(tokens)
                and tokens[i + 1]['text'] == '.'
                and (i == 0 or tokens[i - 1]['text'] not in ('.', '?.'))):
            target = mapping.get(tokens[i + 2]['text'], tokens[i + 2]['text'])
            if value == owner_for.get(target) or (value == origin_owner_for.get(target) and target in owner_for):
                i += 2; continue
        if static_added and value == 'static':
            static_added = False; i += 1; continue
        result.append(value)
        i += 1
    return result


def apply_exact_exceptions(original, rows, package=None):
    """Patch only named original snippets, once each, to the expected text.

    Applying these to the baseline and then comparing complete declarations
    means neither a broad ignore nor an additional 'warning fix' can pass.
    """
    patches = {
        'VideoPlayerLauncher._handleProgressUpdate': (
            'progressUrl ??\n              (resumeId != null ? _resolvedStreamCache[resumeId] : null)',
            'progressUrl ??\n              _resolvedStreamCache[resumeId]'),
        '_AndroidTvPlaylistResolver': (
            '${target != null}, entry: ${target?.entry.title}',
            '${true}, entry: ${target.entry.title}'),
    }
    changed = {}
    for row in rows:
        key = row['original_name']
        note = row['expected_difference']
        if note.startswith('warning fix'):
            if key not in patches:
                raise ValueError('Unknown exact warning exception: ' + key)
            before, after = patches[key]
            text = original[key]['text']
            if text.count(before) != 1:
                raise ValueError('Warning exception baseline differs: ' + key)
            text = text.replace(before, after)
            owner = original[key]['owner']
            changed[key] = f'class {owner} {{\n{text}\n}}' if owner else text
        if note.startswith('annotation removal:'):
            text = original[key]['text']
            if text.count('@visibleForTesting') != 1:
                raise ValueError('Annotation exception baseline differs: ' + key)
            text = text.replace('@visibleForTesting', '')
            changed[key] = 'class ' + original[key]['owner'] + ' {\n' + text + '\n}'
    if not changed:
        return {}
    parsed = parse(changed, package)
    return {key: value['declarations'][0]['members'][0] if original[key]['owner']
            else value['declarations'][0] for key, value in parsed.items()}


def forwarding_source(node, row):
    prefix = node['text'][:node['bodyOffset'] - node['start']]
    args = [f'{name}: {name}' if named else name for name, named in
            zip(node['parameterNames'], node['namedParameters'])]
    return prefix + '=> ' + row['destination_class'] + '.' + row['new_name'] + '(' + ', '.join(args) + ');'


def forwarding_tokens(node, rows):
    # The facade's expression body is new wiring. A formatter-added trailing
    # comma in that call does not change its arguments. Keep the complete
    # original signature/default tokens and exact dispatch owner untouched.
    tokens = canonical(node, rows, normalize_qualifiers=False)
    if tokens[-3:] == [',', ')', ';']:
        del tokens[-3]
    return tokens


def line_comments(text, rows):
    """Non-doc `//` comments: whole-line ones, plus trailing ones whose code
    part has balanced quotes (so `//` inside a string never counts)."""
    mapping = renames(rows)
    owner_for = {r['new_name']: r['destination_class'] for r in rows if r['destination_class']}
    origin_owner_for = {r['new_name']: r['original_name'].split('.')[0]
                        for r in rows if '.' in r['original_name']}
    def link(match):
        parts = match.group(1).split('.')
        name = mapping.get(parts[-1], parts[-1])
        owner = parts[0] if len(parts) == 2 else None
        if owner and (owner == owner_for.get(name)
                      or (owner == origin_owner_for.get(name) and name in owner_for)):
            return '[' + name + ']'
        return '[' + '.'.join(parts[:-1] + [name]) + ']'
    found = Counter()
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith('///'):
            continue
        if stripped.startswith('//'):
            comment = stripped
        else:
            match = re.match(r'^(.*\S)\s+(//(?!/).*)$', line)
            if not match or match.group(1).count("'") % 2 or match.group(1).count('"') % 2:
                continue
            comment = match.group(2)
        if re.fullmatch(r'//\s*dart format (off|on)\b.*', comment):
            continue
        found[re.sub(r'\s+', '', re.sub(r'\[(\w+(?:\.\w+)?)\]', link, comment))] += 1
    return found


def missing_line_comments(original_source, sources, rows):
    """Every original line comment must survive somewhere in the destinations."""
    before = line_comments(original_source, rows)
    after = Counter()
    for text in sources.values():
        after += line_comments(text, rows)
    return [f'Line comment lost ({count}x): {comment}'
            for comment, count in sorted((before - after).items())]


def check(original_source, sources, rows, source_path=SOURCE, package=None):
    errors = []
    parsed = parse({'<original>': original_source, **sources}, package)
    splits = split_names(rows)
    original = original_leaves(parsed['<original>']['declarations'], splits)
    known = {r['original_name'] for r in rows}
    if not original or set(original) != known:
        return ['Original parse/manifest mismatch: missing=' + str(sorted(known - set(original)))
                + ' extra=' + str(sorted(set(original) - known))]
    errors.extend(missing_line_comments(original_source, sources, rows))
    expected_patches = apply_exact_exceptions(original, rows, package)
    headers = {d['name']: d for d in parsed['<original>']['declarations'] if d['name'] in splits}
    def header(node):
        copy = dict(node)
        opening = next(i for i, t in enumerate(node['tokens']) if t['text'] == '{')
        copy['tokens'] = node['tokens'][:opening]
        return canonical(copy, rows)
    for path, unit in parsed.items():
        if path == '<original>': continue
        for declaration in unit['declarations']:
            if declaration['name'] in headers and header(declaration) != header(headers[declaration['name']]):
                errors.append('Split class header changed: ' + declaration['name'])
    current = original_leaves(parsed[source_path]['declarations'], splits)
    destination_nodes = {}
    expected_dest = {(r['destination_file'], r['destination_class'], r['new_name']) for r in rows}
    for path, unit in parsed.items():
        if path in ('<original>', source_path): continue
        for d in unit['declarations']:
            whole = (path, '', d['name'])
            if whole in expected_dest:
                items = [(whole, d)]
            else:
                wrapper = (path, d['name'])
                if not any((p, c) == wrapper for p, c, _ in expected_dest):
                    errors.append('Unknown destination declaration: ' + str(whole))
                items = [((path, d['name'], m['name']), m) for m in d['members']]
                if d['name'] == 'VideoPlayerLaunchArgsWidget':
                    header = d['text'].split('{', 1)[0]
                    if re.sub(r'\s+', '', header) != 'extensionVideoPlayerLaunchArgsWidgetonVideoPlayerLaunchArgs':
                        errors.append('toWidget extension target/header changed')
            for key, node in items:
                if key not in expected_dest: errors.append('Unknown destination leaf: ' + str(key))
                if key in destination_nodes: errors.append('Duplicate destination declaration: ' + str(key))
                destination_nodes[key] = node
    forwarders = {}
    for row in rows:
        key = row['original_name']; baseline = original[key]
        destination = destination_nodes.get((row['destination_file'], row['destination_class'], row['new_name']))
        in_place = current.pop(key, None)
        if destination is None:
            if in_place is None: errors.append('Missing declaration: ' + key); continue
            actual, expected, added = in_place, baseline, False
        else:
            actual = destination
            expected = expected_patches.get(key, baseline)
            added = row['expected_difference'].startswith(('state owner:', 'static owner:'))
            if added:
                # Only the declaration modifier may be new; initializer/body
                # tokens still compare in full, and duplicate fields fail above.
                if not any(t['text'] == 'static' for t in actual['tokens']):
                    errors.append('Missing static single owner: ' + key)
            if in_place is not None:
                if '.' in key and not key.split('.')[-1].startswith('_') and baseline['parameters'] is not None:
                    forwarders[key] = 'class ' + key.split('.')[0] + ' {\n' + forwarding_source(baseline, row) + '\n}'
                else:
                    errors.append('Duplicate original/destination declaration: ' + key)
        before = canonical(expected, rows)
        after = canonical(actual, rows, static_added=added)
        if before != after:
            diff = '\n'.join(list(difflib.unified_diff(before, after, fromfile=key, tofile=row['destination_file']))[:60])
            errors.append('Non-verbatim declaration: ' + key + '\n' + diff)
    if current:
        errors.append('Unknown original declarations: ' + str(sorted(current)))
    if forwarders:
        expected = parse(forwarders, package)
        current_all = original_leaves(parsed[source_path]['declarations'], splits)
        for key, unit in expected.items():
            if forwarding_tokens(unit['declarations'][0]['members'][0], rows) != forwarding_tokens(current_all[key], rows):
                errors.append('Forwarder signature/default/arguments changed: ' + key)
    return errors


def self_test(package=None):
    fixtures = ROOT / 'dev/tool/verbatim_fixtures'
    rows = read_manifest(fixtures / 'manifest.tsv')
    original = (fixtures / 'original.dart.txt').read_text()
    cases = json.loads((fixtures / 'cases.json').read_text())
    for name, case in cases.items():
        sources = {SOURCE: case['facade'], 'owner.dart': case['owner']}
        case_rows = case.get('manifest') or [dict(r, expected_difference=case.get('exception', r['expected_difference'])) for r in rows]
        errors = check(case.get('original', original), sources, case_rows, package=package)
        if bool(errors) == case['passes']:
            raise AssertionError(f'Self-test {name}: {errors}')
        print(f'Self-test {name}: {"PASS" if not errors else "rejected"}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline')
    parser.add_argument('--source')
    parser.add_argument('--manifest', default='dev/tool/vpl_manifest.tsv')
    parser.add_argument('--feature')
    parser.add_argument('--parser-package', type=Path)
    parser.add_argument('--self-test', action='store_true')
    parser.add_argument('--partition', action='store_true',
                        help='Check Settings whole-list-element partitions and join order')
    parser.add_argument('--context-guard', action='store_true',
                        help='Check Settings first context acquisition against mounted guards')
    args = parser.parse_args()
    package = args.parser_package or parser_package()
    settings = Path(args.manifest).name == 'settings_manifest.tsv'
    # Each manifest has one original and one destination; default them so a
    # bare `--manifest dev/tool/settings_manifest.tsv` can't silently compare
    # the wrong files. Settings always runs both partition and context checks.
    defaults = (('17db33f2', 'lib/screens/settings_screen.dart', 'lib/features/settings')
                if settings else ('204b1011', SOURCE, FEATURE))
    args.baseline = args.baseline or defaults[0]
    args.source = args.source or defaults[1]
    args.feature = args.feature or defaults[2]
    if settings:
        args.partition = args.context_guard = True
    if args.self_test:
        self_test(package)
        if settings:
            from check_settings_moves import self_test as settings_self_test
            settings_self_test(package)
    if (args.partition or args.context_guard) and not settings:
        parser.error('partition/context-guard modes require settings_manifest.tsv')
    rows = read_manifest(ROOT / args.manifest)
    original = subprocess.run(['git', 'show', f'{args.baseline}:{args.source}'],
                              cwd=ROOT, text=True, capture_output=True, check=True).stdout
    sources = {args.source: (ROOT / args.source).read_text()}
    sources.update({p.relative_to(ROOT).as_posix(): p.read_text()
                    for p in (ROOT / args.feature).rglob('*.dart')})
    if settings:
        from check_settings_moves import check as settings_check
        errors = settings_check(original, sources, rows, args.source, package,
                                args.partition, args.context_guard)
    else:
        errors = check(original, sources, rows, args.source, package)
    if errors:
        print('\n'.join(errors)); return 1
    print(f'Verbatim moves: {len(rows)} leaves and all present facade forwarders passed.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
