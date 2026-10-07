#!/usr/bin/env python3
"""Prove named ORIGINAL assertions in an owned detached checkpoint worktree.

Behavioural cases run no source contracts. Guard-only cases run their named
whole-body assertion. Every mutation is restored, including on failure.
"""
import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CHECKPOINT = '88d98af076f264f0a31373c2d1944a310069f29c'
FACADE = 'lib/widgets/iptv/spotlight/spotlight_live_timeline.dart'
TESTS = 'test/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/'


def events(path):
    result = []
    for line in path.read_text().splitlines():
        try:
            result.append(json.loads(line))
        except ValueError:
            pass
    return result


def named_assertions(log):
    names, failed = {}, {}
    for event in events(log):
        if event.get('type') == 'testStart':
            names[event['test']['id']] = event['test']['name']
        text = event.get('error', '') if event.get('type') == 'error' else event.get('message', '')
        # Flutter's named end-of-test timer assertion is the resource-lifecycle
        # proof for timer-cancellation mutants. Compile/load errors never count.
        timer_assertion = ('A Timer is still pending even after the widget tree was disposed.' in text
                           and "'!timersPending'" in text)
        if ('Expected:' in text or timer_assertion) and event.get('testID') in names:
            failed.setdefault(names[event['testID']], []).append(text)
    return failed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--original-worktree', type=Path, required=True)
    parser.add_argument('--only')
    parser.add_argument('--resume', action='store_true')
    args = parser.parse_args()
    original = args.original_worktree.resolve()
    assert original == ROOT / '.dart_tool/iptv_spotlight_timeline_original'
    assert subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=original, text=True).strip() == CHECKPOINT
    pristine = subprocess.check_output(['git', 'show', CHECKPOINT + ':' + FACADE], cwd=original, text=True)
    assert (original / FACADE).read_text() == pristine
    common = subprocess.check_output(['git', 'rev-parse', '--path-format=absolute', '--git-common-dir'], cwd=ROOT, text=True).strip()
    evidence = Path(common) / 'refactor-evidence/iptv_spotlight_timeline'
    evidence.mkdir(parents=True, exist_ok=True)
    cases = json.loads((ROOT / 'dev/tool/iptv_spotlight_timeline_original_mutations.json').read_text())
    paths = [TESTS + 'iptv_spotlight_timeline_' + name + '_test.dart' for name in
             ['input', 'lifecycle', 'loading', 'paint', 'artwork', 'goldens', 'review', 'source_contracts']]
    paths.append('test/widgets/iptv/spotlight/spotlight_live_timeline_test.dart')
    hashes = {p: hashlib.sha256((original / p).read_bytes()).hexdigest() for p in paths}
    hashes.update({str(p.relative_to(original)): hashlib.sha256(p.read_bytes()).hexdigest()
                   for p in (original / 'test/goldens/iptv_spotlight_timeline').rglob('*.png')})
    progress = evidence / 'step0b-original-mutations.json'
    cases_hash = hashlib.sha256((ROOT / 'dev/tool/iptv_spotlight_timeline_original_mutations.json').read_bytes()).hexdigest()
    previous = json.loads(progress.read_text()) if args.resume and progress.exists() else None
    if previous:
        assert previous['fixture_sha256'] == hashes, 'Resume inputs changed'
        assert previous['cases_sha256'] == cases_hash, 'Resume mutations changed'
    results = previous['results'] if previous else []

    def run(log, name=None, source_only=False):
        selected = [paths[-2]] if source_only else paths[:7] + [paths[-1]]
        if name is None:
            selected = paths
        elif positive.exists():
            # The positive run identifies the suite containing this named test.
            # Filtering eight unrelated suites still compiles each of them.
            suites = {e['suite']['id']: e['suite']['path'] for e in events(positive)
                      if e.get('type') == 'suite'}
            matches = {str(Path(suites[e['test']['suiteID']]).relative_to(original))
                       for e in events(positive) if e.get('type') == 'testStart'
                       and name in e['test']['name'] and e['test']['suiteID'] in suites}
            assert matches and matches.issubset(set(selected)), (name, matches)
            selected = sorted(matches)
        command = ['flutter', 'test', '--no-pub', '--concurrency=1', '--reporter=json', *selected]
        command += ['--plain-name=' + name] if name else ['--name=^(?!real-config checker).*$']
        with log.open('w') as stream:
            status = subprocess.run(command, cwd=original, stdout=stream, stderr=subprocess.STDOUT).returncode
        assert any(e.get('type') == 'done' for e in events(log)), 'Incomplete test run: ' + str(log)
        assert 'TimeoutException' not in log.read_text(), 'Contention timeout: rerun in isolation; do not accept this run'
        return status

    positive = evidence / 'step0b-original-positive.jsonl'
    if not args.resume or not positive.exists():
        assert run(positive) == 0, 'ORIGINAL positive failed'
        assert not named_assertions(positive)
    else:
        assert any(e.get('type') == 'done' and e.get('success') for e in events(positive)), 'Resume positive is incomplete'
        assert not named_assertions(positive)
    for index, case in enumerate(cases):
        if args.only and args.only not in case['label']:
            continue
        if args.resume and any(r['label'] == case['label'] for r in results):
            continue
        before, after = case['before'], case['after']
        occurrence = case.get('occurrence', 0)
        offsets = [m.start() for m in re.finditer(re.escape(before), pristine)]
        assert len(offsets) > occurrence, (case['label'], 'missing exact original text')
        offset = offsets[occurrence]
        changed = pristine[:offset] + after + pristine[offset + len(before):]
        slug = re.sub(r'[^a-z0-9]+', '-', case['label'].lower()).strip('-')
        log = evidence / f'step0b-original-negative-{index:02d}-{slug}.jsonl'
        try:
            (original / FACADE).write_text(changed)
            status = run(log, case['must_fail'], 'source_guard_only' in case)
            assertions = named_assertions(log)
            matching = {n: details for n, details in assertions.items() if case['must_fail'] in n}
            assert status != 0 and matching, (case['label'], 'mutation did not fail its named assertion', str(log))
            assert all(hashlib.sha256((original / p).read_bytes()).hexdigest() == h for p, h in hashes.items())
            row = {'label': case['label'], 'original_revision': CHECKPOINT,
                   'production_sha256': hashlib.sha256(changed.encode()).hexdigest(),
                   'exact_before': before, 'exact_after': after, 'occurrence': occurrence,
                   'source_guard_only': case.get('source_guard_only'),
                   'named_failing_assertions': matching, 'log': log.name, 'exit': status}
            results.append(row)
            progress.write_text(json.dumps({'original_revision': CHECKPOINT,
                'positive_log': positive.name, 'fixture_sha256': hashes,
                'cases_sha256': cases_hash,
                'results': results}, indent=2) + '\n')
            print('PASS ' + case['label'], flush=True)
        finally:
            (original / FACADE).write_text(pristine)
        assert (original / FACADE).read_text() == pristine
    if not args.only:
        assert len(results) == len(cases), (len(results), len(cases))
    print(str(len(results)) + ' named ORIGINAL assertion proofs', flush=True)


if __name__ == '__main__':
    main()
