#!/usr/bin/env python3
"""Guard the completed TV-player source set and its reviewed collaborator edges."""
import argparse
import json
from pathlib import Path
import sys

import check_kotlin_moves as k

CONFIG = k.ROOT / 'dev/tool/tvplayer_boundaries.json'
TV = 'android/app/src/main/kotlin/com/debrify/app/tv'
MAIN = 'android/app/src/main'
PACKAGE = 'com.debrify.app.tv'


def completed_sources():
    return {p for phase in range(1, 20) for p in json.loads(
        (k.ROOT / f'dev/tool/kotlin_moves/tvplayer_p{phase}.json').read_text())['destinations']}


def discover_sources(root=None):
    """Include the whole TV subtree and main-source files declaring its package."""
    root = k.ROOT if root is None else root
    sources = {p.relative_to(root).as_posix(): p.read_text()
               for p in sorted((root / MAIN).rglob('*.kt'))}
    return sorted(path for path, unit in k.parse(sources).items()
                  if path.startswith(TV + '/') or unit['package'] == PACKAGE)


def import_ranges(tokens):
    ranges, aliases = [], {}
    for i, token in enumerate(tokens):
        if token['text'] != 'import' or token['kind'] != 'IDENTIFIER':
            continue
        end = i + 1
        while end < len(tokens) and tokens[end]['kind'] != 'NL':
            end += 1
        segment = tokens[i + 1:end]
        split = next((j for j, t in enumerate(segment) if t['text'] == 'as'), len(segment))
        names = [t['text'] for t in segment[:split] if t['kind'] == 'IDENTIFIER']
        if split < len(segment):
            aliases[segment[split + 1]['text']] = names
        ranges.append((i, end, names))
    return ranges, aliases


def audit(sources, config, all_paths=None, expected_sources=None):
    expected = completed_sources() if expected_sources is None else set(expected_sources)
    errors = []
    if set(config['source_set']) != expected or set(sources) != expected:
        errors.append('completed source-set coverage differs from manifests')
    legacy = set(config['legacy_exclusions'])
    if legacy & expected:
        errors.append('legacy exclusion overlaps a completed destination')
    if all_paths is not None and set(all_paths) != expected | legacy:
        errors.append('unclassified TV source or stale legacy exclusion')
    units = k.parse(sources)
    peers = set(config['collaborator_types'])
    forbidden = set(config['forbidden_types'])
    edges = set(map(tuple, config['owner_child_edges']))
    actual_hosts = {}
    for path, unit in units.items():
        owner = Path(path).stem
        imports, aliases = import_ranges(unit['tokens'])
        hosts = [n for n in k.walk(unit['declarations']) if n['selector'] == 'class Host']
        approved_host = config['host_interfaces'].get(path)
        if [n['id'] for n in hosts] != ([approved_host] if approved_host else []):
            errors.append('approved Host interface coverage differs: ' + path)
        members = [n for host in hosts for n in k.members(host)]
        approved = config['host_edges'].get(path, {})
        actual_edges = {}
        raw = unit['tokens']
        for i, token in enumerate(raw):
            if token['kind'] != 'IDENTIFIER':
                continue
            name = token['text'].strip('`')
            names = aliases.get(name, [name])
            imported = next((entry for entry in imports if entry[0] <= i < entry[1]), None)
            chain = [name]
            j = i + 1
            while j + 1 < len(raw) and raw[j]['kind'] == 'DOT' and raw[j + 1]['kind'] == 'IDENTIFIER':
                chain.append(raw[j + 1]['text']); j += 2
            if chain[:2] == ['io', 'flutter'] and chain[:5] != ['io', 'flutter', 'plugin', 'common', 'MethodChannel']:
                errors.append('forbidden Flutter namespace: ' + path + ':' + '.'.join(chain))
            for target in names:
                if target in forbidden:
                    errors.append('forbidden Flutter type: ' + path + ':' + target)
                if target == 'MainActivity':
                    allowed = path in config['main_activity_channel_files']
                    if imported:
                        allowed &= imported[2] == ['com', 'debrify', 'app', 'MainActivity']
                    else:
                        allowed &= len(chain) >= 2 and chain[1] == 'getAndroidTvPlayerChannel'
                        allowed &= j < len(raw) and raw[j]['kind'] == 'LPAR'
                    if not allowed:
                        errors.append('unapproved MainActivity access: ' + path)
                if target == 'AndroidTvTorrentPlayerActivity':
                    allowed = config['activity_nested_type_imports'].get(path, [])
                    nested = imported[2][-1] if imported else (chain[1] if len(chain) > 1 else None)
                    if nested not in allowed:
                        errors.append('unapproved concrete Activity reference: ' + path)
                if target not in peers or target == owner:
                    continue
                member = next((m for m in members if m['start'] <= token['start'] < m['end']), None)
                if member:
                    actual_edges.setdefault(member['selector'], set()).add(target)
                    if target not in approved.get(member['selector'], []):
                        errors.append('unapproved Host edge: ' + path + ':' + member['selector'] + ' -> ' + target)
                elif imported:
                    if (owner, target) not in edges and not any(target in values for values in approved.values()):
                        errors.append('direct peer bypass import: ' + path + ' -> ' + target)
                elif (owner, target) not in edges:
                    errors.append('direct peer bypass: ' + path + ' -> ' + target)
        actual_hosts[path] = {name: sorted(values) for name, values in actual_edges.items()}
        if actual_hosts[path] != approved:
            errors.append('approved Host edge coverage differs: ' + path)
    if set(config['host_interfaces']) != {p for p, u in units.items()
            if any(n['selector'] == 'class Host' for n in k.walk(u['declarations']))}:
        errors.append('stale approved Host interface')
    return sorted(set(errors))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--self-test', action='store_true')
    args = parser.parse_args()
    if args.self_test:
        import unittest
        import test_tvplayer_boundaries
        result = unittest.TextTestRunner(verbosity=2).run(
            unittest.defaultTestLoader.loadTestsFromModule(test_tvplayer_boundaries))
        return not result.wasSuccessful()
    config = json.loads(CONFIG.read_text())
    sources = {p: (k.ROOT / p).read_text() for p in config['source_set']}
    all_paths = discover_sources()
    errors = audit(sources, config, all_paths)
    for error in errors:
        print(error)
    print(f'{"FAIL" if errors else "PASS"}: {len(sources)} TV destinations; '
          f'{len(config["host_interfaces"])} approved Hosts; '
          f'{len(config["owner_child_edges"]) // 2} owner/child pairs; '
          f'{len(config["legacy_exclusions"])} exact legacy exclusions')
    return bool(errors)


if __name__ == '__main__':
    sys.exit(main())
