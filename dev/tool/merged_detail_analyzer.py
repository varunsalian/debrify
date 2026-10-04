#!/usr/bin/env python3
"""Compare destination-lint diagnostics by original enclosing symbol.

The formatted original is authoritative. Per-identity maxima with the
unformatted original preserve only original identities, never a candidate.
Imports are grouped explicitly; destination diagnostics must trace to an
original leaf (or a member of an original whole-class leaf).
"""
import argparse
from collections import Counter
import csv
import json
from pathlib import Path
import re
import subprocess

from check_verbatim_moves import ROOT, parse

FACADE = 'lib/screens/merged_series_detail_screen.dart'
FORMATTED = '21320ff9264fb7b1072b7682665058982a763dec'
ORIGINAL = 'def4e30423c9d8344eeb340c665afc2ee866c11f'


def entries(path):
    for line in Path(path).read_text().splitlines():
        pieces = [piece.strip() for piece in line.split(' • ')]
        if len(pieces) != 4:
            continue
        location = re.match(r'(.+):(\d+):(\d+)$', pieces[2])
        if location:
            yield pieces[0], location[1], int(location[2]), pieces[3], pieces[1]


def enclosing(unit, source, line):
    def start_line(node):
        return source.count('\n', 0, node['start']) + 1
    def end_line(node):
        return source.count('\n', 0, node['end']) + 1
    members = [(declaration['name'] + '.' + member['name'], member)
               for declaration in unit['declarations'] for member in declaration['members']]
    matches = [(name, node) for name, node in members
               if start_line(node) <= line <= end_line(node)]
    if matches:
        return min(matches, key=lambda pair: pair[1]['end'] - pair[1]['start'])[0]
    for declaration in unit['declarations']:
        if start_line(declaration) <= line <= end_line(declaration):
            return declaration['name']
    return '<imports>'


def baseline(log, revision, package):
    source = subprocess.check_output(['git', 'show', revision + ':' + FACADE], cwd=ROOT, text=True)
    unit = parse({FACADE: source}, package)[FACADE]
    counter = Counter()
    identities = []
    for severity, file, line, rule, message in entries(log):
        assert file.endswith('merged_series_detail_screen.dart'), file
        symbol = enclosing(unit, source, line)
        identity = (severity, rule, symbol, message)
        counter[identity] += 1
        identities.append({'severity': severity, 'rule': rule, 'file': FACADE,
                           'symbol': symbol, 'message': message, 'line': line})
    assert len(identities) in (38, 42), len(identities)
    return counter, identities


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--parser-package', type=Path, required=True)
    parser.add_argument('--formatted-log', type=Path, required=True)
    parser.add_argument('--original-log', type=Path, required=True)
    parser.add_argument('--candidate-log', type=Path)
    parser.add_argument('--strict-facade-path', default='.dart_tool/merged_detail_strict/current_facade.dart')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    formatted, formatted_identities = baseline(args.formatted_log, FORMATTED, args.parser_package)
    unformatted, original_identities = baseline(args.original_log, ORIGINAL, args.parser_package)
    maximum = formatted | unformatted
    added_to_original = formatted - unformatted
    assert sum(added_to_original.values()) == 4
    assert all(key[1] == 'curly_braces_in_flow_control_structures' for key in added_to_original)
    result = {'analyzer_baseline_revision': FORMATTED, 'execution_base': ORIGINAL,
              'procedure': 'per-identity maximum of formatted and unformatted ORIGINAL only',
              'formatted_identities': formatted_identities, 'unformatted_identities': original_identities,
              'baseline_count': sum(maximum.values()), 'format_induced': [list(key) for key in added_to_original]}
    added = Counter()
    if args.candidate_log:
        rows = list(csv.DictReader((ROOT / 'dev/tool/merged_detail_manifest.tsv').open(), delimiter='\t'))
        sources = {FACADE: (ROOT / FACADE).read_text()}
        feature = ROOT / 'lib/features/merged_detail'
        if feature.exists():
            sources.update({str(p.relative_to(ROOT)): p.read_text() for p in feature.rglob('*.dart')})
        parsed = parse(sources, args.parser_package)
        current = Counter()
        traced = []
        for severity, file, line, rule, message in entries(args.candidate_log):
            if file == args.strict_facade_path:
                file = FACADE
            if file not in parsed:
                continue
            symbol = enclosing(parsed[file], sources[file], line)
            if file != FACADE and symbol != '<imports>':
                owner, _, name = symbol.rpartition('.')
                direct = [r for r in rows if r['destination_file'] == file
                          and r['destination_class'] == owner and r['new_name'] == name]
                whole = [r for r in rows if r['destination_file'] == file
                         and not r['destination_class'] and r['new_name'] == owner]
                if len(direct) == 1:
                    symbol = direct[0]['original_name']
                elif len(whole) == 1:
                    symbol = whole[0]['original_name'] + '.' + name
                else:
                    symbol = '<new>:' + file + ':' + symbol
            identity = (severity, rule, symbol, message)
            current[identity] += 1
            traced.append({'severity': severity, 'rule': rule, 'file': file,
                           'original_symbol': symbol, 'message': message, 'line': line})
        added = current - maximum
        result.update(candidate_log=str(args.candidate_log), candidate_count=sum(current.values()),
                      candidate_identities=traced, added=[{'identity': list(key), 'count': value} for key, value in added.items()],
                      removed=[{'identity': list(key), 'count': value} for key, value in (maximum-current).items()])
    result['verdict'] = 'FAIL' if added else 'PASS'
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(f'{result["verdict"]}: original strict baseline {sum(maximum.values())}; additions {sum(added.values())}')
    return bool(added)


if __name__ == '__main__':
    raise SystemExit(main())
