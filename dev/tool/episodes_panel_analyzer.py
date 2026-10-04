#!/usr/bin/env python3
"""Trace strict episode-panel diagnostics to the two ORIGINALs and alias probe."""
import argparse
from collections import Counter
import csv, json, subprocess
from pathlib import Path
from check_verbatim_moves import ROOT, parse
from merged_detail_analyzer import enclosing, entries
FACADE = 'lib/widgets/episodes_panel.dart'

def main():
    p = argparse.ArgumentParser()
    p.add_argument('--parser-package', type=Path, required=True)
    p.add_argument('--evidence', type=Path, required=True)
    p.add_argument('--candidate-log', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    a = p.parse_args()
    rows = list(csv.DictReader((ROOT / 'dev/tool/episodes_panel_manifest.tsv').open(), delimiter='\t'))
    maximum = Counter()
    baselines = []
    for label, revision in [('original', '81fff4be'), ('formatted', '92339749'), ('rename-alias', '92339749')]:
        source = subprocess.check_output(['git', 'show', revision + ':' + FACADE], cwd=ROOT, text=True)
        if label == 'rename-alias':
            source = (ROOT / '.dart_tool/episodes_panel_strict/rename_alias_probe.dart').read_text()
        unit = parse({FACADE: source}, a.parser_package)[FACADE]
        counter = Counter()
        identities = []
        log = a.evidence / {'original': 'original-strict.txt', 'formatted': 'formatted-strict.txt', 'rename-alias': 'rename-alias-strict-final.txt'}[label]
        for severity, file, line, rule, message in entries(log):
            symbol = enclosing(unit, source, line)
            if label == 'rename-alias' and symbol.startswith('EpisodesPanelState.'):
                name = symbol.split('.')[-1]
                matching = [r for r in rows if r['new_name'] == name and r['original_name'].startswith('EpisodesPanelState.')]
                if len(matching) == 1:
                    symbol = matching[0]['original_name']
            identity = (severity, rule, symbol, message)
            counter[identity] += 1
            identities.append({'identity': identity, 'line': line})
        assert sum(counter.values()) == 19 and all((k[0] == 'info' and k[1] in ('directives_ordering', 'curly_braces_in_flow_control_structures') for k in counter)), counter
        maximum |= counter
        baselines.append({'label': label, 'revision': revision, 'identities': identities})
    assert sum(maximum.values()) == 19, maximum
    sources = {FACADE: (ROOT / FACADE).read_text()}
    sources.update({str(f.relative_to(ROOT)): f.read_text() for f in (ROOT / 'lib/features/episodes_panel').rglob('*.dart')})
    parsed = parse(sources, a.parser_package)
    current = Counter()
    traced = []
    for severity, file, line, rule, message in entries(a.candidate_log):
        if file == '.dart_tool/episodes_panel_strict/current_facade.dart':
            file = FACADE
        if file not in parsed:
            continue
        symbol = enclosing(parsed[file], sources[file], line)
        if file != FACADE and symbol != '<imports>':
            owner, _, name = symbol.rpartition('.')
            matching = [r for r in rows if r['destination_file'] == file and r['destination_class'] == owner and (r['new_name'] == name)]
            whole = [r for r in rows if r['destination_file'] == file and (not r['destination_class']) and (r['new_name'] == owner)]
            if len(matching) == 1:
                symbol = matching[0]['original_name']
            elif len(whole) == 1:
                symbol = whole[0]['original_name'] + '.' + name
            else:
                symbol = '<new>:' + file + ':' + symbol
        current[severity, rule, symbol, message] += 1
        traced.append({'severity': severity, 'rule': rule, 'original_symbol': symbol, 'file': file, 'line': line, 'message': message})
    added = current - maximum
    result = {'procedure': 'maximum of two ORIGINAL strict inventories and ORIGINAL-only rename/alias probe', 'baselines': baselines, 'baseline_count': sum(maximum.values()), 'candidate_count': sum(current.values()), 'candidate_identities': traced, 'added': [{'identity': k, 'count': v} for k, v in added.items()], 'removed': [{'identity': k, 'count': v} for k, v in (maximum - current).items()], 'verdict': 'FAIL' if added else 'PASS'}
    a.output.write_text(json.dumps(result, indent=2) + '\n')
    print(result['verdict'], len(traced), 'strict diagnostics;', sum(added.values()), 'new identities')
    return bool(added)
if __name__ == '__main__':
    raise SystemExit(main())
