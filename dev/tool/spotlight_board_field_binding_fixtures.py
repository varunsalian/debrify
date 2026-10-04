"""Reject parameter/local capture even when token renames would compare equal."""
import copy
from check_settings_moves import all_nodes
from check_verbatim_moves import parse
from spotlight_board_field_bindings import failures


def self_test(original, sources, rows, source, config, package):
    parsed = all_nodes(parse({'<original>': original, **sources}, package))
    originals = {r['original_name']: parsed[('<original>', *r['original_name'].rsplit('.', 1))]
                 for r in rows if '.' in r['original_name']}
    assert not failures(originals, parsed, rows, source, config)
    method = next(r for r in rows if r['original_name'] == '_CardState._setWideSelection')
    field = next(r for r in rows if r['original_name'] == '_CardState._moving')
    key = (method['destination_file'], method['destination_class'], method['new_name'])
    if key not in parsed:
        print('Spotlight field binding original-code positive: PASS')
        return
    node = parsed[key]
    changed = dict(sources)
    text = changed[key[0]]
    klass = parsed[(key[0], '', key[1])]
    edits = [(t['offset'], t['offset'] + len(t['text'])) for t in klass['tokens']
             if not t['comment'] and t['text'] == field['new_name']]
    for start, end in sorted(edits, reverse=True):
        text = text[:start] + 'moving' + text[end:]
    changed[key[0]] = text
    mutant_rows = copy.deepcopy(rows)
    next(r for r in mutant_rows if r['original_name'] == field['original_name'])['new_name'] = 'moving'
    error = failures(originals, all_nodes(parse(changed, package)), mutant_rows, source, config)
    assert any('_setWideSelection' in e and '_moving' in e for e in error), error
    print('Spotlight field binding guard alone: alias captures selection parameter rejected')
    changed = dict(sources)
    start = node['text'].index('{', node['bodyOffset'] - node['start']) + 1
    body = node['text'][:start] + '\n bool ' + field['new_name'] + ' = false;\n' + node['text'][start:]
    changed[key[0]] = changed[key[0]][:node['start']] + body + changed[key[0]][node['end']:]
    error = failures(originals, all_nodes(parse(changed, package)), rows, source, config)
    assert any('_setWideSelection' in e and '_moving' in e for e in error), error
    print('Spotlight field binding guard alone: local field capture rejected')
