import 'dart:convert';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/models/media_identity.dart';
import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/iptv_channel_order.dart';
import 'package:debrify/services/iptv_media_store.dart';
import 'package:debrify/services/playback_recovery_intent.dart';
import 'package:debrify/services/playlist_dedupe_key.dart';
import 'package:debrify/services/profiles/connection_resource_service.dart';
import 'package:debrify/services/profiles/profile_collection_resource_facade.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/tvos_recovery_limits.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage/debrify_tv_storage.dart';
import 'package:debrify/services/storage/mdblist_storage.dart';
import 'package:debrify/services/storage/playback_identity_storage.dart';
import 'package:debrify/services/storage/playback_state_store.dart';
import 'package:debrify/services/storage/profile_policy_storage.dart';
import 'package:debrify/services/storage/real_debrid_storage.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_hot_merge.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_library_models.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_tombstones.dart';
import 'package:debrify/utils/json_isolate.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:synchronized/synchronized.dart';

export '../models/home_preferences.dart';

class StorageService {
  static const String _explicitlyWatchedSeriesKey =
      'explicitly_watched_series_v1';

  /// Tracker/account watched-title invalidation. Kept separate from local
  /// playback so finishing an episode never reloads entire remote histories.
  static final ValueNotifier<int> movieFinishedRevision = ValueNotifier(0);

  /// Local movie, episode, and derived-series completion invalidation.
  static final ValueNotifier<int> localCompletionRevision = ValueNotifier(0);

  /// The tracker snapshots are each stored as one JSON object containing every
  /// show. Serializing their read/modify/write cycle prevents two concurrent
  /// show refreshes from both reading the same old object and dropping whichever
  /// write finishes first.
  static final Lock _episodeTrackerSnapshotWriteLock = Lock(); // granted|denied|never|unknown
  static const String _videoResumeKey = 'video_resume_v1';
  static const String _continueWatchingKey = 'continue_watching_v1';
  static const String localSeriesCompletionStateKey =
      'local_series_completion_v1';
  static const String localSeriesCalendarCheckedAtKey =
      'local_series_completion_calendar_checked_at_v1';
  static const String localSeriesCalendarAttemptedAtKey =
      'local_series_completion_calendar_attempted_at_v1';
  static const String _finishedMoviesKey = 'finished_movies_v1';
  static const String _debrifyTvStartRandomKey = 'debrify_tv_start_random';
  static const String _debrifyTvHideSeekbarKey = 'debrify_tv_hide_seekbar';
  static const String _debrifyTvShowChannelNameKey =
      'debrify_tv_show_watermark';
  static const String _debrifyTvShowVideoTitleKey =
      'debrify_tv_show_video_title';
  static const String _debrifyTvHideOptionsKey = 'debrify_tv_hide_options';
  static const String _debrifyTvHideBackButtonKey =
      'debrify_tv_hide_back_button';
  static const String _debrifyTvAvoidNsfwKey = 'debrify_tv_avoid_nsfw';
  static const String _debrifyTvProviderKey = 'debrify_tv_provider';
  static const String _debrifyTvRandomStartPercentKey =
      'debrify_tv_random_start_percent';
  static const String _debrifyTvChannelsKey = 'debrify_tv_channels';
  // Debrify TV playback filters. Quality is matched on the torrent NAME
  // (applied when a channel's cache is read); size is matched on the real
  // per-FILE byte count after the debrid provider returns its file list —
  // per-file sizes are per-episode, so packs need no series/movie detection.
  static const String _debrifyTvFilterQualitiesKey =
      'debrify_tv_filter_qualities';
  static const String _debrifyTvFilterSizesKey = 'debrify_tv_filter_sizes';

  // "You're using an external player" notice shown before Debrify TV hands a
  // stream to another app. Dismissible forever, because the trade-off it
  // explains (one title, no channel rotation) never changes.
  static const String _debrifyTvExternalNoticeDismissedKey =
      'debrify_tv_external_notice_dismissed';

  // Startup settings
  static const String _startupAutoLaunchEnabledKey =
      'startup_auto_launch_enabled';
  static const String _startupChannelIdKey = 'startup_channel_id';
  static const String _startupStremioTvChannelIdKey =
      'startup_stremio_tv_channel_id';
  static const String _startupModeKey =
      'startup_mode'; // 'channel', 'stremio_tv', 'playlist', 'continue_watching', 'trakt_continue_watching_movies', or 'trakt_continue_watching_shows'
  static const String _startupPlaylistItemIdKey = 'startup_playlist_item_id';
  static const String _startupContinueWatchingItemIdKey =
      'startup_continue_watching_item_id';
  static const String _startupTraktContinueWatchingMovieIdKey =
      'startup_trakt_continue_watching_movie_id';
  static const String _startupTraktContinueWatchingShowIdKey =
      'startup_trakt_continue_watching_show_id';
  static const String _movieCompletionThresholdKey =
      'movie_completion_threshold';
  static const String _episodeCompletionThresholdKey =
      'episode_completion_threshold';
  static const String _playbackCompletionMigrationGenerationKey =
      'playback_completion_migration_generation';
  static const int _currentPlaybackCompletionMigrationGeneration = 1;
  static const String _resumeGhostPurgeGenerationKey =
      'resume_ghost_purge_generation';
  static const int _currentResumeGhostPurgeGeneration = 1;

  /// Completion thresholds selectable in Settings → Playback. A lower bound
  /// avoids treating a brief accidental play as watched; 100% lets users
  /// require playback to reach the end.
  static const List<int> localCompletionThresholdOptions = <int>[
    50,
    60,
    70,
    75,
    80,
    85,
    90,
    95,
    100,
  ];
  static const int defaultLocalCompletionThreshold = 80;

  // IPTV settings
  static const String _iptvPlaylistsKey = 'iptv_playlists';
  static const String _iptvDefaultPlaylistKey = 'iptv_default_playlist';
  static const String _iptvLastLiveChannelKey = 'iptv_last_live_channel';

  // TVMaze series mapping keys
  static const String _tvMazeSeriesMappingKey = 'tvmaze_series_mappings';

  // Playlist poster override storage key
  static const String _playlistPosterOverridesKey =
      'playlist_poster_overrides_v1';

  static const String _debrifyTvFavoriteChannelsKey =
      'debrify_tv_favorite_channels_v1';

  // Stremio TV settings
  static const String _stremioTvRotationMinutesKey =
      'stremio_tv_rotation_minutes';
  static const String _stremioTvSeriesRotationMinutesKey =
      'stremio_tv_series_rotation_minutes';
  static const String _stremioTvAutoRefreshKey = 'stremio_tv_auto_refresh';
  static const String _stremioTvFavoriteChannelsKey =
      'stremio_tv_favorite_channels_v1';
  static const String _stremioTvPreferredQualityKey =
      'stremio_tv_preferred_quality';
  static const String _stremioTvDebridProviderKey =
      'stremio_tv_debrid_provider';
  static const String _stremioTvMaxStartPercentKey =
      'stremio_tv_max_start_percent';
  static const String _stremioTvRandomEpisodesKey =
      'stremio_tv_random_episodes';
  static const String _stremioTvLocalCatalogsKey =
      'stremio_tv_local_catalogs_v1';
  static const String _stremioTvCatalogRepoUrlsKey =
      'stremio_tv_catalog_repo_urls_v1';
  static const String _stremioTvHideNowPlayingKey =
      'stremio_tv_hide_now_playing';
  static const String _stremioTvTorrentsFirstKey = 'stremio_tv_torrents_first';

  static const String _playlistKey = 'user_playlist_v1';
  static const String _playlistViewModesKey = 'playlist_view_modes_v1';
  static const String _playlistFavoritesKey = 'playlist_favorites_v1';
  static const String _myWatchlistKey =
      TvOsRecoveryLimits.myWatchlistPreferenceKey;

  static const int _debrifyTvRandomStartPercentDefault = 20;
  static const int _debrifyTvRandomStartPercentMin = 10;
  static const int _debrifyTvRandomStartPercentMax = 90;

  /// Every shipping Debrify TV layout. 'grid' is the historical default — the
  /// channel wall `build()` has always drawn; 'spotlight' is the standing
  /// rail + stage (list + sheet on phone). One key covers every device class:
  /// the style resolves its own layout per device, like `detail_page_style`.
  ///
  /// Coercion is TOTAL and both ways: a value written by a newer build and
  /// read by an older one lands on 'grid' rather than rendering nothing.
  static const Set<String> kDebrifyTvStyles = {'grid', 'spotlight'};

  /// Synchronous mirror of `debrify_tv_style`, kept so a Look can read the
  /// current value without an await. Every existing caller still goes through
  /// the async getter, which also refreshes this.
  static String debrifyTvStyleCached = 'grid';

  static Future<String> getDebrifyTvStyle() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(DebrifyTvStorage.debrifyTvStyleKey);
    return debrifyTvStyleCached = kDebrifyTvStyles.contains(raw)
        ? raw!
        : 'grid';
  }

  static Future<void> setDebrifyTvStyle(String style) async {
    final normalized = kDebrifyTvStyles.contains(style) ? style : 'grid';
    // Mirror BEFORE the await, so anything reading synchronously on the next
    // frame sees the choice. Existing async readers are unaffected.
    debrifyTvStyleCached = normalized;
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(DebrifyTvStorage.debrifyTvStyleKey, normalized);
  }

  static const String _iptvStyleKey = 'iptv_style';
  static const String kIptvStyleDefault = 'spotlight';
  static const Set<String> _iptvStyles = {
    'command',
    'edition',
    'console',
    'spotlight',
  };

  /// Whether browsing IPTV channels may open the focused channel in the
  /// embedded side preview. This is on by default to preserve the shipped
  /// experience; users whose provider enforces a small connection limit can
  /// turn it off without affecting explicit fullscreen playback.
  static const String _iptvChannelPreviewEnabledKey =
      'iptv_channel_preview_enabled';

  static Future<bool> getIptvChannelPreviewEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_iptvChannelPreviewEnabledKey) ?? true;
  }

  static Future<void> setIptvChannelPreviewEnabled(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_iptvChannelPreviewEnabledKey, enabled);
  }

  /// IPTV appearance for TV and desktop. Phones and touch tablets keep their
  /// existing layouts. Missing or unknown values use Spotlight Guide; valid
  /// saved choices remain unchanged.
  ///
  /// Synchronous mirror for Looks, refreshed by the async getter and reset
  /// to the default when switching profiles.
  static String iptvStyleCached = kIptvStyleDefault;

  static Future<String> getIptvStyle() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_iptvStyleKey);
    return iptvStyleCached = _iptvStyles.contains(raw)
        ? raw!
        : kIptvStyleDefault;
  }

  static Future<void> setIptvStyle(String style) async {
    final normalized = _iptvStyles.contains(style) ? style : kIptvStyleDefault;
    iptvStyleCached = normalized;
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_iptvStyleKey, normalized);
  }

  static const String _iptvPlayerGuideStyleKey = 'iptv_player_guide_style';
  static const Set<String> _iptvPlayerGuideStyles = {
    'classic',
    'glass',
    'edition',
    'console',
    'spotlight',
  };

  /// In-player IPTV guide look (zap banner, channel sheet, native guide
  /// overlay + dock): 'classic' (today's look, the default), 'glass'
  /// (Cinema Glass), 'edition' (Midnight Edition) or 'console' (Master
  /// Control). Both players read it once at launch — the Dart player via
  /// this getter, the native TV player via `flutter.iptv_player_guide_style`
  /// in FlutterSharedPreferences. Unknown or unset coerces to 'classic' on
  /// BOTH read and write, so an old build downgrading past a newer value can
  /// never pin a look the reader treats as the exception.
  static Future<String> getIptvPlayerGuideStyle() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_iptvPlayerGuideStyleKey);
    if (_iptvPlayerGuideStyles.contains(raw)) return raw!;
    // Never chosen: Apple TV gets its native idiom, everything else keeps
    // the shipped look. An explicit pick (either way) is stored and wins.
    return PlatformUtil.isTvOS ? 'spotlight' : 'classic';
  }

  static Future<void> setIptvPlayerGuideStyle(String style) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(
      _iptvPlayerGuideStyleKey,
      _iptvPlayerGuideStyles.contains(style) ? style : 'classic',
    );
  }

  static const String _debrifyTvPlayerStyleKey = 'debrify_tv_player_style';
  static const Set<String> _debrifyTvPlayerStyles = {
    'classic',
    'network',
    'cinema',
    'guide',
    'spotlight',
    'prestige',
  };

  /// Playback-screen style for the NATIVE Debrify TV player
  /// (TorboxTvPlayerActivity): 'cinema' (poster + gilded spec line — the
  /// default), 'network' (broadcast lower-third), 'guide' (opaque
  /// broadcast band), 'spotlight' (frosted glass panel), 'prestige'
  /// (quiet serif identity), or 'classic' (the legacy ESPN-style bar +
  /// top marquee). Android TV only. Read once per player launch — the
  /// native side via
  /// `ProfilePreferenceProjection.getString("debrify_tv_player_style")`
  /// (falling back to `flutter.debrify_tv_player_style` in
  /// FlutterSharedPreferences). Unknown or unset coerces to 'cinema' on
  /// BOTH read and write so the two readers can never disagree about the
  /// default.
  static Future<String> getDebrifyTvPlayerStyle() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_debrifyTvPlayerStyleKey);
    return _debrifyTvPlayerStyles.contains(raw) ? raw! : 'cinema';
  }

  static Future<void> setDebrifyTvPlayerStyle(String style) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(
      _debrifyTvPlayerStyleKey,
      _debrifyTvPlayerStyles.contains(style) ? style : 'cinema',
    );
  }

  // ── Continue Watching (recently watched items for home screen) ──────────

  /// Get all continue watching items, sorted by most recent first.
  static Future<List<Map<String, dynamic>>> getContinueWatchingItems() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_continueWatchingKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final List<dynamic> list = await decodeJsonAsync(raw);
      final items = list
          .whereType<Map<String, dynamic>>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      for (final item in items) {
        final id = item['imdbId'];
        final type = item['contentType'];
        if (id is String && type is String) {
          item['imdbId'] = MediaIdentity.progressId(id, type);
        }
      }
      items.sort(
        (a, b) => ((b['updatedAt'] as int?) ?? 0).compareTo(
          (a['updatedAt'] as int?) ?? 0,
        ),
      );
      return items;
    } catch (_) {
      return [];
    }
  }

  /// Add or update a continue watching entry.
  /// Deduplicates by IMDB ID — updates existing entry if found.
  static Future<void> saveContinueWatchingItem({
    required String imdbId,
    required String title,
    required String contentType,
    String? posterUrl,
    String? addonId,
    String? year,
  }) async {
    imdbId = MediaIdentity.progressId(imdbId, contentType);
    // Server-owned titles reopen through Discover, not catalog lookup.
    if (imdbId.startsWith('medialibrary:')) return;
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_continueWatchingKey);
    List<Map<String, dynamic>> items = [];
    if (raw != null && raw.isNotEmpty) {
      try {
        final List<dynamic> list = await decodeJsonAsync(raw);
        items = list
            .whereType<Map<String, dynamic>>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      } catch (_) {}
    }

    // Remove existing entry with same IMDB ID
    items.removeWhere((e) => MediaIdentity.progressId(
      e['imdbId'] as String? ?? '', e['contentType'] as String? ?? '',
    ) == imdbId);

    // Add at front
    items.insert(0, {
      'imdbId': imdbId,
      'title': title,
      'contentType': contentType,
      'posterUrl': posterUrl,
      'addonId': addonId,
      'year': year,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    });

    // Keep max 50 items
    if (items.length > 50) items = items.sublist(0, 50);

    await _saveContinueWatchingItems(items, tombstoneRemovals: false);
  }

  /// Remove a continue watching entry by IMDB ID.
  static Future<void> removeContinueWatchingItem(String imdbId) async {
    final normalized = imdbId.trim().toLowerCase();
    if (normalized.isEmpty) return;
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_continueWatchingKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final List<dynamic> list = await decodeJsonAsync(raw);
      final items = list
          .whereType<Map<String, dynamic>>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final before = items.length;
      items.removeWhere(
        (e) => MediaIdentity.progressId(
          (e['imdbId'] as String? ?? '').trim().toLowerCase(),
          e['contentType'] as String? ?? '',
        ) == normalized,
      );
      if (items.length == before) return;
      await _saveContinueWatchingItems(items);
    } catch (_) {}
  }

  /// Clear all continue watching items.
  static Future<void> clearContinueWatching({
    bool recordSyncDeletions = true,
  }) async {
    await _saveContinueWatchingItems(
      const <Map<String, dynamic>>[],
      tombstoneRemovals: recordSyncDeletions,
    );
  }

  static Future<void> _saveContinueWatchingItems(
    List<Map<String, dynamic>> items, {
    bool tombstoneRemovals = true,
  }) async {
    final prefs = await ProfilePreferences.instance();
    if (tombstoneRemovals) {
      final previous = await getContinueWatchingItems();
      final retained = <String>{
        for (final item in items)
          if ((item['imdbId']?.toString().trim().toLowerCase() ?? '')
              .isNotEmpty)
            item['imdbId'].toString().trim().toLowerCase(),
      };
      await WebDavSyncTombstoneRecorder.recordForCurrentProfile(
        previous
            .map(
              (item) => item['imdbId']?.toString().trim().toLowerCase() ?? '',
            )
            .where((id) => id.isNotEmpty && !retained.contains(id))
            .map(WebDavSyncRecordKey.continueWatching),
      );
    }
    await prefs.setString(_continueWatchingKey, jsonEncode(items));
  }

  /// Movies finished locally by the Debrify player. This intentionally stays
  /// separate from Trakt and Simkl: tracker-backed sessions use the tracker as
  /// their source of truth, while offline/local sessions still need a durable
  /// completed state for the detail screen.
  static Future<Set<String>> _getFinishedMovieIds() async {
    final prefs = await ProfilePreferences.instance();
    final stored = prefs.getStringList(_finishedMoviesKey) ?? const <String>[];
    return {
      for (final raw in stored)
        if (raw.trim().isNotEmpty) MediaIdentity.progressId(raw.trim().toLowerCase(), 'movie'),
    };
  }

  /// Snapshot used by poster badges. Returned IDs are normalized lowercase.
  static Future<Set<String>> getFinishedMovieIds() => _getFinishedMovieIds();

  static Future<bool> isMovieFinished(String imdbId) async {
    imdbId = MediaIdentity.progressId(imdbId, 'movie');
    final normalized = imdbId.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    return (await _getFinishedMovieIds()).contains(normalized);
  }

  /// Mark a locally tracked movie finished, remove it from Continue Watching,
  /// and clear its resumable state. The finished record itself remains so the
  /// detail action can accurately read "Rewatch".
  static Future<void> markMovieAsFinished(String imdbId) async {
    imdbId = MediaIdentity.progressId(imdbId, 'movie');
    final normalized = imdbId.trim().toLowerCase();
    if (normalized.isEmpty) return;

    final finished = await _getFinishedMovieIds();
    if (finished.add(normalized)) {
      final prefs = await ProfilePreferences.instance();
      await prefs.setStringList(_finishedMoviesKey, finished.toList()..sort());
      localCompletionRevision.value++;
    }
    await Future.wait([
      removeContinueWatchingItem(normalized),
      clearPlaybackStateByImdbId(normalized),
    ]);
    debugPrint('StorageService: markMovieAsFinished imdbId="$normalized"');
  }

  /// Start a local rewatch. The caller saves a fresh resume point afterwards,
  /// so only the completed marker is removed here.
  static Future<void> unmarkMovieAsFinished(String imdbId) async {
    imdbId = MediaIdentity.progressId(imdbId, 'movie');
    final normalized = imdbId.trim().toLowerCase();
    if (normalized.isEmpty) return;

    final finished = await _getFinishedMovieIds();
    if (!finished.remove(normalized)) return;

    await PlaybackRecoveryIntent.record({
      WebDavSyncRecordKey.finishedMovie(normalized),
    });
    await WebDavSyncTombstoneRecorder.recordForCurrentProfile(<String>{
      WebDavSyncRecordKey.finishedMovie(normalized),
    });
    final prefs = await ProfilePreferences.instance();
    if (finished.isEmpty) {
      await prefs.remove(_finishedMoviesKey);
    } else {
      await prefs.setStringList(_finishedMoviesKey, finished.toList()..sort());
    }
    localCompletionRevision.value++;
    debugPrint('StorageService: unmarkMovieAsFinished imdbId="$normalized"');
  }

  static Future<Set<String>> getExplicitlyWatchedSeriesIds() async {
    final prefs = await ProfilePreferences.instance();
    return (prefs.getStringList(_explicitlyWatchedSeriesKey) ?? const [])
        .map((id) => id.trim().toLowerCase())
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  static Future<void> setSeriesExplicitlyWatched(
    String imdbId, {
    required bool watched,
  }) async {
    final normalized = imdbId.trim().toLowerCase();
    if (normalized.isEmpty) return;
    final ids = await getExplicitlyWatchedSeriesIds();
    final changed = watched ? ids.add(normalized) : ids.remove(normalized);
    if (!changed) return;
    if (!watched) {
      await WebDavSyncTombstoneRecorder.recordForCurrentProfile(<String>{
        WebDavSyncRecordKey.explicitlyWatchedSeries(normalized),
      });
    }
    final prefs = await ProfilePreferences.instance();
    if (ids.isEmpty) {
      await prefs.remove(_explicitlyWatchedSeriesKey);
    } else {
      await prefs.setStringList(
        _explicitlyWatchedSeriesKey,
        ids.toList()..sort(),
      );
    }
    localCompletionRevision.value++;
  }

  /// Remove all playback state entries (series progress, video progress) for an IMDB ID.
  static Future<void> clearPlaybackStateByImdbId(String imdbId) async {
    final normalized = imdbId.trim().toLowerCase();
    if (normalized.isEmpty) return;
    final map = await PlaybackStateStore.getPlaybackStateMap();
    final keysToRemove = <String>[];
    for (final entry in map.entries) {
      if (entry.value is Map<String, dynamic> &&
          (entry.value['imdbId'] as String?)?.trim().toLowerCase() ==
              normalized) {
        keysToRemove.add(entry.key);
      }
    }
    if (keysToRemove.isEmpty) return;
    for (final key in keysToRemove) {
      map.remove(key);
    }
    await PlaybackStateStore.savePlaybackStateMap(map, recordDeletions: true);
    // Series finished-episode markers share this map, so clearing a Continue
    // Watching item must also invalidate derived series completion.
    localCompletionRevision.value++;
    debugPrint(
      'StorageService: Cleared ${keysToRemove.length} playback state entries for "$imdbId"',
    );
  }

  /// Exact series reset; never touches source bindings or unrelated titles.
  static Future<void> clearSeriesWatchProgress(
    String imdbId,
    String title,
  ) async {
    final id = imdbId.trim().toLowerCase();
    if (id.isEmpty) throw ArgumentError.value(imdbId, 'imdbId');
    final map = await PlaybackStateStore.getPlaybackStateMap();
    map.removeWhere((key, raw) {
      if (raw is! Map) return false;
      final storedId = raw['imdbId']?.toString().trim().toLowerCase();
      return storedId == id ||
          (!PlaybackIdentityStorage.requiresExactProgressIdentity(id) && (storedId == null || storedId.isEmpty) &&
              raw['type'] == 'series' &&
              raw['title']?.toString().trim().toLowerCase() ==
                  title.trim().toLowerCase());
    });
    await PlaybackStateStore.savePlaybackStateMap(map, recordDeletions: true);
    await setSeriesExplicitlyWatched(id, watched: false);
    await saveEpisodeTraktProgress(imdbId: id, percents: {});
    await saveEpisodeSimklProgress(imdbId: id, percents: {});
    await saveEpisodeMdblistProgress(imdbId: id, percents: {});
    localCompletionRevision.value++;
  }

  /// Deletions and sync intent fence every replay. Cold recovery also checks
  /// local position timestamps; a proven return can finish an interrupted
  /// normal save whose position was written just after its native snapshot.
  static Future<bool> hasNewerPlaybackRecoveryIntent({
    String? seriesTitle,
    int? season,
    int? episode,
    String? imdbId,
    String? resumeId,
    required int checkpointAtMs,
    bool includePositions = true,
    bool includeSyncedPositions = true,
    bool Function(Map<String, dynamic>)? isOwnRecoveryWrite,
    bool Function(Map<String, dynamic>)? matchesRecoveryPosition,
  }) async {
    String alias(String type, String title) =>
        '${type}_${title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';
    final map = await PlaybackStateStore.getPlaybackStateMap();
    final stableId = imdbId?.trim().toLowerCase();
    final keys = <String>{};
    final ownRecoveryKeys = <String>{};
    bool newerPosition(Object? value, String key) {
      if (value is! Map) return false;
      final state = Map<String, dynamic>.from(value);
      if (isOwnRecoveryWrite?.call(state) ?? false) {
        ownRecoveryKeys.add(key);
        return false;
      }
      return includePositions &&
          (state['updatedAt'] as num? ?? 0) >= checkpointAtMs;
    }

    final seriesAliases = <String>{
      if (seriesTitle != null) PlaybackIdentityStorage.seriesProgressKey(seriesTitle, stableId),
    };
    final videoAliases = <String>{
      if (resumeId != null) PlaybackIdentityStorage.requiresExactProgressIdentity(stableId)
          ? 'video_${stableId}_${resumeId.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}'
          : alias('video', resumeId),
    };
    if (stableId != null && stableId.isNotEmpty) {
      if (seriesTitle == null) {
        keys.add(WebDavSyncRecordKey.finishedMovie(stableId));
        keys.add(WebDavSyncRecordKey.playback('imdb:$stableId'));
      }
      for (final entry in map.entries) {
        final value = entry.value;
        if (value is! Map ||
            value['imdbId']?.toString().trim().toLowerCase() != stableId) {
          continue;
        }
        if (value['type'] == 'series' && seriesTitle != null) {
          seriesAliases.add(entry.key);
        } else if (value['type'] == 'video' && seriesTitle == null) {
          videoAliases.add(entry.key);
        }
      }
    }
    for (final key in seriesAliases) {
      if (season == null || episode == null) continue;
      keys.addAll({
        WebDavSyncRecordKey.playbackMeta(key),
        WebDavSyncRecordKey.playbackEpisode(key, season, episode),
        WebDavSyncRecordKey.playbackFinished(key, season, episode),
        if (stableId != null) ...{
          WebDavSyncRecordKey.playbackEpisode(
            'imdb:$stableId',
            season,
            episode,
          ),
          WebDavSyncRecordKey.playbackFinished(
            'imdb:$stableId',
            season,
            episode,
          ),
        },
      });
      final state =
          map[key]?['seasons']?[season.toString()]?[episode.toString()];
      if (newerPosition(
        state,
        WebDavSyncRecordKey.playbackEpisode(key, season, episode),
      )) {
        return true;
      }
    }
    for (final key in videoAliases) {
      keys.add(WebDavSyncRecordKey.playback(key));
      final state = map[key];
      if (newerPosition(state, WebDavSyncRecordKey.playback(key))) {
        return true;
      }
    }
    return await PlaybackRecoveryIntent.hasNewer(keys, checkpointAtMs) ||
        await WebDavSyncTombstoneRecorder.hasNewerPlaybackIntent(
          keys,
          checkpointAtMs,
          includePositions: includeSyncedPositions,
          isOwnRecoveryWrite: (key, payload) =>
              ownRecoveryKeys.contains(key) &&
              (matchesRecoveryPosition?.call(payload) ?? false),
        );
  }

  static Future<void> saveSeriesPlaybackState({
    required String seriesTitle,
    required int season,
    required int episode,
    required int positionMs,
    required int durationMs,
    double speed = 1.0,
    String aspect = 'contain',
    String? imdbId,
    String? recoveryCheckpointId,
    int? recoveryUpdatedAtMs,
  }) async {
    final map = await PlaybackStateStore.getPlaybackStateMap();
    final key = PlaybackIdentityStorage.seriesProgressKey(seriesTitle, imdbId);

    if (!map.containsKey(key)) {
      map[key] = {'type': 'series', 'title': seriesTitle, 'seasons': {}};
    }

    final seriesData = map[key] as Map<String, dynamic>;

    // Store IMDB ID if provided (enables lookup by IMDB ID)
    if (imdbId != null && imdbId.isNotEmpty) {
      seriesData['imdbId'] = imdbId;
    }
    if (!seriesData['seasons'].containsKey(season.toString())) {
      seriesData['seasons'][season.toString()] = {};
    }

    seriesData['seasons'][season.toString()][episode.toString()] = {
      'positionMs': positionMs,
      'durationMs': durationMs,
      'speed': speed,
      'aspect': aspect,
      'updatedAt': recoveryUpdatedAtMs ?? DateTime.now().millisecondsSinceEpoch,
      if (recoveryCheckpointId != null)
        'recoveryCheckpointId': recoveryCheckpointId,
    };

    debugPrint(
      'StorageService: saveSeriesPlaybackState title="$seriesTitle" S${season}E$episode position=${positionMs}ms duration=${durationMs}ms',
    );

    await PlaybackStateStore.savePlaybackStateMap(map);
  }

  /// Mark an episode as finished (watched completely)
  static Future<void> markEpisodeAsFinished({
    required String seriesTitle,
    required int season,
    required int episode,
    String? imdbId,
    int? recoveryUpdatedAtMs,
  }) async {
    // Recovery is a historical observation, not a new playback event. Both
    // records must keep its original time so the latest episode remains last.
    final completedAtMs =
        recoveryUpdatedAtMs ?? DateTime.now().millisecondsSinceEpoch;
    final map = await PlaybackStateStore.getPlaybackStateMap();
    final key = PlaybackIdentityStorage.seriesProgressKey(seriesTitle, imdbId);

    if (!map.containsKey(key)) {
      map[key] = {
        'type': 'series',
        'title': seriesTitle,
        'seasons': {},
        'finishedEpisodes': {},
      };
    }

    final seriesData = map[key] as Map<String, dynamic>;

    // Store IMDB ID if provided
    if (imdbId != null && imdbId.isNotEmpty) {
      seriesData['imdbId'] = imdbId;
    }

    // Ensure seasons map exists
    if (!seriesData.containsKey('seasons')) {
      seriesData['seasons'] = {};
    }

    // Ensure finishedEpisodes map exists
    if (!seriesData.containsKey('finishedEpisodes')) {
      seriesData['finishedEpisodes'] = {};
    }

    if (!seriesData['finishedEpisodes'].containsKey(season.toString())) {
      seriesData['finishedEpisodes'][season.toString()] = {};
    }

    seriesData['finishedEpisodes'][season.toString()][episode.toString()] = {
      'finishedAt': completedAtMs,
    };

    // Also add/update in seasons map so it appears in getEpisodeProgress()
    // This ensures UI can find the episode even if it was never played
    if (!seriesData['seasons'].containsKey(season.toString())) {
      seriesData['seasons'][season.toString()] = {};
    }

    final episodeData =
        seriesData['seasons'][season.toString()][episode.toString()];

    if (episodeData == null) {
      // Episode was never played - add dummy data to mark as watched
      seriesData['seasons'][season.toString()][episode.toString()] = {
        'positionMs': 0,
        'durationMs': 1,
        'speed': 1.0,
        'aspect': 'contain',
        'updatedAt': completedAtMs,
      };
    } else {
      // Episode has existing progress - update it to show as finished
      // Set position = duration to show 100% progress
      final existingData = episodeData as Map<String, dynamic>;
      // A later rewatch can already be saved while the older watched marker
      // is still pending. Preserve that newer bookmark when filling the gap.
      if (recoveryUpdatedAtMs == null ||
          (existingData['updatedAt'] as num? ?? 0) <= completedAtMs) {
        final durationMs = existingData['durationMs'] as int? ?? 1;
        existingData['positionMs'] = durationMs; // Mark as fully watched
        existingData['updatedAt'] = completedAtMs;
        existingData.remove('recoveryCheckpointId');
      }
    }

    debugPrint(
      'StorageService: markEpisodeAsFinished title="$seriesTitle" S${season}E$episode',
    );

    await PlaybackStateStore.savePlaybackStateMap(map);
    localCompletionRevision.value++;
  }

  /// Unmark an episode as finished (mark as unwatched)
  static Future<void> unmarkEpisodeAsFinished({
    required String seriesTitle,
    required int season,
    required int episode,
    String? imdbId,
  }) async {
    final map = await PlaybackStateStore.getPlaybackStateMap();
    final currentTitleKey = PlaybackIdentityStorage.seriesProgressKey(seriesTitle, imdbId);
    final normalizedImdbId = imdbId?.trim().toLowerCase();
    final stableImdbId = normalizedImdbId == null || normalizedImdbId.isEmpty
        ? null
        : normalizedImdbId;
    var changed = false;
    var aliasesChanged = 0;

    for (final entry in map.entries) {
      final seriesData = entry.value;
      if (seriesData is! Map<String, dynamic> ||
          seriesData['type'] != 'series') {
        continue;
      }
      final storedImdbId = seriesData['imdbId']
          ?.toString()
          .trim()
          .toLowerCase();
      final matchesCurrentTitle = entry.key == currentTitleKey;
      final matchesStableId =
          stableImdbId != null && storedImdbId == stableImdbId;
      if (!matchesCurrentTitle && !matchesStableId) continue;

      if (_clearEpisodeCompletion(
        seriesData: seriesData,
        season: season,
        episode: episode,
      )) {
        changed = true;
        aliasesChanged++;
      }
    }

    if (!changed) return;

    debugPrint(
      'StorageService: unmarkEpisodeAsFinished title="$seriesTitle" '
      'S${season}E$episode aliases=$aliasesChanged',
    );

    await PlaybackStateStore.savePlaybackStateMap(map, recordDeletions: true);
    localCompletionRevision.value++;
  }

  /// Clear every completed episode owned by a stable series identity.
  ///
  /// This is the local equivalent of removing a show from tracker history.
  /// Synthetic watched rows and completed checkpoints are cleared across all
  /// release-title aliases, while genuine partial rewatch progress survives.
  static Future<void> unmarkSeriesAsFinished(
    String imdbId, {
    String? seriesTitle,
  }) async {
    final normalized = imdbId.trim().toLowerCase();
    if (normalized.isEmpty) return;
    final normalizedTitle = seriesTitle?.trim().toLowerCase();
    final map = await PlaybackStateStore.getPlaybackStateMap();
    var changed = false;

    for (final raw in map.values) {
      if (raw is! Map<String, dynamic> || raw['type'] != 'series') continue;
      final storedId = raw['imdbId']?.toString().trim().toLowerCase();
      final storedTitle = raw['title']?.toString().trim().toLowerCase();
      final matchesStableId = storedId == normalized;
      final matchesLegacyTitle =
          !PlaybackIdentityStorage.requiresExactProgressIdentity(normalized) &&
          !PlaybackIdentityStorage.requiresExactProgressIdentity(storedId) &&
          normalizedTitle != null &&
          normalizedTitle.isNotEmpty &&
          storedTitle == normalizedTitle;
      if (!matchesStableId && !matchesLegacyTitle) continue;

      final coordinates = <({int season, int episode})>{};
      void collect(Object? seasons) {
        if (seasons is! Map) return;
        for (final seasonEntry in seasons.entries) {
          final season = int.tryParse(seasonEntry.key.toString());
          final episodes = seasonEntry.value;
          if (season == null || episodes is! Map) continue;
          for (final episodeKey in episodes.keys) {
            final episode = int.tryParse(episodeKey.toString());
            if (episode != null) {
              coordinates.add((season: season, episode: episode));
            }
          }
        }
      }

      collect(raw['finishedEpisodes']);
      collect(raw['seasons']);
      for (final coordinate in coordinates) {
        if (_clearEpisodeCompletion(
          seriesData: raw,
          season: coordinate.season,
          episode: coordinate.episode,
        )) {
          changed = true;
        }
      }
    }

    if (!changed) return;
    await PlaybackStateStore.savePlaybackStateMap(map, recordDeletions: true);
    localCompletionRevision.value++;
    debugPrint('StorageService: unmarkSeriesAsFinished imdbId="$normalized"');
  }

  /// Remove one episode's explicit completion and any synthetic/completed
  /// progress produced by marking it watched. Genuine partial progress remains
  /// intact, including a rewatch in progress under another title alias.
  static bool _clearEpisodeCompletion({
    required Map<String, dynamic> seriesData,
    required int season,
    required int episode,
  }) {
    final seasonKey = season.toString();
    final episodeKey = episode.toString();
    var changed = false;

    final finishedEpisodes = seriesData['finishedEpisodes'];
    if (finishedEpisodes is Map) {
      final seasonData = finishedEpisodes[seasonKey];
      if (seasonData is Map && seasonData.containsKey(episodeKey)) {
        seasonData.remove(episodeKey);
        if (seasonData.isEmpty) finishedEpisodes.remove(seasonKey);
        changed = true;
      }
    }

    final seasons = seriesData['seasons'];
    if (seasons is! Map) return changed;
    final seasonData = seasons[seasonKey];
    if (seasonData is! Map) return changed;
    final episodeData = seasonData[episodeKey];
    if (episodeData is! Map) return changed;

    final positionMs = (episodeData['positionMs'] as num?)?.toInt() ?? 0;
    final durationMs = (episodeData['durationMs'] as num?)?.toInt() ?? 0;
    final isDummy = positionMs == 0 && durationMs == 1;
    final isCompleted = durationMs > 0 && positionMs >= durationMs;
    // Unwatching a fully-watched episode DROPS its row. Zeroing the offset
    // instead used to leave a "played, 0% in, not finished" ghost carrying a
    // fresh updatedAt, which then won `getLastPlayedEpisode*` and pinned
    // Continue Watching to an episode the user had just declared unwatched —
    // and every repeat of mark→unmark re-stamped it fresher.
    if (isDummy || isCompleted) {
      seasonData.remove(episodeKey);
      if (seasonData.isEmpty) seasons.remove(seasonKey);
      return true;
    }
    // Reached only for rows that were never marked watched through
    // [markEpisodeAsFinished] (it overwrites positionMs with durationMs, so a
    // marked row always lands in the branch above). A genuine partial — e.g. a
    // rewatch in progress under another title alias, swept by
    // [unmarkSeriesAsFinished] — keeps its offset.
    return changed;
  }

  /// Check if an episode is marked as finished
  static Future<bool> isEpisodeFinished({
    required String seriesTitle,
    required int season,
    required int episode,
    String? imdbId,
  }) async {
    final map = await PlaybackStateStore.getPlaybackStateMap();
    final currentTitleKey = PlaybackIdentityStorage.seriesProgressKey(seriesTitle, imdbId);
    final normalizedImdbId = imdbId?.trim().toLowerCase();
    final stableImdbId = normalizedImdbId == null || normalizedImdbId.isEmpty
        ? null
        : normalizedImdbId;

    for (final entry in map.entries) {
      final seriesData = entry.value;
      if (seriesData is! Map<String, dynamic> ||
          seriesData['type'] != 'series') {
        continue;
      }
      final matchesCurrentTitle = entry.key == currentTitleKey;
      final storedImdbId = seriesData['imdbId']
          ?.toString()
          .trim()
          .toLowerCase();
      final matchesStableId =
          stableImdbId != null && storedImdbId == stableImdbId;
      if (!matchesCurrentTitle && !matchesStableId) continue;

      final finishedEpisodes = seriesData['finishedEpisodes'];
      if (finishedEpisodes is! Map) continue;
      final seasonData = finishedEpisodes[season.toString()];
      if (seasonData is Map && seasonData.containsKey(episode.toString())) {
        return true;
      }
    }
    return false;
  }

  /// Get all finished episodes for a series
  static Future<Map<String, Set<int>>> getFinishedEpisodes({
    required String seriesTitle,
  }) async {
    final map = await PlaybackStateStore.getPlaybackStateMap();
    final key =
        'series_${seriesTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

    final seriesData = map[key];
    if (seriesData == null || seriesData['type'] != 'series') return {};

    final finishedEpisodes = seriesData['finishedEpisodes'];
    if (finishedEpisodes == null) return {};

    final result = <String, Set<int>>{};

    for (final seasonEntry in finishedEpisodes.entries) {
      final season = seasonEntry.key;
      final episodes = seasonEntry.value as Map<String, dynamic>;
      result[season] = episodes.keys.map((e) => int.parse(e)).toSet();
    }

    return result;
  }

  /// Resolve finished episodes by stable title identity, falling back to the
  /// historical title-keyed record for installs created before IMDb IDs were
  /// persisted with series playback.
  static Future<Map<String, Set<int>>> getFinishedEpisodesByImdbId({
    required String imdbId,
    String? seriesTitle,
  }) async {
    final normalized = imdbId.trim().toLowerCase();
    final map = await PlaybackStateStore.getPlaybackStateMap();
    final result = <String, Set<int>>{};
    for (final raw in map.values) {
      if (raw is! Map<String, dynamic> || raw['type'] != 'series') continue;
      final storedId = raw['imdbId']?.toString().trim().toLowerCase();
      if (storedId != normalized) continue;
      final finished = raw['finishedEpisodes'];
      if (finished is! Map) continue;
      for (final entry in finished.entries) {
        final episodes = entry.value;
        if (episodes is! Map) continue;
        result.putIfAbsent(entry.key.toString(), () => <int>{}).addAll({
          for (final episode in episodes.keys)
            if (int.tryParse(episode.toString()) case final value?) value,
        });
      }
    }
    if (result.isNotEmpty) return result;
    if (!PlaybackIdentityStorage.requiresExactProgressIdentity(imdbId) && seriesTitle != null && seriesTitle.isNotEmpty) {
      // Only ID-less legacy records may provide title fallback. A matching
      // display title does not make another IMDb series the same show.
      final index = await getFinishedSeriesEpisodeIndex();
      return index['title:${seriesTitle.trim().toLowerCase()}'] ?? {};
    }
    return {};
  }

  /// One-pass index for derived series completion. IMDb keys are preferred;
  /// title keys preserve older playback records that predate stable IDs.
  static Future<Map<String, Map<String, Set<int>>>>
  getFinishedSeriesEpisodeIndex() async {
    final map = await PlaybackStateStore.getPlaybackStateMap();
    final result = <String, Map<String, Set<int>>>{};
    for (final raw in map.values) {
      if (raw is! Map<String, dynamic> || raw['type'] != 'series') continue;
      final finished = raw['finishedEpisodes'];
      if (finished is! Map) continue;
      final parsed = <String, Set<int>>{
        for (final entry in finished.entries)
          entry.key.toString(): {
            if (entry.value is Map)
              for (final episode in (entry.value as Map).keys)
                if (int.tryParse(episode.toString()) case final value?) value,
          },
      };
      void mergeInto(String key) {
        final target = result.putIfAbsent(key, () => <String, Set<int>>{});
        for (final season in parsed.entries) {
          target.putIfAbsent(season.key, () => <int>{}).addAll(season.value);
        }
      }

      final imdbId = raw['imdbId']?.toString().trim().toLowerCase();
      if (imdbId != null && imdbId.isNotEmpty) {
        mergeInto(imdbId);
        continue;
      }
      final title = raw['title']?.toString().trim().toLowerCase();
      if (title != null && title.isNotEmpty) mergeInto('title:$title');
    }
    return result;
  }

  /// Get episode progress for a series
  static Future<Map<String, Map<String, dynamic>>> getEpisodeProgress({
    required String seriesTitle,
  }) async {
    final map = await PlaybackStateStore.getPlaybackStateMap();
    final key =
        'series_${seriesTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

    final seriesData = map[key];
    if (seriesData == null || seriesData['type'] != 'series') return {};

    final seasons = seriesData['seasons'];
    if (seasons == null) return {};

    final result = <String, Map<String, dynamic>>{};

    for (final seasonEntry in seasons.entries) {
      final season = seasonEntry.key;
      final episodes = seasonEntry.value as Map<String, dynamic>;

      for (final episodeEntry in episodes.entries) {
        final episode = episodeEntry.key;
        final episodeData = episodeEntry.value as Map<String, dynamic>;
        final episodeKey = '${season}_$episode';
        result[episodeKey] = episodeData;
      }
    }

    return result;
  }

  // v2: keyed by IMDb id (stable, unambiguous) instead of the normalized series
  // title. Title-keying silently broke the playlist bars whenever the writer's
  // and readers' title derivations diverged; the seed and every reader always
  // have the show's IMDb id, so we key on that. Bumped from _v1 so stale
  // title-keyed data is dropped (it re-seeds on the next series launch).
  static const String _episodeTraktProgressKey = 'episode_trakt_progress_v2';

  /// Normalized storage key for the per-episode Trakt store (keyed by IMDb id).
  static String _episodeTraktKeyFor(String imdbId) =>
      'imdb_${imdbId.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

  /// Cross-device Trakt playback progress per episode (percent, 0–100), kept
  /// SEPARATE from the ms-based resume state. It drives the playlist progress
  /// bars only — never a resume seek directly (the players convert % → ms at
  /// play time once the real duration is known, so we never store a fake
  /// position). Keyed by the show's IMDb id; episode keys are "season_episode".
  static Future<Map<String, double>> getEpisodeTraktProgress({
    required String imdbId,
  }) async {
    if (imdbId.isEmpty) return {};
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_episodeTraktProgressKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = await decodeJsonAsync(raw);
      if (decoded is! Map) return {};
      final series = decoded[_episodeTraktKeyFor(imdbId)];
      if (series is! Map) return {};
      final out = <String, double>{};
      series.forEach((k, v) {
        final p = (v as num?)?.toDouble();
        if (p != null) out[k.toString()] = p;
      });
      return out;
    } catch (_) {
      return {};
    }
  }

  /// Replace the stored Trakt per-episode percents for the show [imdbId].
  /// [percents] is keyed by "season_episode".
  static Future<void> saveEpisodeTraktProgress({
    required String imdbId,
    required Map<String, double> percents,
  }) => _saveEpisodeTrackerProgress(
    storeKey: _episodeTraktProgressKey,
    imdbId: imdbId,
    percents: percents,
  );

  // Kept separate from both local playback state and Trakt. This is a
  // replace-on-launch snapshot of Simkl's remote truth, so marking an episode
  // unwatched on Simkl can clear the player tick without mutating local
  // history.
  static const String _episodeSimklProgressKey = 'episode_simkl_progress_v1';

  static String _episodeSimklKeyFor(String imdbId) =>
      'imdb_${imdbId.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

  /// Cross-device Simkl progress per episode (percent, 0–100), keyed by the
  /// show's IMDb id. Episode keys are "season_episode".
  static Future<Map<String, double>> getEpisodeSimklProgress({
    required String imdbId,
  }) async {
    if (imdbId.isEmpty) return {};
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_episodeSimklProgressKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = await decodeJsonAsync(raw);
      if (decoded is! Map) return {};
      final series = decoded[_episodeSimklKeyFor(imdbId)];
      if (series is! Map) return {};
      final out = <String, double>{};
      series.forEach((k, v) {
        final p = (v as num?)?.toDouble();
        if (p != null) out[k.toString()] = p;
      });
      return out;
    } catch (_) {
      return {};
    }
  }

  /// Replace the stored Simkl per-episode snapshot for [imdbId].
  /// [percents] is keyed by "season_episode".
  static Future<void> saveEpisodeSimklProgress({
    required String imdbId,
    required Map<String, double> percents,
  }) => _saveEpisodeTrackerProgress(
    storeKey: _episodeSimklProgressKey,
    imdbId: imdbId,
    percents: percents,
  );

  static const String _episodeMdblistProgressKey =
      'episode_mdblist_progress_v1';

  static Future<Map<String, double>> getEpisodeMdblistProgress({
    required String imdbId,
  }) async {
    if (imdbId.isEmpty) return {};
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_episodeMdblistProgressKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = await decodeJsonAsync(raw);
      if (decoded is! Map) return {};
      final series = decoded[_episodeTraktKeyFor(imdbId)];
      if (series is! Map) return {};
      return {
        for (final entry in series.entries)
          if (entry.value is num)
            entry.key.toString(): (entry.value as num).toDouble(),
      };
    } catch (_) {
      return {};
    }
  }

  /// Player-facing read: never display a departed account's cached snapshot.
  static Future<Map<String, double>> getConnectedEpisodeMdblistProgress({
    required String imdbId,
  }) async {
    if (!await MdblistStorage.hasMdblistCredential()) return {};
    return getEpisodeMdblistProgress(imdbId: imdbId);
  }

  static Future<void> saveEpisodeMdblistProgress({
    required String imdbId,
    required Map<String, double> percents,
  }) => _saveEpisodeTrackerProgress(
    storeKey: _episodeMdblistProgressKey,
    imdbId: imdbId,
    percents: percents,
  );

  /// Replace one show's entry inside a provider's whole-store snapshot.
  /// Capture the originating profile before this operation queues so a profile
  /// switch cannot redirect a delayed write into the newly active profile.
  static Future<void> _saveEpisodeTrackerProgress({
    required String storeKey,
    required String imdbId,
    required Map<String, double> percents,
  }) {
    if (imdbId.isEmpty) return Future.value();
    final normalizedKey = _episodeTraktKeyFor(imdbId);
    final snapshot = Map<String, double>.from(percents);
    final profileScope =
        ProfileRuntime.isInitialized && ProfileRuntime.isProfileCommitted
        ? ProfileRuntime.capture()
        : null;

    Future<void> commit() =>
        _episodeTrackerSnapshotWriteLock.synchronized(() async {
          final prefs = await ProfilePreferences.instance();
          final raw = prefs.getString(storeKey);
          Map<String, dynamic> all = {};
          if (raw != null && raw.isNotEmpty) {
            try {
              final decoded = await decodeJsonAsync(raw);
              if (decoded is Map<String, dynamic>) all = decoded;
            } catch (_) {}
          }
          all[normalizedKey] = snapshot;
          await prefs.setString(storeKey, jsonEncode(all));
        });

    return profileScope == null
        ? commit()
        : ProfileRuntime.withCapturedScope(profileScope, commit);
  }

  /// Get episode progress by IMDB ID (scans playback state for matching imdbId)
  /// Also checks single-file video entries and parses season/episode from title.
  static Future<Map<String, Map<String, dynamic>>> getEpisodeProgressByImdbId(
    String imdbId,
  ) async {
    final map = await PlaybackStateStore.getPlaybackStateMap();
    final normalizedImdbId = imdbId.trim().toLowerCase();

    // Merge every legacy title-keyed series entry with this IMDb id. Older
    // builds could save the same show under multiple release-derived titles;
    // stopping at the first record silently hid episodes from the others.
    final seriesResult = <String, Map<String, dynamic>>{};
    Map<String, dynamic>? videoFallback;
    int videoFallbackUpdatedAt = -1;
    for (final entry in map.values) {
      if (entry is Map<String, dynamic> &&
          entry['imdbId']?.toString().trim().toLowerCase() ==
              normalizedImdbId) {
        if (entry['type'] == 'series') {
          final seasons = entry['seasons'];
          if (seasons is! Map) continue;
          for (final seasonEntry in seasons.entries) {
            final episodes = seasonEntry.value;
            if (episodes is! Map) continue;
            for (final episodeEntry in episodes.entries) {
              final episodeData = episodeEntry.value;
              if (episodeData is! Map) continue;
              final episodeKey = '${seasonEntry.key}_${episodeEntry.key}';
              final candidate = Map<String, dynamic>.from(episodeData);
              final existing = seriesResult[episodeKey];
              final candidateUpdatedAt =
                  (candidate['updatedAt'] as num?)?.toInt() ?? 0;
              final existingUpdatedAt =
                  (existing?['updatedAt'] as num?)?.toInt() ?? -1;
              if (candidateUpdatedAt >= existingUpdatedAt) {
                seriesResult[episodeKey] = candidate;
              }
            }
          }
        } else if (entry['type'] == 'video') {
          final updatedAt = (entry['updatedAt'] as num?)?.toInt() ?? 0;
          if (updatedAt > videoFallbackUpdatedAt) {
            videoFallbackUpdatedAt = updatedAt;
            videoFallback = entry;
          }
        }
      }
    }

    if (seriesResult.isNotEmpty) return seriesResult;

    // Fallback: single-file video entry — parse season/episode from title
    if (videoFallback != null) {
      final title = videoFallback['title'] as String? ?? '';
      final match = RegExp(r'[Ss](\d+)[Ee](\d+)').firstMatch(title);
      if (match != null) {
        final season = int.parse(match.group(1)!).toString();
        final episode = int.parse(match.group(2)!).toString();
        return {
          '${season}_$episode': {
            'positionMs': videoFallback['positionMs'] ?? 0,
            'durationMs': videoFallback['durationMs'] ?? 1,
            'updatedAt': videoFallback['updatedAt'] ?? 0,
          },
        };
      }
    }

    return {};
  }

  /// Merge local episode progress across stable IMDb identity and the current
  /// title-keyed record. The newest update wins duplicate coordinates. Equal
  /// or missing timestamps prefer the current title deterministically, which
  /// preserves legacy behavior without letting an older title record move a
  /// newer cross-alias resume position backwards.
  static Future<Map<String, Map<String, dynamic>>> getMergedEpisodeProgress({
    required String seriesTitle,
    String? imdbId,
  }) async {
    if (PlaybackIdentityStorage.requiresExactProgressIdentity(imdbId) ||
        (imdbId?.startsWith('medialibrary:') ?? false)) {
      return getEpisodeProgressByImdbId(imdbId!);
    }
    final reads = await Future.wait([
      if (imdbId != null && imdbId.isNotEmpty)
        getEpisodeProgressByImdbId(imdbId)
      else
        Future.value(const <String, Map<String, dynamic>>{}),
      if (seriesTitle.isNotEmpty)
        getEpisodeProgress(seriesTitle: seriesTitle)
      else
        Future.value(const <String, Map<String, dynamic>>{}),
    ]);
    int updatedAt(Map<String, dynamic> state) {
      final value = state['updatedAt'];
      if (value is! num || !value.isFinite) return 0;
      final timestamp = value.toInt();
      return timestamp > 0 ? timestamp : 0;
    }

    final merged = Map<String, Map<String, dynamic>>.from(reads[0]);
    for (final entry in reads[1].entries) {
      final previous = merged[entry.key];
      if (previous == null || updatedAt(entry.value) >= updatedAt(previous)) {
        merged[entry.key] = entry.value;
      }
    }
    return merged;
  }

  /// IMDb-aware counterpart to [getFinishedEpisodes], unioning historical
  /// release-title records with the current title record.
  static Future<Map<String, Set<int>>> getMergedFinishedEpisodes({
    required String seriesTitle,
    String? imdbId,
  }) async {
    if (PlaybackIdentityStorage.requiresExactProgressIdentity(imdbId) ||
        (imdbId?.startsWith('medialibrary:') ?? false)) {
      return getFinishedEpisodesByImdbId(imdbId: imdbId!);
    }
    final reads = await Future.wait([
      if (imdbId != null && imdbId.isNotEmpty)
        getFinishedEpisodesByImdbId(imdbId: imdbId)
      else
        Future.value(const <String, Set<int>>{}),
      if (seriesTitle.isNotEmpty)
        getFinishedEpisodes(seriesTitle: seriesTitle)
      else
        Future.value(const <String, Set<int>>{}),
    ]);
    final merged = <String, Set<int>>{};
    for (final snapshot in reads) {
      for (final entry in snapshot.entries) {
        merged.putIfAbsent(entry.key, () => <int>{}).addAll(entry.value);
      }
    }
    return merged;
  }

  /// Get finished episodes for a specific season
  static Future<Set<int>> getFinishedEpisodesForSeason({
    required String seriesTitle,
    required int season,
  }) async {
    final allFinished = await getFinishedEpisodes(seriesTitle: seriesTitle);
    return allFinished[season.toString()] ?? <int>{};
  }

  /// Get playback state for series content
  static Future<Map<String, dynamic>?> getSeriesPlaybackState({
    required String seriesTitle,
    required int season,
    required int episode,
    String? imdbId,
  }) async {
    final map = await PlaybackStateStore.getPlaybackStateMap();
    final key = PlaybackIdentityStorage.seriesProgressKey(seriesTitle, imdbId);

    final seriesData = map[key];
    if (seriesData == null || seriesData['type'] != 'series') return null;

    final seasonData = seriesData['seasons'][season.toString()];
    if (seasonData == null) return null;

    final episodeData = seasonData[episode.toString()];
    if (episodeData == null) return null;

    return episodeData as Map<String, dynamic>;
  }

  /// Save playback state for non-series content (movies, single videos)
  static Future<void> saveVideoPlaybackState({
    required String videoTitle,
    required String videoUrl,
    required int positionMs,
    required int durationMs,
    double speed = 1.0,
    String aspect = 'contain',
    String? imdbId,
    String? recoveryCheckpointId,
    int? recoveryUpdatedAtMs,
  }) async {
    final map = await PlaybackStateStore.getPlaybackStateMap();
    final key = (PlaybackIdentityStorage.requiresExactProgressIdentity(imdbId) ||
            (imdbId?.startsWith('medialibrary:') ?? false))
        ? 'video_${imdbId}_${videoTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}'
        : 'video_${videoTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

    map[key] = {
      'type': 'video',
      'title': videoTitle,
      'url': videoUrl,
      'positionMs': positionMs,
      'durationMs': durationMs,
      'speed': speed,
      'aspect': aspect,
      'updatedAt': recoveryUpdatedAtMs ?? DateTime.now().millisecondsSinceEpoch,
      if (recoveryCheckpointId != null)
        'recoveryCheckpointId': recoveryCheckpointId,
      if (imdbId != null) 'imdbId': imdbId,
    };

    await PlaybackStateStore.savePlaybackStateMap(map);
  }

  /// Get playback state for non-series content
  static Future<Map<String, dynamic>?> getVideoPlaybackState({
    required String videoTitle,
    bool includeFinished = false,
    String? contentIdentity,
  }) async {
    final map = await PlaybackStateStore.getPlaybackStateMap();
    final key = (PlaybackIdentityStorage.requiresExactProgressIdentity(contentIdentity) ||
            (contentIdentity?.startsWith('medialibrary:') ?? false))
        ? 'video_${contentIdentity}_${videoTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}'
        : 'video_${videoTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

    final videoData = map[key];
    if (videoData == null || videoData['type'] != 'video') return null;

    final imdbId = (videoData['imdbId'] as String?)?.trim();
    // A finished movie can have a stale source-specific state from a final
    // autosave tick. Its local completion record wins over that stale resume.
    if (!includeFinished &&
        imdbId != null &&
        imdbId.isNotEmpty &&
        await isMovieFinished(imdbId)) {
      return null;
    }

    return videoData as Map<String, dynamic>;
  }

  /// Get video playback state by IMDB ID (scans all video entries, returns most recent).
  static Future<Map<String, dynamic>?> getVideoPlaybackStateByImdbId(
    String imdbId,
  ) async {
    // A blank id would match every record saved without one and hand back an
    // unrelated movie's position.
    final wanted = imdbId.trim();
    if (wanted.isEmpty) return null;
    // A completion write and the periodic player autosave can overlap by one
    // tick. The finished marker is authoritative for movies, so never expose
    // a stale resume record that slipped back in during that tiny window.
    if (await isMovieFinished(wanted)) return null;
    final map = await PlaybackStateStore.getPlaybackStateMap();
    Map<String, dynamic>? best;
    int bestUpdatedAt = -1;
    for (final entry in map.values) {
      if (entry is! Map<String, dynamic> || entry['type'] != 'video') continue;
      // Pattern-matched, not cast: one malformed legacy record must not throw
      // out of a scan over every saved video.
      final recorded = entry['imdbId'];
      if (recorded is String && recorded.trim() == wanted) {
        final updatedAt = (entry['updatedAt'] as num?)?.toInt() ?? 0;
        if (updatedAt > bestUpdatedAt) {
          bestUpdatedAt = updatedAt;
          best = entry;
        }
      }
    }
    return best;
  }

  /// Get the last played episode for a series
  static Future<Map<String, dynamic>?> getLastPlayedEpisode({
    required String seriesTitle,
  }) async {
    final map = await PlaybackStateStore.getPlaybackStateMap();
    final key =
        'series_${seriesTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

    final seriesData = map[key];
    if (seriesData is! Map || seriesData['type'] != 'series') return null;

    // Find the most recently updated episode. Parse defensively (matching
    // getVideoPlaybackStateByImdbId above): a corrupt or old-schema entry
    // must skip, not throw, on this resume hot path.
    Map<String, dynamic>? lastEpisode;
    int lastUpdated = 0;

    final seasons = seriesData['seasons'];
    if (seasons is! Map) return null;
    for (final seasonEntry in seasons.entries) {
      final season = int.tryParse(seasonEntry.key.toString());
      final episodes = seasonEntry.value;
      if (season == null || episodes is! Map) continue;

      for (final episodeEntry in episodes.entries) {
        final episode = int.tryParse(episodeEntry.key.toString());
        final episodeData = episodeEntry.value;
        if (episode == null || episodeData is! Map) continue;
        final updatedAt = (episodeData['updatedAt'] as num?)?.toInt() ?? 0;

        if (updatedAt > lastUpdated) {
          lastUpdated = updatedAt;
          lastEpisode = {
            'season': season,
            'episode': episode,
            ...Map<String, dynamic>.from(episodeData),
          };
        }
      }
    }

    if (lastEpisode != null) {
      debugPrint(
        'StorageService: getLastPlayedEpisode found S${lastEpisode['season']}E${lastEpisode['episode']} for "$seriesTitle"',
      );
    } else {
      debugPrint(
        'StorageService: getLastPlayedEpisode no episodes for "$seriesTitle"',
      );
    }

    return lastEpisode;
  }

  /// Get all episode watch progress for a series by IMDB ID.
  /// Returns a map of "season-episode" → progress percentage (0-100).
  static Future<Map<String, double>> getEpisodeWatchProgressByImdbId(
    String imdbId,
  ) async {
    final map = await PlaybackStateStore.getPlaybackStateMap();
    final result = <String, double>{};

    // Find ALL series entries with matching imdbId (different season packs may
    // have different title keys). Also track most recent video fallback.
    final seriesEntries = <Map<String, dynamic>>[];
    Map<String, dynamic>? videoFallback;
    int videoFallbackUpdatedAt = -1;
    for (final entry in map.values) {
      if (entry is Map<String, dynamic> && entry['imdbId'] == imdbId) {
        if (entry['type'] == 'series') {
          seriesEntries.add(entry);
        } else if (entry['type'] == 'video') {
          final updatedAt = (entry['updatedAt'] as num?)?.toInt() ?? 0;
          if (updatedAt > videoFallbackUpdatedAt) {
            videoFallbackUpdatedAt = updatedAt;
            videoFallback = entry;
          }
        }
      }
    }

    // Fallback: single-file video entry — parse season/episode from title
    if (seriesEntries.isEmpty && videoFallback != null) {
      final title = videoFallback['title'] as String? ?? '';
      final match = RegExp(r'[Ss](\d+)[Ee](\d+)').firstMatch(title);
      if (match != null) {
        final season = int.parse(match.group(1)!).toString();
        final episode = int.parse(match.group(2)!).toString();
        final posMs = (videoFallback['positionMs'] as num?)?.toInt() ?? 0;
        final durMs = (videoFallback['durationMs'] as num?)?.toInt() ?? 1;
        if (durMs > 0 && posMs > 0) {
          result['$season-$episode'] = (posMs / durMs * 100).clamp(0.0, 100.0);
        }
        return result;
      }
    }

    if (seriesEntries.isEmpty) return result;

    // Aggregate progress across ALL matching series entries
    for (final seriesData in seriesEntries) {
      final finishedMap =
          seriesData['finishedEpisodes'] as Map<String, dynamic>?;

      final seasons = seriesData['seasons'] as Map<String, dynamic>? ?? {};
      for (final seasonEntry in seasons.entries) {
        final seasonNum = seasonEntry.key;
        final episodes = seasonEntry.value as Map<String, dynamic>? ?? {};

        // Get finished episodes for this season
        final finishedEps = finishedMap?[seasonNum] as Map<String, dynamic>?;

        for (final episodeEntry in episodes.entries) {
          final epNum = episodeEntry.key;
          final epData = episodeEntry.value as Map<String, dynamic>;
          final key = '$seasonNum-$epNum';

          // Check if finished first
          if (finishedEps != null && finishedEps.containsKey(epNum)) {
            result[key] = 100.0;
            continue;
          }

          final positionMs = (epData['positionMs'] as num?)?.toInt() ?? 0;
          final durationMs = (epData['durationMs'] as num?)?.toInt() ?? 1;
          if (durationMs > 0 && positionMs > 0) {
            final progress = (positionMs / durationMs * 100).clamp(0.0, 100.0);
            // Keep higher progress if duplicate across entries
            if (!result.containsKey(key) || progress > result[key]!) {
              result[key] = progress;
            }
          }
        }
      }
    }

    return result;
  }

  /// Look up the last played episode by IMDB ID.
  /// Scans all series entries for a matching imdbId field.
  /// Also checks single-file video entries (type=video) as a fallback,
  /// parsing season/episode from the title.
  static Future<Map<String, dynamic>?> getLastPlayedEpisodeByImdbId(
    String imdbId,
  ) async {
    final map = await PlaybackStateStore.getPlaybackStateMap();

    // Find ALL series entries with matching imdbId (different season packs may
    // have different title keys, e.g. "young sheldon (2017)" vs "young sheldon").
    // Also track most recent video fallback.
    final seriesEntries = <Map<String, dynamic>>[];
    Map<String, dynamic>? videoFallback;
    int videoFallbackUpdatedAt = -1;
    for (final entry in map.values) {
      if (entry is Map<String, dynamic> && entry['imdbId'] == imdbId) {
        if (entry['type'] == 'series') {
          seriesEntries.add(entry);
        } else if (entry['type'] == 'video') {
          final updatedAt = (entry['updatedAt'] as num?)?.toInt() ?? 0;
          if (updatedAt > videoFallbackUpdatedAt) {
            videoFallbackUpdatedAt = updatedAt;
            videoFallback = entry;
          }
        }
      }
    }

    if (seriesEntries.isNotEmpty) {
      // Find most recently updated episode across ALL matching series entries
      Map<String, dynamic>? lastEpisode;
      Map<String, dynamic>?
      lastEpisodeSeriesData; // track which entry it came from
      int lastUpdated = 0;

      for (final seriesData in seriesEntries) {
        final seasons = seriesData['seasons'] as Map<String, dynamic>? ?? {};
        for (final seasonEntry in seasons.entries) {
          final season = int.parse(seasonEntry.key);
          final episodes = seasonEntry.value as Map<String, dynamic>;

          for (final episodeEntry in episodes.entries) {
            final episode = int.parse(episodeEntry.key);
            final episodeData = episodeEntry.value as Map<String, dynamic>;
            final updatedAt = (episodeData['updatedAt'] as num?)?.toInt() ?? 0;

            if (updatedAt > lastUpdated) {
              lastUpdated = updatedAt;
              lastEpisode = {
                'season': season,
                'episode': episode,
                ...episodeData,
              };
              lastEpisodeSeriesData = seriesData;
            }
          }
        }
      }

      if (lastEpisode != null && lastEpisodeSeriesData != null) {
        // Check if this episode is marked as finished (in its own series entry)
        final finishedEpisodes =
            lastEpisodeSeriesData['finishedEpisodes'] as Map<String, dynamic>?;
        if (finishedEpisodes != null) {
          final seasonFinished =
              finishedEpisodes[lastEpisode['season'].toString()]
                  as Map<String, dynamic>?;
          if (seasonFinished != null &&
              seasonFinished.containsKey(lastEpisode['episode'].toString())) {
            lastEpisode['finished'] = true;
          }
        }
        debugPrint(
          'StorageService: getLastPlayedEpisodeByImdbId found S${lastEpisode['season']}E${lastEpisode['episode']} for "$imdbId"${lastEpisode['finished'] == true ? ' (finished)' : ''}',
        );
      }
      return lastEpisode;
    }

    // Fallback: single-file video entry — parse season/episode from title
    if (videoFallback != null) {
      final title = videoFallback['title'] as String? ?? '';
      final match = RegExp(r'[Ss](\d+)[Ee](\d+)').firstMatch(title);
      if (match != null) {
        final season = int.parse(match.group(1)!);
        final episode = int.parse(match.group(2)!);
        debugPrint(
          'StorageService: getLastPlayedEpisodeByImdbId (video fallback) parsed S${season}E$episode from "$title" for "$imdbId"',
        );
        return {
          'season': season,
          'episode': episode,
          'positionMs': videoFallback['positionMs'] ?? 0,
          'durationMs': videoFallback['durationMs'] ?? 1,
          'updatedAt': videoFallback['updatedAt'] ?? 0,
        };
      }
    }

    return null;
  }

  /// Clean up old playback state data (older than 30 days)
  static Future<void> cleanupOldPlaybackState() async {
    final map = await PlaybackStateStore.getPlaybackStateMap();
    final now = DateTime.now().millisecondsSinceEpoch;
    final thirtyDaysAgo = now - (30 * 24 * 60 * 60 * 1000);

    final keysToRemove = <String>[];

    for (final entry in map.entries) {
      final data = entry.value as Map<String, dynamic>;
      final updatedAt = data['updatedAt'] as int?;

      if (updatedAt != null && updatedAt < thirtyDaysAgo) {
        keysToRemove.add(entry.key);
      }
    }

    for (final key in keysToRemove) {
      map.remove(key);
    }

    if (keysToRemove.isNotEmpty) {
      await PlaybackStateStore.savePlaybackStateMap(map, recordDeletions: true);
    }
  }

  /// Clear all playback-related data (series and video states, track prefs, legacy resume)
  /// [recordSyncDeletions] distinguishes a deliberate clear (default, which
  /// deletes on every synced device) from a device-local wipe such as app
  /// reset, which must never mint circle-wide deletions.
  static Future<void> clearAllPlaybackData({
    bool recordSyncDeletions = true,
  }) async {
    final prefs = await ProfilePreferences.instance();
    // Device-local clears must invalidate native recovery too, without
    // publishing a deletion to the user's other devices.
    await PlaybackRecoveryIntent.recordClearAll();
    await PlaybackStateStore.savePlaybackStateMap(
      <String, dynamic>{},
      recordDeletions: recordSyncDeletions,
    );
    if (recordSyncDeletions) {
      final finishedMovies = await _getFinishedMovieIds();
      await WebDavSyncTombstoneRecorder.recordForCurrentProfile(
        finishedMovies.map(WebDavSyncRecordKey.finishedMovie),
      );
    }
    await prefs.remove(_finishedMoviesKey);
    await prefs.remove(localSeriesCompletionStateKey);
    await prefs.remove(localSeriesCalendarCheckedAtKey);
    await prefs.remove(localSeriesCalendarAttemptedAtKey);
    localCompletionRevision.value++;
    // Resume lives in the DB now; the prefs key only still exists for users
    // who wipe before the one-time import has run.
    await prefs.remove(_videoResumeKey);
    await IptvMediaStore.clearVideoResume(
      origin: recordSyncDeletions
          ? WebDavSyncMutationOrigin.user
          : WebDavSyncMutationOrigin.maintenance,
    );
    debugPrint(
      'StorageService: cleared playback state, completed movies, and video resume data',
    );
  }

  /// Clear all progress data for a specific playlist/series
  static Future<void> clearPlaylistProgress({required String title}) async {
    final map = await PlaybackStateStore.getPlaybackStateMap();

    debugPrint('StorageService: clearPlaylistProgress called for "$title"');

    final keysToRemove = <String>[];

    // Use the SAME matching logic as when finding series progress
    // Try multiple title variations to find all matching entries

    // Variation 1: Use the full playlist item title
    final fullTitleKey =
        'series_${title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';
    final fullVideoKey =
        'video_${title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

    // Variation 2: Try extracting clean title (like "breaking bad" from "Breaking.Bad.SEASON.01.S01...")
    // This matches how SeriesPlaylist extracts the title
    String cleanedTitle = title;

    // Remove common patterns to extract series name
    cleanedTitle = cleanedTitle.replaceAll(
      RegExp(r'\.S\d{2}.*', caseSensitive: false),
      '',
    ); // Remove S01-S08 and everything after
    cleanedTitle = cleanedTitle.replaceAll(
      RegExp(r'\.Season\..*', caseSensitive: false),
      '',
    ); // Remove Season.1-8
    cleanedTitle = cleanedTitle.replaceAll(
      RegExp(r'\.(1080p|720p|2160p|4k).*', caseSensitive: false),
      '',
    ); // Remove quality
    cleanedTitle = cleanedTitle.replaceAll(
      RegExp(r'\.(x264|x265|h264|h265).*', caseSensitive: false),
      '',
    ); // Remove codec
    cleanedTitle = cleanedTitle.replaceAll(
      RegExp(r'\.(BluRay|WEB|HDTV|WEBRip).*', caseSensitive: false),
      '',
    ); // Remove source
    cleanedTitle = cleanedTitle.replaceAll('.', ' ').trim();

    final cleanTitleKey =
        'series_${cleanedTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';
    final cleanVideoKey =
        'video_${cleanedTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

    debugPrint(
      'StorageService: checking keys - full: $fullTitleKey / $fullVideoKey, clean: $cleanTitleKey / $cleanVideoKey',
    );
    debugPrint('StorageService: available keys: ${map.keys.toList()}');

    // Check for exact key matches first
    for (final key in [
      cleanTitleKey,
      cleanVideoKey,
      fullTitleKey,
      fullVideoKey,
    ]) {
      if (map.containsKey(key) && !keysToRemove.contains(key)) {
        keysToRemove.add(key);
        debugPrint('StorageService: exact key match: "$key"');
      }
    }

    // Fallback: Search through all series/video entries
    // Check if the input title contains the stored series title
    // This handles cases where playlist title is "Game of Thrones - Season 3" but stored title is "game of thrones"
    for (final entry in map.entries) {
      if ((entry.key.startsWith('series_') || entry.key.startsWith('video_')) &&
          entry.value is Map<String, dynamic> &&
          !keysToRemove.contains(entry.key)) {
        final storedTitle =
            (entry.value['title'] as String?)?.toLowerCase() ?? '';
        if (storedTitle.isEmpty) continue;

        final titleLower = title.toLowerCase();
        final cleanedTitleLower = cleanedTitle.toLowerCase();

        // Check if the stored series title matches in several ways:
        // 1. Exact match with cleaned title (e.g., "game of thrones" == "game of thrones")
        // 2. Input title contains the stored series title (e.g., "game of thrones - season 3" contains "game of thrones")
        // 3. Cleaned title contains the stored series title
        if (storedTitle == cleanedTitleLower ||
            storedTitle == titleLower ||
            (titleLower.contains(storedTitle) &&
                storedTitle.split(' ').length >= 2)) {
          keysToRemove.add(entry.key);
          debugPrint(
            'StorageService: stored title match - key: "${entry.key}", storedTitle: "$storedTitle"',
          );
        }
      }
    }

    // Remove all matching keys
    for (final key in keysToRemove) {
      map.remove(key);
      debugPrint('StorageService: removed progress entry with key: "$key"');
    }

    // Save the updated map if anything was removed
    if (keysToRemove.isNotEmpty) {
      await PlaybackStateStore.savePlaybackStateMap(map, recordDeletions: true);
      // Finished episodes live in this same map. Re-derive local series
      // completion so watched badges and Continue Watching update immediately.
      localCompletionRevision.value++;
      debugPrint(
        'StorageService: clearPlaylistProgress completed - removed ${keysToRemove.length} entries for "$title"',
      );
    } else {
      debugPrint('StorageService: no progress data found for "$title"');
    }
  }

  // Video resume — one row per item in debrify_tv.db (see IptvMediaStore).
  static Future<Map<String, dynamic>?> getVideoResume(String key) {
    return IptvMediaStore.videoResume(key);
  }

  static Future<void> upsertVideoResume(
    String key,
    Map<String, dynamic> entry, {
    String? sourceId,
    WebDavSyncMutationOrigin origin = WebDavSyncMutationOrigin.user,
  }) {
    return IptvMediaStore.upsertVideoResume(
      key,
      entry,
      sourceId: sourceId,
      origin: origin,
    );
  }

  static Future<void> removeVideoResume(
    String key, {
    bool playbackCheckpoint = false,
    WebDavSyncMutationOrigin origin = WebDavSyncMutationOrigin.user,
  }) {
    return IptvMediaStore.removeVideoResume(
      key,
      origin: origin,
      playbackCheckpoint: playbackCheckpoint,
    );
  }

  // Debrify TV settings methods
  static Future<String> getDebrifyTvProvider() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_debrifyTvProviderKey) ?? 'real_debrid';
  }

  static Future<void> saveDebrifyTvProvider(String value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_debrifyTvProviderKey, value);
  }

  static Future<bool> hasDebrifyTvProvider() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.containsKey(_debrifyTvProviderKey);
  }

  static Future<bool> getDebrifyTvStartRandom() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_debrifyTvStartRandomKey) ?? true;
  }

  static Future<void> saveDebrifyTvStartRandom(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_debrifyTvStartRandomKey, value);
  }

  static int _normalizeDebrifyTvRandomStartPercent(int? value) {
    final candidate = value ?? _debrifyTvRandomStartPercentDefault;
    if (candidate < _debrifyTvRandomStartPercentMin) {
      return _debrifyTvRandomStartPercentMin;
    }
    if (candidate > _debrifyTvRandomStartPercentMax) {
      return _debrifyTvRandomStartPercentMax;
    }
    return candidate;
  }

  static Future<int> getDebrifyTvRandomStartPercent() async {
    final prefs = await ProfilePreferences.instance();
    final stored = prefs.getInt(_debrifyTvRandomStartPercentKey);
    return _normalizeDebrifyTvRandomStartPercent(stored);
  }

  static Future<void> saveDebrifyTvRandomStartPercent(int value) async {
    final prefs = await ProfilePreferences.instance();
    final normalized = _normalizeDebrifyTvRandomStartPercent(value);
    await prefs.setInt(_debrifyTvRandomStartPercentKey, normalized);
  }

  static Future<bool> getDebrifyTvHideSeekbar() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_debrifyTvHideSeekbarKey) ?? true;
  }

  static Future<void> saveDebrifyTvHideSeekbar(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_debrifyTvHideSeekbarKey, value);
  }

  static Future<bool> getDebrifyTvShowChannelName() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_debrifyTvShowChannelNameKey) ?? true;
  }

  static Future<void> saveDebrifyTvShowChannelName(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_debrifyTvShowChannelNameKey, value);
  }

  static Future<bool> getDebrifyTvShowVideoTitle() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_debrifyTvShowVideoTitleKey) ?? true;
  }

  static Future<void> saveDebrifyTvShowVideoTitle(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_debrifyTvShowVideoTitleKey, value);
  }

  static Future<bool> getDebrifyTvHideOptions() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_debrifyTvHideOptionsKey) ?? true;
  }

  static Future<void> saveDebrifyTvHideOptions(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_debrifyTvHideOptionsKey, value);
  }

  static Future<bool> getDebrifyTvHideBackButton() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_debrifyTvHideBackButtonKey) ?? true;
  }

  static Future<void> saveDebrifyTvHideBackButton(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_debrifyTvHideBackButtonKey, value);
  }

  static Future<bool> getDebrifyTvAvoidNsfw() async {
    if (!await ProfilePolicyStorage.profileAllowsAdultContent()) return true;
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_debrifyTvAvoidNsfwKey) ?? true; // Default enabled
  }

  static Future<void> saveDebrifyTvAvoidNsfw(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(
      _debrifyTvAvoidNsfwKey,
      await ProfilePolicyStorage.profileAllowsAdultContent() ? value : true,
    );
  }

  static Future<List<Map<String, dynamic>>> getDebrifyTvChannels() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_debrifyTvChannelsKey);
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    try {
      final List<dynamic> list = await decodeJsonAsync(raw) as List<dynamic>;
      return list
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  static Future<void> saveDebrifyTvChannels(
    List<Map<String, dynamic>> channels,
  ) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_debrifyTvChannelsKey, jsonEncode(channels));
  }

  // Playlist storage (local-only MVP)
  static Future<List<Map<String, dynamic>>> getPlaylistItemsRaw() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_playlistKey);
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    try {
      final List<dynamic> list = await decodeJsonAsync(raw);
      return list
          .whereType<Map<String, dynamic>>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  static Future<void> savePlaylistItemsRaw(
    List<Map<String, dynamic>> items, {
    bool recordSyncDeletions = true,
    bool Function()? canContinue,
  }) async {
    if (canContinue?.call() == false) return;
    final prefs = await ProfilePreferences.instance();
    if (canContinue?.call() == false) return;
    if (recordSyncDeletions) {
      final previous = await getPlaylistItemsRaw();
      if (canContinue?.call() == false) return;
      final retained = items.map(computePlaylistDedupeKey).toSet();
      await WebDavSyncTombstoneRecorder.recordForCurrentProfile(
        previous
            .map(computePlaylistDedupeKey)
            .where((key) => !retained.contains(key))
            .map(WebDavSyncRecordKey.playlistItem),
      );
    }
    await prefs.setString(
      _playlistKey,
      jsonEncode(items),
      canCommit: canContinue,
    );
  }

  static String computePlaylistDedupeKey(Map<String, dynamic> item) =>
      PlaylistDedupeKey.compute(item);

  /// Add a new playlist item if it does not already exist.
  /// Expected item shape (MVP): { url, title, restrictedLink, rdTorrentId }
  /// Returns true if inserted, false if duplicate.
  static Future<bool> addPlaylistItemRaw(
    Map<String, dynamic> item, {
    bool Function()? canContinue,
  }) async {
    if (canContinue?.call() == false) return false;
    final items = await getPlaylistItemsRaw();
    if (canContinue?.call() == false) return false;
    final initialKey = computePlaylistDedupeKey(item);
    debugPrint('Playlist dedupe: initialKey=$initialKey');
    for (final existing in items) {
      final existingKey = computePlaylistDedupeKey(existing);
      final existingProvider = (existing['provider'] as String?) ?? 'unknown';
      debugPrint(
        'Playlist dedupe: existingKey=$existingKey provider=$existingProvider',
      );
    }
    final initialExists = items.any(
      (entry) => computePlaylistDedupeKey(entry) == initialKey,
    );
    if (initialExists) {
      debugPrint('Playlist dedupe: blocked by initial key match');
      return false;
    }

    final enriched = Map<String, dynamic>.from(item);
    enriched['addedAt'] = DateTime.now().millisecondsSinceEpoch;
    enriched['provider'] = ((item['provider'] as String?)?.isNotEmpty ?? false)
        ? item['provider']
        : 'realdebrid';

    final bool isTorbox =
        (enriched['provider'] as String?)?.toLowerCase() == 'torbox';

    // Fetch and add torrent hash if we have a torrent ID
    final String? rdTorrentId = item['rdTorrentId'] as String?;
    final String? apiKey = await RealDebridStorage.getApiKey(canContinue: canContinue);
    if (canContinue?.call() == false) return false;

    if (!isTorbox &&
        rdTorrentId != null &&
        rdTorrentId.isNotEmpty &&
        apiKey != null &&
        apiKey.isNotEmpty) {
      try {
        // Import DebridService here to avoid circular dependency
        final response = await http.get(
          Uri.parse(
            'https://api.real-debrid.com/rest/1.0/torrents/info/$rdTorrentId',
          ),
          headers: {'Authorization': 'Bearer $apiKey'},
        );

        if (canContinue?.call() == false) return false;
        if (response.statusCode == 200) {
          final torrentInfo = json.decode(response.body);
          final String? hash = torrentInfo['hash'] as String?;
          if (hash != null && hash.isNotEmpty) {
            enriched['torrent_hash'] = hash;
            debugPrint(
              '✅ Torrent hash fetched and stored: $hash for torrent ID: $rdTorrentId',
            );
          } else {
            debugPrint(
              '⚠️ No hash found in torrent info for torrent ID: $rdTorrentId',
            );
          }
        } else {
          debugPrint(
            '❌ Failed to fetch torrent info. Status code: ${response.statusCode} for torrent ID: $rdTorrentId',
          );
        }
      } catch (e) {
        debugPrint(
          '❌ Error fetching torrent hash for torrent ID: $rdTorrentId - $e',
        );
        // Silently continue without hash if fetch fails
        // This ensures playlist addition doesn't fail due to hash fetch issues
      }
    } else {
      debugPrint(
        'ℹ️ Skipping torrent hash fetch - missing rdTorrentId or API key',
      );
    }

    // Log what's being saved to database
    debugPrint('📝 Adding playlist item to database:');
    debugPrint('   Title: ${enriched['title']}');
    debugPrint('   Kind: ${enriched['kind']}');
    debugPrint('   rdTorrentId: ${enriched['rdTorrentId']}');
    debugPrint('   torrent_hash: ${enriched['torrent_hash'] ?? 'null'}');
    debugPrint('   restrictedLink: ${enriched['restrictedLink'] ?? 'null'}');
    debugPrint(
      '   addedAt: ${DateTime.fromMillisecondsSinceEpoch(enriched['addedAt']).toIso8601String()}',
    );

    final finalKey = computePlaylistDedupeKey(enriched);
    if (finalKey != initialKey) {
      final finalExists = items.any(
        (entry) => computePlaylistDedupeKey(entry) == finalKey,
      );
      if (finalExists) {
        debugPrint('Playlist dedupe: blocked by final key match ($finalKey)');
        return false;
      }
    }

    Future<bool> save() async {
      if (canContinue?.call() == false) return false;
      items.insert(0, enriched);
      await savePlaylistItemsRaw(items, canContinue: canContinue);
      return true;
    }

    if (canContinue == null) return save();
    // Recheck after waiting for sync/profile mutations, before any persisted
    // playlist or tombstone work. Existing unguarded callers retain their path.
    return ProfilePreferences.synchronizeExternalMutation(
      save,
      marksMutation: false,
    );
  }

  static Future<void> removePlaylistItemByKey(String dedupeKey) async {
    final items = await getPlaylistItemsRaw();
    items.removeWhere((e) => computePlaylistDedupeKey(e) == dedupeKey);
    await savePlaylistItemsRaw(items);
  }

  /// Update lastPlayedAt timestamp for a playlist item
  /// Call this when user starts playing a playlist item
  static Future<void> updatePlaylistItemLastPlayed(
    Map<String, dynamic> item,
  ) async {
    final items = await getPlaylistItemsRaw();
    final dedupeKey = computePlaylistDedupeKey(item);
    final index = items.indexWhere(
      (e) => computePlaylistDedupeKey(e) == dedupeKey,
    );

    if (index != -1) {
      items[index]['lastPlayedAt'] = DateTime.now().millisecondsSinceEpoch;
      await savePlaylistItemsRaw(items);
      debugPrint(
        'StorageService: Updated lastPlayedAt for "${items[index]['title']}"',
      );
    }
  }

  /// Get lastPlayedAt timestamp for a playlist item
  /// Returns null if item has never been played
  static int? getPlaylistItemLastPlayed(Map<String, dynamic> item) {
    return item['lastPlayedAt'] as int?;
  }

  static Future<void> clearPlaylist({bool recordSyncDeletions = true}) async {
    await savePlaylistItemsRaw(
      const <Map<String, dynamic>>[],
      recordSyncDeletions: recordSyncDeletions,
    );
  }

  /// Clear all playlist-related metadata (view modes, favorites, poster overrides)
  static Future<void> clearAllPlaylistMetadata({
    bool recordSyncDeletions = true,
  }) async {
    final prefs = await ProfilePreferences.instance();
    if (recordSyncDeletions) {
      final favorites = await getPlaylistFavoriteKeys();
      await WebDavSyncTombstoneRecorder.recordForCurrentProfile(
        favorites.map(WebDavSyncRecordKey.playlistFavorite),
      );
    }
    await prefs.remove(_playlistViewModesKey);
    await prefs.remove(_playlistFavoritesKey);
    await prefs.remove(_playlistPosterOverridesKey);
    await prefs.remove(_tvMazeSeriesMappingKey);
  }

  /// Clear all startup settings (auto-launch, channel/playlist references)
  static Future<void> clearAllStartupSettings() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_startupAutoLaunchEnabledKey);
    await prefs.remove(_startupChannelIdKey);
    await prefs.remove(_startupStremioTvChannelIdKey);
    await prefs.remove(_startupModeKey);
    await prefs.remove(_startupPlaylistItemIdKey);
    await prefs.remove(_startupContinueWatchingItemIdKey);
    await prefs.remove(_startupTraktContinueWatchingMovieIdKey);
    await prefs.remove(_startupTraktContinueWatchingShowIdKey);
    // The startup-channel memory is a startup reference too — Reset must wipe
    // it, or a fresh setup would inherit the previous install's channel.
    await prefs.remove(_iptvLastLiveChannelKey);
    await prefs.remove(_startupIptvModeKey);
    await prefs.remove(_startupIptvChannelKey);
  }

  /// Clear Debrify TV provider and legacy channels key
  static Future<void> clearDebrifyTvProviderAndLegacy() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_debrifyTvProviderKey);
    await prefs.remove(_debrifyTvChannelsKey);
  }

  /// Clear all Debrify TV display and engine settings
  static Future<void> clearAllDebrifyTvSettings() async {
    final prefs = await ProfilePreferences.instance();
    // Display settings
    await prefs.remove(_debrifyTvStartRandomKey);
    await prefs.remove(_debrifyTvHideSeekbarKey);
    await prefs.remove(_debrifyTvShowChannelNameKey);
    await prefs.remove(_debrifyTvShowVideoTitleKey);
    await prefs.remove(_debrifyTvHideOptionsKey);
    await prefs.remove(_debrifyTvHideBackButtonKey);
    await prefs.remove(_debrifyTvAvoidNsfwKey);
    await prefs.remove(_debrifyTvRandomStartPercentKey);
    // Playback filters
    await prefs.remove(_debrifyTvFilterQualitiesKey);
    await prefs.remove(_debrifyTvFilterSizesKey);
    for (final key
        in prefs
            .getKeys()
            .where(
              (key) =>
                  key.startsWith('engine_tv_') ||
                  key.startsWith('debrify_tv_use_') ||
                  key.startsWith('debrify_tv_channel_small_') ||
                  key.startsWith('debrify_tv_channel_large_') ||
                  key.startsWith('debrify_tv_quick_play_') ||
                  key == 'debrify_tv_keyword_threshold' ||
                  key == 'debrify_tv_min_torrents_per_keyword',
            )
            .toList()) {
      await prefs.remove(key);
    }
  }

  /// Update an existing playlist item with poster URL
  /// Supports both RealDebrid (rdTorrentId) and PikPak (pikpakCollectionId)
  static Future<bool> updatePlaylistItemPoster(
    String posterUrl, {
    String? rdTorrentId,
    String? torboxTorrentId,
    String? pikpakCollectionId,
    String? premiumizeHash,
    String? premiumizeItemId,
    String? allDebridHash,
    String? webDavServerId,
    String? webDavBaseUrl,
    String? webDavPath,
  }) async {
    debugPrint('🎨 updatePlaylistItemPoster called with:');
    debugPrint('  posterUrl: $posterUrl');
    debugPrint('  rdTorrentId: $rdTorrentId');
    debugPrint('  torboxTorrentId: $torboxTorrentId');
    debugPrint('  pikpakCollectionId: $pikpakCollectionId');
    debugPrint('  webDavServerId: $webDavServerId');
    debugPrint('  webDavPath: $webDavPath');

    final items = await getPlaylistItemsRaw();
    debugPrint('  Total playlist items: ${items.length}');

    int itemIndex = -1;

    // Search by rdTorrentId if provided (RealDebrid)
    if (rdTorrentId != null && rdTorrentId.isNotEmpty) {
      itemIndex = items.indexWhere(
        (item) => (item['rdTorrentId'] as String?) == rdTorrentId,
      );
      if (itemIndex != -1) {
        debugPrint('  ✅ Found item by rdTorrentId at index $itemIndex');
      }
    }

    // Search by torboxTorrentId if provided and not found yet (Torbox)
    if (itemIndex == -1 &&
        torboxTorrentId != null &&
        torboxTorrentId.isNotEmpty) {
      debugPrint('  Searching for torboxTorrentId: $torboxTorrentId');
      for (int i = 0; i < items.length; i++) {
        final item = items[i];
        final torboxId = item['torboxTorrentId'];
        debugPrint(
          '    Item[$i] torboxTorrentId: $torboxId (type: ${torboxId.runtimeType})',
        );
        if (torboxId != null &&
            torboxId.toString() == torboxTorrentId.toString()) {
          itemIndex = i;
          debugPrint('  ✅ Found item by torboxTorrentId at index $itemIndex');
          break;
        }
      }
    }

    // Search by pikpakCollectionId if provided and not found yet (PikPak)
    if (itemIndex == -1 &&
        pikpakCollectionId != null &&
        pikpakCollectionId.isNotEmpty) {
      itemIndex = items.indexWhere((item) {
        // Check single PikPak files
        final pikpakFileId = item['pikpakFileId'] as String?;
        if (pikpakFileId == pikpakCollectionId) {
          return true;
        }

        // Check PikPak collections (first file ID in array)
        final pikpakFileIds = item['pikpakFileIds'] as List<dynamic>?;
        if (pikpakFileIds != null && pikpakFileIds.isNotEmpty) {
          final firstId = pikpakFileIds[0].toString();
          if (firstId == pikpakCollectionId) {
            return true;
          }
        }

        return false;
      });
      if (itemIndex != -1) {
        debugPrint('  ✅ Found item by pikpakCollectionId at index $itemIndex');
      }
    }

    // Search by Premiumize infohash if provided and not found yet (Premiumize)
    if (itemIndex == -1 &&
        premiumizeHash != null &&
        premiumizeHash.isNotEmpty) {
      itemIndex = items.indexWhere(
        (item) =>
            ((item['provider'] as String?)?.toLowerCase() == 'premiumize') &&
            (item['torrent_hash'] as String?)?.toLowerCase() ==
                premiumizeHash.toLowerCase(),
      );
      if (itemIndex != -1) {
        debugPrint('  ✅ Found item by premiumizeHash at index $itemIndex');
      }
    }

    // Search by Premiumize cloud item id if provided and not found yet
    // (cloud-browser items have no torrent hash).
    if (itemIndex == -1 &&
        premiumizeItemId != null &&
        premiumizeItemId.isNotEmpty) {
      itemIndex = items.indexWhere(
        (item) =>
            ((item['provider'] as String?)?.toLowerCase() == 'premiumize') &&
            (item['premiumizeItemId']?.toString() == premiumizeItemId),
      );
      if (itemIndex != -1) {
        debugPrint('  ✅ Found item by premiumizeItemId at index $itemIndex');
      }
    }

    // Search by AllDebrid infohash if provided and not found yet.
    if (itemIndex == -1 && allDebridHash != null && allDebridHash.isNotEmpty) {
      itemIndex = items.indexWhere(
        (item) =>
            ((item['provider'] as String?)?.toLowerCase() == 'alldebrid') &&
            (item['torrent_hash'] as String?)?.toLowerCase() ==
                allDebridHash.toLowerCase(),
      );
      if (itemIndex != -1) {
        debugPrint('  ✅ Found item by allDebridHash at index $itemIndex');
      }
    }

    if (itemIndex == -1 &&
        webDavPath != null &&
        webDavPath.isNotEmpty &&
        ((webDavServerId != null && webDavServerId.isNotEmpty) ||
            (webDavBaseUrl != null && webDavBaseUrl.isNotEmpty))) {
      final webDavKey = computePlaylistDedupeKey({
        'provider': 'webdav',
        if (webDavServerId != null && webDavServerId.isNotEmpty)
          'webdavServerId': webDavServerId,
        if (webDavBaseUrl != null && webDavBaseUrl.isNotEmpty)
          'webdavBaseUrl': webDavBaseUrl,
        'webdavPath': webDavPath,
      });
      itemIndex = items.indexWhere(
        (item) => computePlaylistDedupeKey(item) == webDavKey,
      );
      if (itemIndex != -1) {
        debugPrint('  ✅ Found item by WebDAV key at index $itemIndex');
      }
    }

    if (itemIndex == -1) {
      debugPrint('  ❌ Item not found in playlist!');
      return false;
    }

    debugPrint('  💾 Saving poster to item at index $itemIndex');
    items[itemIndex]['posterUrl'] = posterUrl;
    await savePlaylistItemsRaw(items);
    debugPrint('  ✅ Poster saved successfully!');
    return true;
  }

  static Future<bool> updatePlaylistItemImdbId(
    String imdbId, {
    String? rdTorrentId,
    String? torboxTorrentId,
    String? pikpakCollectionId,
    String? premiumizeHash,
    String? premiumizeItemId,
    String? allDebridHash,
    bool force = false,
  }) async {
    final items = await getPlaylistItemsRaw();
    int itemIndex = -1;

    if (rdTorrentId != null && rdTorrentId.isNotEmpty) {
      itemIndex = items.indexWhere(
        (item) => (item['rdTorrentId'] as String?) == rdTorrentId,
      );
    }

    if (itemIndex == -1 &&
        premiumizeHash != null &&
        premiumizeHash.isNotEmpty) {
      itemIndex = items.indexWhere(
        (item) =>
            ((item['provider'] as String?)?.toLowerCase() == 'premiumize') &&
            (item['torrent_hash'] as String?)?.toLowerCase() ==
                premiumizeHash.toLowerCase(),
      );
    }

    if (itemIndex == -1 &&
        premiumizeItemId != null &&
        premiumizeItemId.isNotEmpty) {
      itemIndex = items.indexWhere(
        (item) =>
            ((item['provider'] as String?)?.toLowerCase() == 'premiumize') &&
            (item['premiumizeItemId']?.toString() == premiumizeItemId),
      );
    }

    if (itemIndex == -1 &&
        torboxTorrentId != null &&
        torboxTorrentId.isNotEmpty) {
      for (int i = 0; i < items.length; i++) {
        final torboxId = items[i]['torboxTorrentId'];
        if (torboxId != null &&
            torboxId.toString() == torboxTorrentId.toString()) {
          itemIndex = i;
          break;
        }
      }
    }

    if (itemIndex == -1 &&
        pikpakCollectionId != null &&
        pikpakCollectionId.isNotEmpty) {
      itemIndex = items.indexWhere((item) {
        final pikpakFileId = item['pikpakFileId'] as String?;
        if (pikpakFileId == pikpakCollectionId) return true;
        final pikpakFileIds = item['pikpakFileIds'] as List<dynamic>?;
        if (pikpakFileIds != null && pikpakFileIds.isNotEmpty) {
          return pikpakFileIds[0].toString() == pikpakCollectionId;
        }
        return false;
      });
    }

    if (itemIndex == -1 && allDebridHash != null && allDebridHash.isNotEmpty) {
      itemIndex = items.indexWhere(
        (item) =>
            ((item['provider'] as String?)?.toLowerCase() == 'alldebrid') &&
            (item['torrent_hash'] as String?)?.toLowerCase() ==
                allDebridHash.toLowerCase(),
      );
    }

    if (itemIndex == -1) return false;

    if (!force) {
      final existing = items[itemIndex]['imdbId'] as String?;
      if (existing != null && existing.isNotEmpty) return true;
    }

    items[itemIndex]['imdbId'] = imdbId;
    await savePlaylistItemsRaw(items);
    debugPrint(
      'StorageService: Saved imdbId $imdbId to playlist item "${items[itemIndex]['title']}"',
    );
    return true;
  }

  /// Get saved view mode for a playlist item
  /// Returns null if no view mode has been saved for this item
  static Future<String?> getPlaylistItemViewMode(
    Map<String, dynamic> item,
  ) async {
    final prefs = await ProfilePreferences.instance();
    final viewModesJson = prefs.getString(_playlistViewModesKey);

    if (viewModesJson == null) return null;

    try {
      final viewModes = jsonDecode(viewModesJson) as Map<String, dynamic>;
      final dedupeKey = computePlaylistDedupeKey(item);
      return viewModes[dedupeKey] as String?;
    } catch (e) {
      debugPrint('Error reading playlist view modes: $e');
      return null;
    }
  }

  /// Save view mode for a playlist item
  static Future<void> savePlaylistItemViewMode(
    Map<String, dynamic> item,
    String viewMode,
  ) async {
    final prefs = await ProfilePreferences.instance();
    final viewModesJson = prefs.getString(_playlistViewModesKey);

    Map<String, dynamic> viewModes = {};
    if (viewModesJson != null) {
      try {
        viewModes = jsonDecode(viewModesJson) as Map<String, dynamic>;
      } catch (e) {
        debugPrint('Error parsing playlist view modes: $e');
      }
    }

    final dedupeKey = computePlaylistDedupeKey(item);
    viewModes[dedupeKey] = viewMode;

    await prefs.setString(_playlistViewModesKey, jsonEncode(viewModes));
  }

  /// Check if a playlist item is favorited
  static Future<bool> isPlaylistItemFavorited(Map<String, dynamic> item) async {
    final prefs = await ProfilePreferences.instance();
    final favoritesJson = prefs.getString(_playlistFavoritesKey);

    if (favoritesJson == null) return false;

    try {
      final favorites = jsonDecode(favoritesJson) as Map<String, dynamic>;
      final dedupeKey = computePlaylistDedupeKey(item);
      return favorites[dedupeKey] == true;
    } catch (e) {
      debugPrint('Error reading playlist favorites: $e');
      return false;
    }
  }

  /// Set favorite status for a playlist item
  static Future<void> setPlaylistItemFavorited(
    Map<String, dynamic> item,
    bool isFavorited,
  ) async {
    final prefs = await ProfilePreferences.instance();
    final favoritesJson = prefs.getString(_playlistFavoritesKey);

    Map<String, dynamic> favorites = {};
    if (favoritesJson != null) {
      try {
        favorites = jsonDecode(favoritesJson) as Map<String, dynamic>;
      } catch (e) {
        debugPrint('Error parsing playlist favorites: $e');
      }
    }

    final dedupeKey = computePlaylistDedupeKey(item);
    if (isFavorited) {
      favorites[dedupeKey] = true;
    } else {
      if (!favorites.containsKey(dedupeKey)) return;
      await WebDavSyncTombstoneRecorder.recordForCurrentProfile(<String>{
        WebDavSyncRecordKey.playlistFavorite(dedupeKey),
      });
      favorites.remove(dedupeKey);
    }

    await prefs.setString(_playlistFavoritesKey, jsonEncode(favorites));
  }

  /// Get all favorite dedupe keys
  static Future<Set<String>> getPlaylistFavoriteKeys() async {
    final prefs = await ProfilePreferences.instance();
    final favoritesJson = prefs.getString(_playlistFavoritesKey);

    if (favoritesJson == null) return {};

    try {
      final favorites = jsonDecode(favoritesJson) as Map<String, dynamic>;
      return favorites.keys.toSet();
    } catch (e) {
      debugPrint('Error reading playlist favorites: $e');
      return {};
    }
  }

  // ========================================================================
  // My Watchlist (movies + series)
  // ========================================================================

  /// Stable identity for Debrify's local movie/series watchlist. Prefer IMDb
  /// so the same title coming from two addons is one entry; fall back to the
  /// source addon + its content id for titles that do not expose IMDb metadata.
  /// Addon ids are part of that fallback because content ids are addon-local.
  static bool supportsMyWatchlistItem(StremioMeta item) {
    final type = item.type.trim().toLowerCase();
    return type == 'movie' || type == 'series';
  }

  /// Returns the identity-bearing item used by both watchlist reads and
  /// writes. A stored source is authoritative for non-IMDb ids; [fallback]
  /// only fills in a source for a newly opened source-less item.
  static StremioMeta withMyWatchlistSource(
    StremioMeta item,
    StremioAddon fallback,
  ) => item.sourceAddon == null ? item.withSourceAddon(fallback) : item;

  static String myWatchlistItemKey(StremioMeta item) {
    if (!supportsMyWatchlistItem(item)) {
      throw ArgumentError.value(
        item.type,
        'item.type',
        'My Watchlist supports only movies and series',
      );
    }
    final type = item.type.trim().toLowerCase();
    final imdbId = item.effectiveImdbId?.trim();
    if (imdbId != null && imdbId.isNotEmpty) return '$type:$imdbId';

    final sourceId = item.sourceAddon?.id.trim();
    final namespace = (sourceId == null || sourceId.isEmpty)
        ? 'unknown'
        : sourceId;
    return '$type:addon:${Uri.encodeComponent(namespace)}:'
        '${Uri.encodeComponent(item.id)}';
  }

  /// tvOS durability ceiling for the encoded watchlist. The recovery envelope
  /// silently skips any single value over its per-value limit, which would
  /// resurrect the wipe-on-restart bug; the 16KiB margin covers the
  /// JSON-escaping inflation the value picks up inside the envelope.
  static const int myWatchlistTvOsCapBytes =
      TvOsRecoveryLimits.envelopeValueBytes - 16 * 1024;

  /// Test seam: `PlatformUtil.isTvOS` is a `static final` and cannot be
  /// overridden, so tests drive the cap through this instead.
  @visibleForTesting
  static bool? debugMyWatchlistTvOsCapOverride;

  static bool get _myWatchlistCapEnforced =>
      debugMyWatchlistTvOsCapOverride ?? PlatformUtil.isTvOS;

  static int _myWatchlistAddedAt(Map<String, dynamic> row) {
    final raw = row['addedAt'];
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw) ?? 0;
    return 0;
  }

  /// Recomputes keys from stored metadata so rows written by the original
  /// un-namespaced fallback scheme migrate in memory immediately. The next
  /// mutation persists the canonical key.
  static void _canonicalizeMyWatchlistRowKey(Map<String, dynamic> row) {
    final raw = row['item'];
    if (raw is! Map) return;
    try {
      final item = StremioMeta.fromJson(Map<String, dynamic>.from(raw));
      if (supportsMyWatchlistItem(item)) {
        row['key'] = myWatchlistItemKey(item);
      }
    } catch (_) {
      // The item loader below will ignore the malformed row.
    }
  }

  static Future<List<Map<String, dynamic>>> _readMyWatchlistRows() async {
    final prefs = await ProfilePreferences.instance();
    final encoded = prefs.getString(_myWatchlistKey);
    if (encoded == null) return <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List) return <Map<String, dynamic>>[];
      final rows = [
        for (final row in decoded)
          if (row is Map) Map<String, dynamic>.from(row),
      ];
      for (final row in rows) {
        _canonicalizeMyWatchlistRowKey(row);
      }
      return rows;
    } catch (e) {
      debugPrint('Error reading My Watchlist: $e');
      return <Map<String, dynamic>>[];
    }
  }

  /// Saved titles, newest first. Corrupt individual rows are ignored so one
  /// bad addon payload cannot make the whole shelf disappear.
  static Future<List<StremioMeta>> getMyWatchlistItems() async {
    final rows = await _readMyWatchlistRows();
    rows.sort(
      (a, b) => _myWatchlistAddedAt(b).compareTo(_myWatchlistAddedAt(a)),
    );
    final items = <StremioMeta>[];
    for (final row in rows) {
      final raw = row['item'];
      if (raw is! Map) continue;
      try {
        final item = StremioMeta.fromJson(Map<String, dynamic>.from(raw));
        if (item.id.isEmpty || !supportsMyWatchlistItem(item)) {
          continue;
        }
        items.add(item);
      } catch (_) {
        // Skip only the malformed row.
      }
    }
    return items;
  }

  static Future<bool> isInMyWatchlist(StremioMeta item) async {
    if (!supportsMyWatchlistItem(item)) return false;
    final key = myWatchlistItemKey(item);
    final rows = await _readMyWatchlistRows();
    return rows.any((row) => row['key'] == key);
  }

  /// Adds, refreshes, or removes a title. Adding stores the full presentation
  /// metadata needed by Home, not just an id, so My Watchlist paints instantly
  /// offline and can route back through the source addon when it is installed.
  static Future<void> setMyWatchlistItem(StremioMeta item, bool saved) async {
    if (!supportsMyWatchlistItem(item)) {
      throw ArgumentError.value(
        item.type,
        'item.type',
        'My Watchlist supports only movies and series',
      );
    }
    final prefs = await ProfilePreferences.instance();
    final rows = await _readMyWatchlistRows();
    final key = myWatchlistItemKey(item);
    final existing = rows.where((row) => row['key'] == key).firstOrNull;
    rows.removeWhere((row) => row['key'] == key);
    if (saved) {
      rows.insert(0, {
        'key': key,
        'addedAt': existing == null
            ? DateTime.now().millisecondsSinceEpoch
            : _myWatchlistAddedAt(existing),
        'item': item.toJson(),
      });
    }
    if (rows.isEmpty) {
      await prefs.remove(_myWatchlistKey);
    } else {
      var encoded = jsonEncode(rows);
      if (_myWatchlistCapEnforced) {
        // Oldest rows go first. The scan starts past index 0 because the row
        // just written sits there — a re-save keeps its original addedAt, so
        // an oldest-by-timestamp scan could otherwise evict exactly it.
        while (rows.length > 1 &&
            utf8.encode(encoded).length > myWatchlistTvOsCapBytes) {
          var oldest = 1;
          for (var i = 2; i < rows.length; i++) {
            if (_myWatchlistAddedAt(rows[i]) <
                _myWatchlistAddedAt(rows[oldest])) {
              oldest = i;
            }
          }
          rows.removeAt(oldest);
          encoded = jsonEncode(rows);
        }
      }
      await prefs.setString(_myWatchlistKey, encoded);
    }
  }

  /// Removes a saved movie/series once actual playback is about to launch.
  /// IMDb is authoritative. Older/addon-local items without IMDb metadata use
  /// a conservative title/source fallback and are removed only when unique.
  static Future<bool> removeMyWatchlistItemForPlayback({
    String? imdbId,
    required String contentType,
    required String title,
    String? addonId,
  }) async {
    final type = contentType.trim().toLowerCase();
    if (type != 'movie' && type != 'series') return false;
    final normalizedImdb = imdbId?.trim().toLowerCase();
    final normalizedTitle = title.trim().toLowerCase();
    final normalizedAddon = addonId?.trim().toLowerCase();
    final prefs = await ProfilePreferences.instance();
    final rows = await _readMyWatchlistRows();
    final matches = <Map<String, dynamic>>[];
    for (final row in rows) {
      final raw = row['item'];
      if (raw is! Map) continue;
      try {
        final item = StremioMeta.fromJson(Map<String, dynamic>.from(raw));
        if (item.type.trim().toLowerCase() != type) continue;
        final itemImdb = item.effectiveImdbId?.trim().toLowerCase();
        if (normalizedImdb != null && normalizedImdb.isNotEmpty) {
          if (itemImdb == normalizedImdb) matches.add(row);
          continue;
        }
        if (itemImdb != null && itemImdb.isNotEmpty) continue;
        if (normalizedTitle.isEmpty ||
            item.name.trim().toLowerCase() != normalizedTitle) {
          continue;
        }
        final itemAddon = item.sourceAddon?.id.trim().toLowerCase();
        if (normalizedAddon != null &&
            normalizedAddon.isNotEmpty &&
            itemAddon != normalizedAddon) {
          continue;
        }
        matches.add(row);
      } catch (_) {
        // Malformed rows are ignored rather than making playback fail.
      }
    }
    if (matches.length != 1) return false;
    rows.remove(matches.single);
    if (rows.isEmpty) {
      await prefs.remove(_myWatchlistKey);
    } else {
      await prefs.setString(_myWatchlistKey, jsonEncode(rows));
    }
    return true;
  }

  static Future<void> clearMyWatchlist() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_myWatchlistKey);
  }

  // ==========================================================================
  // Debrify TV Channel Favorites
  // ==========================================================================

  /// Check if a Debrify TV channel is favorited
  static Future<bool> isDebrifyTvChannelFavorited(String channelId) async {
    final prefs = await ProfilePreferences.instance();
    final favoritesJson = prefs.getString(_debrifyTvFavoriteChannelsKey);

    if (favoritesJson == null) return false;

    try {
      final favorites = jsonDecode(favoritesJson) as Map<String, dynamic>;
      return favorites.containsKey(channelId);
    } catch (e) {
      debugPrint('Error reading Debrify TV channel favorites: $e');
      return false;
    }
  }

  /// Set favorite status for a Debrify TV channel
  static Future<void> setDebrifyTvChannelFavorited(
    String channelId,
    bool isFavorited,
  ) async {
    final prefs = await ProfilePreferences.instance();
    final favoritesJson = prefs.getString(_debrifyTvFavoriteChannelsKey);

    Map<String, dynamic> favorites = {};
    if (favoritesJson != null) {
      try {
        favorites = jsonDecode(favoritesJson) as Map<String, dynamic>;
      } catch (_) {}
    }

    if (isFavorited) {
      favorites[channelId] = true;
    } else {
      favorites.remove(channelId);
    }

    await prefs.setString(_debrifyTvFavoriteChannelsKey, jsonEncode(favorites));
  }

  /// Get all favorite Debrify TV channel IDs
  static Future<Set<String>> getDebrifyTvFavoriteChannelIds() async {
    final prefs = await ProfilePreferences.instance();
    final favoritesJson = prefs.getString(_debrifyTvFavoriteChannelsKey);

    if (favoritesJson == null) return {};

    try {
      final favorites = jsonDecode(favoritesJson) as Map<String, dynamic>;
      return favorites.keys.toSet();
    } catch (e) {
      debugPrint('Error reading Debrify TV channel favorites: $e');
      return {};
    }
  }

  // ==========================================================================
  // IPTV Channel Favorites
  // ==========================================================================

  /// Canonical comparison key for an IPTV channel URL (see
  /// [IptvMediaStore.canonicalChannelKey]).
  static String canonicalIptvChannelKey(String url) {
    return IptvMediaStore.canonicalChannelKey(url);
  }

  /// Rewrite stored favorite URLs to the current format when a fetched
  /// channel matches an existing favorite canonically but not literally
  /// (e.g. favorites saved before the Xtream /live/ URL fix). Keeps the
  /// Home favorites row playing working URLs.
  static Future<void> reconcileIptvFavoriteUrls(List<IptvChannel> channels) {
    return IptvMediaStore.reconcileFavoriteUrls(channels);
  }

  /// DB-catalog variant: the fresh URLs come from the catalog rows on a
  /// worker isolate instead of a channel list.
  static Future<void> reconcileIptvFavoriteUrlsForCatalog(String catalogKey) {
    return IptvMediaStore.reconcileFavoriteUrlsForCatalog(catalogKey);
  }

  /// Set favorite status for an IPTV channel
  static Future<void> setIptvChannelFavorited(
    String channelUrl,
    bool isFavorited, {
    String? channelName,
    String? logoUrl,
    String? group,
    String? playlistId,
    int? channelNumber,
    String? contentType,
    int? duration,
    Map<String, String>? httpHeaders,
  }) {
    return IptvMediaStore.setChannelFavorited(
      channelUrl,
      isFavorited,
      channelName: channelName,
      logoUrl: logoUrl,
      group: group,
      playlistId: playlistId,
      channelNumber: channelNumber,
      contentType: contentType,
      duration: duration,
      httpHeaders: httpHeaders,
    );
  }

  // ── IPTV custom lists ────────────────────────────────────────────────────

  /// Reserved id of the built-in Favorites list.
  static const String iptvFavoritesListId = IptvMediaStore.favoritesListId;

  /// Every channel list, Favorites first then custom lists in user order.
  static Future<List<IptvListMeta>> getIptvLists() {
    return IptvMediaStore.lists();
  }

  /// Create a channel list and return its id.
  static Future<String> createIptvList(String name) {
    return IptvMediaStore.createList(name);
  }

  static Future<void> renameIptvList(String listId, String name) {
    return IptvMediaStore.renameList(listId, name);
  }

  /// Delete a custom list. The channels themselves are untouched.
  static Future<void> deleteIptvList(String listId) {
    return IptvMediaStore.deleteList(listId);
  }

  static Future<void> reorderIptvLists(List<String> orderedIds) {
    return IptvMediaStore.reorderLists(orderedIds);
  }

  /// Add or remove a channel in a list.
  static Future<void> setIptvChannelInList(
    String listId,
    String channelUrl,
    bool inList, {
    String? channelName,
    String? logoUrl,
    String? group,
    String? playlistId,
    int? channelNumber,
    String? contentType,
    int? duration,
    Map<String, String>? httpHeaders,
  }) {
    return IptvMediaStore.setChannelInList(
      listId,
      channelUrl,
      inList,
      channelName: channelName,
      logoUrl: logoUrl,
      group: group,
      playlistId: playlistId,
      channelNumber: channelNumber,
      contentType: contentType,
      duration: duration,
      httpHeaders: httpHeaders,
    );
  }

  /// One list's channels, url → metadata.
  static Future<Map<String, Map<String, dynamic>>> getIptvListChannels(
    String listId,
  ) {
    return IptvMediaStore.listChannels(listId);
  }

  /// Persist the display order of channels inside Favorites or a custom list.
  static Future<void> reorderIptvListChannels(
    String listId,
    Iterable<String> orderedUrls,
  ) {
    return IptvMediaStore.reorderListChannels(listId, orderedUrls);
  }

  static Future<List<IptvChannelOrderEntry>> getIptvCategoryOrderEntries(
    String sourceId,
    Iterable<IptvChannel> channels,
    String group,
  ) {
    return IptvMediaStore.categoryOrderEntries(sourceId, channels, group);
  }

  static Future<void> setIptvCategoryChannelOrder(
    String sourceId,
    String group,
    Iterable<IptvChannelOrderIdentity> ordered,
  ) {
    return IptvMediaStore.setCategoryChannelOrder(sourceId, group, ordered);
  }

  static Future<List<IptvChannel>> applyIptvCategoryChannelOrders(
    String sourceId,
    List<IptvChannel> channels,
  ) {
    return IptvMediaStore.applyCategoryChannelOrders(sourceId, channels);
  }

  static Future<void> removeIptvCategoryOrdersForSource(String sourceId) {
    return IptvMediaStore.removeCategoryOrdersForSource(sourceId);
  }

  /// Which lists each stored channel belongs to, url → list ids.
  static Future<Map<String, Set<String>>> getIptvChannelMembership() {
    return IptvMediaStore.channelMembership();
  }

  /// Membership + per-(list, url) origin providers in one read (see
  /// [IptvMediaStore.membershipSnapshot]).
  static Future<
    ({
      Map<String, Set<String>> membership,
      Map<(String, String), String> origins,
    })
  >
  getIptvMembershipSnapshot() {
    return IptvMediaStore.membershipSnapshot();
  }

  /// The lists one channel belongs to, matched canonically.
  static Future<Set<String>> getIptvListsForChannel(String channelUrl) {
    return IptvMediaStore.listsForChannel(channelUrl);
  }

  /// Remove every membership belonging to a playlist, across all lists.
  static Future<void> removeIptvListChannelsByPlaylistId(String playlistId) {
    return IptvMediaStore.removeListChannelsByPlaylistId(playlistId);
  }

  /// Per-channel HTTP headers stored with a favorite (see
  /// [setIptvChannelFavorited]). JSON round-trips them as a dynamic map, and
  /// favorites saved before headers existed simply have none.
  static Map<String, String> iptvFavoriteHeaders(Map<String, dynamic> meta) {
    final raw = meta['httpHeaders'];
    if (raw is! Map) return const {};
    final headers = <String, String>{};
    raw.forEach((key, value) {
      if (key is String && value != null) headers[key] = value.toString();
    });
    return headers;
  }

  /// Remove all IPTV favorites that belong to a specific playlist
  static Future<void> removeIptvFavoritesByPlaylistId(String playlistId) {
    return IptvMediaStore.removeFavoritesByPlaylistId(playlistId);
  }

  /// Get all favorite IPTV channel URLs with metadata
  static Future<Map<String, Map<String, dynamic>>> getIptvFavoriteChannels() {
    return IptvMediaStore.favoriteChannels();
  }

  /// Get all favorite IPTV channel URLs
  static Future<Set<String>> getIptvFavoriteChannelUrls() async {
    final favorites = await getIptvFavoriteChannels();
    return favorites.keys.toSet();
  }

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
  static const String _iptvTrackContinueWatchingKey =
      'iptv_track_continue_watching';

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
  /// trick [setIptvChannelFavorited] uses, and necessary for the same reason:
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

      final sortAt =
          (resume['updatedAt'] as num?)?.toInt() ??
          _iptvWatchTimestamp(entry.value);
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
      final keep =
          seriesKey != null &&
          item['hasNext'] == true &&
          (item['sortAt'] as int) == seriesLatest[seriesKey];
      if (keep) items.add(item);
    }

    items.sort((a, b) => (b['sortAt'] as int).compareTo(a['sortAt'] as int));
    return items;
  }

  /// Stored position/duration for whichever of [urls] the players have
  /// progress for. Reads the resume map once — callers are typically a list of
  /// thousands of rows.
  static Future<
    Map<String, ({int positionMs, int durationMs, double fraction})>
  >
  _iptvResumeStates(Iterable<String> urls) async {
    final wanted = urls.toSet();
    if (wanted.isEmpty) return {};

    final resumeMap = await IptvMediaStore.resumeEntries(wanted);
    final states =
        <String, ({int positionMs, int durationMs, double fraction})>{};
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
        if (entry.value.fraction >= _iptvWatchStartedFraction)
          entry.key: entry.value.fraction,
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
        if (entry.value.fraction >= _iptvWatchStartedFraction &&
            entry.value.fraction <= iptvWatchFinishedFraction)
          entry.key: entry.value.positionMs,
    };
  }

  /// Remove all watch history that belongs to a deleted playlist — mirrors
  /// [removeIptvFavoritesByPlaylistId] so a removed provider leaves nothing
  /// behind pointing at URLs that no longer authenticate.
  static Future<void> removeIptvWatchHistoryByPlaylistId(String playlistId) {
    return IptvMediaStore.removeWatchHistoryByPlaylistId(playlistId);
  }

  /// Take one on-demand IPTV item off the Continue Watching shelf (history +
  /// saved position). The local counterpart of [removeContinueWatchingItem].
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

  /// Build progress map for playlist items
  /// Maps playlist dedupe keys to their playback progress data
  static Future<Map<String, Map<String, dynamic>>> buildPlaylistProgressMap(
    List<Map<String, dynamic>> playlistItems,
  ) async {
    final progressMap = <String, Map<String, dynamic>>{};
    final playbackStateMap = await PlaybackStateStore.getPlaybackStateMap();

    for (final item in playlistItems) {
      final dedupeKey = computePlaylistDedupeKey(item);
      final title = (item['title'] as String?) ?? '';

      // Try to find progress data for this item
      Map<String, dynamic>? progressData;

      // Check if it's stored as a video (single file)
      final videoKey =
          'video_${title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';
      final videoState = playbackStateMap[videoKey];
      if (videoState != null && videoState['type'] == 'video') {
        progressData = {
          'positionMs': videoState['positionMs'] ?? 0,
          'durationMs': videoState['durationMs'] ?? 0,
          'updatedAt': videoState['updatedAt'] ?? 0,
        };
      }

      // Check if it's stored as a series
      if (progressData == null) {
        // Try multiple title variations to find the series state
        String? matchingSeriesKey;
        Map<String, dynamic>? seriesState;

        // Variation 1: Use the full playlist item title
        final fullTitleKey =
            'series_${title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

        // Variation 2: Try extracting clean title (like "game of thrones" from torrent name)
        // This matches how SeriesPlaylist extracts the title
        String cleanedTitle = title;

        // Remove common patterns to extract series name
        cleanedTitle = cleanedTitle.replaceAll(
          RegExp(r'\.S\d{2}.*', caseSensitive: false),
          '',
        ); // Remove S01-S08 and everything after
        cleanedTitle = cleanedTitle.replaceAll(
          RegExp(r'\.Season\..*', caseSensitive: false),
          '',
        ); // Remove Season.1-8
        cleanedTitle = cleanedTitle.replaceAll(
          RegExp(r'\.(1080p|720p|2160p|4k).*', caseSensitive: false),
          '',
        ); // Remove quality
        cleanedTitle = cleanedTitle.replaceAll(
          RegExp(r'\.(x264|x265|h264|h265).*', caseSensitive: false),
          '',
        ); // Remove codec
        cleanedTitle = cleanedTitle.replaceAll(
          RegExp(r'\.(BluRay|WEB|HDTV|WEBRip).*', caseSensitive: false),
          '',
        ); // Remove source
        cleanedTitle = cleanedTitle.replaceAll('.', ' ').trim();

        final cleanTitleKey =
            'series_${cleanedTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

        // Try both variations - PRIORITIZE clean title first (where playback state is actually saved)
        if (playbackStateMap[cleanTitleKey] != null &&
            playbackStateMap[cleanTitleKey]['type'] == 'series') {
          matchingSeriesKey = cleanTitleKey;
          seriesState = playbackStateMap[cleanTitleKey] as Map<String, dynamic>;
        } else if (playbackStateMap[fullTitleKey] != null &&
            playbackStateMap[fullTitleKey]['type'] == 'series') {
          matchingSeriesKey = fullTitleKey;
          seriesState = playbackStateMap[fullTitleKey] as Map<String, dynamic>;
        } else {
          // Fallback: Search through all series entries for a partial match
          for (final entry in playbackStateMap.entries) {
            if (entry.key.startsWith('series_') &&
                entry.value['type'] == 'series') {
              final seriesTitle =
                  (entry.value['title'] as String?)?.toLowerCase() ?? '';
              final itemTitleLower = title.toLowerCase();

              // Check if the series title is contained in the item title or vice versa
              if (itemTitleLower.contains(seriesTitle) ||
                  seriesTitle.contains(cleanedTitle.toLowerCase())) {
                matchingSeriesKey = entry.key;
                seriesState = entry.value as Map<String, dynamic>;
                break;
              }
            }
          }
        }

        if (seriesState != null && matchingSeriesKey != null) {
          debugPrint(
            '📺 Matched series state for "$title" using key: $matchingSeriesKey',
          );

          // Calculate overall series progress (Option 2)
          // Formula: (finished episodes + partial episode progress) / total episodes

          int totalEpisodes =
              (item['fileCount'] as int?) ?? (item['count'] as int?) ?? 0;
          if (totalEpisodes == 0) {
            // Try to count from the playlist item structure
            totalEpisodes = 1; // Fallback to at least 1
          }

          // Count finished episodes from both finishedEpisodes and seasons maps
          // Use a Set to track which episodes are finished to avoid double-counting
          final Set<String> finishedEpisodeKeys = {};
          int finishedEpisodeCount = 0;

          // First, count episodes explicitly marked as finished (TV series)
          final finishedEpisodes =
              seriesState['finishedEpisodes'] as Map<String, dynamic>?;
          if (finishedEpisodes != null) {
            for (final seasonEntry in finishedEpisodes.entries) {
              final seasonKey = seasonEntry.key;
              final seasonFinished = seasonEntry.value as Map<String, dynamic>;
              for (final episodeKey in seasonFinished.keys) {
                final key = '${seasonKey}_$episodeKey';
                finishedEpisodeKeys.add(key);
                finishedEpisodeCount++;
              }
            }
          }

          // Find the most recently played episode (for timestamp and partial progress)
          int latestPosition = 0;
          int latestDuration = 0;
          int latestUpdatedAt = 0;
          String? latestEpisodeKey;

          final seasons = seriesState['seasons'] as Map<String, dynamic>?;
          if (seasons != null) {
            for (final seasonEntry in seasons.entries) {
              final seasonKey = seasonEntry.key;
              final episodes = seasonEntry.value as Map<String, dynamic>;
              for (final episodeEntry in episodes.entries) {
                final episodeKey = episodeEntry.key;
                final episodeData = episodeEntry.value as Map<String, dynamic>;
                final positionMs = episodeData['positionMs'] as int? ?? 0;
                final durationMs = episodeData['durationMs'] as int? ?? 0;
                final updatedAt = episodeData['updatedAt'] as int? ?? 0;

                // Count as finished if >= 95% watched AND not already counted
                final key = '${seasonKey}_$episodeKey';
                if (durationMs > 0 && (positionMs / durationMs) >= 0.95) {
                  if (!finishedEpisodeKeys.contains(key)) {
                    finishedEpisodeKeys.add(key);
                    finishedEpisodeCount++;
                  }
                }

                // Track latest episode for partial progress
                if (updatedAt > latestUpdatedAt) {
                  latestUpdatedAt = updatedAt;
                  latestPosition = positionMs;
                  latestDuration = durationMs;
                  latestEpisodeKey = key;
                }
              }
            }
          }

          // Calculate partial progress from latest episode ONLY if not already counted as finished
          double partialEpisodeProgress = 0.0;
          bool hasPartialProgress = false;
          if (latestDuration > 0 &&
              latestPosition > 0 &&
              latestEpisodeKey != null) {
            partialEpisodeProgress = latestPosition / latestDuration;
            // Only count as partial if < 95% (not already counted as finished)
            if (partialEpisodeProgress < 0.95 &&
                !finishedEpisodeKeys.contains(latestEpisodeKey)) {
              hasPartialProgress = true;
            }
          }

          if (latestUpdatedAt > 0 && totalEpisodes > 0) {
            // Calculate overall series progress
            double totalEpisodesWatched = finishedEpisodeCount.toDouble();
            if (hasPartialProgress) {
              totalEpisodesWatched += partialEpisodeProgress;
            }

            // Create synthetic position/duration representing series progress
            final syntheticDuration =
                totalEpisodes * 1000000; // 1M ms per episode (arbitrary)
            final syntheticPosition = (totalEpisodesWatched * 1000000).toInt();

            progressData = {
              'positionMs': syntheticPosition,
              'durationMs': syntheticDuration,
              'updatedAt': latestUpdatedAt,
            };

            debugPrint(
              'Series "$title": $finishedEpisodeCount finished + ${partialEpisodeProgress.toStringAsFixed(2)} partial = ${totalEpisodesWatched.toStringAsFixed(2)} / $totalEpisodes episodes (${((totalEpisodesWatched / totalEpisodes) * 100).toStringAsFixed(1)}%)',
            );
          }
        }
      }

      if (progressData != null) {
        progressMap[dedupeKey] = progressData;
        debugPrint(
          'StorageService: Found progress for "$title" - ${progressData['positionMs']}ms / ${progressData['durationMs']}ms (${((progressData['positionMs'] / progressData['durationMs']) * 100).toStringAsFixed(1)}%)',
        );
      }
    }

    debugPrint(
      'StorageService: Built progress map with ${progressMap.length} entries',
    );
    return progressMap;
  }

  static int _normalizeLocalCompletionThreshold(int value) {
    return localCompletionThresholdOptions.contains(value)
        ? value
        : defaultLocalCompletionThreshold;
  }

  /// Percentage of a movie that must be watched before the local player marks
  /// it complete. Tracker-backed sessions retain Trakt/Simkl's own semantics.
  static Future<int> getMovieCompletionThreshold() async {
    final prefs = await ProfilePreferences.instance();
    return _normalizeLocalCompletionThreshold(
      prefs.getInt(_movieCompletionThresholdKey) ??
          defaultLocalCompletionThreshold,
    );
  }

  static Future<void> setMovieCompletionThreshold(int value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setInt(
      _movieCompletionThresholdKey,
      _normalizeLocalCompletionThreshold(value),
    );
  }

  /// Percentage of an episode that must be watched before the local player
  /// marks it complete. Kept separate from movies because users commonly want
  /// a different rule for episode credits.
  static Future<int> getEpisodeCompletionThreshold() async {
    final prefs = await ProfilePreferences.instance();
    return _normalizeLocalCompletionThreshold(
      prefs.getInt(_episodeCompletionThresholdKey) ??
          defaultLocalCompletionThreshold,
    );
  }

  static Future<void> setEpisodeCompletionThreshold(int value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setInt(
      _episodeCompletionThresholdKey,
      _normalizeLocalCompletionThreshold(value),
    );
  }

  /// Re-arms the resume-ghost purge for a restore/transfer preference overlay.
  ///
  /// A restore applies the package key-by-key over the destination profile, so
  /// a key the package does NOT carry keeps its destination value. A backup or
  /// device transfer taken on a pre-purge build carries `playback_state_v1`
  /// (ghosts and all) but no purge marker — so a destination that already ran
  /// the purge would keep `generation = 1` and never inspect the playback state
  /// it just imported, stranding those ghosts forever. Resetting the marker
  /// alongside imported playback lets the one-shot purge run once more against
  /// the new data.
  ///
  /// A package that DOES carry a marker came from a build that already purged
  /// at the source, so its value is honoured untouched.
  static void rearmGhostPurgeForImportedPlayback(
    Map<String, Object?> preferences,
  ) {
    if (!preferences.containsKey(PlaybackStateStore.playbackStateKey)) return;
    if (preferences.containsKey(_resumeGhostPurgeGenerationKey)) return;
    preferences[_resumeGhostPurgeGenerationKey] = 0;
  }

  /// One-time, per-profile purge of the resume "ghosts" older builds minted
  /// when an episode was unwatched.
  ///
  /// Until [_clearEpisodeCompletion] learned to drop the row, unwatching a
  /// fully-watched episode zeroed its `positionMs` and stamped `updatedAt` to
  /// now. The leftover row reads as "played, 0% in, not finished", which is the
  /// newest thing in the series — so it won `getLastPlayedEpisode*` and pinned
  /// Continue Watching (home card, detail pill, and Play alike) to an episode
  /// the user had just declared unwatched. Repeating mark→unmark to shake it
  /// loose only re-stamped it fresher.
  ///
  /// This runs ONCE rather than filtering on every read. A zero-position row is
  /// indistinguishable from an episode legitimately opened and closed before
  /// the first autosave tick, and permanently ignoring that shape would make a
  /// pack reopen the previous (already-watched) episode. Bounding the cleanup
  /// to one pass fixes the installs carrying a ghost — including ones that
  /// received it over a device transfer — while leaving normal playback
  /// bookkeeping exactly as it was.
  ///
  /// Rows marked in `finishedEpisodes` are kept: a mark-only watch stores the
  /// dummy 0ms/1ms shape and still means "watched".
  static Future<void> purgeUnwatchedResumeGhosts() async {
    final prefs = await ProfilePreferences.instance();
    final generation = prefs.getInt(_resumeGhostPurgeGenerationKey) ?? 0;
    if (generation >= _currentResumeGhostPurgeGeneration) return;

    final playback = await PlaybackStateStore.getPlaybackStateMap();
    var purged = 0;

    for (final stateEntry in playback.values) {
      if (stateEntry is! Map<String, dynamic> ||
          stateEntry['type'] != 'series') {
        continue;
      }
      final seasons = stateEntry['seasons'];
      if (seasons is! Map) continue;
      final finishedEpisodes = stateEntry['finishedEpisodes'];

      for (final seasonKey in seasons.keys.toList()) {
        final episodes = seasons[seasonKey];
        if (episodes is! Map) continue;
        final seasonFinished = finishedEpisodes is Map
            ? finishedEpisodes[seasonKey]
            : null;

        for (final episodeKey in episodes.keys.toList()) {
          final episodeData = episodes[episodeKey];
          if (episodeData is! Map) continue;
          if (seasonFinished is Map && seasonFinished.containsKey(episodeKey)) {
            continue;
          }
          final positionMs = (episodeData['positionMs'] as num?)?.toInt() ?? 0;
          final durationMs = (episodeData['durationMs'] as num?)?.toInt() ?? 0;
          // durationMs > 1 skips the mark-only dummy shape, which is already
          // excluded above whenever its completion record survived.
          if (positionMs == 0 && durationMs > 1) {
            episodes.remove(episodeKey);
            purged++;
          }
        }
        if (episodes.isEmpty) seasons.remove(seasonKey);
      }
    }

    if (purged > 0) {
      await PlaybackStateStore.savePlaybackStateMap(playback, recordDeletions: true);
      localCompletionRevision.value++;
      debugPrint(
        'StorageService: purged $purged unwatched resume ghost(s) from playback state',
      );
    }
    await prefs.setInt(
      _resumeGhostPurgeGenerationKey,
      _currentResumeGhostPurgeGeneration,
    );
  }

  /// One-time, per-profile adoption of the local completion thresholds for
  /// playback recorded before threshold-based watched status existed.
  ///
  /// Movies at/above their threshold become locally finished and leave local
  /// Continue Watching. Series episodes at/above their threshold are folded
  /// into the existing `finishedEpisodes` structure used by episode ticks.
  /// Tracker data is deliberately untouched; this migration only rewrites the
  /// app's local playback state.
  static Future<void> migrateExistingPlaybackCompletionThresholds() async {
    final prefs = await ProfilePreferences.instance();
    final generation =
        prefs.getInt(_playbackCompletionMigrationGenerationKey) ?? 0;
    if (generation >= _currentPlaybackCompletionMigrationGeneration) return;

    final movieThreshold = await getMovieCompletionThreshold();
    final episodeThreshold = await getEpisodeCompletionThreshold();
    final playback = await PlaybackStateStore.getPlaybackStateMap();
    final completedMovieIds = await _getFinishedMovieIds();
    final newlyCompletedMovieIds = <String>{};
    final completedMovieStateKeys = <String>{};
    final completedMovieResumeKeys = <String>{};
    var completedEpisodeCount = 0;
    var playbackChanged = false;

    for (final stateEntry in playback.entries) {
      final rawState = stateEntry.value;
      if (rawState is! Map<String, dynamic>) continue;

      if (rawState['type'] == 'video') {
        final imdbId = (rawState['imdbId'] as String?)?.trim().toLowerCase();
        final positionMs = (rawState['positionMs'] as num?)?.toInt() ?? 0;
        final durationMs = (rawState['durationMs'] as num?)?.toInt() ?? 0;
        if (imdbId == null ||
            imdbId.isEmpty ||
            durationMs <= 0 ||
            positionMs <= 0 ||
            positionMs * 100.0 / durationMs < movieThreshold) {
          continue;
        }
        completedMovieIds.add(imdbId);
        newlyCompletedMovieIds.add(imdbId);
        continue;
      }

      if (rawState['type'] != 'series') continue;
      final seasons = rawState['seasons'];
      if (seasons is! Map<String, dynamic>) continue;
      final finishedEpisodes = rawState['finishedEpisodes'] is Map
          ? Map<String, dynamic>.from(rawState['finishedEpisodes'] as Map)
          : <String, dynamic>{};

      for (final seasonEntry in seasons.entries) {
        final episodesRaw = seasonEntry.value;
        if (episodesRaw is! Map) continue;
        final seasonFinished = finishedEpisodes[seasonEntry.key] is Map
            ? Map<String, dynamic>.from(
                finishedEpisodes[seasonEntry.key] as Map,
              )
            : <String, dynamic>{};

        for (final episodeEntry in episodesRaw.entries) {
          if (episodeEntry.value is! Map) continue;
          final episodeData = Map<String, dynamic>.from(
            episodeEntry.value as Map,
          );
          final positionMs = (episodeData['positionMs'] as num?)?.toInt() ?? 0;
          final durationMs = (episodeData['durationMs'] as num?)?.toInt() ?? 0;
          if (durationMs <= 0 ||
              positionMs <= 0 ||
              positionMs * 100.0 / durationMs < episodeThreshold ||
              seasonFinished.containsKey(episodeEntry.key)) {
            continue;
          }

          seasonFinished[episodeEntry.key.toString()] = {
            'finishedAt':
                (episodeData['updatedAt'] as num?)?.toInt() ??
                DateTime.now().millisecondsSinceEpoch,
          };
          // Keep the episode's historical updatedAt so migration does not
          // reorder a show's "last played" episode.
          episodeData['positionMs'] = durationMs;
          episodesRaw[episodeEntry.key] = episodeData;
          completedEpisodeCount++;
          playbackChanged = true;
        }

        if (seasonFinished.isNotEmpty) {
          finishedEpisodes[seasonEntry.key] = seasonFinished;
        }
      }
      rawState['finishedEpisodes'] = finishedEpisodes;
    }

    if (newlyCompletedMovieIds.isNotEmpty) {
      for (final stateEntry in playback.entries) {
        final state = stateEntry.value;
        if (state is! Map<String, dynamic> || state['type'] != 'video') {
          continue;
        }
        final imdbId = (state['imdbId'] as String?)?.trim().toLowerCase();
        if (imdbId != null && newlyCompletedMovieIds.contains(imdbId)) {
          completedMovieStateKeys.add(stateEntry.key);
          final resumeKey = (state['title'] as String?)?.trim();
          if (resumeKey != null && resumeKey.isNotEmpty) {
            completedMovieResumeKeys.add(resumeKey);
          }
        }
      }
      playback.removeWhere((key, _) => completedMovieStateKeys.contains(key));
      playbackChanged = true;
      await prefs.setStringList(
        _finishedMoviesKey,
        completedMovieIds.toList()..sort(),
      );
      localCompletionRevision.value++;

      final rawContinueWatching = prefs.getString(_continueWatchingKey);
      if (rawContinueWatching != null && rawContinueWatching.isNotEmpty) {
        try {
          final decoded = await decodeJsonAsync(rawContinueWatching);
          if (decoded is List) {
            final items = decoded
                .whereType<Map<String, dynamic>>()
                .map(Map<String, dynamic>.from)
                .where((item) {
                  final imdbId = (item['imdbId'] as String?)
                      ?.trim()
                      .toLowerCase();
                  return imdbId == null ||
                      !newlyCompletedMovieIds.contains(imdbId);
                })
                .toList();
            await _saveContinueWatchingItems(items);
          }
        } catch (_) {
          // Leave malformed legacy data untouched; the normal CW reader also
          // treats it as empty, and completion migration can still succeed.
        }
      }
    }

    // The older player resume store uses the playback state's title as its
    // key. Clear it as part of the same migration so a later rewatch cannot
    // resurrect a near-credits position after the enhanced state is removed.
    // Do this before saving the removal so a database failure leaves enough
    // playback metadata for the next startup to retry the cleanup.
    for (final resumeKey in completedMovieResumeKeys) {
      await removeVideoResume(
        resumeKey,
        origin: WebDavSyncMutationOrigin.migration,
      );
    }
    if (playbackChanged) {
      await PlaybackStateStore.savePlaybackStateMap(playback, recordDeletions: true);
    }
    await prefs.setInt(
      _playbackCompletionMigrationGenerationKey,
      _currentPlaybackCompletionMigrationGeneration,
    );
    debugPrint(
      'StorageService: completion migration marked '
      '${newlyCompletedMovieIds.length} movies and '
      '$completedEpisodeCount episodes watched',
    );
  }

  // TVMaze Series Mapping Methods

  /// Get a unique key for a playlist item based on available identifiers
  static String _getPlaylistItemUniqueKey(Map<String, dynamic> playlistItem) {
    final provider = ((playlistItem['provider'] as String?) ?? 'realdebrid')
        .toLowerCase();

    if (provider == 'webdav') {
      return computePlaylistDedupeKey(playlistItem);
    }

    // Try different identifiers in order of preference
    if (playlistItem['rdTorrentId'] != null) {
      return 'rd_${playlistItem['rdTorrentId']}';
    }
    if (playlistItem['torrent_hash'] != null) {
      return 'hash_${playlistItem['torrent_hash']}';
    }
    if (playlistItem['torboxTorrentId'] != null) {
      return 'torbox_${playlistItem['torboxTorrentId']}';
    }
    if (playlistItem['pikpakFileId'] != null) {
      return 'pikpak_${playlistItem['pikpakFileId']}';
    }
    // Fallback to title if nothing else is available
    final title =
        (playlistItem['title'] as String?)?.toLowerCase().replaceAll(
          RegExp(r'[^a-z0-9]'),
          '_',
        ) ??
        'unknown';
    return 'title_$title';
  }

  /// Save a TVMaze series mapping for a playlist item
  static Future<void> saveTVMazeSeriesMapping({
    required Map<String, dynamic> playlistItem,
    required int tvmazeShowId,
    required String showName,
  }) async {
    final prefs = await ProfilePreferences.instance();
    final mappingsJson = prefs.getString(_tvMazeSeriesMappingKey);

    Map<String, dynamic> mappings = {};
    if (mappingsJson != null) {
      try {
        mappings = jsonDecode(mappingsJson) as Map<String, dynamic>;
      } catch (e) {
        debugPrint('Error parsing TVMaze series mappings: $e');
      }
    }

    final key = _getPlaylistItemUniqueKey(playlistItem);
    mappings[key] = {
      'tvmazeShowId': tvmazeShowId,
      'showName': showName,
      'savedAt': DateTime.now().millisecondsSinceEpoch,
    };

    await prefs.setString(_tvMazeSeriesMappingKey, jsonEncode(mappings));
    debugPrint(
      '✅ Saved TVMaze mapping for $key -> Show ID: $tvmazeShowId ($showName)',
    );
  }

  /// Get TVMaze series mapping for a playlist item
  static Future<Map<String, dynamic>?> getTVMazeSeriesMapping(
    Map<String, dynamic> playlistItem,
  ) async {
    final prefs = await ProfilePreferences.instance();
    final mappingsJson = prefs.getString(_tvMazeSeriesMappingKey);

    if (mappingsJson == null) return null;

    try {
      final mappings = jsonDecode(mappingsJson) as Map<String, dynamic>;
      final key = _getPlaylistItemUniqueKey(playlistItem);
      final mapping = mappings[key];

      if (mapping != null && mapping is Map<String, dynamic>) {
        debugPrint(
          '✅ Found TVMaze mapping for $key -> Show ID: ${mapping['tvmazeShowId']} (${mapping['showName']})',
        );
        return mapping;
      }
    } catch (e) {
      debugPrint('Error reading TVMaze series mappings: $e');
    }

    return null;
  }

  /// Clear TVMaze series mapping for a playlist item
  static Future<void> clearTVMazeSeriesMapping(
    Map<String, dynamic> playlistItem,
  ) async {
    final prefs = await ProfilePreferences.instance();
    final mappingsJson = prefs.getString(_tvMazeSeriesMappingKey);

    if (mappingsJson == null) return;

    try {
      final mappings = jsonDecode(mappingsJson) as Map<String, dynamic>;
      final key = _getPlaylistItemUniqueKey(playlistItem);

      if (mappings.containsKey(key)) {
        mappings.remove(key);
        await prefs.setString(_tvMazeSeriesMappingKey, jsonEncode(mappings));
        debugPrint('✅ Cleared TVMaze mapping for $key');
      }
    } catch (e) {
      debugPrint('Error clearing TVMaze series mapping: $e');
    }
  }

  /// Clear all TVMaze series mappings
  static Future<void> clearAllTVMazeSeriesMappings() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_tvMazeSeriesMappingKey);
    debugPrint('✅ Cleared all TVMaze series mappings');
  }

  // Playlist Poster Override Methods

  /// Save a poster URL override for a playlist item
  /// This ensures the poster persists across app restarts
  static Future<void> savePlaylistPosterOverride({
    required Map<String, dynamic> playlistItem,
    required String posterUrl,
  }) async {
    final prefs = await ProfilePreferences.instance();
    final overridesJson = prefs.getString(_playlistPosterOverridesKey);

    Map<String, dynamic> overrides = {};
    if (overridesJson != null) {
      try {
        overrides = jsonDecode(overridesJson) as Map<String, dynamic>;
      } catch (e) {
        debugPrint('Error parsing playlist poster overrides: $e');
      }
    }

    final key = _getPlaylistItemUniqueKey(playlistItem);
    overrides[key] = {
      'posterUrl': posterUrl,
      'savedAt': DateTime.now().millisecondsSinceEpoch,
    };

    await prefs.setString(_playlistPosterOverridesKey, jsonEncode(overrides));
    debugPrint('✅ Saved poster override for $key -> $posterUrl');
  }

  /// Get poster URL override for a playlist item
  /// Returns null if no override exists
  static Future<String?> getPlaylistPosterOverride(
    Map<String, dynamic> playlistItem,
  ) async {
    final prefs = await ProfilePreferences.instance();
    final overridesJson = prefs.getString(_playlistPosterOverridesKey);

    if (overridesJson == null) return null;

    try {
      final overrides = jsonDecode(overridesJson) as Map<String, dynamic>;
      final key = _getPlaylistItemUniqueKey(playlistItem);
      final override = overrides[key];

      if (override != null && override is Map<String, dynamic>) {
        final posterUrl = override['posterUrl'] as String?;
        if (posterUrl != null && posterUrl.isNotEmpty) {
          return posterUrl;
        }
      }
    } catch (e) {
      debugPrint('Error reading playlist poster override: $e');
    }

    return null;
  }

  /// Get all poster overrides as a map of item unique key → poster URL.
  /// Reads and parses the overrides blob once for batch lookups.
  static Future<Map<String, String>> getAllPlaylistPosterOverrides() async {
    final prefs = await ProfilePreferences.instance();
    final overridesJson = prefs.getString(_playlistPosterOverridesKey);
    if (overridesJson == null) return {};

    try {
      final overrides = jsonDecode(overridesJson) as Map<String, dynamic>;
      final result = <String, String>{};
      for (final entry in overrides.entries) {
        if (entry.value is Map<String, dynamic>) {
          final posterUrl =
              (entry.value as Map<String, dynamic>)['posterUrl'] as String?;
          if (posterUrl != null && posterUrl.isNotEmpty) {
            result[entry.key] = posterUrl;
          }
        }
      }
      return result;
    } catch (e) {
      debugPrint('Error reading playlist poster overrides: $e');
      return {};
    }
  }

  /// Get the unique key for a playlist item (public accessor for batch lookups)
  static String getPlaylistItemUniqueKey(Map<String, dynamic> item) =>
      _getPlaylistItemUniqueKey(item);

  /// Clear poster URL override for a playlist item
  static Future<void> clearPlaylistPosterOverride(
    Map<String, dynamic> playlistItem,
  ) async {
    final prefs = await ProfilePreferences.instance();
    final overridesJson = prefs.getString(_playlistPosterOverridesKey);

    if (overridesJson == null) return;

    try {
      final overrides = jsonDecode(overridesJson) as Map<String, dynamic>;
      final key = _getPlaylistItemUniqueKey(playlistItem);

      if (overrides.containsKey(key)) {
        overrides.remove(key);
        await prefs.setString(
          _playlistPosterOverridesKey,
          jsonEncode(overrides),
        );
        debugPrint('✅ Cleared poster override for $key');
      }
    } catch (e) {
      debugPrint('Error clearing playlist poster override: $e');
    }
  }

  /// Clear all playlist poster overrides
  static Future<void> clearAllPlaylistPosterOverrides() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_playlistPosterOverridesKey);
    debugPrint('✅ Cleared all playlist poster overrides');
  }

  // Debrify TV Filter Settings — scoped to Debrify TV only, deliberately
  // separate from the Search tab's default filters above so tuning a channel
  // feed never changes search behaviour (and vice versa).
  static Future<List<String>> getDebrifyTvFilterQualities() async {
    final prefs = await ProfilePreferences.instance();
    final json = prefs.getString(_debrifyTvFilterQualitiesKey);
    if (json == null) return [];
    return List<String>.from(jsonDecode(json));
  }

  static Future<void> setDebrifyTvFilterQualities(
    List<String> qualities,
  ) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_debrifyTvFilterQualitiesKey, jsonEncode(qualities));
  }

  static Future<List<String>> getDebrifyTvFilterSizes() async {
    final prefs = await ProfilePreferences.instance();
    final json = prefs.getString(_debrifyTvFilterSizesKey);
    if (json == null) return [];
    return List<String>.from(jsonDecode(json));
  }

  static Future<void> setDebrifyTvFilterSizes(List<String> sizes) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_debrifyTvFilterSizesKey, jsonEncode(sizes));
  }

  /// Whether the user dismissed the Debrify TV external-player notice forever.
  static Future<bool> getDebrifyTvExternalNoticeDismissed() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_debrifyTvExternalNoticeDismissedKey) ?? false;
  }

  static Future<void> setDebrifyTvExternalNoticeDismissed(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_debrifyTvExternalNoticeDismissedKey, value);
  }

  static const String _iptvSeriesAudioLangKey = 'iptv_series_audio_lang';

  /// The audio LANGUAGE the user last chose for an IPTV series (keyed by the
  /// series' name). Language, not the mpv track ordinal — episodes are
  /// separate files whose track ordering differs, so an ordinal wouldn't
  /// carry. Null when the series has no remembered choice.
  static Future<String?> getIptvSeriesAudioLanguage(String seriesKey) async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_iptvSeriesAudioLangKey);
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map[seriesKey] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Remember the audio language for an IPTV series so later episodes (and
  /// future sessions) default to it.
  static Future<void> setIptvSeriesAudioLanguage(
    String seriesKey,
    String languageCode,
  ) async {
    if (seriesKey.isEmpty || languageCode.isEmpty) return;
    final prefs = await ProfilePreferences.instance();
    Map<String, dynamic> map = {};
    final raw = prefs.getString(_iptvSeriesAudioLangKey);
    if (raw != null) {
      try {
        map = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {}
    }
    map[seriesKey] = languageCode;
    await prefs.setString(_iptvSeriesAudioLangKey, jsonEncode(map));
  }

  // IPTV Playlist Settings

  /// Credential-bearing fields of a stored playlist. Encrypted field-level
  /// rather than sealing the whole element: `content` can be a multi-megabyte
  /// raw M3U body and this getter sits on hot paths, so blob-level AES would
  /// cost real time on TV hardware for data that arrived as a plaintext file
  /// the user chose. Residual: URLs embedded inside a file-imported `content`
  /// body stay plaintext — accepted.
  static const List<String> _iptvPlaylistSecretFields = [
    'url', 'serverUrl', 'username', 'password', 'epgUrl', //
  ];

  /// Restores the `url` key the legacy→profile migration erased.
  ///
  /// An Xtream provider legitimately stores `url: ''` — its endpoint is
  /// [IptvPlaylist.serverUrl]. The migration's shared resource writer stripped
  /// every empty value before sealing, so an Xtream resource migrated by an
  /// affected build carries no `url` key at all, and `IptvPlaylist.fromJson`
  /// threw on the required cast. That took out the ENTIRE playlist list — and
  /// with it the IPTV page — rather than the one provider.
  ///
  /// Fixing the migration cannot help these devices: migration is a one-way
  /// door that never re-runs. Repairing on read is what brings them back, and
  /// it keeps working for anyone who migrated on an affected build and updates
  /// later.
  ///
  /// TWO provider kinds legitimately carry an empty `url`, and both are
  /// repaired: an Xtream login (endpoint in `serverUrl`) and a playlist
  /// imported from a file (body in `content` — see the IPTV settings page,
  /// which writes `url: ''` for exactly that reason). Neither field is
  /// stripped by the migration, so either one identifies a record whose empty
  /// `url` was real rather than missing.
  ///
  /// Still deliberately narrow: a row with none of the three is genuinely
  /// malformed and keeps throwing, because papering over that would turn real
  /// corruption into a silent blank provider.
  static Map<String, dynamic> _repairMigratedIptvRow(Map<String, dynamic> row) {
    if (row['url'] != null) return row;
    if (!_hasText(row['serverUrl']) && !_hasText(row['content'])) return row;
    return <String, dynamic>{...row, 'url': ''};
  }

  static bool _hasText(Object? value) =>
      value is String && value.trim().isNotEmpty;

  /// Get all saved IPTV playlists
  static Future<List<IptvPlaylist>> getIptvPlaylists({
    bool forSettings = true,
    bool forRemoteTransfer = false,
  }) async {
    if (ProfileCollectionResourceFacade.active) {
      final rows = await ProfileCollectionResourceFacade.read(
        types: const <ConnectionResourceType>{
          ConnectionResourceType.iptvM3u,
          ConnectionResourceType.iptvXtream,
        },
        feature: ProfileFeature.iptv,
        forSettings: forSettings,
        forRemoteTransfer: forRemoteTransfer,
      );
      return rows
          .map(_repairMigratedIptvRow)
          .map(IptvPlaylist.fromJson)
          .toList(growable: false);
    }
    final prefs = await ProfilePreferences.instance();
    final jsonList = prefs.getStringList(_iptvPlaylistsKey) ?? [];
    var legacySeen = false;
    var anyDropped = false;
    final playlists = <IptvPlaylist>[];
    for (final json in jsonList) {
      try {
        final opened = await SecretVault.openFields(
          Map<String, dynamic>.from(jsonDecode(json) as Map),
          _iptvPlaylistSecretFields,
        );
        if (opened.wasLegacy) legacySeen = true;
        // A playlist whose url failed to decrypt throws in fromJson and is
        // dropped here — same signed-out semantics as the standalone keys.
        playlists.add(IptvPlaylist.fromJson(opened.map));
      } catch (e) {
        // Skip malformed entries FOR THIS READ only.
        anyDropped = true;
      }
    }
    // Migrate lazily, but never off a lossy read: rewriting while an entry
    // failed (possibly a transient vault-key hiccup) would turn a one-launch
    // read error into permanent deletion. A later clean read migrates.
    if (legacySeen && !anyDropped) {
      await setIptvPlaylists(playlists);
    }
    return playlists;
  }

  /// Save IPTV playlists.
  ///
  /// Virtual playlists (Favorites, custom lists, Continue watching, Stremio
  /// addon shelves) are dropped here rather than trusted not to arrive: the
  /// page's own list holds real and virtual entries side by side, and a
  /// virtual one that reached the preference would be restored AND injected
  /// on the next load — two entries with the same id, where id-only equality
  /// makes lookups resolve the stale copy.
  static Future<void> setIptvPlaylists(
    List<IptvPlaylist> playlists, {
    bool revokeBorrowers = false,
  }) async {
    if (ProfileCollectionResourceFacade.active) {
      final stored = playlists.where((playlist) => !playlist.isVirtual);
      await ProfileCollectionResourceFacade.replace(
        types: const <ConnectionResourceType>{
          ConnectionResourceType.iptvM3u,
          ConnectionResourceType.iptvXtream,
        },
        feature: ProfileFeature.iptv,
        items: <ResourceCollectionItem>[
          for (final playlist in stored)
            ResourceCollectionItem(
              type: playlist.isXtreamCodes
                  ? ConnectionResourceType.iptvXtream
                  : ConnectionResourceType.iptvM3u,
              label: playlist.name,
              publicConfig: <String, dynamic>{
                'playlistName': playlist.name,
                'providerKind': playlist.isXtreamCodes ? 'xtream' : 'm3u',
              },
              secretConfig: playlist.toJson(),
              sourceResourceId: playlist.connectionResourceId,
            ),
        ],
        revokeBorrowers: revokeBorrowers,
      );
      return;
    }
    final prefs = await ProfilePreferences.instance();
    final jsonList = <String>[];
    for (final p in playlists.where((p) => !p.isVirtual)) {
      jsonList.add(
        jsonEncode(
          await SecretVault.sealFields(p.toJson(), _iptvPlaylistSecretFields),
        ),
      );
    }
    await prefs.setStringList(_iptvPlaylistsKey, jsonList);
  }

  /// Persists an IPTV collection and returns the authoritative records.
  ///
  /// In profile mode a collection write can mint or rotate connection
  /// resources, so the caller's input objects are deliberately not execution
  /// capabilities. UI code that keeps using those objects would have no
  /// resource ID for a new playlist, or a stale revision for an existing one.
  static Future<List<IptvPlaylist>> setIptvPlaylistsAndReload(
    List<IptvPlaylist> playlists, {
    required bool forSettings,
    bool revokeBorrowers = false,
  }) async {
    final expectedScope = ProfileCollectionResourceFacade.active
        ? ProfileRuntime.scope.value
        : null;
    await setIptvPlaylists(playlists, revokeBorrowers: revokeBorrowers);
    if (expectedScope != null &&
        (!ProfileCollectionResourceFacade.active ||
            ProfileRuntime.scope.value != expectedScope)) {
      throw StateError('Profile changed while saving IPTV playlists');
    }
    final saved = await getIptvPlaylists(forSettings: forSettings);
    if (expectedScope != null &&
        (!ProfileCollectionResourceFacade.active ||
            ProfileRuntime.scope.value != expectedScope)) {
      throw StateError('Profile changed while loading IPTV playlists');
    }
    return saved;
  }

  /// Get default IPTV playlist ID
  static Future<String?> getIptvDefaultPlaylist() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_iptvDefaultPlaylistKey);
  }

  /// Set default IPTV playlist ID
  static Future<void> setIptvDefaultPlaylist(String? playlistId) async {
    final prefs = await ProfilePreferences.instance();
    if (playlistId == null || playlistId.isEmpty) {
      await prefs.remove(_iptvDefaultPlaylistKey);
    } else {
      await prefs.setString(_iptvDefaultPlaylistKey, playlistId);
    }
  }

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
        for (final playlist in await getIptvPlaylists()) {
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
      _iptvLastLiveChannelKey,
      jsonEncode({
        'url': url,
        'name': name,
        if (playlistId != null && playlistId.isNotEmpty)
          'playlistId': playlistId,
        if (channelNumber != null) 'channelNumber': channelNumber,
        if (group != null && group.isNotEmpty) 'group': group,
        if (logoUrl != null && logoUrl.isNotEmpty) 'logoUrl': logoUrl,
        if (httpHeaders != null && httpHeaders.isNotEmpty)
          'httpHeaders': httpHeaders,
        if (serverUrl != null && serverUrl.isNotEmpty) 'serverUrl': serverUrl,
        if (username != null && username.isNotEmpty) 'username': username,
        'playedAt': DateTime.now().millisecondsSinceEpoch,
      }),
    );
  }

  /// The last live channel that reached a playing state, or null.
  static Future<Map<String, dynamic>?> getIptvLastLiveChannel() async {
    final prefs = await ProfilePreferences.instance();
    final raw = await SecretVault.getString(prefs, _iptvLastLiveChannelKey);
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
    await prefs.remove(_iptvLastLiveChannelKey);
  }

  // ==========================================================================
  // Startup channel (boot straight into a live IPTV channel)
  //
  // Reuses the surviving `startup_auto_launch_enabled` / `startup_mode` keys
  // from the removed general Launch-on-Startup feature; `startup_mode` is set
  // to 'iptv' so a future second mode can coexist without another master flag.
  // ==========================================================================

  static const String _startupIptvModeKey = 'startup_iptv_mode';
  static const String _startupIptvChannelKey = 'startup_iptv_channel';

  /// 'last' (whatever played most recently) or 'pinned' (a chosen channel).
  static const String startupIptvModeLast = 'last';
  static const String startupIptvModePinned = 'pinned';

  /// Payload marker meaning "nothing is remembered yet — start on whatever the
  /// IPTV page lands on". Never persisted; only ever set by [warmStartupIptv].
  static const String startupIptvFirstAvailable = 'firstAvailable';

  static Future<bool> getStartupIptvEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return (prefs.getBool(_startupAutoLaunchEnabledKey) ?? false) &&
        prefs.getString(_startupModeKey) == 'iptv';
  }

  static Future<void> setStartupIptvEnabled(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_startupAutoLaunchEnabledKey, enabled);
    if (enabled) {
      await prefs.setString(_startupModeKey, 'iptv');
    } else {
      // Leave the mode behind rather than clearing it: re-enabling should come
      // back to IPTV, not to a blank slate.
      await prefs.remove(_startupModeKey);
    }
  }

  static Future<String> getStartupIptvMode() async {
    final prefs = await ProfilePreferences.instance();
    final mode = prefs.getString(_startupIptvModeKey);
    return mode == startupIptvModePinned
        ? startupIptvModePinned
        : startupIptvModeLast;
  }

  static Future<void> setStartupIptvMode(String mode) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(
      _startupIptvModeKey,
      mode == startupIptvModePinned
          ? startupIptvModePinned
          : startupIptvModeLast,
    );
  }

  /// The pinned startup channel. Same blob shape as [setIptvLastLiveChannel],
  /// so both modes resolve through one code path at launch.
  static Future<Map<String, dynamic>?> getStartupIptvChannel() async {
    final prefs = await ProfilePreferences.instance();
    final raw = await SecretVault.getString(prefs, _startupIptvChannelKey);
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
        for (final playlist in await getIptvPlaylists()) {
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
      _startupIptvChannelKey,
      jsonEncode({
        'url': url,
        'name': name,
        if (playlistId != null && playlistId.isNotEmpty)
          'playlistId': playlistId,
        if (channelNumber != null) 'channelNumber': channelNumber,
        if (group != null && group.isNotEmpty) 'group': group,
        if (logoUrl != null && logoUrl.isNotEmpty) 'logoUrl': logoUrl,
        if (httpHeaders != null && httpHeaders.isNotEmpty)
          'httpHeaders': httpHeaders,
        if (serverUrl != null && serverUrl.isNotEmpty) 'serverUrl': serverUrl,
        if (username != null && username.isNotEmpty) 'username': username,
      }),
    );
  }

  static Future<void> clearStartupIptvChannel() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_startupIptvChannelKey);
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
  static Map<String, dynamic>? get startupIptvChannelCached =>
      _startupIptvChannelCached;

  /// Resolve the startup channel once, before `runApp`. Never throws — a
  /// failure here must degrade to "no startup channel", never to a broken boot.
  static Future<void> warmStartupIptv() async {
    try {
      if (!await getStartupIptvEnabled()) return;
      final mode = await getStartupIptvMode();
      final channel = mode == startupIptvModePinned
          ? await getStartupIptvChannel()
          : await getIptvLastLiveChannel();
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

  // ==========================================================================
  // Stremio TV Settings
  // ==========================================================================

  /// Get the Stremio TV rotation interval in minutes (default: 90)
  static Future<int> getStremioTvRotationMinutes() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getInt(_stremioTvRotationMinutesKey) ?? 90;
  }

  /// Save the Stremio TV rotation interval in minutes
  static Future<void> setStremioTvRotationMinutes(int value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setInt(_stremioTvRotationMinutesKey, value);
  }

  /// Get the Stremio TV series rotation interval in minutes (default: 45)
  static Future<int> getStremioTvSeriesRotationMinutes() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getInt(_stremioTvSeriesRotationMinutesKey) ?? 45;
  }

  /// Save the Stremio TV series rotation interval in minutes
  static Future<void> setStremioTvSeriesRotationMinutes(int value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setInt(_stremioTvSeriesRotationMinutesKey, value);
  }

  /// Get whether Stremio TV picks a random episode each time (default: false)
  static Future<bool> getStremioTvRandomEpisodes() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_stremioTvRandomEpisodesKey) ?? false;
  }

  /// Save whether Stremio TV picks a random episode each time
  static Future<void> setStremioTvRandomEpisodes(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_stremioTvRandomEpisodesKey, value);
  }

  /// Get whether Stremio TV auto-refreshes catalogs (default: true)
  static Future<bool> getStremioTvAutoRefresh() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_stremioTvAutoRefreshKey) ?? true;
  }

  /// Save whether Stremio TV auto-refreshes catalogs
  static Future<void> setStremioTvAutoRefresh(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_stremioTvAutoRefreshKey, value);
  }

  /// Get whether Stremio TV hides now-playing details (default: false)
  static Future<bool> getStremioTvHideNowPlaying() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_stremioTvHideNowPlayingKey) ?? false;
  }

  /// Save whether Stremio TV hides now-playing details
  static Future<void> setStremioTvHideNowPlaying(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_stremioTvHideNowPlayingKey, value);
  }

  static Future<bool> getStremioTvTorrentsFirst() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_stremioTvTorrentsFirstKey) ?? true;
  }

  static Future<void> setStremioTvTorrentsFirst(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_stremioTvTorrentsFirstKey, value);
  }

  /// Get preferred quality for Stremio TV streams (default: 'auto')
  /// Values: 'auto', '720p', '1080p', '2160p'
  static Future<String> getStremioTvPreferredQuality() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_stremioTvPreferredQualityKey) ?? 'auto';
  }

  /// Save preferred quality for Stremio TV streams
  static Future<void> setStremioTvPreferredQuality(String value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_stremioTvPreferredQualityKey, value);
  }

  /// Get preferred debrid provider for Stremio TV (auto = first available)
  static Future<String> getStremioTvDebridProvider() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_stremioTvDebridProviderKey) ?? 'auto';
  }

  /// Save preferred debrid provider for Stremio TV
  static Future<void> setStremioTvDebridProvider(String value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_stremioTvDebridProviderKey, value);
  }

  /// Get max start position percent for Stremio TV (0 = always from beginning, -1 = no limit)
  static Future<int> getStremioTvMaxStartPercent() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getInt(_stremioTvMaxStartPercentKey) ?? -1;
  }

  /// Save max start position percent for Stremio TV
  static Future<void> setStremioTvMaxStartPercent(int value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setInt(_stremioTvMaxStartPercentKey, value);
  }

  // ==========================================================================
  // Stremio TV Channel Favorites
  // ==========================================================================

  /// Check if a Stremio TV channel is favorited
  static Future<bool> isStremioTvChannelFavorited(String channelId) async {
    final prefs = await ProfilePreferences.instance();
    final favoritesJson = prefs.getString(_stremioTvFavoriteChannelsKey);

    if (favoritesJson == null) return false;

    try {
      final favorites = jsonDecode(favoritesJson) as Map<String, dynamic>;
      return favorites.containsKey(channelId);
    } catch (e) {
      debugPrint('Error reading Stremio TV channel favorites: $e');
      return false;
    }
  }

  /// Set favorite status for a Stremio TV channel
  static Future<void> setStremioTvChannelFavorited(
    String channelId,
    bool isFavorited,
  ) async {
    final prefs = await ProfilePreferences.instance();
    final favoritesJson = prefs.getString(_stremioTvFavoriteChannelsKey);

    Map<String, dynamic> favorites = {};
    if (favoritesJson != null) {
      try {
        favorites = jsonDecode(favoritesJson) as Map<String, dynamic>;
      } catch (_) {}
    }

    if (isFavorited) {
      favorites[channelId] = true;
    } else {
      favorites.remove(channelId);
    }

    await prefs.setString(_stremioTvFavoriteChannelsKey, jsonEncode(favorites));
  }

  /// Get all favorite Stremio TV channel IDs
  static Future<Set<String>> getStremioTvFavoriteChannelIds() async {
    final prefs = await ProfilePreferences.instance();
    final favoritesJson = prefs.getString(_stremioTvFavoriteChannelsKey);

    if (favoritesJson == null) return {};

    try {
      final favorites = jsonDecode(favoritesJson) as Map<String, dynamic>;
      return favorites.keys.toSet();
    } catch (e) {
      debugPrint('Error reading Stremio TV channel favorites: $e');
      return {};
    }
  }

  // ==========================================================================
  // Stremio TV Local Catalogs
  // ==========================================================================

  /// Get all locally imported catalogs for Stremio TV.
  static Future<List<Map<String, dynamic>>> getStremioTvLocalCatalogs() async {
    final prefs = await ProfilePreferences.instance();
    final json = prefs.getString(_stremioTvLocalCatalogsKey);
    if (json == null) return [];

    try {
      final list = await decodeJsonAsync(json) as List<dynamic>;
      return list.whereType<Map<String, dynamic>>().toList();
    } catch (e) {
      debugPrint('Error reading Stremio TV local catalogs: $e');
      return [];
    }
  }

  /// Save all locally imported catalogs for Stremio TV.
  static Future<void> setStremioTvLocalCatalogs(
    List<Map<String, dynamic>> catalogs,
  ) async {
    final prefs = await ProfilePreferences.instance();
    if (catalogs.isEmpty) {
      await prefs.remove(_stremioTvLocalCatalogsKey);
    } else {
      await prefs.setString(_stremioTvLocalCatalogsKey, jsonEncode(catalogs));
    }
  }

  /// The picker keeps its captured namespace while waiting for snapshots.
  /// Recheck at the actual commit and propagate persistence/budget refusal.
  static Future<bool> _setStremioTvLocalCatalogsIfCurrent(
    List<Map<String, dynamic>> catalogs,
    bool Function() canContinue,
  ) async {
    if (!canContinue()) return false;
    final prefs = await ProfilePreferences.instance();
    return ProfilePreferences.synchronizeExternalMutation(() async {
      if (!canContinue()) return false;
      return catalogs.isEmpty
          ? await prefs.remove(_stremioTvLocalCatalogsKey)
          : await prefs.setString(
              _stremioTvLocalCatalogsKey,
              jsonEncode(catalogs),
            );
    }, marksMutation: false);
  }

  /// Add a single local catalog. Returns false if a catalog with the same ID
  /// already exists.
  static Future<bool> addStremioTvLocalCatalog(
    Map<String, dynamic> catalog, {
    bool Function()? canContinue,
  }) async {
    if (canContinue?.call() == false) return false;
    final existing = await getStremioTvLocalCatalogs();
    if (canContinue?.call() == false) return false;
    final id = catalog['id'] as String?;
    if (id == null) return false;
    if (existing.any((c) => c['id'] == id)) return false;
    existing.add(catalog);
    if (canContinue != null) {
      return _setStremioTvLocalCatalogsIfCurrent(existing, canContinue);
    }
    await setStremioTvLocalCatalogs(existing);
    return true;
  }

  /// Remove a local catalog by its ID.
  static Future<void> removeStremioTvLocalCatalog(String catalogId) async {
    final existing = await getStremioTvLocalCatalogs();
    existing.removeWhere((c) => c['id'] == catalogId);
    await setStremioTvLocalCatalogs(existing);
  }

  /// Update an existing local catalog by its ID (replaces the entry in-place).
  static Future<bool> updateStremioTvLocalCatalog(
    Map<String, dynamic> catalog, {
    bool Function()? canContinue,
  }) async {
    if (canContinue?.call() == false) return false;
    final existing = await getStremioTvLocalCatalogs();
    if (canContinue?.call() == false) return false;
    final id = catalog['id'] as String?;
    if (id == null) return false;
    final idx = existing.indexWhere((c) => c['id'] == id);
    if (idx < 0) return false;
    existing[idx] = catalog;
    if (canContinue != null) {
      return _setStremioTvLocalCatalogsIfCurrent(existing, canContinue);
    }
    await setStremioTvLocalCatalogs(existing);
    return true;
  }

  // --------------------------------------------------------------------------
  // Stremio TV Catalog Repo URLs
  // --------------------------------------------------------------------------

  /// Get saved catalog repository URLs.
  static Future<List<String>> getStremioTvCatalogRepoUrls() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getStringList(_stremioTvCatalogRepoUrlsKey) ?? [];
  }

  /// Set catalog repository URLs.
  static Future<void> setStremioTvCatalogRepoUrls(List<String> urls) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setStringList(_stremioTvCatalogRepoUrlsKey, urls);
  }

  /// Add a catalog repository URL. Returns false if already present.
  static Future<bool> addStremioTvCatalogRepoUrl(String url) async {
    final urls = await getStremioTvCatalogRepoUrls();
    if (urls.contains(url)) return false;
    urls.add(url);
    await setStremioTvCatalogRepoUrls(urls);
    return true;
  }

  /// Remove a catalog repository URL.
  static Future<void> removeStremioTvCatalogRepoUrl(String url) async {
    final urls = await getStremioTvCatalogRepoUrls();
    urls.remove(url);
    await setStremioTvCatalogRepoUrls(urls);
  }

  // ==========================================================================
  // Stremio TV Channel Filters
  // ==========================================================================

  static const String _stremioTvDisabledChannelFiltersKey =
      'stremio_tv_disabled_channel_filters_v1';

  /// Get set of disabled channel filter IDs (addon, catalog, or genre level).
  static Future<Set<String>> getStremioTvDisabledFilters() async {
    final prefs = await ProfilePreferences.instance();
    final json = prefs.getString(_stremioTvDisabledChannelFiltersKey);
    if (json == null) return {};

    try {
      final list = jsonDecode(json) as List<dynamic>;
      return list.cast<String>().toSet();
    } catch (e) {
      debugPrint('Error reading Stremio TV disabled filters: $e');
      return {};
    }
  }

  /// Save set of disabled channel filter IDs.
  static Future<void> setStremioTvDisabledFilters(Set<String> disabled) async {
    final prefs = await ProfilePreferences.instance();
    if (disabled.isEmpty) {
      await prefs.remove(_stremioTvDisabledChannelFiltersKey);
    } else {
      await prefs.setString(
        _stremioTvDisabledChannelFiltersKey,
        jsonEncode(disabled.toList()),
      );
    }
  }

  /// Clears this owner before the existing profile handoff ledger stamp.
  static void resetProfileCaches() {
    debrifyTvStyleCached = 'grid';
    iptvStyleCached = kIptvStyleDefault;
    _startupIptvChannelCached = null;
  }
}
