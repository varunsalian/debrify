import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('settings dialogs never bypass the TV-safe text field', () {
    final source = File('lib/screens/settings_screen.dart').readAsStringSync();

    // A raw TextField can strand DPAD-only users on TVs affected by
    // flutter/flutter#177360. TvTextField retains the ordinary mobile/desktop
    // path while supplying the in-app keyboard on television platforms.
    expect(RegExp(r'\bTextField\(').hasMatch(source), isFalse);
    expect(RegExp(r'\bTvTextField\(').allMatches(source), isNotEmpty);
  });
}
