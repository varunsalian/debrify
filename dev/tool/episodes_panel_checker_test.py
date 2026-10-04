#!/usr/bin/env python3
"""Real episodes-panel configuration positives and independent mutation proofs."""
import copy
import csv
import json
import re
import subprocess
from pathlib import Path


def self_test(package=None):
    from check_settings_moves import ROOT, all_nodes, check, configured, tokens
    from check_verbatim_moves import parse
    from torbox_callback_identity import argument_ranges, check_callback_identities, member_occurrences
    config = json.loads((ROOT / 'dev/tool/episodes_panel_checker_config.json').read_text())
    rows = list(csv.DictReader((ROOT / 'dev/tool/episodes_panel_manifest.tsv').open(), delimiter='\t'))
    source = config['source']
    original = subprocess.run(['git', 'show', config['baseline'] + ':' + source], cwd=ROOT, capture_output=True, text=True, check=True).stdout
    sources = {source: (ROOT / source).read_text()}
    sources.update({str(path.relative_to(ROOT)): path.read_text() for path in (ROOT / config['feature']).rglob('*.dart')})
    lookup = all_nodes(parse(sources, package))

    def checked(changed):
        return check(original, changed, rows, source, package, context_guard=True, config=config)

    assert not checked(sources), checked(sources)
    print('Episodes panel real configuration positive: PASS')

    def located(original_name):
        scaffold = config.get('callback_scaffold_members', {}).get(original_name)
        if scaffold:
            key = (scaffold['file'], scaffold['owner'], scaffold['name'])
            return key, lookup[key]
        row = next((r for r in rows if r['original_name'] == original_name), None)
        owner, _, member = original_name.rpartition('.')
        if row is None:
            row = next(r for r in rows if r['original_name'] == owner)
            key = (row['destination_file'], row['new_name'], member)
        else:
            key = (row['destination_file'], row['destination_class'], row['new_name'])
        if key not in lookup:
            key = (source, owner, member) if owner else (source, '', original_name)
        return key, lookup[key]

    def mutate(original_name, label, transform):
        key, node = located(original_name)
        changed_text = transform(node['text'])
        assert changed_text != node['text'], label
        changed = dict(sources)
        changed[key[0]] = sources[key[0]][:node['start']] + changed_text + sources[key[0]][node['end']:]
        assert checked(changed), 'Accepted ' + label
        print('Episodes real fixture ' + label + ': rejected')

    state = 'EpisodesPanelState.'
    _, disposal = located(state + 'dispose')
    removals = list(re.finditer(r'[\w.]+\.removeListener\([\s\S]*?\);', disposal['text']))
    assert len(removals) == 3
    for index, match in enumerate(removals):
        mutate(state + 'dispose', f'listener removal #{index}', lambda text, m=match: text[:m.start()] + text[m.end():])
    # Pin the first two and final two protocol steps, including the final super.
    def swap(text, first, second):
        a, b = text.index(first), text.index(second)
        assert a < b
        return text[:a] + second + text[a + len(first):b] + first + text[b + len(second):]
    mutate(state + 'dispose', 'first disposal steps', lambda text: swap(text, removals[0].group(), removals[1].group()))
    mutate(state + 'dispose', 'last disposal steps', lambda text: text.replace('    super.dispose();', '').replace('for (final node', 'super.dispose();\n    for (final node', 1))
    mutate(state + 'initState', 'new didUpdateWidget', lambda text: text + '\n void didUpdateWidget(EpisodesPanel oldWidget) {}')
    mutate(state + '_episodeSeasonDropdownFocusNode', 'changed debug label', lambda text: text.replace("'catalog-ep-season'", "'changed-ep-season'"))
    mutate(state + '_onEpisodeTap', 'before-terminal order', lambda text: re.sub(r'([^\n]*onBeforeTerminalDispatch[^\n]*\n)([^\n]*onItemSelected[^\n]*\n)', r'\2\1', text))
    mutate(state + '_onEpisodeQuickPlay', 'quick/item swap', lambda text: text.replace('onQuickPlay', 'swapCallback').replace('onItemSelected', 'onQuickPlay').replace('swapCallback', 'onItemSelected'))
    mutate(state + '_setEpisodeWatchedEverywhere', 'reworded moved comment', lambda text: text.replace('Unwatch always changes', 'Unwatch definitely changes', 1))
    mutate(state + '_buildEpisodeFiltersBar', 'new const', lambda text: text.replace('return Padding(', 'return const Padding(', 1))
    mutate('EpisodesPanel', 'public whitespace byte', lambda text: text.replace('class EpisodesPanel extends', 'class EpisodesPanel  extends', 1))
    for group in config['adjacent_declarations']:
        key, node = located(group[1])
        changed = dict(sources)
        # A declaration inserted between the original fields and their method.
        changed[key[0]] = sources[key[0]][:node['end']] + '\nint fixtureSeparatedField = 0;\n' + sources[key[0]][node['end']:]
        assert checked(changed), 'Accepted separated mid-class fields'
        print('Episodes mid-class adjacency negative: rejected')
    # Constructor exports are lint bridges; exact target changes are rejected.
    for path, name, target in [
        ('lib/features/episodes_panel/presentation/episodes_panel_source_button.dart',
         'episodesPanelSourceButtonConstructor', '_CatalogSelectSourceButton'),
        ('lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_compact_row.dart',
         'episodesPanelCompactRowConstructor', '_CompactEpisodeRow'),
    ]:
        if config['completed_step'] >= 2:
            key = (path, '', name)
            node = lookup[key]
            changed = dict(sources)
            replacement = node['text'].replace(target + '.new', '_SeasonStepButton.new')
            assert replacement != node['text']
            changed[path] = sources[path][:node['start']] + replacement + sources[path][node['end']:]
            assert checked(changed), 'Accepted changed constructor export target'
            print('Episodes exact constructor export target:', name, 'rejected')
    if config['completed_step'] >= 3:
        accessors = [
            ((source, 'EpisodesPanelState', '_s'), '_parts.viewState'),
            ((source, 'EpisodesPanelState', '_r'), '_parts.resources'),
        ]
        if config['completed_step'] >= 5:
            # The navigation borrower moves out of State with the builders.
            state_key = (source, 'EpisodesPanelState', '_n')
            key = state_key if state_key in lookup else next(
                key for key in sorted(lookup) if key[2] == '_n')
            accessors.append((key, '_parts.navigation' if key == state_key else '_deps.parts.navigation'))
        for key, receiver in accessors:
            node = lookup[key]
            changed = dict(sources)
            swapped = node['text'].replace(receiver, 'secondParts.' + receiver.split('.')[-1])
            assert swapped != node['text']
            changed[key[0]] = sources[key[0]][:node['start']] + swapped + sources[key[0]][node['end']:]
            assert checked(changed), 'Accepted borrowed record accessor swap'
            print('Episodes borrowed accessor same-class record swap:', key[1:], 'rejected')
    if config['completed_step'] >= 4:
        key = ('lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_progress.dart', 'EpisodesPanelProgress', 'mounted')
        node = lookup[key]
        changed = dict(sources)
        cached = node['text'].replace('_deps.mounted()', 'false')
        assert cached != node['text']
        changed[key[0]] = sources[key[0]][:node['start']] + cached + sources[key[0]][node['end']:]
        assert checked(changed), 'Accepted cached borrowed mounted value'
        print('Episodes borrowed mounted live getter cached value: rejected')
    deps_path = 'lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_deps.dart'
    if config['completed_step'] >= 3:
        key, node = located('EpisodesPanelState.EpisodesPanelState')
        changed = dict(sources)
        cached = node['text'].replace('() => widget.show,', '() => initialShow,', 1)
        assert cached != node['text']
        changed[key[0]] = sources[key[0]][:node['start']] + cached + sources[key[0]][node['end']:]
        assert checked(changed), 'Accepted cached widget getter'
        from check_settings_moves import check_live_widget_factory
        assert check_live_widget_factory(all_nodes(parse(changed, package)), config)
        print('Episodes actual factory cached widget property: rejected independently')
    if config['completed_step'] in (4, 5):
        expired = copy.deepcopy(config)
        expired['completed_step'] = 6
        failures = check(original, sources, rows, source, package, context_guard=True, config=expired)
        assert any('Live getter alias must name one retained facade getter' in error for error in failures)
        for alias, retained in config['live_getter_aliases'].items():
            missing = dict(sources)
            key, node = located(retained)
            missing[key[0]] = sources[key[0]][:node['start']] + sources[key[0]][node['end']:]
            assert any('Live getter alias must name one retained facade getter: ' + alias in error for error in checked(missing))
            print('Episodes staged live getter missing original facade getter:', alias, 'rejected')
        print('Episodes staged live getter expired step: rejected')
    # The actual config's factory is exercised even before composition lands.
    from check_settings_moves import check_live_widget_factory
    fixture_config = {**config, 'completed_step': 3}
    slots = ', '.join(name + ': () => widget.' + name for name in config['live_widget_getters'])
    factory = 'class EpisodesPanelState { EpisodesPanelState() { final deps = EpisodesPanelDeps(' + slots + '); } }'
    fixture_lookup = all_nodes(parse({source: factory}, package))
    assert not check_live_widget_factory(fixture_lookup, fixture_config)
    for property_name in config['live_widget_getters']:
        cached = factory.replace('() => widget.' + property_name + ',', '() => initialValue,', 1)
        if cached == factory:
            cached = factory.replace('() => widget.' + property_name + ')', '() => initialValue)', 1)
        assert cached != factory
        bad_lookup = all_nodes(parse({source: cached}, package))
        assert check_live_widget_factory(bad_lookup, fixture_config), property_name
    assert check_live_widget_factory({}, fixture_config)
    print('Episodes actual-config live getter factory positive, 23 cached getters and missing factory: rejected')
    # Resolver-only negatives: whole-leaf token failures must not mask identity.
    with configured(config):
        assert not check_callback_identities(lookup, rows, source, config)
        for spec in config['callback_identities']:
            for site in spec['sites']:
                key, node = located(site['member'])
                values = tokens(node)
                if 'assignment_property' in site:
                    start = values.index(site['assignment_property']) + 2
                    end = values.index(';', start)
                elif site.get('invocation'):
                    target = site['call']
                    start = next(i for i in range(len(values)-2) if values[i:i+3] == [target, '(', ')'])
                    end = start + 1
                    while start >= 2 and values[start-1] == '.': start -= 2
                else:
                    spans = argument_ranges(values, site['call'])[site.get('occurrence', 0)]
                    selector = site['argument']
                    if isinstance(selector, int): start, end = spans[selector]
                    else:
                        selected = [(a,b) for a,b in spans if [v for v in values[a:b] if not v.startswith(('//','/*'))][:2] == [selector, ':']]
                        assert len(selected) == 1
                        start, end = selected[0]
                        start = values.index(':', start, end) + 1
                    while start < end and values[start].startswith(('//','/*')): start += 1
                    if 'conditional_member' in site:
                        _, target = located(site['conditional_member'])
                        positions = [start+i for i in member_occurrences(values[start:end], target['name'])]
                        end = positions[site.get('branch_occurrence',0)] + 1
                        start = end - 1
                        while start >= 2 and values[start-1] == '.': start -= 2
                expr = values[start:end]
                replacements = [('wrapper', ['(', ')', '=>', *expr, '(', ')']), ('same-class receiver swap', ['secondInstance', '.', expr[-1]])]
                for label, replacement in replacements:
                    bad = copy.deepcopy(lookup)
                    vals = values[:start] + replacement + values[end:]
                    bad[key]['tokens'] = [{'text':value, 'offset':i, 'comment':value.startswith(('//','/*'))} for i,value in enumerate(vals)]
                    bad[key]['formatCommas'] = []
                    assert check_callback_identities(bad, rows, source, {**config, 'callback_identities':[spec]}), f'Accepted {spec["name"]} {label}'
                    print(f'Episodes callback {spec["name"]} {site.get("call", "assignment")} #{site.get("occurrence",0)} {label}: rejected')
        # Distinct same-class receivers on the two policy adds cannot compare equal.
        first, second = config['callback_identities'][:2]
        assert first['callback_member'] == second['callback_member']
        bad = copy.deepcopy(lookup)
        key, node = located(state + 'initState')
        vals = tokens(node)
        a,b = argument_ranges(vals, 'addListener')[1][0]
        vals[a:b] = ['secondPolicyOwner', '.', vals[b-1]]
        bad[key]['tokens'] = [{'text':v,'offset':i,'comment':v.startswith(('//','/*'))} for i,v in enumerate(vals)]
        bad[key]['formatCommas'] = []
        assert check_callback_identities(bad, rows, source, {**config,'callback_identities':[first,second]})
        print('Episodes two policy adds different owner instances: rejected')

if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--parser-package', type=Path, required=True)
    self_test(parser.parse_args().parser_package)
