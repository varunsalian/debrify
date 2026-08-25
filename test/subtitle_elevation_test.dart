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
