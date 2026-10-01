import 'package:debrify/services/profiles/profile_preferences.dart';

final class YoutubeStorage {
  const YoutubeStorage._();
  // YouTube settings
  static const String _youtubeMaxHeightKey = 'youtube_max_height';

  // YouTube Settings
  /// Preferred max playback height for YouTube (1080/720/480/360). Default 1080.
  static Future<int> getYoutubeMaxHeight() async {
    final prefs = await ProfilePreferences.instance();
    final v = prefs.getInt(_youtubeMaxHeightKey);
    return (v != null && v > 0) ? v : 1080;
  }

  static Future<void> setYoutubeMaxHeight(int height) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setInt(_youtubeMaxHeightKey, height);
  }
}
