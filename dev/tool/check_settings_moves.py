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
           'summary_accessor', 'production_api_annotation',
           'classic_update_indicator_const', 'public_widget_key'}

PUBLIC_WIDGET_KEY_DIFFERENCE = 'public_widget_key: add optional super.key only; no caller passes a key'
RECEIVERS = {'_deps', '_summaries', 'layout', '_connections'}

NAMED_EXCEPTIONS = {
    'production_api_annotation': (
        'shouldApplyPendingCredentialOverride',
        'lib/features/settings/application/settings_pending_credentials.dart',
        'production_api_annotation: remove only @visibleForTesting; production API'),
    'classic_update_indicator_const': (
        '_SettingsLayout.build',
        'lib/features/settings/presentation/settings_classic_layout.dart',
        'classic_update_indicator_const: add const only to checkingUpdates trailing SizedBox; child CircularProgressIndicator inherits const context'),
}


def named_exception_tokens(values, row):
    """User-authorized edits, at exact baseline token sequences only."""
    values = list(values)
    if 'production_api_annotation' in row['allowed_edits'].split(','):
        if values[:2] != ['@', 'visibleForTesting']:
            raise ValueError('Production API exception requires the original annotation')
        del values[:2]
    if 'classic_update_indicator_const' in row['allowed_edits'].split(','):
        sequence = ['trailing', ':', 'checkingUpdates', '?', 'SizedBox', '(',
                    'width', ':', '20', ',', 'height', ':', '20', ',',
                    'child', ':', 'CircularProgressIndicator', '(',
                    'strokeWidth', ':', '2.5', ')', ')', ':', 'null']
        matches = [i for i in range(len(values))
                   if values[i:i + len(sequence)] == sequence]
        if len(matches) != 1:
            raise ValueError('Classic const exception must match exactly one original update indicator')
        values.insert(matches[0] + 4, 'const')
    if 'public_widget_key' in row['allowed_edits'].split(','):
        opening = values.index('(')
        named = values.index('{', opening)
        if named != opening + 1 or 'key' in values[opening:named]:
            raise ValueError('Public widget key exception requires the original named parameters')
        values[named + 1:named + 1] = ['super', '.', 'key', ',']
    return values


def check_named_exceptions(rows):
    errors = []
    for row in rows:
        if 'public_widget_key' in row['allowed_edits'].split(','):
            owner, _, constructor = row['original_name'].rpartition('.')
            if (not owner.startswith('_') or constructor != owner
                    or row['destination_class'] != owner[1:]
                    or row['new_name'] != owner[1:]
                    or row['expected_difference'] != PUBLIC_WIDGET_KEY_DIFFERENCE):
                errors.append('Public widget key exception must name one private-to-public constructor')
        for name in set(row['allowed_edits'].split(',')) & NAMED_EXCEPTIONS.keys():
            original, destination, difference = NAMED_EXCEPTIONS[name]
            if (row['original_name'], row['destination_file'], row['expected_difference']) != (original, destination, difference):
                errors.append('Named exception registered outside its exact declaration: ' + name)
    return errors


def check_lint_comments(original_source, sources):
    pattern = r'(?m)^\s*//\s*ignore(?:_for_file)?:[^\n]*'
    before = Counter(x.strip() for x in re.findall(pattern, original_source))
    after = Counter(x.strip() for source in sources.values()
                    for x in re.findall(pattern, source))
    return [] if before == after else ['Settings lint suppressions changed outside the authorized exceptions']


def tokens(node, start=None, end=None):
    punctuation = set(node.get('formatCommas', []))
    return [t['text'] for t in node['tokens']
            if (start is None or t['offset'] >= start)
            and (end is None or t['offset'] < end)
            and t['offset'] not in punctuation]


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
    if row and 'live_service_getter' in row['allowed_edits']:
        mapped.add('legacyReasonSummary')
    out = []
    i = 0
    while i < len(values):
        value = values[i]
        # A member qualification needs braces in a formerly simple string
        # interpolation. Canonicalize only an otherwise identical single read.
        if value == '${':
            if values[i + 1:i + 2] and values[i + 1] in RECEIVERS and values[i + 2:i + 3] == ['.'] and values[i + 4:i + 5] == ['}'] and values[i + 3] in mapped:
                out.extend(['$', mapping.get(values[i + 3], values[i + 3])])
                i += 5; continue
            if values[i + 2:i + 3] == ['}'] and values[i + 1] in mapping:
                out.extend(['$', mapping[values[i + 1]]])
                i += 3; continue
        # Injected context acquisition is checked separately BEFORE removing it.
        if values[i:i + 9] == ['final', 'context', '=', '_deps', '.', 'context', '(', ')', ';']:
            i += 9
            continue
        if values[i:i + 4] == ['context', '.', 'mounted', '(']:
            raise ValueError('context.mounted is a property, not a callback')
        if values[i:i + 3] == ['context', '.', 'mounted']:
            out.append('mounted'); i += 3; continue
        if value in RECEIVERS and i + 2 < len(values) and values[i + 1] == '.':
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
            for receiver in RECEIVERS:
                value = re.sub(r'\b' + re.escape(receiver) + r'\.(' + '|'.join(map(re.escape, mapped)) + r')\b', r'\1', value)
            out.append(re.sub(r'\s+', '', value))
        else:
            out.append(mapping.get(value, value))
        i += 1
    return out


def declaration_tokens(node, rows, row, *, original=False):
    """Apply ONLY the plan's named structural edits to the expected baseline.

    Actual signatures, defaults, widgets, tear-offs and bodies still compare
    completely. Commas are normalized only at AST argument/parameter-list ends;
    a record comma (which changes its type/value) is never removed.
    """
    values = normalize(tokens(node), rows, row)
    if not original:
        return values
    key = row['original_name']
    old = key.split('.')[-1]
    mapped = names(rows).get(old, old)
    # A common name such as build is renamed only on this declaration.
    if old != row['new_name'] and mapped != row['new_name']:
        index = values.index(mapped)
        values[index] = row['new_name']
    if 'layout_first_param' in row['allowed_edits']:
        opening = values.index('(')
        values[opening + 1:opening + 1] = ['SettingsLayout', 'layout', ',']
        # Calls get the layout argument; method tear-offs remain class methods.
        i = opening + 4
        while i < len(values) - 1:
            if values[i] in {'buildConnectionGrid', 'buildSpotlightLayout'} and values[i + 1] == '(':
                values[i + 2:i + 2] = ['layout', ',']
                i += 2
            i += 1
    if 'layout_body' in row['allowed_edits'] and values[:2] == ['@', 'override']:
        del values[:2]
    if key == '_SettingsLayout._SettingsLayout':
        sequence = ['required', 'this', '.', 'connections', ',']
        index = next(i for i in range(len(values)) if values[i:i + 5] == sequence) + 5
        values[index:index] = ['required', 'this', '.', 'legacyReasonSummary', ',']
    if key == '_SettingsScreenState._buildLayout':
        index = values.index('SettingsLayout') + 2
        values[index:index] = ['legacyReasonSummary', ':', '(', ')', '=>',
                              'ProfileBootstrap', '.', 'legacyReasonSummary', ',']
    if key == '_SettingsLayout._buildSpotlightCategory':
        sequence = ['ProfileBootstrap', '.', 'legacyReasonSummary']
        index = next(i for i in range(len(values)) if values[i:i + 3] == sequence)
        values[index:index + 3] = ['legacyReasonSummary', '(', ')']
    return named_exception_tokens(values, row)


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
    # Arguments are evaluated before suspension. The boundary is at the end
    # of the await operand, not at its keyword: `await show(context)` permits
    # the named context acquisition before that statement, while acquiring it
    # above a preceding awaited permission gate must still be rejected.
    for awaited in node['awaits']:
        if not awaited['contextParameter']:
            events_by_offset.append((awaited['end'], awaited['scope'], 'await'))
    for _, scope, event in sorted(events_by_offset):
        groups.setdefault(scope, []).append(event)
    return [([e for e in events[:events.index('context')] if e in {'guard', 'await'}]
             if 'context' in events else None,
             events.count('guard')) for events in groups.values()]


def context_prefixes(node, rows, row):
    """First owned context must start at the same original statement.

    Counting mounted/await alone misses a synchronous early-return guard or
    a service call before first context use. Compare the canonical statement
    prefix as well; the named injected acquisition is removed, but no original
    statement is ignored. Dialog/builder parameter contexts remain excluded.
    """
    code = [t for t in node['tokens'] if not t['comment']]
    indexes = {t['offset']: i for i, t in enumerate(code)}
    prefixes = {}
    for ref in node['references']:
        if ref['name'] != 'context' or ref['contextParameter']:
            continue
        i = indexes.get(ref['offset'])
        if i is None or [t['text'] for t in code[i:i + 3]] == ['context', '.', 'mounted']:
            continue
        if ref['scope'] not in prefixes:
            start = ref['statementOffset']
            prefixes[ref['scope']] = normalize(tokens(node, end=start), rows, row)
    return list(prefixes.values())


def check_context(before, after, rows=None, row=None):
    expected, actual = context_events(before), context_events(after)
    errors = [] if expected == actual else [f'Context/guard scope or first-use position changed: {expected} -> {actual}']
    if context_prefixes(before, rows or [], row) != context_prefixes(after, rows or [], row):
        errors.append('First owned context acquisition moved across an original statement/guard')
    return errors


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
    def add(key, node):
        if key in found:
            raise ValueError('Duplicate settings destination declaration: ' + str(key))
        found[key] = node
    for path, unit in parsed.items():
        for d in unit['declarations']:
            add((path, '', d['name']), d)
            for m in d['members']:
                add((path, d['name'], m['name']), m)
    return found


def destination_ownership(parsed, rows, source_path, scaffolds=()):
    """No unregistered original copy or extra feature helper can hide in a move.

    The three extra layout leaves are exactly the structural additions named
    in the plan and checked separately below. Later section/deps scaffolding
    must be registered explicitly when that step is implemented.
    """
    known = {(r['destination_file'], r['destination_class'], r['new_name'])
             for r in rows}
    known.update((s['file'], s['owner'], s['name']) for s in scaffolds)
    layout = 'lib/features/settings/presentation/settings_layout.dart'
    known.update((layout, 'SettingsLayout', name)
                 for name in ('legacyReasonSummary', 'build', 'buildSpotlightCategory'))
    owners = {(path, owner) for path, owner, _ in known if owner}
    errors = []
    for path, unit in parsed.items():
        if path in ('<original>', source_path):
            continue
        for declaration in unit['declarations']:
            name = declaration['name']
            if (path, '', name) in known:
                continue
            if (path, name) not in owners:
                errors.append('Unregistered settings destination owner: ' + str((path, name)))
            for member in declaration['members']:
                key = (path, name, member['name'])
                if key not in known:
                    errors.append('Unregistered settings destination leaf: ' + str(key))
    return errors


def check_scaffolds(lookup, scaffolds):
    errors = []
    for scaffold in scaffolds:
        key = (scaffold['file'], scaffold['owner'], scaffold['name'])
        node = lookup.get(key)
        if node is None or tokens(node) != scaffold['tokens']:
            errors.append('Registered settings scaffold changed: ' + str(key))
    return errors


def check(original_source, sources, rows, source_path, package=None,
          partition=False, context_guard=False):
    from check_verbatim_moves import parse, original_leaves, split_names, missing_line_comments, ROOT
    parsed = parse({'<original>': original_source, **sources}, package)
    original = original_leaves(parsed['<original>']['declarations'], split_names(rows))
    errors = missing_line_comments(original_source, sources, rows)
    errors.extend(check_named_exceptions(rows))
    errors.extend(check_lint_comments(original_source, sources))
    known = {r['original_name'] for r in rows}
    if set(original) != known:
        return ['Settings manifest coverage differs: ' + str(sorted(set(original) ^ known))]
    lookup = all_nodes(parsed)
    scaffold_path = ROOT / 'dev/tool/settings_scaffolding.json'
    scaffolds = (json.loads(scaffold_path.read_text())['scaffolds']
                 if source_path == 'lib/screens/settings_screen.dart' and scaffold_path.exists() else [])
    errors.extend(check_scaffolds(lookup, scaffolds))
    errors.extend(destination_ownership(parsed, rows, source_path, scaffolds))
    mapping = names(rows)
    # Retained/moved widget class headers are also part of the contract. New
    # section classes have no original header; original widget headers do.
    for declaration in parsed['<original>']['declarations']:
        if not declaration['members']:
            continue
        name = declaration['name']
        key_rows = [r for r in rows if r['original_name'] == name + '.' + name
                    and 'public_widget_key' in r['allowed_edits'].split(',')]
        if key_rows:
            values = tokens(declaration)
            if not any(values[i:i + 2] == ['extends', base]
                       for base in ('StatelessWidget', 'StatefulWidget')
                       for i in range(len(values))):
                errors.append('Public widget key exception used on a non-widget: ' + name)
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
        elif declaration_tokens(before, rows, row, original=destination is not None or (key == '_SettingsScreenState._buildLayout' and 'lib/features/settings/presentation/settings_layout.dart' in sources)) != declaration_tokens(actual, rows, row):
            diff = '\n'.join(list(difflib.unified_diff(declaration_tokens(before, rows, row, original=destination is not None or (key == '_SettingsScreenState._buildLayout' and 'lib/features/settings/presentation/settings_layout.dart' in sources)), declaration_tokens(actual, rows, row)))[:45])
            errors.append('Non-verbatim settings declaration: ' + key + '\n' + diff)
        if context_guard and 'context_guard' in row['allowed_edits']:
            errors.extend(key + ': ' + e for e in check_context(before, actual, rows, row))
    # Only the registered single test accessor is new in the facade at step 0.
    leaves = original_leaves(parsed[source_path]['declarations'], split_names(rows))
    registered_facade = {s['owner'] + '.' + s['name'] for s in scaffolds
                         if s['file'] == source_path}
    extras = set(leaves) - known - {'settingsScreenTestAccess'} - registered_facade
    if extras:
        errors.append('Unregistered facade declarations: ' + str(sorted(extras)))
    layout_path = 'lib/features/settings/presentation/settings_layout.dart'
    if layout_path in sources:
        required_field = lookup.get((layout_path, 'SettingsLayout', 'legacyReasonSummary'))
        if required_field is None or tokens(required_field) != ['final', 'String', 'Function', '(', ')', 'legacyReasonSummary', ';']:
            errors.append('Live legacyReasonSummary constructor field differs from the named edit')
        forwarders = {
            'build': ['@', 'override', 'Widget', 'build', '(', 'BuildContext', 'context', ')', '=>', 'buildClassicSettingsLayout', '(', 'this', ',', 'context', ')', ';'],
            'buildSpotlightCategory': ['Widget', 'buildSpotlightCategory', '(', 'BuildContext', 'context', ',', 'int', 'category', ')', '=>', 'spotlight', '.', 'buildSpotlightCategory', '(', 'this', ',', 'context', ',', 'category', ')', ';'],
        }
        for name, expected in forwarders.items():
            forwarder = lookup.get((layout_path, 'SettingsLayout', name))
            if forwarder is None or tokens(forwarder) != expected:
                errors.append('Layout forwarder signature or dispatch changed: ' + name)
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
    layout_row = {'original_name': '_SettingsLayout._buildSpotlight',
                  'new_name': 'buildSpotlightLayout',
                  'allowed_edits': 'rename,receiver,layout_first_param'}
    layout_before = method('Widget _buildSpotlight(BuildContext context) { return const Thing(); }')
    layout_after = method('Widget buildSpotlightLayout(SettingsLayout layout, BuildContext context) { return const Thing(); }')
    expected = declaration_tokens(layout_before, [layout_row], layout_row, original=True)
    if expected != declaration_tokens(layout_after, [layout_row], layout_row):
        raise AssertionError('Named layout first-parameter edit rejected')
    for label, text in {
        'changed layout parameter': 'Widget buildSpotlightLayout(Object layout, BuildContext context) { return const Thing(); }',
        'changed widget const': 'Widget buildSpotlightLayout(SettingsLayout layout, BuildContext context) { return Thing(); }',
    }.items():
        if expected == declaration_tokens(method(text), [layout_row], layout_row):
            raise AssertionError('Accepted ' + label)
        print('Settings self-test ' + label + ': rejected')
    api_row = dict(original_name='shouldApplyPendingCredentialOverride',
                   new_name='shouldApplyPendingCredentialOverride',
                   destination_file=NAMED_EXCEPTIONS['production_api_annotation'][1],
                   allowed_edits='production_api_annotation',
                   expected_difference=NAMED_EXCEPTIONS['production_api_annotation'][2])
    api_before = method('@visibleForTesting bool shouldApplyPendingCredentialOverride() => true;')
    api_after = method('bool shouldApplyPendingCredentialOverride() => true;')
    expected_api = declaration_tokens(api_before, [api_row], api_row, original=True)
    if check_named_exceptions([api_row]) or expected_api != declaration_tokens(api_after, [api_row], api_row):
        raise AssertionError('Authorized annotation-only exception rejected')
    for label, changed in {
        'retained production API annotation': api_before,
        'additional API annotation': method('@deprecated bool shouldApplyPendingCredentialOverride() => true;'),
        'changed production API body': method('bool shouldApplyPendingCredentialOverride() => false;'),
    }.items():
        if expected_api == declaration_tokens(changed, [api_row], api_row):
            raise AssertionError('Accepted ' + label)
        print('Settings self-test ' + label + ': rejected')
    for key, value in {'original_name': 'Other.helper', 'destination_file': 'other.dart',
                       'expected_difference': 'remove any annotation'}.items():
        if not check_named_exceptions([dict(api_row, **{key: value})]):
            raise AssertionError('Accepted widened named exception: ' + key)
    print('Settings self-test widened named exception: rejected')
    const_row = dict(original_name='_SettingsLayout.build',
                     new_name='buildClassicSettingsLayout',
                     destination_file=NAMED_EXCEPTIONS['classic_update_indicator_const'][1],
                     allowed_edits='classic_update_indicator_const',
                     expected_difference=NAMED_EXCEPTIONS['classic_update_indicator_const'][2])
    const_before_text = 'Widget build() { return Tile(trailing: checkingUpdates ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)) : null); }'
    const_after_text = const_before_text.replace('Widget build()', 'Widget buildClassicSettingsLayout()').replace('? SizedBox', '? const SizedBox')
    expected_const = declaration_tokens(method(const_before_text), [const_row], const_row, original=True)
    if check_named_exceptions([const_row]) or expected_const != declaration_tokens(method(const_after_text), [const_row], const_row):
        raise AssertionError('Authorized exact update-indicator const exception rejected')
    for label, changed in {
        'missing update indicator const': const_after_text.replace('? const SizedBox', '? SizedBox'),
        'additional nested const': const_after_text.replace('child: CircularProgressIndicator', 'child: const CircularProgressIndicator'),
        'changed indicator dimensions': const_after_text.replace('width: 20', 'width: 21'),
        'const on another widget': const_after_text.replace('return Tile', 'return const Tile'),
    }.items():
        if expected_const == declaration_tokens(method(changed), [const_row], const_row):
            raise AssertionError('Accepted ' + label)
        print('Settings self-test ' + label + ': rejected')
    if check_lint_comments('', {'source': 'void action() {}'}) or not check_lint_comments('', {'source': '// ignore_for_file: some_lint\nvoid action() {}'}):
        raise AssertionError('Lint suppression addition check failed')
    print('Settings self-test new lint suppression: rejected')
    key_row = dict(original_name='_Example._Example', new_name='Example',
                   destination_class='Example', allowed_edits='rename,public_widget_key',
                   expected_difference=PUBLIC_WIDGET_KEY_DIFFERENCE)
    def constructor(text, owner):
        return parse({'test': 'class ' + owner + ' { ' + text + ' }'}, package)['test']['declarations'][0]['members'][0]
    key_before = constructor('const _Example({this.title = "default"});', '_Example')
    key_after_text = 'const Example({super.key, this.title = "default"});'
    expected_key = declaration_tokens(key_before, [key_row], key_row, original=True)
    if check_named_exceptions([key_row]) or expected_key != declaration_tokens(constructor(key_after_text, 'Example'), [key_row], key_row):
        raise AssertionError('Authorized optional widget key exception rejected')
    for label, changed in {
        'missing optional widget key': key_after_text.replace('super.key, ', ''),
        'required widget key': key_after_text.replace('super.key', 'required super.key'),
        'changed constructor default': key_after_text.replace('"default"', '"other"'),
        'lost constructor const': key_after_text.replace('const ', ''),
    }.items():
        if expected_key == declaration_tokens(constructor(changed, 'Example'), [key_row], key_row):
            raise AssertionError('Accepted ' + label)
        print('Settings self-test ' + label + ': rejected')
    singleton = method('List<Object> one() { return [(1,)]; }')
    nonrecord = method('List<Object> one() { return [(1)]; }')
    if not compare_elements(singleton, [nonrecord], []):
        raise AssertionError('Record comma was treated as formatting')
    print('Settings self-test changed record comma: rejected')
    original = method('void snack() { if (!mounted) return; ScaffoldMessenger.of(context); }')
    good_context = method('void snack() { if (!_deps.mounted()) return; final context = _deps.context(); ScaffoldMessenger.of(context); }')
    bad_context = method('void snack() { final context = _deps.context(); if (!_deps.mounted()) return; ScaffoldMessenger.of(context); }')
    if check_context(original, good_context) or not check_context(original, bad_context):
        raise AssertionError('Context guard self-test failed')
    print('Settings self-test context fetched before guard: rejected')
    permission = method('void action() async { if (!await allowed()) return; show(context); }')
    permission_hoist = method('void action() async { final context = _deps.context(); if (!await allowed()) return; show(context); }')
    if not check_context(permission, permission_hoist):
        raise AssertionError('Accepted context fetched before awaited permission')
    print('Settings self-test context fetched before awaited permission: rejected')
    awaited_context = method('void action() async { await show(context); if (!mounted) return; }')
    acquired_context = method('void action() async { final context = _deps.context(); await show(context); if (!context.mounted) return; }')
    if check_context(awaited_context, acquired_context):
        raise AssertionError('Context argument before its await suspension was rejected')
    print('Settings self-test context argument evaluated before await: passed')
    for label, prefix in {
        'context fetched before synchronous guard': 'if (busy) return;',
        'context fetched before service call': 'service.prepare();',
    }.items():
        action = method('void action() { ' + prefix + ' show(context); }')
        hoisted = method('void action() { final context = _deps.context(); ' + prefix + ' show(context); }')
        if not check_context(action, hoisted):
            raise AssertionError('Accepted ' + label)
        print('Settings self-test ' + label + ': rejected')
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
    interpolation_row = dict(original_name='Original._caption', new_name='caption')
    interpolation_before = method("String title() => '$_caption';")
    interpolation_after = method("String title() => '${_summaries.caption}';")
    if normalize(tokens(interpolation_before), [interpolation_row]) != normalize(tokens(interpolation_after), [interpolation_row]):
        raise AssertionError('Qualified single-value interpolation rejected')
    for text in ("String title() => '${_summaries.other}';",
                 "String title() => '${_summaries.caption.length}';"):
        if normalize(tokens(interpolation_before), [interpolation_row]) == normalize(tokens(method(text)), [interpolation_row]):
            raise AssertionError('Accepted changed interpolation value/expression')
    print('Settings self-test changed interpolation expression: rejected')
    scaffold_source = {'owner': 'class NewOwner { final int dependency = 1; }'}
    scaffold_lookup = all_nodes(parse(scaffold_source, package))
    scaffold_key = ('owner', 'NewOwner', 'dependency')
    scaffold = dict(file='owner', owner='NewOwner', name='dependency',
                    tokens=tokens(scaffold_lookup[scaffold_key]))
    if check_scaffolds(scaffold_lookup, [scaffold]):
        raise AssertionError('Registered exact scaffold rejected')
    for changed in ('class NewOwner { final int dependency = 2; }',
                    'class NewOwner { int dependency = 1; }',
                    'class NewOwner {}'):
        if not check_scaffolds(all_nodes(parse({'owner': changed}, package)), [scaffold]):
            raise AssertionError('Accepted changed/missing registered scaffold')
    print('Settings self-test changed registered scaffold: rejected')
    before_owner = 'class Original { int value = 1; }'
    owner_row = {'original_name': 'Original.value', 'destination_file': 'owner',
                 'destination_class': 'NewOwner', 'new_name': 'value',
                 'allowed_edits': 'unchanged', 'expected_difference': ''}
    valid_owner = {'source': 'class Original {}',
                   'owner': 'class NewOwner { int value = 1; }'}
    errors = check(before_owner, valid_owner, [owner_row], 'source', package)
    if errors:
        raise AssertionError('Valid single destination owner rejected: ' + str(errors))
    for label, extra in {
        'unregistered destination helper': 'class NewOwner { int value = 1; void extra() {} }',
        'unregistered destination class': 'class NewOwner { int value = 1; } class Extra {}',
        'unregistered destination function': 'class NewOwner { int value = 1; } void extra() {}',
    }.items():
        if not check(before_owner, dict(valid_owner, owner=extra), [owner_row], 'source', package):
            raise AssertionError('Accepted ' + label)
        print('Settings self-test ' + label + ': rejected')
    duplicate = parse({'owner': 'class NewOwner { int value = 1; int value = 1; }'}, package)
    try:
        all_nodes(duplicate)
    except ValueError:
        print('Settings self-test duplicate destination field: rejected')
    else:
        raise AssertionError('Accepted duplicate destination field')
