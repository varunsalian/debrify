// Which sources title search may query, persisted per profile.
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

import 'profiles/profile_preferences.dart';

@immutable
final class SourceSearchChoices {
  const SourceSearchChoices({
    this.iptv = true,
    this.excludedPlaylistIds = const <String>{},
    this.mediaServers = true,
  });

  /// false: no IPTV playlist is searched.
  final bool iptv;

  /// Playlists left out while [iptv] is true.
  final Set<String> excludedPlaylistIds;

  /// false: Jellyfin/Emby/Plex are not searched.
  final bool mediaServers;

  bool includesPlaylist(String playlistId) =>
      iptv && !excludedPlaylistIds.contains(playlistId);

  /// A copy with [playlistId] included (removed from the exclusions) or
  /// excluded.
  SourceSearchChoices withPlaylist(
    String playlistId, {
    required bool included,
  }) {
    final excluded = excludedPlaylistIds.toSet();
    if (included) {
      excluded.remove(playlistId);
    } else {
      excluded.add(playlistId);
    }
    return SourceSearchChoices(
      iptv: iptv,
      excludedPlaylistIds: excluded,
      mediaServers: mediaServers,
    );
  }

  SourceSearchChoices copyWith({bool? iptv, bool? mediaServers}) =>
      SourceSearchChoices(
        iptv: iptv ?? this.iptv,
        excludedPlaylistIds: excludedPlaylistIds,
        mediaServers: mediaServers ?? this.mediaServers,
      );

  @override
  bool operator ==(Object other) =>
      other is SourceSearchChoices &&
      iptv == other.iptv &&
      mediaServers == other.mediaServers &&
      const SetEquality<String>().equals(
        excludedPlaylistIds,
        other.excludedPlaylistIds,
      );

  @override
  int get hashCode => Object.hash(
    iptv,
    mediaServers,
    Object.hashAllUnordered(excludedPlaylistIds),
  );
}

final class SourceSearchPreferences {
  const SourceSearchPreferences._();

  static const iptvKey = 'source_search_iptv_v1';
  static const excludedKey = 'source_search_iptv_excluded_v1';
  static const mediaServersKey = 'source_search_media_servers_v1';

  /// Missing keys read as the defaults (everything searched).
  static Future<SourceSearchChoices> read() async {
    final prefs = await ProfilePreferences.instance();
    return SourceSearchChoices(
      iptv: prefs.getBool(iptvKey) ?? true,
      excludedPlaylistIds: {...?prefs.getStringList(excludedKey)},
      mediaServers: prefs.getBool(mediaServersKey) ?? true,
    );
  }

  /// Like [read], but never throws: any error (no profile yet, storage
  /// failure) → defaults.
  static Future<SourceSearchChoices> readOrDefault() async {
    try {
      return await read();
    } catch (_) {
      return const SourceSearchChoices();
    }
  }

  /// Stores the bools; stores the exclusions as a SORTED list, removing the
  /// key when empty.
  static Future<void> write(SourceSearchChoices choices) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(iptvKey, choices.iptv);
    await prefs.setBool(mediaServersKey, choices.mediaServers);
    if (choices.excludedPlaylistIds.isEmpty) {
      await prefs.remove(excludedKey);
    } else {
      final sorted = choices.excludedPlaylistIds.toList()..sort();
      await prefs.setStringList(excludedKey, sorted);
    }
  }
}
