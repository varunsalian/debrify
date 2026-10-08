"""Exact destination scaffolding, original initializer slots and earlier slices."""
from collections import Counter
import subprocess

import check_kotlin_moves as k


def check_pinned_destination(path, spec, unit, actual, order, expected, compare, errors):
    pinned = spec['pinned_spans']
    if ':prefix' not in pinned or ':tail' not in pinned or not spec.get('order'):
        errors.append('complete pinned destination structure required: ' + path)
    for split in spec.get('split_containers', []):
        for suffix in (':header', ':close', ':tail'):
            if split + suffix not in pinned:
                errors.append('missing pinned structural span: ' + path + ':' + split + suffix)
    fragments = k.lex_fragments(pinned)
    for name in pinned:
        if name in expected:
            errors.append('duplicate destination span ownership: ' + path + ':' + name)
        expected.add(name)
        if name not in actual:
            errors.append('missing pinned structural span: ' + path + ':' + name)
        else:
            compare('pinned destination: ' + path + ':' + name,
                    fragments[name]['pairs'], k.tokens(unit, *actual[name]))
    if order != spec.get('order'):
        errors.append('destination declaration order changed: ' + path)


def check_added(manifest, inventory, orders, actual, unit, expected, compare, errors):
    rows = manifest['added']
    duplicates = Counter(row.get('target') for row in rows)
    originals = {row['original']: row for row in manifest['declarations']}
    fragments = k.lex_fragments({row['target']: row['text'] for row in rows})
    for row in rows:
        target, slot = row['target'], row.get('slot')
        if duplicates[target] > 1 or target in expected:
            errors.append('duplicate added ownership: ' + target)
        if not row.get('text') or not row.get('reason') or slot not in originals:
            errors.append('added requires pinned text, reason and original slot: ' + target)
            continue
        original = originals[slot]
        if original['fate'] != 'moved' or not inventory[slot]['selector'].startswith('property '):
            errors.append('added slot must be a removed original field: ' + target)
        else:
            # The first owned field, not a convenient later method/constant.
            fields = [r['original'] for r in originals.values()
                      if r['fate'] == 'moved' and r['destination'] == original['destination']
                      and inventory[r['original']]['selector'].startswith('property ')
                      and '/companion ' not in r['original']]
            if slot != min(fields, key=lambda name: inventory[name]['start']):
                errors.append('added slot must be the first removed field: ' + target)
        expected.add(target)
        if target not in actual:
            errors.append('missing added declaration: ' + target)
        else:
            compare('added declaration: ' + target, fragments[target]['pairs'],
                    k.tokens(unit, *actual[target]))


def check_earlier(manifest, root, current=None):
    spec = manifest.get('earlier_destinations')
    if not spec:
        return ['earlier destination revision/paths/whitelist required']
    paths = spec['paths']
    if len(paths) != len(set(paths)):
        return ['duplicate earlier destination']
    # Coverage comes from the actual historical manifests, not a caller's list.
    import json
    approved = set()
    for phase in range(1, manifest['phase']):
        previous = json.loads(subprocess.check_output([
            'git', '-C', str(root), 'show',
            spec['revision'] + f':dev/tool/kotlin_moves/tvplayer_p{phase}.json',
        ]))
        approved.update(previous['destinations'])
    if set(paths) != approved:
        return ['earlier destination coverage differs from historical manifests']
    baseline = {path: subprocess.check_output([
        'git', '-C', str(root), 'show', spec['revision'] + ':' + path,
    ]).decode() for path in paths}
    actual = current or {path: (root / path).read_text() for path in paths}
    if set(actual) != set(paths):
        return ['earlier destination source set changed']
    whitelist = spec['whitelist']
    if any(not row.get('reason') or not row.get('review') or row['path'] not in paths
           or not row.get('substitutions') for row in whitelist):
        return ['earlier whitelist requires exact substitutions, reason and review']
    units = k.parse({**{'base:' + p: t for p, t in baseline.items()}, **actual})
    edits = {e[key]: e[key] for row in whitelist for e in row['substitutions']
             for key in ('before', 'after')}
    fragments = k.lex_fragments(edits) if edits else {}
    errors = []
    for path in paths:
        replacements = [e for row in whitelist if row['path'] == path for e in row['substitutions']]
        expected = k.substitutions(k.tokens(units['base:' + path]), replacements, fragments)
        if expected != k.tokens(units[path]):
            errors.append('earlier destination changed beyond reviewed whitelist: ' + path)
    return errors


def extraction(manifest, original):
    """Materialize the exhaustive partition; every inserted byte has an owner."""
    spans, _ = k.spans(k.parse({'base': original})['base'], set(manifest['split_containers']))
    source_edits, moved = {}, {}
    for row in manifest['declarations']:
        if row['fate'] == 'retained':
            continue
        start, end = spans[row['original']]
        text = original[start:end]
        text = apply_text_edits(text, row.get('substitutions', []) + row.get('patches', []))
        source_edits[row['original']] = text if row['fate'] == 'patched' else ''
        if row['fate'] == 'moved':
            moved[row['destination'], row['target']] = text
    for row in manifest['added']:
        source_edits[row['slot']] += row['text']
    current = original
    for name in sorted(source_edits, key=lambda name: spans[name][0], reverse=True):
        start, end = spans[name]
        current = current[:start] + source_edits[name] + current[end:]
    files = {manifest['source']: current}
    for path, spec in manifest['destinations'].items():
        pinned = spec['pinned_spans']
        def render(container):
            text = pinned[container + ':header'] if container else pinned[':prefix']
            for name in spec['order'][container]:
                text += render(name) if name in spec['order'] else moved.get((path, name), pinned.get(name, ''))
            text += pinned[container + ':tail']
            if container:
                text += pinned[container + ':close']
            return text
        files[path] = render('')
    return files


def initializer_kind(expression):
    """Recognize only the reviewed inert forms; calls with arguments stay rejected."""
    import re
    if re.fullmatch(r'(?:null|false|true|[0-9]+(?:_[0-9]+)*(?:L|[uU]L?)?)', expression):
        return 'constant'
    if expression == 'Any()':
        return 'allocation'
    # Phase 11: only a quoted constant (no interpolation or escapes), and an
    # explicitly typed empty Java deque. Constructor arguments remain excluded.
    if re.fullmatch(r'"[^"\\$\r\n]*"', expression):
        return 'constant'
    if re.fullmatch(r'java\.util\.ArrayDeque<[A-Za-z_][A-Za-z0-9_<>,.? \t]*>\(\)', expression):
        return 'allocation'
    # A Kotlin quoted literal without interpolation, escapes or call arguments.
    # parseColor is deterministic for the reviewed literal; no state is read.
    color = re.fullmatch(r'Color\.parseColor\("([^"\\$\n]*)"\)', expression)
    if color and (re.fullmatch(r'#[0-9a-fA-F]{6}(?:[0-9a-fA-F]{2})?', color[1])
                  or color[1].lower() in {
                      'black', 'darkgray', 'gray', 'lightgray', 'white', 'red',
                      'green', 'blue', 'yellow', 'cyan', 'magenta', 'aqua',
                      'fuchsia', 'darkgrey', 'grey', 'lightgrey', 'lime',
                      'maroon', 'navy', 'olive', 'purple', 'silver', 'teal'}):
        return 'constant'
    if expression == 'Handler(Looper.getMainLooper())':
        return 'handler-allocation'
    # Type syntax contains no expression/call tokens. Explicit empty factories
    # allocate only; state-reading arguments and factory wrappers are forbidden.
    typed_empty = r'(?:mutableSetOf|mutableListOf|mutableMapOf|setOf|listOf|mapOf|emptySet|emptyList|emptyMap)<[A-Za-z_][A-Za-z0-9_<>,.? \t]*>\(\)'
    if re.fullmatch(r'(?:intArrayOf\([\d, ]+\)|emptyList\(\)|' + typed_empty +
                   r'|Runnable \{[\s\S]*\}|object : SubtitlePanelController.Callbacks \{[\s\S]*\})', expression):
        return 'allocation'
    return None


def check_initializer_timing(manifest, inventory, original, errors):
    """All later property initializers require an exact, reviewed inert proof."""
    import re
    fields = [r for r in manifest['declarations'] if r['fate'] == 'moved'
              and inventory[r['original']]['selector'].startswith('property ')
              and '/companion ' not in r['original']]
    slots = {r['destination']: min((x['original'] for x in fields if x['destination'] == r['destination']),
                                   key=lambda name: inventory[name]['start']) for r in fields}
    if manifest['phase'] >= 6:
        nested = manifest.get('nested_construction', [])
        children = {row['destination']: row for row in nested}
        if len(children) != len(nested):
            errors.append('duplicate nested construction destination')
        direct = {next(r['destination'] for r in manifest['declarations']
                       if r['original'] == row['slot']): row['slot']
                  for row in manifest['added'] if row['slot'] in inventory}
        def effective(path, trail=()):
            if path in trail:
                raise ValueError('nested construction cycle')
            if path in children:
                row = children[path]
                owner = manifest['destinations'].get(row['owner_destination'], {})
                pinned = owner.get('pinned_spans', {})
                if (row['initializer'] not in pinned or pinned[row['initializer']] != row['text']
                        or row['initializer'] not in owner.get('order', {}).get(row['container'], [])):
                    errors.append('nested construction initializer/position must be pinned: ' + path)
                return effective(row['owner_destination'], (*trail, path))
            if path not in direct:
                raise ValueError('destination lacks effective construction slot: ' + path)
            return direct[path]
        slots = {path: effective(path) for path in slots}
    expected = {r['original']: slots[r['destination']] for r in fields if r['original'] != slots[r['destination']]}
    rows = manifest.get('initializer_timing', [])
    if len(rows) != len(expected) or {r['original']: r['slot'] for r in rows} != expected:
        errors.append('initializer timing coverage differs from all later moved fields')
        return
    for row in rows:
        node = inventory[row['original']]
        text = original[node['start']:node['end']]
        if row.get('text') != text or row.get('line') != original.count('\n', 0, node['start']) + 1 or not row.get('proof'):
            errors.append('initializer timing requires original text/line and inert proof: ' + row['original'])
        expression = text.split(' = ', 1)[-1].split(' //', 1)[0].strip()
        kind = initializer_kind(expression)
        if kind is None or row.get('kind') != kind:
            errors.append('initializer timing not proven inert: ' + row['original'])


def apply_text_edits(text, edits):
    """Pin complete physical-line contexts without relying on indentation."""
    import re
    for edit in edits:
        if edit['before'].startswith('\n') and '\n' not in edit['before'][1:]:
            pattern = re.compile(r'\n([ \t]*)' + re.escape(edit['before'][1:]) + r'(?=\n|$)')
            text, count = pattern.subn(lambda match: '\n' + match[1] + edit['after'].lstrip('\n'), text)
        else:
            count = text.count(edit['before'])
            text = text.replace(edit['before'], edit['after'])
        if count != edit['count']:
            raise ValueError('fixture text substitution occurrence count')
    return text
