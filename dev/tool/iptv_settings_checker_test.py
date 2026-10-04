#!/usr/bin/env python3
"""Original/moved real-config fixtures, including direct named callbacks."""
import copy
import csv
import json
import re
import subprocess
from pathlib import Path


def self_test(package=None):
    from check_settings_moves import ROOT, all_nodes, check, tokens
    from check_verbatim_moves import parse
    from torbox_callback_identity import arguments, callback_argument, check_callback_identities
    config = json.loads((ROOT / 'dev/tool/iptv_settings_checker_config.json').read_text())
    fixtures = ROOT / 'dev/tool/iptv_settings_verbatim_fixtures'
    override = json.loads((fixtures / 'config.json').read_text())
    assert set(override) <= {'source', 'feature', 'sidecars'}
    config.update(override)
    rows = list(csv.DictReader((ROOT / 'dev/tool/iptv_settings_manifest.tsv').open(), delimiter='\t'))
    source = config['source']
    original = subprocess.check_output(['git', 'show', config['baseline'] + ':' + source], cwd=ROOT, text=True)
    sources = {source: (ROOT / source).read_text()}
    sources.update({str(p.relative_to(ROOT)): p.read_text() for p in (ROOT / config['feature']).rglob('*.dart')})
    lookup = all_nodes(parse(sources, package))
    assert not check(original, sources, rows, source, package, context_guard=True, config=config)
    print('IPTV settings real configuration positive: PASS')

    # An interpolated subtitle precedes a direct callback, just as in the hub.
    # Invoke the identity checker alone so the verbatim checker cannot mask it.
    # Keep the standalone parser probes independent of the move stage.
    probe = ['SettingsTile', '(', 'subtitle', ':', "'prefix", '${', 'count', '}', "suffix'", ',', 'onTap', ':', '_pickAutoRefresh', ')']
    assert arguments(['RadioListTile', '<', 'String', '>', '(', 'onChanged', ':', '_setStartupMode', ')'], 'RadioListTile') == [[['onChanged', ':', '_setStartupMode']]]
    parsed = arguments(probe, 'SettingsTile')
    assert len(parsed) == 1
    assert callback_argument(parsed[0], {'named_argument': 'onTap'}) == ['_pickAutoRefresh']
    hub_row = next(r for r in rows if r['original_name'] == '_IptvSettingsPageState._buildPhoneHub')
    hub_key = (hub_row['destination_file'], hub_row['destination_class'], hub_row['new_name'])
    if hub_key not in lookup:
        hub_key = (source, '_IptvSettingsPageState', '_buildPhoneHub')
    hub_calls = arguments(tokens(lookup[hub_key]), 'SettingsTile')
    assert len(hub_calls) == 12
    hub_arg = callback_argument(hub_calls[1], {'named_argument': 'onTap'})
    interpolated = [*probe[:-2], *hub_arg, ')']
    fixture_config = copy.deepcopy(config)
    fixture_config['callback_identities'] = [{'name': 'interpolated argument callback', 'callback_member': '_IptvSettingsPageState._pickAutoRefresh', 'sites': [{'member': '_IptvSettingsPageState._buildPhoneHub', 'call': 'SettingsTile', 'named_argument': 'onTap'}]}]
    mutated = copy.deepcopy(lookup)
    mutated[hub_key]['tokens'] = [{'text': t, 'offset': i} for i, t in enumerate(interpolated)]
    mutated[hub_key]['formatCommas'] = []
    assert not check_callback_identities(mutated, rows, source, fixture_config)
    for replacement in [
        [*hub_arg[:-1], 'wrongCallback'],
        ['secondInstance', '.', hub_arg[-1]],
        ['(', ')', '=>', *hub_arg, '(', ')'],
    ]:
        poisoned = [*probe[:-2], *replacement, ')']
        mutated[hub_key]['tokens'] = [{'text': t, 'offset': i} for i, t in enumerate(poisoned)]
        assert check_callback_identities(mutated, rows, source, fixture_config), replacement
    print('IPTV settings interpolated-argument positive and identity negatives: PASS')

    # Narrow dependency records bind the original receiver's tear-off, or read
    # an original getter lazily. Check these aliases without scaffold/token
    # checks, on both original and moved trees.
    for getter in (False, True):
        member = 'value' if getter else 'action'
        owner = 'BoundSection'
        synthetic_rows = [
            {'original_name': '_State.site', 'destination_file': 'bound.dart',
             'destination_class': owner, 'new_name': 'site'},
            {'original_name': '_State.' + member, 'destination_file': 'bound.dart',
             'destination_class': owner, 'new_name': member},
        ]
        canonical = '$State._sections.bound.' + member
        bound_config = {
            'callback_instances': {owner: '$State._sections.bound'},
            'callback_receiver_aliases': {'_deps.' + member: canonical},
            'callback_getter_aliases': {'_deps.' + member + '()': canonical},
            'callback_identities': [{'name': 'bound ' + member,
                'callback_member': '_State.' + member,
                'sites': [{'member': '_State.site', 'call': 'Tile',
                           'named_argument': 'value'}]}],
        }
        expression = ['_deps', '.', member] + (['(', ')'] if getter else [])
        def bound_lookup(argument):
            values = ['Tile', '(', 'value', ':', *argument, ')']
            return {
                ('bound.dart', owner, 'site'): {'owner': owner,
                    'tokens': [{'text': t, 'offset': i} for i, t in enumerate(values)],
                    'formatCommas': []},
                ('bound.dart', owner, member): {'owner': owner, 'name': member,
                    'parameters': None if getter else '()'},
            }
        assert not check_callback_identities(bound_lookup(expression), synthetic_rows, source, bound_config)
        invalid = [
            ['_deps', '.', 'wrong'],
            ['secondInstance', '.', member],
            ['(', ')', '=>', *expression],
            [],
            ['_deps', '.', member, '(', 'unexpected', ')'],
        ]
        if not getter:
            # Even a registered getter alias must never turn a method call
            # into a valid tear-off.
            invalid.append(['_deps', '.', member, '(', ')'])
        for argument in invalid:
            assert check_callback_identities(bound_lookup(argument), synthetic_rows, source, bound_config), argument
    print('IPTV settings bound tear-off/live-getter positives and isolated negatives: PASS')

    def located(name):
        row = next((r for r in rows if r['original_name'] == name), None)
        if row is None:
            key = (source, '', name)
            return key, lookup[key]
        key = (row['destination_file'], row['destination_class'], row['new_name'])
        if key not in lookup:
            owner, _, leaf = name.rpartition('.')
            key = (source, owner, leaf or name)
        return key, lookup[key]

    for case in json.loads((fixtures / 'cases.json').read_text()):
        name = case.get('member', case.get('declaration'))
        key, node = located(name)
        changed = dict(sources)
        text = node['text']
        mutation = case.get('mutation')
        if mutation in ('dispose_first', 'dispose_last'):
            calls = [m for m in re.finditer(r'[\w.]+\.dispose\(\);', text) if m.group() != 'super.dispose();']
            assert len(calls) == 32  # 29 singles and three array-loop sites.
            first, second = calls[:2] if mutation == 'dispose_first' else calls[-2:]
            text = text[:first.start()] + second.group() + text[first.end():second.start()] + first.group() + text[second.end():]
        elif mutation == 'profile_body_split':
            text = text[:text.index('=>') + 2] + ' _runProfileAction(() => detachedSetterBody(enabled));'
        elif mutation in ('move_lifecycle', 'split_dialog'):
            changed[key[0]] = changed[key[0]][:node['start']] + changed[key[0]][node['end']:]
            changed['fixture_split.dart'] = ('class MovedLifecycle { ' + text + ' }' if mutation == 'move_lifecycle' else text)
        else:
            before = case['before']
            if before not in text:
                # Public method names/owner qualification are the only stage-dependent edits.
                before = before.replace('_onTabChanged', 'onTabChanged')
            assert before in text, case['name']
            text = text.replace(before, case['after'], 1)
        if mutation not in ('move_lifecycle', 'split_dialog'):
            changed[key[0]] = changed[key[0]][:node['start']] + text + changed[key[0]][node['end']:]
        assert check(original, changed, rows, source, package, context_guard=True, config=config), case['name']
        print('IPTV settings real fixture ' + case['name'] + ': rejected')

    # Directly invoke the identity checker: unrelated token/scaffold errors
    # cannot mask a broken named-argument resolver. Mutate every recorded site.
    for spec in config['callback_identities']:
        for site in spec['sites']:
            key, node = located(site['member'])
            values = tokens(node)
            call_name = site['call']
            call_row = next((r for r in rows if r['original_name'] == call_name), None)
            if call_row and call_row['new_name'] in values:
                call_name = call_row['new_name']
            calls = arguments(values, call_name)
            arg = callback_argument(calls[site.get('occurrence', 0)], site)
            tail = ['(', ')'] if arg[-2:] == ['(', ')'] else []
            direct = arg[:-2] if tail else arg
            changes = [
                ('wrong member', [*direct[:-1], 'wrongCallback', *tail]),
                ('wrong receiver', ['secondInstance', '.', direct[-1], *tail]),
                ('wrapping closure', ['(', ')', '=>', *arg, '(', ')']),
                ('missing argument', []),
            ]
            for label, replacement in changes:
                mutated = copy.deepcopy(lookup)
                count = 0
                for i, value in enumerate(values[:-1]):
                    if value != call_name:
                        continue
                    opening = i + 1
                    if values[opening] == '<':
                        opening = values.index('>', opening) + 1
                    if values[opening] != '(':
                        continue
                    if count != site.get('occurrence', 0):
                        count += 1
                        continue
                    if 'named_argument' in site:
                        marker = [site['named_argument'], ':', *arg]
                        start = next(j for j in range(opening + 1, len(values)) if values[j:j + len(marker)] == marker)
                        if label == 'missing argument':
                            end = start + len(marker)
                            if values[end:end + 1] == [',']:
                                end += 1
                            poisoned = values[:start] + values[end:]
                        else:
                            start += 2
                            poisoned = values[:start] + replacement + values[start + len(arg):]
                    else:
                        # Observer/listener sites have one positional argument.
                        assert site['argument'] == 0
                        start = opening + 1
                        poisoned = values[:start] + replacement + values[start + len(arg):]
                    mutated[key]['tokens'] = [{'text': t, 'offset': j} for j, t in enumerate(poisoned)]
                    mutated[key]['formatCommas'] = []
                    break
                else:
                    raise AssertionError(site)
                assert check_callback_identities(mutated, rows, source, config), (spec['name'], label)
                print('IPTV settings callback ' + spec['name'] + ' ' + label + ': rejected')


if __name__ == '__main__':
    self_test()
