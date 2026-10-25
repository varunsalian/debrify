#!/usr/bin/env python3
"""Final lexical ownership guard; no historical git objects are required."""
import re
import sys

from storage_dart import LEGACY, ROOT, code_tokens, read_map, tracked_dart, tokens


# Phase 21b: the one test-support file that owns the storage-internal calls the
# video-player characterization suites need for physical resume-map
# assertions. Exact path and exact member set; no prefix and no ceiling.
SUPPORT = 'test/features/video_player/support/physical_resume_store.dart'
SUPPORT_MEMBERS = frozenset({'PlaybackStateStore.getPlaybackStateMap',
                             'PlaybackStateStore.savePlaybackStateMap',
                             'PlaybackIdentityStorage.seriesProgressKey'})


def findings(source, path, shared):
    errors = []
    executable = code_tokens(source)
    if any(t.text == 'StorageService' for t in executable):
        errors.append(f'{path}: executable StorageService reference')

    # Include conditional URIs and ignore intervening comments in directives.
    directive = False
    for token in tokens(source):
        if token.kind == 'code' and token.text in ('import', 'export'):
            directive = True
        elif token.kind == 'code' and token.text == ';':
            directive = False
        elif directive and token.kind == 'literal':
            match = re.fullmatch(r'''r?(['"])(.*?)\1''', token.text, re.DOTALL)
            if match and match.group(2).rsplit('/', 1)[-1] == 'storage_service.dart':
                errors.append(f'{path}: old storage import/export')

    if not path.startswith('lib/services/storage/'):
        for owner, dot, member in zip(executable, executable[1:], executable[2:]):
            target = owner.text + '.' + member.text
            if dot.text == '.' and target in shared and not (path == SUPPORT and target in SUPPORT_MEMBERS):
                errors.append(f'{path}: shared internal member {target} escaped storage')
    return errors


def self_test(shared):
    allowed = """// StorageService.foo()
void f() {
  print('StorageService: preserved log');
  print(r'${StorageService.foo()}');
  print('lib/services/storage_service.dart');
}
"""
    assert not findings(allowed, 'test/example.dart', shared)
    for source in (
        'StorageService? value;',
        "print('${StorageService.foo()}');",
        "import /* retained comment */ 'package:debrify/services/storage_service.dart';",
        "export 'new.dart' if (dart.library.io) 'storage_service.dart';",
        "import r'../services/storage_service.dart';",
    ):
        assert findings(source, 'test/example.dart', shared), source
    target = sorted(shared)[0]
    assert findings(target + '();', 'lib/example.dart', shared)
    assert not findings(target + '();', 'lib/services/storage/example.dart', shared)
    assert SUPPORT_MEMBERS <= shared, sorted(SUPPORT_MEMBERS - shared)
    support = ''.join(member + '();\n' for member in sorted(SUPPORT_MEMBERS))
    assert not findings(support, SUPPORT, shared)
    other = sorted(shared - SUPPORT_MEMBERS)[0]
    for label, source, path in (
        ('the same member in lib/', support, 'lib/features/video_player/example.dart'),
        ('another video-player test file', support, 'test/features/video_player/video_player_resume_test.dart'),
        ('another video-player support file', support, 'test/features/video_player/support/resume_driver.dart'),
        ('another test directory', support, 'test/services/physical_resume_store.dart'),
        ('a new file next to the support file', support, SUPPORT.replace('.dart', '_extra.dart')),
        ('a fourth member in the support file', support + other + '();\n', SUPPORT),
    ):
        found = findings(source, path, shared)
        assert found, label
        if path == SUPPORT:
            assert found == [f'{SUPPORT}: shared internal member {other} escaped storage'], found
    print('Support exemption: exact path and exact three-member set; lib/, other test files/directories, '
          'a new file and a fourth member rejected.')
    print('Reference guard fixtures: executable, directive and shared-owner violations rejected.')


def check():
    shared = {r['target'] for r in read_map() if r['shared'] == 'yes'}
    if '--self-test' in sys.argv:
        self_test(shared)
    errors = []
    if (ROOT / LEGACY).exists():
        errors.append(f'Legacy storage file still exists: {LEGACY}')
    for path in tracked_dart():
        file = ROOT / path
        if not file.exists():
            continue
        source = file.read_text()
        # Visit every tracked Dart file, including tools; skip unrelated lexing.
        if ('StorageService' not in source and 'storage_service.dart' not in source
                and not any(s.split('.')[0] in source for s in shared)):
            continue
        errors.extend(findings(source, path, shared))
    assert not errors, '\n'.join(errors)
    print('Storage references: no legacy executable references/imports; shared members stay within storage.')


if __name__ == '__main__':
    check()
