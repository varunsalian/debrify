import 'package:debrify/services/profiles/profile_creation_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/profiles/sanitized_profile_preferences.dart';
import 'package:debrify/services/storage/iptv_appearance_storage.dart';
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
    expect(await IptvAppearanceStorage.getIptvChannelPreviewEnabled(), isTrue);
  });

  test('channel preview can be disabled and re-enabled', () async {
    await IptvAppearanceStorage.setIptvChannelPreviewEnabled(false);
    expect(await IptvAppearanceStorage.getIptvChannelPreviewEnabled(), isFalse);

    await IptvAppearanceStorage.setIptvChannelPreviewEnabled(true);
    expect(await IptvAppearanceStorage.getIptvChannelPreviewEnabled(), isTrue);
  });

  test('channel preview choice is isolated per profile', () async {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeCommitted(
      ProfileScope(profileId: 'one', dataGeneration: 1, sessionEpoch: 1),
    );
    await IptvAppearanceStorage.setIptvChannelPreviewEnabled(false);

    ProfileRuntime.publish(
      ProfileScope(profileId: 'two', dataGeneration: 1, sessionEpoch: 2),
    );
    expect(await IptvAppearanceStorage.getIptvChannelPreviewEnabled(), isTrue);

    ProfileRuntime.publish(
      ProfileScope(profileId: 'one', dataGeneration: 1, sessionEpoch: 3),
    );
    expect(await IptvAppearanceStorage.getIptvChannelPreviewEnabled(), isFalse);
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
