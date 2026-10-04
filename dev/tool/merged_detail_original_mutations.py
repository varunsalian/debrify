#!/usr/bin/env python3
"""Execute guard-specific production mutations in the owned original worktree.

Never edits the active facade or accepts changed masters. Each negative records
its tested tree, requires an assertion failure at an existing positive identity,
and restores every production file in a finally block.
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

FACADE = 'lib/screens/merged_series_detail_screen.dart'
TESTS = 'test/features/merged_detail/presentation/legacy_merged_detail/'
ORIGINAL = '21320ff9264fb7b1072b7682665058982a763dec'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--original-worktree', type=Path, required=True)
    parser.add_argument('--parser-package', type=Path, required=True)
    parser.add_argument('--only')
    parser.add_argument('--start',type=int,default=0)
    args = parser.parse_args()
    original = args.original_worktree.resolve()
    assert original == ROOT / '.dart_tool/merged_detail_original'
    revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=original, text=True).strip()
    assert revision == ORIGINAL
    pristine = (original / FACADE).read_text()
    ast = parse({FACADE: pristine}, args.parser_package.resolve())
    state = next(n for n in ast[FACADE]['declarations'] if n['name'] == '_MergedDetailScreenState')
    nodes = {n['name']: n for n in state['members']}
    cases = json.loads((ROOT / 'dev/tool/merged_detail_original_mutations.json').read_text())
    positive, _ = outcomes(evidence_dir() / 'merged_detail/original-characterization-final4.jsonl')
    retention, _ = outcomes(evidence_dir() / 'merged_detail/original-metadata-retention2.jsonl')
    positive.update(retention)
    assert set(positive.values()) == {'success'}
    covered = set()
    results = []
    if args.start or args.only:
        results=json.loads((evidence_dir()/'merged_detail/original-mutations-progress.json').read_text())
        covered=set().union(*(set(r['rejected_by']) for r in results))
    for index, case in enumerate(cases):
        if index < args.start or (args.only and args.only not in case['label']):
            continue
        changes = {FACADE: pristine}
        if case.get('source_guards'):
            frozen = json.loads((original / 'dev/tool/merged_detail_source_contracts.json').read_text())
            for name in frozen:
                node = nodes[name]
                body_start = node['bodyOffset'] - node['start']
                if node['text'][body_start:].startswith('=>'):
                    position = body_start + 2
                else:
                    position = node['text'].index('{', body_start) + 1
                changed = node['text'][:position] + ' /* original mutation */ ' + node['text'][position:]
                changes[FACADE] = changes[FACADE].replace(node['text'], changed, 1)
            for name in ('_style', '_focusCoordinator', '_bodySpec'):
                node = nodes[name]
                changed = node['text'].replace(';', ' /* original mutation */ ;', 1)
                changes[FACADE] = changes[FACADE].replace(node['text'], changed, 1)
            changes[FACADE] = changes[FACADE].replace('/// Merged series page (experimental,', '/// Mutated merged series page (experimental,', 1)
            changes[FACADE] = changes[FACADE].replace('  void _browsePrimarySources()', '  /* separated original declarations */\n  void _browsePrimarySources()', 1)
            changes[FACADE] += '\n// SeriesSourceFetcher mergeSources\n'
            xtream = 'lib/screens/iptv/xtream_series_detail.dart'
            changes[xtream] = (original / xtream).read_text().replace(
                'settings: const RouteSettings(name: kCatalogDetailRouteName)',
                "settings: const RouteSettings(name: 'mutated-merged-route')", 1)
        member_versions = {}
        for edit in case.get('edits', []):
            path = edit.get('file', FACADE)
            changes.setdefault(path, (original / path).read_text())
            before = changes[path]
            if 'member' in edit:
                text = member_versions.get(edit['member'], nodes[edit['member']]['text'])
                assert before.count(text) == 1, edit
                assert text.count(edit['before']) == edit.get('count', 1), edit
                replacement = text.replace(edit['before'], edit['after'])
                changes[path] = before.replace(text, replacement, 1)
                member_versions[edit['member']] = replacement
            else:
                assert before.count(edit['before']) == edit.get('count', 1), edit
                changes[path] = before.replace(edit['before'], edit['after'])
        saved = {path: (original / path).read_bytes() for path in changes}
        label = f'merged_detail/original-negative-{index:02d}-{case["label"]}'
        try:
            for path, text in changes.items():
                (original / path).write_text(text)
            command = ['python3', 'dev/tool/suite_evidence.py', 'run', label,
                       *[TESTS + name + '.dart' for name in case['tests']], '--timeout', '30s']
            if case.get('plain_name'):
                command += ['--plain-name', case['plain_name']]
            subprocess.run(command, cwd=original, check=True)
            actual, _ = outcomes(evidence_dir() / (label + '.jsonl'))
            failed = {key for key, value in actual.items() if value in ('failure', 'error')}
            assert failed, 'Mutation accepted: ' + case['label']
            assert failed <= set(positive), 'Compilation/loading failure: ' + str(failed - set(positive))
            expected = {key for key in positive if key.split('::')[0] in {TESTS + name + '.dart' for name in case['tests']} and any(fragment in key for fragment in case['must_fail'])}
            assert expected and expected <= failed, f'{case["label"]}: not rejected by {sorted(expected - failed)}'
            env = json.loads((evidence_dir() / (label + '.env.json')).read_text())
            assert not env['tree_changed_during_run'], case['label']
            covered |= failed
            result = {'label': label, 'expected': sorted(expected), 'rejected_by': sorted(failed),
                      'original_revision': revision, 'execution_base': 'def4e30423c9d8344eeb340c665afc2ee866c11f',
                      'production_sha256': {path: hashlib.sha256(text.encode()).hexdigest() for path, text in changes.items()},
                      'tested_tree': env['tested_tree']}
            results=[r for r in results if r['label']!=label]
            results.append(result)
            covered=set().union(*(set(r['rejected_by']) for r in results))
            (evidence_dir() / 'merged_detail/original-mutations-progress.json').write_text(json.dumps(results, indent=2) + '\n')
            print('PASS ' + case['label'], flush=True)
        finally:
            for path, data in saved.items():
                (original / path).write_bytes(data)
        assert (original / FACADE).read_text() == pristine
    output = evidence_dir() / 'merged_detail/original-mutations.json'
    output.write_text(json.dumps({'original_revision': revision, 'results': results,
                                  'covered': sorted(covered), 'uncovered': sorted(set(positive) - covered)}, indent=2) + '\n')
    print(f'{len(results)} production mutations rejected; {len(covered)}/{len(positive)} original guard identities exercised')


if __name__ == '__main__':
    main()
