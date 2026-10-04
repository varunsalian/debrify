#!/usr/bin/env python3
"""Resolve listener tear-offs before the move check erases receiver qualifiers.

Instances, not merely their classes, define callback identity. This checker is
opt-in through the TorBox config; other manifest configurations are unchanged.
"""
import re


def arguments(values, method):
    found = []
    for i, value in enumerate(values[:-1]):
        if value != method or values[i + 1] != '(':
            continue
        depth, current, args = 0, [], []
        for token in values[i + 2:]:
            if token == ')' and depth == 0:
                if current:
                    args.append(current)
                found.append(args)
                break
            if token == ',' and depth == 0:
                args.append(current)
                current = []
                continue
            if token in ('(', '[', '{'):
                depth += 1
            elif token in (')', ']', '}'):
                depth -= 1
            current.append(token)
    return found


def callback_argument(call, argument):
    """Select one positional argument or one exact named argument value."""
    if isinstance(argument, int):
        return call[argument]
    matches = [expr[2:] for expr in call if expr[:2] == [argument, ':']]
    if len(matches) != 1:
        raise ValueError(f'expected one named argument {argument}, got {len(matches)}')
    return matches[0]


def check_callback_identities(lookup, rows, source_path, config):
    from check_settings_moves import tokens
    specs = config.get('callback_identities', [])
    if not specs:
        return []
    by_original = {row['original_name']: row for row in rows}
    aliases = config.get('callback_receiver_aliases', {})
    instances = config.get('callback_instances', {})
    errors = []

    def node_for(original):
        row = by_original[original]
        key = (row['destination_file'], row['destination_class'], row['new_name'])
        if key in lookup:
            return lookup[key]
        owner, _, name = original.rpartition('.')
        return lookup[(source_path, owner, name)]

    def identity(expr, owner):
        expr = list(expr)
        if expr[-1:] == ['!']:
            expr.pop()
        path = ''.join(expr)
        if not re.fullmatch(r'[A-Za-z_$][\w$]*(?:\.[A-Za-z_$][\w$]*)*', path):
            raise ValueError('callback must be a direct tear-off: ' + path)
        if path.startswith('this.'):
            path = path[5:]
        if '.' not in path:
            path = instances.get(owner, '$State') + '.' + path
        for alias in sorted(aliases, key=len, reverse=True):
            if path.startswith(alias + '.'):
                path = aliases[alias] + path[len(alias):]
                break
        if path.startswith(('_owners.', '_sections.')):
            path = '$State.' + path
        return path

    for spec in specs:
        resolved = []
        for site in spec['sites']:
            try:
                node = node_for(site['member'])
                calls = arguments(tokens(node), site['call'])
                if len(calls) != site.get('count', 1):
                    raise ValueError(f"expected {site.get('count', 1)} {site['call']} calls, got {len(calls)}")
                for call in ([calls[site['occurrence']]] if 'occurrence' in site else calls):
                    resolved.append(identity(callback_argument(call, site['argument']), node['owner']))
            except (KeyError, ValueError, IndexError) as error:
                errors.append(f"Callback identity {spec['name']}: {error}")
        if 'callback_member' in spec:
            expected_node = node_for(spec['callback_member'])
            resolved.append(identity([expected_node['name']], expected_node['owner']))
        if resolved and len(set(resolved)) != 1:
            errors.append(f"Callback identity {spec['name']} differs: {resolved}")
    return errors
