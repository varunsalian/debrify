#!/usr/bin/env python3
"""Phase 21b cleanup proof (layer 1) and its cross-check against the P21 manifest.

Layer 1 compares the whole C1-C3 diff token by token. Its base is the 21a merge
and its "current" side is the post-C3 commit (HEAD below), both read through
git, never the working tree; its file set is the facade, every
lib/features/video_player/** file and exactly one non-feature comment target.
The outside-the-set rule covers `git diff BASE HEAD -- lib` only. The live
feature files and facade are covered by the P21 current move check
(check_dart_moves.py) and the end-state guards, so later unrelated lib/
commits do not affect this proof (review P1-1). The non-feature comment
target is intentionally covered by no video-player guard after C3 (re-review
P3-D). HEAD must stay reachable: do not rebase, reword or squash C1-C3
(re-review P3-E). `--head REV` runs the proof against another head (negatives on
scratch commits). The declared edits are:

  remove_directive   (file, uri)                     C1: an unused import;
  remove_shown_name  (file, uri, name)               C1: one name of a show list;
  insert_braces      (file, declaration, ordinal)    C2: `{`/`}` around one body;
  replace_comment    (file, declaration, ordinal,    C3: one comment token
                      before, after[])                   replaced by 0..n comments.

Everything else must be token-identical, comments included. Formatter commas
(optional trailing commas) are excluded, as in every move check. A declaration
is a partition span (leading trivia belongs to the next declaration) with every
class split into members.

Layer 2 is the P21 manifest itself (check_dart_moves.py). In normal mode the
cross-check projects every span both ways (layer-1 edits; the manifest's
21b-added patches, earlier_patches and directive list, both read at HEAD) and requires the same
(file, declaration, ordinal, before, after) record set, apart from the
non-feature comment target, which only layer 1 covers.
"""
import argparse
import copy
import difflib
import json
from pathlib import Path
import subprocess

from check_verbatim_moves import ROOT, parse, ensure_parser_package
from check_settings_moves import apply_explicit_token_edits
from dart_move_partition import partition
from dart_move_history import git_text, load_manifest

BASE = 'b72ff16f8'
# The post-C3 commit: the proof's pinned "current" side (review P1-1).
HEAD = '218a5806a'
EDITS = 'dev/tool/dart_moves/vplayer_p21b_cleanup.json'
MANIFEST = 'dev/tool/dart_moves/vplayer_p21.json'
FACADE = 'lib/screens/video_player_screen.dart'
FEATURE = 'lib/features/video_player'
EXTRA = 'lib/screens/video_player/services/network_tuning.dart'
STARTUP = FEATURE + '/presentation/legacy_video_player/vp_player_startup.dart'
# Braces here would make the exact 623-line startup exception 624 (review P2-1).
EXCLUDED_BRACES = [dict(file=STARTUP, declaration='VpPlayerStartup.initializePlayer', ordinal=3,
                        head=['if', '(', '_host', '.', 'engineFlagOn', ')', 'unawaited'])]
KINDS = {'remove_directive', 'remove_shown_name', 'insert_braces', 'replace_comment'}
HEADS = {'if', 'for', 'while'}
OPEN, CLOSE = {'(': ')', '[': ']', '{': '}'}, {')', ']', '}'}


def lines_of(text):
    starts = [0]
    for i, ch in enumerate(text):
        if ch == '\n':
            starts.append(i + 1)
    return starts


def line_at(starts, offset):
    lo, hi = 0, len(starts)
    while hi - lo > 1:
        mid = (lo + hi) // 2
        lo, hi = (mid, hi) if starts[mid] <= offset else (lo, mid)
    return lo


class Unit:
    """Scanner tokens (formatter commas dropped) and partition spans."""

    def __init__(self, text, parsed):
        self.text = parsed_text = text
        commas = set(parsed['unitFormatCommas'])
        self.tokens = [t for t in parsed['unitTokens'] if t['offset'] not in commas]
        splits = [d['name'] for d in parsed['declarations'] if d.get('bodyOpen') is not None]
        spans, _, _ = partition(parsed, splits)
        self.spans = sorted(((k, v['start'], v['end']) for k, v in spans.items()), key=lambda s: s[1])
        self.directives = parsed['directiveNodes']
        self.directive_text = parsed['directives']
        self.starts = lines_of(parsed_text)

    def span_of(self, offset):
        for key, start, end in self.spans:
            if start <= offset < end:
                return key
        raise ValueError('offset outside every span')

    def span_tokens(self, key):
        (start, end), = [(s, e) for k, s, e in self.spans if k == key] or [(None, None)]
        if start is None:
            raise ValueError('unknown declaration: ' + key)
        return [i for i, t in enumerate(self.tokens) if start <= t['offset'] < end]

    def code(self, indices):
        return [i for i in indices if not self.tokens[i]['comment']]


def brace_sites(unit, key):
    """Unbraced statement bodies of if/else/for/while in one span, in order.

    A candidate whose body meets a closing bracket, or a comma, before its `;`
    at depth 0 is a collection element, not a statement, and is skipped. A body
    that is itself a flow-control statement is rejected rather than guessed.
    """
    code = unit.code(unit.span_tokens(key))
    text = [unit.tokens[i]['text'] for i in code]
    sites = []
    for n, value in enumerate(text):
        if value in HEADS and n + 1 < len(text) and text[n + 1] == '(':
            depth, j = 0, n + 1
            while True:
                depth += text[j] in OPEN
                depth -= text[j] in CLOSE
                if depth == 0:
                    break
                j += 1
            body = j + 1
        elif value == 'else':
            body = n + 1
        else:
            continue
        if body >= len(text) or text[body] in ('{', ';', 'if'):
            continue
        if text[body] in ('for', 'while', 'do', 'try', 'switch'):
            raise ValueError('unsupported nested flow-control body: ' + key)
        depth, j = 0, body
        while j < len(text):
            if text[j] in OPEN:
                depth += 1
            elif text[j] in CLOSE:
                depth -= 1
                if depth < 0:
                    break
            elif depth == 0 and text[j] in (';', ','):
                break
            j += 1
        if j >= len(text) or text[j] != ';' or depth != 0:
            continue
        sites.append(dict(head=code[n], body=code[body], end=code[j]))
    return sites


def apply(unit, edits):
    """Return the expected token texts after the declared edits, or raise."""
    inserts, deletes, replaces = {}, set(), {}
    for edit in edits:
        kind = edit['kind']
        if kind == 'remove_directive':
            hits = [d for d, src in zip(unit.directives, unit.directive_text)
                    if src.startswith('import ') and src.split("'")[1] == edit['uri']]
            if not hits and any(src.startswith('export ') and src.split("'")[1] == edit['uri']
                                for src in unit.directive_text):
                raise ValueError('export removal: ' + edit['uri'])
            if len(hits) != 1:
                raise ValueError('removed import not found exactly once: ' + edit['uri'])
            span = [i for i, t in enumerate(unit.tokens) if hits[0]['start'] <= t['offset'] < hits[0]['end']]
            if any(unit.tokens[i]['comment'] for i in span):
                raise ValueError('removed import contains a comment: ' + edit['uri'])
            deletes.update(span)
        elif kind == 'remove_shown_name':
            hits = [d for d, src in zip(unit.directives, unit.directive_text)
                    if src.startswith('import ') and src.split("'")[1] == edit['uri']]
            if len(hits) != 1:
                raise ValueError('show-list import not found exactly once: ' + edit['uri'])
            span = [i for i, t in enumerate(unit.tokens) if hits[0]['start'] <= t['offset'] < hits[0]['end']]
            values = [unit.tokens[i]['text'] for i in span]
            if 'show' not in values:
                raise ValueError('no show list: ' + edit['uri'])
            names = [k for k in range(values.index('show') + 1, len(values)) if values[k] == edit['name']]
            if len(names) != 1:
                raise ValueError('shown name not found exactly once: ' + edit['name'])
            k = names[0]
            comma = k + 1 if values[k + 1] == ',' else k - 1
            if values[comma] != ',':
                raise ValueError('last shown name cannot be removed: ' + edit['name'])
            deletes.update({span[k], span[comma]})
        elif kind == 'insert_braces':
            for excluded in EXCLUDED_BRACES:
                if (edit['file'], edit['declaration'], edit['ordinal']) == (
                        excluded['file'], excluded['declaration'], excluded['ordinal']):
                    raise ValueError('excluded startup brace site declared: ' + edit['declaration'])
            sites = brace_sites(unit, edit['declaration'])
            if not 0 <= edit['ordinal'] < len(sites):
                raise ValueError('declared brace site does not exist: ' + edit['declaration'])
            site = sites[edit['ordinal']]
            if 'head' in edit and [unit.tokens[i]['text'] for i in range(site['head'], site['body'] + 1)
                                   if not unit.tokens[i]['comment']][:len(edit['head'])] != edit['head']:
                raise ValueError('declared brace site no longer matches: ' + edit['declaration'])
            end = site['end']
            line = line_at(unit.starts, unit.tokens[end]['offset'])
            while (end + 1 < len(unit.tokens) and unit.tokens[end + 1]['comment']
                   and line_at(unit.starts, unit.tokens[end + 1]['offset']) == line):
                end += 1  # a trailing same-line comment stays inside the block
            inserts.setdefault(site['body'], []).append('{')
            inserts.setdefault(end + 1, []).insert(0, '}')
        elif kind == 'replace_comment':
            comments = [i for i in unit.span_tokens(edit['declaration']) if unit.tokens[i]['comment']]
            if not 0 <= edit['ordinal'] < len(comments):
                raise ValueError('declared comment does not exist: ' + edit['declaration'])
            index = comments[edit['ordinal']]
            if unit.tokens[index]['text'] != edit['before']:
                raise ValueError('declared comment no longer matches: ' + edit['declaration'])
            for value in edit['after']:
                single_line = value.startswith('//') and '\n' not in value
                block = value.startswith('/*') and value.endswith('*/') and '*/' not in value[2:-2]
                if not (single_line or block):
                    raise ValueError('comment replacement is not a single comment: ' + repr(value))
            replaces[index] = list(edit['after'])
        else:
            raise ValueError('unknown edit kind: ' + kind)
    result = []
    for i, token in enumerate(unit.tokens + [None]):
        result.extend(inserts.get(i, []))
        if token is None or i in deletes:
            continue
        result.extend(replaces.get(i, [token['text']]))
    return result


def file_set(root, revision=None):
    if revision:
        listed = subprocess.check_output(['git', '-C', str(root), 'ls-tree', '-r', '--name-only',
                                          revision, '--', FEATURE], text=True).splitlines()
    else:
        listed = [p.relative_to(root).as_posix() for p in (root / FEATURE).rglob('*.dart')]
    return sorted({FACADE, EXTRA, *[p for p in listed if p.endswith('.dart')]})


def layer_one(edits, base, current, package, changed_lib=None):
    """base/current: {path: text}. Returns errors and the projected token lists."""
    errors = []
    if set(base) != set(current):
        return ['cleanup file set changed: ' + str(sorted(set(base) ^ set(current)))], {}
    outside = sorted({e['file'] for e in edits} - set(base))
    errors += ['edit outside the cleanup file set: ' + p for p in outside]
    errors += ['unknown edit kind: ' + str(e.get('kind')) for e in edits if e.get('kind') not in KINDS]
    seen = set()
    for e in edits:
        key = json.dumps({k: v for k, v in e.items() if k not in ('commit', 'after', 'head')}, sort_keys=True)
        if key in seen:
            errors.append('duplicate declared edit: ' + key)
        seen.add(key)
    if changed_lib is not None:
        errors += ['lib change outside the cleanup file set: ' + p for p in sorted(set(changed_lib) - set(base))]
    if errors:
        return errors, {}
    parsed = parse({**{'base:' + p: t for p, t in base.items()}, **current}, package, ownership=True)
    projected = {}
    for path in sorted(base):
        before = Unit(base[path], parsed['base:' + path])
        after = Unit(current[path], parsed[path])
        try:
            expected = apply(before, [e for e in edits if e['file'] == path])
        except ValueError as error:
            errors.append(path + ': ' + str(error))
            continue
        actual = [t['text'] for t in after.tokens]
        if expected != actual:
            diff = list(difflib.unified_diff(expected, actual, 'declared', 'current', n=2, lineterm=''))
            errors.append('undeclared token change: ' + path + '\n' + '\n'.join(diff[:30]))
        projected[path] = (before, expected)
    return errors, projected


def records(path, unit, expected, granularity):
    """(file, declaration, ordinal, before, after) per difflib opcode, in order."""
    rows = []
    original = [t['text'] for t in unit.tokens]
    matcher = difflib.SequenceMatcher(a=original, b=expected, autojunk=False)
    ordinal = {}
    for tag, i1, i2, j1, j2 in matcher.get_opcodes():
        if tag == 'equal':
            continue
        anchor = unit.tokens[min(i1, len(unit.tokens) - 1)]['offset']
        key = granularity(path, unit, anchor)
        n = ordinal.get(key, 0)
        ordinal[key] = n + 1
        rows.append((path, key, n, tuple(original[i1:i2]), tuple(expected[j1:j2])))
    return rows


def manifest_projection(base_manifest, manifest, base, package):
    """Apply only the 21b additions of the P21 manifest to the 21a-merge tokens.

    Each file is cut into the manifest's own spans (the facade with its State
    split, a P21 destination with its split containers, an earlier destination
    as one unit) so every counted patch applies inside its declaration only.
    """
    errors, projected = [], {}
    parsed = parse({'base:' + p: t for p, t in base.items()}, package, ownership=True)
    old_rows = {r['original']: r for r in base_manifest['declarations']}
    source = manifest['source']
    segments = {}
    for path in base:
        unit = Unit(base[path], parsed['base:' + path])
        if path == source or path in manifest['destinations']:
            splits = (manifest['split_containers'] if path == source
                      else manifest['destinations'][path].get('split_containers', []))
            spans, _, _ = partition(parsed['base:' + path], splits)
            ordered = sorted(spans.items(), key=lambda kv: kv[1]['start'])
            cut = [(k, [t['text'] for t in unit.tokens if v['start'] <= t['offset'] < v['end']])
                   for k, v in ordered]
        else:
            cut = [('#file', [t['text'] for t in unit.tokens])]
        segments[path] = (unit, dict(cut), [k for k, _ in cut])
    # Directives: the manifest's list diff, by text, re-tokenized.
    old_list, new_list = base_manifest['facade_directives'], manifest['facade_directives']
    unit, cut, order = segments[source]
    if unit.directive_text != old_list:
        errors.append('21a-merge facade directives differ from the P21 manifest at ' + BASE)
    matcher = difflib.SequenceMatcher(a=old_list, b=new_list, autojunk=False)
    for tag, i1, i2, j1, j2 in matcher.get_opcodes():
        if tag == 'delete':
            for n in range(i1, i2):
                cut['@directive:' + str(n)] = []
        elif tag == 'replace' and i2 - i1 == j2 - j1:
            for k in range(i2 - i1):
                key = '@directive:' + str(i1 + k)
                cut[key] = [t['text'] for t in parse({'d': new_list[j1 + k] + '\n'}, package,
                                                     ownership=True)['d']['unitTokens']]
        elif tag != 'equal':
            errors.append('facade directive list gained or reordered entries')
    # Declarations: only the patches 21b appended to a row.
    for row in manifest['declarations']:
        old = old_rows.get(row['original'], {})
        added, prior = row.get('patches', []), old.get('patches', [])
        if added[:len(prior)] != prior:
            errors.append('21a patches changed: ' + row['original'])
            continue
        if row['original'].startswith('@directive:') or not added[len(prior):]:
            continue
        path = row.get('destination', source) if row['fate'] == 'moved' else source
        key = row.get('target', row['original'])
        unit, cut, order = segments[path]
        try:
            cut[key] = apply_explicit_token_edits(cut[key], added[len(prior):])
        except (ValueError, KeyError) as error:
            errors.append('manifest patch does not apply: ' + key + ': ' + str(error))
    for path, spec in manifest.get('earlier_patches', {}).items():
        if path not in segments or path in manifest['destinations'] or path == source:
            errors.append('earlier patch outside the earlier destinations: ' + path)
            continue
        unit, cut, order = segments[path]
        try:
            cut['#file'] = apply_explicit_token_edits(cut['#file'], spec['patches'])
        except ValueError as error:
            errors.append('earlier patch does not apply: ' + path + ': ' + str(error))
    for path, (unit, cut, order) in segments.items():
        projected[path] = (unit, [v for k in order for v in cut[k]])
    return errors, projected


def manifest_granularity(manifest):
    def key(path, unit, offset):
        return path + '#' + unit.span_of(offset)
    return key


def cross_check(edits, base, projected, package, root=ROOT, manifest=None, head=HEAD):
    """Layer-1 records == layer-2 records (network_tuning.dart is layer 1 only).

    The P21 manifest is read at the pinned head, not from the working tree: a
    later reviewed facade fix adds a patched row there (raise procedure).
    """
    base_manifest = json.loads(git_text(BASE, MANIFEST, root))
    manifest = manifest or load_manifest(root / MANIFEST, revision=head, root=root)
    errors, second = manifest_projection(base_manifest, manifest, base, package)
    key = manifest_granularity(manifest)
    one = {r for p, (u, v) in projected.items() if p != EXTRA for r in records(p, u, v, key)}
    two = {r for p, (u, v) in second.items() if p != EXTRA for r in records(p, u, v, key)}
    errors += ['layer 1 only: ' + str(r[:3]) + ' ' + ' '.join(r[3]) + ' -> ' + ' '.join(r[4])
               for r in sorted(one - two)]
    errors += ['layer 2 only: ' + str(r[:3]) + ' ' + ' '.join(r[3]) + ' -> ' + ' '.join(r[4])
               for r in sorted(two - one)]
    return errors, len(one)


def load_edits(root=ROOT):
    data = json.loads((root / EDITS).read_text())
    if data.get('base') != BASE:
        raise ValueError('declared edits must use the 21a merge base')
    return data['edits']


def gather(root=ROOT, head=HEAD):
    """Base and current texts, both from git (BASE and the pinned head)."""
    paths = file_set(root, BASE)
    if file_set(root, head) != paths:
        return paths, None, None, None
    base = {p: git_text(BASE, p, root) for p in paths}
    current = {p: git_text(head, p, root) for p in paths}
    changed = subprocess.check_output(['git', '-C', str(root), 'diff', '--name-only', BASE, head, '--', 'lib'],
                                      text=True).splitlines()
    return paths, base, current, changed


def summary(edits):
    counts = {}
    for e in edits:
        counts[e['commit'] + ' ' + e['kind']] = counts.get(e['commit'] + ' ' + e['kind'], 0) + 1
    return counts


def self_test(package, edits, base, current, changed, head=HEAD):
    """Each negative mutates one input; the real diff must stay accepted."""
    def rejected(label, edits_, current_, changed_=None, expect=''):
        errors, _ = layer_one(edits_, base, current_, package, changed if changed_ is None else changed_)
        if not errors:
            raise AssertionError('accepted: ' + label)
        if not any(expect in e for e in errors):
            raise AssertionError('rejected for another reason: ' + label + ': ' + '\n'.join(errors))
        print('cleanup proof negative ' + label + ': rejected (' + (expect or errors[0].splitlines()[0]) + ')')
    errors, _ = layer_one(edits, base, current, package, changed)
    assert not errors, errors
    print('cleanup proof positive: declared edits reproduce the current tree')
    first = next((e for e in edits if e['kind'] == 'insert_braces'), None)
    path = first['file'] if first else FACADE
    # A planted undeclared token change (a literal in a feature file).
    feature = next(p for p in sorted(current) if p.startswith(FEATURE) and '== null' in current[p])
    rejected('planted undeclared token change', edits,
             dict(current, **{feature: current[feature].replace('== null', '!= null', 1)}),
             expect='undeclared token change: ' + feature)
    # An undeclared brace: brace the excluded startup site in the tree only.
    startup = current[STARTUP]
    site = 'if (_host.engineFlagOn)\n            unawaited(_host.refreshEngineRecordingState());'
    assert site in startup, 'startup exclusion site moved'
    braced = startup.replace(site, 'if (_host.engineFlagOn) {\n            unawaited(_host.refreshEngineRecordingState());\n          }')
    rejected('undeclared brace (excluded startup site braced)', edits, dict(current, **{STARTUP: braced}),
             expect='undeclared token change: ' + STARTUP)
    excluded = dict(EXCLUDED_BRACES[0], kind='insert_braces', commit='C2')
    excluded.pop('head')
    rejected('excluded startup site declared and braced', edits + [excluded], dict(current, **{STARTUP: braced}),
             expect='excluded startup brace site declared')
    # An extra removed import, undeclared.
    facade = current[FACADE]
    import_line = next(l for l in facade.splitlines() if l.startswith("import 'package:flutter/material.dart'"))
    rejected('extra removed import', edits, dict(current, **{FACADE: facade.replace(import_line + '\n', '', 1)}),
             expect='undeclared token change: ' + FACADE)
    # An export removal, declared and applied.
    # An export removal: undeclared, and declared (exports are never removable).
    export_line = next(l for l in facade.splitlines() if l.startswith('export '))
    without_export = dict(current, **{FACADE: facade.replace(export_line + '\n', '', 1)})
    rejected('export removal (undeclared)', edits, without_export, expect='undeclared token change: ' + FACADE)
    exported = dict(base, **{FACADE: base[FACADE].replace("import 'dart:async';\n", "export 'dart:async';\n", 1)})
    assert exported[FACADE] != base[FACADE]
    errors, _ = layer_one(edits + [dict(kind='remove_directive', commit='C1', file=FACADE, uri='dart:async')],
                          exported, current, package, changed)
    assert any('export removal: dart:async' in e for e in errors), errors
    print('cleanup proof negative export removal (declared): rejected (export removal)')
    if edits:
        rejected('duplicate declared edit', edits + [edits[0]], current, expect='duplicate declared edit')
    # A code token hidden in a comment replacement.
    comment = next((e for e in edits if e['kind'] == 'replace_comment' and e['after']), None)
    if comment:
        hidden = copy.deepcopy(edits)
        target = next(e for e in hidden if e == comment)
        target['after'] = [comment['after'][0] + '\nint hidden = 0;']
        text = current[comment['file']].replace(comment['after'][0], comment['after'][0] + '\nint hidden = 0;', 1)
        rejected('code token hidden in a comment replacement', hidden, dict(current, **{comment['file']: text}),
                 expect='not a single comment')
        stale = copy.deepcopy(edits)
        next(e for e in stale if e == comment)['before'] = comment['before'] + ' (stale)'
        rejected('declared comment that no longer matches', stale, current, expect='no longer matches')
    if first:
        stale = copy.deepcopy(edits)
        next(e for e in stale if e == first)['ordinal'] = 99
        rejected('declared brace site that no longer exists', stale, current, expect='does not exist')
        drifted = copy.deepcopy(edits)
        next(e for e in drifted if e == first)['head'] = ['if', '(', 'drifted']
        rejected('declared brace site whose head no longer matches', drifted, current, expect='no longer matches')
    rejected('edit in a file outside the set', edits + [dict(kind='replace_comment', commit='C3',
             file='lib/main.dart', declaration='main', ordinal=0, before='// x', after=[])], current,
             expect='edit outside the cleanup file set')
    rejected('lib change outside the set', edits, current, list(changed) + ['lib/main.dart'],
             expect='lib change outside the cleanup file set')
    # Layer cross-check negatives on the real manifest: a dropped layer-2 edit
    # and a layer-2 edit with no declared layer-1 counterpart.
    _, projected = layer_one(edits, base, current, package, changed)
    manifest = load_manifest(ROOT / MANIFEST, revision=head)
    assert not cross_check(edits, base, projected, package, manifest=manifest, head=head)[0]
    if edits:
        dropped = copy.deepcopy(manifest)
        if dropped.get('earlier_patches'):
            path = sorted(dropped['earlier_patches'])[0]
            dropped['earlier_patches'][path]['patches'].pop()
        else:
            dropped['facade_directives'] = json.loads(git_text(BASE, MANIFEST))['facade_directives']
        errors = cross_check(edits, base, projected, package, manifest=dropped)[0]
        assert any(e.startswith('layer 1 only') for e in errors), errors
        print('cleanup proof negative layer-2 edit dropped: rejected (layer 1 only)')
    extra = copy.deepcopy(manifest)
    row = next(r for r in extra['declarations'] if r['original'] == '_VideoPlayerScreenState._vpSetState')
    row.update(fate='patched', reason='planted', test='planted',
               patches=row.get('patches', []) + [dict(before=['setState'], after=['_planted'], count=1)])
    errors = cross_check(edits, base, projected, package, manifest=extra)[0]
    assert any(e.startswith('layer 2 only') for e in errors), errors
    print('cleanup proof negative undeclared layer-2 edit: rejected (layer 2 only)')
    print('cleanup proof self-test: PASS (' + str(len(edits)) + ' declared edits)')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--parser-package', type=Path, required=True)
    parser.add_argument('--self-test', action='store_true')
    parser.add_argument('--no-cross-check', action='store_true', help='layer 1 only (diagnostics)')
    parser.add_argument('--head', default=HEAD,
                        help='revision of the current side (default: the post-C3 commit ' + HEAD + ')')
    args = parser.parse_args()
    ensure_parser_package(args.parser_package.parent.parent, args.parser_package)
    edits = load_edits()
    head = subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', '--short=9', args.head + '^{commit}'],
                                   text=True).strip()
    paths, base, current, changed = gather(head=head)
    if base is None:
        print('FAIL: cleanup file set changed between ' + BASE + ' and ' + head)
        return 1
    if args.self_test:
        self_test(args.parser_package, edits, base, current, changed, head=head)
    errors, projected = layer_one(edits, base, current, args.parser_package, changed)
    count = 0
    if not errors and not args.no_cross_check:
        more, count = cross_check(edits, base, projected, args.parser_package, head=head)
        errors += more
    for error in errors:
        print(error)
    print(('FAIL' if errors else 'PASS') + ': cleanup proof ' + BASE + '..' + head + ' over '
          + str(len(paths)) + ' files; '
          + json.dumps(summary(edits)) + '; cross-checked records ' + str(count)
          + '; ' + str(len(errors)) + ' differences')
    return bool(errors)


if __name__ == '__main__':
    raise SystemExit(main())
