#!/usr/bin/env python3
"""Audit reviewed activity receivers using JVM owners, descriptors and opcodes."""
import argparse
import bisect
import json
from pathlib import Path
import re
import subprocess

import check_kotlin_moves as k

ACTIVITY_ARGUMENTS = ('Landroid/content/Context;', 'Landroid/app/Activity;',
                      'Landroidx/fragment/app/FragmentActivity;',
                      'Landroidx/appcompat/app/AppCompatActivity;',
                      'Landroidx/lifecycle/LifecycleOwner;')


def invocations(disassembly):
    """Read javap's method-local PCs and line tables, including lambda classes."""
    result, owner, method, code, lines = [], None, None, [], []

    def flush():
        offsets = [pc for pc, line in lines]
        for pc, opcode, call in code:
            index = bisect.bisect_right(offsets, pc) - 1
            if index >= 0:
                result.append(dict(owner=owner, method=method, line=lines[index][1], pc=pc, opcode=opcode, call=call))

    for line in disassembly.splitlines():
        if re.match(r'^\S.*\b(class|interface)\b', line):
            flush(); code, lines = [], []
            owner = re.search(r'\b(?:class|interface) (\S+)', line).group(1)
        elif re.match(r'^  \S.*\);$', line) or line == '  static {};':
            flush(); code, lines = [], []
            method = line.strip()
        else:
            instruction = re.match(r'\s+(\d+): (invoke\w+)\s+.*// (?:InterfaceMethod|Method) (.*)', line)
            location = re.match(r'\s+line (\d+): (\d+)$', line)
            if instruction:
                code.append((int(instruction[1]), instruction[2], instruction[3].replace('"', '')))
            elif location:
                lines.append((int(location[2]), int(location[1])))
    flush()
    return result


def bytecode(folder):
    paths = sorted(Path(folder).glob('*.class'))
    if not paths:
        raise ValueError('compiled classes missing: ' + str(folder))
    return invocations(subprocess.check_output(
        [str(k.JBR / 'bin/javap'), '-p', '-c', '-l', '-s', *map(str, paths)], text=True))


def typed_bytecode(folder):
    """Read field/cast/constant instructions without changing historical call output."""
    paths = sorted(Path(folder).glob('*.class'))
    if not paths:
        raise ValueError('compiled classes missing: ' + str(folder))
    raw = subprocess.check_output([str(k.JBR / 'bin/javap'), '-p', '-c', '-l', '-s',
                                   *map(str, paths)], text=True)
    result, owner, method, code, lines = [], None, None, [], []
    def flush():
        offsets = [pc for pc, line in lines]
        for pc, opcode, operand in code:
            index = bisect.bisect_right(offsets, pc) - 1
            if index >= 0:
                result.append(dict(owner=owner, method=method, line=lines[index][1],
                                   pc=pc, opcode=opcode, operand=operand))
    for line in raw.splitlines():
        if re.match(r'^\S.*\b(class|interface)\b', line):
            flush(); code, lines = [], []
            owner = re.search(r'\b(?:class|interface) (\S+)', line).group(1)
        elif re.match(r'^  \S.*\);$', line) or line == '  static {};':
            flush(); code, lines = [], []; method = line.strip()
        else:
            instruction = re.match(r'\s+(\d+): (\w+)\s*(.*)', line)
            location = re.match(r'\s+line (\d+): (\d+)$', line)
            if instruction:
                operand = instruction[3].split('// ', 1)[-1].replace('"', '')
                code.append((int(instruction[1]), instruction[2], operand))
            elif location:
                lines.append((int(location[2]), int(location[1])))
    flush()
    return result


def find_assignment_inventory(manifest, original, current, units, nodes, moved):
    """Exhaust all moved assignments to shared Host targets, including no-cast sites."""
    if manifest['phase'] < 15:
        return []
    original_fields = {n['selector'].removeprefix('property '): n for n in nodes['original'].values()
                       if n['id'].startswith('class AndroidTvTorrentPlayerActivity/property ')
                       and n['id'].count('/') == 1}
    expected = []
    for site in units['original']['find_view_assignments']:
        row = next((r for name, r in moved.items() if nodes['original'][name]['start'] <= site['start'] < nodes['original'][name]['end']), None)
        if row is None:
            continue
        field = site['target'].split('[', 1)[0]
        hosts = [n for n in nodes[row['destination']].values()
                 if n['id'].endswith('/class Host/property ' + field)]
        if not hosts:
            continue
        if len(hosts) != 1 or field not in original_fields:
            raise ValueError('findViewById shared target must resolve uniquely')
        old = original_fields[field]
        typ = old.get('declared_type')
        if typ is None and re.fullmatch(r'arrayOfNulls<TextView>\(3\)', old.get('initializer_text') or ''):
            typ = 'Array<TextView?>'
        if typ is None or hosts[0].get('declared_type') != typ:
            raise ValueError('findViewById Host target type/nullability differs: ' + field)
        line = original.count('\n', 0, site['start']) + 1
        expected.append(dict(original=row['original'], destination=row['destination'], target=row['target'],
                             line=line, context=original.splitlines()[line-1].strip(),
                             field=field, assignment_target=site['target'], source_type=typ))
    actual = manifest.get('find_view_assignments', [])
    keys = tuple(expected[0]) if expected else ()
    if [{key: r.get(key) for key in keys} for r in actual] != expected:
        raise ValueError('findViewById assignment audit coverage differs from original PSI')
    for site in actual:
        if 'cast' not in site or not site.get('descriptor') or not site.get('reason'):
            raise ValueError('findViewById requires cast presence/absence and descriptor pins')
    return actual


def audit_view_bindings(manifest, original, current, before, after):
    """Compare field descriptors against setters/array getters and per-site casts."""
    units = k.parse({'original': original, **current})
    nodes = {p: {n['id']: n for n in k.walk(u['declarations'])} for p, u in units.items()}
    moved = {r['original']: r for r in manifest['declarations'] if r['fate'] == 'moved'}
    sites = find_assignment_inventory(manifest, original, current, units, nodes, moved)
    results = []
    for site in sites:
        old_node = nodes['original'][site['original']];new_node = nodes[site['destination']][site['target']]
        delta = current[site['destination']].count('\n', 0, new_node['start']) - original.count('\n', 0, old_node['start'])
        old_owner = 'com.debrify.app.tv.AndroidTvTorrentPlayerActivity'
        new_owner = 'com.debrify.app.tv.' + site['target'].split('/')[0].removeprefix('class ')
        evidence = []
        for instructions, owner, line, is_new in ((before, old_owner, site['line'], False), (after, new_owner, site['line']+delta, True)):
            local = [i for i in instructions if i['owner'] == owner and i['line'] == line]
            finds = [i for i in local if i['opcode'] == 'invokevirtual' and '.findViewById:(I)Landroid/view/View;' in i['operand']]
            casts = [i['operand'].removeprefix('class ') for i in local if i['opcode'] == 'checkcast']
            if len(finds) != 1 or casts != ([] if site['cast'] is None else [site['cast']]):
                raise ValueError('findViewById cast presence/type differs: ' + site['context'])
            field = site['field'];array = '[' in site['assignment_target'];descriptor = site['descriptor']
            if is_new:
                method = ('get' if array else 'set') + field[0].upper() + field[1:]
                target = method + (':()'+descriptor if array else ':('+descriptor+')V')
                matches = [i for i in local if i['opcode'] == 'invokeinterface' and i['operand'].endswith('.'+target)]
            else:
                matches = [i for i in local if i['opcode'] == ('getfield' if array else 'putfield') and
                           i['operand'].endswith(field+':'+descriptor)]
            if len(matches) != 1:
                raise ValueError('findViewById field/Host descriptor differs: ' + site['context'])
            if array and not any(i['opcode'] == 'aastore' for i in local):
                raise ValueError('findViewById array-element assignment missing')
            evidence.append(local)
        results.append(dict(site=site, before=evidence[0], after=evidence[1]))
    return results


def constant_inlining_inventory(manifest, original, nodes, moved):
    if manifest['phase'] < 15:
        return []
    expected = []
    for row in moved.values():
        node = nodes['original'][row['original']]
        expression = node.get('initializer_text') or ''
        if 'AspectRatioFrameLayout.RESIZE_MODE_' in expression:
            expected.append(dict(original=row['original'], destination=row['destination'], target=row['target'],
                                 expression=expression, owner='androidx/media3/ui/AspectRatioFrameLayout'))
    actual = manifest.get('constant_inlining', [])
    keys = tuple(expected[0]) if expected else ()
    if [{key: r.get(key) for key in keys} for r in actual] != expected or any(not r.get('reason') for r in actual):
        raise ValueError('array constant-inlining proof coverage differs')
    return actual


def audit_constant_inlining(manifest, original, before, after):
    unit = k.parse({'original': original})['original']
    nodes = {'original': {n['id']: n for n in k.walk(unit['declarations'])}}
    moved = {r['original']: r for r in manifest['declarations'] if r['fate'] == 'moved'}
    rows = constant_inlining_inventory(manifest, original, nodes, moved)
    for row in rows:
        old_owner = 'com.debrify.app.tv.AndroidTvTorrentPlayerActivity'
        new_owner = 'com.debrify.app.tv.' + row['target'].split('/')[0].removeprefix('class ')
        for instructions, owner in ((before, old_owner), (after, new_owner)):
            constructor = [i for i in instructions if i['owner'] == owner and
                           i['method'].startswith('public '+owner+'(')]
            if not constructor or any(i['opcode'] == 'getstatic' and row['owner'] in i['operand'] for i in constructor):
                raise ValueError('reviewed array constants must be inlined in constructor bytecode')
    return rows


def resolve(calls, site, start, end):
    callee = site['callee']
    def matches(call):
        target, descriptor = call.split(':', 1)
        if target.endswith('.<init>'):
            named = target.endswith('/' + callee + '.<init>') or target.endswith('$' + callee + '.<init>')
        else:
            named = target.split('.')[-1] in (callee, callee + '$default')
        return named and any(argument in descriptor.split(')')[0] for argument in ACTIVITY_ARGUMENTS)
    found = [x for x in calls if start <= x['line'] <= end and matches(x['call'])]
    signatures = {x['call'] for x in found}
    if len(signatures) != 1:
        raise ValueError(f'call site must resolve uniquely: {callee} at {start}-{end}: {sorted(signatures)}')
    return signatures.pop(), found


def resolve_inherited(calls, site, start, end):
    """Pin owner, descriptor and opcode for a reviewed implicit receiver."""
    found = []
    for invocation in calls:
        target, descriptor = invocation['call'].split(':', 1)
        if not start <= invocation['line'] <= end or target.split('.')[-1] != site['callee']:
            continue
        owner = target.rsplit('.', 1)[0] if '.' in target else invocation['owner'].replace('.', '/')
        found.append((dict(owner=owner, descriptor=descriptor, opcode=invocation['opcode']), invocation))
    signatures = {tuple(sorted(signature.items())) for signature, _ in found}
    if len(signatures) != 1:
        raise ValueError(f'implicit inherited call must resolve uniquely: {site["callee"]} at {start}-{end}')
    return dict(signatures.pop()), [invocation for _, invocation in found]


def receiver_lambda_inventory(manifest, original, unit, nodes, moved):
    """Exhaustive lexical exclusions, pinned to the original receiver and context."""
    expected = []
    for site in unit['all_this_sites']:
        if 'lambda_receiver' not in site:
            continue
        row = next((r for name, r in moved.items()
                    if nodes[name]['start'] <= site['start'] < nodes[name]['end']), None)
        if row:
            line = original.count('\n', 0, site['start']) + 1
            expected.append(dict(original=row['original'], line=line,
                context=original.splitlines()[line - 1].strip(), text=site['text'],
                receiver='receiver-lambda', lambda_callee=site['lambda_callee'],
                lambda_receiver=site['lambda_receiver']))
    actual = manifest.get('receiver_lambda_exclusions', [])
    identities = [{key: row.get(key) for key in expected[0]} for row in actual] if expected else actual
    if expected != identities or any(not row.get('reason') for row in actual):
        raise ValueError('receiver-lambda exclusion coverage/classification differs from original PSI')
    return expected


def receiver_lambda_transformations(manifest, original, unit, nodes, moved):
    """Allow reviewed constructor Activity arguments, never receiver-lambda this."""
    if manifest['phase'] < 12:
        return {}
    expected, offsets = [], []
    for site in unit['all_this_sites']:
        constructors = ('EditText', 'ListView') if manifest['phase'] >= 14 else ('EditText',)
        callee = next((c for c in constructors if site.get('lambda_receiver') == c + '(this)'), None)
        if callee is None:
            continue
        row = next((r for name, r in moved.items()
                    if nodes[name]['start'] <= site['start'] < nodes[name]['end']), None)
        if not row:
            continue
        start, end = site['lambda_receiver_start'], site['lambda_receiver_end']
        constructor = [s for s in unit['all_this_sites'] if s.get('callee') == callee
                       and s.get('receiver') == 'activity' and s.get('call_start') == start
                       and s.get('call_end') == end and 'lambda_receiver' not in s]
        if len(constructor) != 1 or original[start:end] != callee + '(this)':
            raise ValueError('constructor-receiver transformation requires the original Activity argument')
        expected.append(dict(original=row['original'], line=original.count('\n', 0, site['start']) + 1,
            constructor_line=original.count('\n', 0, constructor[0]['start']) + 1,
            context=original.splitlines()[original.count('\n', 0, start)].strip(),
            before=callee + '(this)', after=callee + '(activity)', callee=callee))
        offsets.append((row['original'], site['start']))
    actual = manifest.get('receiver_lambda_transformations', [])
    keys = tuple(expected[0]) if expected else ()
    if ([{key: row.get(key) for key in keys} for row in actual] != expected or
            any(set(row) != {*keys, 'reason'} or not row.get('reason') for row in actual)):
        raise ValueError('constructor-receiver transformation coverage differs from original PSI')
    for row in actual:
        pin = dict(owner='android/widget/' + row['callee'], descriptor='(Landroid/content/Context;)V', opcode='invokespecial')
        audits = [s for s in manifest['overload_audit'] if s['original'] == row['original']
                  and s['line'] == row['constructor_line'] and s['callee'] == row['callee']]
        if len(audits) != 1 or any(audits[0].get(key) != pin for key in ('expected_before', 'expected_after')):
            raise ValueError('constructor-receiver transformation requires pinned constructor audit')
    return dict(zip(offsets, actual))


def listener_inventory(manifest, original, unit, nodes, moved):
    """Only the reviewed global-layout listener self receiver is excluded."""
    expected = []
    for site in unit['all_this_sites']:
        row = next((r for name, r in moved.items()
                    if nodes[name]['start'] <= site['start'] < nodes[name]['end']), None)
        if not row or site.get('receiver') != 'object':
            continue
        if (site.get('object_types') != ['android.view.ViewTreeObserver.OnGlobalLayoutListener'] or
                site.get('object_method') != 'onGlobalLayout' or
                site.get('callee') != 'removeOnGlobalLayoutListener' or site['text'] != 'this'):
            raise ValueError('wrong receiver classification: unreviewed object this')
        line = original.count('\n', 0, site['start']) + 1
        expected.append(dict(original=row['original'], line=line,
            context=original.splitlines()[line - 1].strip(), text='this',
            object_types=site['object_types'], object_method=site['object_method'],
            callee=site['callee']))
    actual = manifest.get('listener_receivers', [])
    keys = tuple(expected[0]) if expected else ()
    if ([{key: row.get(key) for key in keys} for row in actual] != expected or
            any(set(row) != {*keys, 'reason'} or not row.get('reason') for row in actual)):
        raise ValueError('typed listener exclusion coverage/binding differs from original PSI')
    return expected


def reference_inventory(manifest, original, unit, nodes, moved):
    expected = []
    for site in unit['callable_references']:
        row = next((r for name, r in moved.items()
                    if nodes[name]['start'] <= site['start'] < nodes[name]['end']), None)
        if row:
            expected.append(dict(original=row['original'], line=original.count('\n', 0, site['start']) + 1,
                context=original.splitlines()[original.count('\n', 0, site['start'])].strip(),
                callee=site['callee'], receiver=site['receiver']))
    actual = manifest.get('function_references', [])
    keys = tuple(expected[0]) if expected else ()
    if ([{key: row.get(key) for key in keys} for row in actual] != expected or
            any(not row.get('after_receiver') or not row.get('expected_before') or not row.get('expected_after') for row in actual)):
        raise ValueError('function-reference audit coverage differs from original PSI')
    return expected


def check_special_bindings(manifest, original, current, units, nodes, moved):
    if manifest['phase'] >= 15:
        find_assignment_inventory(manifest, original, current, units, nodes, moved)
        constant_inlining_inventory(manifest, original, nodes, moved)
    """Pin typed listener self and callable-reference receiver after extraction."""
    listener_inventory(manifest, original, units['original'], nodes['original'], moved)
    reference_inventory(manifest, original, units['original'], nodes['original'], moved)
    for name, row in moved.items():
        if row['destination'] not in units:
            continue
        old, new = nodes['original'][name], nodes[row['destination']][row['target']]
        def within(sites, node):
            return [s for s in sites if node['start'] <= s['start'] < node['end']]
        before = within(units['original']['all_this_sites'], old)
        listeners = [s for s in before if s.get('receiver') == 'object']
        after = within(units[row['destination']]['all_this_sites'], new)
        keys = ('text', 'object_types', 'object_method', 'callee')
        if [[s.get(key) for key in keys] for s in listeners] != [[s.get(key) for key in keys] for s in after if s.get('receiver') == 'object']:
            raise ValueError('typed listener expression substituted or binding changed: ' + name)
        if manifest['phase'] >= 14:
            keys = ('text', 'lambda_callee', 'lambda_receiver')
            expected = [[s[key] for key in keys] for s in before if 'lambda_receiver' in s]
            transforms = [r for r in manifest['receiver_lambda_transformations'] if r['original'] == name]
            for receiver in expected:
                for transform in transforms:
                    if receiver[-1] == transform['before']:
                        receiver[-1] = transform['after']
            if expected != [[s[key] for key in keys] for s in after if 'lambda_receiver' in s]:
                raise ValueError('receiver-lambda expression substituted or binding changed: ' + name)
            keys = ('text', 'binding', 'callee')
            before_bindings = within(units['original']['preserved_receiver_sites'], old)
            after_bindings = within(units[row['destination']]['preserved_receiver_sites'], new)
            if [[s.get(key) for key in keys] for s in before_bindings] != [[s.get(key) for key in keys] for s in after_bindings]:
                raise ValueError('preserved receiver expression substituted or binding changed: ' + name)
        old_refs = [r for r in manifest.get('function_references', []) if r['original'] == name]
        new_refs = within(units[row['destination']]['callable_references'], new)
        if [(r['callee'], r['after_receiver']) for r in old_refs] != [(r['callee'], r['receiver']) for r in new_refs]:
            raise ValueError('function-reference receiver/dispatch changed: ' + name)


def receiver_inventory(manifest, original, unit, nodes, moved):
    """Require every activity receiver, alias use and Runnable self site by PSI."""
    def row_at(offset):
        return next((r for name, r in moved.items() if nodes[name]['start'] <= offset < nodes[name]['end']), None)
    def identity(row, site):
        line = original.count('\n', 0, site['start']) + 1
        return row['original'], line, original.splitlines()[line - 1].strip()
    expected_runnable, expected_alias, calls = [], [], []
    if manifest['phase'] >= 13:
        listener_inventory(manifest, original, unit, nodes, moved)
        reference_inventory(manifest, original, unit, nodes, moved)
    if manifest['phase'] >= 14:
        preserved_receiver_inventory(manifest, original, unit, nodes, moved)
    if manifest['phase'] >= 11:
        receiver_lambda_inventory(manifest, original, unit, nodes, moved)
    if manifest['phase'] >= 12:
        receiver_lambda_transformations(manifest, original, unit, nodes, moved)
    for site in unit['all_this_sites']:
        row = row_at(site['start'])
        if not row:
            continue
        if manifest['phase'] >= 11 and 'lambda_receiver' in site:
            continue
        if manifest['phase'] >= 13 and site.get('receiver') == 'object':
            continue  # Exhaustively checked by the typed listener inventory above.
        if site['receiver'] == 'Runnable':
            expected_runnable.append(identity(row, site))
            continue
        if site['receiver'] != 'activity':
            raise ValueError('wrong receiver classification: unreviewed object this')
        alias = next((a for a in unit['context_aliases'] if a['start'] == site['start']), None)
        if alias:
            expected_alias.append(dict(original=row['original'], line=identity(row, site)[1],
                context=identity(row, site)[2], name=alias['name'], uses=[dict(
                    line=original.count('\n', 0, use['start']) + 1, callee=use.get('callee'),
                    context=original.splitlines()[original.count('\n', 0, use['start'])].strip()) for use in alias['uses']]))
            if not alias['uses'] or any('callee' not in use for use in alias['uses']):
                raise ValueError('unlisted alias escape/non-call use')
            calls.extend(alias['uses'])
        elif 'callee' in site:
            calls.append(site)
        else:
            raise ValueError('unlisted alias/non-call activity receiver')
    actual_runnable = [(x['original'], x['line'], x['context']) for x in manifest['runnable_receivers']]
    if sorted(expected_runnable) != sorted(actual_runnable) or any(not x.get('reason') for x in manifest['runnable_receivers']):
        raise ValueError('wrong receiver classification: reviewed Runnable receiver list differs from PSI')
    if expected_alias != manifest['context_aliases']:
        raise ValueError('unlisted alias: context alias initialization/uses differ from PSI')
    expected = sorted((row_at(x['start'])['original'], original.count('\n', 0, x['start']) + 1, x['callee']) for x in calls)
    actual = sorted((x['original'], x['line'], x['callee']) for x in manifest['overload_audit']
                    if x.get('receiver') != 'implicit-inherited')
    if expected != actual:
        raise ValueError('substituted this-site audit coverage differs from original PSI')
    for site in manifest['overload_audit']:
        if site.get('receiver') == 'implicit-inherited':
            continue
        is_alias = any(a['original'] == site['original'] and any(
            use['line'] == site['line'] for use in a['uses']) for a in expected_alias)
        if is_alias != bool(site.get('alias')):
            raise ValueError('wrong receiver classification: alias-use marker differs')
        if manifest['phase'] >= 14:
            psi = next(s for s in calls if identity(row_at(s['start']), s)[:2] ==
                       (site['original'], site['line']) and s['callee'] == site['callee'])
            if psi.get('call_kind') != site.get('call_kind'):
                raise ValueError('super-constructor audit call kind differs from original PSI')
    if manifest['phase'] >= 9:
        inherited = [s for s in unit['implicit_inherited_sites']
                     if s.get('introduced_phase', 9) <= manifest['phase'] and row_at(s['start'])]
        expected = sorted((row_at(s['start'])['original'], original.count('\n', 0, s['start']) + 1, s['callee']) for s in inherited)
        actual = sorted((s['original'], s['line'], s['callee']) for s in manifest['overload_audit']
                        if s.get('receiver') == 'implicit-inherited')
        if expected != actual:
            raise ValueError('implicit inherited-receiver audit coverage differs from original PSI')
        for site in manifest['overload_audit']:
            if site.get('receiver') == 'implicit-inherited':
                for key in ('expected_before', 'expected_after'):
                    pin = site.get(key, {})
                    if set(pin) != {'owner', 'descriptor', 'opcode'} or pin['opcode'] != 'invokevirtual':
                        raise ValueError('implicit inherited-receiver pin requires virtual owner/descriptor/opcode')
        calls.extend(inherited)
    elif any(s.get('receiver') == 'implicit-inherited' for s in manifest['overload_audit']):
        raise ValueError('implicit inherited receivers require phase 9 audit')
    return calls


def preserved_receiver_inventory(manifest, original, unit, nodes, moved):
    """Pin adapter/View receivers and the constructor's resources argument."""
    expected = []
    for site in unit['preserved_receiver_sites']:
        row = next((r for name, r in moved.items() if nodes[name]['start'] <= site['start'] < nodes[name]['end']), None)
        if row:
            line = original.count('\n', 0, site['start']) + 1
            expected.append(dict(original=row['original'], line=line,
                context=original.splitlines()[line - 1].strip(), text=site['text'],
                binding=site['binding'], callee=site.get('callee')))
    actual = manifest.get('preserved_receivers', [])
    keys = tuple(expected[0]) if expected else ()
    if ([{key: row.get(key) for key in keys} for row in actual] != expected or
            any(not row.get('reason') for row in actual)):
        raise ValueError('preserved receiver coverage/binding differs from original PSI')
    for row in actual:
        if row['callee']:
            if any(set(row.get(key, {})) != {'owner', 'descriptor', 'opcode'}
                   or row[key]['opcode'] != 'invokevirtual' for key in ('expected_before', 'expected_after')):
                raise ValueError('preserved receiver requires pinned virtual owner/descriptor/opcode')
    return expected


def audit(manifest, original, current, before, after):
    units = k.parse({'original': original, **current})
    nodes = {path: {n['id']: n for n in k.walk(u['declarations'])} for path, u in units.items()}
    sites = manifest['overload_audit']
    moved = {r['original']: r for r in manifest['declarations'] if r['fate'] == 'moved'}
    if manifest['phase'] >= 4:
        receiver_sites = receiver_inventory(manifest, original, units['original'], nodes['original'], moved)
    else:
        # Historical phase-3 manifest retains its reviewed Up Next receiver.
        expected = []
        for site in units['original']['this_sites']:
            row = next((r for name, r in moved.items() if nodes['original'][name]['start'] <= site['start'] < nodes['original'][name]['end']), None)
            if row and row['original'].split('/')[-1] != 'property upNextTicker':
                expected.append((row['original'], original.count('\n', 0, site['start']) + 1, site['callee']))
        actual = [(s['original'], s['line'], s['callee']) for s in sites]
        if sorted(expected) != sorted(actual):
            raise ValueError('substituted this-site audit coverage differs from original PSI')
        receiver_sites = units['original']['this_sites']
    if manifest['phase'] >= 13:
        check_special_bindings(manifest, original, current, units, nodes, moved)
    results = []
    for site in sites:
        row = moved[site['original']]
        if (site['destination'], site['target']) != (row['destination'], row['target']):
            raise ValueError('audit destination differs from moved declaration')
        original_node = nodes['original'][site['original']]
        moved_node = nodes[site['destination']][site['target']]
        psi_site = next(s for s in receiver_sites
                        if original.count('\n', 0, s['start']) + 1 == site['line']
                        and s['callee'] == site['callee'])
        if (site['call_start_line'], site['call_end_line'], site['context']) != (
                original.count('\n', 0, psi_site['call_start']) + 1,
                original.count('\n', 0, psi_site['call_end']) + 1,
                original.splitlines()[site['line'] - 1].strip()):
            raise ValueError('audit call context differs from original PSI')
        delta = current[site['destination']].count('\n', 0, moved_node['start']) - original.count('\n', 0, original_node['start'])
        old_owner = 'com.debrify.app.tv.AndroidTvTorrentPlayerActivity'
        new_owner = 'com.debrify.app.tv.' + site['target'].split('/')[0].removeprefix('class ')
        resolver = resolve_inherited if site.get('receiver') == 'implicit-inherited' else resolve
        old, old_evidence = resolver([c for c in before if c['owner'] == old_owner or c['owner'].startswith(old_owner + '$')],
                                   site, site['call_start_line'], site['call_end_line'])
        new, new_evidence = resolver([c for c in after if c['owner'] == new_owner or c['owner'].startswith(new_owner + '$')],
                                   site, site['call_start_line'] + delta, site['call_end_line'] + delta)
        if site.get('receiver') == 'implicit-inherited':
            if old != site['expected_before'] or new != site['expected_after']:
                raise ValueError(f'implicit inherited dispatch changed at original line {site["line"]}: {old} -> {new}')
        elif manifest['phase'] >= 10:
            def signature(call, evidence):
                target, descriptor = call.split(':', 1)
                opcodes = {entry['opcode'] for entry in evidence}
                if len(opcodes) != 1:
                    raise ValueError('argument receiver opcode must resolve uniquely')
                return dict(owner=target.rsplit('.', 1)[0], descriptor=descriptor, opcode=opcodes.pop())
            for key in ('expected_before', 'expected_after'):
                if set(site.get(key, {})) != {'owner', 'descriptor', 'opcode'}:
                    raise ValueError('argument receiver pin requires owner/descriptor/opcode')
            if (old != new or signature(old, old_evidence) != site['expected_before'] or
                    signature(new, new_evidence) != site['expected_after']):
                raise ValueError(f'argument receiver dispatch changed at original line {site["line"]}')
        elif old != new:
            raise ValueError(f'overload changed at original line {site["line"]}: {old} -> {new}')
        results.append(dict(site=site, resolved_before=old, resolved_after=new,
                            before=old_evidence, after=new_evidence))
    if manifest['phase'] >= 13:
        for reference in manifest.get('function_references', []):
            row = moved[reference['original']]
            old_node = nodes['original'][row['original']]
            new_node = nodes[row['destination']][row['target']]
            delta = current[row['destination']].count('\n', 0, new_node['start']) - original.count('\n', 0, old_node['start'])
            for calls, pin, line in ((before, reference['expected_before'], reference['line']),
                                     (after, reference['expected_after'], reference['line'] + delta)):
                candidates = [call for call in calls if call['line'] == line and
                              '$' in call['owner'] and ' invoke(' in call['method'] and
                              call['call'].split(':')[0].endswith('.' + pin['callee'])]
                signatures = { (call['call'], call['opcode']) for call in candidates }
                if signatures != {(pin['owner'] + '.' + pin['callee'] + ':' + pin['descriptor'], pin['opcode'])}:
                    raise ValueError('compiled function-reference dispatch changed: ' + reference['original'])
    if manifest['phase'] >= 14:
        for site in manifest['preserved_receivers']:
            row = moved[site['original']]
            old_node = nodes['original'][row['original']]
            new_node = nodes[row['destination']][row['target']]
            delta = current[row['destination']].count('\n', 0, new_node['start']) - original.count('\n', 0, old_node['start'])
            old_owner = 'com.debrify.app.tv.AndroidTvTorrentPlayerActivity'
            new_owner = 'com.debrify.app.tv.' + row['target'].split('/')[0].removeprefix('class ')
            for calls, owner, line, key in ((before, old_owner, site['line'], 'expected_before'),
                                            (after, new_owner, site['line'] + delta, 'expected_after')):
                scope = [c for c in calls if c['owner'] == owner or c['owner'].startswith(owner + '$')]
                if site['callee']:
                    pin, _ = resolve_inherited(scope, site, line, line)
                    if pin != site[key]:
                        raise ValueError('preserved receiver compiled dispatch changed: ' + site['context'])
                elif any(c['line'] == line and c['call'].split(':')[0].endswith('.getResources') for c in scope):
                    raise ValueError('named resources argument became a getter')
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', type=Path, required=True)
    parser.add_argument('--tree', type=Path, default=k.ROOT)
    parser.add_argument('--original-classes', type=Path, required=True)
    parser.add_argument('--moved-classes', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    try:
        manifest = json.loads(args.manifest.read_text())
        original = subprocess.check_output(['git', '-C', str(k.ROOT), 'show', manifest['base'] + ':' + manifest['source']], text=True)
        current = {path: (args.tree / path).read_text() for path in manifest['destinations']}
        results = audit(manifest, original, current, bytecode(args.original_classes), bytecode(args.moved_classes))
        view_results, constant_results = [], []
        if manifest['phase'] >= 15:
            before, after = typed_bytecode(args.original_classes), typed_bytecode(args.moved_classes)
            view_results = audit_view_bindings(manifest, original, current, before, after)
            constant_results = audit_constant_inlining(manifest, original, before, after)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(dict(sites=len(results), preserved_receivers=len(manifest.get('preserved_receivers', [])), function_references=len(manifest.get('function_references', [])), listener_receivers=len(manifest.get('listener_receivers', [])), results=results, find_view_assignments=len(view_results), view_results=view_results, constant_inlining=constant_results), indent=2) + '\n')
        print(f'PASS: {len(results)} reviewed receiver call sites; pinned JVM invocations' +
              (f'; {len(manifest.get("function_references", []))} compiled function references; '
               f'{len(manifest.get("listener_receivers", []))} typed listener receivers' if manifest['phase'] >= 13 else ''))
        if manifest['phase'] >= 15:
            print(f'PASS: {len(view_results)} field/Host type and cast pins; {len(constant_results)} constant-inlining proofs')
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, 'FAIL: ' + str(error) + '\n')


if __name__ == '__main__':
    main()
