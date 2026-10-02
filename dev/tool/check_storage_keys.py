#!/usr/bin/env python3
"""Shallow-clone-safe constant inventory check for the storage split.

The committed inventory includes every original static constant, its declared
expression and its expression with referenced constants resolved. No historical
git objects are needed to check. --generate is only for step 0, on the unsplit
source; inventory changes require a separately reviewed behavior change.
"""
from collections import defaultdict
import json
import re
import sys
from storage_dart import (LEGACY, ROOT, code_tokens, members, read_map,
                          source_paths, replacements, normalized)

INVENTORY = ROOT / 'dev/tool/storage_key_inventory.json'
EXTERNAL = {
    'TrackingScrobblePreferences.key': 'lib/services/tracking_scrobble_preferences.dart',
    'TvOsRecoveryLimits.myWatchlistPreferenceKey': 'lib/services/profiles/tvos_recovery_limits.dart',
    'TvOsRecoveryLimits.envelopeValueBytes': 'lib/services/profiles/tvos_recovery_limits.dart',
    'IptvMediaStore.favoritesListId': 'lib/services/iptv_media_store.dart',
    'DebrifyTvDatabase.favoritesListId': 'lib/services/debrify_tv_database.dart',
}


def expression(declaration):
    ts = code_tokens(declaration)
    start = next(t.end for t in ts if t.text == '=')
    return declaration[start:ts[-1].start].strip()


def unqualify(source, rows):
    ts, edits, covered = code_tokens(source), [], set()
    targets = {r['target']: r['member'] for r in rows}
    renamed = {r['target'].split('.')[-1]: r['member'] for r in rows if r['shared'] == 'yes'}
    for i in range(len(ts)-2):
        a, d, b = ts[i:i+3]
        if d.text == '.' and a.text+'.'+b.text in targets:
            edits.append((a.start, b.end, targets[a.text+'.'+b.text]))
            covered.update((i, i+1, i+2))
    for i,t in enumerate(ts):
        if i not in covered and t.text in renamed and (not i or ts[i-1].text != '.'):
            edits.append((t.start, t.end, renamed[t.text]))
    return replacements(source, edits)


def resolved(source, constants, visiting=()):
    ts, edits, covered = code_tokens(source), [], set()
    for i in range(len(ts)-2):
        a, d, b = ts[i:i+3]
        name = a.text+'.'+b.text
        if d.text == '.' and name in EXTERNAL:
            assert name not in visiting, name
            file = (ROOT / EXTERNAL[name]).read_text()
            match = re.search(r'static\s+const\s+(?:\w+(?:<[^>]+>)?\s+)?'+re.escape(b.text)+r'\s*=([^;]+);', file)
            assert match, name
            value = resolved(match.group(1).strip(), constants, (*visiting, name))
            edits.append((a.start, b.end, '('+value+')'))
            covered.update((i, i+1, i+2))
    for i,t in enumerate(ts):
        if i not in covered and t.text in constants and (not i or ts[i-1].text != '.'):
            assert t.text not in visiting, t.text
            value = resolved(constants[t.text], constants, (*visiting, t.text))
            edits.append((t.start, t.end, '('+value+')'))
    return replacements(source, edits)


def declarations():
    rows, found = read_map(), defaultdict(list)
    for p in source_paths():
        path = p.relative_to(ROOT).as_posix()
        candidates = [r for r in rows if r['file'] == path and r['ref_kind'] == 'static'
                      and r['kind'] != 'reset_entry']
        if path == LEGACY:
            cls = 'StorageService'
        elif candidates:
            cls = candidates[0]['target'].split('.')[0]
        else:
            # A storage file the member map doesn't know must not hide a
            # constant: an unmapped redeclared key would otherwise pass.
            assert not re.search(r'\bstatic\s+const\b', p.read_text()), (
                path, 'declares constants but has no member-map rows')
            continue
        names = {r['target'].split('.')[-1]: r['member'] for r in candidates}
        for m in members(p.read_text(), cls):
            if m.kind in ('key','const'):
                name = m.name if path == LEGACY else names.get(m.name, m.name)
                found[name].append(unqualify(expression(m.declaration), rows))
    return found


def check(generate=False):
    found = declarations()
    values = {k:v[0] for k,v in found.items()}
    if generate:
        assert len(values) == 314 and all(len(v)==1 for v in found.values())
        inventory = [{'name': k, 'expression': v, 'resolved_expression': resolved(v, values),
                      'occurrences': len(found[k])} for k,v in sorted(values.items())]
        INVENTORY.write_text(json.dumps(inventory, indent=2)+'\n')
    expected = {r['name']:r for r in json.loads(INVENTORY.read_text())}
    assert set(found) == set(expected), ('lost', set(expected)-set(found), 'added', set(found)-set(expected))
    for name, expressions in found.items():
        e = expected[name]
        assert len(expressions) == e['occurrences'] == 1, (name, 'duplicated')
        assert normalized(expressions[0]) == normalized(e['expression']), (name,'expression changed')
        assert normalized(resolved(expressions[0], values)) == normalized(e['resolved_expression']), (name,'resolved value changed')
    print('Storage constants: all 314 name/value pairs declared exactly once; resolved references unchanged.')


if __name__ == '__main__':
    check('--generate' in sys.argv)
