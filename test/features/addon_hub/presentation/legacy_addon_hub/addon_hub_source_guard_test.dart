import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'rename remains TextFormField and both TV fields never assign node onKeyEvent',
    () {
      final source = [
        File('lib/screens/addons/addon_hub_screen.dart').readAsStringSync(),
        for (final file
            in Directory('lib/features/addon_hub')
                .listSync(recursive: true)
                .whereType<File>()
                .where((f) => f.path.endsWith('.dart')))
          file.readAsStringSync(),
      ].join('\n');
      expect(RegExp(r'\bTextFormField\(').allMatches(source).length, 1);
      expect(RegExp(r'\bTvTextField\(').allMatches(source).length, 2);
      expect(RegExp(r'\.onKeyEvent\s*=').hasMatch(source), isFalse);
      expect(RegExp(r'\bTextField\(').hasMatch(source), isFalse);
    },
  );
}
