#!/usr/bin/env python3
"""Real-config mutation fixtures, including named callback arguments."""
import copy
import csv
import json
import re
import subprocess
from pathlib import Path


from playlist_content_live_bindings import validate_sources as validate_live_item_binding


def self_test(package=None):
    from check_settings_moves import ROOT, all_nodes, check, tokens
    from check_verbatim_moves import parse
    from torbox_callback_identity import arguments, callback_argument, check_callback_identities
    config = json.loads((ROOT / 'dev/tool/playlist_content_checker_config.json').read_text())
    overrides = json.loads((ROOT / 'dev/tool/playlist_content_verbatim_fixtures/config.json').read_text())
    assert set(overrides) <= {'source', 'feature', 'sidecars'}
    config.update(overrides)
    rows = list(csv.DictReader((ROOT / 'dev/tool/playlist_content_manifest.tsv').open(), delimiter='\t'))
    source = config['source']
    original = subprocess.check_output(['git', 'show', config['baseline'] + ':' + source], cwd=ROOT, text=True)
    sources = {source: (ROOT / source).read_text()}
    sources.update({str(p.relative_to(ROOT)): p.read_text() for p in (ROOT / config['feature']).rglob('*.dart')})
    lookup = all_nodes(parse(sources, package))
    assert not check(original, sources, rows, source, package, context_guard=True, config=config)
    assert not validate_live_item_binding(sources)
    print('Playlist content real configuration positive fixture: PASS')

    def located(name):
        row = next(r for r in rows if r['original_name'] == name)
        key = (row['destination_file'], row['destination_class'], row['new_name'])
        if key not in lookup:
            owner, _, leaf = name.rpartition('.')
            key = (source, owner, leaf)
        return key, lookup[key]

    for case in json.loads((ROOT / 'dev/tool/playlist_content_verbatim_fixtures/cases.json').read_text()):
        key, node = located(case['member'])
        changed = dict(sources)
        text = node['text']
        if case['mutation'] == 'move_lifecycle':
            changed[key[0]] = changed[key[0]][:node['start']] + changed[key[0]][node['end']:]
            changed['fixture_moved_lifecycle.dart'] = 'class PlaylistContentMovedLifecycle { ' + text + ' }'
        elif case['mutation'] == 'dispose_order':
            calls = list(re.finditer(r'[\w.]+\.dispose\(\);', text))
            assert len(calls) == 8
            a, b = calls[:2]
            text = text[:a.start()] + b.group() + text[a.end():b.start()] + a.group() + text[b.end():]
        elif case['mutation'] == 'wrong_timer_owner':
            if 'scrollRetryTimer' in text and '_scrollRetryTimer' not in text:
                text = text.replace('scrollRetryTimer', 'ottViewAutoSwitchTimer', 1)
            else:
                text = text.replace('_scrollRetryTimer', '_ottViewAutoSwitchTimer', 1)
        elif case['mutation'] == 'drop_callback':
            text, count = re.subn(r'(?:widget\.onPlaybackStarted|_deps\.onPlaybackStarted\(\))\?\.call\(\);', '', text, count=1)
            assert count == 1
        elif case['mutation'] == 'drop_notify':
            assert 'MainPageBridge.notifyPlayerLaunching();' in text
            text = text.replace('MainPageBridge.notifyPlayerLaunching();', '', 1)
        elif case['mutation'] == 'duplicate_owner':
            changed['fixture_duplicate.dart'] = 'class PlaylistContentDuplicate { ' + text + ' }'
        else:
            before = case['before']
            if before == '_initializeScreen();' and before not in text:
                init_key, init_node = located('_PlaylistContentViewScreenState._initializeScreen')
                assert init_key[0] != source
                section = init_node['owner'].removeprefix('PlaylistContent')
                section = section[0].lower() + section[1:]
                before = '_sections.' + section + '.' + init_node['name'] + '();'
            assert before in text, case
            text = text.replace(before, case['after'], 1)
        if case['mutation'] not in ('move_lifecycle', 'duplicate_owner'):
            changed[key[0]] = changed[key[0]][:node['start']] + text + changed[key[0]][node['end']:]
        errors = check(original, changed, rows, source, package, context_guard=True, config=config)
        assert errors, 'Accepted real fixture ' + case['name']
        print('Playlist content fixture ' + case['name'] + ': rejected')

    # Prove the callback rule itself catches wrappers and another instance of
    # the same class. Full move/token/scaffold failures cannot mask this rule.
    for spec in config['callback_identities']:
        for site in spec['sites']:
            key, node = located(site['member'])
            calls = arguments(tokens(node), site['call'])
            occurrence = site.get('occurrence', 0)
            expr = callback_argument(calls[occurrence], site['argument'])
            for label, replacement in [('wrapping closure', ['(', ')', '=>', *expr, '(', ')']),
                                       ('same-class receiver swap', ['secondInstance', '.', expr[-1]])]:
                mutated = copy.deepcopy(lookup)
                values = tokens(mutated[key])
                indices = [i for i, v in enumerate(values[:-1]) if v == site['call'] and values[i + 1] == '(']
                start = indices[occurrence] + 2
                position = next(i for i in range(start, len(values)) if values[i:i + len(expr)] == expr)
                values[position:position + len(expr)] = replacement
                mutated[key]['tokens'] = [{'text': t, 'offset': i} for i, t in enumerate(values)]
                mutated[key]['formatCommas'] = []
                assert check_callback_identities(mutated, rows, source, config), (spec['name'], label)
                print('Playlist content callback ' + spec['name'] + ' ' + site['member'] + ' ' + label + ': rejected')
            if isinstance(site['argument'], str):
                mutated = copy.deepcopy(lookup)
                values = tokens(mutated[key])
                position = next(i for i in range(start, len(values)) if values[i:i + 2] == [site['argument'], ':'])
                values[position] = 'wrongNamedArgument'
                mutated[key]['tokens'] = [{'text': t, 'offset': i} for i, t in enumerate(values)]
                mutated[key]['formatCommas'] = []
                assert check_callback_identities(mutated, rows, source, config)
                print('Playlist content named callback ' + spec['name'] + ': wrong label rejected')

    # A callback stored directly in a narrow dependency record is still the
    # original tear-off. Exact aliases are allowed only with pinned wiring.
    spec = next(s for s in config['callback_identities'] if s['name'] == 'Refresh and Retry direct tear-offs')
    site = spec['sites'][0]
    key, node = located(site['member'])
    target_key, target = located(spec['callback_member'])
    expected = config['callback_instances'].get(target['owner'], '$State') + '.' + target['name']
    aliased = copy.deepcopy(lookup)
    values = tokens(aliased[key])
    calls = arguments(values, site['call'])
    expr = callback_argument(calls[site.get('occurrence', 0)], site['argument'])
    positions = [i for i, v in enumerate(values[:-1]) if v == site['call'] and values[i + 1] == '(']
    start = positions[site.get('occurrence', 0)] + 2
    position = next(i for i in range(start, len(values)) if values[i:i + len(expr)] == expr)
    alias = ['_deps', '.', 'testAliasedCallback']
    values[position:position + len(expr)] = alias
    aliased[key]['tokens'] = [{'text': t, 'offset': i} for i, t in enumerate(values)]
    aliased[key]['formatCommas'] = []
    alias_config = copy.deepcopy(config)
    alias_config['callback_receiver_aliases']['_deps.testAliasedCallback'] = expected
    assert not check_callback_identities(aliased, rows, source, alias_config)
    swapped = copy.deepcopy(aliased)
    vals = tokens(swapped[key]); vals[position] = 'secondDepsInstance'
    swapped[key]['tokens'] = [{'text': t, 'offset': i} for i, t in enumerate(vals)]
    assert check_callback_identities(swapped, rows, source, alias_config)
    print('Playlist content exact dependency-record tear-off: PASS; receiver swap rejected')

    positive = {'binding': 'final Map<String, dynamic> Function() playlistItem;\nPlaylistContentFixture((\nplaylistItem: () => widget.playlistItem,\n));\n'}
    assert not validate_live_item_binding(positive)
    for label, text in [('nullable return', positive['binding'].replace('dynamic>', 'dynamic>?')),
                        ('copied map', positive['binding'].replace('() => widget.playlistItem', '() => Map<String, dynamic>.from(widget.playlistItem)')),
                        ('cached map', positive['binding'].replace('() => widget.playlistItem', '() => widget.playlistItemCached'))]:
        assert validate_live_item_binding({'binding': text}), label
        print('Playlist content live getter ' + label + ': rejected')

    callback = {'binding': 'final VoidCallback? Function() onPlaybackStarted;\nPlaylistContentFixture((\nonPlaybackStarted: () => widget.onPlaybackStarted,\n));\n'}
    assert not validate_live_item_binding(callback)
    for label, binding in [
        ('non-null callback', callback['binding'].replace('VoidCallback?', 'VoidCallback')),
        ('nullable getter', callback['binding'].replace('Function()', 'Function()?')),
        ('cached callback', callback['binding'].replace('() => widget.onPlaybackStarted', '() => cachedCallback')),
        ('eager callback', callback['binding'].replace('() => widget.onPlaybackStarted', 'widget.onPlaybackStarted')),
    ]:
        assert validate_live_item_binding({'binding': binding}), label
        print('Playlist content live onPlaybackStarted ' + label + ': rejected')

    from playlist_content_live_bindings import COMPOSITION
    forwarding = ('final Map<String, dynamic> Function() playlistItem;\n'
                  'final VoidCallback? Function() onPlaybackStarted;\n'
                  'PlaylistContentFixture((\nplaylistItem: _deps.playlistItem,\n'
                  'onPlaybackStarted: _deps.onPlaybackStarted,\n));\n')
    assert not validate_live_item_binding({COMPOSITION: forwarding})
    for getter in ['playlistItem', 'onPlaybackStarted']:
        for label, replacement in [('eager forwarding', '_deps.' + getter + '()'),
                                   ('cached forwarding', '_deps.cached' + getter),
                                   ('wrapper forwarding', '() => _deps.' + getter + '()')]:
            bad = forwarding.replace(getter + ': _deps.' + getter + ',', getter + ': ' + replacement + ',')
            assert validate_live_item_binding({COMPOSITION: bad}), (getter, label)
            print('Playlist content composition ' + getter + ' ' + label + ': rejected')
    assert validate_live_item_binding({'wrong_factory.dart': forwarding})
    print('Playlist content typed getter forwarding: PASS; wrong factory rejected')

    from check_settings_moves import configured, check_plain_sections, check_forwarder
    row = next(r for r in rows if r['original_name'].endswith('.build'))
    original_lookup = all_nodes(parse({source: original}, package))
    before = original_lookup[(source, '_PlaylistContentViewScreenState', 'build')]
    root_spec = {'file': row['destination_file'], 'owner': row['destination_class']}
    root_key = (root_spec['file'], '', root_spec['owner'])
    if root_key in lookup:
        good = dict(sources)
        root = lookup[root_key]
        bad = dict(sources)
        bad[root_key[0]] = sources[root_key[0]][:root['start']] + root['text'].replace('class ' + root_spec['owner'] + ' {', 'class ' + root_spec['owner'] + ' extends StatelessWidget {', 1) + sources[root_key[0]][root['end']:]
        good_lookup, bad_lookup = lookup, all_nodes(parse(bad, package))
    else:
        body = re.sub(r'@override\s*', '', before['text'], count=1)
        plain = 'class ' + root_spec['owner'] + ' { ' + body + ' }'
        good_lookup = all_nodes(parse({root_spec['file']: plain}, package))
        bad_lookup = all_nodes(parse({root_spec['file']: plain.replace(' {', ' extends StatelessWidget {', 1)}, package))
    c = copy.deepcopy(config); c['plain_sections'] = [root_spec]
    with configured(c):
        assert not check_plain_sections(good_lookup)
        assert check_plain_sections(bad_lookup)
    prefix = before['text'][:before['bodyOffset'] - before['start']]
    spec = config['forwarders'].get(row['original_name'], {'receiver': '_sections.rootLayout'})
    forward = prefix + '=> ' + spec['receiver'] + '.' + row['new_name'] + '(context);'
    def node(text):
        return parse({'forward': 'class Facade { ' + text + ' }'}, package)['forward']['declarations'][0]['members'][0]
    assert not check_forwarder(before, node(forward), row, spec, package)
    assert check_forwarder(before, node(forward.replace('(context);', '(otherContext);')), row, spec, package)
    print('Playlist content root widget / wrong-context forwarder: rejected')


if __name__ == '__main__':
    self_test()
