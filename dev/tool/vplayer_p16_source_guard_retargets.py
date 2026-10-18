#!/usr/bin/env python3
"""Prepare equal-or-stronger live-reader guards; no application/history activation."""
import argparse
import json
from pathlib import Path

from check_verbatim_moves import ROOT, parse
from check_settings_moves import tokens, apply_explicit_token_edits
from dart_move_history import load_manifest
from dart_move_partition import partition
from vplayer_checkpoint_proof import run_current_manifest
from vplayer_source_reader import chain, live_text, registration_order


def failures(contract, text):
    errors = []
    for anchor in contract['anchors']:
        if anchor not in text:
            errors.append('missing anchor: ' + anchor)
    for anchor in contract.get('absent', []):
        if anchor in text:
            errors.append('prohibited anchor: ' + anchor)
    for first, second in contract.get('ordered', []):
        a, b = text.find(first), text.find(second)
        if a < 0 or b < 0 or a >= b:
            errors.append('missing or reordered anchors: ' + repr((first, second)))
    return errors


def projected(identity, manifests, sources, package, future=None):
    response = live_text(identity, manifests, sources, package)
    path, target, _ = chain(identity, manifests)
    owner = next(m for m in reversed(manifests)
                 if m['source'] == path or path in m.get('destinations', {}))
    splits = (owner['split_containers'] if path == owner['source']
              else owner['destinations'][path].get('split_containers', []))
    unit = parse({path: sources[path]}, package, ownership=True)[path]
    _, _, nodes = partition(unit, splits)
    node = nodes[target]
    assert node['text'] == response['source']
    values = tokens(node)
    if future:
        row = next(r for r in future['declarations'] if r['original'] == identity)
        edits = row.get('substitutions', [])
        values = apply_explicit_token_edits(values, [
            dict(before=e['after'], after=e['before'], count=e['count'])
            for e in sorted(edits, key=lambda e: -len(e['after']))])
    return ' '.join(values), response


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--parser-package', type=Path, required=True)
    parser.add_argument('--prototype', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    config = json.loads((ROOT / 'dev/tool/vplayer_p16_source_guard_retargets.json').read_text())
    registered = []
    for path in (ROOT / 'dev/tool/dart_moves').glob('*.json'):
        item = load_manifest(path)
        if item.get('series') == 'vplayer' and item.get('status') in {'applied', 'checkpoint'}:
            registered.append((path, item))
    registered.sort(key=registration_order)
    errors = run_current_manifest(registered[-1][0], args.parser_package)
    if errors:
        raise ValueError('\n'.join(errors))
    manifests = [m for _, m in registered]
    paths = {m['source'] for m in manifests}
    paths.update(p for m in manifests for p in m.get('destinations', {}))
    current = {p: (ROOT / p).read_text() for p in paths}
    modes = [('current', manifests, current, None)]
    if args.prototype:
        from check_dart_moves import check
        draft = load_manifest(ROOT / 'dev/tool/dart_moves/vplayer_p16.json')
        virtual = {p: (args.prototype / p).read_text()
                   for p in [draft['source'], *draft['destinations']]}
        assert not check(draft, current[draft['source']], virtual, args.parser_package)
        modes.append(('provisional materialization; no history claim',
                      manifests + [draft], {**current, **virtual}, draft))
    results = []
    for label, sequence, source, future in modes:
        for contract in config['contracts']:
            identity = '_VideoPlayerScreenState.' + contract['declaration']
            text, response = projected(identity, sequence, source, args.parser_package, future)
            found = failures(contract, text)
            assert not found, (label, contract['name'], found)
            deletions = 0
            for anchor in contract['anchors']:
                changed = text.replace(anchor, ' P16_DELETED_ANCHOR ')
                assert any(e == 'missing anchor: ' + anchor for e in failures(contract, changed))
                deletions += 1
            reorders = 0
            for first, second in contract.get('ordered', []):
                # VALID token snippets at both sites; require the explicit order
                # diagnostic even when other contracts also notice the change.
                changed = text.replace(first, ' P16_SWAP_FIRST ', 1).replace(second, first, 1).replace(' P16_SWAP_FIRST ', second, 1)
                assert any(e.startswith('missing or reordered anchors:')
                           for e in failures(contract, changed))
                reorders += 1
            results.append(dict(mode=label, contract=contract['name'], path=response['path'],
                                identity=response['declaration'], deletion_negatives=deletions,
                                reorder_negatives=reorders, status='PASS'))
    args.output.write_text(json.dumps(dict(status='PASS', results=results), indent=2) + '\n')
    print('PASS:', len(results), 'reader contracts with independent removal/order negatives')


if __name__ == '__main__':
    main()
