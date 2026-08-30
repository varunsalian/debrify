import 'package:debrify/services/profiles/profile_creation_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/profiles/sanitized_profile_preferences.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
  });

  tearDown(ProfileRuntime.debugReset);

  test('channel preview defaults to enabled', () async {
    expect(await StorageService.getIptvChannelPreviewEnabled(), isTrue);
  });

  test('channel preview can be disabled and re-enabled', () async {
    await StorageService.setIptvChannelPreviewEnabled(false);
    expect(await StorageService.getIptvChannelPreviewEnabled(), isFalse);

    await StorageService.setIptvChannelPreviewEnabled(true);
    expect(await StorageService.getIptvChannelPreviewEnabled(), isTrue);
  });

  test('channel preview choice is isolated per profile', () async {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeCommitted(
      ProfileScope(profileId: 'one', dataGeneration: 1, sessionEpoch: 1),
    );
    await StorageService.setIptvChannelPreviewEnabled(false);

    ProfileRuntime.publish(
      ProfileScope(profileId: 'two', dataGeneration: 1, sessionEpoch: 2),
    );
    expect(await StorageService.getIptvChannelPreviewEnabled(), isTrue);

    ProfileRuntime.publish(
      ProfileScope(profileId: 'one', dataGeneration: 1, sessionEpoch: 3),
    );
    expect(await StorageService.getIptvChannelPreviewEnabled(), isFalse);
  });

  test('channel preview choice is a reviewed portable preference', () {
    expect(
      ProfileCreationService.copyablePreferenceKeys,
      contains('iptv_channel_preview_enabled'),
    );
    expect(
      SanitizedProfilePreferences.allowsEntry(
        'iptv_channel_preview_enabled',
        false,
      ),
      isTrue,
    );
    expect(
      SanitizedProfilePreferences.allowsEntry(
        'iptv_channel_preview_enabled',
        'false',
      ),
      isFalse,
    );
  });
}
