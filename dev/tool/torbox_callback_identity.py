#!/usr/bin/env python3
"""Resolve listener tear-offs before the move check erases receiver qualifiers.

Instances, not merely their classes, define callback identity. This checker is
opt-in through the TorBox config; other manifest configurations are unchanged.
"""
import re


def argument_ranges(values, method):
    """Return exact token spans for each argument of each matching call."""
    found = []
    for i, value in enumerate(values[:-1]):
        if value != method or values[i + 1] != '(':
            continue
        depth, start, args = 0, i + 2, []
        for j in range(i + 2, len(values)):
            token = values[j]
            if token == ')' and depth == 0:
                if j > start:
                    args.append((start, j))
                found.append(args)
                break
            if token == ',' and depth == 0:
                args.append((start, j))
                start = j + 1
                continue
            # Interpolation opens a brace pair within a string argument.
            if token in ('(', '[', '{', '${'):
                depth += 1
            elif token in (')', ']', '}'):
                depth -= 1
    return found


def arguments(values, method):
    return [[values[start:end] for start, end in call]
            for call in argument_ranges(values, method)]


def argument_expression(call, selector):
    """Select a positional argument or one exact named argument's expression."""
    call = [[token for token in arg if not token.startswith(('//', '/*'))]
            for arg in call]
    if isinstance(selector, int):
        return call[selector]
    matches = [arg[2:] for arg in call if arg[:2] == [selector, ':']]
    if len(matches) != 1:
        raise ValueError(f'expected one named argument {selector}, got {len(matches)}')
    return matches[0]


def member_occurrences(values, member):
    """Find member reads, excluding constructor/record named labels.

    A renamed getter can have the same name as a nested named argument. Map
    keys remain expressions; only labels within parentheses are excluded.
    """
    stack, found = [], []
    for i, value in enumerate(values):
        previous = next((v for v in reversed(values[:i])
                         if not v.startswith(('//', '/*'))), None)
        label = (stack[-1:] == ['('] and previous in ('(', ',')
                 and values[i + 1:i + 2] == [':'])
        if value == member and not label:
            found.append(i)
        if value in ('(', '[', '{', '${'):
            stack.append(value)
        elif value in (')', ']', '}') and stack:
            stack.pop()
    return found


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
            if path == alias or path.startswith(alias + '.'):
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
                    expr = argument_expression(call, site['argument'])
                    if 'conditional_member' in site:
                        # Check a direct branch tear-off in an otherwise
                        # verbatim conditional argument. Its surrounding
                        # conditions remain covered by the whole-leaf check.
                        target = node_for(site['conditional_member'])['name']
                        positions = member_occurrences(expr, target)
                        occurrence = site.get('branch_occurrence', 0)
                        if len(positions) != site.get('branch_count', 1):
                            raise ValueError('conditional tear-off occurrence count changed: ' + target)
                        end = positions[occurrence] + 1
                        start = end - 1
                        while start >= 2 and expr[start - 1] == '.':
                            start -= 2
                        if (expr[start - 1:start] not in (['?'], [':'])
                                or expr[end:end + 1] not in ([], [':'], [')'])):
                            raise ValueError('conditional branch must be a direct tear-off: ' + target)
                        expr = expr[start:end]
                    resolved.append(identity(expr, node['owner']))
            except (KeyError, ValueError, IndexError) as error:
                errors.append(f"Callback identity {spec['name']}: {error}")
        if 'callback_member' in spec:
            expected_node = node_for(spec['callback_member'])
            resolved.append(identity([expected_node['name']], expected_node['owner']))
        if resolved and len(set(resolved)) != 1:
            errors.append(f"Callback identity {spec['name']} differs: {resolved}")
    return errors
