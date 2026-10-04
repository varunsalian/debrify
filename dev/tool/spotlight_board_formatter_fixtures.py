"""Full-composition fixtures for the one scoped named-record comma."""
import copy

from check_settings_moves import ROOT, all_nodes, check, configured, spotlight_formatter_commas
from check_verbatim_moves import parse
from spotlight_board_source_reader import read_member


def self_test(original, sources, rows, source, config, package):
    member = 'SpotlightBoardState._loadShelvesAndFinishDown'
    row = next(row for row in rows if row['original_name'] == member)
    key = (row['destination_file'], row['destination_class'], row['new_name'])
    nodes = all_nodes(parse(sources, package))
    if key not in nodes:
        print('Spotlight named-record full-composition fixtures: pending destination')
        return
    node = nodes[key]
    with configured(config):
        validated = spotlight_formatter_commas(node, row)
    comma = node['namedRecords'][0]['trailingComma']
    assert comma is not None and comma in validated['formatCommas']
    assert not check(original, sources, rows, source, package, context_guard=True, config=config)
    read_member(member, original, sources, rows, config, package)
    print('Spotlight full-composition formatter comma and reader positive: PASS')
    # Original single-line record and formatter-produced multiline record both
    # pass. Every other comma/value remains owned by ordinary comparisons.
    without = dict(sources)
    without[key[0]] = without[key[0]][:comma] + without[key[0]][comma + 1:]
    assert not check(original, without, rows, source, package, context_guard=True, config=config)
    print('Spotlight full-composition optional comma absent positive: PASS')
    record = node['namedRecords'][0]
    opening = sources[key[0]].index('{', node['bodyOffset']) + 1
    controls = [
        ('changed record value', record['offset'], record['end'],
         sources[key[0]][record['offset']:record['end']].replace('DateTime.now()', 'DateTime(2026)', 1)),
        ('unregistered record comma elsewhere', opening, opening,
         '\n final extra = (origin: origin, at: DateTime.now(),);\n'),
        ('hoisted context', opening, opening,
         '\n final context = _deps.context();\n'),
        ('other token in declaration', opening, opening, '\n final extraToken = true;\n'),
        ('other comma in declaration', opening, opening,
         '\n final extra = (unregistered: true,);\n'),
    ]
    for label, start, end, text in controls:
        changed = dict(sources)
        changed[key[0]] = changed[key[0]][:start] + text + changed[key[0]][end:]
        assert check(original, changed, rows, source, package, context_guard=True, config=config), label
        try:
            read_member(member, original, changed, rows, config, package)
        except ValueError:
            pass
        else:
            raise AssertionError('Reader accepted ' + label)
        print('Spotlight full-composition ' + label + ': rejected')
    # The general parser still pins named-record commas at all other sites.
    elsewhere = parse({'other': 'void other() { final value = (flag: true,); }'}, package)['other']['declarations'][0]
    assert elsewhere['namedRecords'][0]['trailingComma'] not in elsewhere['formatCommas']
    print('General named-record comma rule unchanged: PASS')
