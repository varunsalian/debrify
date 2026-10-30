import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recordings retains thirteen bare radii and no shape tokens', () {
    final sources = [
      File('lib/screens/settings/recordings_page.dart'),
      if (Directory('lib/features/recordings').existsSync())
        ...Directory('lib/features/recordings')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart')),
    ].map((f) => f.readAsStringSync()).join('\n');
    // Same radius matcher as shape_manifest_test.dart; no shared registry edit.
    final radius = RegExp(
      r'BorderRadius\.circular\(\s*[0-9]+(?:\.[0-9]+)?\s*\)'
      r'|BorderRadius\.all\(\s*Radius\.circular\(\s*[0-9]+(?:\.[0-9]+)?\s*\)\s*\)',
    );
    // 12, +1 for the network share status row (2026-10-30).
    expect(radius.allMatches(sources).length, 13);
    expect(RegExp(r'app\.shape\.').allMatches(sources), isEmpty);
  });
}
