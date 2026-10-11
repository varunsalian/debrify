#!/usr/bin/env python3
"""Resolve a declaration through applied manifests; return validated LIVE text."""
import argparse
import json
from pathlib import Path

from check_verbatim_moves import ROOT, parse, ensure_parser_package
from check_dart_moves import run_manifest
from dart_move_history import load_manifest
from dart_move_partition import partition


def chain(identity, manifests):
    if not manifests:
        raise ValueError('no applied video-player ownership manifests')
    path = manifests[0]['source']
    traces = []
    for manifest in manifests:
        if path != manifest['source']:
            # Later facade phases protect earlier destinations via history.
            # A further relocation is only legal in a manifest owning this path.
            continue
        rows = [r for r in manifest['declarations'] if r['original'] == identity]
        if len(rows) != 1:
            if identity in manifest.get('scaffolding', {}).get(path, {}):
                traces.append(dict(checkpoint=manifest.get('checkpoint'), phase=manifest['phase'], path=path, identity=identity))
                continue
            raise ValueError('missing/duplicate declaration fate: ' + identity)
        row = rows[0]
        if row['fate'] == 'moved':
            path, identity = row['destination'], row.get('target', identity)
        traces.append(dict(checkpoint=manifest.get('checkpoint'), phase=manifest['phase'], path=path, identity=identity))
    return path, identity, traces


def live_text(identity, manifests, sources, package):
    path, target, traces = chain(identity, manifests)
    if path not in sources:
        raise ValueError('missing live owner: ' + path)
    unit = parse({path: sources[path]}, package, ownership=True)[path]
    owner = next((m for m in reversed(manifests) if m['source'] == path or path in m['destinations']), None)
    splits = owner['split_containers'] if owner['source'] == path else owner['destinations'][path].get('split_containers', [])
    _, _, nodes = partition(unit, splits)
    if target not in nodes:
        raise ValueError('missing live declaration: ' + target)
    return dict(path=path, declaration=target, source=nodes[target]['text'], chain=traces)


def read(identity, package):
    registered = []
    for path in sorted((ROOT / 'dev/tool/dart_moves').glob('*.json')):
        value = load_manifest(path)
        if value.get('schema') == 1 and value.get('series') == 'vplayer' and value.get('status') in {'applied', 'checkpoint'}:
            registered.append((path, value))
    registered.sort(key=lambda item: (item[1]['phase'], 0 if item[1].get('checkpoint') == 'S' else 1))
    if not registered:
        raise ValueError('no current ownership checkpoint')
    manifests = [m for _, m in registered]
    # The latest phase compares its entire facade and destination set and
    # derives earlier destinations from history; S also stays frozen while
    # it is the latest checkpoint. Never use git-show text as the response.
    errors = run_manifest(registered[-1][0], package)
    if errors:
        raise ValueError('\n'.join(errors))
    path, _, _ = chain(identity, manifests)
    sources = {path: (ROOT / path).read_text()}
    return live_text(identity, manifests, sources, package)


def self_test(package):
    from check_dart_moves import check
    from dart_move_fixture import materialize
    from dart_move_history import git_text
    seam = load_manifest(ROOT / 'dev/tool/dart_moves/vplayer_p1_seam.json')
    draft = load_manifest(ROOT / 'dev/tool/dart_moves/vplayer_p1.json')
    identity = '_VideoPlayerScreenState._generateFilenameHash'
    current = read(identity, package)
    expected_path = 'lib/features/video_player/application/vp_filename_hash.dart'
    assert current['path'] == (expected_path if draft['status'] == 'applied' else seam['source'])
    if draft['status'] == 'applied':
        assert current['declaration'] == 'vpFilenameHash'
        assert len(current['chain']) == 2
    assert 'nameWithoutExt.hashCode.toString()' in current['source']
    original = git_text(draft['base'], draft['source'])
    virtual = materialize(draft, original, package)
    assert not check(draft, original, virtual, package)
    first = live_text(identity, [seam, draft], virtual, package)
    assert first['declaration'] == 'vpFilenameHash'
    assert first['path'].endswith('application/vp_filename_hash.dart')
    # A second owner manifest relocates the already-renamed declaration.
    path = first['path']
    next_path = path.replace('vp_filename_hash', 'vp_filename_identity')
    next_manifest = dict(source=path, phase=2, split_containers=[],
        declarations=[dict(original='vpFilenameHash', fate='moved', destination=next_path, target='vpFilenameIdentity')],
        destinations={next_path: dict(split_containers=[])})
    moved = first['source'].replace('vpFilenameHash', 'vpFilenameIdentity', 1)
    second = live_text(identity, [seam, draft, next_manifest], {next_path: moved}, package)
    assert second['declaration'] == 'vpFilenameIdentity' and second['source'] == moved
    assert len(second['chain']) == 3
    # Current-body mutation cannot pass validation using the historical body.
    drift = dict(virtual)
    drift[path] = drift[path].replace('nameWithoutExt.hashCode', 'filename.hashCode', 1)
    assert check(draft, original, drift, package)
    for bad in [[], [dict(seam, declarations=[])], [dict(seam, declarations=seam['declarations'] * 2)]]:
        try:
            chain(identity, bad)
        except ValueError:
            pass
        else:
            raise AssertionError('incomplete or duplicate ownership accepted')
    try:
        live_text(identity, [seam, draft, next_manifest], {}, package)
    except ValueError:
        pass
    else:
        raise AssertionError('historical text substituted for a missing current owner')
    print('PASS: current validated owner, frozen Phase-1 manifest, two relocations, changed body, missing/duplicate fates and missing live owner')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--declaration')
    parser.add_argument('--self-test', action='store_true')
    parser.add_argument('--parser-package', type=Path, required=True)
    args = parser.parse_args()
    package = args.parser_package.resolve()
    if not package.is_relative_to(ROOT / '.dart_tool/vplayer_parser'):
        parser.error('use a worktree-local isolated .dart_tool/vplayer_parser package')
    ensure_parser_package(package.parents[1], package)
    if args.self_test:
        self_test(package)
    elif args.declaration:
        print(json.dumps(read(args.declaration, package)))
    else:
        parser.error('use --declaration or --self-test')


if __name__ == '__main__':
    main()
