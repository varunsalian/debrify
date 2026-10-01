import 'package:debrify/services/storage/player_settings_storage.dart';
import 'package:debrify/services/storage/subtitle_settings_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';


void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('audio passthrough defaults false and round-trips', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await PlayerSettingsStorage.getAudioPassthroughEnabled(), isFalse);
    await PlayerSettingsStorage.setAudioPassthroughEnabled(true);
    expect(await PlayerSettingsStorage.getAudioPassthroughEnabled(), isTrue);
    await PlayerSettingsStorage.setAudioPassthroughEnabled(false);
    expect(await PlayerSettingsStorage.getAudioPassthroughEnabled(), isFalse);
  });

  test('Apple multichannel defaults false and round-trips', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await PlayerSettingsStorage.getAppleMultichannelAudio(), isFalse);
    await PlayerSettingsStorage.setAppleMultichannelAudio(true);
    expect(await PlayerSettingsStorage.getAppleMultichannelAudio(), isTrue);
  });

  test('tvOS force-software-decode defaults false and round-trips', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await PlayerSettingsStorage.getTvosForceSoftwareDecode(), isFalse);
    await PlayerSettingsStorage.setTvosForceSoftwareDecode(true);
    expect(await PlayerSettingsStorage.getTvosForceSoftwareDecode(), isTrue);
  });

  test('subtitle auto-sync stays experimental opt-in and round-trips', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await SubtitleSettingsStorage.getSubtitleAutoSyncEnabled(), isFalse);
    await SubtitleSettingsStorage.setSubtitleAutoSyncEnabled(true);
    expect(await SubtitleSettingsStorage.getSubtitleAutoSyncEnabled(), isTrue);
    await SubtitleSettingsStorage.setSubtitleAutoSyncEnabled(false);
    expect(await SubtitleSettingsStorage.getSubtitleAutoSyncEnabled(), isFalse);
  });
}
