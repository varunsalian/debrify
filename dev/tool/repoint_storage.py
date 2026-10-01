#!/usr/bin/env python3
"""Repoint tracked Dart callers after merging the StorageService split.

  python3 dev/tool/repoint_storage.py --through-step N
  python3 dev/tool/repoint_storage.py --self-test

Executable interpolation expressions are rewritten; literal text and comments
are untouched. Imports with show/hide/as are handled explicitly. The legacy
reset forwarding leaf is exempt until step 8 deletes it. Repeated runs are
idempotent. This script changes callers only; the member map governs ownership.
"""
import argparse
import re
import subprocess
from storage_dart import (LEGACY, RESET, ROOT, code_tokens, read_map,
                          replacements, tokens)

IMPORT = re.compile(r"(?m)^import\s+(['\"])([^'\"]+)\1([^;]*);[^\S\n]*\n?")
HOME_TYPES = {'HomeHeroSourceMode', 'HomeHeroSource', 'HomeExtraRow', 'HomeCardOrientation'}


def executable_tokens(source):
    directives = [(m.start(),m.end()) for m in IMPORT.finditer(source)]
    return [t for t in code_tokens(source)
            if not any(a <= t.start < b for a,b in directives)]


def rewrite(source, path, rows, through):
    if through == 0:
        return source
    imports = list(IMPORT.finditer(source))
    old_imports = [m for m in imports if m.group(2).endswith('storage_service.dart')]
    aliases = set()
    for m in old_imports:
        suffix = m.group(3)
        if not re.fullmatch(r'\s*(?:as\s+\w+\s*)?(?:(?:show|hide)\s+\w+(?:\s*,\s*\w+)*\s*)?', suffix):
            raise ValueError(f'{path}: unsupported import suffix {suffix!r}')
        alias = re.search(r'\bas\s+(\w+)', suffix)
        if alias:
            aliases.add(alias.group(1))
    mapping = {r['member']: r for r in rows if r['step'] <= through}
    ts = executable_tokens(source)
    edits, covered = [], set()
    for i,t in enumerate(ts):
        if t.text != 'StorageService' or i+2 >= len(ts) or ts[i+1].text != '.':
            continue
        r = mapping.get(ts[i+2].text)
        if not r or r['ref_kind'] != 'static':
            continue
        if path == RESET and r['kind'] == 'reset_entry':
            continue
        a = i
        if i >= 2 and ts[i-1].text == '.' and ts[i-2].text in aliases:
            a = i-2
        edits.append((ts[a].start, ts[i+2].end, r['target']))
        covered.update(range(a,i+3))
    types = {r['member']:r for r in mapping.values() if r['ref_kind']=='type'}
    for i,t in enumerate(ts):
        if i in covered or t.text not in types or path == types[t.text]['file']:
            continue
        if i >= 2 and ts[i-1].text == '.' and ts[i-2].text in aliases:
            edits.append((ts[i-2].start, t.end, types[t.text]['target']))
    source = replacements(source, edits)
    ts = executable_tokens(source)
    words = {t.text for t in ts}
    expressions = {a.text+'.'+b.text for a,d,b in zip(ts,ts[1:],ts[2:]) if d.text=='.'}
    remaining_types = {r['member'] for r in rows if r['ref_kind']=='type' and r['step']>through}
    keep_legacy = 'StorageService' in words or bool(words & remaining_types)
    # Explicit alias-qualified uses of re-exported Home types lose only the
    # alias; a direct import restores the original re-export contract.
    home_edits = []
    for i in range(len(ts)-2):
        if ts[i].text in aliases and ts[i+1].text=='.' and ts[i+2].text in HOME_TYPES:
            home_edits.append((ts[i].start,ts[i+2].end,ts[i+2].text))
    source = replacements(source, home_edits)
    required = set()
    ts = executable_tokens(source)
    words = {t.text for t in ts}
    for r in mapping.values():
        if r['file'] == path:
            continue
        if r['ref_kind']=='type':
            used = r['target'] in words
        elif '.' not in r['target']:
            used = r['target'] in words
        else:
            cls,member = r['target'].split('.')
            used = cls+'.'+member in expressions
        if used:
            required.add('package:debrify/'+r['file'].removeprefix('lib/'))
    if old_imports and not keep_legacy and words & HOME_TYPES:
        required.add('package:debrify/models/home_preferences.dart')
    # Import URIs are canonicalized for duplicate detection, while existing
    # style and import combinators for unrelated imports remain verbatim.
    def canonical_uri(uri):
        if uri.startswith('package:debrify/'):
            return uri
        if uri.startswith(('dart:','package:')):
            return uri
        from pathlib import PurePosixPath
        import posixpath
        resolved = posixpath.normpath(str(PurePosixPath(path).parent / uri))
        return 'package:debrify/'+resolved.removeprefix('lib/') if resolved.startswith('lib/') else uri
    imported = {canonical_uri(m.group(2)) for m in IMPORT.finditer(source)
                if not m.group(3).strip()}
    edits = []
    for m in IMPORT.finditer(source):
        if m.group(2).endswith('storage_service.dart') and not keep_legacy:
            edits.append((m.start(),m.end(),''))
    source = replacements(source, edits)
    additions = sorted(required-imported)
    if additions:
        def order(uri):
            return (0 if uri.startswith('dart:') else 1 if uri.startswith('package:') else 2, uri)
        for uri in additions:
            existing = list(IMPORT.finditer(source))
            later = next((m for m in existing if order(m.group(2)) > order(uri)), None)
            point = later.start() if later else existing[-1].end() if existing else 0
            source = source[:point]+f"import '{uri}';\n"+source[point:]
    return source


def run(root, rows, through):
    paths = subprocess.run(['git','ls-files','*.dart'],cwd=root,capture_output=True,
                           text=True,check=True).stdout.splitlines()
    changed = []
    for path in paths:
        file = root / path
        if not file.exists():
            continue
        source = file.read_text()
        new = rewrite(source,path,rows,through)
        if new != source:
            file.write_text(new)
            changed.append(path)
    return changed


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--through-step',type=int,choices=range(9))
    parser.add_argument('--self-test',action='store_true')
    args = parser.parse_args()
    if args.self_test:
        import unittest
        import storage_tooling_test
        result = unittest.TextTestRunner().run(unittest.defaultTestLoader.loadTestsFromModule(storage_tooling_test))
        if not result.wasSuccessful():
            raise SystemExit(1)
    if args.through_step is not None:
        changed = run(ROOT,read_map(),args.through_step)
        print(f'Storage callers: {len(changed)} tracked Dart files repointed through step {args.through_step}.')
    elif not args.self_test:
        parser.error('--through-step or --self-test is required')
