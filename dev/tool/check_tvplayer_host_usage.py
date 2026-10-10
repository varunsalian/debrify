#!/usr/bin/env python3
"""Require a production invocation of every declared collaborator Host member.

Generated default/access helpers are edges, never usage roots. Properties need
either accessor; a setter-only Host is valid. This is a compiled call-site audit,
not a claim that every runtime branch has been visited.
"""
import argparse
from collections import deque
import json
from pathlib import Path
import re
import subprocess

import check_kotlin_moves as k


def compiled_methods(folder):
    paths = sorted(Path(folder).glob('*.class'))
    if not paths:
        raise ValueError('compiled production classes missing')
    raw = subprocess.check_output([str(k.JBR / 'bin/javap'), '-p', '-c', '-s',
                                   *map(str, paths)], text=True)
    methods, owner, pending, current = {}, None, None, None
    for line in raw.splitlines():
        header = re.match(r'^\S.*\b(?:class|interface) (\S+)', line)
        if header:
            owner = header[1].split('<')[0]
            pending = current = None
        elif re.match(r'^  .*\(.*\)(?: throws .*)?;$', line):
            name = line.split('(', 1)[0].split()[-1]
            pending = '<init>' if name == owner else name
            current = None
        elif line == '  static {};':
            pending, current = '<clinit>', None
        elif pending and line.strip().startswith('descriptor:'):
            descriptor = line.split(':', 1)[1].strip()
            current = (owner, pending, descriptor)
            methods[current] = dict(calls=set(), code=False)
            pending = None
        elif current and line.strip() == 'Code:':
            methods[current]['code'] = True
        elif current:
            call = re.search(r'\binvoke\w+\s+.*// (?:InterfaceMethod|Method) (.*)', line)
            if call:
                target, descriptor = call[1].replace('"', '').split(':', 1)
                callee_owner, dot, name = target.rpartition('.')
                methods[current]['calls'].add((callee_owner.replace('/', '.') if dot else owner,
                                              name if dot else target, descriptor))
    return methods


def host_members(sources):
    units = k.parse(sources)
    result = []
    for path, unit in units.items():
        for node in k.walk(unit['declarations']):
            if node['selector'] != 'class Host':
                continue
            owner = 'com.debrify.app.tv.' + '$'.join(
                part.removeprefix('class ') for part in node['id'].split('/'))
            for member in k.members(node):
                selector = member['selector']
                if selector.startswith('property '):
                    name = selector.removeprefix('property ')
                    boolean = re.match(r'^is[A-Z]', name)
                    getter = name if boolean else 'get' + name[0].upper() + name[1:]
                    setter = 'set' + (name[2:] if boolean else name[0].upper() + name[1:])
                    names = [getter, setter]
                elif selector.startswith('fun '):
                    names = [selector.removeprefix('fun ').split('(', 1)[0]]
                else:
                    raise ValueError('unclassified Host member: ' + member['id'])
                result.append(dict(owner=owner, selector=selector, names=names, source=path))
    return result


def audit(members, methods):
    owners = {row['owner'] for row in members}
    roots = {key for key, value in methods.items() if value['code'] and
             not any(key[0] == host or key[0].startswith(host + '$') for host in owners)
             and not key[1].endswith('$default') and not key[1].startswith('access$')}
    previous = {key: None for key in roots}
    queue = deque(sorted(roots))
    while queue:
        key = queue.popleft()
        for target in sorted(methods.get(key, {}).get('calls', [])):
            if target not in previous:
                previous[target] = key
                queue.append(target)
    result, errors = [], []
    for row in members:
        declarations = {key for key in methods if key[0] == row['owner'] and key[1] in row['names']}
        if not declarations:
            errors.append('compiled Host declaration missing: ' + row['owner'] + '/' + row['selector'])
            continue
        if row['selector'].startswith('fun ') and len(declarations) != 1:
            errors.append('ambiguous compiled Host overload: ' + row['owner'] + '/' + row['selector'])
            continue
        used = sorted(declarations & previous.keys())
        if not used:
            errors.append('unused Host member: ' + row['owner'] + '/' + row['selector'])
        paths = []
        for key in used:
            chain = [key]
            while previous[chain[-1]] is not None:
                chain.append(previous[chain[-1]])
            paths.append(list(reversed(chain)))
        result.append(dict(**row, declared=sorted(declarations), used=used, caller_paths=paths))
    if errors:
        raise ValueError('\n'.join(errors))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--classes', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    paths = set()
    for phase in range(1, 20):
        manifest = json.loads((k.ROOT / f'dev/tool/kotlin_moves/tvplayer_p{phase}.json').read_text())
        paths.update(manifest['destinations'])
    # Keep the PSI build and all intermediate inputs beside the evidence report.
    k.evidence_root = lambda root: args.output.parent / 'host-psi'
    members = host_members({p: (k.ROOT / p).read_text() for p in sorted(paths)})
    try:
        result = audit(members, compiled_methods(args.classes))
    except ValueError as error:
        parser.exit(1, str(error) + '\n')
    report = dict(hosts=len({x['owner'] for x in members}), members=len(members),
                  all_used=True, results=result)
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(f"PASS: {report['hosts']} compiled Hosts / {report['members']} members have production callers")


if __name__ == '__main__':
    main()
