"""Materialize reviewed virtual fixtures/probes; never writes application files."""
from check_verbatim_moves import parse
from check_settings_moves import apply_explicit_token_edits, tokens
from dart_move_partition import partition


def render(values):
    return ''.join(value + ('\n' if value.startswith('//') else ' ') for value in values) + '\n'


def edited_text(text, span, edits):
    """Use scanner positions and the core's occurrence counts, preserving trivia."""
    result = text[span['start']:span['end']]
    # All edits in fixture manifests are disjoint ORIGINAL token sequences.
    # Reparse is deliberately avoided; reject overlap instead of interpreting it.
    raw = [t for t in span['tokens'] if t['offset'] not in set(span['formatCommas'])]
    values = [t['text'] for t in raw]
    apply_explicit_token_edits(values, edits)
    replacements, occupied = [], set()
    for edit in edits:
        before = edit['before']
        matches = [i for i in range(len(raw)) if values[i:i + len(before)] == before]
        if len(matches) != edit['count']:
            raise ValueError('fixture edits must be disjoint original-token edits')
        for i in matches:
            indices = set(range(i, i + len(before)))
            if indices & occupied:
                raise ValueError('overlapping fixture edits')
            occupied.update(indices)
            start = raw[i]['offset'] - span['start']
            end = raw[i + len(before) - 1]['offset'] + len(raw[i + len(before) - 1]['text']) - span['start']
            replacements.append((start, end, ' '.join(edit['after'])))
    for start, end, value in sorted(replacements, reverse=True):
        result = result[:start] + value + result[end:]
    return result


def materialize(manifest, original, package):
    unit = parse({'base': original}, package, ownership=True)['base']
    spans, _, _ = partition(unit, manifest['split_containers'])
    values = {p: {} for p in [manifest['source'], *manifest['destinations']]}
    for row in manifest['declarations']:
        path = row.get('destination', manifest['source']) if row['fate'] == 'moved' else manifest['source']
        edits = row.get('substitutions', []) + row.get('patches', [])
        if row.get('remove_static'):
            edits = [dict(before=['static'], after=[], count=1), *edits]
        values[path][row.get('target', row['original'])] = edited_text(original, spans[row['original']], edits)
    for path, scaffold in manifest.get('scaffolding', {}).items():
        for key, pinned in scaffold.items():
            if key in values[path]:
                raise ValueError('duplicate fixture scaffold')
            values[path][key] = render(pinned)
    result = {}
    for path, owned in values.items():
        spec = manifest if path == manifest['source'] else manifest['destinations'][path]
        order = spec['span_order']
        if set(order) != set(owned) or len(order) != len(owned):
            raise ValueError('fixture span order is not exhaustive: ' + path)
        result[path] = ''.join(owned[key] for key in order)
    return result
