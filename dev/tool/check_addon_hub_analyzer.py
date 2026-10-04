#!/usr/bin/env python3
"""Map every relocated info/warning/error to observed ORIGINAL strict symbols.

Inventory is a checkpoint-owned maximum of observed original strict and exactly
permitted public-rename probes. It cannot be enlarged by a moved-code run.
Usage: check_addon_hub_analyzer.py ANALYZE.txt --parser-package CONFIG
"""
import argparse
import csv
import json
import re
from collections import Counter
from pathlib import Path

from check_settings_moves import all_nodes
from check_verbatim_moves import parse

ROOT = Path(__file__).resolve().parents[2]
SOURCE = 'lib/screens/addons/addon_hub_screen.dart'
FEATURE = 'lib/features/addon_hub/'
LINE = re.compile(r'^\s*(error|warning|info) • (.*) • (\S+?):(\d+):(\d+) • (\S+)\s*$')


def main():
    args = argparse.ArgumentParser(description=__doc__)
    args.add_argument('analyzer', type=Path)
    args.add_argument('--parser-package', type=Path, required=True)
    options = args.parse_args()
    inventory = json.loads((ROOT / 'dev/tool/addon_hub_analyzer_inventory.json').read_text())
    sources = {SOURCE: (ROOT / SOURCE).read_text()}
    sources.update({str(p.relative_to(ROOT)): p.read_text() for p in (ROOT / FEATURE).rglob('*.dart')})
    nodes = all_nodes(parse(sources, options.parser_package))
    rows = list(csv.DictReader((ROOT / 'dev/tool/addon_hub_manifest.tsv').open(), delimiter='\t'))
    origins = {(r['destination_file'], r['destination_class'], r['new_name']): r['original_name'] for r in rows}
    observed = Counter()
    failures = []
    for line in options.analyzer.read_text().splitlines():
        match = LINE.match(line)
        if not match:
            continue
        severity, message, path, line_number, column, rule = match.groups()
        if path != SOURCE and not path.startswith(FEATURE):
            continue
        source = sources[path]
        offset = sum(len(s) for s in source.splitlines(keepends=True)[:int(line_number) - 1]) + int(column) - 1
        candidates = [(key, node) for key, node in nodes.items() if key[0] == path and node['start'] <= offset < node['end']]
        if candidates:
            key, _ = min(candidates, key=lambda pair: pair[1]['end'] - pair[1]['start'])
            original = origins.get(key)
            if original is None and key[1]:
                class_origin = origins.get((path, '', key[1]))
                if class_origin is not None:
                    original = class_origin + '.' + (class_origin if key[2] == key[1] else key[2])
            if original is None and path == SOURCE:
                original = '.'.join(part for part in key[1:] if part)
        else:
            original = '<imports>' if rule == 'directives_ordering' else None
        if original is None:
            failures.append('Unregistered diagnostic symbol: ' + line.strip())
            continue
        observed[(original, severity, rule, message)] += 1
    allowed = Counter({(r['original_member'], r['severity'], r['rule'], r['message']): r['maximum_count'] for r in inventory['identities']})
    for identity, count in (observed - allowed).items():
        failures.append(f'Unobserved ORIGINAL identity/count: {identity} (+{count})')
    # The three unchanged const infos must actually relocate with their leaves.
    # Import ordering and public key infos may disappear after import cleanup.
    for identity, count in allowed.items():
        original, severity, rule, message = identity
        if rule != 'prefer_const_constructors':
            continue
        row = next((r for r in rows if original == r['original_name']
                    or original.startswith(r['original_name'] + '.')), None)
        if row and (ROOT / row['destination_file']).exists():
            if observed[identity] != count:
                failures.append(f'Original const identity did not relocate: {identity}')
    for failure in failures:
        print(failure)
    if failures:
        return 1
    print(f'Addon hub strict per-symbol evidence: {sum(observed.values())} observed destination diagnostics, zero additions')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
