#!/usr/bin/env python3
"""Assertion-based original-code negatives; never changes the active facade.

Run against the owned detached original and restore every mutated byte in finally.
The positive snapshot includes all tracked fixtures, contracts and original pixels.
"""
import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'dev/tool'))
from check_verbatim_moves import parse
from suite_evidence import evidence_dir, outcomes

FACADE = 'lib/screens/catalog_item_detail_screen.dart'
TESTS = 'test/features/catalog_detail/presentation/legacy_catalog_detail/'
ORIGINAL = 'adc2e32e7127fb5109de14afa74c0daecfa4c184'
EXECUTION_BASE = '881ed25073c9cac0f80c5ae650118a9bcdcb4d41'


def assertions(path):
    suites, tests, failed = {}, {}, set()
    root = json.loads(path.with_suffix('.env.json').read_text())['root']
    for line in path.read_text().splitlines():
        try:
            e = json.loads(line)
        except ValueError:
            continue
        if e.get('type') == 'suite':
            suites[e['suite']['id']] = e['suite']['path'].removeprefix(root + '/')
        elif e.get('type') == 'testStart':
            t = e['test']
            tests[t['id']] = suites[t['suiteID']] + '::' + t['name']
        elif e.get('type') == 'error' and 'Expected:' in e.get('error', ''):
            failed.add(tests[e['testID']])
        elif e.get('type') == 'print' and 'Expected:' in e.get('message', ''):
            failed.add(tests[e['testID']])
    return failed


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--original-worktree', type=Path, required=True)
    p.add_argument('--parser-package', type=Path, required=True)
    p.add_argument('--positive', default='catalog_detail/original-characterization-final')
    p.add_argument('--start', type=int, default=0)
    p.add_argument('--only')
    a = p.parse_args()
    original = a.original_worktree.resolve()
    assert original == ROOT / '.dart_tool/catalog_detail_original'
    revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=original, text=True).strip()
    assert revision == ORIGINAL
    pristine = (original / FACADE).read_text()
    expected = subprocess.check_output(['git', 'show', ORIGINAL + ':' + FACADE], cwd=original, text=True)
    assert pristine == expected
    ast = parse({FACADE: pristine}, a.parser_package.resolve())
    nodes = {}
    for declaration in ast[FACADE]['declarations']:
        nodes[declaration['name']] = declaration
        for member in declaration.get('members', []):
            nodes[declaration['name'] + '.' + member['name']] = member
    cases = json.loads((ROOT / 'dev/tool/catalog_detail_original_mutations.json').read_text())
    evidence = evidence_dir()
    positive = outcomes(evidence / (a.positive + '.jsonl'))[0]
    positive = {k: v for k, v in positive.items() if k.split('::')[0].startswith(TESTS)}
    assert set(positive.values()) == {'success'}
    positive_env = json.loads((evidence / (a.positive + '.env.json')).read_text())
    assert not positive_env['tree_changed_during_run'] and not positive_env['untracked_paths']
    progress = evidence / 'catalog_detail/original-mutations-progress.json'
    results = json.loads(progress.read_text()) if (a.start or a.only) and progress.exists() else []
    fixture_paths = sorted((original / 'test/goldens/catalog_detail').rglob('*.png'))
    fixture_hashes = {str(f.relative_to(original)): hashlib.sha256(f.read_bytes()).hexdigest() for f in fixture_paths}
    for index, case in enumerate(cases):
        if index < a.start or (a.only and a.only not in case['label']):
            continue
        changed = pristine
        versions = {}
        if case.get('source_guards'):
            for name in json.loads((original / 'dev/tool/catalog_detail_source_contracts.json').read_text()):
                node = nodes['_CatalogItemDetailScreenState.' + name]
                position = node['bodyOffset'] - node['start']
                position = position + 2 if node['text'][position:].startswith('=>') else node['text'].index('{', position) + 1
                replacement = node['text'][:position] + ' /* original mutation */ ' + node['text'][position:]
                changed = changed.replace(node['text'], replacement, 1)
        for edit in case.get('edits', []):
            member = edit.get('member')
            text = versions.get(member, nodes[member]['text']) if member else changed
            assert text.count(edit['before']) == edit.get('count', 1), (case['label'], edit)
            replacement = text.replace(edit['before'], edit['after'])
            if member:
                assert changed.count(text) == 1
                changed = changed.replace(text, replacement, 1)
                versions[member] = replacement
            else:
                changed = replacement
        label = f'catalog_detail/original-negative-{index:02d}-{case["label"]}'
        try:
            (original / FACADE).write_text(changed)
            command = ['python3', 'dev/tool/suite_evidence.py', 'run', label,
                       *[TESTS + name + '_test.dart' for name in case['tests']], '--no-pub', '--timeout=30s']
            if case.get('plain_name'):
                command += ['--plain-name=' + case['plain_name']]
            subprocess.run(command, cwd=original, check=True)
            path = evidence / (label + '.jsonl')
            actual = outcomes(path)[0]
            failed = {k for k, v in actual.items() if v in ('failure', 'error')}
            assert failed and failed <= set(positive), 'Compile/load failure or accepted mutation: ' + case['label']
            rejected = failed & assertions(path)
            expected_failures = {k for k in positive if k.split('::')[0] in {TESTS + name + '_test.dart' for name in case['tests']} and any(fragment in k for fragment in case['must_fail'])}
            assert expected_failures and expected_failures <= rejected, (case['label'], sorted(expected_failures - rejected))
            env = json.loads(path.with_suffix('.env.json').read_text())
            assert not env['tree_changed_during_run']
            assert fixture_hashes == {str(f.relative_to(original)): hashlib.sha256(f.read_bytes()).hexdigest() for f in fixture_paths}
            results = [r for r in results if r['label'] != label]
            results.append({'label': label, 'expected': sorted(expected_failures), 'rejected_by': sorted(rejected),
                            'other_failures': sorted(failed - rejected), 'original_revision': revision,
                            'execution_base': EXECUTION_BASE, 'tested_tree': env['tested_tree'],
                            'production_sha256': hashlib.sha256(changed.encode()).hexdigest()})
            progress.write_text(json.dumps(results, indent=2) + '\n')
            print('PASS ' + case['label'], flush=True)
        finally:
            (original / FACADE).write_text(pristine)
        assert (original / FACADE).read_text() == expected
    covered = set().union(*(set(r['rejected_by']) for r in results))
    output = {'original_revision': revision, 'execution_base': EXECUTION_BASE,
              'positive': a.positive, 'positive_tested_tree': positive_env['tested_tree'],
              'fixture_sha256': fixture_hashes, 'results': results,
              'covered': sorted(covered), 'uncovered': sorted(set(positive) - covered)}
    (evidence / 'catalog_detail/original-mutations.json').write_text(json.dumps(output, indent=2) + '\n')
    print(f'{len(results)} mutations rejected; {len(covered)}/{len(positive)} original test identities exercised')
    assert not output['uncovered'], output['uncovered']


if __name__ == '__main__':
    main()
