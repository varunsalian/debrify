#!/usr/bin/env python3
"""Mutation proofs using the actual merged-detail manifest and configuration."""
import copy
import csv
import json
import re
import subprocess
from pathlib import Path


def rewatch_adjacency(lookup, rows, source):
    keys = []
    for member in ('_rewatchTitle', '_browsePrimarySources'):
        row = next(r for r in rows if r['original_name'] == '_MergedDetailScreenState.' + member)
        key = (row['destination_file'], row['destination_class'], row['new_name'])
        if key not in lookup:
            key = (source, '_MergedDetailScreenState', member)
        keys.append(key)
    if keys[0][:2] != keys[1][:2]:
        return ['Rewatch and browse must have the same owner/file']
    members = sorted((n for key, n in lookup.items() if key[:2] == keys[0][:2]), key=lambda n: n['start'])
    names = [n['name'] for n in members]
    if keys[0][2] not in names or keys[1][2] not in names:
        return ['Missing rewatch/browse declaration']
    if names.index(keys[1][2]) != names.index(keys[0][2]) + 1:
        return ['Rewatch must immediately precede browse']
    return []


def self_test(package=None):
    from check_settings_moves import ROOT, all_nodes, check, tokens
    from check_verbatim_moves import parse
    from torbox_callback_identity import argument_expression, argument_ranges, arguments, check_callback_identities
    config = json.loads((ROOT / 'dev/tool/merged_detail_checker_config.json').read_text())
    rows = list(csv.DictReader((ROOT / 'dev/tool/merged_detail_manifest.tsv').open(), delimiter='\t'))
    source = config['source']
    original = subprocess.run(['git', 'show', config['baseline'] + ':' + source], cwd=ROOT, capture_output=True, text=True, check=True).stdout
    sources = {source: (ROOT / source).read_text()}
    feature = ROOT / config['feature']
    sources.update({str(p.relative_to(ROOT)): p.read_text() for p in feature.rglob('*.dart')})
    lookup = all_nodes(parse(sources, package))
    errors = check(original, sources, rows, source, package, context_guard=True, config=config)
    assert not errors, 'Real merged positive: ' + str(errors)
    assert not rewatch_adjacency(lookup, rows, source)
    print('Merged detail real configuration positive: PASS')
    from check_settings_moves import normalize
    for name in config.get('original_static_receivers', {}).get('_MergedDetailScreenState', []):
        row = next(r for r in rows if r['original_name'] == '_MergedDetailScreenState.' + name)
        expected = normalize(['_MergedDetailScreenState', '.', name], rows)
        assert expected == normalize([row['destination_class'], '.', row['new_name']], rows)
        assert expected != normalize(['SecondState', '.', name], rows)
    print('Merged exact original static qualifiers and receiver negatives: PASS')

    def located(member):
        row = next(r for r in rows if r['original_name'] == member)
        key = (row['destination_file'], row['destination_class'], row['new_name'])
        if key not in lookup:
            owner, _, name = member.rpartition('.')
            key = (source, owner, name)
        return key, lookup[key]

    def mutate(member, label, transform):
        key, node = located(member)
        text = transform(node['text'])
        assert text != node['text'], label
        changed = dict(sources)
        changed[key[0]] = sources[key[0]][:node['start']] + text + sources[key[0]][node['end']:]
        errors = check(original, changed, rows, source, package, context_guard=True, config=config)
        assert errors, 'Accepted ' + label
        print('Merged real fixture ' + label + ': rejected')

    state = '_MergedDetailScreenState.'
    for operation, member in [('removeListener', 'dispose'), ('removePlaybackReturnListener', 'dispose'), ('unsubscribe', 'dispose')]:
        key, node = located(state + member)
        pattern = re.compile(r'[\w.]+\.' + operation + r'\([\s\S]*?\);')
        calls = list(pattern.finditer(node['text']))
        assert len(calls) == (3 if operation == 'removeListener' else 1)
        for i in range(len(calls)):
            mutate(state + member, operation + ' deletion #' + str(i), lambda text, i=i: text[:calls[i].start()] + text[calls[i].end():])
    mutate(state + 'didChangeDependencies', 'route subscriber is not State', lambda text: text.replace('subscribe(this,', 'subscribe(otherState,'))
    for member in ('_style', '_focusCoordinator'):
        mutate(state + member, member + ' becomes eager', lambda text: text.replace('late final', 'final', 1))
        key, node = located(state + member)
        changed = dict(sources)
        changed[key[0]] = sources[key[0]][:node['start']] + sources[key[0]][node['end']:]
        changed['fixture_lazy.dart'] = 'class OtherOwner { ' + node['text'] + ' }'
        assert check(original, changed, rows, source, package, context_guard=True, config=config)
        print('Merged real fixture moved lazy ' + member + ': rejected')
    for last in (False, True):
        def reorder(text):
            calls = list(re.finditer(r'[\w.]+\.dispose\(\);', text))
            resources = [m for m in calls if m.group() != 'super.dispose();']
            first, second = resources[-2:] if last else resources[:2]
            return text[:first.start()] + second.group() + text[first.end():second.start()] + first.group() + text[second.end():]
        mutate(state + 'dispose', 'disposal last pair' if last else 'disposal first pair', reorder)
    changed = dict(sources)
    changed[source] = changed[source].replace('with RouteAware, MetadataPresentationMixin<MergedDetailScreen>', 'with RouteAware', 1)
    assert changed[source] != sources[source]
    assert check(original, changed, rows, source, package, context_guard=True, config=config)
    print('Merged real fixture lost metadata mixin: rejected')
    mutate(state + '_buildEpisodesPanel', 'panel presented item swap', lambda text: text.replace('show: widget.item,', 'show: _item,', 1).replace('show: _deps.item(),', 'show: _deps.presentedItem(),', 1))
    mutate(state + '_buildEpisodesPanel', 'panel argument order', lambda text: text.replace('showChrome: false,\n      compact: true,', 'compact: true,\n      showChrome: false,', 1))
    mutate(state + '_playSelectedTrailer', 'launcher trailer flag', lambda text: text.replace('isTrailer: true', 'isTrailer: false', 1))
    mutate(state + '_boundSources', 'dropped interleaved comment', lambda text: text.replace('  /// Layouts are stateless with respect to data — they own only focus, scroll\n', '', 1).replace('/// Layouts are stateless with respect to data — they own only focus, scroll\n', '', 1))
    separated = copy.deepcopy(lookup)
    key, node = located(state + '_browsePrimarySources')
    separated[('fixture_browse.dart', key[1], key[2])] = separated.pop(key)
    assert rewatch_adjacency(separated, rows, source)
    print('Merged real fixture rewatch separated from browse: rejected')

    # Test resolver directly, so whole-leaf failures cannot mask its identity checks.
    for spec in config['callback_identities']:
        for site in spec['sites']:
            key, node = located(site['member'])
            values = tokens(node)
            spans = argument_ranges(values, site['call'])[site.get('occurrence', 0)]
            if isinstance(site['argument'], int):
                start, end = spans[site['argument']]
            else:
                selected = [(a, b) for a, b in spans
                            if [v for v in values[a:b] if not v.startswith(('//', '/*'))][:2]
                            == [site['argument'], ':']]
                assert len(selected) == 1
                start, end = selected[0]
                start = next(j for j in range(start, end) if values[j] == ':') + 1
            while start < end and values[start].startswith(('//', '/*')):
                start += 1
            if 'conditional_member' in site:
                _, target = located(site['conditional_member'])
                positions = [j for j in range(start, end) if values[j] == target['name']]
                end = positions[site.get('branch_occurrence', 0)] + 1
                start = end - 1
                while start >= 2 and values[start - 1] == '.':
                    start -= 2
            argument = values[start:end]
            for label, replacement in [('wrapper', ['(', ')', '=>', *argument, '(', ')']), ('same-class receiver swap', ['secondInstance', '.', argument[-1]])]:
                i = start
                mutated = copy.deepcopy(lookup)
                bad = values[:i] + replacement + values[i + len(argument):]
                mutated[key]['tokens'] = [{'text': value, 'offset': j, 'comment': value.startswith(('//', '/*'))} for j, value in enumerate(bad)]
                mutated[key]['formatCommas'] = []
                assert check_callback_identities(mutated, rows, source, {**config, 'callback_identities': [spec]}), f'Accepted {spec["name"]} {site} {label}'
                print(f'Merged callback {spec["name"]} {site["call"]} #{site.get("occurrence", 0)} {label}: rejected')
    # Named selection and interpolation are both needed by the real DetailModel call.
    assert argument_expression(arguments(['X', '(', 'title', ':', "'", '${', 'name', '}', "'", ',', 'onTap', ':', 'tap', ')'], 'X')[0], 'onTap') == ['tap']
    for bad in ([], [['other', ':', 'tap']], [['onTap', ':', 'a'], ['onTap', ':', 'b']]):
        try: argument_expression(bad, 'onTap')
        except ValueError: pass
        else: raise AssertionError('Named selector accepted missing/duplicate argument')
    print('Merged named argument / interpolation positive and negatives: PASS')
    from check_settings_moves import configured, normalize, check_type_aliases
    alias_rows = [{'original_name': '_PrivateProbe', 'destination_file': 'alias.dart',
                   'destination_class': '', 'new_name': '_PrivateProbe'}]
    aliases = [{'original_name': '_PrivateProbe', 'alias': 'MergedProbe'}]
    alias_config = {**config, 'type_aliases': aliases}
    good = all_nodes(parse({'alias.dart': 'class _PrivateProbe {} typedef MergedProbe = _PrivateProbe;'}, package))
    assert not check_type_aliases(good, alias_rows, alias_config)
    with configured(alias_config):
        assert normalize(['_PrivateProbe', '(', ')'], alias_rows) == normalize(['MergedProbe', '(', ')'], alias_rows)
    for label, text in [('wrong target', 'typedef MergedProbe = OtherProbe;'),
                        ('factory wrapper', 'dynamic MergedProbe() => _PrivateProbe();'),
                        ('missing alias', '')]:
        bad = all_nodes(parse({'alias.dart': 'class _PrivateProbe {} ' + text}, package))
        assert check_type_aliases(bad, alias_rows, alias_config), label
    assert check_type_aliases(good, [{**alias_rows[0], 'new_name': 'DifferentProbe'}], alias_config)
    print('Merged exact private widget constructor alias positive and negatives: PASS')

    for alias in config.get('type_aliases', []):
        path = alias['file']
        name = alias['alias'][0].lower() + alias['alias'][1:] + 'Constructor'
        exact = 'const ' + name + ' = ' + alias['original_name'] + '.new;'
        assert sources[path].count(exact) == 1
        changed = dict(sources)
        changed[path] = changed[path].replace(exact, exact.replace('.new', '.other'), 1)
        assert check(original, changed, rows, source, package, context_guard=True, config=config)
    print('Merged exact constructor tear-off export negatives: rejected')



if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--parser-package', type=Path, required=True)
    self_test(parser.parse_args().parser_package)
