import 'dart:io';

import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('scope produces stable generation-aware keys and paths', () {
    final scope = ProfileScope(
      profileId: 'profile-abc_123',
      dataGeneration: 7,
      sessionEpoch: 4,
    );

    expect(scope.preferencePrefix, 'p.profile-abc_123.g.7.');
    expect(scope.preferenceKey('theme'), 'p.profile-abc_123.g.7.theme');
    expect(
      scope.file(Directory.systemTemp, 'db/catalog.sqlite').path,
      p.join(
        Directory.systemTemp.path,
        'profiles',
        'profile-abc_123',
        'g',
        '7',
        'data',
        'db',
        'catalog.sqlite',
      ),
    );
  });

  test('scope rejects unsafe identifiers and traversal', () {
    expect(
      () => ProfileScope(
        profileId: '../admin',
        dataGeneration: 1,
        sessionEpoch: 0,
      ),
      throwsArgumentError,
    );
    final scope = ProfileScope(
      profileId: 'safe',
      dataGeneration: 1,
      sessionEpoch: 0,
    );
    expect(
      () => scope.file(Directory('/tmp/root'), '../escape'),
      throwsArgumentError,
    );
  });

  group('scoped file containment', () {
    final scope = ProfileScope(
      profileId: 'path-pin',
      dataGeneration: 7,
      sessionEpoch: 2,
    );
    final root = Directory(p.join(Directory.systemTemp.path, 'profile paths'));
    final unsafePaths = <String>[
      '..',
      '../escape',
      'nested/../../escape',
      '../data-sibling/escape',
      p.absolute('outside.sqlite'),
      // Even an absolute path inside the scope is not a relative input.
      p.join(scope.storageDirectory(root, 'data').path, 'inside.sqlite'),
      if (Platform.isWindows) ...[
        r'..\escape',
        r'nested\..\..\escape',
        r'nested/..\..\escape',
        r'\escape',
        r'C:\escape',
        r'C:escape',
        r'C:..\escape',
        r'.\C:escape',
        r'nested\..\C:escape',
        r'E:escape',
        r'\\server\share\escape',
        '//server/share/escape',
      ],
    ];
    for (final path in unsafePaths) {
      test('rejects $path through both APIs', () {
        expect(() => scope.file(root, path), throwsArgumentError);
        expect(
          () => scope.fileIn(root, 'documents', path),
          throwsArgumentError,
        );
      });
    }

    final safePaths = <String, String>{
      'db/catalog.sqlite': p.join('db', 'catalog.sqlite'),
      './db/catalog.sqlite': p.join('db', 'catalog.sqlite'),
      'cache/../db/catalog.sqlite': p.join('db', 'catalog.sqlite'),
      'db/./catalog.sqlite': p.join('db', 'catalog.sqlite'),
      'db/../catalog.sqlite': 'catalog.sqlite',
      '.../report..txt': p.join('...', 'report..txt'),
      'db/my file [1].sqlite': p.join('db', 'my file [1].sqlite'),
      'db/café_日本語.txt': p.join('db', 'café_日本語.txt'),
      if (Platform.isWindows)
        r'cache\..\db\catalog.sqlite': p.join('db', 'catalog.sqlite'),
      // POSIX permits these literal filenames; do not impose Windows syntax.
      if (!Platform.isWindows) ...{
        'C:notes.txt': 'C:notes.txt',
        r'db\literal.sqlite': r'db\literal.sqlite',
        r'..\escape': r'..\escape',
      },
    };
    for (final entry in safePaths.entries) {
      test('preserves contained path ${entry.key}', () {
        for (final area in ['data', 'documents', 'cache']) {
          final directory = scope.storageDirectory(root, area).path;
          final actual = scope.fileIn(root, area, entry.key).path;
          expect(actual, p.join(directory, entry.value));
          expect(p.isWithin(directory, actual), isTrue);
        }
      });
    }

    test('preserves relative-root spelling and scope identity', () {
      final relativeRoot = Directory(p.join('relative root', 'storage'));
      expect(
        scope.file(relativeRoot, 'db/catalog.sqlite').path,
        p.join(
          relativeRoot.path,
          'profiles',
          'path-pin',
          'g',
          '7',
          'data',
          'db',
          'catalog.sqlite',
        ),
      );
      expect(scope.preferenceKey('theme'), 'p.path-pin.g.7.theme');
      expect(scope.cacheKey, 'p.path-pin.g.7.e.2');
    });

    test('retains root-equal paths', () {
      for (final path in ['', '.', 'nested/..']) {
        expect(
          p.equals(
            p.normalize(scope.file(root, path).path),
            scope.storageDirectory(root, 'data').path,
          ),
          isTrue,
        );
      }
    });
  });
}
