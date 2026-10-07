#!/usr/bin/env python3
"""Audit activity arguments at moved call sites using JVM invocation descriptors."""
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
        for pc, call in code:
            index = bisect.bisect_right(offsets, pc) - 1
            if index >= 0:
                result.append(dict(owner=owner, method=method, line=lines[index][1], call=call))

    for line in disassembly.splitlines():
        if re.match(r'^\S.*\b(class|interface)\b', line):
            flush(); code, lines = [], []
            owner = re.search(r'\b(?:class|interface) (\S+)', line).group(1)
        elif re.match(r'^  \S.*\);$', line) or line == '  static {};':
            flush(); code, lines = [], []
            method = line.strip()
        else:
            instruction = re.match(r'\s+(\d+): invoke\w+\s+.*// (?:InterfaceMethod|Method) (.*)', line)
            location = re.match(r'\s+line (\d+): (\d+)$', line)
            if instruction:
                code.append((int(instruction[1]), instruction[2].replace('"', '')))
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
        if callee in ('Intent', 'Builder'):
            named = target.endswith('/' + callee + '.<init>') or target.endswith('$' + callee + '.<init>')
        else:
            named = target.split('.')[-1] in (callee, callee + '$default')
        return named and any(argument in descriptor.split(')')[0] for argument in ACTIVITY_ARGUMENTS)
    found = [x for x in calls if start <= x['line'] <= end and matches(x['call'])]
    signatures = {x['call'] for x in found}
    if len(signatures) != 1:
        raise ValueError(f'call site must resolve uniquely: {callee} at {start}-{end}: {sorted(signatures)}')
    return signatures.pop(), found


def audit(manifest, original, current, before, after):
    units = k.parse({'original': original, **current})
    nodes = {path: {n['id']: n for n in k.walk(u['declarations'])} for path, u in units.items()}
    sites = manifest['overload_audit']
    moved = {r['original']: r for r in manifest['declarations'] if r['fate'] == 'moved'}
    # Exact coverage: all activity-this expressions in moved subtrees except the
    # Runnable's own this, whose text is preserved by the move checker.
    expected = []
    for site in units['original']['this_sites']:
        row = next((r for name, r in moved.items() if nodes['original'][name]['start'] <= site['start'] < nodes['original'][name]['end']), None)
        if row and row['original'].split('/')[-1] != 'property upNextTicker':
            expected.append((row['original'], original.count('\n', 0, site['start']) + 1, site['callee']))
    actual = [(s['original'], s['line'], s['callee']) for s in sites]
    if sorted(expected) != sorted(actual):
        raise ValueError('substituted this-site audit coverage differs from original PSI')
    results = []
    for site in sites:
        row = moved[site['original']]
        if (site['destination'], site['target']) != (row['destination'], row['target']):
            raise ValueError('audit destination differs from moved declaration')
        original_node = nodes['original'][site['original']]
        moved_node = nodes[site['destination']][site['target']]
        psi_site = next(s for s in units['original']['this_sites']
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
        old, old_evidence = resolve([c for c in before if c['owner'] == old_owner or c['owner'].startswith(old_owner + '$')],
                                   site, site['call_start_line'], site['call_end_line'])
        new, new_evidence = resolve([c for c in after if c['owner'] == new_owner or c['owner'].startswith(new_owner + '$')],
                                   site, site['call_start_line'] + delta, site['call_end_line'] + delta)
        if old != new:
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
        print(f'PASS: {len(results)} activity-this call sites; identical JVM invocation descriptors')
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, 'FAIL: ' + str(error) + '\n')


if __name__ == '__main__':
    main()
