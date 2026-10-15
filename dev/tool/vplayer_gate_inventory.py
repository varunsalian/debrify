#!/usr/bin/env python3
"""Require every frozen reduced-gate suite to load before outcome comparison."""
import argparse
import json
from pathlib import Path

from suite_evidence import ROOT, outcomes, cmd_compare


def validate(inventory, log, root=ROOT):
    expected = set(inventory['files'])
    if len(expected) != len(inventory['files']):
        return ['duplicate suite in frozen inventory']
    discovered = {p.relative_to(root).as_posix()
                  for p in (root / 'test/features/video_player').rglob('*_test.dart')}
    errors = []
    if discovered != {p for p in expected if p.startswith('test/features/video_player/')}:
        errors.append('video-player suite inventory drift')
    try:
        _, loaded = outcomes(log)
    except AssertionError as error:
        return errors + [str(error)]
    if expected != loaded:
        errors.append('missing/unexpected suites: ' + repr((sorted(expected - loaded), sorted(loaded - expected))))
    suites, loading, finished = {}, {}, {}
    for line in Path(log).read_text().splitlines():
        try:
            event = json.loads(line)
        except ValueError:
            continue
        if event.get('type') == 'suite':
            suites[event['suite']['id']] = event['suite']['path']
        elif event.get('type') == 'testStart' and event['test']['name'].startswith('loading '):
            loading[event['test']['id']] = event['test']['suiteID']
        elif event.get('type') == 'testDone':
            finished[event['testID']] = event['result']
    for test, suite in loading.items():
        if finished.get(test) != 'success':
            errors.append('suite did not load: ' + suites[suite])
    if len(loading) != len(expected):
        errors.append('missing suite-load outcomes')
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inventory', type=Path, required=True)
    parser.add_argument('--run', type=Path, required=True)
    parser.add_argument('--against', type=Path)
    args = parser.parse_args()
    inventory = json.loads(args.inventory.read_text())
    errors = validate(inventory, args.run)
    if args.against:
        errors += ['baseline: ' + error for error in validate(inventory, args.against)]
    for error in errors:
        print(error)
    if errors:
        return 1
    print('PASS: every frozen suite loaded')
    return cmd_compare(['--against', str(args.against), str(args.run)]) if args.against else 0


if __name__ == '__main__':
    raise SystemExit(main())
