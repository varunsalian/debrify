import 'package:debrify/screens/video_player/services/subtitle_settings_service.dart';
import 'package:debrify/services/profiles/sanitized_profile_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
  });
}
