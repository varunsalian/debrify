#!/usr/bin/env python3
"""Resolve listener tear-offs before the move check erases receiver qualifiers.

Instances, not merely their classes, define callback identity. This checker is
opt-in through the TorBox config; other manifest configurations are unchanged.
"""
import re


def arguments(values, method):
    found = []
    for i, value in enumerate(values[:-1]):
        if value != method:
            continue
        opening = i + 1
        if values[opening] == '<':
            # Typed widget constructor calls retain their type arguments.
            generic_depth = 0
            while opening < len(values):
                token = values[opening]
                generic_depth += token.count('<') - token.count('>')
                opening += 1
                if generic_depth == 0:
                    break
        if opening >= len(values) or values[opening] != '(':
            continue
        depth, current, args = 0, [], []
        for token in values[opening + 1:]:
            if token == ')' and depth == 0:
                if current:
                    args.append(current)
                found.append(args)
                break
            if token == ',' and depth == 0:
                args.append(current)
                current = []
                continue
            # '${' opens a string interpolation whose '}' is counted as a
            # closer; without it the depth never returns to 0 and the call
            # is silently dropped.
            if token in ('(', '[', '{', '${'):
                depth += 1
            elif token in (')', ']', '}'):
                depth -= 1
            current.append(token)
    return found


def callback_argument(call, site):
    """Resolve one exact positional or named callback without erasing its value.

    A named argument is given either as `named_argument` or, in older
    configurations, as a string `argument`; an int `argument` is positional.
    A bare int or string may be passed instead of a site.
    """
    if not isinstance(site, dict):
        site = {'argument': site}
    if 'named_argument' in site:
        name = site['named_argument']
    elif isinstance(site['argument'], str):
        name = site['argument']
    else:
        return call[site['argument']]
    matches = [arg[2:] for arg in call if arg[:2] == [name, ':']]
    if len(matches) != 1 or not matches[0]:
        raise ValueError('expected exactly one named argument: ' + name)
    return matches[0]


def check_callback_identities(lookup, rows, source_path, config):
    from check_settings_moves import tokens
    specs = config.get('callback_identities', [])
    if not specs:
        return []
    by_original = {row['original_name']: row for row in rows}
    aliases = config.get('callback_receiver_aliases', {})
    instances = config.get('callback_instances', {})
    getter_aliases = config.get('callback_getter_aliases', {})
    errors = []

    def node_for(original):
        row = by_original[original]
        key = (row['destination_file'], row['destination_class'], row['new_name'])
        if key in lookup:
            return lookup[key]
        owner, _, name = original.rpartition('.')
        retained_owner = config.get('type_renames', {}).get(owner, owner)
        return lookup[(source_path, retained_owner, name)]

    def identity(expr, owner, *, getter=False):
        expr = list(expr)
        if expr[-1:] == ['!']:
            expr.pop()
        path = ''.join(expr)
        if getter and path in getter_aliases:
            path = getter_aliases[path]
        if not re.fullmatch(r'[A-Za-z_$][\w$]*(?:\.[A-Za-z_$][\w$]*)*', path):
            raise ValueError('callback must be a direct tear-off: ' + path)
        if path.startswith('this.'):
            path = path[5:]
        # Named record dependencies borrow the actual tear-off. Resolve only
        # exact configured member aliases to its currently owning declaration.
        member_alias = config.get('callback_member_aliases', {}).get(path)
        if member_alias:
            target = node_for(member_alias)
            return identity([target['name']], target['owner'])
        if '.' not in path:
            path = instances.get(owner, '$State') + '.' + path
        for alias in sorted(aliases, key=len, reverse=True):
            if path == alias:
                path = aliases[alias]
                break
            if path.startswith(alias + '.'):
                path = aliases[alias] + path[len(alias):]
                break
        if path.startswith(('_owners.', '_sections.')):
            path = '$State.' + path
        return path

    for spec in specs:
        resolved = []
        # Getter detection only; a missing callback member is reported by the
        # guarded lookup below, so a failed lookup here must not raise.
        try:
            expected_node = node_for(spec['callback_member']) if 'callback_member' in spec else None
        except (KeyError, ValueError, IndexError):
            expected_node = None
        is_getter = expected_node is not None and expected_node['parameters'] is None
        for site in spec['sites']:
            try:
                node = node_for(site['member'])
                count = site.get('count', 1)
                occurrence = site.get('occurrence')
                if 'partition_element' in site:
                    partition = config['callback_partitions'][site['member']]
                    piece = next(piece for piece in partition
                                 if piece['first_element'] <= site['partition_element'] < piece['end_element'])
                    piece_node = lookup.get((piece['file'], piece['owner'], piece['name']))
                    if piece_node is not None:
                        node = piece_node
                        count = site['piece_count']
                        occurrence = site['piece_occurrence']
                call_name = site['call']
                values = tokens(node)
                if 'call_member' in site:
                    call_name = node_for(site['call_member'])['name']
                else:
                    # A manifest-renamed callee is looked up under its new name.
                    call_row = by_original.get(call_name)
                    if call_row and call_row['new_name'] in values:
                        call_name = call_row['new_name']
                calls = arguments(values, call_name)
                if len(calls) != count:
                    raise ValueError(f"expected {count} {call_name} calls, got {len(calls)}")
                for call in ([calls[occurrence]] if occurrence is not None else calls):
                    resolved.append(identity(callback_argument(call, site), node['owner'], getter=is_getter))
            except (KeyError, ValueError, IndexError) as error:
                errors.append(f"Callback identity {spec['name']}: {error}")
        if 'callback_member' in spec:
            try:
                expected_node = node_for(spec['callback_member'])
                resolved.append(identity([expected_node['name']], expected_node['owner']))
            except (KeyError, ValueError, IndexError) as error:
                errors.append(f"Callback identity {spec['name']}: {error}")
        if resolved and len(set(resolved)) != 1:
            errors.append(f"Callback identity {spec['name']} differs: {resolved}")
    return errors
