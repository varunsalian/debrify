#!/usr/bin/env python3
"""Exhaustive, manifest-driven Kotlin PSI move comparison; no handwritten parser."""
import argparse
import bisect
from collections import Counter
import difflib
import fcntl
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

from android_junit_evidence import evidence_root, JBR

ROOT = Path(__file__).resolve().parents[2]
SOURCE = 'android/app/src/main/kotlin/com/debrify/app/tv/AndroidTvTorrentPlayerActivity.kt'
MANIFEST = ROOT / 'dev/tool/kotlin_moves/tvplayer_p1.json'
EVIDENCE_PHASE = 'p1'
PARSE_CACHE = {}


def parse(sources, *, lexer_only=False):
    """Compile offline under a lock, then parse all inputs in one JVM."""
    missing = {key: value for key, value in sources.items() if (value, lexer_only) not in PARSE_CACHE}
    if not missing:
        return {key: PARSE_CACHE[value, lexer_only] for key, value in sources.items()}
    cache = Path(os.environ.get('GRADLE_USER_HOME', str(Path.home() / '.gradle'))) / 'caches/modules-2/files-2.1'
    coordinates = [('org.jetbrains.kotlin', 'kotlin-compiler-embeddable', '2.2.20'),
                   ('org.jetbrains.kotlin', 'kotlin-stdlib', '2.2.20'),
                   ('org.jetbrains.kotlinx', 'kotlinx-coroutines-core-jvm', '1.8.0'),
                   ('org.jetbrains', 'annotations', '13.0')]
    jars = []
    for group, artifact, version in coordinates:
        matches = list((cache / group / artifact / version).glob('*/*.jar'))
        if len(matches) != 1:
            raise ValueError(f'offline PSI artifact unavailable/ambiguous: {artifact}:{version}')
        jars.append(matches[0])
    cp = os.pathsep.join(map(str, jars))
    folder = evidence_root(ROOT) / 'p1/psi'
    folder.mkdir(parents=True, exist_ok=True)
    adapter = ROOT / 'dev/tool/kotlin_psi/KotlinPsi.java'
    digest = hashlib.sha256(adapter.read_bytes() + cp.encode()).hexdigest()
    with (folder / 'build.lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        stamp = folder / 'build.sha256'
        if not stamp.exists() or stamp.read_text() != digest:
            subprocess.run([str(JBR / 'bin/javac'), '-cp', cp, '-d', str(folder), str(adapter)], check=True)
            stamp.write_text(digest)
    with tempfile.TemporaryDirectory(dir=folder) as directory:
        paths = []
        for index, source in enumerate(missing.values()):
            path = Path(directory) / f'input{index}.kt'
            path.write_text(source)
            paths.append(str(path))
        result = subprocess.run([str(JBR / 'bin/java'), '-cp', str(folder) + os.pathsep + cp,
                                 'KotlinPsi', *(['--lexer-only'] if lexer_only else []), *paths], text=True, capture_output=True)
        if result.returncode:
            raise ValueError('Kotlin PSI failed: ' + result.stderr)
        for value, unit in zip(missing.values(), json.loads(result.stdout)):
            PARSE_CACHE[value, lexer_only] = unit
        return {key: PARSE_CACHE[value, lexer_only] for key, value in sources.items()}


def walk(nodes):
    for node in nodes:
        yield node
        yield from walk(node['children'])


def tokens(unit, start=0, end=None):
    result = []
    starts = unit.setdefault('_starts', [t['start'] for t in unit['tokens']])
    left = bisect.bisect_left(starts, start)
    right = len(starts) if end is None else bisect.bisect_left(starts, end)
    for token in unit['tokens'][left:right]:
        if end is not None and token['end'] > end:
            continue
        kind, text = token['kind'], token['text']
        if kind in ('BLOCK_COMMENT', 'DOC_COMMENT', 'EOL_COMMENT'):
            text = '\n'.join(line.strip(' \t') for line in text.split('\n'))
        result.append((kind, text))
    return result


def substitutions(expected, edits, parsed_edits):
    result = list(expected)
    for edit in edits:
        before = tokens(parsed_edits[edit['before']])
        after = tokens(parsed_edits[edit['after']])
        if not before or before == after or edit['count'] < 1:
            raise ValueError('invalid declared substitution')
        found, out, pos = 0, [], 0
        while pos < len(result):
            if result[pos:pos + len(before)] == before:
                out.extend(after)
                pos += len(before)
                found += 1
            else:
                out.append(result[pos])
                pos += 1
        if found != edit['count']:
            raise ValueError(f'substitution occurrence count: expected {edit["count"]}, found {found}')
        result = out
    return result


def members(node):
    starts = set(map(int, node['body_member_starts']))
    return [child for child in node['children'] if child['start'] in starts]


def spans(unit, split):
    """Disjoint whole-subtree spans, leading trivia attached to next child."""
    result, structure = {}, {}

    def visit(nodes, start, end, container):
        previous = start
        structure[container] = [n['id'] for n in nodes]
        for node in nodes:
            if node['id'] in split:
                if 'body_start' not in node:
                    raise ValueError('split container has no class body: ' + node['id'])
                result[node['id'] + ':header'] = (previous, node['body_start'] + 1)
                visit(members(node), node['body_start'] + 1, node['body_end'] - 1, node['id'])
                result[node['id'] + ':close'] = (node['body_end'] - 1, node['end'])
            else:
                result[node['id']] = (previous, node['end'])
            previous = node['end']
        result[container + ':tail'] = (previous, end)

    result[':prefix'] = (0, unit['prefix_end'])
    visit(unit['declarations'], unit['prefix_end'], unit['length'], '')
    intervals = sorted(result.values())
    cursor = 0
    for start, end in intervals:
        if start != cursor or end < start:
            raise ValueError('partition gap/overlap')
        cursor = end
    if cursor != unit['length']:
        raise ValueError('partition incomplete')
    return result, structure


def check(manifest, original, current):
    """Subtree ownership assigns every descendant exactly once, explicitly."""
    errors = []
    all_sources = {'original': original, **current}
    # Substitutions are lexed by the same lexer; snippets need not be valid PSI.
    edit_sources = {edit[key]: edit[key] for row in manifest['declarations']
                    for edit in row.get('substitutions', []) + row.get('patches', []) for key in ('before', 'after')}
    # Wrap fragments in a valid declaration so PSI validates only the wrapper.
    # Use the lexer-only mode for exact fragment tokenization.
    parsed = parse(all_sources)
    edited = lex_fragments(edit_sources) if edit_sources else {}
    base = parsed['original']
    inventory = {n['id']: n for n in walk(base['declarations'])}
    split = manifest.get('split_containers', [])
    if len(split) != len(set(split)):
        errors.append('duplicate split container')
    split = set(split)
    for name in split:
        if name not in inventory:
            errors.append('missing split container: ' + name)
    if errors:
        return errors, len(inventory)
    base_spans, base_order = spans(base, split)
    rows = manifest['declarations']
    added = manifest.get('added', [])
    if added and manifest['phase'] < 3:
        errors.append('added declarations require phase 3')
    targets = Counter((source if row['fate'] != 'moved' else row.get('destination'), row.get('target', row['original']))
                      for row in rows for source in [manifest['source']])
    for (path, name), count in targets.items():
        if count > 1:
            errors.append('duplicate destination ownership: ' + str(path) + ':' + name)
    owners = Counter()
    for name in split:
        node = inventory[name]
        owners[name] += 1
        body_ids = {d['id'] for child in members(node) for d in walk([child])}
        for descendant in walk(node['children']):
            if descendant['id'] not in body_ids:
                owners[descendant['id']] += 1
    for row in rows:
        name = row['original']
        if name not in inventory:
            errors.append('unknown original declaration: ' + name)
            continue
        if name not in base_spans:
            errors.append('ownership must cover a whole disjoint subtree: ' + name)
        if row.get('subtree') is not True:
            errors.append('explicit subtree ownership required: ' + name)
        for descendant in walk([inventory[name]]):
            owners[descendant['id']] += 1
        if row['fate'] == 'patched' and manifest['phase'] == 1:
            errors.append('patched forbidden in phase 1: ' + name)
        elif row['fate'] not in ('retained', 'moved', 'patched'):
            errors.append('unknown fate: ' + name)
    for name in inventory:
        if owners[name] == 0:
            errors.append('unassigned declaration: ' + name)
        elif owners[name] > 1:
            errors.append('duplicate ownership: ' + name)
    if errors:
        return errors, len(inventory)

    if manifest['phase'] >= 4:
        from kotlin_move_partition import check_initializer_timing
        check_initializer_timing(manifest, inventory, original, errors)
    if manifest['phase'] >= 11:
        from check_kotlin_overloads import receiver_inventory
        moved = {r['original']: r for r in rows if r['fate'] == 'moved'}
        try:
            receiver_inventory(manifest, original, base, inventory, moved)
            for name, row in moved.items():
                node = inventory[name]
                before = [s for s in base['all_this_sites']
                          if node['start'] <= s['start'] < node['end'] and 'lambda_receiver' in s]
                if not before:
                    continue
                if row['destination'] not in parsed:
                    continue  # The exhaustive source-set check reports this below.
                destination = parsed[row['destination']]
                target = next(n for n in walk(destination['declarations']) if n['id'] == row['target'])
                after = [s for s in destination['all_this_sites']
                         if target['start'] <= s['start'] < target['end'] and 'lambda_receiver' in s]
                keys = ('text', 'lambda_callee', 'lambda_receiver')
                if [[s[key] for key in keys] for s in before] != [[s[key] for key in keys] for s in after]:
                    errors.append('receiver-lambda expression substituted or binding changed: ' + name)
        except (ValueError, StopIteration) as error:
            errors.append(str(error))

    source = manifest['source']
    if set(current) != {source, *manifest['destinations']}:
        errors.append('unexpected/missing destination source set')
        return errors, len(inventory)
    actual_spans, actual_orders = {}, {}
    for path in current:
        destination_split = set(manifest['destinations'].get(path, {}).get('split_containers', []))
        actual_spans[path], actual_orders[path] = spans(parsed[path], split if path == source else destination_split)
    expected_ids = {path: set() for path in current}
    expected_ids[source].update(k for k in base_spans if k.startswith(':') or k.endswith((':header', ':close', ':tail')))

    def compare_span(label, expected, actual):
        if expected != actual:
            diff = list(difflib.unified_diff([repr(t) for t in expected], [repr(t) for t in actual], n=2))
            errors.append('token mismatch: ' + label + '\n' + '\n'.join(diff[:18]))

    for key in expected_ids[source]:
        if key not in actual_spans[source]:
            errors.append('missing container: ' + key)
        else:
            compare_span(key, tokens(base, *base_spans[key]), tokens(parsed[source], *actual_spans[source][key]))
    for path, spec in manifest['destinations'].items():
        if 'pinned_spans' in spec:
            from kotlin_move_partition import check_pinned_destination
            check_pinned_destination(path, spec, parsed[path], actual_spans[path], actual_orders[path],
                                     expected_ids[path], compare_span, errors)
            continue
        compare_span('destination imports/package/file annotations: ' + path,
                     tokens(parse({'prefix': spec['prefix']})['prefix']), tokens(parsed[path], *actual_spans[path][':prefix']))
        expected_ids[path].update((':prefix', ':tail'))
        # A moved file's trailing trivia is reviewed explicitly too.
        compare_span('destination tail: ' + path, lex_fragments({'tail': spec.get('tail', '\n')})['tail']['pairs'],
                     tokens(parsed[path], *actual_spans[path][':tail']))
    for row in rows:
        name, fate = row['original'], row['fate']
        path = source if fate in ('retained', 'patched') else row['destination']
        target = row.get('target', name)
        if target in expected_ids[path]:
            errors.append('duplicate destination span ownership: ' + path + ':' + target)
        expected_ids[path].add(target)
        if fate == 'moved' and name in actual_spans[source]:
            errors.append('surviving-after-move: ' + name)
        if target not in actual_spans[path]:
            errors.append('missing declaration: ' + target)
            continue
        edits = row.get('substitutions', []) + (row.get('patches', []) if fate == 'patched' else [])
        if fate == 'patched' and (not row.get('reason') or not row.get('test') or not row.get('patches')):
            errors.append('patched requires exact patches, reason and named test: ' + name)
        expected = substitutions(tokens(base, *base_spans[name]), edits, edited)
        compare_span(name, expected, tokens(parsed[path], *actual_spans[path][target]))
    if added:
        from kotlin_move_partition import check_added
        check_added(manifest, inventory, base_order, actual_spans[source], parsed[source],
                    expected_ids[source], compare_span, errors)
    for path, actual in actual_spans.items():
        for name in actual.keys() - expected_ids[path]:
            errors.append('unexpected new declaration: ' + path + ':' + name)
    for container, ordered in base_order.items():
        expected = []
        for name in ordered:
            expected.extend(row['target'] for row in added if row.get('slot') == name)
            if name in split or any(r['original'] == name and r['fate'] in ('retained', 'patched') for r in rows):
                expected.append(name)
        if actual_orders[source].get(container) != expected:
            errors.append('retained declaration order changed: ' + container)
    for path in manifest['destinations']:
        if 'pinned_spans' in manifest['destinations'][path]:
            continue
        ordered = sorted((r for r in rows if r['fate'] == 'moved' and r['destination'] == path), key=lambda r: inventory[r['original']]['start'])
        if actual_orders[path][''] != [r.get('target', r['original']) for r in ordered]:
            errors.append('destination declaration order changed: ' + path)
    return errors, len(inventory)


def lex_fragments(sources):
    parsed = parse({key: value for key, value in sources.items()}, lexer_only=True)
    for unit in parsed.values():
        unit['pairs'] = tokens(unit)
    return parsed


def retained_manifest(source, original, base='39c630303'):
    unit = parse({'original': original})['original']
    return dict(base=base, phase=1, source=source, split_containers=[], destinations={},
                declarations=[dict(original=n['id'], fate='retained', subtree=True) for n in unit['declarations']])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', type=Path, default=MANIFEST)
    parser.add_argument('--self-compare-original', action='store_true')
    parser.add_argument('--self-test', action='store_true')
    parser.add_argument('--at', help='Compare the manifest against this historical revision')
    parser.add_argument('--check-earlier', action='store_true', help='Check approved earlier destinations in the current tree')
    args = parser.parse_args()
    if args.self_test:
        import test_kotlin_moves
        global EVIDENCE_PHASE
        EVIDENCE_PHASE = 'p' + str(json.loads(args.manifest.read_text())['phase'])
        return test_kotlin_moves.run(args.manifest)
    manifest = json.loads(args.manifest.read_text())
    if args.check_earlier:
        from kotlin_move_partition import check_earlier
        errors = check_earlier(manifest, ROOT)
        for error in errors:
            print(error)
        print(f'{"FAIL" if errors else "PASS"}: earlier destinations; {len(errors)} differences')
        return bool(errors)
    original = subprocess.check_output(['git', '-C', str(ROOT), 'show', manifest['base'] + ':' + manifest['source']]).decode()
    if args.self_compare_original:
        manifest = retained_manifest(manifest['source'], original, manifest['base'])
        current = {manifest['source']: original}
    else:
        current = {p: (subprocess.check_output(['git', '-C', str(ROOT), 'show', args.at + ':' + p]).decode()
                       if args.at else (ROOT / p).read_text())
                   for p in [manifest['source'], *manifest['destinations']]}
    errors, count = check(manifest, original, current)
    if manifest.get('earlier_destinations') and not args.self_compare_original and not args.at:
        from kotlin_move_partition import check_earlier
        errors.extend(check_earlier(manifest, ROOT))
    for error in errors:
        print(error)
    print(f'{"FAIL" if errors else "PASS"}: {count} declarations classified; {len(errors)} differences')
    return bool(errors)


if __name__ == '__main__':
    sys.exit(main())
