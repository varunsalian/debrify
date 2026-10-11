"""Disjoint analyzer/scanner spans, with leading trivia owned by the next leaf."""
from collections import Counter

from check_settings_moves import tokens


def identity(node):
    return node['name'] + ('@set' if node.get('isSetter') else '')


def partition(unit, splits):
    spans, orders, nodes = {}, {}, {}
    stream = unit['unitTokens']

    def span(key, start, end, node=None):
        if key in spans:
            raise ValueError('duplicate declaration: ' + key)
        spans[key] = dict(tokens=[t for t in stream if start <= t['offset'] < end],
                          formatCommas=unit['unitFormatCommas'], start=start, end=end)
        if node is not None:
            nodes[key] = node

    def visit(children, start, end, owner):
        cursor = start
        orders[owner] = []
        for child in children:
            name = identity(child)
            key = owner + '.' + name if owner else name
            orders[owner].append(key)
            if key in splits:
                opening, closing = child['bodyOpen'], child['bodyClose']
                if opening is None:
                    raise ValueError('split requires a class body: ' + key)
                span(key + ':header', cursor, opening + 1, child)
                visit(child['members'], opening + 1, closing, key)
                span(key + ':close', closing, child['end'])
            else:
                span(key, cursor, child['end'], child)
            cursor = child['end']
        span(owner + ':tail', cursor, end)

    cursor = 0
    orders['@directives'] = []
    for index, directive in enumerate(unit['directiveNodes']):
        key = '@directive:' + str(index)
        span(key, cursor, directive['end'])
        orders['@directives'].append(key)
        cursor = directive['end']
    visit(unit['declarations'], cursor, unit['length'], '')
    coverage = Counter(t['offset'] for value in spans.values() for t in value['tokens'])
    if coverage != Counter(t['offset'] for t in stream):
        raise ValueError('partition gap/overlap')
    return spans, orders, nodes


def frozen(spans):
    """Pin every scaffold token, including comments, rather than hashes alone."""
    return {key: tokens(node) for key, node in spans.items()}


def ownership_rows(manifest):
    """Bridge the ownership schema to the existing occurrence/scope guards."""
    rows = []
    for row in manifest['declarations']:
        key = row['original']
        if key.startswith('@') or ':' in key:
            continue
        target = row.get('target', key)
        owner, _, name = target.rpartition('.')
        rows.append(dict(original_name=key, destination_file=row.get('destination', manifest['source']),
                         destination_class=owner, new_name=name or target,
                         allowed_edits='', expected_difference=''))
    return rows
