#!/usr/bin/env python3
"""Audit ORIGINAL's exhaustive AST strings, Text sites and reachable focus cases.

This source inventory is a checker, never behavioural mutation evidence. The
named tests inspect mounted public widgets without reading application source.
"""
import argparse
from collections import Counter, defaultdict
import copy
import hashlib
import json
from pathlib import Path
import subprocess

from check_verbatim_moves import ensure_parser_package
from recordings_source_reader import original_source

ROOT = Path(__file__).resolve().parents[2]
INVENTORY = ROOT / 'dev/tool/recordings_text_inventory.json'


def ast(source, package):
    template = ROOT / 'dev/tool/recordings_text_ast.dart.txt'
    kernel = package.parent / 'recordings_text_ast.dill'
    if not kernel.exists() or kernel.stat().st_mtime < template.stat().st_mtime:
        subprocess.run(['dart', 'compile', 'kernel', '--packages='+str(package),
                        '-o', str(kernel), str(template)], check=True,
                       stdout=subprocess.DEVNULL)
    result = subprocess.run(['dart', str(kernel)],
                            input=json.dumps({'source': source})+'\n',
                            capture_output=True, text=True, check=True)
    return json.loads(result.stdout)


def validate(inventory, parsed):
    for field, collection in [('strings', 'strings'), ('text_properties', 'texts')]:
        expected = [{key: row[key] for key in actual} for row, actual in
                    zip(inventory[field], parsed[collection])]
        if len(inventory[field]) != len(parsed[collection]) or expected != parsed[collection]:
            raise ValueError('Unregistered or altered AST '+collection)
        for row in inventory[field]:
            contract = row.get('contract')
            if contract not in ['B', 'S', 'internal']:
                raise ValueError('Unclassified inventory item: '+row['id'])
            if field == 'text_properties' and contract == 'internal':
                raise ValueError('Text cannot be internal')
            coverage(row)
    for row in inventory['focus_visuals']: coverage(row)
    calls = parsed['buttons']
    if calls != inventory['hub_button_calls'] or len(calls) != 3:
        raise ValueError('HubButton call inventory changed')
    if not all(row['properties'].get('filled') == 'true' or
               row['properties'].get('danger') == 'true' for row in calls):
        raise ValueError('Plain HubButton is now reachable; S must become B')


def coverage(row):
    if row['contract'] == 'B':
        spec = row.get('coverage', {})
        file = ROOT / spec.get('test_file', '')
        if (not spec.get('test_name') or not spec.get('assertion') or
                not file.is_file() or 'source_contract' in str(file) or
                'shape_inventory' in str(file)):
            raise ValueError('B requires a named behavioural test')
        text = file.read_text()
        if 'RecordingsSource' in text or 'recordings_source.dart' in text:
            raise ValueError('B cannot use source-reader evidence')
        if spec['assertion'] not in text:
            raise ValueError('Missing named behavioural assertion: '+spec['assertion'])
    elif not row.get('reason'):
        raise ValueError('S/internal requires an explicit reason')


def counts(inventory):
    grouped = defaultdict(Counter)
    for row in inventory['strings']: grouped[row['class']][row['contract']] += 1
    return dict(strings={k:dict(v) for k,v in sorted(grouped.items())},
                text_properties=dict(Counter(x['contract'] for x in inventory['text_properties'])),
                focus_visuals=dict(Counter(x['contract'] for x in inventory['focus_visuals'])))


def self_test(inventory, parsed, source, package):
    validate(inventory, parsed)
    # The helper must see both implicit and const constructors, adjacent strings,
    # interpolation branches, and literals that are not direct Text arguments.
    probe = ast("class Probe { void build() { Text('a' 'b'); const Text('c'); "
                "Text('${true ? 'yes' : 'no'}'); final days = ['Mon', 'Tue']; } }", package)
    assert len(probe['texts']) == 3 and len(probe['strings']) == 7
    assert probe['strings'][0]['value'] == 'ab'
    rejections = []
    def negative(label, candidate=inventory, tree=parsed):
        try: validate(candidate, tree)
        except (ValueError, KeyError) as error:
            rejections.append(dict(label=label, rejection=str(error)))
        else: raise AssertionError('inventory accepted '+label)
    bad = copy.deepcopy(inventory); bad['strings'].pop()
    negative('omitted literal', bad)
    bad = copy.deepcopy(inventory); bad['text_properties'].pop()
    negative('omitted Text site', bad)
    bad = copy.deepcopy(inventory); bad['strings'][18]['contract'] = 'unchecked'
    negative('unclassified visible text', bad)
    bad = copy.deepcopy(inventory)
    row = next(x for x in bad['strings'] if x['contract'] == 'B')
    row['coverage']['test_file'] = 'test/features/recordings/presentation/recordings_source_contract_test.dart'
    negative('source contract substituted for B', bad)
    bad = copy.deepcopy(inventory)
    next(x for x in bad['strings'] if x['contract'] == 'S')['reason'] = ''
    negative('S without reason', bad)
    for label, before, after in [
        ('new unregistered string', "'Recordings',", "'DVR',"),
        ('weekday reordered', "['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']", "['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']"),
        ('Text layout changed', 'maxLines: 2,', 'maxLines: 1,'),
        ('plain variant becomes reachable', 'filled: true,', 'filled: false,'),
    ]:
        assert before in source
        negative(label, tree=ast(source.replace(before, after, 1), package))
    print('Recordings text inventory: 2 positives; '+str(len(rejections))+' rejections')
    return dict(positive=2, negative=len(rejections), rejections=rejections)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--parser-package', required=True, type=Path)
    parser.add_argument('--self-test', action='store_true')
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    package = args.parser_package.resolve()
    ensure_parser_package(package.parent.parent, package)
    inventory = json.loads(INVENTORY.read_text())
    config = json.loads((ROOT / 'dev/tool/recordings_checker_config.json').read_text())
    source = original_source(config)
    assert hashlib.sha256(source.encode()).hexdigest() == inventory['source_sha256']
    parsed = ast(source, package); validate(inventory, parsed)
    report = dict(counts=counts(inventory))
    if args.self_test: report['self_test'] = self_test(inventory, parsed, source, package)
    print(json.dumps(report['counts'], sort_keys=True))
    if args.report: args.report.write_text(json.dumps(report, indent=2)+'\n')


if __name__ == '__main__': main()
