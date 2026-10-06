#!/usr/bin/env python3
"""Named-assertion ORIGINAL proofs using the tuner's mutation/evidence procedure.

Only the owned detached checkpoint is mutated; every byte is restored in finally.
Source-only cases run the real source reader and record their observable limit.
"""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path
from check_verbatim_moves import ROOT, ensure_parser_package, parse
import suite_evidence as suite

SOURCE = 'lib/screens/settings/iptv_settings_two_pane.dart'
CHECKPOINT = '7e7006062094559cdf0f33c64216066c8c5dfaf1'
TESTS = 'test/features/iptv_settings_two_pane/presentation/legacy_iptv_settings_two_pane/'


def assertion_failures(path):
    tests, suites, failed = {}, {}, set()
    root = json.loads(path.with_suffix('.env.json').read_text())['root']
    for line in path.read_text().splitlines():
        try:
            event = json.loads(line)
        except ValueError:
            continue
        if event.get('type') == 'suite':
            value = event['suite']
            suites[value['id']] = value['path'].removeprefix(root + '/')
        elif event.get('type') == 'testStart':
            value = event['test']
            tests[value['id']] = suites[value['suiteID']] + '::' + value['name']
        elif event.get('type') in ('error', 'print'):
            message = event.get('error', event.get('message', ''))
            if 'Expected:' in message:
                failed.add(tests[event['testID']])
    return failed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--original-worktree', type=Path, required=True)
    parser.add_argument('--parser-package', type=Path, required=True)
    parser.add_argument('--only')
    args = parser.parse_args()
    original = args.original_worktree.resolve()
    assert original == ROOT / '.dart_tool/iptv_settings_two_pane_original_step0b'
    assert subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=original, text=True).strip() == CHECKPOINT
    pristine = subprocess.check_output(['git', 'show', CHECKPOINT + ':' + SOURCE], cwd=original, text=True)
    assert (original / SOURCE).read_text() == pristine
    package = args.parser_package.resolve()
    assert package.is_relative_to(ROOT / '.dart_tool')
    ensure_parser_package(package.parent.parent, package)
    ast = parse({SOURCE: pristine}, package)[SOURCE]
    nodes = {}
    for declaration in ast['declarations']:
        nodes[declaration['name']] = declaration
        for member in declaration.get('members', []):
            nodes[declaration['name'] + '.' + member['name']] = member
    evidence = suite.evidence_dir() / 'iptv_settings_two_pane'
    positive_path = evidence / 'step0b-original-positive.jsonl'
    positive = suite.outcomes(positive_path)[0]
    positive_env = json.loads(positive_path.with_suffix('.env.json').read_text())
    assert not positive_env['tree_changed_during_run']
    assert set(positive.values()) == {'success'}
    cases = json.loads((ROOT / 'dev/tool/iptv_settings_two_pane_original_mutations.json').read_text())
    progress = evidence / 'step0b-mutations.json'
    results = json.loads(progress.read_text()) if args.only and progress.exists() else []
    fixture_hashes = {p.relative_to(original).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                      for p in (original / 'test/goldens/iptv_settings_two_pane').rglob('*.png')}
    suite.ROOT = original
    for case in cases:
        if args.only and args.only != case['label']:
            continue
        changed = pristine
        for edit in case['edits']:
            node = nodes[edit['member']]
            text = node['text']
            assert text.count(edit['before']) == edit.get('count', 1), case['label']
            assert changed.count(text) == 1
            changed = changed.replace(text, text.replace(edit['before'], edit['after']), 1)
        prefix = evidence / ('step0b-negative-' + case['label'])
        try:
            (original / SOURCE).write_text(changed)
            env = suite.flutter_env([])
            if case.get('source_guard_only'):
                command = ['python3', 'dev/tool/iptv_settings_two_pane_source_reader.py', '--json',
                           '--parser-package', str(package)]
                result = subprocess.run(command, cwd=original, text=True, capture_output=True)
                prefix.with_suffix('.txt').write_text(result.stdout + result.stderr)
                assert result.returncode != 0
                assert case['edits'][0]['member'] in result.stderr, result.stderr
                assert 'ValueError:' in result.stderr, result.stderr
                rejected = ['source reader: ' + case['edits'][0]['member']]
                env['command'] = command
            else:
                flags = ['--no-pub', '--concurrency=1', '--timeout=3m',
                         '--plain-name=' + case['must_fail'], TESTS + case['test']]
                env = suite.flutter_env(flags)
                prefix.with_suffix('.env.json').write_text(json.dumps(env, indent=2) + '\n')
                code = suite.flutter_test_json(flags, prefix.with_suffix('.jsonl'))
                actual = suite.outcomes(prefix.with_suffix('.jsonl'))[0]
                failed = {k for k, value in actual.items() if value in ('failure', 'error')}
                assert code != 0 and failed and failed <= set(positive), (case['label'], actual)
                asserted = assertion_failures(prefix.with_suffix('.jsonl'))
                expected = {k for k in positive if case['must_fail'] in k}
                assert expected and expected <= asserted, (case['label'], expected - asserted)
                if case.get('assertion_reason'):
                    assert case['assertion_reason'] in prefix.with_suffix('.jsonl').read_text(), case['label']
                rejected = sorted(asserted)
                env['exit_code'] = code
            end = suite.git_tree_evidence()
            env.update(end_head=end['head'], end_tree=end['tested_tree'],
                       tree_changed_during_run=env['tested_tree'] != end['tested_tree'])
            assert not env['tree_changed_during_run']
            prefix.with_suffix('.env.json').write_text(json.dumps(env, indent=2) + '\n')
            assert fixture_hashes == {p.relative_to(original).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                                      for p in (original / 'test/goldens/iptv_settings_two_pane').rglob('*.png')}
            results = [r for r in results if r['label'] != case['label']]
            results.append({'label': case['label'], 'rejected_by': rejected,
                            'assertion_reason': case.get('assertion_reason'),
                            'source_guard_only': case.get('source_guard_only'),
                            'original_revision': CHECKPOINT, 'tested_tree': env['tested_tree'],
                            'production_sha256': hashlib.sha256(changed.encode()).hexdigest()})
            progress.write_text(json.dumps(results, indent=2) + '\n')
            print('PASS ' + case['label'], flush=True)
        finally:
            (original / SOURCE).write_text(pristine)
        assert (original / SOURCE).read_text() == pristine
    if not args.only:
        assert len(results) == len(cases)
    print(str(len(results)) + ' original mutations rejected')


if __name__ == '__main__':
    main()
