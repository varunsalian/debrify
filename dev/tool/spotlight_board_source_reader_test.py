#!/usr/bin/env python3
"""Simulated real-config moves must preserve comments, locals and bindings."""
import csv
import json
import re
import subprocess
from pathlib import Path

from check_settings_moves import all_nodes, configured, names
from check_verbatim_moves import parse
from spotlight_board_source_reader import ROOT, SOURCE, read_member


def self_test(package):
    config = json.loads((ROOT / 'dev/tool/spotlight_board_checker_config.json').read_text())
    # These fixtures simulate the unformatted structural move from R. Actual
    # formatted destinations exercise their pinned wraps in the full checker.
    config.get('sidecars', {}).pop('context_exceptions', None)
    rows = list(csv.DictReader((ROOT / 'dev/tool/spotlight_board_manifest.tsv').open(), delimiter='\t'))
    original = subprocess.check_output(['git', 'show', config['baseline'] + ':' + SOURCE], cwd=ROOT, text=True)
    nodes = all_nodes(parse({SOURCE: original}, package))
    registry = {row['original_name']: row for row in rows}
    paths = {owner: receiver for receiver, owner in config['receiver_paths'].items()}
    for member in ['SpotlightBoardState._shelf', 'SpotlightBoardState._down',
                   'SpotlightBoardState._warmHeroImage', 'SpotlightBoardState._openHero',
                   '_CardState._buildCard']:
        owner, name = member.split('.')
        node = nodes[(SOURCE, owner, name)]
        row = registry[member]
        with configured(config):
            mapping = names(rows, owner)
        references = {ref['offset']: ref for ref in node['references']}
        edits = []
        values = node['tokens']
        for index, token in enumerate(values):
            value = token['text']
            if token.get('comment'):
                continue
            replacement = mapping.get(value, value)
            ref = references.get(token['offset'])
            qualified = index > 0 and values[index-1]['text'] in ['.', '?.']
            if owner == '_CardState' and value == 'this':
                replacement = 'cardState'
            elif ref is not None and not qualified:
                target = registry.get(owner + '.' + value)
                if owner == 'SpotlightBoardState' and value in config['widget_views'][member]['state_members']:
                    replacement = 'view.' + value
                elif target is not None:
                    receiver = 'cardState' if owner == '_CardState' else paths[target['destination_class']]
                    replacement = receiver + '.' + target['new_name']
                elif owner == '_CardState' and value in config['bound_this'][member]['state_members']:
                    replacement = 'cardState.' + value
                elif owner == 'SpotlightBoardState' and value == 'widget':
                    replacement = 'view'
                elif owner == 'SpotlightBoardState' and value in ['context', 'mounted', 'setState']:
                    replacement = '_deps.' + value + ('()' if value != 'setState' and not ref['contextParameter'] else '')
                    if value == 'context' and ref['contextParameter']:
                        replacement = value
            if replacement != value:
                edits.append((token['offset']-node['start'], token['offset']-node['start']+len(value), replacement))
        body = node['text']
        for start,end,replacement in sorted(edits,reverse=True):
            body = body[:start]+replacement+body[end:]
        sources = {SOURCE: original, row['destination_file']: 'class '+row['destination_class']+' {\n'+body+'\n}\n'}
        expected = re.sub(r'\s+', '', node['text'])
        assert read_member(member, original, sources, rows, config, package) == expected
        print('Reader correct simulated move: '+member+' PASS')
        if owner == '_CardState':
            before = 'onInteraction?.call(cardState, v)'
            assert before in body
            changed = body.replace(before, 'onInteraction?.call(anotherState, v)', 1)
        else:
            # Change a real executable integer while keeping syntax valid.
            before = ' 4)' if owner == 'SpotlightBoardState' and name == '_shelf' else ' 0)'
            match = re.search(r'\b(?:4|0)\b', body)
            if match:
                changed = body[:match.start()]+'99'+body[match.end():]
            else:
                assert 'view.' in body
                changed = body.replace('view.', 'anotherState.', 1)
        bad = dict(sources);bad[row['destination_file']] = bad[row['destination_file']].replace(body, changed)
        try:
            read_member(member, original, bad, rows, config, package)
        except ValueError:
            pass
        else:
            raise AssertionError('Reader accepted a mutated body: '+member)
        print('Reader mutated simulated move: '+member+' rejected')
        if 'row below' in body:
            bad = dict(sources);bad[row['destination_file']] = bad[row['destination_file']].replace('row below','_row below')
            try:
                read_member(member, original, bad, rows, config, package)
            except ValueError:
                pass
            else:
                raise AssertionError('Reader rewrote ordinary comment prose')
            print('Reader ordinary comment prose mutation: rejected')


if __name__ == '__main__':
    import argparse
    from spotlight_board_source_reader import package_at
    args = argparse.ArgumentParser(description=__doc__)
    args.add_argument('--parser-package', type=Path, required=True)
    options = args.parse_args()
    self_test(package_at(options.parser_package.resolve()))
