"""Config-scoped State-field binding proof before token normalization."""
from collections import Counter


def failures(original, current, rows, source, config, *, members=None):
    owners = config.get('spotlight_state_field_bindings', [])
    if not owners:
        return []
    fields = {}
    for row in rows:
        owner, _, name = row['original_name'].rpartition('.')
        node = original.get(row['original_name'])
        if owner in owners and node and node.get('variables'):
            fields[row['original_name']] = row
    errors = []
    for row in rows:
        owner, _, name = row['original_name'].rpartition('.')
        if members is not None and row['original_name'] not in members:
            continue
        if owner not in owners:
            continue
        before = original[row['original_name']]
        key = (row['destination_file'], row['destination_class'], row['new_name'])
        after = current.get(key) or current.get((source, owner, name))
        if after is None:
            continue  # The main checker reports missing declarations.
        def signature(node, moved):
            found = Counter()
            for ref in node['references']:
                if ref['parent'].startswith('CommentReference'):
                    continue
                receiver = ref.get('receiver')
                if receiver is None and ref['name'] in ref.get('lexicalNames', []):
                    continue
                for identity, field in fields.items():
                    if identity.rpartition('.')[0] != owner:
                        continue
                    old_name = identity.rpartition('.')[2]
                    if not moved:
                        valid = ref['name'] == old_name and receiver in (None, 'this', owner)
                    else:
                        receiver_owner = config.get('receiver_owners', {}).get(receiver)
                        renamed = ref['name'] == field['new_name'] and (
                            receiver in (None, 'this') and node['owner'] == field['destination_class']
                            or receiver == field['destination_class']
                            or receiver_owner == field['destination_class'])
                        retained = ref['name'] == old_name and (
                            receiver in (None, 'this') and node['owner'] == owner
                            or receiver == owner)
                        valid = renamed or retained
                    if valid:
                        found[(identity, ref['bindingRole'])] += 1
            return found
        moved = key in current and key != (source, owner, name)
        expected, observed = signature(before, False), signature(after, True)
        if expected != observed:
            errors.append('Spotlight State field binding changed: ' + row['original_name']
                          + '; missing ' + str(expected - observed)
                          + '; added ' + str(observed - expected))
    return errors
