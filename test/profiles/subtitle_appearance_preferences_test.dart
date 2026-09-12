import 'package:debrify/screens/video_player/services/subtitle_settings_service.dart';
import 'package:debrify/services/profiles/profile_appearance_preferences.dart';
import 'package:debrify/services/profiles/subtitle_appearance_preferences.dart';
import 'package:debrify/services/subtitle_font_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('portable subtitle contract matches every Flutter preset and font', () {
    expect(
      SubtitleAppearancePreferences.builtInFontIds,
      SubtitleFont.builtInOptions.map((font) => font.id).toSet(),
    );
    expect(SubtitleSize.options, hasLength(7));
    expect(SubtitleStyle.options, hasLength(5));
    expect(SubtitleColor.options, hasLength(8));
    expect(SubtitleBackground.options, hasLength(5));
    expect(SubtitleOutlineColor.options, hasLength(10));
    expect(SubtitleElevation.options, hasLength(6));
    for (final key in SubtitleAppearancePreferences.syncedKeys) {
      expect(ProfileAppearancePreferences.keys, isNot(contains(key)));
    }
    expect(
      ProfileAppearancePreferences.keys,
      contains(SubtitleAppearancePreferences.elevationMigrationKey),
    );
  });

  test('a received elevation marks the old-default migration complete', () {
    final values = <String, Object>{
      SubtitleAppearancePreferences.elevationKey: 0,
    };
    SubtitleAppearancePreferences.markSyncedElevation(values);
    expect(values, {
      SubtitleAppearancePreferences.elevationKey: 0,
      SubtitleAppearancePreferences.elevationMigrationKey: true,
    });
    final unrelated = <String, Object>{'subtitle_size_index': 4};
    SubtitleAppearancePreferences.markSyncedElevation(unrelated);
    expect(unrelated, {'subtitle_size_index': 4});
  });
}
