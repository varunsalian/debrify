#!/usr/bin/env python3
"""Settings-specific named transformations, partition and context-guard evidence.

Called by check_verbatim_moves.py for settings_manifest.tsv. Uses the same
analyzer token adapter; the launcher verifier and its fixtures remain intact.
"""
from collections import Counter
import difflib
import json
import re
from pathlib import Path

ALLOWED = {'unchanged', 'rename', 'receiver', 'state_callback', 'context_guard',
           'lifecycle_wiring', 'layout_body', 'layout_first_param',
           'layout_legacy_param', 'live_service_getter', 'partition',
           'summary_accessor'}


def tokens(node, start=None, end=None):
    return [t['text'] for t in node['tokens']
            if (start is None or t['offset'] >= start)
            and (end is None or t['offset'] < end)]


def names(rows):
    # Ambiguous method names (e.g. build) are declaration-local below.
    candidates = {}
    for r in rows:
        old = r['original_name'].split('.')[-1]
        candidates.setdefault(old, set()).add(r['new_name'])
    return {old: next(iter(news)) for old, news in candidates.items()
            if len(news) == 1 and old != next(iter(news))}


def normalize(values, rows, row=None):
    mapping = names(rows)
    mapped = set(mapping.values()) | {r['new_name'] for r in rows}
    out = []
    i = 0
    while i < len(values):
        value = values[i]
        # Injected context acquisition is checked separately BEFORE removing it.
        if values[i:i + 9] == ['final', 'context', '=', '_deps', '.', 'context', '(', ')', ';']:
            i += 9
            continue
        if values[i:i + 4] == ['context', '.', 'mounted', '(']:
            raise ValueError('context.mounted is a property, not a callback')
        if values[i:i + 3] == ['context', '.', 'mounted']:
            out.append('mounted'); i += 3; continue
        if value in {'_deps', '_summaries', 'layout'} and i + 2 < len(values) and values[i + 1] == '.':
            target = values[i + 2]
            if target in mapped or target in {'mounted', 'setState', 'context', 'summaryReadOverrides'}:
                if target in {'mounted', 'context', 'summaryReadOverrides'} and values[i + 3:i + 5] == ['(', ')']:
                    out.extend(['widget', '.', target] if target == 'summaryReadOverrides' else [target])
                    i += 5; continue
                i += 2; continue
        if value.startswith(('//', '/*')):
            # Preserve comment contents, allowing documented identifier renames.
            for old, new in mapping.items():
                value = re.sub(r'\b' + re.escape(old) + r'\b', new, value)
            out.append(re.sub(r'\s+', '', value))
        else:
            out.append(mapping.get(value, value))
        i += 1
    return out


def context_events(node):
    """Owned context reads/acquisition and guards by closure, excluding builders.

    The first context read must have exactly the same preceding guard sequence
    in its callback. A context.mounted property stands for the original mounted
    guard; it does not count as a fresh context acquisition. Every subsequent
    guard must remain in the same scope too. Comparing meaningful scopes in
    lexical order tolerates preamble local functions becoming builder methods.
    """
    code = [t for t in node['tokens'] if not t['comment']]
    indexes = {t['offset']: i for i, t in enumerate(code)}
    groups = {}
    events_by_offset = []
    for ref in node['references']:
        name = ref['name']
        if name not in {'context', 'mounted'} or ref['contextParameter']:
            continue
        i = indexes.get(ref['offset'])
        if i is None:
            continue
        following = [t['text'] for t in code[i:i + 3]]
        if name == 'context' and following == ['context', '.', 'mounted']:
            continue
        # The explicit injected acquisition and its later local uses count as
        # the same first-context event, not two independent guards.
        events_by_offset.append((ref['offset'], ref['scope'], 'guard' if name == 'mounted' else 'context'))
    # Await boundaries matter too: an acquisition cannot jump above an
    # awaited permission gate, even when that gate has no mounted reference.
    for token in code:
        if token['text'] == 'await':
            callbacks = [c for c in node['callbacks'] if c['offset'] <= token['offset'] < c['end']]
            callback = callbacks[-1] if callbacks else None
            if callback and 'context' in callback['parameters']:
                continue
            events_by_offset.append((token['offset'], callback['scope'] if callback else '', 'await'))
    for _, scope, event in sorted(events_by_offset):
        groups.setdefault(scope, []).append(event)
    return [([e for e in events[:events.index('context')] if e in {'guard', 'await'}]
             if 'context' in events else None,
             events.count('guard')) for events in groups.values()]


def check_context(before, after):
    expected, actual = context_events(before), context_events(after)
    return [] if expected == actual else [f'Context/guard scope or first-use position changed: {expected} -> {actual}']


def partition_elements(node):
    result = node.get('returnedList')
    if result is None:
        raise ValueError('Partition method must return one top-level list literal: ' + node['name'])
    return result['elements']


def compare_elements(before, after, rows):
    # Compare the AST partition units individually, not just flattened text.
    # Splitting if/for into spread/condition fragments cannot preserve this list.
    a = [(e['kind'], normalize(tokens(before, e['offset'], e['end']), rows))
         for e in partition_elements(before)]
    b = [(e['kind'], normalize(tokens(node, e['offset'], e['end']), rows))
         for node in after for e in partition_elements(node)]
    return [] if a == b else ['Partition elements changed, reordered, dropped, duplicated or split']


def check_preamble(before, spec, lookup, rows, package=None):
    """Local functions/consts stay exact; final initializers run in the ctor.

    Field type annotations are structural. The initializer expression, local
    function signature/body and declaration order are compared in full.
    """
    from check_verbatim_moves import parse
    errors = []
    owner, path = spec['builder_class'], spec['builder_file']
    constructor = lookup.get((path, owner, owner))
    finals = []
    for declaration in before['returnedList']['preamble']:
        name = declaration['names'][0]
        member = lookup.get((path, owner, name))
        if member is None:
            errors.append('Missing builder preamble member: ' + name); continue
        text = declaration['text']
        parsed = parse({'local': 'class Local { ' + text + ' }'}, package)['local']['declarations'][0]['members'][0]
        expected = normalize(tokens(parsed), rows)
        actual = normalize(tokens(member), rows)
        if declaration['kind'].startswith('FunctionDeclaration'):
            if expected != actual:
                errors.append('Builder preamble function changed: ' + name)
        elif expected[0] == 'const':
            if actual[0] != 'static' or expected != actual[1:]:
                errors.append('Builder preamble constant changed: ' + name)
        elif expected[0] == 'final':
            finals.append(name)
            if constructor is None:
                errors.append('Missing fresh builder constructor'); continue
            matches = [i for i in constructor['initializers'] if i['name'] == name]
            if len(matches) != 1 or 'final' not in actual or '=' in actual:
                errors.append('Builder final must be initialized once in constructor: ' + name); continue
            initializer = matches[0]
            old = parsed['variables'][0]
            if normalize(tokens(parsed, old['initializerOffset'], old['initializerEnd']), rows) != normalize(tokens(constructor, initializer['expressionOffset'], initializer['expressionEnd']), rows):
                errors.append('Builder initializer changed: ' + name)
        else:
            errors.append('Unsupported builder preamble declaration: ' + name)
    if constructor:
        order = [i['name'] for i in constructor['initializers'] if i['name'] in finals]
        if order != finals:
            errors.append('Builder preamble initialization order changed')
    expected_order = spec['preamble_names']
    actual_order = [name for _, name in sorted(
        (node['offset'], name) for (file, cls, name), node in lookup.items()
        if file == path and cls == owner and name in expected_order)]
    if actual_order != expected_order:
        errors.append('Builder preamble declaration order changed')
    return errors


def check_partition(before, current, spec, lookup, rows, package=None):
    errors = []
    original = partition_elements(before)
    slices = spec['slices']
    cursor = 0
    for item in slices:
        start, end = item['first_element'], item['end_element']
        if start != cursor or not start < end <= len(original):
            errors.append('Invalid/non-contiguous partition boundary: ' + item['name'])
        elif 'cut_line' in item and (item['cut_line'] != original[start]['line']
                                     or item['last_line'] != original[end - 1]['endLine']):
            errors.append('Manifest cut lines differ from original AST boundaries: ' + item['name'])
        cursor = end
    if cursor != len(original):
        errors.append('Partition does not cover every original element')
    # Before step 5, the real original method remains and the proposed cuts
    # are checked against its complete AST elements.
    if current.get('returnedList') and len(partition_elements(current)) == len(original):
        errors.extend(compare_elements(before, [current], rows))
        a = before['returnedList']['preamble']
        b = current['returnedList']['preamble']
        if [x['text'] for x in a] != [x['text'] for x in b]:
            errors.append('Unmoved partition preamble changed')
        return errors
    actual_slices = []
    for item in slices:
        key = (item['file'], item.get('owner', ''), item['name'])
        node = lookup.get(key)
        if node is None:
            errors.append('Missing partition slice: ' + str(key)); continue
        actual_slices.append(node)
        expected = original[item['first_element']:item['end_element']]
        if len(partition_elements(node)) != len(expected):
            errors.append('Slice boundary/count changed: ' + item['name'])
    if len(actual_slices) == len(slices):
        errors.extend(compare_elements(before, actual_slices, rows))
    # The dispatcher MUST construct a new builder every call and join each
    # slice exactly once in the manifest order; it cannot cache a result.
    code = normalize(tokens(current, current['bodyOffset']), rows)
    expected = ['{', 'final', 'b', '=', spec['builder_class'], '(']
    expected += spec.get('constructor_arguments', ['_deps'])
    expected += [')', ';', 'return', '[']
    for item in slices:
        expected += ['...', 'b', '.', item['name'], '(', ')', ',']
    expected += [']', ';', '}']
    # Formatting may add the last comma, but every spread and receiver is exact.
    if code[-4:] == [')', ']', ';', '}']:
        code.insert(len(code) - 3, ',')
    if code != expected:
        errors.append('Partition dispatcher must construct a fresh builder and join exactly in manifest order')
    errors.extend(check_preamble(before, spec, lookup, rows, package))
    return errors


def all_nodes(parsed):
    found = {}
    for path, unit in parsed.items():
        for d in unit['declarations']:
            found[path, '', d['name']] = d
            for m in d['members']:
                found[path, d['name'], m['name']] = m
    return found


def check(original_source, sources, rows, source_path, package=None,
          partition=False, context_guard=False):
    from check_verbatim_moves import parse, original_leaves, split_names, missing_line_comments, ROOT
    parsed = parse({'<original>': original_source, **sources}, package)
    original = original_leaves(parsed['<original>']['declarations'], split_names(rows))
    errors = missing_line_comments(original_source, sources, rows)
    known = {r['original_name'] for r in rows}
    if set(original) != known:
        return ['Settings manifest coverage differs: ' + str(sorted(set(original) ^ known))]
    lookup = all_nodes(parsed)
    mapping = names(rows)
    # Retained/moved widget class headers are also part of the contract. New
    # section classes have no original header; original widget headers do.
    for declaration in parsed['<original>']['declarations']:
        if not declaration['members']:
            continue
        name = declaration['name']
        new_name = mapping.get(name, name)
        headers = [d for path, unit in parsed.items() if path != '<original>'
                   for d in unit['declarations'] if d['name'] in {name, new_name}]
        if len(headers) != 1:
            errors.append('Widget class missing or duplicated: ' + name); continue
        def header(node):
            values = tokens(node)
            return normalize(values[:values.index('{')], rows)
        if header(declaration) != header(headers[0]):
            errors.append('Widget class header changed: ' + name)
    partitions = json.loads((ROOT / 'dev/tool/settings_partitions.json').read_text())['partitions']
    for row in rows:
        key = row['original_name']
        if set(row['allowed_edits'].split(',')) - ALLOWED:
            errors.append('Unknown allowed edit: ' + key)
        old_owner, _, old_name = key.rpartition('.')
        if not old_owner: old_name = key
        in_place = lookup.get((source_path, old_owner, old_name))
        destination = lookup.get((row['destination_file'], row['destination_class'], row['new_name']))
        actual = destination or in_place
        before = original[key]
        if actual is None:
            errors.append('Missing settings declaration: ' + key); continue
        if destination is not None and in_place is not None and destination is not in_place:
            errors.append('Duplicate settings owner: ' + key)
        if partition and key in partitions:
            errors.extend(key + ': ' + e for e in check_partition(before, actual, partitions[key], lookup, rows, package))
        elif normalize(tokens(before), rows, row) != normalize(tokens(actual), rows, row):
            diff = '\n'.join(list(difflib.unified_diff(normalize(tokens(before), rows), normalize(tokens(actual), rows)))[:45])
            errors.append('Non-verbatim settings declaration: ' + key + '\n' + diff)
        if context_guard and 'context_guard' in row['allowed_edits']:
            errors.extend(key + ': ' + e for e in check_context(before, actual))
    # Only the registered single test accessor is new in the facade at step 0.
    leaves = original_leaves(parsed[source_path]['declarations'], split_names(rows))
    extras = set(leaves) - known - {'settingsScreenTestAccess'}
    if extras:
        errors.append('Unregistered facade declarations: ' + str(sorted(extras)))
    accessor = lookup.get((source_path, '', 'settingsScreenTestAccess'))
    if accessor is not None:
        expected = json.loads((ROOT / 'dev/tool/settings_test_accessor.json').read_text())
        if normalize(tokens(accessor), rows) != normalize(expected, rows):
            errors.append('Test accessor changed outside its registered receiver edits')
    return errors


def self_test(package=None):
    from check_verbatim_moves import parse
    def method(source):
        return parse({'test': 'class Test { ' + source + ' }'}, package)['test']['declarations'][0]['members'][0]
    before = method('List<Object> entries() { final x = 1; return [x, if (true) ...[2, 3], for (final n in [4]) n]; }')
    good = [method('List<Object> one() { return [x]; }'),
            method('List<Object> two() { return [if (true) ...[2, 3], for (final n in [4]) n]; }')]
    if compare_elements(before, good, []):
        raise AssertionError('Valid whole-element partition rejected')
    mutations = {
        'reordered slice': list(reversed(good)),
        'dropped element': [good[0]],
        'duplicated element': [good[0], *good],
        'split collection-if': [good[0], method('List<Object> two() { return [if (true) 2, if (true) 3, for (final n in [4]) n]; }')],
        'split collection-for': [good[0], method('List<Object> two() { return [if (true) ...[2, 3], 4]; }')],
    }
    for label, nodes in mutations.items():
        if not compare_elements(before, nodes, []):
            raise AssertionError('Accepted ' + label)
        print('Settings self-test ' + label + ': rejected')
    spec = {'builder_class': 'B', 'builder_file': 'builder',
            'constructor_arguments': [], 'preamble_names': ['x'], 'slices': [
                {'file': 'builder', 'owner': 'B', 'name': 'one', 'first_element': 0, 'end_element': 1},
                {'file': 'builder', 'owner': 'B', 'name': 'two', 'first_element': 1, 'end_element': 3}]}
    builder = 'class B { B() : x = 1; final int x; List<Object> one() { return [x]; } List<Object> two() { return [if (true) ...[2, 3], for (final n in [4]) n]; } }'
    parsed_builder = parse({'builder': builder}, package)
    lookup = all_nodes(parsed_builder)
    dispatch = method('List<Object> entries() { final b = B(); return [...b.one(), ...b.two()]; }')
    errors = check_partition(before, dispatch, spec, lookup, [], package)
    if errors:
        raise AssertionError('Valid builder/dispatcher rejected: ' + str(errors))
    for label, changed in {
        'changed preamble initializer': builder.replace('x = 1', 'x = 9'),
        'non-final preamble field': builder.replace('final int x', 'int x'),
        'missing preamble field': builder.replace('final int x;', ''),
    }.items():
        if not check_partition(before, dispatch, spec, all_nodes(parse({'builder': changed}, package)), [], package):
            raise AssertionError('Accepted ' + label)
        print('Settings self-test ' + label + ': rejected')
    reordered = method('List<Object> entries() { final b = B(); return [...b.two(), ...b.one()]; }')
    if not check_partition(before, reordered, spec, lookup, [], package):
        raise AssertionError('Accepted reordered dispatcher')
    print('Settings self-test reordered dispatcher: rejected')
    original = method('void snack() { if (!mounted) return; ScaffoldMessenger.of(context); }')
    good_context = method('void snack() { if (!_deps.mounted()) return; final context = _deps.context(); ScaffoldMessenger.of(context); }')
    bad_context = method('void snack() { final context = _deps.context(); if (!_deps.mounted()) return; ScaffoldMessenger.of(context); }')
    if check_context(original, good_context) or not check_context(original, bad_context):
        raise AssertionError('Context guard self-test failed')
    print('Settings self-test context fetched before guard: rejected')
    delayed = method('void finish() { future.then((_) { if (!mounted) return; show(context); }); }')
    hoisted = method('void finish() { final context = _deps.context(); future.then((_) { if (!_deps.mounted()) return; show(context); }); }')
    if not check_context(delayed, hoisted):
        raise AssertionError('Accepted context hoisted out of deferred callback')
    print('Settings self-test context hoisted before deferred guard: rejected')
    shadow = method('void snack() { if (!mounted) return; show(context, builder: (context) => show(context)); }')
    shadow_good = method('void snack() { if (!_deps.mounted()) return; final context = _deps.context(); show(context, builder: (context) => show(context)); }')
    if check_context(shadow, shadow_good):
        raise AssertionError('Builder context incorrectly treated as State context')
    print('Settings self-test builder parameter context: passed')
