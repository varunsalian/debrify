import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/sanitized_profile_preferences.dart';

/// `tv_player_controls_style` is read by the NATIVE Android TV player via the
/// profile projection, so its registration is a cross-language contract: a
/// missing entry here silently pins the Kotlin side to its hard-coded
/// fallback. Source-of-truth checks, not behavior tests.
void main() {
  test('tv_player_controls_style is projected to native', () {
    expect(
      ProfilePreferences.nativeProjectionKeys,
      contains('tv_player_controls_style'),
    );
  });

  test('sanitizer accepts both skins and rejects anything else', () {
    bool accepts(Object? value) => SanitizedProfilePreferences.allowsEntry(
      'tv_player_controls_style',
      value,
    );
    expect(accepts('ott'), isTrue);
    expect(accepts('classic'), isTrue);
    expect(accepts('cinema'), isFalse);
    expect(accepts(''), isFalse);
    expect(accepts(1), isFalse);
  });
}
