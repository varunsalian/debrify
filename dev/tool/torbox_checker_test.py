#!/usr/bin/env python3
"""Mutate real TorBox declarations under the real production configuration."""
import copy
import csv
import json
import re
import subprocess
from pathlib import Path


def self_test(package=None):
    from check_settings_moves import ROOT, all_nodes, check, tokens
    from check_verbatim_moves import parse
    from torbox_callback_identity import arguments, check_callback_identities
    fixtures = Path(__file__).with_name('torbox_verbatim_fixtures')
    config = json.loads((ROOT / 'dev/tool/torbox_checker_config.json').read_text())
    # The fixture override file contains paths only; ownership, TorBox getters,
    # baseline, lifecycle, accessor, and normalization are production settings.
    overrides = json.loads((fixtures / 'config.json').read_text())
    assert set(overrides) <= {'source', 'feature', 'sidecars'}
    config.update(overrides)
    rows = list(csv.DictReader((ROOT / 'dev/tool/torbox_manifest.tsv').open(), delimiter='\t'))
    source = config['source']
    original = subprocess.run(['git', 'show', config['baseline'] + ':' + source],
                              cwd=ROOT, capture_output=True, text=True, check=True).stdout
    sources = {source: (ROOT / source).read_text()}
    sources.update({str(p.relative_to(ROOT)): p.read_text()
                    for p in (ROOT / config['feature']).rglob('*.dart')})
    lookup = all_nodes(parse(sources, package))
    errors = check(original, sources, rows, source, package, context_guard=True, config=config)
    assert not errors, 'Real TorBox positive fixture: ' + str(errors)
    print('TorBox real configuration positive fixture: PASS')

    def located(name):
        row = next(r for r in rows if r['original_name'] == name)
        key = (row['destination_file'], row['destination_class'], row['new_name'])
        if key not in lookup:
            owner, _, leaf = name.rpartition('.')
            key = (source, owner, leaf)
        return key, lookup[key]

    for case in json.loads((fixtures / 'cases.json').read_text()):
        key, node = located(case['member'])
        changed = dict(sources)
        text = node['text']
        if case['mutation'] == 'dispose_order':
            calls = list(re.finditer(r'[\w.]+\.dispose\(\);', text))
            first, second = calls[:2]
            text = text[:first.start()] + second.group() + text[first.end():second.start()] + first.group() + text[second.end():]
        elif case['mutation'] == 'duplicate_owner':
            changed['fixture_duplicate.dart'] = 'class DuplicateTorboxOwner { ' + text + ' }'
        elif case['mutation'] == 'wrong_fetch_pair':
            text = text.replace('_fetchTorrents(', '_fetchWebDownloads(').replace('fetchTorrents(', 'fetchWebDownloads(')
            assert text != node['text']
        else:
            old, new = case['before'], case['after']
            assert old in text, (case['name'], text)
            text = text.replace(old, new, 1)
        if case['mutation'] != 'duplicate_owner':
            changed[key[0]] = changed[key[0]][:node['start']] + text + changed[key[0]][node['end']:]
        errors = check(original, changed, rows, source, package, context_guard=True, config=config)
        assert errors, 'TorBox accepted ' + case['name']
        print('TorBox real fixture ' + case['name'] + ': rejected')

    accessor_key = (source, '', 'torboxDownloadsTestAccess')
    accessor = lookup[accessor_key]
    match = re.search(r"('findFirstEpisodeIndex':\s*)([^,]+)(,)", accessor['text'])
    assert match
    for label, replacement in [('wrapped accessor tear-off', '() => ' + match[2] + '()'),
                               ('wrong accessor member', match[2].replace('findFirstEpisodeIndex', 'extractLeadingNumber'))]:
        text = accessor['text'][:match.start(2)] + replacement + accessor['text'][match.end(2):]
        changed = dict(sources)
        changed[source] = sources[source][:accessor['start']] + text + sources[source][accessor['end']:]
        assert check(original, changed, rows, source, package, context_guard=True, config=config), label
        print('TorBox real fixture ' + label + ': rejected')

    # Inspect resolved identities directly so scaffold/token failures cannot
    # conceal a broken callback checker. Every scroll/back/TV pair gets both
    # negatives, including a second receiver of the SAME owning class.
    for spec in config['callback_identities']:
        site = spec['sites'][1]
        key, node = located(site['member'])
        calls = arguments(tokens(node), site['call'])
        argument = calls[site.get('occurrence', 0)][site['argument']]
        for label, replacement in [('wrapping closure', ['(', ')', '=>', *argument, '(', ')']),
                                   ('same-class receiver swap', ['secondInstance', '.', argument[-2] if argument[-1] == '!' else argument[-1]])]:
            mutated = copy.deepcopy(lookup)
            values = tokens(mutated[key])
            # Replace precisely the callback argument in the selected call.
            occurrence = site.get('occurrence', 0)
            count = 0
            for i, value in enumerate(values):
                if value != site['call'] or values[i + 1:i + 2] != ['(']:
                    continue
                if count != occurrence:
                    count += 1
                    continue
                a = i + 2
                for _ in range(site['argument']):
                    a = values.index(',', a) + 1
                b = a + len(argument)
                values[a:b] = replacement
                mutated[key]['tokens'] = [{'text': t, 'offset': i} for i, t in enumerate(values)]
                mutated[key]['formatCommas'] = []
                break
            identity_errors = check_callback_identities(mutated, rows, source, config)
            assert identity_errors, f"Accepted {spec['name']} {label}"
            print(f"TorBox callback {spec['name']} {label}: rejected")


if __name__ == '__main__':
    self_test()
