#!/usr/bin/env python3
"""Compare all 17 observed original warning occurrences by rule and original member.

Usage: playlist_content_warning_evidence.py ANALYZE.txt [--parser-package CONFIG]
Line shifts and destination changes do not erase warnings. No recording mode.
"""
import argparse
from collections import Counter
import csv
import json
from pathlib import Path
import re
import subprocess
import sys
from check_verbatim_moves import parse

ROOT = Path(__file__).resolve().parents[2]
SOURCE = 'lib/screens/playlist_content_view_screen.dart'
FEATURE = 'lib/features/playlist_content/'
PATTERN = re.compile(r'^\s*(warning) • (.*) • (\S+?):(\d+):(\d+) • (\S+)\s*$')

def occurrences(log, sources, rows, package, original=False):
    ast = parse(sources, package)
    result = Counter()
    for line in log.splitlines():
        match = PATTERN.match(line)
        if not match:
            continue
        severity, message, path, lineno, column, rule = match.groups()
        if path != SOURCE and not path.startswith(FEATURE):
            continue
        text = sources[path]
        offset = sum(len(s) for s in text.splitlines(keepends=True)[:int(lineno) - 1]) + int(column) - 1
        members = []
        for d in ast[path]['declarations']:
            leaves = [(d['name'], m) for m in d['members']] if d['members'] else [('', d)]
            for owner, leaf in leaves:
                if leaf['start'] <= offset < leaf['end']:
                    members.append((owner, leaf['name']))
        if len(members) != 1:
            raise AssertionError(('Warning has no unique enclosing member', line, members))
        owner, name = members[0]
        if original:
            identity = owner + '.' + name if owner else name
        else:
            matches = [r['original_name'] for r in rows if (r['destination_file'], r['destination_class'], r['new_name']) == (path, owner, name)]
            if not matches and path == SOURCE:
                matches = [r['original_name'] for r in rows if r['original_name'] == owner + '.' + name]
            if len(matches) != 1:
                raise AssertionError(('Unmapped warning', line, owner, name, matches))
            identity = matches[0]
        result[(severity, rule, identity, message)] += 1
    return result

def main():
    args = argparse.ArgumentParser(description=__doc__)
    args.add_argument('analyze', type=Path)
    args.add_argument('--parser-package', type=Path)
    a = args.parse_args()
    rows = list(csv.DictReader((ROOT / 'dev/tool/playlist_content_manifest.tsv').open(), delimiter='\t'))
    expected = Counter(tuple(item) for item in json.loads((ROOT / 'dev/tool/playlist_content_original_warnings.json').read_text()))
    sources = {SOURCE: (ROOT / SOURCE).read_text()}
    sources.update({str(p.relative_to(ROOT)): p.read_text() for p in (ROOT / FEATURE).rglob('*.dart')})
    actual = occurrences(a.analyze.read_text(), sources, rows, a.parser_package)
    if expected != actual:
        print('Missing:', expected - actual)
        print('Added:', actual - expected)
        return 1
    print('Playlist content warnings: all 17 observed original occurrences preserved by rule/member/message.')
    return 0

if __name__ == '__main__':
    sys.exit(main())
