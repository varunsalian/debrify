import 'dart:convert';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage/iptv_playlist_storage.dart';

final class IptvLastChannelStorage {
  const IptvLastChannelStorage._();
  // Shared within lib/services/storage/.
  static const String iptvLastLiveChannelKey = 'iptv_last_live_channel';

  // ==========================================================================
  // Last live IPTV channel (startup-channel memory)
  //
  // Single slot, overwritten. Written ONLY once a live channel has actually
  // reached a playing state — never at tune time. Both players call in from
  // their playing-state transition; recording an *attempted* tune would let one
  // dead stream replace the last working channel, and the startup feature
  // re-tunes this unattended on every cold boot, so a dead entry would mean
  // booting into failure until the user cancels out of it.
  //
  // Deliberately NOT [recordIptvWatch]: that store is the Continue Watching
  // shelf, which is on-demand only ("62% through Sky Sports" is meaningless).
  // ==========================================================================

  /// Remember [url]/[name] as the last live channel that actually played.
  ///
  /// [playlistId] is the channel's ORIGIN provider, not whichever shelf it was
  /// launched from — a channel played out of Favourites or a custom list must
  /// come back under its real provider's credentials.
  ///
  /// The provider fingerprint (`serverUrl` + `username`) is resolved here from
  /// [playlistId] rather than asked of callers: the players know only a source
  /// id, and the fingerprint has to be captured while the playlist still
  /// exists — it is what allows a re-added Xtream account (which mints a fresh
  /// playlist id) to be recognised later. Resolving it costs one prefs read,
  /// paid once per settled channel, never per zap.
  static Future<void> setIptvLastLiveChannel(
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
      } catch (_) {
        // Fingerprint is a recovery aid, never a precondition — a failed
        // lookup still stores a usable entry keyed by playlist id.
      }
    }
    final prefs = await ProfilePreferences.instance();
    // Sealed whole: the stored Xtream `url` embeds the account password.
    await SecretVault.setString(
      prefs,
      iptvLastLiveChannelKey,
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
        'playedAt': DateTime.now().millisecondsSinceEpoch,
      }),
    );
  }

  /// The last live channel that reached a playing state, or null.
  static Future<Map<String, dynamic>?> getIptvLastLiveChannel() async {
    final prefs = await ProfilePreferences.instance();
    final raw = await SecretVault.getString(prefs, iptvLastLiveChannelKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // Malformed (hand-edited prefs, or a format change): treat as absent
      // rather than throwing on a startup path.
    }
    return null;
  }

  static Future<void> clearIptvLastLiveChannel() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(iptvLastLiveChannelKey);
  }
}
