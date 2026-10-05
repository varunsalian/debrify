#!/usr/bin/env python3
"""Local verbatim declaration/reset check against 072407c3 (not a CI check).

Only mapped storage qualifiers/renames and whitespace outside literals are
normalized. Signatures, defaults, receivers, literal bytes, initializers,
modifiers and annotations must remain identical. --self-test exercises negative
fixtures without modifying production files.
"""
from collections import Counter, defaultdict
import sys
from storage_dart import (LEGACY, RESET, ROOT, code_tokens, members, normalized,
                          original, read_map, replacements, retired_members, source_paths,
                          tokens, type_declaration)


def canonical(source, rows):
    ts = [t for t in tokens(source) if t.kind != 'comment']
    edits, covered = [], set()
    expressions = {r['target']: r['member'] for r in rows if r['ref_kind'] == 'static'}
    expressions.update({'StorageService.'+r['member']: r['member']
                        for r in rows if r['ref_kind'] == 'static'})
    renamed = {r['target'].split('.')[-1]: r['member'] for r in rows
               if r['shared'] == 'yes'}
    for i in range(len(ts)-2):
        a, dot, b = ts[i:i+3]
        if all(t.kind == 'code' for t in (a, dot, b)) and dot.text == '.':
            match = expressions.get(a.text+'.'+b.text)
            if match:
                edits.append((a.start, b.end, match))
                covered.update((i, i+1, i+2))
    for i, t in enumerate(ts):
        if t.kind == 'code' and i not in covered and t.text in renamed:
            if i and ts[i-1].text == '.':
                continue
            edits.append((t.start, t.end, renamed[t.text]))
    return normalized(replacements(source, edits))


def reset_statements(declaration):
    ts = tokens(declaration)
    opening = next(t for t in ts if t.kind == 'code' and t.text == '{')
    ending = next(t for t in reversed(ts) if t.kind == 'code' and t.text == '}')
    body = declaration[opening.end:ending.start]
    statements, start = [], 0
    for t in code_tokens(body):
        if t.text == ';':
            statements.append(body[start:t.end])
            start = t.end
    assert not body[start:].strip()
    return statements


def check():
    rows = read_map()
    before = {m.name: m for m in members(original())}
    found, resets = defaultdict(list), {}
    errors = []
    for p in source_paths():
        path, source = p.relative_to(ROOT).as_posix(), p.read_text()
        if path in (RESET, *[r['file'] for r in rows if r['ref_kind'] == 'type']):
            continue
        class_name = 'StorageService' if path == LEGACY else next(
            r['target'].split('.')[0] for r in rows if r['file'] == path)
        for m in members(source, class_name):
            if m.name == 'resetProfileCaches':
                resets[path] = m
                continue
            matched = False
            for r in rows:
                if r['ref_kind'] != 'static' or r['kind'] == 'reset_entry':
                    continue
                if ((path == LEGACY and m.name == r['member']) or
                    (path == r['file'] and m.name == r['target'].split('.')[-1])):
                    found[r['member']].append((path, m))
                    matched = True
            if not matched:
                errors.append(f'{path}: unmapped static declaration {m.name}')
    retired = retired_members()
    for r in rows:
        name = r['member']
        if r['kind'] == 'reset_entry':
            continue
        if name in retired:
            # Deleted dead code: it must stay gone, not reappear unmapped.
            if found[name]:
                errors.append(f'{name}: retired member is declared again')
            continue
        if r['ref_kind'] == 'type':
            owners = [p for p in ((ROOT / LEGACY), ROOT / r['file'])
                      if p.exists() and any(t.text == name for t in code_tokens(p.read_text())
                                           if t.kind == 'code') and
                      __import__('re').search(r'(class|enum)\s+'+name+r'\b', p.read_text())]
            if len(owners) != 1:
                errors.append(f'{name}: {len(owners)} declarations')
            elif canonical(type_declaration(original(), name), rows) != canonical(
                    type_declaration(owners[0].read_text(), name), rows):
                errors.append(f'{name}: declaration changed')
        else:
            declarations = found[name]
            if len(declarations) != 1:
                errors.append(f'{name}: {len(declarations)} declarations')
            elif canonical(before[name].declaration, rows) != canonical(declarations[0][1].declaration, rows):
                errors.append(f'{name}: declaration changed in {declarations[0][0]}')
    baseline = [canonical(s, rows) for s in reset_statements(before['resetProfileCaches'].declaration)]
    observed = []
    for path, m in resets.items():
        partition = [canonical(s, rows) for s in reset_statements(m.declaration)]
        observed += partition
        positions = [baseline.index(s) for s in partition if s in baseline]
        if positions != sorted(positions):
            errors.append(f'{path}: reset statement order changed')
        for statement in partition:
            # The first identifier owns this reset; no cross-class assignment.
            owner = next((r['file'] for r in rows if r['member'] == statement[0][1]), None)
            if path != LEGACY and owner != path:
                errors.append(f'{path}: reset belongs to {owner}')
    freeze = lambda s: tuple(s)
    if Counter(map(freeze, baseline)) != Counter(map(freeze, observed)):
        errors.append('Reset partition lost, duplicated or changed a statement')
    assert not errors, '\n'.join(errors)
    checked = sum(1 for r in rows if r['kind'] != 'reset_entry' and r['member'] not in retired)
    print(f'Storage bodies: {checked:,} verbatim declarations ({len(retired)} retired); reset partition exact and ordered.')


def self_test():
    rows = read_map()
    sample = "static Future<String> f({bool forRemoteTransfer = false}) async { return prefs.getString('inline  key') ?? ''; }"
    for changed in (sample.replace('= false', '= true'),
                    sample.replace('inline  key', 'inline  changed'),
                    sample.replace('prefs.getString', 'other.getString'),
                    sample.replace('inline  key', 'inline key')):
        assert canonical(sample, rows) != canonical(changed, rows)
    assert canonical(sample, rows) == canonical(sample.replace('async {', 'async\n {'), rows)
    assert canonical('_getPlaybackStateMap()', rows) == canonical('PlaybackStateStore.getPlaybackStateMap()', rows)
    assert canonical('_getFinishedMovieIds()', rows) == canonical('MovieProgressStorage.getFinishedMovieIdsInternal()', rows)
    assert canonical('_getFinishedMovieIds()', rows) != canonical('MovieProgressStorage.getFinishedMovieIds()', rows)
    print('Body checker fixtures: four changed-declaration negatives rejected; authorized moves accepted.')


if __name__ == '__main__':
    if '--self-test' in sys.argv:
        self_test()
    check()
