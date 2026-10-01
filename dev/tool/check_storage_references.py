#!/usr/bin/env python3
"""Final lexical ownership guard; no historical git objects are required."""
import re
import sys

from storage_dart import LEGACY, ROOT, code_tokens, read_map, tracked_dart, tokens


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
            if dot.text == '.' and target in shared:
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
