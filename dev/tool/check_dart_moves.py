#!/usr/bin/env python3
"""Exhaustive ownership/history over the existing Dart scanner comparison core.

No production writes. --at reads the manifest and every sidecar from that tree;
ordinary checks also protect destinations derived from all earlier manifests.
The required isolated --parser-package is a package_config.json path.
"""
import argparse
from collections import Counter
import json
from pathlib import Path
import subprocess

from check_verbatim_moves import ROOT, parse, ensure_parser_package
from check_settings_moves import (configured, check_context, builder_context_signature,
                                  compare_explicit_tokens, tokens)
from occurrence_field_bindings import failures, lexical_setter_failures
from dart_move_partition import partition, ownership_rows
from dart_move_history import git_text, load_manifest, check_earlier, earlier_sources


def guard_config(manifest):
    config = dict(feature=manifest['feature'], allowed_edits=[], receivers=[],
                  occurrence_field_bindings={'owners': manifest['split_containers'],
                                            'state_classes': manifest['split_containers'],
                                            'mandatory_qualification': True},
                  exact_move_comparison=True)
    config.update(manifest.get('guards', {}))
    return config


def retained_manifest(source, feature, original, base, package):
    unit = parse({'base': original}, package, ownership=True)['base']
    splits = ['_VideoPlayerScreenState'] if any(
        n['name'] == '_VideoPlayerScreenState' for n in unit['declarations']) else []
    spans, orders, _ = partition(unit, splits)
    return dict(schema=1, series='vplayer', phase=1, status='snapshot', base=base,
                source=source, feature=feature, split_containers=splits,
                facade_directives=unit['directives'], facade_orders=orders,
                destinations={}, scaffolding={},
                declarations=[dict(original=key, fate='retained') for key in spans])


def check(manifest, original, sources, package):
    """Validate ownership first, then compare complete disjoint spans and guards."""
    source = manifest['source']
    paths = {source, *manifest['destinations']}
    if set(sources) != paths:
        return ['source set changed: missing=' + str(paths - sources.keys())
                + ' unexpected=' + str(sources.keys() - paths)]
    try:
        parsed = parse({'<original>': original, **sources}, package,
                       occurrence_bindings=True, ownership=True)
    except (ValueError, subprocess.CalledProcessError) as error:
        return ['Dart parse failed: ' + str(error)]
    base, base_orders, original_nodes = partition(parsed['<original>'], manifest['split_containers'])
    current, orders, nodes = {}, {}, {}
    for path in paths:
        splits = (manifest['split_containers'] if path == source
                  else manifest['destinations'][path].get('split_containers', []))
        current[path], orders[path], nodes[path] = partition(parsed[path], splits)
    rows = manifest['declarations']
    assigned = Counter(r['original'] for r in rows)
    errors = ['unassigned declaration: ' + key for key in base.keys() - assigned.keys()]
    errors += ['unknown original declaration: ' + key for key in assigned.keys() - base.keys()]
    errors += ['duplicate move/fate: ' + key for key, count in assigned.items() if count != 1]
    if errors:
        return errors
    expected = {p: set() for p in paths}
    located = {}
    for row in rows:
        key, fate = row['original'], row['fate']
        if fate not in {'retained', 'moved', 'patched'}:
            errors.append('unknown fate: ' + key)
            continue
        path = row.get('destination', source) if fate == 'moved' else source
        target = row.get('target', key)
        if path not in paths or (fate == 'moved' and path == source):
            errors.append('invalid destination: ' + key)
            continue
        if fate != 'moved' and target != key:
            errors.append('retained identity changed: ' + key)
        if target in expected[path]:
            errors.append('duplicate destination ownership: ' + path + ':' + target)
        expected[path].add(target)
        if fate == 'moved' and key in current[source]:
            errors.append('surviving-after-move: ' + key)
        if target not in current[path]:
            errors.append('missing declaration: ' + target)
            continue
        if fate == 'patched' and (not row.get('reason') or not row.get('test') or not row.get('patches')):
            errors.append('patched requires exact patches, reason and test: ' + key)
        if fate != 'patched' and row.get('patches'):
            errors.append('patch outside patched fate: ' + key)
        edits = row.get('substitutions', []) + row.get('patches', [])
        if row.get('remove_static'):
            node = original_nodes.get(key)
            code = [t for t in node['tokens'] if not t['comment']] if node else []
            destination_node = nodes[path].get(target)
            if (fate != 'moved' or '.' in target or not node or not node.get('isStatic')
                    or not node['kind'].startswith('MethodDeclaration') or node['parameters'] is None
                    or not destination_node['kind'].startswith('FunctionDeclaration')
                    or not any(t['text'] == 'static' and t['offset'] < node['bodyOffset'] for t in code)):
                errors.append('static removal requires a static member moved top-level: ' + key)
            edits = [dict(before=['static'], after=[], count=1), *edits]
        errors.extend(compare_explicit_tokens(base[key], current[path][target], edits, key))
        if key in original_nodes and target in nodes[path]:
            located[key] = nodes[path][target]
    for path in paths:
        scaffold = manifest.get('scaffolding', {}).get(path, {})
        for key, pinned in scaffold.items():
            if key in expected[path]:
                errors.append('duplicate scaffold ownership: ' + path + ':' + key)
            expected[path].add(key)
            if key not in current[path] or tokens(current[path][key]) != pinned:
                errors.append('frozen scaffolding changed: ' + path + ':' + key)
        errors += ['unexpected new declaration: ' + path + ':' + key
                   for key in current[path].keys() - expected[path]]
        imports = (manifest['facade_directives'] if path == source
                   else manifest['destinations'][path]['directives'])
        if parsed[path]['directives'] != imports:
            errors.append(('facade import change: ' if path == source else 'destination import mismatch: ') + path)
        reviewed = (manifest['facade_orders'] if path == source else manifest['destinations'][path]['orders'])
        if orders[path] != reviewed:
            errors.append('declaration order differs from reviewed list: ' + path)
    # An edited order list cannot authorize reordered retained field initializers.
    retained = {r['original'] for r in rows if r['fate'] != 'moved'}
    for owner, order in base_orders.items():
        if owner == '@directives':
            continue
        keep = [key for key in order if key in retained or key + ':header' in retained]
        observed = [key for key in orders[source].get(owner, []) if key in keep]
        if observed != keep:
            errors.append('retained member order changed: ' + owner)
    for path in manifest['destinations']:
        moved = sorted((r for r in rows if r['fate'] == 'moved' and r['destination'] == path),
                       key=lambda r: base[r['original']]['start'])
        targets = [r.get('target', r['original']) for r in moved]
        present = sorted((t for t in targets if t in current[path]), key=lambda t: current[path][t]['start'])
        if present != targets:
            errors.append('moved declaration order changed: ' + path)
    # Reviewed patches can change an unbound constructor chain into a helper
    # chain. Project only the ORIGINAL patched members through the existing
    # counted-edit core; then retain all occurrence/scope/context protections
    # for the whole declaration. Destination source is never rewritten.
    from dart_move_fixture import edited_text
    projected = {}
    class_patches = set(manifest.get('patched_class_projection', []))
    for key in class_patches:
        row = next((r for r in rows if r['original'] == key), None)
        node = original_nodes.get(key)
        if (row is None or row['fate'] != 'patched' or not node
                or node['owner'] or not node['kind'].startswith('ClassDeclaration')):
            errors.append('class patch projection requires a patched facade class: ' + key)
    for row in rows:
        key = row['original']
        node = original_nodes.get(key)
        if row['fate'] == 'patched' and node and node['owner'] in manifest['split_containers']:
            text = edited_text(original, base[key], row['patches'])
            projected[key] = 'class ' + node['owner'] + ' { ' + text + ' }'
        elif row['fate'] == 'patched' and key in class_patches and node and not node['owner']:
            try:
                projected[key] = edited_text(original, base[key], row['patches'])
            except ValueError as error:
                errors.append('class patch projection failed: ' + key + ': ' + str(error))
    if projected:
        units = parse(projected, package, occurrence_bindings=True)
        original_nodes = dict(original_nodes)
        for key, unit in units.items():
            members = unit['declarations'] if key in class_patches else unit['declarations'][0]['members']
            if len(members) != 1 or members[0]['name'] != original_nodes[key]['name']:
                errors.append('patch projection changed declaration ownership: ' + key)
            else:
                original_nodes[key] = members[0]
    config = guard_config(manifest)
    core_rows = ownership_rows(manifest)
    original_leaves = {r['original_name']: original_nodes[r['original_name']]
                       for r in core_rows if r['original_name'] in original_nodes}
    core_rows = [r for r in core_rows if r['original_name'] in original_leaves]
    lookup = {}
    for row in core_rows:
        node = located.get(row['original_name'])
        if node:
            lookup[(row['destination_file'], row['destination_class'], row['new_name'])] = node
    with configured(config):
        errors.extend(failures(original_leaves, lookup, core_rows, source, config, package=package))
        errors.extend(lexical_setter_failures(original_leaves, lookup, core_rows, source, config))
        for row in core_rows:
            before, after = original_leaves[row['original_name']], located.get(row['original_name'])
            if after is None or not before['bodyOffset'] or row['original_name'].endswith(':header'):
                continue
            # Same-position receiver substitution changes the AST spelling only;
            # first-use/guard scopes and builder parameters still stay lexical.
            errors.extend(check_context(before, after, core_rows, row))
            receivers = config.get('live_state_receivers', [])
            if builder_context_signature(before, receivers) != builder_context_signature(after, receivers):
                errors.append('builder context changed: ' + row['original_name'])
            if row['destination_file'] != source and before['owner'] in manifest['split_containers']:
                code = [t['text'] for t in after['tokens'] if not t['comment']]
                ownership = next(r for r in rows if r['original'] == row['original_name'])
                qualified = {}
                for name, count in ownership.get('owned_this_fields', {}).items():
                    field = next((r for r in rows if r['original'] == before['owner'] + '.' + name), None)
                    target = field.get('target', '') if field else ''
                    owner, _, public = target.rpartition('.')
                    original_node = original_nodes.get(before['owner'] + '.' + name, {})
                    if (ownership['fate'] != 'moved' or not field or field['fate'] != 'moved'
                            or field['destination'] != row['destination_file']
                            or owner != row['destination_class']
                            or not original_node.get('kind', '').startswith('FieldDeclaration')
                            or dict(before=[name], after=['this', '.', public], count=count)
                               not in ownership.get('substitutions', [])):
                        errors.append('invalid owned this qualification: ' + row['original_name'])
                        continue
                    sites = [i for i in range(len(code)) if code[i:i+3] == ['this', '.', public]]
                    if len(sites) != count:
                        errors.append('owned this qualification count changed: ' + row['original_name'])
                    qualified.update(dict.fromkeys(sites, public))
                if any(v == 'this' and i not in qualified for i, v in enumerate(code)):
                    errors.append('unsubstituted owner-identity this: ' + row['original_name'])
    return errors


def run_manifest(path, package, at=None, root=ROOT):
    manifest = load_manifest(path, at, root)
    if manifest.get('status') == 'draft':
        raise ValueError('draft manifest is not applied; use --self-compare-original')
    original = git_text(manifest['base'], manifest['source'], root)
    paths = {manifest['source'], *manifest['destinations']}
    sources = {p: git_text(at, p, root) if at else (root / p).read_text() for p in paths}
    if not at:
        earlier = set(earlier_sources(manifest, root))
        actual = {p.relative_to(root).as_posix() for p in (root / manifest['feature']).rglob('*.dart')}
        if actual != set(manifest['destinations']) | earlier:
            return ['unexpected/missing feature source files']
    return check(manifest, original, sources, package) + ([] if at else check_earlier(manifest, package, root=root))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', type=Path, default=Path('dev/tool/dart_moves/vplayer_p1_retained.json'))
    parser.add_argument('--parser-package', type=Path, required=True)
    parser.add_argument('--at')
    parser.add_argument('--self-test', action='store_true')
    parser.add_argument('--self-compare-original', action='store_true')
    args = parser.parse_args()
    ensure_parser_package(args.parser_package.parent.parent, args.parser_package)
    if args.self_test:
        from test_dart_moves import run
        run(args.parser_package)
    if args.self_compare_original:
        manifest = load_manifest(args.manifest, args.at)
        original = git_text(manifest['base'], manifest['source'])
        snapshot = retained_manifest(manifest['source'], manifest['feature'], original, manifest['base'], args.parser_package)
        errors = check(snapshot, original, {manifest['source']: original}, args.parser_package)
        print('Classified spans:', len(snapshot['declarations']))
    else:
        errors = run_manifest(args.manifest, args.parser_package, args.at)
    for error in errors:
        print(error)
    print(f'{"FAIL" if errors else "PASS"}: exhaustive Dart ownership; {len(errors)} differences')
    return bool(errors)


if __name__ == '__main__':
    raise SystemExit(main())
