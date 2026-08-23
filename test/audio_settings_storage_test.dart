import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:debrify/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('audio passthrough defaults false and round-trips', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await StorageService.getAudioPassthroughEnabled(), isFalse);
    await StorageService.setAudioPassthroughEnabled(true);
    expect(await StorageService.getAudioPassthroughEnabled(), isTrue);
    await StorageService.setAudioPassthroughEnabled(false);
    expect(await StorageService.getAudioPassthroughEnabled(), isFalse);
  });

  test('Apple multichannel defaults false and round-trips', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await StorageService.getAppleMultichannelAudio(), isFalse);
    await StorageService.setAppleMultichannelAudio(true);
    expect(await StorageService.getAppleMultichannelAudio(), isTrue);
  });

  test('tvOS force-software-decode defaults false and round-trips', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await StorageService.getTvosForceSoftwareDecode(), isFalse);
    await StorageService.setTvosForceSoftwareDecode(true);
    expect(await StorageService.getTvosForceSoftwareDecode(), isTrue);
  });

  test('subtitle auto-sync defaults on and round-trips', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await StorageService.getSubtitleAutoSyncEnabled(), isTrue);
    await StorageService.setSubtitleAutoSyncEnabled(false);
    expect(await StorageService.getSubtitleAutoSyncEnabled(), isFalse);
    await StorageService.setSubtitleAutoSyncEnabled(true);
    expect(await StorageService.getSubtitleAutoSyncEnabled(), isTrue);
  });
}
