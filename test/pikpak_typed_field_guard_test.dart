import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `PikPakFile.kind`/`.phase` are enums and `.size`/`.id`/`.name` are typed,
/// but they all used to be wire values off a `Map`. Reading them the old way
/// still compiles: `kind == 'drive#folder'` is merely always false, and
/// `kind.toString()` or `id as String?` are invisible to the analyzer. Nine of
/// these shipped at once — enough to kill folder playback, search and the
/// playlist tree — so they are worth a guard.
///
/// The plain `==` form is an analyzer error now
/// (`unrelated_type_equality_checks`); this covers the forms it cannot see.
void main() {
  final wireStrings = RegExp(
    r"""'(drive#(file|folder)|virtual#season|PHASE_TYPE_[A-Z]+)'""",
  );
  final launderedToString = RegExp(r'\.(kind|phase)\s*\.toString\(\)');
  // The leading dot matters: it separates a field read from a raw map read
  // like `data['access_token'] as String?`, where the cast is correct.
  final castToString = RegExp(
    r'\.(kind|phase|size|id|name|fileId|mimeType|parentId)\s+as\s+String',
  );

  test('no PikPak typed field is read as the wire value it used to be', () {
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;

      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        final where = '${entity.path}:${i + 1}';

        if (launderedToString.hasMatch(line)) {
          offenders.add('$where — toString() on an enum, compared as a string');
        }
        if (castToString.hasMatch(line)) {
          offenders.add('$where — cast of an already-typed field to String');
        }
        // A wire string next to one of these fields means the migration was
        // missed here. Models may name them: that is where parsing happens.
        if (wireStrings.hasMatch(line) &&
            RegExp(r'\.(kind|phase)\b').hasMatch(line) &&
            !entity.path.startsWith('lib/features/pikpak/models/')) {
          offenders.add('$where — typed field compared to a wire string');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Use the getters on PikPakFile (isFolder, isFile, isVirtual, '
          'isReady, isVideo) or the field directly:\n${offenders.join('\n')}',
    );
  });
}
