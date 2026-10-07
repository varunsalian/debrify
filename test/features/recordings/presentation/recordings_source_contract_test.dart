import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../support/recordings_source.dart';

void main() {
  test('recordings AST ownership and verbatim S contracts', () {
    // An S rejection is an assertion failure here. Behaviour files never read
    // source, run the reader, or count this assertion as behavioural evidence.
    final proof = Process.runSync('python3', [
      'dev/tool/recordings_source_reader.py',
      '--json',
      if (recordingsComplete) '--complete',
    ]);
    expect(
      proof.exitCode,
      0,
      reason: 'recordings S source contracts: ${proof.stdout}${proof.stderr}',
    );
    final snapshot = recordingsSource();
    expect(snapshot['files'], isNotEmpty);
    expect(
      (snapshot['files'] as List).first,
      'lib/screens/settings/recordings_page.dart',
    );
    final guards =
        jsonDecode(
              File('dev/tool/recordings_source_guards.json').readAsStringSync(),
            )
            as Map;
    final original = snapshot['source'] as String;
    for (final row in (guards['guards'] as List).cast<Map>()) {
      expect(
        original,
        contains(row['original_fragment']),
        reason: 'frozen S inventory ${row['id']}: ${row['reason']}',
      );
    }
  });
}
