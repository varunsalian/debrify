// dart format width=160
import 'package:debrify/services/iptv_media_store.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';

final class IptvHistoryStorage {
  const IptvHistoryStorage._();

  // ── IPTV watch history (backs the virtual "Continue watching" playlist) ──

  /// A watched item counts as in-progress between these fractions: below the
  /// floor nothing meaningful was watched (a mis-click, or a few seconds of
  /// buffering), and above the ceiling it's effectively finished.
  static const double _iptvWatchStartedFraction = 0.02;
  static const double iptvWatchFinishedFraction = 0.95;

  /// Whether on-demand IPTV playback feeds the Continue Watching shelves at
  /// all. Off is enforced at BOTH ends — nothing new is recorded, and whatever
  /// is already stored is filtered out of [getIptvContinueWatching] — so the
  /// shelves empty out immediately without deleting anything: turning it back
  /// on restores the rows that were there.
  ///
  /// Deliberately does NOT touch playback positions. Those live in the
  /// separate video-resume store, which the players write directly and which
  /// backs both resuming a movie where you left off and the progress bars on
  /// VOD/episode cards — all of that keeps working with tracking off.
  static const String _iptvTrackContinueWatchingKey = 'iptv_track_continue_watching';

  static Future<bool> getIptvTrackContinueWatching() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_iptvTrackContinueWatchingKey) ?? true;
  }

  static Future<void> setIptvTrackContinueWatching(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_iptvTrackContinueWatchingKey, value);
  }

  /// Remember that an on-demand IPTV item was played, capturing enough
  /// metadata to rebuild its row without re-fetching the panel — the same
  /// trick `IptvFavoritesStorage.setIptvChannelFavorited` uses, and necessary for the same reason:
  /// the provider's catalog can be renumbered or gone by the time the shelf
  /// is read.
  ///
  /// The playback position is deliberately NOT stored here. Both players
  /// already write it to the shared video-resume store keyed by stream URL,
  /// and copying it would hand the shelf a second, staler truth to disagree
  /// with; [getIptvContinueWatching] joins the two at read time instead.
  ///
  /// A no-op when [getIptvTrackContinueWatching] is off. Gating here rather
  /// than at each caller is deliberate: this is the single funnel every
  /// on-demand play goes through — both players, the IPTV page, the series
  /// page, the Home shelf, and the native TV player's bridge hop — and live
  /// channels never reach it.
  static Future<void> recordIptvWatch(
    String channelUrl, {
    String? channelName,
    String? logoUrl,
    String? group,
    String? playlistId,
    Map<String, String>? httpHeaders,
    // Series-episode markers (Xtream series only). When set, the Continue
    // Watching shelf collapses a series' episodes into one row and keeps the
    // series present after a mid-series episode finishes. Absent for movies /
    // catchup / live — their behavior is unchanged.
    String? seriesId,
    String? seriesName,
    int? season,
    int? episode,
    bool? hasNextEpisode,
  }) async {
    if (!await getIptvTrackContinueWatching()) return;
    return IptvMediaStore.recordWatch(
      channelUrl,
      channelName: channelName,
      logoUrl: logoUrl,
      group: group,
      playlistId: playlistId,
      httpHeaders: httpHeaders,
      seriesId: seriesId,
      seriesName: seriesName,
      season: season,
      episode: episode,
      hasNextEpisode: hasNextEpisode,
    );
  }

  static int _iptvWatchTimestamp(dynamic meta) {
    if (meta is Map) {
      final value = meta['lastPlayedAt'];
      if (value is num) return value.toInt();
    }
    return 0;
  }

  /// All remembered on-demand IPTV items (url → metadata).
  static Future<Map<String, Map<String, dynamic>>> getIptvWatchHistory() {
    return IptvMediaStore.watchHistory();
  }

  /// Watched-but-unfinished IPTV items, most recent first. Joins the metadata
  /// captured at play time with the position the players persist to the
  /// video-resume store (both keyed by stream URL), so an item only appears
  /// once it has real progress behind it.
  ///
  /// Each entry is the stored metadata plus `url`, `positionMs`, `durationMs`
  /// and `progress` (0-1).
  static Future<List<Map<String, dynamic>>> getIptvContinueWatching() async {
    // Tracking off hides the shelf everywhere at once: Home's two IPTV rows,
    // the IPTV page's virtual `continue://` playlist (which already drops
    // itself when this comes back empty), and the command rail's count.
    if (!await getIptvTrackContinueWatching()) return [];
    final history = await getIptvWatchHistory();
    if (history.isEmpty) return [];

    // History is capped at 100 entries, so this is a small batched lookup.
    final resumeMap = await IptvMediaStore.resumeEntries(history.keys);

    // Series identity for grouping: <playlistId>::<seriesId>. Same shape the
    // shelf and per-series audio use.
    String? seriesKeyOf(Map<String, dynamic> meta) {
      final sid = meta['seriesId'];
      if (sid == null || (sid is String && sid.isEmpty)) return null;
      return '${meta['playlistId'] ?? ''}::$sid';
    }

    // First pass: gather every started entry with its recency, and track the
    // most-recent recency per series.
    final started = <Map<String, dynamic>>[];
    final seriesLatest = <String, int>{};
    for (final entry in history.entries) {
      final resume = resumeMap[entry.key];
      if (resume == null) continue;
      final positionMs = (resume['positionMs'] as num?)?.toInt() ?? 0;
      final durationMs = (resume['durationMs'] as num?)?.toInt() ?? 0;
      if (durationMs <= 0) continue;
      final progress = positionMs / durationMs;
      if (progress < _iptvWatchStartedFraction) continue;

      final sortAt = (resume['updatedAt'] as num?)?.toInt() ?? _iptvWatchTimestamp(entry.value);
      final seriesKey = seriesKeyOf(entry.value);
      if (seriesKey != null) {
        final prev = seriesLatest[seriesKey];
        if (prev == null || sortAt > prev) seriesLatest[seriesKey] = sortAt;
      }
      started.add({
        ...entry.value,
        'url': entry.key,
        'positionMs': positionMs,
        'durationMs': durationMs,
        'progress': progress,
        // Prefer when playback last moved; a rebuilt-metadata entry can be
        // older than the watching it describes.
        'sortAt': sortAt,
        if (seriesKey != null) '_seriesKey': seriesKey,
      });
    }

    // Second pass: a partially-watched item always shows. A FINISHED item is
    // kept only when it's a series episode that (a) still has a next episode
    // and (b) is the most-recent watched episode of its series — so a series
    // stays for "next up" after finishing a middle episode, but leaves once
    // its finale (or last-watched episode) is done. Movies/catchup and older
    // finished episodes drop out as before.
    final items = <Map<String, dynamic>>[];
    for (final item in started) {
      final progress = item['progress'] as double;
      if (progress <= iptvWatchFinishedFraction) {
        items.add(item);
        continue;
      }
      final seriesKey = item['_seriesKey'] as String?;
      final keep = seriesKey != null && item['hasNext'] == true && (item['sortAt'] as int) == seriesLatest[seriesKey];
      if (keep) items.add(item);
    }

    items.sort((a, b) => (b['sortAt'] as int).compareTo(a['sortAt'] as int));
    return items;
  }

  /// Stored position/duration for whichever of [urls] the players have
  /// progress for. Reads the resume map once — callers are typically a list of
  /// thousands of rows.
  static Future<Map<String, ({int positionMs, int durationMs, double fraction})>> _iptvResumeStates(Iterable<String> urls) async {
    final wanted = urls.toSet();
    if (wanted.isEmpty) return {};

    final resumeMap = await IptvMediaStore.resumeEntries(wanted);
    final states = <String, ({int positionMs, int durationMs, double fraction})>{};
    for (final entry in resumeMap.entries) {
      final resume = entry.value;
      final positionMs = (resume['positionMs'] as num?)?.toInt() ?? 0;
      final durationMs = (resume['durationMs'] as num?)?.toInt() ?? 0;
      if (durationMs <= 0) continue;
      states[entry.key] = (
        positionMs: positionMs,
        durationMs: durationMs,
        fraction: (positionMs / durationMs).clamp(0.0, 1.0),
      );
    }
    return states;
  }

  /// Resume fractions (0-1) for whichever of [urls] have been started. No
  /// upper bound — a finished item shows a full bar, which is the point.
  static Future<Map<String, double>> getIptvProgressForUrls(
    Iterable<String> urls,
  ) async {
    final states = await _iptvResumeStates(urls);
    return {
      for (final entry in states.entries)
        if (entry.value.fraction >= _iptvWatchStartedFraction) entry.key: entry.value.fraction,
    };
  }

  /// Resume position in ms for each part-watched item among [urls], using the
  /// same window as the shelf — so a finished item restarts from the
  /// beginning rather than resuming a second from the end.
  static Future<Map<String, int>> getIptvResumePositions(
    Iterable<String> urls,
  ) async {
    final states = await _iptvResumeStates(urls);
    return {
      for (final entry in states.entries)
        if (entry.value.fraction >= _iptvWatchStartedFraction && entry.value.fraction <= iptvWatchFinishedFraction) entry.key: entry.value.positionMs,
    };
  }

  /// Remove all watch history that belongs to a deleted playlist — mirrors
  /// `IptvFavoritesStorage.removeIptvFavoritesByPlaylistId` so a removed provider leaves nothing
  /// behind pointing at URLs that no longer authenticate.
  static Future<void> removeIptvWatchHistoryByPlaylistId(String playlistId) {
    return IptvMediaStore.removeWatchHistoryByPlaylistId(playlistId);
  }

  /// Take one on-demand IPTV item off the Continue Watching shelf (history +
  /// saved position). The local counterpart of `ContinueWatchingStorage.removeContinueWatchingItem`.
  static Future<void> removeIptvContinueWatchingItem(String url) {
    return IptvMediaStore.removeWatchEntry(url);
  }

  /// Take a whole IPTV series off the Continue Watching shelf — every watched
  /// episode of it, since the shelf collapses them into one card.
  static Future<void> removeIptvContinueWatchingSeries({
    required String playlistId,
    required String seriesId,
  }) {
    return IptvMediaStore.removeWatchSeries(
      playlistId: playlistId,
      seriesId: seriesId,
    );
  }
}
