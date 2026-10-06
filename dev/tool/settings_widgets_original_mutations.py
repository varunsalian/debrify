#!/usr/bin/env python3
"""Step 0b assertion proofs, one mutation at a time on an owned original copy."""
import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path
from check_verbatim_moves import parse
from settings_widgets_probe import SOURCE

PREFIX='test/features/settings_widgets/presentation/'

def digest(text):return hashlib.sha256(text.encode()).hexdigest()

def compilation_error(text):
    return bool(re.search(r'Compilation failed|Failed to load|\.dart:\d+:\d+: Error:', text))

def fixture_test():
    assert compilation_error('lib/example.dart:1:2: Error: invalid declaration')
    assert compilation_error('Compilation failed')
    assert compilation_error('Failed to load test')
    assert not compilation_error('Actual: _TypeError:<Null check operator used on a null value>')
    # A subprocess deadline also bounds this fixture if the quadratic prefix
    # is accidentally restored; a timing assertion alone would hang first.
    script="""from settings_widgets_original_mutations import compilation_error
import time
negative='x'*(512*1024)+'.dart:1:2: Expected: a failing assertion, without a compiler error'
start=time.monotonic()
assert not compilation_error(negative)
elapsed=time.monotonic()-start
assert compilation_error(negative+'\\nlib/example.dart:1:2: Error: invalid declaration')
print(elapsed)
"""
    result=subprocess.run([sys.executable,'-c',script],cwd=Path(__file__).resolve().parent,
                          capture_output=True,text=True,check=True,timeout=5)
    elapsed=float(result.stdout)
    assert elapsed<2, f'Large negative log took {elapsed:.3f}s'
    print(f'Mutation classifier fixtures: 512 KiB negative line classified as no compile error in {elapsed:.6f}s; positive markers PASS')

def cases_for(original,ast):
    nodes={n['name']:n for n in ast['declarations']}
    cases=[]
    def case(name,test,plain_name,before,after,owner=None,kind='B',file=SOURCE):
        body=nodes[owner]['text'] if owner else original
        assert before in body and before!=after,(name,before)
        cases.append(dict(name=name,test=PREFIX+test+'.dart',plain_name=plain_name,before=before,after=after,owner=owner,proof_class=kind,file=file))
    for wide in [False,True]:
        for media in [False,True]:
            for mdblist in [False,True]:
                flags=f'wide={str(wide).lower()} media={str(media).lower()} mdblist={str(mdblist).lower()}'
                case('swapped-neighbour-'+flags.replace(' ','-'),'settings_connections_dpad_test','Connections every edge '+flags,
                     'downNeighbor: wide\n                            ? _premiumizeFocusNode\n                            : _torboxFocusNode,',
                     'downNeighbor: wide\n                            ? _torboxFocusNode\n                            : _premiumizeFocusNode,','_ConnectionsSummaryState')
    body=nodes['_ConnectionsSummaryState']['text']
    before=re.search(r'upNeighbor: widget\.mediaServers != null\s*\? _mediaServersFocusNode\s*: wide\s*\? _indexerManagersFocusNode\s*: _iptvFocusNode,',body).group()
    case('tracking-up-parenthesized','settings_connections_dpad_test','Connections every edge wide=false media=true mdblist=false',before,'upNeighbor: wide ? (widget.mediaServers != null ? _mediaServersFocusNode : _indexerManagersFocusNode) : _iptvFocusNode,','_ConnectionsSummaryState')
    case('sidebar-handoff-removed','settings_connections_dpad_test','sidebar callback=true left=true','MainPageBridge.focusTvSidebar!();',';','_ConnectionCardState')
    case('sidebar-called-when-null','settings_connections_dpad_test','sidebar callback=false left=true','widget.isLeftColumn && MainPageBridge.focusTvSidebar != null','widget.isLeftColumn','_ConnectionCardState')
    case('repeat-handled','settings_connections_dpad_test','ConnectionCard repeat/up are ignored; tap awaits callback','event is! KeyDownEvent','event is! KeyDownEvent && event is! KeyRepeatEvent','_ConnectionCardState')
    body=nodes['_ConnectionCardState']['text'];a=body.index('    WidgetsBinding.instance.addPostFrameCallback');b=body.index('\n    });',a)+len('\n    });')
    case('reveal-not-scheduled','settings_connections_dpad_test','neighbour reveal is deferred post-frame with scaled tempo target and curve',body[a:b],'    // Original-only mutant: no scheduled reveal.','_ConnectionCardState')
    tile='disabled tile cannot focus activate or hover-light and stays dim'
    case('disabled-canRequestFocus-true','settings_tiles_focus_test',tile,'canRequestFocus: widget.enabled,','canRequestFocus: true,','_SettingsTileState')
    body=nodes['_SettingsTileState']['text'];before=re.search(r'onTap: widget\.enabled\s*\? \(\) async \{\s*await widget\.onTap\(\);\s*\}\s*: null,',body).group()
    case('disabled-onTap-kept','settings_tiles_focus_test',tile,before,'onTap: () async { await widget.onTap(); },','_SettingsTileState')
    body=nodes['_SettingsToggleTileState']['text'];match=re.search(r'ExcludeFocus\(\s*child: (Switch\.adaptive\([\s\S]*?\n\s*\)),\s*\)',body)
    case('ExcludeFocus-removed','settings_tiles_focus_test','toggle row is one stop and tap or OK invert the value',match.group(),match[1],'_SettingsToggleTileState')
    case('toggle-does-not-invert','settings_tiles_focus_test','toggle row is one stop and tap or OK invert the value','widget.onChanged(!widget.value)','widget.onChanged(widget.value)','_SettingsToggleTileState')
    for label,owner in [('tile','_SettingsTileState'),('toggle','_SettingsToggleTileState'),('hero','_SettingsLookHeroState')]:
        case(label+'-borrowed-node-ignored','settings_tiles_focus_test',label+' focus ownership borrowed=true and live focus','widget.focusNode ?? (_ownNode ??= FocusNode())','(_ownNode ??= FocusNode())',owner)
    case('hero-threshold-380','settings_tiles_focus_test','hero swatches threshold width=380.0','constraints.maxWidth >= 390','constraints.maxWidth >= 380','_SettingsLookHeroState')
    case('memo-base-only','settings_page_theme_test','page theme memo keys identical base and app independently','!identical(base, _settingsThemeBase) ||\n      !identical(app, _settingsThemeApp)','!identical(base, _settingsThemeBase)','settingsPageTheme')
    # The test page already themes its own build via SettingsPageScaffold;
    # dropping the route Theme leaves those pixels themed but its State's
    # calling context bare. This is the exact page-vs-route regression.
    case('page-instead-of-route-theme','settings_page_theme_test','push themes route State context so its dialog inherits palette','builder: (ctx) => Theme(data: settingsPageTheme(ctx), child: page),','builder: (ctx) => page,','pushSettingsPage')
    case('barrierDismissible-dropped','settings_page_theme_test','settings dialog scopes palette barrierDismissible=false','barrierDismissible: barrierDismissible,','','showSettingsDialog')
    case('attention-keyword-removed','settings_helpers_test','connection predicates characterize every negative keyword and readiness',"status.contains('inactive') ||\n      ",'','settingsConnectionNeedsAttention')
    case('initials-capital-rule-removed','settings_helpers_test','initials preserve separators internal capitals and empty fallback','if (caps.length >= 2) return caps.substring(0, 2);','if (false) return caps.substring(0, 2);','settingsInitialsFor')
    case('screen-size-label-fallback','settings_helpers_test','TV choices preserve order labels subtitles completeness and size fallback',"return '$percent%';","return 'Automatic';",'tvUiScaleLabel')
    case('dropdown-null-guard','settings_widgets_render_test','dropdown stale value is empty null callback returns normally and subtitle echoes','if (v != null) onChanged(v);','onChanged(v!);','SettingsSelectDropdown')
    case('visible-radius-change','settings_widgets_goldens_test','original pixel golden tv_legacy_gallery','BorderRadius.circular(16)','BorderRadius.circular(30)','SettingsSection')
    case('rule-surface-fill','settings_widgets_render_test','section rule surface keeps border dividers and blurb without fill','color: rule\n                ? Colors.transparent','color: false\n                ? Colors.transparent','SettingsSection')
    # Claude Step 0 review: all 26 original anchors, including already-killed cases.
    # Reviewer script SHA-256: 97dea2e671299bc6810ed9d3e291f46988512e3e23261a9805ab846aff48df13
    review_mutations = [
        ('reveal-unscaled', 'settings_connections_dpad_test', 'neighbour reveal is deferred post-frame with scaled tempo target and curve',
         'duration: _motion.scaled(const Duration(milliseconds: 200)),',
         'duration: const Duration(milliseconds: 200),'),
        ('legacy-autofocus-off', 'settings_touchpoints_test', 'legacy dialog shows full current reason autofocus OK and pops',
         'autofocus: true,\n          onPressed: () => Navigator.of(dialogCtx).pop(),',
         'autofocus: false,\n          onPressed: () => Navigator.of(dialogCtx).pop(),'),
        ('launch-mode', 'settings_touchpoints_test', 'settings URL forwards parsed URI through launcher platform',
         'await launchUrl(Uri.parse(url));',
         'await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);'),
        ('spotlight-bg-bloom', 'settings_widgets_goldens_test', 'original pixel golden tv_spotlight_gallery',
         'colors: [app.fade(t.accent, 0.13), Colors.transparent],',
         'colors: [app.fade(t.accent, 0.2), Colors.transparent],'),
        ('keyup-handled', 'settings_connections_dpad_test', 'ConnectionCard repeat/up are ignored; tap awaits callback',
         'if (event is! KeyDownEvent) return KeyEventResult.ignored;',
         'if (event is KeyRepeatEvent) return KeyEventResult.ignored;'),
        ('wide-threshold', 'settings_connections_dpad_test', 'Connections every edge wide=false media=false mdblist=false width=520.0',
         'final bool wide = constraints.maxWidth > 520;',
         'final bool wide = constraints.maxWidth > 500;'),
        ('tile-opacity', 'settings_tiles_focus_test', 'disabled tile cannot focus activate or hover-light and stays dim',
         'opacity: widget.enabled ? 1 : 0.45,',
         'opacity: widget.enabled ? 1 : 0.5,'),
        ('tile-spec-subtitle', 'settings_tiles_focus_test', 'spec factories retain icon title subtitles and overrides',
         'subtitle: subtitle ?? content.subtitle,',
         'subtitle: content.subtitle,'),
        ('toggle-spec-maxlines', 'settings_tiles_focus_test', 'spec factories retain icon title subtitles and overrides',
         '      subtitleMaxLines: subtitleMaxLines,\n    );',
         '    );'),
        ('banner-warning-tone', 'settings_widgets_goldens_test', 'original pixel golden tv_legacy_gallery',
         'SettingsBannerTone.warning => t.warning,',
         'SettingsBannerTone.warning => t.danger,'),
        ('tile-own-node-not-disposed', 'settings_tiles_focus_test', 'tile focus ownership borrowed=false and live focus',
         "  @override\n  void dispose() {\n    _ownNode?.dispose();\n    super.dispose();\n  }\n\n  @override\n  Widget build(BuildContext context) {\n    final app = AppThemeScope.of(context);\n    final t = app.settings;\n    final spotlight = app.id == 'spotlight';\n    final bool lit = widget.enabled",
         "  @override\n  void dispose() {\n    super.dispose();\n  }\n\n  @override\n  Widget build(BuildContext context) {\n    final app = AppThemeScope.of(context);\n    final t = app.settings;\n    final spotlight = app.id == 'spotlight';\n    final bool lit = widget.enabled"),
        ('header-copy', 'settings_widgets_review_render_test', 'header copy styles and structure spotlight=false',
         "'Manage connections, search & playback'",
         "'Manage connections, search and playback'"),
        ('skeleton-two-sections', 'settings_widgets_render_test', 'section chrome banners skeleton runtime types spotlight=false',
         '                SizedBox(height: 24),\n                _SkeletonSection(),\n              ],',
         '              ],'),
        ('badge-size', 'settings_widgets_review_render_test', 'pending badge size and color palette=explicit',
         '      Icons.chevron_right_rounded,\n      size: 20,\n      color:\n          IconTheme.of(context).color ??',
         '      Icons.chevron_right_rounded,\n      size: 24,\n      color:\n          IconTheme.of(context).color ??'),
        ('legacy-reason-dropped', 'settings_touchpoints_test', 'legacy dialog shows full current reason autofocus OK and pops',
         '                ProfileBootstrap.legacyReasonSummary,',
         "                '',"),
        ('dropdown-echo-removed', 'settings_widgets_render_test', 'dropdown stale value is empty null callback returns normally and subtitle echoes',
         'if (selected?.subtitle != null) ...[',
         'if (false) ...['),
        ('hero-tap-not-awaited', 'settings_tiles_focus_test', 'hero awaits async tap completion',
         'onTap: () async => await widget.onTap(),',
         'onTap: () { widget.onTap(); },'),
        ('input-focused-width', 'settings_widgets_theme_table_test', 'resolved settings theme table look=legacy',
         'borderSide: BorderSide(color: t.accent, width: 1.5),',
         'borderSide: BorderSide(color: t.accent, width: 2),'),
        ('card-focus-border', 'settings_widgets_review_render_test', 'card hover differs from focus spotlight=false',
         'color: inverse ? app.core.tx : (_focused ? t.accent : t.line),',
         'color: inverse ? app.core.tx : (lit ? t.accent : t.line),'),
        ('summary-first-borrowed-disposed', 'settings_connections_dpad_test', 'Connections every edge wide=false media=false mdblist=false',
         '    _torboxFocusNode.dispose();',
         '    widget.firstCardFocusNode?.dispose();\n    _torboxFocusNode.dispose();'),
        ('section-empty-title-label', 'settings_widgets_review_render_test', 'empty section title creates no section label',
         'if (title.isNotEmpty) SettingsSectionLabel(title, color: accentColor),',
         'SettingsSectionLabel(title, color: accentColor),'),
        ('info-tile-spec', 'settings_tiles_focus_test', 'spec factories retain icon title subtitles and overrides',
         '      title: content.title,\n      value: value,',
         '      title: content.subtitle,\n      value: value,'),
        ('right-col-left-nosidebar', 'settings_connections_dpad_test', 'sidebar callback=true left=false',
         '} else if (widget.isLeftColumn && MainPageBridge.focusTvSidebar != null) {',
         '} else if (MainPageBridge.focusTvSidebar != null) {'),
        ('reveal-context-check', 'settings_connections_dpad_test', 'unattached neighbour remains handled and reveal does not throw',
         '      if (target.context != null) {\n        tvRevealMinimal(',
         '      if (true) {\n        tvRevealMinimal('),
        ('pending-badge-color', 'settings_widgets_review_render_test', 'pending badge size and color palette=resolved-null',
         'AppThemeScope.of(context).settings.dim2,',
         'AppThemeScope.of(context).settings.dim,'),
        ('switch-thumb-unselected', 'settings_widgets_theme_table_test', 'resolved settings theme table look=broadsheet',
         ': app.core.tx;\n        return states.contains(WidgetState.disabled)',
         ': onAccent;\n        return states.contains(WidgetState.disabled)'),
    ]
    for name,test,plain,before,after in review_mutations:
        assert original.count(before)==1, (name, "Review anchor must be unique")
        case(name,test,plain,before,after)
    source='settings_widgets_source_contract_test'
    case('dispose-order',source,'S summary focus labels creation points and ordered disposal','_torboxFocusNode.dispose();\n    _premiumizeFocusNode.dispose();','_premiumizeFocusNode.dispose();\n    _torboxFocusNode.dispose();','_ConnectionsSummaryState',kind='S')
    case('focus-debug-label',source,'S summary focus labels creation points and ordered disposal',"'settings-media-servers'","'settings-media-serverz'",'_ConnectionsSummaryState',kind='S')
    case('motion-hook',source,'S motion dependency hook reveal guard wrapper disposal and borrowed ownership','_motion = AppMotion.of(context);','// Original-only mutant: dependency assignment removed.','_ConnectionCardState',kind='S')
    case('rendering-fallback',source,'S rendering fallback remains Automatic and memo is private to one owner',"return 'Automatic';","return 'Unknown';",'tvRenderQualityLabel',kind='S')
    case('declaration-deleted',source,'all 60 manifest declarations have exactly one physical owner',nodes['WebDavSyncPendingBadge']['text'],'',kind='S')
    cases.append(dict(name='completion-flag-on-original',test=PREFIX+source+'.dart',plain_name='staged service show lists import boundaries DAG and dormant completion',before='',after='\nSETTINGS_WIDGETS_COMPLETE = True\n',owner=None,proof_class='S',file='dev/tool/check_search_architecture.py'))
    case('facade-http-import',source,'staged service show lists import boundaries DAG and dormant completion',"import 'package:flutter/material.dart';","import 'package:flutter/material.dart';\nimport 'package:http/http.dart';",kind='S')
    case('facade-player-import',source,'staged service show lists import boundaries DAG and dormant completion',"import 'package:flutter/material.dart';","import 'package:flutter/material.dart';\nimport 'package:debrify/screens/video_player_screen.dart';",kind='S')
    return cases,nodes

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--fixtures',action='store_true')
    p.add_argument('--worktree',type=Path);p.add_argument('--checkpoint')
    p.add_argument('--parser-package',type=Path);p.add_argument('--evidence',type=Path)
    p.add_argument('--only',nargs='*')
    args=p.parse_args();
    if args.fixtures:fixture_test();return
    if not all((args.worktree,args.checkpoint,args.parser_package,args.evidence)):
        p.error('--worktree, --checkpoint, --parser-package and --evidence are required without --fixtures')
    assert compilation_error('lib/example.dart:1:2: Error: invalid declaration')
    assert not compilation_error('Actual: _TypeError:<Null check operator used on a null value>')
    root=args.worktree.resolve();evidence=args.evidence.resolve();evidence.mkdir(parents=True,exist_ok=True)
    assert root.name=='settings_widgets_original' and '.dart_tool' in root.parts
    def git(*args):return subprocess.check_output(['git',*args],cwd=root,text=True).strip()
    assert git('rev-parse','HEAD')==git('rev-parse',args.checkpoint)
    assert not git('status','--porcelain'), 'Original copy must start clean'
    assert not (root/'lib/features/settings_widgets').exists()
    original=(root/SOURCE).read_text();assert 'class _ConnectionsSummaryState' in original
    ast=parse({'original':original},args.parser_package.resolve())['original']
    cases,nodes=cases_for(original,ast)
    results=[]
    if args.only:
        old=json.loads((evidence/'table.json').read_text());assert old['checkpoint']==git('rev-parse','HEAD')
        results=[r for r in old['mutations'] if r['name'] not in args.only]
    for case in cases:
        if args.only and case['name'] not in args.only:continue
        file=root/case['file'];before=file.read_text();mutant=before
        if case['owner']:
            node=nodes[case['owner']];changed=node['text'].replace(case['before'],case['after'],1)
            assert changed!=node['text']
            mutant=before[:node['start']]+changed+before[node['end']:]
        elif case['before']:mutant=before.replace(case['before'],case['after'],1)
        else:mutant=before+case['after']
        assert mutant!=before,case['name'];file.write_text(mutant)
        try:
            cmd=['flutter','test','--no-pub','--concurrency=1','--reporter','json',case['test'],'--plain-name',case['plain_name']]
            result=subprocess.run(cmd,cwd=root,capture_output=True,text=True)
            directory=evidence/case['proof_class'];directory.mkdir(exist_ok=True)
            log=directory/(case['name']+'.jsonl');log.write_text(result.stdout)
            (directory/(case['name']+'.stderr')).write_text(result.stderr)
            output=result.stdout+result.stderr
            assert not compilation_error(output), 'Compile failure is not a proof: '+case['name']
            tests={};errors={};failed=[]
            for line in result.stdout.splitlines():
                try:event=json.loads(line)
                except ValueError:continue
                if event.get('type')=='testStart':tests[event['test']['id']]=event['test']['name']
                if event.get('type') in ('error','print'):
                    errors.setdefault(event.get('testID'),[]).append(event.get('error',event.get('message','')))
                if event.get('type')=='testDone' and event.get('result') in ('failure','error'):failed.append(event['testID'])
            assertions=[tests[i] for i in failed if any('Expected:' in e or 'TestFailure' in e or 'Pixel test failed' in e for e in errors.get(i,[]))]
            survived=result.returncode==0
            record=dict(name=case['name'],proof_class=case['proof_class'],test=case['test'],assertion_failures=assertions,exit=result.returncode,survived=survived,compilation_error=False,original_sha256=digest(before),mutant_sha256=digest(mutant),log_sha256=hashlib.sha256(log.read_bytes()).hexdigest())
            results.append(record)
            (evidence/'table.json').write_text(json.dumps(dict(checkpoint=git('rev-parse','HEAD'),mutations=results),indent=2)+'\n')
            assert result.returncode and assertions, 'Survived or not an assertion proof: '+case['name']+'\n'+output[-2500:]
            assert case['plain_name'] in assertions,record
            print(case['proof_class']+' '+case['name']+' -> '+assertions[0],flush=True)
        finally:
            file.write_text(before)
            for base in [root/'test/goldens/settings_widgets',root/PREFIX]:
                for directory in base.rglob('failures'):
                    if directory.is_dir():shutil.rmtree(directory)
            assert not git('diff','--name-only','--','lib','test','dev/tool/check_search_architecture.py')
    assert len(results)==len(cases),(len(results),len(cases))
    assert not git('status','--porcelain')
    print('Step 0b:',len(results),'assertion-failing mutations; no survivors; original copy clean')
if __name__=='__main__':main()
