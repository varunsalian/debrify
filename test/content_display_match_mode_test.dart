import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:debrify/models/content_display_match_mode.dart';
import 'package:debrify/services/profiles/profile_creation_service.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/sanitized_profile_preferences.dart';
import 'package:debrify/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('unset and unknown values preserve system-managed behavior', () async {
    expect(
      await StorageService.getContentDisplayMatchMode(),
      ContentDisplayMatchMode.systemDefault,
    );

    SharedPreferences.setMockInitialValues({
      'content_display_match_mode': 'future_mode',
    });
    expect(
      await StorageService.getContentDisplayMatchMode(),
      ContentDisplayMatchMode.systemDefault,
    );
  });

  test('every mode round-trips through profile storage', () async {
    for (final mode in ContentDisplayMatchMode.values) {
      await StorageService.setContentDisplayMatchMode(mode);
      expect(await StorageService.getContentDisplayMatchMode(), mode);
    }
  });

  test('preference is copied, projected to Android, and safely portable', () {
    const key = 'content_display_match_mode';
    expect(ProfileCreationService.copyablePreferenceKeys, contains(key));
    expect(ProfilePreferences.nativeProjectionKeys, contains(key));

    for (final mode in ContentDisplayMatchMode.values) {
      expect(
        SanitizedProfilePreferences.allowsEntry(key, mode.storageKey),
        isTrue,
        reason: mode.storageKey,
      );
    }
    expect(SanitizedProfilePreferences.allowsEntry(key, 'automatic'), isFalse);
    expect(SanitizedProfilePreferences.allowsEntry(key, true), isFalse);
  });
}
