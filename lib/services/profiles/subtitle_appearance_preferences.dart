/// Cross-device subtitle appearance contract.
///
/// Custom fonts stay installation-local because their IDs point at files in
/// that device's app storage. The bundled IDs below exist in both Flutter and
/// the native Android TV player and are therefore safe to sync.
abstract final class SubtitleAppearancePreferences {
  static const String elevationKey = 'subtitle_elevation_index';
  static const String elevationMigrationKey =
      'subtitle_extreme_bottom_default_adopted_v1';
  static const String selectedFontKey = 'subtitle_selected_font_id';

  static const Set<String> syncedKeys = <String>{
    'subtitle_size_index',
    'subtitle_style_index',
    'subtitle_color_index',
    'subtitle_bg_index',
    'subtitle_outline_color_index',
    elevationKey,
    'subtitle_bold',
    selectedFontKey,
  };

  static const Set<String> builtInFontIds = <String>{
    'default',
    'roboto',
    'opensans',
    'inter',
    'lato',
    'poppins',
    'nunito',
    'merriweather',
    'sourceserif',
    'firamono',
    'notosans',
  };

  static bool isBuiltInFontId(Object? value) =>
      value is String && builtInFontIds.contains(value);

  static bool isCustomFontId(Object? value) =>
      value is String && value.startsWith('custom_');

  /// Protect an explicit synced Bottom (index 0) from the one-time migration
  /// that only applies to values written before Extreme Bottom existed.
  static void markSyncedElevation(Map<String, Object?> values) {
    if (values.containsKey(elevationKey)) values[elevationMigrationKey] = true;
  }
}
