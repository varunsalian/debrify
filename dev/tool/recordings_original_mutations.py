#!/usr/bin/env python3
"""Whole-file assertion proofs on the owned untouched-R scratch worktree.

Test/fixture bytes are frozen for each run. B, S and the inert-listener probe
have separate reports; a parser, compile, timeout or load failure is never B.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

from check_verbatim_moves import parse
from stremio_tv_tuner_original_mutations import assertions
from suite_evidence import evidence_dir, outcomes

ROOT = Path(__file__).resolve().parents[2]
FACADE = 'lib/screens/settings/recordings_page.dart'
TESTS = 'test/features/recordings/presentation/'
ORIGINAL = '49c53e2e'


def frozen(root):
    paths = set()
    for pattern in ['test/features/recordings/**/*.dart', 'test/support/recordings_*.dart',
                    'test/goldens/recordings/**/*.png', 'dev/tool/recordings_*.json',
                    'dev/tool/recordings_*.tsv', 'dev/tool/recordings_*.txt']:
        paths.update(root.glob(pattern))
    return {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(paths)}


def mutate(pristine, nodes, case):
    versions = {}
    for edit in case['edits']:
        member = edit['member']; text = versions.get(member, nodes[member]['text'])
        before = edit['before']; count = edit.get('count', 1)
        assert text.count(before) == count, (case['label'], member, before, text.count(before))
        replacement = text.replace(before, edit['after'], count)
        versions[member] = replacement
    changed = pristine
    for member, text in sorted(versions.items(), key=lambda item: nodes[item[0]]['start'], reverse=True):
        node = nodes[member]
        changed = changed[:node['start']]+text+changed[node['end']:]
    return changed


def run_suite(command, root, notes):
    for attempt in range(3):
        result = subprocess.run(command, cwd=root, capture_output=True, text=True)
        print(result.stdout, end='', flush=True)
        if result.returncode == 0: return
        # Concurrent worktrees occasionally contend while capturing provenance.
        # Retry that infrastructure failure only; never retry a mutant verdict.
        if "'git', 'stash', 'create'" not in result.stderr:
            raise RuntimeError(result.stderr)
        with notes.open('a') as log:
            log.write(json.dumps(dict(command=command, attempt=attempt,
                                      note='git snapshot contention', stderr=result.stderr))+'\n')
    raise RuntimeError(result.stderr)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--original-worktree', required=True, type=Path)
    p.add_argument('--parser-package', required=True, type=Path)
    p.add_argument('--positive', default='recordings/step0-original-characterization')
    p.add_argument('--kind', choices=['B', 'S', 'probe'], required=True)
    p.add_argument('--only')
    p.add_argument('--start', type=int, default=0)
    a = p.parse_args(); root = a.original_worktree.resolve()
    assert root == ROOT / '.dart_tool/recordings_original'
    git = lambda *args: subprocess.check_output(['git', *args], cwd=root, text=True).strip()
    revision = git('rev-parse', 'HEAD'); assert revision == git('rev-parse', ORIGINAL)
    pristine = (root / FACADE).read_text()
    assert pristine == subprocess.check_output(['git', 'show', ORIGINAL+':'+FACADE], cwd=root, text=True)
    unit = parse({FACADE: pristine}, a.parser_package.resolve())[FACADE]
    nodes = {d['name']: d for d in unit['declarations']}
    nodes.update({d['name']+'.'+m['name']: m for d in unit['declarations'] for m in d['members']})
    cases = json.loads((ROOT/'dev/tool/recordings_original_mutations.json').read_text())
    cases = [c for c in cases if c['kind'] == a.kind]
    e = evidence_dir(); positive = outcomes(e/(a.positive+'.jsonl'))[0]
    positive_env = json.loads((e/(a.positive+'.env.json')).read_text())
    assert not positive_env['tree_changed_during_run']
    assert all(v == 'success' for v in positive.values()), positive
    snapshot = frozen(root)
    report = e/f'recordings/original-{a.kind}-mutations.json'
    results = json.loads(report.read_text())['results'] if (a.only or a.start) and report.exists() else []
    for index, case in enumerate(cases):
        if index < a.start or (a.only and a.only not in case['label']): continue
        changed = mutate(pristine, nodes, case)
        label = f'recordings/mutations/{a.kind}-{index:02d}-{case["label"]}'
        try:
            (root/FACADE).write_text(changed)
            command = ['python3', 'dev/tool/suite_evidence.py', 'run', label,
                       *[TESTS+t+'_test.dart' for t in case['tests']],
                       '--no-pub', '--concurrency=1']
            run_suite(command, root, e/'recordings/git-snapshot-retry-notes.jsonl')
            path = e/(label+'.jsonl'); actual = outcomes(path)[0]
            expected = {k for k in positive if k.split('::')[0] in {TESTS+t+'_test.dart' for t in case['tests']}
                        and any(fragment in k for fragment in case['must_fail'])}
            assert expected, case['label']
            failed = {k for k,v in actual.items() if v in ['failure','error']}
            rejected = assertions(path) & expected
            reasons = case.get('assertion_reasons', [])
            assertion_events = [event for line in path.read_text().splitlines()
                                if isinstance(event:=json.loads(line),dict) and event.get('type') in ['print','error']
                                and 'Expected:' in event.get('error',event.get('message',''))]
            text = json.dumps(assertion_events)
            killed = expected <= rejected and all(reason in text for reason in reasons)
            env = json.loads(path.with_suffix('.env.json').read_text())
            assert not env['tree_changed_during_run']
            assert frozen(root) == snapshot, 'test/fixture bytes changed'
            result = dict(label=case['label'], kind=a.kind, killed_by_named_assertion=killed,
                          expected=sorted(expected), assertions=sorted(rejected),
                          other_failures=sorted(failed-rejected), reason=case.get('reason'),
                          command=command, evidence=label, original_revision=revision,
                          mutated_sha256=hashlib.sha256(changed.encode()).hexdigest(),
                          assertion_details=assertion_events)
            results = [r for r in results if r['label'] != case['label']]+[result]
            report.write_text(json.dumps(dict(original_revision=revision, positive=a.positive,
                fixture_sha256=snapshot, results=results,
                survivors=[r['label'] for r in results if not r['killed_by_named_assertion']]), indent=2)+'\n')
            print(('KILLED ' if killed else 'SURVIVED ')+a.kind+' '+case['label'], flush=True)
        finally:
            (root/FACADE).write_text(pristine)
    assert (root/FACADE).read_text() == pristine
    survivors = [r['label'] for r in results if not r['killed_by_named_assertion']]
    print(f'{a.kind}: {len(results)-len(survivors)}/{len(results)} named assertion rejections; survivors {survivors}')
    if a.kind != 'probe': assert not survivors, survivors


if __name__ == '__main__': main()
