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


def receiver_inventory(manifest, original, unit, nodes, moved):
    """Require every activity receiver, alias use and Runnable self site by PSI."""
    def row_at(offset):
        return next((r for name, r in moved.items() if nodes[name]['start'] <= offset < nodes[name]['end']), None)
    def identity(row, site):
        line = original.count('\n', 0, site['start']) + 1
        return row['original'], line, original.splitlines()[line - 1].strip()
    expected_runnable, expected_alias, calls = [], [], []
    for site in unit['all_this_sites']:
        row = row_at(site['start'])
        if not row:
            continue
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
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(dict(sites=len(results), results=results), indent=2) + '\n')
        print(f'PASS: {len(results)} reviewed receiver call sites; pinned JVM invocations')
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, 'FAIL: ' + str(error) + '\n')


if __name__ == '__main__':
    main()
