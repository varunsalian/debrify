// The subtitle colour is stored as an index shared by the Flutter player, the
// Android TV player and profile packages, so the three must agree.

import 'dart:io';

import 'package:debrify/screens/video_player/services/subtitle_settings_service.dart';
import 'package:debrify/services/profiles/sanitized_profile_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Light grey is appended, so saved choices keep their colour', () {
    final labels = SubtitleColor.options.map((o) => o.label).toList();
    expect(labels.first, 'White');
    expect(labels[7], 'Orange');
    expect(labels.last, 'Light grey');
  });

  test('the Android TV table lists the same colours in the same order', () {
    final kotlin = File(
      'android/app/src/main/kotlin/com/debrify/app/util/SubtitleSettings.kt',
    ).readAsStringSync();
    final table = kotlin.substring(
      kotlin.indexOf('val COLOR_OPTIONS = listOf('),
      kotlin.indexOf('data class BgOption'),
    );
    expect(
      RegExp(r'ColorOption\("([^"]+)"').allMatches(table).map((m) => m[1]),
      SubtitleColor.options.map((o) => o.label),
    );
  });

  test('profile packages carry every colour and nothing past them', () {
    final last = SubtitleColor.options.length - 1;
    const key = 'subtitle_color_index';
    expect(SanitizedProfilePreferences.allowsEntry(key, last), isTrue);
    expect(SanitizedProfilePreferences.allowsEntry(key, last + 1), isFalse);
  });
}
