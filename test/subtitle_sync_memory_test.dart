import 'package:debrify/screens/video_player/services/subtitle_settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    SubtitleSettingsService.instance.resetProfileScope();
  });

  test('a dialed-in sync is remembered per identity and recalled', () async {
    final service = SubtitleSettingsService.instance;
    service.setActiveSubtitleIdentity('ep1|ext:sub-a');
    await service.setSyncOffsetMs(1500);
    await service.setSyncScale(25 / 23.976);

    // A subtitle change resets the live values but never the memory.
    service.resetSyncOffset();
    expect(await service.getSyncOffsetMs(), 0);
    expect(service.syncScale, 1.0);

    final recalled = await service.recallSync('ep1|ext:sub-a');
    expect(recalled, isNotNull);
    expect(recalled!.offsetMs, 1500);
    expect(recalled.scale, closeTo(25 / 23.976, 1e-9));
    expect(await service.recallSync('ep2|ext:sub-a'), isNull);
  });

  test('zeroing the sync forgets it; a scale alone is still remembered',
      () async {
    final service = SubtitleSettingsService.instance;
    service.setActiveSubtitleIdentity('ep1|ext:sub-a');
    await service.setSyncOffsetMs(900);
    await service.setSyncOffsetMs(0);
    expect(await service.recallSync('ep1|ext:sub-a'), isNull);

    await service.setSyncScale(1.001);
    final recalled = await service.recallSync('ep1|ext:sub-a');
    expect(recalled?.offsetMs, 0);
    expect(recalled?.scale, closeTo(1.001, 1e-9));
  });

  test('writes without an identity are not remembered', () async {
    final service = SubtitleSettingsService.instance;
    service.setActiveSubtitleIdentity(null);
    await service.setSyncOffsetMs(700);
    service.setActiveSubtitleIdentity('ep1|ext:sub-a');
    expect(await service.recallSync('ep1|ext:sub-a'), isNull);
  });
}
