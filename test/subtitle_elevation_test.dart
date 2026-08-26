import 'package:debrify/screens/video_player/services/subtitle_settings_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/profiles/sanitized_profile_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ProfileRuntime.debugReset();
    SubtitleSettingsService.instance.resetProfileScope();
  });

  tearDown(() {
    SubtitleSettingsService.instance.resetProfileScope();
    ProfileRuntime.debugReset();
  });

  test(
    'Extreme Bottom is appended without shifting saved elevation indexes',
    () {
      expect(SubtitleElevation.options.map((option) => option.label), <String>[
        'Bottom',
        'Low',
        'Medium',
        'High',
        'Higher',
        'Extreme Bottom',
      ]);
      expect(SubtitleElevation.options.last.bottomPadding, 8);
      expect(SubtitleElevation.defaultIndex, 5);
      expect(
        const SubtitleSettingsData(
          sizeIndex: 0,
          styleIndex: 0,
          colorIndex: 0,
          bgIndex: 0,
        ).elevation.label,
        'Extreme Bottom',
      );
    },
  );

  test('Extreme Bottom remains portable with a profile', () {
    expect(
      SanitizedProfilePreferences.allowsEntry('subtitle_elevation_index', 5),
      isTrue,
    );
    expect(
      SanitizedProfilePreferences.allowsEntry('subtitle_elevation_index', 6),
      isFalse,
    );
    expect(
      SanitizedProfilePreferences.allowsEntry(
        'subtitle_extreme_bottom_default_adopted_v1',
        true,
      ),
      isTrue,
    );
  });

  test('old saved Bottom adopts Extreme Bottom once per profile', () async {
    final scope = ProfileScope(
      profileId: 'viewer',
      dataGeneration: 1,
      sessionEpoch: 1,
    );
    SharedPreferences.setMockInitialValues(<String, Object>{
      '${scope.preferencePrefix}subtitle_elevation_index': 0,
    });
    ProfileRuntime.initializeCommitted(scope);

    final service = SubtitleSettingsService.instance;
    expect(await service.getElevationIndex(), SubtitleElevation.defaultIndex);

    final raw = await SharedPreferences.getInstance();
    expect(
      raw.getInt('${scope.preferencePrefix}subtitle_elevation_index'),
      SubtitleElevation.defaultIndex,
    );
    expect(
      raw.getBool(
        '${scope.preferencePrefix}'
        'subtitle_extreme_bottom_default_adopted_v1',
      ),
      isTrue,
    );

    await service.setElevationIndex(0);
    service.resetProfileScope();
    expect(await service.getElevationIndex(), 0);
  });

  test('one-time adoption preserves a saved custom elevation', () async {
    ProfileRuntime.initializeLegacy();
    SharedPreferences.setMockInitialValues(<String, Object>{
      'subtitle_elevation_index': 3,
    });

    expect(await SubtitleSettingsService.instance.getElevationIndex(), 3);
    final raw = await SharedPreferences.getInstance();
    expect(raw.getInt('subtitle_elevation_index'), 3);
    expect(raw.getBool('subtitle_extreme_bottom_default_adopted_v1'), isTrue);
  });
}
