import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/sanitized_profile_preferences.dart';

/// `debrify_tv_player_style` is read by the NATIVE Debrify TV player
/// (TorboxTvPlayerActivity) via the profile projection, so its registration
/// is a cross-language contract: a missing entry here silently pins the
/// native side to its hard-coded fallback. Source-of-truth checks, not
/// behavior tests.
void main() {
  test('debrify_tv_player_style is projected to native', () {
    expect(
      ProfilePreferences.nativeProjectionKeys,
      contains('debrify_tv_player_style'),
    );
  });

  test('sanitizer accepts every style and rejects anything else', () {
    bool accepts(Object? value) => SanitizedProfilePreferences.allowsEntry(
      'debrify_tv_player_style',
      value,
    );
    for (final style in [
      'classic',
      'network',
      'cinema',
      'guide',
      'spotlight',
      'prestige',
    ]) {
      expect(accepts(style), isTrue, reason: style);
    }
    expect(accepts('ott'), isFalse);
    expect(accepts(''), isFalse);
    expect(accepts(1), isFalse);
  });
}
