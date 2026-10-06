#!/usr/bin/env python3
"""Pin IPTV two-pane diagnostics to ORIGINAL/rename-probe rule, symbol, message maxima."""
import argparse
import csv
import json
import re
from collections import Counter
from pathlib import Path
from check_verbatim_moves import ROOT, ensure_parser_package, parse
from check_settings_moves import all_nodes

SOURCE = 'lib/screens/settings/iptv_settings_two_pane.dart'
FEATURE = 'lib/features/iptv_settings_two_pane'


def collect(analyzer, app, package, strict_original=None):
    config = json.loads((ROOT / 'dev/tool/iptv_settings_two_pane_checker_config.json').read_text())
    if strict_original:
        sources = {strict_original: (app / strict_original).read_text()}
    else:
        sources = {SOURCE: (app / SOURCE).read_text()}
        sources.update({p.relative_to(app).as_posix(): p.read_text()
                        for p in (app / FEATURE).rglob('*.dart')})
    nodes = all_nodes(parse(sources, package))
    with (ROOT / 'dev/tool/iptv_settings_two_pane_manifest.tsv').open() as handle:
        rows = list(csv.DictReader(handle, delimiter='\t'))
    origins = {(r['destination_file'], r['destination_class'], r['new_name']): r['original_name']
               for r in rows}
    classes = {r['new_name']: r['original_name'] for r in rows
               if not r['destination_class'] and '.' not in r['original_name']}
    reverse = {v: k for k, v in config['type_renames'].items()}
    observed = Counter()
    errors = []
    for line in Path(analyzer).read_text().splitlines():
        match = re.match(r'^\s*(error|warning|info) • (.*) • (\S+?):(\d+):(\d+) • (\S+)\s*$', line)
        if not match:
            continue
        severity, message, file, ln, col, rule = match.groups()
        if file not in sources:
            continue
        text = sources[file]
        offset = sum(map(len, text.splitlines(keepends=True)[:int(ln) - 1])) + int(col) - 1
        candidates = [(k, n) for k, n in nodes.items()
                      if k[0] == file and n['start'] <= offset < n['end']]
        symbol = None
        if rule == 'directives_ordering':
            symbol = '@imports'
        elif candidates:
            key, node = min(candidates, key=lambda item: item[1]['end'] - item[1]['start'])
            symbol = origins.get(key)
            if symbol is None:
                owner = classes.get(key[1], reverse.get(key[1], key[1]))
                name = classes.get(key[2], reverse.get(key[2], key[2]))
                if name == owner and key[1] in classes:
                    symbol = owner
                elif strict_original or file == SOURCE or key[1] in classes or key[1] in reverse or key[1] == 'IptvSettingsTwoPaneState':
                    symbol = owner + '.' + name if owner else name
        if symbol is None:
            errors.append('Unregistered diagnostic: ' + line)
        else:
            observed[(severity, rule, symbol, message)] += 1
    return observed, errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('analyzer', type=Path)
    parser.add_argument('--probe', type=Path)
    parser.add_argument('--parser-package', type=Path, required=True)
    args = parser.parse_args()
    package = args.parser_package.resolve()
    ensure_parser_package(package.parent.parent, package)
    observed, errors = collect(args.analyzer, args.probe or ROOT, package)
    inventory = json.loads((ROOT / 'dev/tool/iptv_settings_two_pane_analyzer_inventory.json').read_text())
    allowed = Counter({(r['severity'], r['rule'], r['symbol'], r['message']): r['maximum']
                       for r in inventory['entries']})
    errors.extend(str((identity, count)) for identity, count in (observed - allowed).items())
    print('Observed diagnostics:', sum(observed.values()))
    if errors:
        raise AssertionError('\n'.join(errors))
    print('Strict rule/symbol/message maxima: zero additions')


if __name__ == '__main__':
    main()
