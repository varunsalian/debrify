import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/sanitized_profile_preferences.dart';
import 'package:debrify/services/storage_service.dart';

/// `tv_player_controls_style` is read by the NATIVE Android TV player via the
/// profile projection, so its registration is a cross-language contract: a
/// missing entry here silently pins the Kotlin side to its hard-coded
/// fallback. Source-of-truth checks, not behavior tests.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('unset and invalid styles resolve to OTT', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await StorageService.getTvPlayerControlsStyle(), 'ott');

    SharedPreferences.setMockInitialValues({
      'tv_player_controls_style': 'unknown',
    });
    expect(await StorageService.getTvPlayerControlsStyle(), 'ott');
  });

  test('an explicit existing style remains selected after upgrade', () async {
    SharedPreferences.setMockInitialValues({
      'tv_player_controls_style': 'marquee',
    });
    expect(await StorageService.getTvPlayerControlsStyle(), 'marquee');
  });

  test('tv_player_controls_style is projected to native', () {
    expect(
      ProfilePreferences.nativeProjectionKeys,
      contains('tv_player_controls_style'),
    );
  });

  test('sanitizer accepts every skin and rejects anything else', () {
    bool accepts(Object? value) => SanitizedProfilePreferences.allowsEntry(
      'tv_player_controls_style',
      value,
    );
    for (final skin in [
      'ott',
      'classic',
      'frost',
      'marquee',
      'broadcast',
      'pulse',
      'ticket',
    ]) {
      expect(accepts(skin), isTrue, reason: skin);
    }
    expect(accepts('cinema'), isFalse);
    expect(accepts(''), isFalse);
    expect(accepts(1), isFalse);
  });
}
