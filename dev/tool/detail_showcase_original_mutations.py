#!/usr/bin/env python3
"""Run assertion-producing mutations only in an owned ORIGINAL-code worktree."""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--worktree', type=Path, required=True)
    parser.add_argument('--checkpoint', required=True)
    parser.add_argument('--evidence', type=Path, required=True)
    parser.add_argument('--only', nargs='*', help='Rerun named cases; validate retained assertion logs for other cases')
    args = parser.parse_args()
    root = args.worktree.resolve()
    evidence = args.evidence.resolve()
    assert root.name == 'detail_showcase_original' and '.dart_tool' in root.parts
    def git(*values):
        return subprocess.check_output(['git', *values], cwd=root, text=True).strip()
    assert git('rev-parse','HEAD') == git('rev-parse',args.checkpoint)
    source = root / 'lib/widgets/detail/showcase_parts.dart'
    architecture = root / 'dev/tool/check_search_architecture.py'
    original = source.read_text()
    assert 'class ShowcaseIdentity' in original and 'class _PrimaryState' in original
    assert not (root / 'lib/features/detail_showcase').exists()
    evidence.mkdir(parents=True, exist_ok=True)
    cases = []
    def case(label, test_file, test_name, replacements, file=source):
        cases.append((label, test_file, test_name, replacements, file))
    prefix = 'test/features/detail_showcase/presentation/'
    source_test = 'detail_showcase_source_contract_test.dart'
    hold = 'showcase_primary_hold_test.dart'
    guide = 'showcase_guide_update_test.dart'
    hover = 'showcase_hover_focus_test.dart'
    bands = 'showcase_band_contracts_test.dart'
    case('lazy-hold',source_test,'primary eagerly owns hold',[
        ('late final TvHoldOk _hold;', 'late final TvHoldOk _hold = TvHoldOk(onTap: () => widget.onTap(), onHold: () => widget.onLongPress?.call());'),
        ('    _hold = TvHoldOk(\n      onTap: () => widget.onTap(),\n      onHold: () => widget.onLongPress?.call(),\n    );', '')])
    case('dispose-order',source_test,'primary eagerly owns hold', [('_hold.reset();\n    super.dispose();','super.dispose();\n    _hold.reset();')])
    case('hold-routed-to-primary',hold,'OK activates once and a 600 ms hold', [('onLongPress: m.onPrimaryLongPress,','onLongPress: m.onPrimary,')])
    case('trailer-double-fire',hold,'trailer mounts only when available', [('onTap: m.onTrailer,','onTap: () { m.onTrailer(); m.onTrailer(); },')])
    case('guide-identical-dropped',guide,'same guide retains selected category', [('!identical(oldWidget.guide, widget.guide)','true')])
    case('guide-selection-not-reseated',guide,'new guide re-seats selection', [('_sel = focused >= 0 ? focused.clamp(0, _cats.length - 1) : 0;','_sel = 0;')])
    case('hover-TV-ungated',hover,'Hover gates MouseRegion on television true', [('if (PlatformUtil.isTelevision) return widget.builder(context, false);','if (false) return widget.builder(context, false);')])
    case('visibility-axis-dropped',hover,'identity circles retain their MouseRegion', [('if (scrollable.position.axis != Axis.horizontal) return;','// Deliberate original-only mutation: axis guard removed.')])
    case('sources-browse-term-dropped',bands,'sources browse term mounts', [('itemCount: 2 + (onBrowseAll != null ? 1 : 0),','itemCount: 2,')])
    case('metrics-k-always-one',bands,'wide touch scale and scope notification', [('double get k => (compact || !touch) ? 1.0 : wideTouchScale(w);','double get k => 1.0;')])
    case('visible-guide-radius', 'detail_showcase_goldens_test.dart','original pixel golden wide_series_bands', [('border: Border.all(color: _ink.withValues(alpha: 0.07)),\n        borderRadius: BorderRadius.circular(10),','border: Border.all(color: _ink.withValues(alpha: 0.07)),\n        borderRadius: BorderRadius.circular(30),')])
    case('lost-original-declaration',source_test,'manifest reader covers every original leaf', [('Color _plateFill(AppTheme app) => Color.lerp(app.home.bg, app.core.tx, 0.10)!;','')])
    case('namespace-changed','detail_showcase_surface_test.dart','facade exported namespace', [('const double kShowcaseGutter = 42;', 'const double kChangedShowcaseGutter = 42;')])
    case('completion-topology-on-original',source_test,'manifest reader covers every original leaf', [('\n','\nDETAIL_SHOWCASE_COMPLETE = True\n')],file=architecture)
    results = []
    for label, test_file, test_name, replacements, file in cases:
        before = file.read_text()
        mutated = before
        for old, new in replacements:
            assert old in mutated, 'No-op original mutation: ' + label
            mutated = mutated.replace(old,new,1 if label not in ['hold-routed-to-primary'] else -1)
        assert mutated != before
        file.write_text(mutated)
        out = evidence / ('original-mutation-' + label + '.jsonl')
        try:
            cmd = ['flutter','test','--no-pub','--reporter','json',prefix+test_file,'--plain-name',test_name]
            reused = bool(args.only and label not in args.only)
            if not reused:
                with out.open('w') as stdout, out.with_suffix('.stderr').open('w') as stderr:
                    code = subprocess.run(cmd,cwd=root,stdout=stdout,stderr=stderr).returncode
            else:
                assert out.exists(), 'Missing retained assertion evidence: ' + label
                code = 1
            events = [json.loads(line) for line in out.read_text().splitlines() if line.startswith('{')]
            assert any(e.get('type') == 'done' and not e.get('success') for e in events), label
            names = {e['test']['id']: e['test']['name'] for e in events if e.get('type')=='testStart'}
            failures = [names[e['testID']] for e in events if e.get('type')=='testDone' and e.get('result') in ('failure','error') and not e.get('hidden')]
            messages = '\n'.join(str(e.get('message',e.get('error',''))) for e in events if e.get('type') in ['print','error'])
            assert code != 0 and failures and all(test_name in n for n in failures), (label, failures, messages[-3000:])
            assert 'Compilation failed' not in messages and 'Failed to load' not in messages, label
            assert 'Expected:' in messages or 'Golden' in messages or 'TestFailure' in messages or 'StateError' in messages, label
            results.append(dict(name=label,test=test_file,assertion_failures=failures,exit_code=None if reused else code,sha256=hashlib.sha256(mutated.encode()).hexdigest(),compilation_error=False,reused_assertion_log=reused,log_sha256=hashlib.sha256(out.read_bytes()).hexdigest()))
            print(label+': assertion rejected',flush=True)
        finally:
            file.write_text(before)
            assert file.read_text()==before
    assert source.read_text() == original
    result = dict(checkpoint=git('rev-parse','HEAD'),lib=git('rev-parse','HEAD:lib'),test=git('rev-parse','HEAD:test'),original_source_sha256=hashlib.sha256(original.encode()).hexdigest(),mutation_runner_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),cases=results,restored=True)
    (evidence/'step0b-original-mutations.json').write_text(json.dumps(result,indent=2)+'\n')


if __name__ == '__main__':
    main()
