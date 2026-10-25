"""Real schema/guards: complete positives and every rule-2/round-2 negative."""
import copy
import json
import os
from pathlib import Path
import subprocess
import tempfile

from check_verbatim_moves import ROOT, parse
from check_settings_moves import tokens
from dart_move_partition import partition, frozen
from dart_move_fixture import materialize
import check_dart_moves as d
from dart_move_history import check_earlier, load_manifest

SOURCE = 'lib/screens/video_player_screen.dart'
DEST = 'lib/features/video_player/presentation/legacy_video_player/vp_fixture.dart'


def fixture(package):
    directory = ROOT / 'dev/tool/dart_moves/fixtures/host'
    return ((directory / 'original.dart.txt').read_text(),
            json.loads((directory / 'manifest.json').read_text()),
            json.loads((directory / 'sources.json').read_text()))


def run(package):
    original, manifest, current = fixture(package)
    def verify(label, changed=None, spec=None, baseline=None, passes=False):
        errors = d.check(spec or manifest, baseline or original, changed or current, package)
        if bool(errors) == passes:
            raise AssertionError(label + ': ' + '\n'.join(errors))
        print('Dart ownership fixture ' + label + ': ' + ('PASS' if passes else 'rejected'))
    verify('complete collaborator/static/Host positive', passes=True)
    mutations = [
        ('changed literal', DEST, 'padLeft(2', 'padLeft(4'),
        ('dropped comment', DEST, '// preserve this comment', ''),
        ('edited comment', DEST, '// preserve this comment', '// edited comment'),
        ('reordered statement', DEST, '_host . x += 2;\n    _host . x++;', '_host . x++;\n    _host . x += 2;'),
        ('undeclared receiver', DEST, '_host . x = x', '_other.x = x'),
        ('undeclared rename', DEST, 'void move', 'void renamed'),
        ('field captured by same-named local', DEST, '_host . x = x', 'x = x'),
        ('builder context replaced by host', DEST, '{ use(context);', '{ use(_host.context);'),
        ('lexical setSheetState replaced', DEST, 'setSheetState(() {})', '_host.setState(() {})'),
        ('lexical setDialogState replaced', DEST, 'setDialogState(() {})', '_host.setState(() {})'),
        ('owner this unsubstituted', DEST, '_host . visibilityOwner', 'this'),
        ('captured snapshot becomes live host read', DEST, '() => snapshot', '() => _host.x'),
        ('Host setter mis-targeted', DEST, '_host . x = x', '_host.y = x'),
        ('Host compound assignment mis-targeted', DEST, '_host . x += 2', '_host.y += 2'),
        ('Host increment mis-targeted', DEST, '_host . x++', '_host.y++'),
        ('retained-body edit', SOURCE, '_x += 2', '_x += 4'),
        ('facade import change', SOURCE, "import 'dart:async';", "import 'dart:io';"),
        ('destination import mismatch', DEST, "import 'dart:async'", "import 'dart:io'"),
        ('patched extra edit', SOURCE, '_x += 2', '_y += 2'),
        ('frozen Host edit', DEST, 'int get x', 'String get x'),
        ('frozen adapter owner identity', SOURCE, 'visibilityOwner => _s', 'visibilityOwner => Object()'),
        ('frozen constructor edit', DEST, 'VpFixture ( this . _host ) ;', 'VpFixture(this._host) { use(1); }'),
        ('static extra modifier', DEST, 'String vpPad2', 'external String vpPad2'),
        ('static body edit', DEST, "'0'", "'1'"),
        ('unexpected new declaration', SOURCE, 'void owner', 'void unexpected() {}\nvoid owner'),
        ('field initializer order', SOURCE, 'int _x = 0; // keep the initializer comment\n  int _y = 1;', 'int _y = 1;\n  int _x = 0; // keep the initializer comment'),
    ]
    for label, path, before, after in mutations:
        if before not in current[path]:
            raise AssertionError('mutation not applied: ' + label + ': ' + repr(before))
        verify(label, dict(current, **{path: current[path].replace(before, after, 1)}))
    spec = copy.deepcopy(manifest)
    del spec['declarations'][0]
    verify('missing declaration fate', spec=spec)
    parsed = parse({'dest': current[DEST]}, package, ownership=True)['dest']
    physical, _, _ = partition(parsed, ['VpFixture'])
    missing = physical['VpFixture.move']
    verify('missing moved declaration', dict(current, **{
        DEST: current[DEST][:missing['start']] + current[DEST][missing['end']:]}))
    spec = copy.deepcopy(manifest)
    spec['declarations'].append(spec['declarations'][0])
    verify('duplicate move', spec=spec)
    # Surviving original plus destination, with identical moved body.
    moved_body = original[original.index('  void move'):original.index('\n}\nvoid owner')]
    verify('original and destination both present', dict(current, **{
        SOURCE: current[SOURCE].replace('\n}\nvoid owner', '\n' + moved_body + '\n}\nvoid owner')}))
    spec = copy.deepcopy(manifest)
    row = next(r for r in spec['declarations'] if r.get('remove_static'))
    del row['remove_static']
    verify('static removal requires opt-in', spec=spec)
    field_original = 'class _VideoPlayerScreenState { static int value = 1; }\n'
    field_sources = {SOURCE: 'class _VideoPlayerScreenState {}\n', DEST: 'int value = 1;\n'}
    spec = d.retained_manifest(SOURCE, 'lib/features/video_player', field_original, 'fixture', package)
    row = next(r for r in spec['declarations'] if r['original'].endswith('.value'))
    row.update(fate='moved', destination=DEST, target='value', remove_static=True)
    field_units = parse(field_sources, package, ownership=True)
    _, spec['facade_orders'], _ = partition(field_units[SOURCE], spec['split_containers'])
    field_spans, field_orders, _ = partition(field_units[DEST], [])
    spec['destinations'][DEST] = dict(directives=[], orders=field_orders)
    spec['scaffolding'][DEST] = frozen({k: v for k, v in field_spans.items() if k != 'value'})
    verify('static removal cannot authorize a field move', field_sources, spec, field_original)
    reordered = current[SOURCE].replace(
        'int _x = 0; // keep the initializer comment\n  int _y = 1;',
        'int _y = 1;\n  int _x = 0; // keep the initializer comment')
    spec = copy.deepcopy(manifest)
    order = spec['facade_orders']['_VideoPlayerScreenState']
    order[0], order[1] = order[1], order[0]
    verify('initializer order cannot be legalized by editing reviewed order', dict(current, **{SOURCE: reordered}), spec)
    # Correct receiver snapshots/lexical setters cannot be legalized by a
    # matching token edit: the binding checks must independently reject them.
    for name in ['setSheetState', 'setDialogState']:
        spec = copy.deepcopy(manifest)
        row = next(r for r in spec['declarations'] if r['original'].endswith('.move'))
        row['substitutions'].append(dict(before=[name, '('], after=['_host', '.', 'setState', '('], count=1))
        changed = dict(current, **{DEST: current[DEST].replace(name + '(() {})', '_host.setState(() {})')})
        verify('lexical ' + name + ' rejected with declared edit', changed, spec)
    spec = copy.deepcopy(manifest)
    row = next(r for r in spec['declarations'] if r['original'].endswith('.move'))
    row['substitutions'].append(dict(before=['{', 'use', '(', 'context', ')'],
                                    after=['{', 'use', '(', '_host', '.', 'context', ')'], count=1))
    verify('builder context rejected with declared edit', dict(current, **{
        DEST: current[DEST].replace('{ use(context);', '{ use(_host.context);')}), spec)
    spec = copy.deepcopy(manifest)
    row = next(r for r in spec['declarations'] if r['original'].endswith('.move'))
    row['substitutions'].append(dict(before=['=>', 'snapshot'], after=['=>', '_host', '.', 'x'], count=1))
    changed = dict(current, **{DEST: current[DEST].replace('=> snapshot', '=> _host.x')})
    verify('binding guard even with declared captured-local edit', changed, spec)
    spec = copy.deepcopy(manifest)
    row = next(r for r in spec['declarations'] if r['original'].endswith('.move'))
    row['substitutions'].append(dict(before=['_host', '.', 'x', '++'], after=['_host', '.', 'y', '++'], count=1))
    spec['guards']['host_property_bindings']['_host.y'] = '_VideoPlayerScreenState._y'
    verify('increment binding rejects a declared wrong owner', dict(current, **{
        DEST: current[DEST].replace('_host . x++', '_host.y++')}), spec)
    spec = copy.deepcopy(manifest)
    row = next(r for r in spec['declarations'] if r['original'].endswith('.move'))
    row['substitutions'][0]['after'] = ['x']
    spec['guards'].update(type_renames={'_x': 'x'}, occurrence_type_renames=True)
    verify('field capture rejected even with registered rename', dict(current, **{
        DEST: current[DEST].replace('_host . x', 'x')}), spec)
    verify('Host receiver captured by an original parameter', dict(current, **{
        DEST: current[DEST].replace('void move(int x)', 'void move(Object _host, int x)')}),
        baseline=original.replace('void move(int x)', 'void move(Object _host, int x)'))
    spec = copy.deepcopy(manifest)
    row = next(r for r in spec['declarations'] if r['original'].endswith('.move'))
    row['substitutions'] = [e for e in row['substitutions'] if e['before'] != ['this']]
    verify('owner identity cannot survive by omitting substitution', dict(current, **{
        DEST: current[DEST].replace('_host . visibilityOwner', 'this')}), spec)
    # Formatting punctuation passes, while the required record comma fails.
    verify('optional commas after receiver substitution', dict(current, **{
        DEST: current[DEST].replace('_host . context)', '_host . context,)')}), passes=True)
    record = original.replace('int _y = 1;', 'Object _y = (1);')
    snap = d.retained_manifest(SOURCE, 'lib/features/video_player', record, 'fixture', package)
    verify('required singleton record comma', {SOURCE: record.replace('(1)', '(1,)')}, snap, record)
    cleanup_tests(package, original, manifest, current, verify)
    from test_dart_sleep_moves import run as sleep_tests
    from test_dart_skip_moves import run as skip_tests
    from test_dart_display_moves import run as display_tests
    from test_dart_trakt_moves import run as trakt_tests
    from test_dart_secondary_tracker_moves import run as secondary_tracker_tests
    secondary_tracker_tests(package)
    from test_dart_completion_moves import run as completion_tests
    completion_tests(package)
    from test_dart_pip_moves import run as pip_tests
    pip_tests(package)
    from test_dart_subtitle_sync_moves import run as subtitle_sync_tests
    subtitle_sync_tests(package)
    from test_dart_subtitle_apply_moves import run as subtitle_apply_tests
    subtitle_apply_tests(package)
    from test_dart_subtitle_sources_moves import run as subtitle_sources_tests
    subtitle_sources_tests(package)
    from test_dart_identify_moves import run as identify_tests
    identify_tests(package)
    from test_dart_menu_recording_moves import run as menu_recording_tests
    menu_recording_tests(package)
    from test_dart_resume_moves import run as resume_tests
    resume_tests(package)
    from test_dart_iptv_moves import run as iptv_tests
    iptv_tests(package)
    sleep_tests(package)
    skip_tests(package)
    display_tests(package)
    trakt_tests(package)
    history_tests(package)
    real_manifest = load_manifest('dev/tool/dart_moves/vplayer_p1.json')
    real_original = d.git_text(real_manifest['base'], real_manifest['source'])
    real_sources = materialize(real_manifest, real_original, package)
    errors = d.check(real_manifest, real_original, real_sources, package)
    assert not errors, '\n'.join(errors)
    print('Real frozen Phase-1 draft: all moves/retained bodies/imports/scaffolds PASS (virtual only)')


def cleanup_tests(package, original, manifest, current, verify):
    """Phase 21b declared cleanup edits: moved-body patches and import removal."""
    braced = dict(current, **{DEST: current[DEST].replace(
        'if (!_host . mounted) return ;', 'if (!_host . mounted) { return ; }')})
    assert braced[DEST] != current[DEST]
    brace = dict(before=[')', 'return', ';'], after=[')', '{', 'return', ';', '}'], count=1)

    def moved_spec(**fields):
        spec = copy.deepcopy(manifest)
        row = next(r for r in spec['declarations'] if r['original'].endswith('.move'))
        row.update(fields)
        return spec
    verify('declared moved-body brace patch', braced,
           moved_spec(patches=[brace], reason='C2 braces', test='cleanup proof'), passes=True)
    verify('moved patch without reason', braced, moved_spec(patches=[brace], test='cleanup proof'))
    verify('moved patch without test', braced, moved_spec(patches=[brace], reason='C2 braces'))
    verify('undeclared moved-body brace edit', braced)
    verify('moved patch before-tokens absent', braced, moved_spec(
        patches=[dict(brace, before=[')', 'return', 'null', ';'])], reason='C2 braces', test='cleanup proof'))
    verify('retained row still rejects patches', spec=dict(copy.deepcopy(manifest), declarations=[
        dict(r, patches=[dict(before=['0'], after=['1'], count=1)]) if r['original'] == '_VideoPlayerScreenState._x'
        else r for r in manifest['declarations']]))
    # Import removal renumbers later directive spans; order and tokens stay exact.
    two = "import 'dart:async';\nimport 'dart:io';"
    base = original.replace("import 'dart:async';", two, 1)

    def directive_spec(rows, directives):
        spec = copy.deepcopy(manifest)
        kept = [r for r in spec['declarations'] if not r['original'].startswith('@directive:')]
        spec['declarations'] = rows + kept
        spec['facade_directives'] = directives
        spec['facade_orders']['@directives'] = ['@directive:' + str(i) for i in range(len(directives))]
        return spec
    removed = dict(original='@directive:0', fate='removed', reason='C1 unused import', test='cleanup proof')
    shifted = dict(original='@directive:1', fate='retained', target='@directive:0')
    only_io = dict(current, **{SOURCE: current[SOURCE].replace("import 'dart:async';", "import 'dart:io';", 1)})
    verify('declared import removal with renumbered directive', only_io,
           directive_spec([removed, shifted], ["import 'dart:io';"]), base, passes=True)
    for label, row in [('removed import without reason', {k: v for k, v in removed.items() if k != 'reason'}),
                       ('removed import without test', {k: v for k, v in removed.items() if k != 'test'}),
                       ('removed import with a target', dict(removed, target='@directive:0'))]:
        verify(label, only_io, directive_spec([row, shifted], ["import 'dart:io';"]), base)
    verify('removed directive still present', dict(current, **{SOURCE: current[SOURCE].replace(
        "import 'dart:async';", two, 1)}), directive_spec([removed, shifted], ["import 'dart:io';"]), base)
    exported = base.replace("import 'dart:io';", "export 'dart:io';", 1)
    verify('export removal', dict(current, **{SOURCE: current[SOURCE].replace(
        "import 'dart:async';", "import 'dart:async';", 1)}), directive_spec(
        [dict(original='@directive:0', fate='retained'), dict(removed, original='@directive:1')],
        ["import 'dart:async';"]), exported)
    commented = original.replace("import 'dart:async';", "// note\n" + two, 1)
    verify('removed import carrying a comment', only_io,
           directive_spec([removed, shifted], ["import 'dart:io';"]), commented)
    swapped = dict(current, **{SOURCE: current[SOURCE].replace("import 'dart:async';", "import 'dart:io';\nimport 'dart:async';", 1)})
    verify('retained directive order changed', swapped, directive_spec(
        [dict(original='@directive:0', fate='retained', target='@directive:1'),
         dict(original='@directive:1', fate='retained', target='@directive:0')],
        ["import 'dart:io';", "import 'dart:async';"]), base)
    verify('removed fate outside directives', spec=dict(copy.deepcopy(manifest), declarations=[
        dict(r, fate='removed', reason='x', test='y') if r['original'] == 'owner' else r
        for r in manifest['declarations']]))


def history_tests(package):
    # All Git fixtures live in the authorized evidence directory, never /tmp.
    common = Path(subprocess.check_output(['git', 'rev-parse', '--path-format=absolute', '--git-common-dir'], text=True).strip())
    evidence = Path(os.environ.get('VPLAYER_EVIDENCE_ROOT', common / 'refactor-evidence/vplayer/p1')) / 'history-fixtures'
    evidence.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=evidence) as directory:
        root = Path(directory)
        def git(*args):
            return subprocess.check_output(['git', '-C', directory, *args], text=True).strip()
        git('init', '-q')
        git('config', 'user.email', 'fixture@example.invalid')
        git('config', 'user.name', 'Fixture')
        (root / 'Facade.dart').write_text('void retained() {}\n')
        git('add', '.')
        git('commit', '-qm', 'base')
        base = git('rev-parse', 'HEAD')
        snap = d.retained_manifest('Facade.dart', 'feature', (root / 'Facade.dart').read_text(), base, package)
        (root / 'dev/tool/dart_moves').mkdir(parents=True)
        (root / 'feature').mkdir()
        (root / 'feature/Old.dart').write_text('void oldDestination() {}\n')
        historical = dict(snap, status='applied', destinations={'feature/Old.dart': {}}, phase=1)
        (root / 'dev/tool/dart_moves/p1.json').write_text(json.dumps(historical))
        (root / 'dev/tool/dart_moves/same.json').write_text(json.dumps(snap))
        (root / 'dev/tool/dart_moves/input.json').write_text(json.dumps(snap['declarations']))
        sidecar = dict(snap)
        del sidecar['declarations']
        sidecar['sidecars'] = {'declarations': 'dev/tool/dart_moves/input.json'}
        (root / 'dev/tool/dart_moves/same.json').write_text(json.dumps(sidecar))
        git('add', '.')
        git('commit', '-qm', 'phase1')
        revision = git('rev-parse', 'HEAD')
        later = dict(snap, phase=2, base=revision)
        assert not check_earlier(later, package, root=root)
        (root / 'feature/Old.dart').write_text('void oldDestination() { changed(); }\n')
        assert check_earlier(later, package, root=root)
        print('Historical earlier destination mutation with unchanged facade: rejected')
        (root / 'dev/tool/dart_moves/input.json').write_text('[]')
        (root / 'dev/tool/dart_moves/same.json').write_text('{}')
        loaded = load_manifest('dev/tool/dart_moves/same.json', revision, root)
        assert loaded['declarations'] == snap['declarations']
        errors = d.run_manifest('dev/tool/dart_moves/same.json', package, revision, root)
        assert not errors, errors
        print('--at reads historical manifest and sidecar despite current edits: PASS')
        (root / 'Facade.dart').write_text('void changed() {}\n')
        (root / 'dev/tool/dart_moves/same.json').write_text(json.dumps(snap))
        git('add', '.')
        git('commit', '-qm', 'wrong tree')
        assert d.run_manifest('dev/tool/dart_moves/same.json', package, git('rev-parse', 'HEAD'), root)
        print('--at wrong SHA: rejected')
