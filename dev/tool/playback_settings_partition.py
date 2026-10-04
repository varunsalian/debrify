"""Configuration-scoped retained-preamble / inline-element list partition.

Only playback_settings opts into this join. Other partition configurations
continue through the existing fresh-builder checker without altered defaults.
"""


def validate_spec(original, spec):
    from check_settings_moves import partition_elements
    elements = partition_elements(original)
    assert spec['retained_preamble_join'] is True
    errors = []
    cursor = spec['inline_elements']
    if cursor != 1 or len(elements) != 15:
        errors.append('Playback partition must retain exactly E1 of E1–E15')
    for piece in spec['slices']:
        start, end = piece['first_element'], piece['end_element']
        if start != cursor or not start < end <= len(elements):
            errors.append('Invalid/non-contiguous playback element range: ' + piece['name'])
        if (piece.get('cut_line') != elements[start]['line']
                or piece.get('last_line') != elements[end - 1]['endLine']):
            errors.append('Playback cut lines differ from complete AST elements: ' + piece['name'])
        cursor = end
    if cursor != len(elements):
        errors.append('Playback pieces do not cover E2–E15')
    if [(p['first_element'], p['end_element']) for p in spec['slices']] != [(1, 4), (4, 7), (7, 10), (10, 14), (14, 15)]:
        errors.append('Playback platform ranges or order changed')
    return errors


def check_partition(before, current, spec, lookup, rows, package, row):
    from check_settings_moves import tokens, normalize, partition_elements, compare_elements
    errors = validate_spec(before, spec)
    elements = partition_elements(before)
    if current.get('returnedList') and len(partition_elements(current)) == len(elements):
        errors.extend(compare_elements(before, [current], rows, row))
        if preamble_tokens(before, rows, row) != preamble_tokens(current, rows, row):
            errors.append('Unmoved playback preamble changed')
        return errors

    pieces = []
    for piece in spec['slices']:
        node = lookup.get((piece['file'], piece['owner'], piece['name']))
        if node is None:
            errors.append('Missing playback piece: ' + piece['name'])
            continue
        pieces.append(node)
        selected = elements[piece['first_element']:piece['end_element']]
        if len(partition_elements(node)) != len(selected):
            errors.append('Playback piece split, omitted or duplicated element: ' + piece['name'])
        expected_locals = [local for local in before['returnedList']['preamble']
                           if local['names'][0] in piece['repeated_locals']]
        actual_locals = node['returnedList']['preamble'] if node.get('returnedList') else []
        if [local['names'] for local in actual_locals] != [local['names'] for local in expected_locals]:
            errors.append('Unpermitted playback local: ' + piece['name'])
        for expected, actual in zip(expected_locals, actual_locals):
            if normalized_local(expected, rows, row, package) != normalized_local(actual, rows, row, package):
                errors.append('Changed repeated playback local: ' + piece['name'])
        used = set().union(*(set(element_tokens(node, e)) for e in partition_elements(node))) if node.get('returnedList') else set()
        if any(name not in used for name in piece['repeated_locals']):
            errors.append('Unused repeated playback local: ' + piece['name'])
        # Exact body grammar prevents statements outside locals/list from hiding.
        expected_body = ['{', *preamble_tokens(node, rows, row), 'return', '[']
        for element in partition_elements(node):
            expected_body += normalize(element_tokens(node, element), rows, row) + [',']
        expected_body += [']', ';', '}']
        actual_body = [t for t in normalize(tokens(node, node['bodyOffset']), rows, row) if not t.startswith(('//', '/*'))]
        expected_body = [t for t in expected_body if not t.startswith(('//', '/*'))]
        # The final literal comma is AST-owned formatting punctuation.
        if expected_body[-4] == ',':
            expected_body.pop(-4)
        if actual_body != expected_body:
            errors.append('Playback piece must contain only permitted locals and its list: ' + piece['name'])
    # The join retains only original locals used by inline E1/the spreads.
    # E1 and the five spread calls use neither theme nor t.
    used = set(element_tokens(before, elements[0]))
    expected_locals = [local for local in before['returnedList']['preamble'] if any(name in used for name in local['names'])]
    actual_locals = current['returnedList']['preamble'] if current.get('returnedList') else []
    if [local['names'] for local in actual_locals] != [local['names'] for local in expected_locals]:
        errors.append('Playback join preamble must contain only used original locals')
    for expected, actual in zip(expected_locals, actual_locals):
        if normalized_local(expected, rows, row, package) != normalized_local(actual, rows, row, package):
            errors.append('Playback used join preamble changed')
    actual_elements = partition_elements(current)
    if not actual_elements:
        return errors + ['Missing playback inline E1']
    if (actual_elements[0]['kind'] != elements[0]['kind']
            or normalize(element_tokens(current, actual_elements[0]), rows, row)
            != normalize(element_tokens(before, elements[0]), rows, row)):
        errors.append('Playback inline E1 changed')
    if len(actual_elements) != 1 + len(spec['slices']):
        errors.append('Playback join omitted/duplicated an inline element or piece')
    for element, piece in zip(actual_elements[1:], spec['slices']):
        if element['kind'] != 'SpreadElementImpl' or element_tokens(current, element) != ['...', '_deps', '.', piece['name'], '(', ')']:
            errors.append('Playback join must spread each platform exactly once in order')
    expected_body = ['{', *preamble_tokens(current, rows, row), 'return', '[']
    for element in actual_elements:
        expected_body += normalize(element_tokens(current, element), rows, row) + [',']
    expected_body += [']', ';', '}']
    expected_body.pop(-4)
    actual_body = normalize(tokens(current, current['bodyOffset']), rows, row)
    strip_comments = lambda values: [v for v in values if not v.startswith(('//', '/*'))]
    if strip_comments(actual_body) != strip_comments(expected_body):
        errors.append('Playback join contains an unpermitted statement')
    if len(pieces) == len(spec['slices']):
        joined = [actual_elements[0]] + [e for piece in pieces for e in partition_elements(piece)]
        expected = [normalize(element_tokens(before, e), rows, row) for e in elements]
        actual = [normalize(element_tokens(current, actual_elements[0]), rows, row)]
        actual += [normalize(element_tokens(piece, e), rows, row)
                   for piece in pieces for e in partition_elements(piece)]
        if expected != actual:
            errors.append('Joined playback elements differ from E1–E15 in exact order')
    return errors


def normalized_local(local, rows, row, package):
    from check_verbatim_moves import parse
    from check_settings_moves import normalize, tokens
    node = parse({'local': 'void scope() { ' + local['text'] + ' }'}, package)['local']['declarations'][0]
    return normalize(tokens(node)[5:-1], rows, row)


def preamble_tokens(node, rows, row):
    from check_settings_moves import normalize, tokens
    # Tokens before the original return, excluding the opening body brace.
    code = tokens(node, node['bodyOffset'], node['returnedList']['offset'])
    assert code[0] == '{' and code[-1] == 'return'
    return normalize(code[1:-1], rows, row)


def element_tokens(node, element):
    from check_settings_moves import tokens
    return tokens(node, element['offset'], element['end'])


def virtual(current, spec, lookup, sources, package):
    from check_verbatim_moves import parse
    raw = sources[spec['join_file']]
    result = current['returnedList']
    first = result['elements'][0]
    # Keep the header, used join locals and inline E1 with its comments.
    start = result['offset'] + 1
    inline = raw[start:first['end']] + ','
    interiors = [inline]
    for piece in spec['slices']:
        node = lookup[(piece['file'], piece['owner'], piece['name'])]
        piece_raw = sources[piece['file']]
        returned = node['returnedList']
        interiors.append(piece_raw[returned['offset'] + 1:returned['end'] - 1])
    prefix = current['text'][:result['offset'] - current['start']]
    # Restore the proven identical piece locals only for virtual whole-method
    # comparison with the original scope; they are absent from the real join.
    first_piece = lookup[(spec['slices'][0]['file'], spec['slices'][0]['owner'], spec['slices'][0]['name'])]
    retained = {name for local in result['preamble'] for name in local['names']}
    missing = '\n'.join(local['text'] for local in first_piece['returnedList']['preamble'] if local['names'][0] not in retained)
    opening = prefix.index('{') + 1
    prefix = prefix[:opening] + '\n' + missing + '\n' + prefix[opening:]
    text = prefix + '[' + '\n'.join(interiors) + '];\n}'
    return parse({'virtual': 'class Virtual { ' + text + ' }'}, package)['virtual']['declarations'][0]['members'][0]
