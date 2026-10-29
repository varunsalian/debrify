import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'merged slice never constructs or imports append-only source fetching',
    () {
      final files = [
        File('lib/screens/merged_series_detail_screen.dart'),
        if (Directory('lib/features/merged_detail').existsSync())
          ...Directory('lib/features/merged_detail')
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart')),
      ];
      for (final file in files) {
        expect(
          file.readAsStringSync(),
          isNot(contains('SeriesSourceFetcher')),
          reason: file.path,
        );
        expect(
          file.readAsStringSync(),
          isNot(contains('mergeSources')),
          reason: file.path,
        );
      }
    },
  );
}
