import 'dart:convert';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage/iptv_last_channel_storage.dart';
import 'package:debrify/services/storage/iptv_playlist_storage.dart';

final class StartupIptvStorage {
  const StartupIptvStorage._();

  // Startup settings
  // Shared within lib/services/storage/.
  static const String startupAutoLaunchEnabledKey = 'startup_auto_launch_enabled';
  // Shared within lib/services/storage/.
  static const String startupModeKey = 'startup_mode';

  // ==========================================================================
  // Startup channel (boot straight into a live IPTV channel)
  //
  // Reuses the surviving `startup_auto_launch_enabled` / `startup_mode` keys
  // from the removed general Launch-on-Startup feature; `startup_mode` is set
  // to 'iptv' so a future second mode can coexist without another master flag.
  // ==========================================================================

  // Shared within lib/services/storage/.
  static const String startupIptvModeKey = 'startup_iptv_mode';
  // Shared within lib/services/storage/.
  static const String startupIptvChannelKey = 'startup_iptv_channel';

  /// 'last' (whatever played most recently) or 'pinned' (a chosen channel).
  static const String startupIptvModeLast = 'last';
  static const String startupIptvModePinned = 'pinned';

  /// Payload marker meaning "nothing is remembered yet — start on whatever the
  /// IPTV page lands on". Never persisted; only ever set by [warmStartupIptv].
  static const String startupIptvFirstAvailable = 'firstAvailable';

  static Future<bool> getStartupIptvEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return (prefs.getBool(startupAutoLaunchEnabledKey) ?? false) && prefs.getString(startupModeKey) == 'iptv';
  }

  static Future<void> setStartupIptvEnabled(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(startupAutoLaunchEnabledKey, enabled);
    if (enabled) {
      await prefs.setString(startupModeKey, 'iptv');
    } else {
      // Leave the mode behind rather than clearing it: re-enabling should come
      // back to IPTV, not to a blank slate.
      await prefs.remove(startupModeKey);
    }
  }

  static Future<String> getStartupIptvMode() async {
    final prefs = await ProfilePreferences.instance();
    final mode = prefs.getString(startupIptvModeKey);
    return mode == startupIptvModePinned ? startupIptvModePinned : startupIptvModeLast;
  }

  static Future<void> setStartupIptvMode(String mode) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(
      startupIptvModeKey,
      mode == startupIptvModePinned ? startupIptvModePinned : startupIptvModeLast,
    );
  }

  /// The pinned startup channel. Same blob shape as `IptvLastChannelStorage.setIptvLastLiveChannel`,
  /// so both modes resolve through one code path at launch.
  static Future<Map<String, dynamic>?> getStartupIptvChannel() async {
    final prefs = await ProfilePreferences.instance();
    final raw = await SecretVault.getString(prefs, startupIptvChannelKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  /// [playlistId] must be the channel's ORIGIN provider — the picker aggregates
  /// Favourites and custom lists, where the same URL can exist under two
  /// different providers, so a URL alone cannot identify which one was chosen.
  static Future<void> setStartupIptvChannel(
    String url, {
    required String name,
    String? playlistId,
    int? channelNumber,
    String? group,
    String? logoUrl,
    Map<String, String>? httpHeaders,
  }) async {
    if (url.isEmpty) return;
    String? serverUrl;
    String? username;
    if (playlistId != null && playlistId.isNotEmpty) {
      try {
        for (final playlist in await IptvPlaylistStorage.getIptvPlaylists()) {
          if (playlist.id == playlistId) {
            if (playlist.isXtreamCodes) {
              serverUrl = playlist.serverUrl;
              username = playlist.username;
            }
            break;
          }
        }
      } catch (_) {}
    }
    final prefs = await ProfilePreferences.instance();
    // Sealed whole for the same reason as the last-live-channel blob: the
    // Xtream `url` embeds the account password.
    await SecretVault.setString(
      prefs,
      startupIptvChannelKey,
      jsonEncode({
        'url': url,
        'name': name,
        if (playlistId != null && playlistId.isNotEmpty) 'playlistId': playlistId,
        if (channelNumber != null) 'channelNumber': channelNumber,
        if (group != null && group.isNotEmpty) 'group': group,
        if (logoUrl != null && logoUrl.isNotEmpty) 'logoUrl': logoUrl,
        if (httpHeaders != null && httpHeaders.isNotEmpty) 'httpHeaders': httpHeaders,
        if (serverUrl != null && serverUrl.isNotEmpty) 'serverUrl': serverUrl,
        if (username != null && username.isNotEmpty) 'username': username,
      }),
    );
  }

  static Future<void> clearStartupIptvChannel() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(startupIptvChannelKey);
  }

  // --- Synchronous startup handoff -----------------------------------------
  //
  // MainPage's `_selectedIndex` is a FIELD INITIALIZER: it runs at construction,
  // long before any async prefs read could answer. Warming the decision in
  // main() before runApp is the same trick `PlatformUtil.isAndroidTvCached`
  // uses, and it is what keeps the Home board from mounting and starting its
  // cold-start IO before we swap to IPTV.

  static Map<String, dynamic>? _startupIptvChannelCached;

  /// The channel to boot into, or null. Only meaningful after [warmStartupIptv].
  static Map<String, dynamic>? get startupIptvChannelCached => _startupIptvChannelCached;

  /// Resolve the startup channel once, before `runApp`. Never throws — a
  /// failure here must degrade to "no startup channel", never to a broken boot.
  static Future<void> warmStartupIptv() async {
    try {
      if (!await getStartupIptvEnabled()) return;
      final mode = await getStartupIptvMode();
      final channel = mode == startupIptvModePinned
          ? await getStartupIptvChannel()
          : await IptvLastChannelStorage.getIptvLastLiveChannel();
      final url = channel?['url'];
      if (url is! String || url.isEmpty) {
        // Nothing remembered yet — the very first boot after switching this on.
        // Rather than doing nothing (which reads as broken), hand the IPTV page
        // a sentinel and let it bootstrap from whatever it lands on. Resolved
        // there, not here, because picking "the first channel" needs the loaded
        // catalog and this runs before the first frame.
        //
        // Only for 'last': "a specific channel" with none chosen is a
        // deliberate blank the settings row already labels, and auto-picking
        // something else would contradict what the user asked for.
        if (mode == startupIptvModeLast) {
          _startupIptvChannelCached = const {startupIptvFirstAvailable: true};
        }
        return;
      }
      _startupIptvChannelCached = channel;
    } catch (_) {
      _startupIptvChannelCached = null;
    }
  }

  /// Clears this owner before the existing profile handoff ledger stamp.
  static void resetProfileCaches() {
    _startupIptvChannelCached = null;
  }
}
