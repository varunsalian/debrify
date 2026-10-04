#!/usr/bin/env python3
"""Mutate real PikPak declarations under the real production configuration."""
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
    fixtures = Path(__file__).with_name('pikpak_verbatim_fixtures')
    config = json.loads((ROOT / 'dev/tool/pikpak_checker_config.json').read_text())
    # The fixture override file contains paths only; ownership, PikPak getters,
    # baseline, lifecycle, accessor, and normalization are production settings.
    overrides = json.loads((fixtures / 'config.json').read_text())
    assert set(overrides) <= {'source', 'feature', 'sidecars'}
    config.update(overrides)
    rows = list(csv.DictReader((ROOT / 'dev/tool/pikpak_manifest.tsv').open(), delimiter='\t'))
    source = config['source']
    original = subprocess.run(['git', 'show', config['baseline'] + ':' + source],
                              cwd=ROOT, capture_output=True, text=True, check=True).stdout
    sources = {source: (ROOT / source).read_text()}
    sources.update({str(p.relative_to(ROOT)): p.read_text()
                    for p in (ROOT / config['feature']).rglob('*.dart')})
    lookup = all_nodes(parse(sources, package))
    errors = check(original, sources, rows, source, package, context_guard=True, config=config)
    assert not errors, 'Real PikPak positive fixture: ' + str(errors)
    print('PikPak real configuration positive fixture: PASS')

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
        if case['mutation'] in ('dispose_order', 'dispose_order_last'):
            calls = list(re.finditer(r'[\w.]+\.dispose\(\);', text))
            resources = [call for call in calls if call.group() != 'super.dispose();']
            assert len(resources) == 14
            first, second = (resources[-2:] if case['mutation'] == 'dispose_order_last'
                             else resources[:2])
            text = text[:first.start()] + second.group() + text[first.end():second.start()] + first.group() + text[second.end():]
        elif case['mutation'] == 'duplicate_owner':
            changed['fixture_duplicate.dart'] = 'class DuplicatePikpakOwner { ' + text + ' }'
        elif case['mutation'] == 'move_lifecycle':
            changed[key[0]] = changed[key[0]][:node['start']] + changed[key[0]][node['end']:]
            changed['fixture_moved_lifecycle.dart'] = 'class PikpakMovedLifecycle { ' + text + ' }'
        elif case['mutation'] == 'wrong_owner_receiver':
            receiver = re.search(r'([A-Za-z_]\w*)\.scrollController\.addListener', text)
            if receiver:
                # Swap an existing State owner, rather than adding a statement.
                text = text[:receiver.start(1)] + '_search' + text[receiver.end(1):]
            else:
                assert '_scrollController.addListener' in text
                text = text.replace('_scrollController.addListener', '_searchController.addListener', 1)
        elif case['mutation'] == 'wrong_fetch_pair':
            text = text.replace('_loadFiles(', '_loadMoreFiles(').replace('loadFiles(', 'loadMoreFiles(')
            assert text != node['text']
        else:
            old, new = case['before'], case['after']
            assert old in text, (case['name'], text)
            text = text.replace(old, new, 1)
        if case['mutation'] not in ('duplicate_owner', 'move_lifecycle'):
            changed[key[0]] = changed[key[0]][:node['start']] + text + changed[key[0]][node['end']:]
        errors = check(original, changed, rows, source, package, context_guard=True, config=config)
        assert errors, 'PikPak accepted ' + case['name']
        print('PikPak real fixture ' + case['name'] + ': rejected')

    # Pending root rules use the real original build declaration until its
    # approved extraction exists; after step 6 mutate the real production root
    # and facade. Direct helper checks ensure scaffold errors cannot mask rules.
    from check_settings_moves import configured, check_plain_sections, check_forwarder
    build_row = next(r for r in rows if r['original_name'] == '_PikPakFilesScreenState.build')
    original_lookup = all_nodes(parse({source: original}, package))
    before = original_lookup[(source, '_PikPakFilesScreenState', 'build')]
    build_key, build_node = located(build_row['original_name'])
    assert all(r['contextParameter'] for r in build_node['references'] if r['name'] == 'context')
    root_spec = {'file': build_row['destination_file'], 'owner': build_row['destination_class']}
    root_config = copy.deepcopy(config)
    root_config['plain_sections'] = [root_spec]
    root_key = (root_spec['file'], '', root_spec['owner'])
    if root_key in lookup:
        root_sources = dict(sources)
        root = lookup[root_key]
        text = root['text'].replace('class ' + root_spec['owner'] + ' {',
                                    'class ' + root_spec['owner'] + ' extends StatelessWidget {', 1)
        assert text != root['text']
        root_sources[root_key[0]] = sources[root_key[0]][:root['start']] + text + sources[root_key[0]][root['end']:]
        assert check(original, root_sources, rows, source, package, context_guard=True, config=config)
        bad_root_lookup = all_nodes(parse(root_sources, package))
        good_root_lookup = lookup
    else:
        # Only a fixture: unchanged original build body, approved plain wrapper.
        body = re.sub(r'@override\s*', '', before['text'], count=1)
        plain = 'class ' + root_spec['owner'] + ' { ' + body + ' }'
        widget = plain.replace('class ' + root_spec['owner'] + ' {',
                               'class ' + root_spec['owner'] + ' extends StatelessWidget {', 1)
        good_root_lookup = all_nodes(parse({root_spec['file']: plain}, package))
        bad_root_lookup = all_nodes(parse({root_spec['file']: widget}, package))
    with configured(root_config):
        assert not check_plain_sections(good_root_lookup)
        assert check_plain_sections(bad_root_lookup)
    print('PikPak real fixture root becomes a stateless widget: rejected')

    forward_spec = config['forwarders'].get(build_row['original_name'], {'receiver': '_sections.rootLayout'})
    prefix = before['text'][:before['bodyOffset'] - before['start']]
    forward_text = prefix + '=> ' + forward_spec['receiver'] + '.' + build_row['new_name'] + '(context);'
    forward_node = parse({'forwarder': 'class Facade { ' + forward_text + ' }'}, package)['forwarder']['declarations'][0]['members'][0]
    assert not check_forwarder(before, forward_node, build_row, forward_spec, package)
    facade_key = (source, '_PikPakFilesScreenState', 'build')
    actual_forwarder = lookup[facade_key] if config['forwarders'] else forward_node
    text = actual_forwarder['text'].replace('(context);', '(otherContext);', 1)
    assert text != actual_forwarder['text']
    wrong_forwarder = parse({'forwarder': 'class Facade { ' + text + ' }'}, package)['forwarder']['declarations'][0]['members'][0]
    assert check_forwarder(before, wrong_forwarder, build_row, forward_spec, package)
    if config['forwarders']:
        changed = dict(sources)
        changed[source] = sources[source][:actual_forwarder['start']] + text + sources[source][actual_forwarder['end']:]
        assert check(original, changed, rows, source, package, context_guard=True, config=config)
    print('PikPak real fixture build forwarder with wrong context: rejected')

    accessor_key = (source, '', 'pikpakFilesTestAccess')
    accessor = lookup[accessor_key]
    match = re.search(r"('extractSeasonNumber':\s*)([^,]+)(,)", accessor['text'])
    assert match
    for label, replacement in [('wrapped accessor tear-off', '() => ' + match[2] + '()'),
                               ('wrong accessor member', match[2].replace('extractSeasonNumber', 'extractLeadingNumber'))]:
        text = accessor['text'][:match.start(2)] + replacement + accessor['text'][match.end(2):]
        changed = dict(sources)
        changed[source] = sources[source][:accessor['start']] + text + sources[source][accessor['end']:]
        assert check(original, changed, rows, source, package, context_guard=True, config=config), label
        print('PikPak real fixture ' + label + ': rejected')

    # Inspect resolved identities directly so scaffold/token failures cannot
    # conceal a broken callback checker. Every scroll/back/TV pair gets both
    # negatives, including a second receiver of the SAME owning class.
    for spec in config['callback_identities']:
        for site in spec['sites']:
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
                assert identity_errors, f"Accepted {spec['name']} {site} {label}"
                print(f"PikPak callback {spec['name']} {site['member']} {site['call']} #{site.get('occurrence', 0)} {label}: rejected")


if __name__ == '__main__':
    self_test()
