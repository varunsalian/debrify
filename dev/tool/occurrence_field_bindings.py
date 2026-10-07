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
    paths += [(['_deps'], {'context', 'mounted', 'setState'} | set(config.get('live_widget_getters', [])))]
    paths += [(['_deps'], {s['after'][2] for s in config.get('registered_occurrence_substitutions', [])
                          if s['after'][:2] == ['_deps', '.']})]
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
    # A registered live widget getter replaces the receiver at the same site.
    # Retain the raw selector classification and check its qualifier below.
    for i in range(len(values) - 2):
        if values[i:i+2] == ['widget', '.'] and values[i+2] in config.get('live_widget_getters', []):
            scaffolding.add(i)
    return [o for o in node.get('occurrences', []) if o['tokenIndex'] not in scaffolding]


def _located(row, lookup, source):
    owner, _, name = row['original_name'].rpartition('.')
    return lookup.get((row['destination_file'], row['destination_class'], row['new_name'])) or lookup.get((source, owner, name or row['original_name']))


def _canonical_name(name, rows, config):
    aliases = {a['alias']: a['original_name'] for a in config.get('type_aliases', [])}
    aliases.update({f['call']: f['original_name'] for f in config.get('constructor_forwarders', [])})
    name = aliases.get(name, name)
    mapping = {r['original_name'].split('.')[-1]: r['new_name'] for r in rows}
    if config.get('occurrence_type_renames'):
        mapping.update(config.get('type_renames', {}))
    return mapping.get(name, name)


def failures(original, lookup, rows, source, config, *, members=None, package=None):
    if not config.get('occurrence_field_bindings'):
        return []
    from check_settings_moves import normalize
    owners = config['occurrence_field_bindings']['owners']
    by_old = {r['original_name'].split('.')[-1]: r for r in rows if r['original_name'].rpartition('.')[0] in owners}
    fields = {name: r for name, r in by_old.items() if original[r['original_name']].get('variables')}
    binding_config = config['occurrence_field_bindings']
    # Preserve the Debrify TV default; additional owners opt in explicitly:
    # state_classes (edit_profile), record_paths (stremio_tv, all owners) or
    # record_owners/record_fields (stremio_tv_tuner); field_classes narrows.
    record_paths = binding_config.get('record_paths')
    default_owners = set(owners) if record_paths is not None else {'_DebrifyTVScreenState'}
    state_classes = set(binding_config['state_classes']) if 'state_classes' in binding_config else default_owners
    field_classes = binding_config.get('field_classes')
    record_owners = config.get('record_owners', state_classes)
    def is_record_field(row):
        owner, _, name = row['original_name'].rpartition('.')
        selected = config.get('record_fields', {}).get(owner)
        return (owner in record_owners and (selected is None or name in selected)
                and (field_classes is None or row['destination_class'] in field_classes))
    record_fields = {r['new_name'] for r in fields.values() if is_record_field(r)}
    if config.get('registered_occurrence_substitutions'):
        from registered_occurrence_substitutions import project
        moved = {r['original_name'] for r in rows if r['destination_file'] != source
                 and (r['destination_file'], r['destination_class'], r['new_name']) in lookup}
        original = project(original, config, package, moved)
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
        annotations = config.get('forwarded_annotation_occurrences', {}).get(identity)
        destination = (row['destination_file'], row['destination_class'], row['new_name'])
        if annotations and destination in lookup and destination[0] != source:
            from check_settings_moves import check_forwarder
            owner, _, name = identity.rpartition('.')
            retained = lookup.get((source, owner, name))
            spec = config.get('forwarders', {}).get(identity)
            code_indices = [i for i,t in enumerate(before['tokens']) if not t['comment']]
            leading = code_indices[:2]
            if (annotations != ['override'] or len(leading) != 2
                    or [before['tokens'][i]['text'] for i in leading] != ['@','override']
                    or retained is None or spec is None
                    or check_forwarder(before, retained, row, spec, package)):
                errors.append('Forwarded annotation requires exact validated forwarder: '+identity)
            else:
                actual_code = [t['text'] for t in after['tokens'] if not t['comment']]
                if actual_code[:2] == ['@','override']:
                    errors.append('Moved forwarded declaration retains override annotation: '+identity)
                else:
                    left = [o for o in left if o['tokenIndex'] != leading[1]]
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
                paths = [p for p, owner in (record_paths if field and record_paths is not None else config.get('receiver_owners', {})).items() if owner == target]
                moved_field = field and is_record_field(field) and (field['destination_file'], field['destination_class'], field['new_name']) in lookup and field['destination_file'] != source
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
            elif (a['kind'] == 'selector' and a['qualifierTokens'] == ['widget']
                  and a['name'] in config.get('live_widget_getters', [])):
                retained_widget = b['kind'] == 'selector' and b['qualifierTokens'] == ['widget'] and b['role'] == a['role']
                live_widget = b['kind'] == 'selector' and b['qualifierTokens'] == ['_deps'] and b['role'] == 'invocation'
                if not (retained_widget or live_widget):
                    errors.append('Occurrence live widget getter changed: '+label)
            elif a['kind'] == 'selector':
                if b['kind'] != 'selector' or normalize(a['qualifierTokens'], rows, row) != normalize(b['qualifierTokens'], rows, row) or a['role'] != b['role']:
                    errors.append('Occurrence selector chain changed: '+label)
            elif (config.get('require_live_state_callbacks') and a['name'] in ['context', 'mounted', 'setState']
                  and a['binding'] == 'unbound' and before['owner'] in state_classes
                  and row['destination_file'] != source
                  and (row['destination_file'], row['destination_class'], row['new_name']) in lookup
                  and b['kind'] != 'selector'):
                errors.append('Occurrence live State callback qualification lost: '+label)
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
            # Unconditional by default (the pre-flag behaviour every feature
            # relied on); a config may only opt out explicitly.
            if (binding_config.get('mandatory_qualification', True)
                    and occurrence['kind'] == 'lexical' and occurrence['binding'] == 'unbound'
                    and occurrence['name'] in record_fields):
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
