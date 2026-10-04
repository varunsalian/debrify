#!/usr/bin/env python3
"""Manifest-configured section moves, partitions and context-guard evidence.

Called by check_verbatim_moves.py for configured manifests. Uses the same
analyzer token adapter; the launcher verifier and its fixtures remain intact.
"""
from collections import Counter
from contextlib import contextmanager
import difflib
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONFIG = json.loads((ROOT / 'dev/tool/settings_checker_config.json').read_text())


def sidecar(name, key, default, *, config=None):
    path = (config or CONFIG).get('sidecars', {}).get(name)
    return json.loads((ROOT / path).read_text())[key] if path else default


def configure(config):
    global CONFIG, ALLOWED, RECEIVERS, LIVE_GETTER_CALLBACKS
    global INDEX_GETTER_CALLBACKS, NAMED_EXCEPTIONS, CONTEXT_EXCEPTION_DIFFERENCE
    CONFIG = config
    ALLOWED = set(config['allowed_edits'])
    RECEIVERS = set(config['receivers'])
    LIVE_GETTER_CALLBACKS = set(config.get('live_getter_callbacks', []))
    INDEX_GETTER_CALLBACKS = sidecar('index_getters', 'methods', {})
    NAMED_EXCEPTIONS = config.get('named_exceptions', {})
    CONTEXT_EXCEPTION_DIFFERENCE = config.get('context_exception_difference', '')


@contextmanager
def configured(config):
    previous = CONFIG
    configure(config)
    try:
        yield
    finally:
        configure(previous)


configure(CONFIG)

CONTEXT_ACQUISITION = ['final', 'context', '=', '_deps', '.', 'context', '(', ')', ';']


def is_context_acquisition(values, index):
    return (values[index:index + 3] == ['final', 'context', '=']
            and values[index + 3:index + 4] in (['_deps'], ['deps'])
            and values[index + 4:index + 9] == ['.', 'context', '(', ')', ';'])


def without_offsets(node, offsets):
    """Remove only validated exception tokens, retaining original AST offsets."""
    return dict(node, tokens=[t for t in node['tokens'] if t['offset'] not in offsets],
                references=[r for r in node['references'] if r['offset'] not in offsets])


def remove_context_exceptions(node, sites, rows, row):
    """Validate each recorded addition before the ordinary verbatim/context checks.

    Ordinal acquisitions and complete canonical prefixes pin the additions to
    their approved sites. All original statements still compare to the baseline.
    This never canonicalizes an unregistered guard or a general pair of braces.
    """
    formatting_commas = set(node.get('formatCommas', []))
    code = [t for t in node['tokens']
            if not t['comment'] and t['offset'] not in formatting_commas]
    values = [t['text'] for t in code]
    acquisitions = [i for i in range(len(code)) if is_context_acquisition(values, i)]
    removed, anchors = set(), []
    for site in sites:
        if site['kind'] == 'context_confirmation':
            ordinal = site['acquisition']
            if ordinal >= len(acquisitions):
                raise ValueError('Missing recorded context acquisition')
            i = acquisitions[ordinal]
            start = i + len(CONTEXT_ACQUISITION)
            check = ['if', '(', '!', 'context', '.', 'mounted', ')', 'return']
            check += [site['return_value']] if site['return_value'] is not None else []
            check += [';']
            if values[start:start + len(check)] != check:
                raise ValueError('Recorded context confirmation changed or is not immediately after acquisition')
            removed.update(t['offset'] for t in code[start:start + len(check)])
            anchors.append((site, code[i]['offset']))
        elif site['kind'] == 'formatter_if_braces':
            pattern = ['{', *site['body_tokens'], '}']
            matches = [i for i in range(len(code)) if values[i:i + len(pattern)] == pattern]
            # Identical original bodies can occur elsewhere. Only the complete
            # recorded prefix selects this site; other bodies remain verbatim.
            if len(matches) > 1:
                if site.get('prefix_tokens') is None:
                    raise ValueError('Repeated formatter if body needs a recorded prefix')
                matches = [i for i in matches if (
                    tokens(without_offsets(node, removed), end=code[i]['offset']) if site.get('prefix_mode') == 'raw'
                    else normalize(tokens(without_offsets(node, removed), end=code[i]['offset']), rows, row)
                ) == site['prefix_tokens']]
            if len(matches) != 1:
                raise ValueError('Recorded formatter if body changed or is not wrapped exactly once')
            i = matches[0]
            removed.update((code[i]['offset'], code[i + len(pattern) - 1]['offset']))
            anchors.append((site, code[i]['offset']))
        else:
            raise ValueError('Unknown context exception kind')
    result = without_offsets(node, removed)
    for site, offset in anchors:
        prefix = (tokens(result, end=offset) if site.get('prefix_mode') == 'raw'
                  else normalize(tokens(result, end=offset), rows, row))
        if prefix != site['prefix_tokens']:
            raise ValueError('Recorded context/formatter exception moved across an original statement')
        if site['kind'] == 'context_confirmation':
            # The pinned approved prefix includes the passing State guard.
            # Also prove that no suspension has appeared after that guard.
            guards = [i for i, value in enumerate(prefix) if value == 'mounted']
            if not guards or 'await' in prefix[guards[-1] + 1:]:
                raise ValueError('Context confirmation requires an existing mounted guard with no intervening await')
    return result

PUBLIC_WIDGET_KEY_DIFFERENCE = 'public_widget_key: add optional super.key only; no caller passes a key'


def named_exception_tokens(values, row):
    """User-authorized edits, at exact baseline token sequences only."""
    values = list(values)
    if 'production_api_annotation' in row['allowed_edits'].split(','):
        start = next((i for i, value in enumerate(values)
                      if not value.startswith(('//', '/*'))), len(values))
        if values[start:start + 2] != ['@', 'visibleForTesting']:
            raise ValueError('Production API exception requires the original annotation')
        del values[start:start + 2]
    for rule in CONFIG.get('token_rules', []):
        if rule.get('original_name', row['original_name']) != row['original_name']:
            continue
        if rule.get('allowed_edit') and rule['allowed_edit'] not in row['allowed_edits'].split(','):
            continue
        if rule.get('difference_prefix') and not row.get('expected_difference', '').startswith(rule['difference_prefix']):
            continue
        sequence = rule['before']
        matches = [i for i in range(len(values)) if values[i:i + len(sequence)] == sequence]
        if len(matches) != 1:
            raise ValueError('Exact token rule must match once: ' + row['original_name'])
        i = matches[0]
        values[i:i + len(sequence)] = rule['after']
    if 'public_widget_key' in row['allowed_edits'].split(','):
        opening = values.index('(')
        if '{' in values[opening:]:
            named = values.index('{', opening)
            values[named + 1:named + 1] = ['super', '.', 'key', ',']
        else:
            closing = values.index(')', opening)
            values[closing:closing] = [',', '{', 'super', '.', 'key', '}', ]
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
        if ('production_api_annotation' in row['allowed_edits'].split(',')
                and 'production_api_annotation' not in NAMED_EXCEPTIONS):
            spec = CONFIG.get('annotation_exceptions', {}).get(row['original_name'])
            if (not spec or spec['file'] != row['destination_file']
                    or spec['difference'] != row['expected_difference']):
                errors.append('Annotation exception must name its exact declaration and destination')
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


def names(rows, owner=None):
    # Ambiguous method names (e.g. build) are declaration-local below.
    candidates = {}
    for r in rows:
        old = r['original_name'].split('.')[-1]
        candidates.setdefault(old, set()).add(r['new_name'])
    if owner:
        for old, news in list(candidates.items()):
            if len(news) > 1:
                local = {r['new_name'] for r in rows
                         if r['original_name'] == owner + '.' + old}
                if len(local) == 1:
                    candidates[old] = local
    return {old: next(iter(news)) for old, news in candidates.items()
            if len(news) == 1 and old != next(iter(news))}


def receiver_path_match(values, index):
    """Match only a configured composition path and retain its exact owner."""
    for path, owner in CONFIG.get('receiver_paths', {}).items():
        pattern = []
        for part in path.split('.'):
            if pattern:
                pattern.append('.')
            pattern.append(part)
        end = index + len(pattern)
        if values[index:end] == pattern and values[end:end + 1] == ['.']:
            return len(pattern), owner
    return None


def normalize(values, rows, row=None):
    mapping = names(rows, row['original_name'].rsplit('.', 1)[0] if row else None)
    mapped = set(mapping.values()) | {r['new_name'] for r in rows}
    if row:
        mapped.update(row.get('_partition_preamble_names', []))
    live_getters = set()
    if row and 'live_getter_callback' in row['allowed_edits'].split(','):
        live_getters = LIVE_GETTER_CALLBACKS
    if row and 'index_live_getter_callbacks' in row['allowed_edits'].split(','):
        live_getters = set(INDEX_GETTER_CALLBACKS.get(row['original_name'], []))
    if row and 'live_service_getter' in row['allowed_edits']:
        mapped.add(CONFIG['live_service_getter'])
    out = []
    i = 0
    while i < len(values):
        value = values[i]
        # A named record cannot have a private field name. This exact borrowed
        # callback alias preserves the retained State member's identity; it is
        # opt-in and never erases a closure or an arbitrary receiver path.
        borrowed = CONFIG.get('borrowed_member_aliases', {})
        matched_alias = False
        for path, original_name in borrowed.items():
            expression = re.split(r'(\.)', path)
            if values[i:i + len(expression)] == expression:
                original_row = next(r for r in rows if r['original_name'] == original_name)
                out.append(original_row['new_name'])
                i += len(expression)
                matched_alias = True
                break
        if matched_alias:
            continue
        # A member qualification needs braces in a formerly simple string
        # interpolation. Canonicalize only an otherwise identical single read.
        if value == '${':
            if (values[i + 1:i + 2] and values[i + 1] in RECEIVERS
                    and values[i + 2:i + 3] == ['.']
                    and values[i + 3:i + 4] and values[i + 3] in live_getters
                    and values[i + 4:i + 7] == ['(', ')', '}']):
                target = values[i + 3]
                alias = CONFIG.get('live_getter_aliases', {}).get(target)
                out.extend(['$', alias.split('.')[-1] if alias else mapping.get(target, target)])
                i += 7
                continue
            path = receiver_path_match(values, i + 1)
            if path:
                member = i + 1 + path[0] + 1
                if (values[member:member + 1] and values[member] in mapped
                        and values[member + 1:member + 2] == ['}']):
                    out.extend(['$', mapping.get(values[member], values[member])])
                    i = member + 2
                    continue
            if values[i + 1:i + 2] and values[i + 1] in RECEIVERS and values[i + 2:i + 3] == ['.'] and values[i + 4:i + 5] == ['}'] and values[i + 3] in mapped:
                out.extend(['$', mapping.get(values[i + 3], values[i + 3])])
                i += 5; continue
            if values[i + 2:i + 3] == ['}'] and values[i + 1] in mapping:
                out.extend(['$', mapping[values[i + 1]]])
                i += 3; continue
        # Injected context acquisition is checked separately BEFORE removing it.
        if is_context_acquisition(values, i):
            i += 9
            continue
        if values[i:i + 4] == ['context', '.', 'mounted', '(']:
            raise ValueError('context.mounted is a property, not a callback')
        if values[i:i + 3] == ['context', '.', 'mounted']:
            out.append('mounted'); i += 3; continue
        path = receiver_path_match(values, i)
        if path and i + path[0] + 1 < len(values):
            target = values[i + path[0] + 1]
            if target in mapped:
                i += path[0] + 1
                continue
        if value in RECEIVERS and i + 2 < len(values) and values[i + 1] == '.':
            target = values[i + 2]
            getter_alias = CONFIG.get('live_getter_aliases', {}).get(target)
            if (getter_alias and target in live_getters
                    and values[i + 3:i + 5] == ['(', ')']):
                out.append(getter_alias.split('.')[-1]); i += 5; continue
            borrowed = CONFIG.get('borrowed_resource_aliases', {}).get(target)
            if borrowed:
                out.append(borrowed.split('.')[-1]); i += 3; continue
            if target in mapped or target in {'mounted', 'setState', 'context'} | set(CONFIG.get('live_widget_getters', [])):
                if value in {'_deps', 'deps'} and target in live_getters and values[i + 3:i + 5] == ['(', ')']:
                    out.append(target); i += 5; continue
                if target in {'mounted', 'context'} | set(CONFIG.get('live_widget_getters', [])) and values[i + 3:i + 5] == ['(', ')']:
                    out.extend(['widget', '.', target] if target in CONFIG.get('live_widget_getters', []) else [target])
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
    completely. Only optional trailing commas in arguments, parameters, named
    record types and list/set/map literals are formatting punctuation. A
    positional record comma (which changes its type/value) is never removed.
    """
    values = normalize(tokens(node), rows, row)
    if not original:
        return values
    key = row['original_name']
    old = key.split('.')[-1]
    mapped = names(rows, key.rsplit('.', 1)[0]).get(old, old)
    # A common name such as build is renamed only on this declaration.
    if old != row['new_name'] and mapped != row['new_name']:
        index = values.index(mapped)
        values[index] = row['new_name']
    if 'layout_first_param' in row['allowed_edits']:
        opening = values.index('(')
        values[opening + 1:opening + 1] = [CONFIG['layout_first_parameter_type'], 'layout', ',']
        # Calls get the layout argument; method tear-offs remain class methods.
        i = opening + 4
        while i < len(values) - 1:
            if values[i] in set(CONFIG.get('layout_first_parameter_calls', [])) and values[i + 1] == '(':
                values[i + 2:i + 2] = ['layout', ',']
                i += 2
            i += 1
    if 'layout_body' in row['allowed_edits'] and values[:2] == ['@', 'override']:
        del values[:2]
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


def builder_context_signature(node):
    """Screen context/guards used inside closures that take their own context.

    The owned-context checks skip these closures (their `context` is a
    builder/dialog parameter), and `normalize` maps `_deps.context()` and
    `context.mounted` onto plain `context`/`mounted`, so a swap there would be
    invisible. This returns what must not change: how many times the State's
    context is fetched inside such closures (`_deps.context()`, never present
    in the original), and how many guards there are of each kind: the
    closure's own `context.mounted`, or the State's `mounted`. Plain uses of a
    parameter named `context` are not compared: a method's parameter and the
    same parameter on its top-level function form are equivalent.
    """
    code = [t for t in node['tokens'] if not t['comment']]
    indexes = {t['offset']: i for i, t in enumerate(code)}
    counts = Counter()
    # A declaration with its own `context` parameter (a builder method, or a
    # top-level builder function) shadows the State's context, so the original
    # can't have used the State's there. Any `_deps.context()` in its body is a
    # substitution for that parameter, wherever it appears.
    own_parameter = re.search(r'\bcontext\b', node.get('parameters') or '') is not None
    if own_parameter:
        for i, token in enumerate(code):
            if (token['text'] == 'context' and i >= 2 and code[i - 1]['text'] == '.'
                    and code[i - 2]['text'] in ('_deps', 'deps')):
                counts['state-context-over-parameter'] += 1
    for ref in node.get('references', []):
        if not ref['contextParameter'] or ref['name'] not in {'context', 'mounted'}:
            continue
        i = indexes.get(ref['offset'])
        if i is None:
            continue
        before = [t['text'] for t in code[max(0, i - 2):i]]
        owned = before[-1:] == ['.'] and before[:1] in (['_deps'], ['deps'])
        if ref['name'] == 'context':
            if owned:
                counts['state-context'] += 1
            elif [t['text'] for t in code[i:i + 3]] == ['context', '.', 'mounted']:
                counts['builder-mounted'] += 1
        elif owned or before[-1:] != ['.']:
            counts['state-mounted'] += 1
    return dict(sorted(counts.items()))


def check_context(before, after, rows=None, row=None):
    expected, actual = context_events(before), context_events(after)
    errors = [] if expected == actual else [f'Context/guard scope or first-use position changed: {expected} -> {actual}']
    if context_prefixes(before, rows or [], row) != context_prefixes(after, rows or [], row):
        errors.append('First owned context acquisition moved across an original statement/guard')
    # A later lexical branch can acquire a new local context after another
    # branch already used context. It still must follow that branch's original
    # guards; checking only the callback's first context would miss a hoist.
    expected_prefixes = [normalize(tokens(before, end=r['statementOffset']), rows or [], row)
                         for r in before['references'] if r['name'] == 'context'
                         and not r['contextParameter']]
    code = [t for t in after['tokens'] if not t['comment']]
    values = [t['text'] for t in code]
    for i, token in enumerate(code):
        if not is_context_acquisition(values, i):
            continue
        prefix = normalize(tokens(after, end=token['offset']), rows or [], row)
        if prefix not in expected_prefixes:
            errors.append('Owned context acquisition moved across its original lexical-branch statement/guard')
    return errors


def partition_elements(node):
    result = node.get('returnedList')
    if result is None:
        raise ValueError('Partition method must return one top-level list literal: ' + node['name'])
    return result['elements']


def compare_elements(before, after, rows, row=None):
    # Compare the AST partition units individually, not just flattened text.
    # Splitting if/for into spread/condition fragments cannot preserve this list.
    a = [(e['kind'], normalize(tokens(before, e['offset'], e['end']), rows, row))
         for e in partition_elements(before)]
    b = [(e['kind'], normalize(tokens(node, e['offset'], e['end']), rows, row))
         for node in after for e in partition_elements(node)]
    return [] if a == b else ['Partition elements changed, reordered, dropped, duplicated or split']


def check_preamble(before, spec, lookup, rows, package=None, row=None):
    """Local functions/consts stay exact; final initializers run in the ctor.

    Field type annotations are structural. The initializer expression, local
    function signature/body and declaration order are compared in full.
    """
    from check_verbatim_moves import parse
    errors = []
    owner, path = spec['builder_class'], spec['builder_file']
    original_names = [declaration['names'][0] for declaration in before['returnedList']['preamble']]
    if spec['preamble_names'] != original_names:
        errors.append('Manifest must name every original preamble declaration in order')
    constructor = lookup.get((path, owner, owner))
    finals = []
    for declaration in before['returnedList']['preamble']:
        name = declaration['names'][0]
        member = lookup.get((path, owner, name))
        if member is None:
            errors.append('Missing builder preamble member: ' + name); continue
        text = declaration['text']
        parsed = parse({'local': 'class Local { ' + text + ' }'}, package)['local']['declarations'][0]['members'][0]
        expected = normalize(tokens(parsed), rows, row)
        actual = normalize(tokens(member), rows, row)
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
            if normalize(tokens(parsed, old['initializerOffset'], old['initializerEnd']), rows, row) != normalize(tokens(constructor, initializer['expressionOffset'], initializer['expressionEnd']), rows, row):
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


def partition_virtual(current, spec, lookup, sources, package=None):
    """Reconstruct the executed list/preamble solely for full-scope comparison.

    This is parser input, never production code. The physical dispatcher and
    initializer order are independently checked. Re-parsing restores original
    callback scope numbering across slice files and local-to-member functions.
    """
    if spec.get('retained_preamble_join'):
        from playback_settings_partition import virtual
        return virtual(current, spec, lookup, sources, package)
    from check_verbatim_moves import parse
    path, owner = spec['builder_file'], spec['builder_class']
    constructor = lookup[(path, owner, owner)]
    dependency = lookup[(path, owner, 'deps')]
    members = [lookup[(path, owner, name)] for name in spec['preamble_names']]
    unit_source = sources[path]
    # The frozen constructor/borrowed fields precede every moved local. Taking
    # the physical tail retains intervening section comments as well as bodies.
    opening = dependency['end']
    closing = unit_source.rfind('}')
    preamble = unit_source[opening:closing]
    edits = []
    for member in members:
        code = [t for t in member['tokens'] if not t['comment']]
        if code[0]['text'] == 'static':
            token = code[0]
            edits.append((token['offset'] - opening,
                          token['offset'] + len(token['text']) - opening, ''))
        elif code[0]['text'] == 'final':
            initializer = next(i for i in constructor['initializers'] if i['name'] == member['name'])
            expression = unit_source[initializer['expressionOffset']:initializer['expressionEnd']]
            edits.append((member['start'] - opening, member['end'] - opening,
                          'final ' + member['name'] + ' = ' + expression + ';'))
    for start, end, value in sorted(edits, reverse=True):
        preamble = preamble[:start] + value + preamble[end:]
    interiors = []
    for item in spec['slices']:
        node = lookup[(item['file'], item.get('owner', ''), item['name'])]
        raw = sources[item['file']]
        result = node['returnedList']
        start, end = result['offset'] + 1, result['end'] - 1
        interior = raw[start:end]
        # Only offsets removed by the exact physical-site exception validator
        # can disappear here; all original tokens/comments remain in place.
        for token in sorted(node.get('_validated_removed_tokens', []),
                            key=lambda token: token['offset'], reverse=True):
            if start <= token['offset'] < end:
                offset = token['offset'] - start
                interior = interior[:offset] + interior[offset + len(token['text']):]
        interiors.append(interior)
    header = current['text'][:current['bodyOffset'] - current['start']]
    text = header + '{' + preamble + '\nreturn [' + '\n'.join(interiors) + '];\n}'
    return parse({'virtual': 'class Virtual { ' + text + ' }'}, package)['virtual']['declarations'][0]['members'][0]


def check_partition(before, current, spec, lookup, rows, package=None, row=None):
    if spec.get('retained_preamble_join'):
        from playback_settings_partition import check_partition as retained_check
        return retained_check(before, current, spec, lookup, rows, package, row)
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
        errors.extend(compare_elements(before, [current], rows, row))
        a = before['returnedList']['preamble']
        b = current['returnedList']['preamble']
        def preamble_units(declarations):
            from check_verbatim_moves import parse
            return [(d['kind'], d['names'], normalize(tokens(parse(
                {'local': 'class Local { ' + d['text'] + ' }'}, package)['local']['declarations'][0]['members'][0]), rows, row))
                    for d in declarations]
        if preamble_units(a) != preamble_units(b):
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
        errors.extend(compare_elements(before, actual_slices, rows, row))
    # The dispatcher MUST construct a new builder every call and join each
    # slice exactly once in the manifest order; it cannot cache a result.
    code = normalize(tokens(current, current['bodyOffset']), rows, row)
    expected = ['{', 'final', 'b', '=', spec['builder_class'], '(']
    arguments = spec.get('constructor_arguments', ['_deps'])
    dependency = lookup.get((spec['builder_file'], spec['builder_class'], 'deps'))
    if dependency is not None:
        fields = dependency.get('recordTypeFields')
        if not fields or len(fields) != len(set(fields)):
            errors.append('Fresh builder must declare its exact typed callback fields')
        else:
            # An argument fingerprint alone could bless an incorrectly rewired
            # callback. Derive the subset record from its declared field names;
            # values are matching borrowed functions, never invoked snapshots.
            wired = [CONFIG.get('partition_summary_receiver', '_summaries'), ',', '(']
            for field in fields:
                wired += [field, ':']
                wired += ([field] if field in CONFIG.get('partition_direct_callbacks', [])
                          else [CONFIG.get('partition_dependency_receiver', '_deps'), '.', field])
                wired += [',']
            wired += [')']
            if arguments != wired:
                errors.append('Fresh builder callbacks must preserve their matching function bindings')
    expected += normalize(arguments, rows, row)
    expected += [')', ';', 'return', '[']
    for item in slices:
        expected += ['...', 'b', '.', item['name'], '(', ')', ',']
    expected += [']', ';', '}']
    # Formatting may add the last comma, but every spread and receiver is exact.
    if code[-4:] == [')', ']', ';', '}']:
        code.insert(len(code) - 3, ',')
    if code != expected:
        errors.append('Partition dispatcher must construct a fresh builder and join exactly in manifest order')
    errors.extend(check_preamble(before, spec, lookup, rows, package, row))
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


def destination_ownership(parsed, rows, source_path, scaffolds=(), partition_specs=()):
    """No unregistered original copy or extra feature helper can hide in a move.

    The three extra layout leaves are exactly the structural additions named
    in the plan and checked separately below. Later section/deps scaffolding
    must be registered explicitly when that step is implemented.
    """
    known = {(r['destination_file'], r['destination_class'], r['new_name'])
             for r in rows}
    known.update((s['file'], s['owner'], s['name']) for s in scaffolds)
    for spec in partition_specs:
        known.update((spec['builder_file'], spec['builder_class'], name)
                     for name in spec['preamble_names'])
        known.update((item['file'], item.get('owner', ''), item['name'])
                     for item in spec['slices'])
    for extra in CONFIG.get('additional_owners', []):
        known.update((extra['file'], extra['owner'], name) for name in extra['names'])
    for accessor in CONFIG.get('test_accessors', []):
        relocation = accessor.get('composition')
        if relocation:
            known.add((relocation['file'], '', relocation['name']))
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


def accessor_receiver_tokens(values, spec, rows):
    """Drop only frozen accessor receivers on named methods moved to functions."""
    rule = spec.get('unbound_tearoffs')
    if not rule:
        return values
    allowed = set()
    for name in rule['members']:
        row = next((row for row in rows if row['original_name'] == name), None)
        if row is None or row['destination_class']:
            raise ValueError('Unbound accessor tear-off must name a top-level destination: ' + name)
        allowed.add(name.split('.')[-1])
    result = []
    i = 0
    while i < len(values):
        if (values[i:i + 2] == [rule['receiver'], '.']
                and i + 2 < len(values) and values[i + 2] in allowed):
            i += 2
        result.append(values[i])
        i += 1
    return result


def normalized_accessor_tokens(values, spec, rows):
    values = normalize(accessor_receiver_tokens(values, spec, rows), rows)
    receiver = spec.get('borrowed_receiver')
    if not receiver:
        return values
    # Only this frozen accessor's local borrowed State/composition receiver.
    # Qualified paths were already validated against exact configured owners.
    members = {r['new_name'] for r in rows}
    result = []
    i = 0
    while i < len(values):
        if (values[i:i + 2] == [receiver, '.']
                and i + 2 < len(values) and values[i + 2] in members):
            i += 2
        result.append(values[i])
        i += 1
    return result


def check_scaffolds(lookup, scaffolds):
    errors = []
    for scaffold in scaffolds:
        key = (scaffold['file'], scaffold['owner'], scaffold['name'])
        node = lookup.get(key)
        if node is None or tokens(node) != scaffold['tokens']:
            errors.append('Registered settings scaffold changed: ' + str(key))
    return errors


def check_plain_sections(lookup):
    """Pin named sections to plain classes, with no widget inheritance/mixins."""
    errors = []
    for spec in CONFIG.get('plain_sections', []):
        key = (spec['file'], '', spec['owner'])
        node = lookup.get(key)
        values = [value for value in tokens(node)
                  if not value.startswith(('//', '/*'))] if node else []
        header = values[:values.index('{') + 1] if '{' in values else values
        if header != ['class', spec['owner'], '{']:
            errors.append('Registered plain section class changed: ' + str(key))
    return errors


def check_seams(original_source, sources, config, baseline, package=None):
    """Apply registered additions to the baseline; sidecar files stay exact.

    The main declaration comparison then checks every patched leaf, so a
    registered seam never excuses a second edit to a method. Auxiliary files
    are checked in full against their patched baseline, including directives.
    """
    from check_verbatim_moves import parse
    errors = []
    for spec in config.get('seams', []):
        path = spec['file']
        expected = original_source if path == config['source'] else subprocess.run(
            ['git', 'show', f'{baseline}:{path}'], cwd=ROOT, text=True,
            capture_output=True, check=True).stdout
        for patch in spec['patches']:
            if expected.count(patch['before']) != 1:
                raise ValueError('Seam baseline must match exactly once: ' + path)
            expected = expected.replace(patch['before'], patch['after'], 1)
        if path == config['source']:
            original_source = expected
            continue
        actual = (ROOT / path).read_text()
        units = parse({'expected': expected, 'actual': actual}, package)
        def fingerprint(unit):
            return (unit['directives'], [(d['name'], tokens(d)) for d in unit['declarations']])
        if fingerprint(units['expected']) != fingerprint(units['actual']):
            errors.append('Auxiliary clock seam changed outside its exact edits: ' + path)
    return original_source, errors


def check_forwarder(before, actual, row, spec, package=None):
    """Retain the exact facade signature and dispatch each argument in order."""
    from check_verbatim_moves import parse
    if before['bodyOffset'] is not None:
        prefix = before['text'][:before['bodyOffset'] - before['start']]
        getter = before['parameters'] is None
        arguments = [f'{name}: {name}' if named else name for name, named in
                     zip(before['parameterNames'], before['namedParameters'])]
        target = spec.get('receiver', row['destination_class']) + '.' + row['new_name']
        text = prefix + '=> ' + target + ('' if getter else '(' + ', '.join(arguments) + ')') + ';'
    elif before['variables'] and len(before['variables']) == 1:
        # A retained const/static field keeps its modifiers and type. Only its
        # initializer becomes a reference to the registered implementation.
        variable = before['variables'][0]
        start, end = variable['initializerOffset'], variable['initializerEnd']
        if start is None:
            return ['Forwarded constant must have an original initializer']
        text = (before['text'][:start - before['start']]
                + spec.get('receiver', row['destination_class']) + '.' + row['new_name']
                + before['text'][end - before['start']:])
    else:
        return ['Forwarder must be a method, getter or initialized constant']
    node = parse({'forwarder': 'class Facade { ' + text + ' }'}, package)['forwarder']['declarations'][0]['members'][0]
    return [] if tokens(node) == tokens(actual) else ['Forwarder signature/default/dispatch/argument order changed']


def lifecycle_tokens(node, rows):
    """Only registered owner receivers and their leaf renames may change."""
    mapping = names(rows, node['owner'])
    owner_for = {r['new_name']: r['destination_class'] for r in rows}
    receivers = CONFIG.get('receiver_owners', {})
    result = []
    values = tokens(node)
    i = 0
    while i < len(values):
        value = values[i]
        path = receiver_path_match(values, i)
        if (path and i + path[0] + 1 < len(values)
                and owner_for.get(values[i + path[0] + 1]) == path[1]):
            i += path[0] + 1
            continue
        if (value in receivers and values[i + 1:i + 2] == ['.']
                and owner_for.get(values[i + 2]) == receivers[value]):
            i += 2
            continue
        if value.startswith(('//', '/*')):
            for old, new in mapping.items():
                value = re.sub(r'\b' + re.escape(old) + r'\b', new, value)
            result.append(re.sub(r'\s+', '', value))
        else:
            result.append(mapping.get(value, value))
        i += 1
    return result


def _check(original_source, sources, rows, source_path, package=None,
           partition=False, context_guard=False):
    from check_verbatim_moves import parse, original_leaves, split_names, missing_line_comments, ROOT
    parsed = parse({'<original>': original_source, **sources}, package)
    original = original_leaves(parsed['<original>']['declarations'], split_names(rows))
    errors = missing_line_comments(original_source, sources, rows)
    errors.extend(check_named_exceptions(rows))
    errors.extend(check_lint_comments(original_source, sources))
    known = {r['original_name'] for r in rows}
    for alias, member in CONFIG.get('live_getter_aliases', {}).items():
        declared = original.get(member)
        retained = next((r for r in rows if r['original_name'] == member), None)
        if (not declared or declared['parameters'] is not None
                or declared['bodyOffset'] is None or not retained
                or retained['destination_file'] != source_path
                or alias not in CONFIG.get('live_getter_callbacks', [])):
            errors.append('Live getter alias must name one retained facade getter: ' + alias)
    for alias, member in CONFIG.get('borrowed_resource_aliases', {}).items():
        declaration = original.get(member)
        retained = next((r for r in rows if r['original_name'] == member), None)
        if (not declaration or not declaration['variables'] or len(declaration['variables']) != 1
                or not retained or retained['destination_file'] != source_path
                or retained['new_name'] != member.split('.')[-1]):
            errors.append('Borrowed resource alias must name one unchanged facade field: ' + alias)
    if set(original) != known:
        return ['Settings manifest coverage differs: ' + str(sorted(set(original) ^ known))]
    lookup = all_nodes(parsed)
    for pair in CONFIG.get('co_located_declarations', []):
        locations = []
        for name in pair:
            row = next(r for r in rows if r['original_name'] == name)
            destination = (row['destination_file'], row['destination_class'], row['new_name'])
            old_owner, _, old_name = name.rpartition('.')
            locations.append(destination[0] if destination in lookup
                             else source_path if (source_path, old_owner, old_name or name) in lookup
                             else None)
        if len(set(locations)) != 1 or locations[0] is None:
            errors.append('Co-located declarations split: ' + str(pair))
    errors.extend(check_plain_sections(lookup))
    from torbox_callback_identity import check_callback_identities
    errors.extend(check_callback_identities(lookup, rows, source_path, CONFIG))
    partitions = sidecar('partitions', 'partitions', {})
    scaffolds = sidecar('scaffolding', 'scaffolds', []) if source_path == CONFIG['source'] else []
    errors.extend(check_scaffolds(lookup, scaffolds))
    active_partitions = [partitions[r['original_name']] for r in rows
                         if r['original_name'] in partitions
                         and (r['destination_file'], r['destination_class'], r['new_name']) in lookup]
    errors.extend(destination_ownership(parsed, rows, source_path, scaffolds, active_partitions))
    exception_sites = sidecar('context_exceptions', 'sites', []) if source_path == CONFIG['source'] else []
    partition_sites = sidecar('partition_context_exceptions', 'sites', []) if source_path == CONFIG['source'] else []
    partition_sites_by_original = {}
    physical_lookup = dict(lookup)
    physical_identities = set()
    for site in partition_sites:
        original_name = site['original_name']
        spec = partitions.get(original_name)
        key = (site['file'], site['owner'], site['method'])
        identity = (*key, site['kind'], site.get('acquisition'))
        if identity in physical_identities:
            errors.append('Duplicate physical partition exception: ' + str(key))
        physical_identities.add(identity)
        if site.get('prefix_mode') != 'raw' or site.get('return_value') is not None:
            errors.append('Partition confirmation must preserve its exact void-return physical site: ' + str(key))
        if spec is None or key not in {(item['file'], item.get('owner', ''), item['name']) for item in spec['slices']}:
            errors.append('Partition context exception registered outside its exact slice: ' + str(key))
            continue
        partition_sites_by_original.setdefault(original_name, []).append(site)
    for original_name, sites in partition_sites_by_original.items():
        row = next((r for r in rows if r['original_name'] == original_name), None)
        if row is None:
            errors.append('Partition context exception has no manifest row: ' + original_name)
            continue
        by_physical = {}
        for site in sites:
            key = (site['file'], site['owner'], site['method'])
            by_physical.setdefault(key, []).append(site)
        for key, registered in by_physical.items():
            node = lookup.get(key)
            if node is None:
                errors.append('Missing registered partition context site: ' + str(key)); continue
            try:
                filtered = remove_context_exceptions(node, registered, rows, row)
            except ValueError as error:
                errors.append(str(key) + ': ' + str(error)); continue
            retained = {token['offset'] for token in filtered['tokens']}
            filtered['_validated_removed_tokens'] = [token for token in node['tokens'] if token['offset'] not in retained]
            physical_lookup[key] = filtered
    registered_sites = {}
    site_identities = set()
    for site in exception_sites:
        key = (site['file'], site['owner'], site['method'])
        identity = (*key, site['kind'], site.get('acquisition'),
                    tuple(site.get('prefix_tokens', [])))
        if identity in site_identities:
            errors.append('Duplicate registered context exception: ' + str(key))
        site_identities.add(identity)
        registered_sites.setdefault(key, []).append(site)
    row_keys = {(r['destination_file'], r['destination_class'], r['new_name']) for r in rows}
    if set(registered_sites) - row_keys:
        errors.append('Context exception registered outside the manifest')
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
    for row in rows:
        key = row['original_name']
        if key in partitions:
            row = dict(row, _partition_preamble_names=partitions[key]['preamble_names'])
        if 'index_live_getter_callbacks' in row['allowed_edits'].split(','):
            difference = CONFIG['index_getter_difference']
            if partition_sites_by_original.get(key):
                difference += CONFIG['partition_confirmation_difference']
            if row['expected_difference'] != difference:
                errors.append('Partition named edit description widened: ' + key)
            targets = INDEX_GETTER_CALLBACKS.get(key, [])
            if key not in partitions or not targets or len(targets) != len(set(targets)):
                errors.append('Index getter callbacks must name exact partition getters: ' + key)
            for target in targets:
                candidates = [r for r in rows if r['new_name'] == target and r['original_name'].startswith(key.split('.')[0] + '.')]
                if len(candidates) != 1:
                    errors.append('Ambiguous/missing original partition getter: ' + target); continue
                declaration = original[candidates[0]['original_name']]
                values = tokens(declaration)
                old_name = candidates[0]['original_name'].split('.')[-1]
                if 'get' not in values[:values.index(old_name)] or not any(ref['name'] == old_name for ref in original[key]['references']):
                    errors.append('Partition callback is not a referenced original getter: ' + target)
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
        if ('retained_forwarder' in row['allowed_edits'].split(',')
                and destination is not None and in_place is None):
            errors.append('Retained facade forwarder missing: ' + key)
        if destination is not None and in_place is not None and destination is not in_place:
            forwarder = CONFIG.get('forwarders', {}).get(key)
            if forwarder is None:
                errors.append('Duplicate settings owner: ' + key)
            else:
                errors.extend(key + ': ' + e for e in check_forwarder(before, in_place, row, forwarder, package))
        if key in CONFIG.get('lifecycle', []):
            if (in_place is None or actual is not in_place
                    or row['destination_file'] != source_path):
                errors.append('Lifecycle must remain in the facade State: ' + key)
            if lifecycle_tokens(before, rows) != lifecycle_tokens(actual, rows):
                errors.append('Lifecycle statement order or receiver ownership changed: ' + key)
        sites = registered_sites.get((row['destination_file'], row['destination_class'], row['new_name']), [])
        physical_sites = partition_sites_by_original.get(key, [])
        exception_flags = set(row['allowed_edits'].split(',')) & {'context_confirmation', 'formatter_if_braces'}
        if exception_flags != {site['kind'] for site in sites + physical_sites}:
            errors.append('Context exception manifest/site coverage differs: ' + key)
        if sites:
            if row['expected_difference'] != CONTEXT_EXCEPTION_DIFFERENCE:
                errors.append('Context exception description widened: ' + key)
            try:
                actual = remove_context_exceptions(actual, sites, rows, row)
            except ValueError as error:
                errors.append(key + ': ' + str(error))
                continue
        if partition and key in partitions:
            spec = partitions[key]
            errors.extend(key + ': ' + e for e in check_partition(before, actual, spec, physical_lookup, rows, package, row))
            if destination is not None and destination is not in_place:
                try:
                    virtual = partition_virtual(actual, spec, physical_lookup, sources, package)
                except (KeyError, StopIteration, ValueError) as error:
                    errors.append('Cannot reconstruct partition scopes: ' + key + ': ' + str(error))
                    continue
                if declaration_tokens(before, rows, row, original=True) != declaration_tokens(virtual, rows, row):
                    diff = '\n'.join(list(difflib.unified_diff(declaration_tokens(before, rows, row, original=True), declaration_tokens(virtual, rows, row)))[:45])
                    errors.append('Non-verbatim reconstructed partition: ' + key + '\n' + diff)
                actual = virtual
        elif declaration_tokens(before, rows, row, original=destination is not None or CONFIG.get('original_activation', {}).get(key) in sources) != declaration_tokens(actual, rows, row):
            diff = '\n'.join(list(difflib.unified_diff(declaration_tokens(before, rows, row, original=destination is not None or CONFIG.get('original_activation', {}).get(key) in sources), declaration_tokens(actual, rows, row)))[:45])
            errors.append('Non-verbatim settings declaration: ' + key + '\n' + diff)
        if builder_context_signature(before) != builder_context_signature(actual):
            errors.append(key + ': builder/dialog context or guard swapped with the '
                          "State's: " + str(builder_context_signature(before)) + ' -> '
                          + str(builder_context_signature(actual)))
        if context_guard and 'context_guard' in row['allowed_edits']:
            errors.extend(key + ': ' + e for e in check_context(before, actual, rows, row))
    # Only the registered single test accessor is new in the facade at step 0.
    leaves = original_leaves(parsed[source_path]['declarations'], split_names(rows))
    registered_facade = {s['owner'] + '.' + s['name'] for s in scaffolds
                         if s['file'] == source_path}
    retained_renames = {r['destination_class'] + '.' + r['new_name'] for r in rows
                       if r['destination_file'] == source_path}
    extras = set(leaves) - known - retained_renames - {a['name'] for a in CONFIG.get('test_accessors', [])} - registered_facade
    if extras:
        errors.append('Unregistered facade declarations: ' + str(sorted(extras)))
    for rule in CONFIG.get('required_nodes', []):
        if rule['file'] not in sources:
            continue
        node = lookup.get((rule['file'], rule['owner'], rule['name']))
        if node is None or tokens(node) != rule['tokens']:
            errors.append('Required composition signature or dispatch changed: ' + str(rule))
    for spec in CONFIG.get('test_accessors', []):
        accessor = lookup.get((source_path, '', spec['name']))
        if accessor is None:
            if spec.get('required'):
                errors.append('Missing registered test accessor: ' + spec['name'])
            continue
        expected = json.loads((ROOT / spec['tokens_file']).read_text())
        if spec.get('composition'):
            from playback_settings_accessor import check_accessor
            errors.extend(check_accessor(lookup, source_path, spec, expected, rows,
                                         normalized_accessor_tokens, tokens))
            continue
        if (normalized_accessor_tokens(tokens(accessor), spec, rows)
                != normalized_accessor_tokens(expected, spec, rows)):
            errors.append('Test accessor changed outside its registered receiver edits')
    return errors


def check(original_source, sources, rows, source_path, package=None,
          partition=False, context_guard=False, config=None):
    with configured(config or CONFIG):
        return _check(original_source, sources, rows, source_path, package,
                      partition, context_guard)


def self_test(package=None):
    from check_verbatim_moves import parse
    def method(source):
        return parse({'test': 'class Test { ' + source + ' }'}, package)['test']['declarations'][0]['members'][0]
    for literal in ('[1, 2]', '{1, 2}', "{'a': 1, 'b': 2}"):
        plain = method('Object value() => ' + literal + ';')
        formatted = method('Object value() => ' + literal[:-1] + ',' + literal[-1] + ';')
        if tokens(plain) != tokens(formatted):
            raise AssertionError('Optional literal trailing comma rejected')
        changed = method('Object value() => ' + literal.replace('2', '3') + ';')
        if tokens(plain) == tokens(changed):
            raise AssertionError('Changed literal value accepted')
    print('Settings self-test literal formatting commas only: passed')
    live_row = dict(original_name='_SettingsScreenState._loadDownloadLocation',
                    new_name='loadDownloadLocation', allowed_edits='live_getter_callback')
    getter_rows = [dict(original_name='_SettingsScreenState._' + name, new_name=name)
                   for name in LIVE_GETTER_CALLBACKS]
    live_rows = [live_row, *getter_rows]
    live_expected = normalize(['_defaultDownloadLocationLabel'], live_rows, live_row)
    if live_expected != normalize(['_deps', '.', 'defaultDownloadLocationLabel', '(', ')'], live_rows, live_row):
        raise AssertionError('Exact live getter callback rejected')
    for values in (['_deps', '.', 'defaultDownloadLocationLabel', '(', '1', ')'],
                   ['_deps', '.', 'downloadLocationUsesSaf', '(', ')']):
        if live_expected == normalize(values, live_rows, live_row):
            raise AssertionError('Changed live getter callback accepted')
    if live_expected == normalize(['_deps', '.', 'defaultDownloadLocationLabel', '(', ')'], live_rows):
        raise AssertionError('Live getter callback accepted without the named edit')
    print('Settings self-test unregistered/changed live getter callback: rejected')
    confirmation_row = dict(original_name='Test.action', new_name='action',
                            allowed_edits='context_guard,context_confirmation')
    confirmation_original = method('Future<void> action() async { if (!await allowed()) return; if (!mounted) return; show(context); }')
    unconfirmed_text = 'Future<void> action() async { if (!await allowed()) return; if (!_deps.mounted()) return; final context = _deps.context(); show(context); }'
    unconfirmed = method(unconfirmed_text)
    acquisition = next(t['offset'] for t in unconfirmed['tokens'] if t['text'] == 'final')
    confirmation_site = dict(kind='context_confirmation', acquisition=0, return_value=None,
                             prefix_tokens=normalize(tokens(unconfirmed, end=acquisition), [confirmation_row]))
    confirmed_text = unconfirmed_text.replace('show(context);', 'if (!context.mounted) return; show(context);')
    def confirmation_valid(text):
        try:
            stripped = remove_context_exceptions(method(text), [confirmation_site], [confirmation_row], confirmation_row)
        except ValueError:
            return False
        return (declaration_tokens(confirmation_original, [confirmation_row], confirmation_row)
                == declaration_tokens(stripped, [confirmation_row], confirmation_row)
                and not check_context(confirmation_original, stripped, [confirmation_row], confirmation_row))
    if not confirmation_valid(confirmed_text):
        raise AssertionError('Exact context confirmation exception rejected')
    for label, text in {
        'missing context confirmation': unconfirmed_text,
        'changed context confirmation condition': confirmed_text.replace('!context.mounted', 'context.mounted'),
        'changed context confirmation return': confirmed_text.replace('if (!context.mounted) return;', 'if (!context.mounted) return false;'),
        'context confirmation before acquisition': confirmed_text.replace('final context = _deps.context(); if (!context.mounted) return;', 'if (!context.mounted) return; final context = _deps.context();'),
        'await between State guard and acquisition': confirmed_text.replace('final context', 'await work(); final context'),
        'changed existing State guard': confirmed_text.replace('!_deps.mounted()', '_deps.mounted()'),
        'context moved above permission': confirmed_text.replace('final context = _deps.context(); if (!context.mounted) return; ', '').replace('async { ', 'async { final context = _deps.context(); if (!context.mounted) return; '),
        'additional unregistered context guard': confirmed_text.replace('show(context);', 'show(context); if (!context.mounted) return;'),
    }.items():
        if confirmation_valid(text):
            raise AssertionError('Accepted ' + label)
        print('Settings self-test ' + label + ': rejected')
    boolean_original = method('Future<bool> action() async { if (!mounted) return false; show(context); return false; }')
    boolean_text = 'Future<bool> action() async { if (!_deps.mounted()) return false; final context = _deps.context(); if (!context.mounted) return false; show(context); return false; }'
    boolean_node = method(boolean_text)
    boolean_offset = next(t['offset'] for t in boolean_node['tokens'] if t['text'] == 'final')
    boolean_site = dict(confirmation_site, return_value='false', prefix_tokens=normalize(tokens(boolean_node, end=boolean_offset), [confirmation_row]))
    boolean_stripped = remove_context_exceptions(boolean_node, [boolean_site], [confirmation_row], confirmation_row)
    if declaration_tokens(boolean_original, [confirmation_row], confirmation_row) != declaration_tokens(boolean_stripped, [confirmation_row], confirmation_row):
        raise AssertionError('Exact boolean context confirmation rejected')
    print('Settings self-test exact boolean context confirmation: passed')
    braced_original = method('void action() { if (denied) return; work(); }')
    brace_offset = next(t['offset'] for t in braced_original['tokens'] if t['text'] == 'return')
    brace_site = dict(kind='formatter_if_braces', body_tokens=['return', ';'],
                      prefix_tokens=normalize(tokens(braced_original, end=brace_offset), []))
    def braces_valid(text):
        try:
            stripped = remove_context_exceptions(method(text), [brace_site], [], None)
        except ValueError:
            return False
        return tokens(braced_original) == tokens(stripped)
    if not braces_valid('void action() { if (denied) { return; } work(); }'):
        raise AssertionError('Exact formatter braces exception rejected')
    for label, text in {
        'changed braced if condition': 'void action() { if (allowed) { return; } work(); }',
        'changed braced if body': 'void action() { if (denied) { return false; } work(); }',
        'braces around a different if': 'void action() { if (denied) return; if (other) { return; } work(); }',
        'additional unregistered braces': 'void action() { if (denied) { return; } { work(); } }',
    }.items():
        if braces_valid(text):
            raise AssertionError('Accepted ' + label)
        print('Settings self-test ' + label + ': rejected')
    repeated_original = method('void action() { if (first) { work(); } if (second) work(); if (third) { work(); } }')
    repeated_code = [t for t in repeated_original['tokens'] if not t['comment']]
    second_offset = [t['offset'] for t in repeated_code if t['text'] == 'work'][1]
    repeated_site = dict(kind='formatter_if_braces', body_tokens=['work', '(', ')', ';'],
                         prefix_mode='raw', prefix_tokens=tokens(repeated_original, end=second_offset))
    repeated_good = 'void action() { if (first) { work(); } if (second) { work(); } if (third) { work(); } }'
    def repeated_valid(text):
        try:
            stripped = remove_context_exceptions(method(text), [repeated_site], [], None)
        except ValueError:
            return False
        return tokens(stripped) == tokens(repeated_original)
    if not repeated_valid(repeated_good):
        raise AssertionError('Exact repeated-body formatter site rejected')
    for label, text in {
        'repeated body changed elsewhere': repeated_good.replace('work();', 'changed();', 1),
        'repeated body guard changed': repeated_good.replace('second', 'changed'),
        'repeated body extra braces elsewhere': repeated_good.replace('{ work(); }', '{ { work(); } }', 1),
        'repeated body original braces removed': repeated_good.replace('{ work(); }', 'work();', 1),
    }.items():
        if repeated_valid(text):
            raise AssertionError('Accepted ' + label)
        print('Settings self-test ' + label + ': rejected')
    print('Settings self-test exact repeated-body formatter site: passed')
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
    scoped_before = method('List<Object> entries() { final x = 1; return [x, () async { if (!await allowed()) return; if (!mounted) return; show(context); }, () async { if (!mounted) return; show(context); }]; }')
    scoped_sources = {
        'builder': 'class B { B(this.deps) : x = 1; final Object deps; final int x; }',
        'one': 'extension One on B { List<Object> one() { return [x, () async { if (!await allowed()) return; if (!deps.mounted()) return; final context = deps.context(); if (!context.mounted) return; show(context); },]; } }',
        'two': 'extension Two on B { List<Object> two() { return [() async { if (!deps.mounted()) return; final context = deps.context(); show(context); },]; } }',
    }
    scoped_spec = dict(spec, slices=[
        dict(file='one', owner='One', name='one', first_element=0, end_element=2),
        dict(file='two', owner='Two', name='two', first_element=2, end_element=3)])
    scoped_row = dict(original_name='Test.entries', new_name='entries', allowed_edits='partition,context_guard,context_confirmation')
    scoped_node = all_nodes(parse(scoped_sources, package))[('one', 'One', 'one')]
    scoped_offset = next(t['offset'] for t in scoped_node['tokens'] if t['text'] == 'final')
    scoped_site = dict(kind='context_confirmation', acquisition=0, return_value=None,
                       prefix_mode='raw', prefix_tokens=tokens(scoped_node, end=scoped_offset))
    def scoped_valid(sources):
        lookup = all_nodes(parse(sources, package))
        node = lookup[('one', 'One', 'one')]
        try:
            filtered = remove_context_exceptions(node, [scoped_site], [scoped_row], scoped_row)
        except ValueError:
            return False
        retained = {t['offset'] for t in filtered['tokens']}
        lookup[('one', 'One', 'one')] = dict(filtered, _validated_removed_tokens=[
            t for t in node['tokens'] if t['offset'] not in retained])
        virtual = partition_virtual(dispatch, scoped_spec, lookup, sources, package)
        return (declaration_tokens(scoped_before, [scoped_row], scoped_row, original=True)
                == declaration_tokens(virtual, [scoped_row], scoped_row)
                and not check_context(scoped_before, virtual, [scoped_row], scoped_row))
    if not scoped_valid(scoped_sources):
        raise AssertionError('Exact public-deps confirmation and reconstructed slice scopes rejected')
    print('Settings self-test reconstructed slice context scopes: passed')
    for label, file, changed in (
        ('missing physical slice confirmation', 'one', scoped_sources['one'].replace('if (!context.mounted) return;', '')),
        ('changed physical slice return', 'one', scoped_sources['one'].replace('if (!context.mounted) return;', 'if (!context.mounted) return false;')),
        ('slice context hoisted above permission', 'one', scoped_sources['one'].replace('final context = deps.context(); if (!context.mounted) return; ', '').replace('async { ', 'async { final context = deps.context(); if (!context.mounted) return; ')),
        ('slice await between guard and acquisition', 'one', scoped_sources['one'].replace('final context', 'await work(); final context')),
        ('later slice context hoisted above guard', 'two', scoped_sources['two'].replace('if (!deps.mounted()) return; final context = deps.context();', 'final context = deps.context(); if (!deps.mounted()) return;')),
        ('unregistered later slice confirmation', 'two', scoped_sources['two'].replace('show(context);', 'if (!context.mounted) return; show(context);')),
    ):
        if scoped_valid(dict(scoped_sources, **{file: changed})):
            raise AssertionError('Accepted ' + label)
        print('Settings self-test ' + label + ': rejected')
    callback_builder = builder.replace('B() :', 'B(Object summaries, this.deps) :').replace(
        'final int x;', 'final ({void Function() first, void Function() second}) deps; final int x;')
    callback_lookup = all_nodes(parse({'builder': callback_builder}, package))
    callback_args = ['_summaries', ',', '(', 'first', ':', '_deps', '.', 'first', ',',
                     'second', ':', '_deps', '.', 'second', ',', ')']
    callback_spec = dict(spec, constructor_arguments=callback_args)
    callback_dispatch_text = 'List<Object> entries() { final b = B(_summaries, (first: _deps.first, second: _deps.second,)); return [...b.one(), ...b.two()]; }'
    if check_partition(before, method(callback_dispatch_text), callback_spec, callback_lookup, [], package):
        raise AssertionError('Exact fresh callback subset rejected')
    poisoned_args = list(callback_args)
    poisoned_args[8] = 'second'
    poisoned_dispatch = method(callback_dispatch_text.replace('first: _deps.first', 'first: _deps.second'))
    if not check_partition(before, poisoned_dispatch, dict(callback_spec, constructor_arguments=poisoned_args), callback_lookup, [], package):
        raise AssertionError('Accepted a matching fingerprint with a rewired callback')
    print('Settings self-test callback rewired in both dispatcher and manifest: rejected')
    for label, changed in {
        'callback snapshot instead of borrowed function': callback_dispatch_text.replace('first: _deps.first', 'first: _deps.first()'),
        'cached builder instead of fresh constructor': callback_dispatch_text.replace('B(_summaries, (first: _deps.first, second: _deps.second,))', 'cachedBuilder'),
    }.items():
        if not check_partition(before, method(changed), callback_spec, callback_lookup, [], package):
            raise AssertionError('Accepted ' + label)
        print('Settings self-test ' + label + ': rejected')
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
    dialog = method('Future<void> ask() async { await showDialog(builder: (context) => TextButton(onPressed: () { if (!mounted) return; Navigator.of(context).pop(false); })); }')
    same = method('Future<void> ask() async { await showDialog(builder: (context) => TextButton(onPressed: () { if (!_deps.mounted()) return; Navigator.of(context).pop(false); })); }')
    if builder_context_signature(dialog) != builder_context_signature(same):
        raise AssertionError('Unchanged builder context rejected')
    print('Settings self-test unchanged builder context: passed')
    for label, text in {
        'State context inside a builder': 'Future<void> ask() async { await showDialog(builder: (context) => TextButton(onPressed: () { if (!_deps.mounted()) return; Navigator.of(_deps.context()).pop(false); })); }',
        'builder mounted for State mounted': 'Future<void> ask() async { await showDialog(builder: (context) => TextButton(onPressed: () { if (!context.mounted) return; Navigator.of(context).pop(false); })); }',
    }.items():
        if builder_context_signature(dialog) == builder_context_signature(method(text)):
            raise AssertionError('Accepted ' + label)
        print('Settings self-test ' + label + ': rejected')
    guarded = method('Future<void> ask() async { await showDialog(builder: (context) => TextButton(onPressed: () { if (!context.mounted) return; Navigator.of(context).pop(false); })); }')
    if builder_context_signature(guarded) == builder_context_signature(method('Future<void> ask() async { await showDialog(builder: (context) => TextButton(onPressed: () { if (!_deps.mounted()) return; Navigator.of(context).pop(false); })); }')):
        raise AssertionError('Accepted State mounted for builder mounted')
    print('Settings self-test State mounted for builder mounted: rejected')
    param_original = method('Widget buildThing(BuildContext context) { return Text(Theme.of(context).toString()); }')
    param_same = method('Widget buildThing(BuildContext context) { return Text(Theme.of(context).toString()); }')
    param_swapped = method('Widget buildThing(BuildContext context) { return Text(Theme.of(_deps.context()).toString()); }')
    if builder_context_signature(param_original) != builder_context_signature(param_same):
        raise AssertionError('Unchanged parameter context rejected')
    if builder_context_signature(param_original) == builder_context_signature(param_swapped):
        raise AssertionError('Accepted State context in place of a context parameter')
    print('Settings self-test State context in place of a context parameter: rejected')
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
    branches = method('void action() { show(context); if (done) { if (!mounted) return; show(context); } }')
    branches_good = method('void action() { final context = _deps.context(); show(context); if (done) { if (!_deps.mounted()) return; final context = _deps.context(); show(context); } }')
    branches_bad = method('void action() { final context = _deps.context(); show(context); if (done) { final context = _deps.context(); if (!_deps.mounted()) return; show(context); } }')
    if check_context(branches, branches_good) or not check_context(branches, branches_bad):
        raise AssertionError('Later lexical-branch context guard self-test failed')
    print('Settings self-test later-branch context hoisted before guard: rejected')
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
