import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/storage/iptv_last_channel_storage.dart';
import 'package:debrify/services/storage/startup_iptv_storage.dart';

final class StartupStorage {
  const StartupStorage._();
  static const String _startupChannelIdKey = 'startup_channel_id';
  static const String _startupStremioTvChannelIdKey =
      'startup_stremio_tv_channel_id'; // 'channel', 'stremio_tv', 'playlist', 'continue_watching', 'trakt_continue_watching_movies', or 'trakt_continue_watching_shows'
  static const String _startupPlaylistItemIdKey = 'startup_playlist_item_id';
  static const String _startupContinueWatchingItemIdKey = 'startup_continue_watching_item_id';
  static const String _startupTraktContinueWatchingMovieIdKey = 'startup_trakt_continue_watching_movie_id';
  static const String _startupTraktContinueWatchingShowIdKey = 'startup_trakt_continue_watching_show_id';

  /// Clear all startup settings (auto-launch, channel/playlist references)
  static Future<void> clearAllStartupSettings() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(StartupIptvStorage.startupAutoLaunchEnabledKey);
    await prefs.remove(_startupChannelIdKey);
    await prefs.remove(_startupStremioTvChannelIdKey);
    await prefs.remove(StartupIptvStorage.startupModeKey);
    await prefs.remove(_startupPlaylistItemIdKey);
    await prefs.remove(_startupContinueWatchingItemIdKey);
    await prefs.remove(_startupTraktContinueWatchingMovieIdKey);
    await prefs.remove(_startupTraktContinueWatchingShowIdKey);
    // The startup-channel memory is a startup reference too — Reset must wipe
    // it, or a fresh setup would inherit the previous install's channel.
    await prefs.remove(IptvLastChannelStorage.iptvLastLiveChannelKey);
    await prefs.remove(StartupIptvStorage.startupIptvModeKey);
    await prefs.remove(StartupIptvStorage.startupIptvChannelKey);
  }
}
