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
        depth, start, args = 0, opening + 1, []
        for j in range(opening + 1, len(values)):
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
            # '${' opens a string interpolation whose '}' is counted as a
            # closer; without it the depth never returns to 0 and the call
            # is silently dropped.
            if token in ('(', '[', '{', '${'):
                depth += 1
            elif token in (')', ']', '}'):
                depth -= 1
    return found


def arguments(values, method):
    return [[values[start:end] for start, end in call]
            for call in argument_ranges(values, method)]


def callback_argument(call, site):
    """Resolve one exact positional or named callback without erasing its value.

    A named argument is given either as `named_argument` or, in older
    configurations, as a string `argument`; an int `argument` is positional.
    A bare int or string may be passed instead of a site.
    """
    if not isinstance(site, dict):
        site = {'argument': site}
    call = [[token for token in arg if not token.startswith(('//', '/*'))]
            for arg in call]
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
    from check_settings_moves import tokens, normalize
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
                # Opt-in callee aliases retain the original private constructor.
                call_alias = config.get('callback_call_aliases', {}).get(call_name)
                if call_alias and call_alias in values:
                    call_name = call_alias
                calls = arguments(values, call_name)
                if len(calls) != count:
                    raise ValueError(f"expected {count} {call_name} calls, got {len(calls)}")
                for call in ([calls[occurrence]] if occurrence is not None else calls):
                    expr = callback_argument(call, site)
                    closure = spec.get('closure')
                    if closure is not None:
                        if config.get('callback_closure_binding') is not True:
                            raise ValueError('closure binding requires config opt-in')
                        parameters = closure['parameters']
                        if expr[:len(parameters) + 1] != [*parameters, '=>']:
                            raise ValueError('closure parameter list or arrow changed')
                        body = expr[len(parameters) + 1:]
                        if body.count('=>') or '(' not in body or body[-1:] != [')']:
                            raise ValueError('closure must invoke exactly its bound member')
                        opening = body.index('(')
                        invoked = body[:opening]
                        # Validate the receiver BEFORE normalization, using the
                        # same instance/member resolution as direct tear-offs.
                        bound = identity(invoked, node['owner'])
                        calls_in_body = arguments(body, invoked[-1])
                        if len(calls_in_body) != 1:
                            raise ValueError('closure invocation shape changed')
                        actual = [normalize(arg, rows) for arg in calls_in_body[0]]
                        expected = [normalize(arg, rows) for arg in closure['arguments']]
                        if actual != expected:
                            raise ValueError('closure argument tokens changed')
                        # No enclosing wrapper, chained invocation, or suffix.
                        if body != [*invoked, '(', *sum(
                            [arg + ([','] if i + 1 < len(calls_in_body[0]) else [])
                             for i, arg in enumerate(calls_in_body[0])], []), ')']:
                            raise ValueError('closure invocation is wrapped or chained')
                        resolved.append(bound)
                    else:
                        if 'conditional_member' in site:
                            # Check a direct branch tear-off in an otherwise
                            # verbatim conditional argument. Its surrounding
                            # conditions remain covered by the whole-leaf check.
                            target = node_for(site['conditional_member'])['name']
                            positions = member_occurrences(expr, target)
                            branch = site.get('branch_occurrence', 0)
                            if len(positions) != site.get('branch_count', 1):
                                raise ValueError('conditional tear-off occurrence count changed: ' + target)
                            end = positions[branch] + 1
                            start = end - 1
                            while start >= 2 and expr[start - 1] == '.':
                                start -= 2
                            if (expr[start - 1:start] not in (['?'], [':'])
                                    or expr[end:end + 1] not in ([], [':'], [')'])):
                                raise ValueError('conditional branch must be a direct tear-off: ' + target)
                            expr = expr[start:end]
                        resolved.append(identity(expr, node['owner'], getter=is_getter))
            except (KeyError, ValueError, IndexError) as error:
                errors.append(f"Callback identity {spec['name']}: {error}")
        if 'callback_member' in spec:
            try:
                expected_node = node_for(spec['callback_member'])
                resolved.append(identity([expected_node['name']], expected_node['owner']))
            except (KeyError, ValueError, IndexError) as error:
                errors.append(f"Callback identity {spec['name']}: {error}")
        if 'expected_identity' in spec:
            resolved.append(spec['expected_identity'])
        if resolved and len(set(resolved)) != 1:
            errors.append(f"Callback identity {spec['name']} differs: {resolved}")
    return errors
