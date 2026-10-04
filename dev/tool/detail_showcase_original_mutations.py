#!/usr/bin/env python3
"""Run assertion-producing mutations only in an owned ORIGINAL-code worktree."""
import argparse
import hashlib
import json
import subprocess
import shutil
import re
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
    layout = root / 'lib/widgets/detail/detail_layout_showcase.dart'
    failure_dir = root / 'test/features/detail_showcase/presentation/failures'
    assert not failure_dir.exists(), 'Original proof input must not contain old pixel failure artifacts'
    original = source.read_text()
    assert 'class ShowcaseIdentity' in original and 'class _PrimaryState' in original
    assert not (root / 'lib/features/detail_showcase').exists()
    assert not git('diff','--name-only','--','lib','test'), 'Proof must start on committed original application/tests'
    evidence.mkdir(parents=True, exist_ok=True)
    cases = []
    def case(label, test_file, test_name, replacements, file=source, declaration=None):
        cases.append((label, test_file, test_name, replacements, file, declaration))
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
    case('guide-select-dropped',guide,'guide card Select toggles', [('onKeyEvent: (_, e) => _activate(e, widget.onOk),','onKeyEvent: (_, e) => _activate(e, null),')])
    case('recommendation-pointer-dropped',bands,'recommendation pointer and Select', [('onTap: () => widget.onTap?.call(widget.item),','onTap: null,')],declaration='_PosterState')
    case('recommendation-select-dropped',bands,'recommendation pointer and Select', [('onKeyEvent: (_, e) => _activate(e, () => widget.onTap?.call(widget.item)),','onKeyEvent: (_, e) => _activate(e, null),')],declaration='_PosterState')
    identity = 'showcase_identity_actions_test.dart'
    explore_start = original.index('    if (m.onMetadataExplore != null && i < actionNodes.length)')
    more_start = original.index('    if (m.onAppMenu != null && i < actionNodes.length)',explore_start)
    actions_end = original.index('\n\n    // A FIRST SCREENFUL',more_start)
    explore = original[explore_start:more_start]
    more = original[more_start:actions_end]
    case('identity-explore-more-swapped',identity,'identity orders all eight', [(explore+more,more+'\n'+explore.rstrip())])
    case('identity-more-wrong-callback',identity,'identity orders all eight', [('onTap: m.onAppMenu!,','onTap: m.onTrackers!,')])
    case('page-action-count-dropped',identity,'page action count mounts', [('if (m.onAppMenu != null) n++;','if (false) n++;')],file=layout)
    case('primary-focused-dropped',hold,'primary focus dispatches', [('if (v) widget.onFocused();','if (v) {}')],declaration='_PrimaryState')
    case('wide-season-wrong-number',bands,'wide TV season tap', [('onTap: () => view.selectSeason(s.number),','onTap: () => view.selectSeason(view.selectedSeasonNumber),')])
    for name in ['_SourceCard','_GuideCard','_Poster','_UniverseCard','_DykCard','_DykMoreCard']:
        case('hover-lift-dropped-'+name[1:],hover,'hover and focus share the '+name+' lift', [('focused: _f || hovered,','focused: _f,')],declaration=name+'State')
    case('popup-accent-dropped',bands,'compact season popup selected text', [('? AppThemeScope.of(context).core.accent','? Colors.white')],declaration='_SeasonDropdownState')
    case('unknown-severity-guessed',guide,'unknown guide severity', [("'severe' => 4,\n  _ => 0,","'severe' => 4,\n  _ => 4,")])
    case('empty-guide-guard-dropped',guide,'empty guide mounts', [('if (_cats.isEmpty) return const SizedBox.shrink();','// Deliberate original mutation: empty guard removed.')])
    case('ambient-fade-duration-changed',source_test,'topology literals and cache and fade', [('duration: const Duration(milliseconds: 550),','duration: const Duration(milliseconds: 551),')],declaration='ShowcaseAmbient')
    for scene in ['tv_movie','compact_series','wide_series_bands','compact_guide']:
        case('dark-golden-ink-'+scene,'detail_showcase_goldens_test.dart','original pixel golden '+scene,[('const _ink = Color(0xFFFFFFFF);','const _ink = Color(0xFFFF0000);')])
    results = []
    for label, test_file, test_name, replacements, file, declaration in cases:
        before = file.read_text()
        start, end = 0, len(before)
        if declaration:
            match = re.search(r'^class '+re.escape(declaration)+r'\b',before,re.M)
            assert match, 'Missing original declaration: '+declaration
            start = match.start()
            next_class = re.search(r'^class ',before[match.end():],re.M)
            end = match.end()+next_class.start() if next_class else len(before)
        changed = before[start:end]
        for old, new in replacements:
            assert old in changed, 'No-op original mutation: ' + label
            changed = changed.replace(old,new,1 if label not in ['hold-routed-to-primary'] else -1)
        mutated = before[:start]+changed+before[end:]
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
            proof_class = 'S' if label in ['lazy-hold','dispose-order','lost-original-declaration','namespace-changed','completion-topology-on-original','ambient-fade-duration-changed'] else ('pixel' if 'golden' in label or label=='visible-guide-radius' else 'widget')
            results.append(dict(name=label,test=test_file,proof_class=proof_class,mutated_file=str(file.relative_to(root)),original_file_sha256=hashlib.sha256(before.encode()).hexdigest(),assertion_failures=failures,exit_code=None if reused else code,sha256=hashlib.sha256(mutated.encode()).hexdigest(),compilation_error=False,reused_assertion_log=reused,log_sha256=hashlib.sha256(out.read_bytes()).hexdigest()))
            print(label+': assertion rejected',flush=True)
        finally:
            file.write_text(before)
            assert file.read_text()==before
            if failure_dir.exists():
                destination = evidence/'golden-mutation-failures'/label
                destination.parent.mkdir(exist_ok=True)
                assert not destination.exists(), 'Retain earlier pixel proof instead of overwriting: '+label
                shutil.move(str(failure_dir),str(destination))
            assert not failure_dir.exists()
    assert source.read_text() == original
    assert not failure_dir.exists()
    assert not git('status','--porcelain'), 'Restored proof tree must be clean'
    result = dict(checkpoint=git('rev-parse','HEAD'),lib=git('rev-parse','HEAD:lib'),test=git('rev-parse','HEAD:test'),original_source_sha256=hashlib.sha256(original.encode()).hexdigest(),mutation_runner_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),cases=results,restored=True)
    (evidence/'step0b-original-mutations.json').write_text(json.dumps(result,indent=2)+'\n')


if __name__ == '__main__':
    main()
