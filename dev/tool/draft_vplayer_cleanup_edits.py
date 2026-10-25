#!/usr/bin/env python3
"""Phase 21b cleanup generator: declared edits, the source change and layer 2.

One stage per run, in order (C1, C2, C3). Each stage:
  1. appends its declared edits to dev/tool/dart_moves/vplayer_p21b_cleanup.json
     (layer 1, proved by vplayer_cleanup_proof.py);
  2. applies exactly those edits to the source text (run `dart format` on the
     printed files afterwards for C2);
  3. after formatting, `--sync-manifest` derives the P21 manifest additions
     (layer 2) from the declared edits: facade directive list and directive
     fates (C1), counted token patches on facade/moved rows, earlier_patches.

Inputs: C1/C2 read the 21a-merge analyzer log; C3 reads a reviewed comment table
(file, line at the 21a merge, exact before text, after texts).
"""
import argparse
import copy
import json
import re
from pathlib import Path

from check_verbatim_moves import ROOT, parse, ensure_parser_package
from check_settings_moves import apply_explicit_token_edits
from dart_move_partition import partition
from dart_move_history import git_text
import vplayer_cleanup_proof as proof

TEST = 'dev/tool/vplayer_cleanup_proof.py'
REASON = {'C1': 'Phase 21b C1: unused facade import removed (analyzer unused_import/unused_shown_name).',
          'C2': 'Phase 21b C2: braces added at a curly_braces_in_flow_control_structures site.',
          'C3': 'Phase 21b C3: comment names the current owner of a moved member.'}


def load(root=ROOT):
    path = root / proof.EDITS
    if path.exists():
        return json.loads(path.read_text())
    return dict(schema=1, base=proof.BASE, description=(
        'Phase 21b declared cleanup edits (C1 imports, C2 braces, C3 comments). '
        'Proved by dev/tool/vplayer_cleanup_proof.py; mirrored in vplayer_p21.json.'), edits=[])


def diagnostics(log, rule):
    for line in Path(log).read_text().splitlines():
        m = re.match(r'^\s*(?:info|warning) • (.*) • (\S+):(\d+):(\d+) • ' + rule + r'\s*$', line)
        if m:
            yield m.group(1), m.group(2), int(m.group(3)), int(m.group(4))


def stage_c1(log):
    edits = []
    for message, path, line, col in diagnostics(log, 'unused_import'):
        if path == proof.FACADE:
            edits.append(dict(commit='C1', kind='remove_directive', file=path,
                              uri=re.match(r"Unused import: '([^']+)'", message).group(1)))
    for message, path, line, col in diagnostics(log, 'unused_shown_name'):
        if path == proof.FACADE:
            text = git_text(proof.BASE, path).splitlines()
            start = max(i for i in range(line) if text[i].startswith('import '))
            edits.append(dict(commit='C1', kind='remove_shown_name', file=path, uri=text[start].split("'")[1],
                              name=re.match(r'The name (\w+) is shown', message).group(1)))
    return edits


def stage_c2(log, package):
    sites = [(p, l, c) for _, p, l, c in diagnostics(log, 'curly_braces_in_flow_control_structures')
             if p == proof.FACADE or p.startswith(proof.FEATURE + '/')]
    texts = {p: git_text(proof.BASE, p) for p, _, _ in sites}
    parsed = parse(texts, package, ownership=True)
    edits = []
    for path, line, col in sites:
        unit = proof.Unit(texts[path], parsed[path])
        offset = unit.starts[line - 1] + col - 1
        key = unit.span_of(offset)
        found = proof.brace_sites(unit, key)
        hits = [n for n, s in enumerate(found) if unit.tokens[s['body']]['offset'] == offset]
        assert len(hits) == 1, (path, line)
        site = found[hits[0]]
        head = [unit.tokens[i]['text'] for i in range(site['head'], site['body'] + 1)
                if not unit.tokens[i]['comment']][:8]
        if any((path, key, hits[0]) == (e['file'], e['declaration'], e['ordinal']) for e in proof.EXCLUDED_BRACES):
            continue
        edits.append(dict(commit='C2', kind='insert_braces', file=path, declaration=key,
                          ordinal=hits[0], head=head))
    return edits


def stage_c3(table, package):
    rows = json.loads(Path(table).read_text())
    texts = {r['file']: git_text(proof.BASE, r['file']) for r in rows}
    parsed = parse(texts, package, ownership=True)
    edits = []
    for row in rows:
        unit = proof.Unit(texts[row['file']], parsed[row['file']])
        hits = [i for i, t in enumerate(unit.tokens) if t['comment'] and t['text'] == row['before']
                and proof.line_at(unit.starts, t['offset']) == row['line'] - 1]
        assert len(hits) == 1, row
        key = unit.span_of(unit.tokens[hits[0]]['offset'])
        comments = [i for i in unit.span_tokens(key) if unit.tokens[i]['comment']]
        edits.append(dict(commit='C3', kind='replace_comment', file=row['file'], declaration=key,
                          ordinal=comments.index(hits[0]), before=row['before'], after=row['after']))
    return edits


def apply_text(path, text, edits, package):
    """Rewrite the source by scanner offsets; formatting is left to dart format."""
    unit = proof.Unit(text, parse({path: text}, package, ownership=True)[path])
    changes = []
    for edit in edits:
        if edit['kind'] == 'remove_directive':
            node, = [d for d, src in zip(unit.directives, unit.directive_text)
                     if src.startswith('import ') and src.split("'")[1] == edit['uri']]
            start = text.rfind('\n', 0, node['start']) + 1
            end = text.index('\n', node['end']) + 1
            assert text[start:node['start']].strip() == '' and text[node['end']:end].strip() == ''
            changes.append((start, end, ''))
        elif edit['kind'] == 'remove_shown_name':
            node, = [d for d, src in zip(unit.directives, unit.directive_text)
                     if src.startswith('import ') and src.split("'")[1] == edit['uri']]
            segment = text[node['start']:node['end']]
            match = re.search(r'\b' + edit['name'] + r',\s*', segment) or re.search(r',\s*' + edit['name'] + r'\b', segment)
            changes.append((node['start'] + match.start(), node['start'] + match.end(), ''))
        elif edit['kind'] == 'insert_braces':
            site = proof.brace_sites(unit, edit['declaration'])[edit['ordinal']]
            end = site['end']
            line = proof.line_at(unit.starts, unit.tokens[end]['offset'])
            while (end + 1 < len(unit.tokens) and unit.tokens[end + 1]['comment']
                   and proof.line_at(unit.starts, unit.tokens[end + 1]['offset']) == line):
                end += 1
            stop = unit.tokens[end]['offset'] + len(unit.tokens[end]['text'])
            body = unit.tokens[site['body']]['offset']
            changes.append((stop, stop, '\n}'))
            changes.append((body, body, '{\n'))
        elif edit['kind'] == 'replace_comment':
            comments = [i for i in unit.span_tokens(edit['declaration']) if unit.tokens[i]['comment']]
            token = unit.tokens[comments[edit['ordinal']]]
            assert token['text'] == edit['before']
            start, end = token['offset'], token['offset'] + len(token['text'])
            if edit['after']:
                indent = text[text.rindex('\n', 0, start) + 1:start]
                lead = indent if indent.strip() == '' else ' ' * (len(indent) - len(indent.lstrip()))
                changes.append((start, end, ('\n' + lead).join(edit['after'])))
            else:
                line_start = text.rindex('\n', 0, start) + 1
                if text[line_start:start].strip() == '':
                    changes.append((line_start, text.index('\n', end) + 1, ''))
                else:
                    changes.append((start - (start - len(text[:start].rstrip())), end, ''))
    for start, end, value in sorted(changes, key=lambda c: (c[0], c[1]), reverse=True):
        text = text[:start] + value + text[end:]
    return text


def window_patch(values, points, after_of, others):
    """Smallest left-context window whose occurrences are exactly `points`."""
    for k in range(1, 60):
        windows = {tuple(values[p - k:p]) for p in points}
        if len(windows) != 1 or any(p - k < 0 for p in points):
            break
        window = list(windows.pop())
        hits = {q for q in range(k, len(values) + 1) if values[q - k:q] == window}
        if hits == set(points) and not hits & others:
            return dict(before=window, after=after_of(window), count=len(points))
    return None


def sync_manifest(package, root=ROOT):
    """Rebuild the P21 manifest's 21b additions from the declared edits."""
    data = load(root)
    edits = data['edits']
    manifest_path = root / proof.MANIFEST
    base_manifest = json.loads(git_text(proof.BASE, proof.MANIFEST, root))
    manifest = copy.deepcopy(base_manifest)
    source = manifest['source']
    paths = proof.file_set(root, proof.BASE)
    base = {p: git_text(proof.BASE, p, root) for p in paths}
    current = {p: (root / p).read_text() for p in paths}
    errors, projected = proof.layer_one(edits, base, current, package)
    if errors:
        raise SystemExit('layer 1 must pass before the manifest is synced:\n' + '\n'.join(errors))
    original = git_text(manifest['base'], source, root)
    parsed = parse({'base:' + p: base[p] for p in base} | {'<original>': original}, package, ownership=True)
    original_spans, _, _ = partition(parsed['<original>'], manifest['split_containers'])
    # C1: directive list, fates and renumbered scaffolding.
    current_unit = parse({source: current[source]}, package, ownership=True)[source]
    manifest['facade_directives'] = current_unit['directives']
    old_list = base_manifest['facade_directives']
    removed = {e['uri'] for e in edits if e['kind'] == 'remove_directive'}
    shown = [e for e in edits if e['kind'] == 'remove_shown_name']
    index, renumber = 0, {}
    for n, text in enumerate(old_list):
        uri = text.split("'")[1]
        if text.startswith('import ') and uri in removed:
            continue
        renumber[n] = index
        index += 1
    assert index == len(manifest['facade_directives'])
    for row in manifest['declarations']:
        key = row['original']
        if not key.startswith('@directive:'):
            continue
        n = int(key.split(':')[1])
        assert old_list[n] == base_manifest['facade_directives'][n]
        if n not in renumber:
            row.clear()
            row.update(original=key, fate='removed', reason=REASON['C1'], test=TEST)
            continue
        if renumber[n] != n:
            row['target'] = '@directive:' + str(renumber[n])
        names = [e['name'] for e in shown if e['uri'] == old_list[n].split("'")[1]]
        if names:
            row.update(fate='patched', reason=REASON['C1'], test=TEST, patches=[
                dict(before=[name, ','], after=[], count=1) for name in names])
    manifest['facade_orders']['@directives'] = ['@directive:' + str(i) for i in range(index)]
    scaffold = manifest['scaffolding'][source]
    manifest['scaffolding'][source] = {
        ('@directive:' + str(renumber[int(k.split(':')[1])]) if k.startswith('@directive:') else k): v
        for k, v in scaffold.items()}
    # C2/C3: counted patches per manifest span.
    rows = {r.get('target', r['original']) if r['fate'] == 'moved' else r['original']: r
            for r in manifest['declarations']}
    earlier = {}
    for path in paths:
        if path == proof.EXTRA:
            continue
        unit, expected = projected[path]
        values = [t['text'] for t in unit.tokens]
        if values == expected:
            continue
        own_edits = [e for e in edits if e['file'] == path and e['kind'] in ('insert_braces', 'replace_comment')]
        if not own_edits:
            continue
        if path == source or path in manifest['destinations']:
            splits = (manifest['split_containers'] if path == source
                      else manifest['destinations'][path].get('split_containers', []))
            spans, _, _ = partition(parsed['base:' + path], splits)
            groups = {}
            for edit in own_edits:
                offset = edit_offset(unit, edit)
                key = next(k for k, v in spans.items() if v['start'] <= offset < v['end'])
                groups.setdefault(key, []).append(edit)
            for key, group in groups.items():
                row = rows[key]
                span_unit_tokens = [i for i, t in enumerate(unit.tokens)
                                    if spans[key]['start'] <= t['offset'] < spans[key]['end']]
                span_values = [values[i] for i in span_unit_tokens]
                # Only this span's edits: the prefix and suffix stay unchanged.
                whole = proof.apply(unit, group)
                lo, hi = span_unit_tokens[0], span_unit_tokens[-1] + 1
                assert whole[:lo] == values[:lo] and whole[len(whole) - (len(values) - hi):] == values[hi:]
                target_values = whole[lo:len(whole) - (len(values) - hi)]
                origin = None
                if row['fate'] == 'moved' or path == source:
                    node = original_spans[row['original']]
                    commas = set(node['formatCommas'])
                    origin = [t['text'] for t in node['tokens'] if t['offset'] not in commas]
                patches = derive(span_values, target_values, origin)
                if path == source:
                    if row['fate'] == 'retained':
                        row.update(fate='patched', reason=REASON[group[0]['commit']], test=TEST, patches=[])
                    row['patches'] = row.get('patches', []) + patches
                else:
                    row.setdefault('reason', REASON[group[0]['commit']])
                    row.setdefault('test', TEST)
                    row['patches'] = row.get('patches', []) + patches
                    if row['reason'] != REASON[group[0]['commit']]:
                        row['reason'] = 'Phase 21b C2/C3 cleanup: braces and/or comments (see vplayer_p21b_cleanup.json).'
        else:
            earlier[path] = dict(reason='Phase 21b ' + '/'.join(sorted({e['commit'] for e in own_edits}))
                                 + ' declared cleanup (braces and/or comments); see vplayer_p21b_cleanup.json.',
                                 review='vplayer_cleanup_proof.py layer 1 + cross-check; Phase 21b review',
                                 patches=derive(values, expected, None))
    if earlier:
        manifest['earlier_patches'] = earlier
    manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')
    return manifest


def edit_offset(unit, edit):
    if edit['kind'] == 'insert_braces':
        return unit.tokens[proof.brace_sites(unit, edit['declaration'])[edit['ordinal']]['body']]['offset']
    comments = [i for i in unit.span_tokens(edit['declaration']) if unit.tokens[i]['comment']]
    return unit.tokens[comments[edit['ordinal']]]['offset']


def derive(values, expected, origin):
    """Counted token patches: values -> expected, applied in order.

    Each change gets the smallest window (left and/or right context) that
    occurs exactly once in the progressively edited tokens and contains no
    token inserted by an earlier patch. For a projected row (a facade or moved
    declaration) the window must also occur exactly once in the original body
    and must not overlap another patch's original window, because the
    projection matches every patch against the original tokens at once.
    """
    import difflib
    ops = [op for op in difflib.SequenceMatcher(a=values, b=expected, autojunk=False).get_opcodes()
           if op[0] != 'equal']
    patches, work, fresh, used, shift = [], list(values), set(), set(), 0
    for tag, i1, i2, j1, j2 in ops:
        a, b = i1 + shift, i2 + shift
        inserted = expected[j1:j2]
        chosen = None
        for size in range(0, 60):
            for k in range(0, size + 1):
                m = size - k
                lo, hi = a - k, b + m
                if lo < 0 or hi > len(work) or set(range(lo, hi)) & fresh:
                    continue
                before = work[lo:hi]
                after = work[lo:a] + inserted + work[b:hi]
                # The projection renders tokens on one line: a line comment may
                # only be followed by further comments.
                if any(t.startswith('//') and not all(u.startswith('//') for u in seq[i + 1:])
                       for seq in (before, after) for i, t in enumerate(seq)):
                    continue
                if not before or sum(work[q:q + len(before)] == before for q in range(len(work))) != 1:
                    continue
                if origin is not None:
                    hits = [q for q in range(len(origin)) if origin[q:q + len(before)] == before]
                    if len(hits) != 1 or set(range(hits[0], hits[0] + len(before))) & used:
                        continue
                    used.update(range(hits[0], hits[0] + len(before)))
                chosen = (lo, hi, dict(before=before, after=work[lo:a] + inserted + work[b:hi], count=1))
                break
            if chosen:
                break
        if not chosen:
            raise ValueError('no unique window for a declared change')
        lo, hi, patch = chosen
        patches.append(patch)
        work = apply_explicit_token_edits(work, [patch])
        delta = len(patch['after']) - len(patch['before'])
        fresh = {q + delta if q >= hi else q for q in fresh}
        fresh.update(range(a, a + len(inserted)))
        shift += (j2 - j1) - (i2 - i1)
    assert work == expected
    return patches


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--parser-package', type=Path, required=True)
    parser.add_argument('--stage', choices=['C1', 'C2', 'C3'])
    parser.add_argument('--analyzer', type=Path)
    parser.add_argument('--comments', type=Path)
    parser.add_argument('--sync-manifest', action='store_true')
    args = parser.parse_args()
    ensure_parser_package(args.parser_package.parent.parent, args.parser_package)
    if args.stage:
        data = load()
        if any(e['commit'] == args.stage for e in data['edits']):
            raise SystemExit('stage already declared: ' + args.stage)
        new = (stage_c1(args.analyzer) if args.stage == 'C1' else stage_c2(args.analyzer, args.parser_package)
               if args.stage == 'C2' else stage_c3(args.comments, args.parser_package))
        data['edits'] += new
        (ROOT / proof.EDITS).write_text(json.dumps(data, indent=1, ensure_ascii=False) + '\n')
        for path in sorted({e['file'] for e in new}):
            text = (ROOT / path).read_text()
            (ROOT / path).write_text(apply_text(path, text, [e for e in new if e['file'] == path],
                                                args.parser_package))
            print(path)
    if args.sync_manifest:
        sync_manifest(args.parser_package)
        print('synced', proof.MANIFEST)


if __name__ == '__main__':
    raise SystemExit(main())
