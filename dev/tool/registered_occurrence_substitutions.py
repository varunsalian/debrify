"""Opt-in exact dependency-expression projections before occurrence alignment.

Only ORIGINAL unbound identifiers at registered token chains are projected.
The projected AST supplies the invocation role and nested qualifier shape;
lexical scopes are still compared occurrence by occurrence by the binder.
No expression in destination source is rewritten or accepted here.
"""
import re


def rewrite(node, specs):
    tokens = node['tokens']
    values = [t['text'] for t in tokens]
    refs = {o['tokenIndex']: o for o in node.get('occurrences', [])}
    edits = {}
    for i, value in enumerate(values):
        occurrence = refs.get(i)
        if not occurrence or occurrence['kind'] != 'lexical' or occurrence['binding'] != 'unbound':
            continue
        for spec in specs:
            before, after = spec['before'], spec['after']
            if values[i:i+len(before)] != before:
                continue
            # Register roles explicitly; the AST will enforce the actual role
            # at each ordinal, including writes and a nullable callback call.
            if spec['binding'] != 'unbound' or not spec['role_change']:
                raise ValueError('Registered substitution lacks binding/role evidence')
            start, end = tokens[i]['offset'], tokens[i+len(before)-1]['offset'] + len(values[i+len(before)-1])
            replacement = ''.join(after)
            edits[start] = (end-start, replacement)
            break
    text = node['text']
    for offset, (size, replacement) in sorted(edits.items(), reverse=True):
        at = offset-node['start']
        text = text[:at]+replacement+text[at+size:]
    return text


def project(original, config, package, keys):
    specs = config.get('registered_occurrence_substitutions', [])
    if not specs:
        return original
    if package is None:
        raise ValueError('Registered substitutions require the isolated parser package')
    from check_verbatim_moves import parse
    sources = {}
    for key, node in original.items():
        if key not in keys or node['owner'] not in config['occurrence_field_bindings']['state_classes']:
            continue
        changed = rewrite(node, specs)
        if key in config.get('occurrence_layout_bodies', []):
            code = [t for t in node['tokens'] if not t['comment']]
            if [t['text'] for t in code[:2]] != ['@', 'override']:
                raise ValueError('Layout projection lacks original override: '+key)
            start, end = code[0]['offset']-node['start'], code[1]['offset']-node['start']+len('override')
            changed = changed[:start]+changed[end:]
        if changed != node['text']:
            sources[key] = 'class '+node['owner']+' { '+changed+' }'
    parsed = parse(sources, package, occurrence_bindings=True) if sources else {}
    result = dict(original)
    for key, unit in parsed.items():
        members = unit['declarations'][0]['members']
        if len(members) != 1 or members[0]['name'] != original[key]['name']:
            raise ValueError('Projection changed declaration ownership: '+key)
        result[key] = members[0]
    return result


def canonical_tokens(values, specs):
    """Reverse exact registered destination chains, without touching literals."""
    out=[]; i=0
    while i<len(values):
        match=next((s for s in specs if values[i:i+len(s['after'])]==s['after']),None)
        if match and (i==0 or values[i-1] not in ('.','?.')):
            out.extend(match['before']); i+=len(match['after'])
        else:
            out.append(values[i]); i+=1
    return out
