#!/usr/bin/env python3
"""Compile the exact full step-2 composition in an owned scratch worktree."""
import argparse
import hashlib
import json
import re
import shutil
import subprocess
from pathlib import Path
from check_verbatim_moves import ROOT, ensure_parser_package, parse
from iptv_spotlight_timeline_checker_fixtures import inputs, layout, SOURCE, STATE, PREFIX, BRIDGE

CHECKPOINT = '88d98af076f264f0a31373c2d1944a310069f29c'
IDENTITY_TEST = r'''import 'package:debrify/widgets/iptv/spotlight/spotlight_live_timeline.dart';
import 'package:debrify/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/spotlight_timeline_widget_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../../support/iptv_spotlight_timeline_fixture.dart';

void main() {
  testWidgets('live view returns every identical host object before and after replacement', (tester) async {
    await timelineCase(tester, (f) async {
      for (var revision = 0; revision < 2; revision++) {
        f.upCallback = () {};
        f.leftCallback = () {};
        f.channelCallback = (_) {};
        f.programmeCallback = (_, _) {};
        f.selectionCallback = (_) {};
        f.actionsCallback = (_) {};
        f.enableActions = true;
        f.loader = (_) async => [];
        f.nowCallback = () => f.clock;
        f.channels = [timelineChannel(revision)];
        if (revision == 0) { await f.mount(tester); } else { await f.refresh(tester); }
        final state = tester.state<State<SpotlightLiveTimeline>>(find.byType(SpotlightLiveTimeline));
        final view = state as SpotlightTimelineWidgetView;
        final host = state.widget;
        expect(view.onExitUp, same(host.onExitUp), reason: 'onExitUp remains the host function');
        expect(view.onExitLeft, same(host.onExitLeft), reason: 'onExitLeft remains the host function');
        expect(view.onChannelActions, same(host.onChannelActions), reason: 'actions remain the host function');
        expect(view.onChannelActivate, same(host.onChannelActivate), reason: 'channel activation remains the host function');
        expect(view.onProgrammeActivate, same(host.onProgrammeActivate), reason: 'programme activation remains the host function');
        expect(view.onSelectionChanged, same(host.onSelectionChanged), reason: 'selection remains the host function');
        expect(view.scheduleLoader, same(host.scheduleLoader), reason: 'loader remains the host function');
        expect(view.now, same(host.now), reason: 'clock remains the host function');
        expect(view.channels, same(host.channels), reason: 'channels remain the current host list');
      }
    });
  });
}
'''


def sorted_imports(text):
    matches = list(re.finditer(r"(?m)^import\s+['\"][^'\"]+['\"][^;]*;\n", text))
    if not matches:
        return text
    directives = sorted({m.group().strip() for m in matches}, key=lambda s: s.split("'")[1])
    groups = [[d for d in directives if d.startswith("import 'dart:")],
              [d for d in directives if not d.startswith("import 'dart:")]]
    imports = '\n\n'.join('\n'.join(g) for g in groups if g) + '\n\n'
    first = matches[0].start()
    for match in reversed(matches):
        text = text[:match.start()] + text[match.end():]
    return text[:first] + imports + text[first:]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--parser-package', type=Path, required=True)
    args = parser.parse_args()
    package = args.parser_package.resolve()
    ensure_parser_package(package.parent.parent, package)
    original, rows, config, parsed, leaves = inputs(package)
    sources = layout(original, rows, config, parsed, leaves, 2)
    probe = ROOT / '.dart_tool/iptv_spotlight_timeline_composition'
    if not probe.exists():
        subprocess.run(['git', 'worktree', 'add', '--detach', str(probe), CHECKPOINT], cwd=ROOT, check=True)
        subprocess.run(['flutter', 'pub', 'get'], cwd=probe, check=True, stdout=subprocess.DEVNULL)
    assert subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=probe, text=True).strip() == CHECKPOINT
    common = subprocess.check_output(['git', 'rev-parse', '--path-format=absolute', '--git-common-dir'], cwd=ROOT, text=True).strip()
    evidence = Path(common) / 'refactor-evidence/iptv_spotlight_timeline'
    evidence.mkdir(parents=True, exist_ok=True)
    for path, text in sources.items():
        target = probe / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(sorted_imports(text))
    (probe / 'lib/widgets/iptv/spotlight/analysis_options.yaml').write_text('include: ../../../features/analysis_options.yaml\n')
    probe_config = {**config, 'completed_step': 2}
    (probe / 'dev/tool/iptv_spotlight_timeline_checker_config.json').write_text(json.dumps(probe_config, indent=2) + '\n')
    for name in ['check_settings_moves.py', 'occurrence_field_bindings.py', 'iptv_spotlight_timeline_contracts.py',
                 'iptv_spotlight_timeline_checker_fixtures.py', 'iptv_spotlight_timeline_checker_test.py',
                 'iptv_spotlight_timeline_manifest.tsv']:
        shutil.copy2(ROOT / 'dev/tool' / name, probe / 'dev/tool' / name)
    subprocess.run(['dart', 'format', *sources], cwd=probe, check=True, stdout=subprocess.DEVNULL)
    analyze = evidence / 'step0b-composition-analyze.txt'
    for attempt in range(3):
        with analyze.open('w') as stream:
            subprocess.run(['flutter', 'analyze', '--no-pub', SOURCE, PREFIX], cwd=probe, stdout=stream, stderr=subprocess.STDOUT)
        removals = {}
        for line in analyze.read_text().splitlines():
            match = re.match(r'^\s*(?:warning|info) • .* • (\S+):(\d+):\d+ • (unused_import|unnecessary_import)\s*$', line)
            if match:
                path, ln, _ = match.groups()
                assert path in sources
                removals.setdefault(path, []).append(int(ln))
        if not removals:
            break
        for path, lines in removals.items():
            target = probe / path
            text = target.read_text()
            offsets = {sum(map(len, text.splitlines(keepends=True)[:ln - 1])) for ln in lines}
            imports = list(re.finditer(r"(?m)^import\s+['\"][^'\"]+['\"][^;]*;\n", text))
            for match in reversed(imports):
                if any(match.start() <= offset < match.end() for offset in offsets):
                    text = text[:match.start()] + text[match.end():]
            target.write_text(text)
        subprocess.run(['dart', 'format', *sources], cwd=probe, check=True, stdout=subprocess.DEVNULL)
    assert not re.search(r'^\s*(?:warning|error) •', analyze.read_text(), re.M), analyze.read_text()
    cli_package = probe / '.dart_tool/iptv_spotlight_timeline_parser/probe_cli/.dart_tool/package_config.json'
    ensure_parser_package(cli_package.parent.parent, cli_package)

    def checker(label, accepted):
        log = evidence / ('step0b-composition-' + label + '.txt')
        command = ['python3', 'dev/tool/check_verbatim_moves.py', '--manifest',
                   'dev/tool/iptv_spotlight_timeline_manifest.tsv', '--parser-package', str(cli_package)]
        with log.open('w') as stream:
            status = subprocess.run(command, cwd=probe, stdout=stream, stderr=subprocess.STDOUT).returncode
        assert (status == 0) == accepted, (label, log.read_text())
        return log

    checker('positive', True)
    facade = (probe / SOURCE).read_text()
    for label, before, after in [
        ('header-extra-interface', 'implements SpotlightTimelineWidgetView', 'implements SpotlightTimelineWidgetView, OtherView'),
        ('header-wrong-superclass', 'extends State<SpotlightLiveTimeline>', 'extends State<WrongWidget>'),
        ('header-extra-mixin', 'implements SpotlightTimelineWidgetView', 'with ExtraMixin implements SpotlightTimelineWidgetView'),
        ('export-extra-name', 'SpotlightTimelineSelection;', 'SpotlightTimelineSelection, SpotlightTimelineSections;'),
        ('export-missing-name', 'SpotlightTimelineSelection;', 'SpotlightTimelineEntry;'),
        ('export-extra-show-name', 'show\n        SpotlightScheduleLoader,', 'show\n        AdditionalName, SpotlightScheduleLoader,'),
        ('stored-widget', 'view: this,', 'view: savedWidget,'),
    ]:
        assert before in facade, (label, before)
        try:
            (probe / SOURCE).write_text(facade.replace(before, after, 1))
            checker(label, False)
        finally:
            (probe / SOURCE).write_text(facade)
    export = re.search(r"export\s+(['\"])([^'\"]*spotlight_timeline_entry.dart)\1\s+show[\s\S]*?;", facade)
    assert export
    try:
        changed = facade[:export.start()] + "export '" + export[2] + "';" + facade[export.end():]
        (probe / SOURCE).write_text(changed)
        checker('export-unrestricted', False)
    finally:
        (probe / SOURCE).write_text(facade)
    identity_path = 'test/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/spotlight_timeline_view_probe_test.dart'
    (probe / identity_path).write_text(IDENTITY_TEST)
    subprocess.run(['dart', 'format', identity_path], cwd=probe, check=True, stdout=subprocess.DEVNULL)
    with (evidence / 'step0b-composition-view-identity.txt').open('w') as stream:
        subprocess.run(['flutter', 'test', '--no-pub', '--reporter=expanded', identity_path], cwd=probe, stdout=stream, stderr=subprocess.STDOUT, check=True)
    for label, before, after in [
        ('wrapped-view', 'get onExitUp => widget.onExitUp;', 'get onExitUp => () => widget.onExitUp?.call();'),
        ('cached-view', 'get channels => widget.channels;', 'get channels => _savedWidget.channels;'),
    ]:
        changed = facade.replace(before, after, 1)
        assert changed != facade
        if label == 'cached-view':
            changed = changed.replace('final _owners =', 'late final _savedWidget = widget;\n  final _owners =', 1)
        try:
            (probe / SOURCE).write_text(changed)
            checker(label, False)
            log = evidence / ('step0b-composition-' + label + '-identity.txt')
            with log.open('w') as stream:
                status = subprocess.run(['flutter', 'test', '--no-pub', '--reporter=expanded', identity_path], cwd=probe, stdout=stream, stderr=subprocess.STDOUT).returncode
            assert status != 0 and 'Expected:' in log.read_text(), log.read_text()
        finally:
            (probe / SOURCE).write_text(facade)
    actual = {p: (probe / p).read_text() for p in sources}
    ast = parse(actual, package)
    total = len(facade.splitlines())
    declarations = {n['name']: facade.count('\n', 0, n['end'] - 1) - facade.count('\n', 0, n['start']) + 1 for n in ast[SOURCE]['declarations']}
    sizes = {p: len(t.splitlines()) for p, t in actual.items()}
    assert total <= 400 and all(n <= 500 for p, n in sizes.items() if p != SOURCE), sizes
    (evidence / 'step0b-composition-measurement.json').write_text(json.dumps({
        'original_revision': CHECKPOINT, 'completed_step': 2,
        'facade_lines': total, 'declaration_lines': declarations,
        'imports_gaps_trailing': total - sum(declarations.values()),
        'destination_lines': sizes, 'sha256': {p: hashlib.sha256(t.encode()).hexdigest() for p, t in actual.items()},
        'view_identity': 'nine objects, before and after replacement; wrapped and cached variants fail named assertions',
    }, indent=2) + '\n')
    print('Full step-2 composition, real CLI, strict analysis and view identity PASS')


if __name__ == '__main__':
    main()
