"""Opt-in occurrence/scope binding checks on raw ASTs before normalization."""
import re


def _parts(path):
    return re.split(r'(\.)', path)


def aligned(node, config):
    """Drop only registered receiver identifiers, retaining raw classification."""
    values = [t['text'] for t in node['tokens']]
    scaffolding = set()
    paths = [(_parts(path), set(config.get('receiver_members', {}).get(owner, [])))
             for path, owner in config.get('receiver_paths', {}).items()]
    paths += [(['_deps'], {'context', 'mounted', 'setState'})]
    by_first = {}
    for path, members in paths:
        by_first.setdefault(path[0], []).append((path, members))
    for i, value in enumerate(values):
        if i and values[i-1] in ('.', '?.'):
            continue
        for path, members in by_first.get(value, []):
            end = i + len(path)
            if (values[i:end] == path and values[end:end+1] == ['.']
                    and values[end+1:end+2] and values[end+1] in members):
                # A declared receiver is scaffolding only for a registered leaf
                # or the three live State callbacks, never an arbitrary selector.
                scaffolding.update(range(i, end))
    return [o for o in node.get('occurrences', []) if o['tokenIndex'] not in scaffolding]


def _located(row, lookup, source):
    owner, _, name = row['original_name'].rpartition('.')
    return lookup.get((row['destination_file'], row['destination_class'], row['new_name'])) or lookup.get((source, owner, name or row['original_name']))


def _canonical_name(name, rows, config):
    aliases = {a['alias']: a['original_name'] for a in config.get('type_aliases', [])}
    name = aliases.get(name, name)
    mapping = {r['original_name'].split('.')[-1]: r['new_name'] for r in rows}
    return mapping.get(name, name)


def failures(original, lookup, rows, source, config, *, members=None):
    if not config.get('occurrence_field_bindings'):
        return []
    from check_settings_moves import normalize
    owners = config['occurrence_field_bindings']['owners']
    by_old = {r['original_name'].split('.')[-1]: r for r in rows if r['original_name'].rpartition('.')[0] in owners}
    fields = {name: r for name, r in by_old.items() if original[r['original_name']].get('variables')}
    record_fields = {r['new_name'] for r in fields.values() if r['original_name'].rpartition('.')[0] == '_DebrifyTVScreenState'}
    errors = []
    for row in rows:
        identity = row['original_name']
        if members is not None and identity not in members:
            continue
        before = original[identity]
        after = _located(row, lookup, source)
        if after is None:
            continue
        left, right = aligned(before, config), aligned(after, config)
        if len(left) != len(right):
            errors.append('Occurrence alignment changed: '+identity+f' ({len(left)} != {len(right)})')
            continue
        for ordinal, (a, b) in enumerate(zip(left, right)):
            label = f'{identity} occurrence {ordinal} ({a["name"]})'
            if str(b.get('binding', '')).startswith('early:'):
                errors.append('Early lexical reference: '+label)
                continue
            expected_name = _canonical_name(a['name'], rows, config)
            observed_name = _canonical_name(b['name'], rows, config)
            if expected_name != observed_name or a['scope'] != b['scope']:
                errors.append('Occurrence name/scope changed: '+label)
                continue
            field = fields.get(a['name'])
            is_state = a['kind'] == 'lexical' and a['binding'] == 'unbound'
            is_this = a['kind'] == 'selector' and a['qualifierTokens'] == ['this']
            registered = by_old.get(a['name']) if is_state or is_this else None
            if registered:
                target = registered['destination_class']
                paths = [p for p, owner in config.get('receiver_owners', {}).items() if owner == target]
                moved_field = field and field['original_name'].rpartition('.')[0] == '_DebrifyTVScreenState' and (field['destination_file'], field['destination_class'], field['new_name']) in lookup and field['destination_file'] != source
                if b['kind'] == 'selector':
                    if b['qualifierTokens'] not in [_parts(p) for p in paths] or b['name'] != registered['new_name']:
                        errors.append('Occurrence field/member receiver changed: '+label)
                elif moved_field or a['kind'] != b['kind'] or a['binding'] != b['binding']:
                    errors.append('Occurrence field qualification lost: '+label)
                if a['role'] != b['role']:
                    errors.append('Occurrence field role changed: '+label)
                continue
            if a['kind'] == 'lexical' and str(a['binding']).startswith('decl:'):
                if b['kind'] != 'lexical' or b['binding'] != a['binding'] or b['name'] != a['name']:
                    errors.append('Occurrence lexical binding changed: '+label)
                elif a['role'] != b['role']:
                    errors.append('Occurrence lexical role changed: '+label)
            elif a['kind'] == 'selector':
                if b['kind'] != 'selector' or normalize(a['qualifierTokens'], rows, row) != normalize(b['qualifierTokens'], rows, row) or a['role'] != b['role']:
                    errors.append('Occurrence selector chain changed: '+label)
            elif a['name'] in ['context', 'mounted', 'setState'] and a['binding'] == 'unbound' and b['kind'] == 'selector':
                expected_role = 'invocation' if a['name'] in config.get('live_getter_callbacks', []) else a['role']
                if b['qualifierTokens'] != ['_deps'] or b['role'] != expected_role:
                    errors.append('Occurrence live State callback changed: '+label)
            elif a['kind'] != b['kind'] or a['binding'] != b['binding'] or a['role'] != b['role']:
                # Registered top-level aliases and helper renames keep a bare
                # reference; a qualified selector cannot capture a lexical read.
                errors.append('Occurrence binding changed: '+label)
    for (file, owner, name), node in lookup.items():
        if file == '<original>' or not file.startswith(config['feature']+'/'):
            continue
        for occurrence in node.get('occurrences', []):
            if occurrence['kind'] == 'lexical' and occurrence['binding'] == 'unbound' and occurrence['name'] in record_fields:
                errors.append('Bare owner field reference: '+f'{file}:{owner}.{name} {occurrence["name"]}')
            if str(occurrence.get('binding', '')).startswith('early:'):
                errors.append('Early destination reference: '+f'{file}:{owner}.{name}')
    return errors


def lexical_setter_failures(original, lookup, rows, source, config):
    errors = []
    for identity, names in config.get('lexical_state_setters', {}).items():
        row = next(r for r in rows if r['original_name'] == identity)
        after = _located(row, lookup, source)
        if after is None:
            continue
        before_refs = [o for o in original[identity].get('occurrences', []) if o['name'] in names and o['kind'] == 'lexical' and str(o['binding']).startswith('decl:')]
        if not before_refs:
            errors.append('Missing original lexical setter evidence: '+identity)
        after_refs = [o for o in aligned(after, config) if o['name'] in names and o['kind'] == 'lexical' and str(o['binding']).startswith('decl:')]
        signature = lambda refs: [(o['name'], o['scope'], o['binding'], o['role']) for o in refs]
        if signature(before_refs) != signature(after_refs):
            errors.append('Lexical State setter changed: '+identity)
    return errors
