import 'dart:async';
import 'dart:io';
import 'package:debrify/models/custom_series_identity.dart';
import 'package:debrify/models/series_playlist.dart';
import 'package:debrify/models/stremio_subtitle.dart';
import 'package:debrify/screens/video_player/services/external_subtitle_payload.dart';
import 'package:debrify/screens/video_player/services/subtitle_track_utils.dart';
import 'package:debrify/screens/video_player/utils/subtitle_priority_selection.dart';
import 'package:debrify/services/storage/subtitle_settings_storage.dart';
import 'package:debrify/services/stremio_subtitle_service.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart' as mk;
import 'package:path_provider/path_provider.dart';

abstract interface class VpAddonSubtitlesHost {
  bool get mounted;
  int get addonSubtitleFetchToken;
  Future<bool> applyDefaultSubtitleLanguage({
    bool ignoreSourcePriority = false,
  });
  Future<bool> applyForcedSubtitle(String? language, bool Function() current);
  bool get audioAllowsAutomaticSubtitles;
  List<AddonSubtitleSlot>? get cachedAddonSlots;
  set cachedAddonSlots(List<AddonSubtitleSlot>? v);
  List<StremioSubtitle>? get cachedStremioSubtitles;
  set cachedStremioSubtitles(List<StremioSubtitle>? v);
  String? get cachedSubtitleKey;
  set cachedSubtitleKey(String? v);
  int? get currentStremioTvContentEpisode;
  int? get currentStremioTvContentSeason;
  int? get effectiveContentEpisode;
  String? get effectiveContentImdbId;
  int? get effectiveContentSeason;
  String? get effectiveContentType;
  bool get embeddedSubtitleApplied;
  set embeddedSubtitleApplied(bool v);
  SeriesEpisode? findSeriesEpisodeForCurrentIndex(
    SeriesPlaylist seriesPlaylist,
  );
  int? get manualContentEpisode;
  String? get manualContentImdbId;
  int? get manualContentSeason;
  String? get manualContentType;
  mk.Player get player;
  String? get selectedStremioSubtitleId;
  set selectedStremioSubtitleId(String? v);
  SeriesPlaylist? get seriesPlaylist;
  String? get singleFileImdbId;
  int get subtitleAudioRevision;
  bool get subtitleForcedOnly;
  bool get trackPreferencesReadyForAddonSubtitles;
  bool get userManuallySelectedSubtitle;
  int? get contentSeason;
  int? get contentEpisode;
  void setActiveExternalSubtitlePath(String? path);
  Future<bool> setSubtitleTrackWithDiagnostics(
    mk.SubtitleTrack track, {
    required String source,
    bool Function()? isCurrent,
  });
}

class VpAddonSubtitles {
  VpAddonSubtitles(this._host);
  final VpAddonSubtitlesHost _host;

  final subtitlePrioritySelectionQueue =
      SubtitlePrioritySelectionQueue(); // Guard against stale async fetches on content switch
  // Paths of temp SRT/VTT files we've written for addon subtitles. We hand
  // these to libmpv as file URIs so it auto-detects encoding (GBK, Big5,
  // Windows-125x, etc.) instead of our http client pre-decoding as UTF-8.
  final Set<String> tempSubtitleFiles = {};

  /// Download an addon subtitle's raw bytes and write them to a temp file.
  ///
  /// Returning a file path (rather than a pre-decoded string) lets libmpv
  /// auto-detect the character encoding via its `sub-codepage=auto` default,
  /// which correctly handles GBK, Big5, EUC-KR, Windows-125x, etc. Pre-decoding
  /// via `http.Response.body` would silently corrupt non-UTF-8 subtitle files.
  Future<String?> downloadStremioSubtitleToTempFile(StremioSubtitle sub) async {
    try {
      final uri = Uri.parse(sub.url);
      final dir = await getTemporaryDirectory();
      final stem = externalSubtitleCacheStem(sub.url);
      for (final ext in const [
        'srt',
        'vtt',
        'ass',
        'ssa',
        'ttml',
        'xml',
        'sub',
      ]) {
        final cached = File('${dir.path}/stremio_sub_$stem.$ext');
        if (cached.existsSync()) {
          final cachedLength = cached.lengthSync();
          if (cachedLength > 0 && cachedLength <= maxDecodedSubtitleBytes) {
            tempSubtitleFiles.add(cached.path);
            return cached.path;
          }
          cached.deleteSync();
        }
      }

      final client = http.Client();
      late http.StreamedResponse response;
      try {
        response = await client
            .send(http.Request('GET', uri))
            .timeout(const Duration(seconds: 15));
        final declaredLength = response.contentLength;
        if (declaredLength != null &&
            declaredLength > maxSubtitleResponseBytes) {
          debugPrint(
            'VideoPlayer: Subtitle download rejected: '
            '$declaredLength bytes exceeds limit',
          );
          return null;
        }
        if (response.statusCode != 200) {
          debugPrint(
            'VideoPlayer: Subtitle download failed: HTTP ${response.statusCode}',
          );
          return null;
        }

        final responseBytes = await readBoundedSubtitleResponse(
          response.stream,
        ).timeout(const Duration(seconds: 15));
        final payload = prepareExternalSubtitlePayload(responseBytes, uri);
        final file = File('${dir.path}/stremio_sub_$stem.${payload.extension}');
        final partial = File('${file.path}.part');
        await partial.writeAsBytes(payload.bytes, flush: true);
        if (file.existsSync()) file.deleteSync();
        await partial.rename(file.path);
        tempSubtitleFiles.add(file.path);
        debugPrint(
          'VideoPlayer: Subtitle written to temp file: ${file.path} '
          '(${payload.bytes.length} bytes)',
        );
        return file.path;
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('VideoPlayer: Subtitle download/write failed: $e');
      return null;
    }
  }

  /// Load a replacement first, then unload older addon tracks. A malformed
  /// replacement therefore leaves the currently working subtitle untouched.
  Future<bool> applyExternalSubtitleTrack(
    mk.SubtitleTrack track, {
    bool Function()? isCurrent,
  }) async {
    // Track IDs are small mpv ordinals and may be reused by the next media.
    // Keep the content generation with this operation so a delayed apply can
    // never remove a same-numbered subtitle from newly opened content.
    final contentToken = _host.addonSubtitleFetchToken;
    final oldExternalIds = _host.player.state.tracks.subtitle
        .where(isAppManagedAddonSubtitleTrack)
        .map((subtitle) => subtitle.id)
        .toList(growable: false);

    final applied = await _host.setSubtitleTrackWithDiagnostics(
      track,
      source: 'addon-external',
      isCurrent: isCurrent,
    );
    if (!applied) return false;

    final platform = _host.player.platform;
    if (platform is mk.NativePlayer) {
      for (final id in oldExternalIds) {
        if (!_host.mounted ||
            contentToken != _host.addonSubtitleFetchToken ||
            (isCurrent != null && !isCurrent())) {
          debugPrint(
            'VideoPlayer: Content changed during addon subtitle cleanup; '
            'stopping before track $id',
          );
          return false;
        }
        try {
          await platform.command(['sub-remove', id]);
        } catch (e) {
          debugPrint('VideoPlayer: Failed to unload external subtitle $id: $e');
        }
      }
    }
    return true;
  }

  /// Delete any temp subtitle files we've written. Called from dispose.
  void cleanupTempSubtitleFilesSync() {
    for (final path in tempSubtitleFiles) {
      try {
        File(path).deleteSync();
      } catch (e) {
        debugPrint('VideoPlayer: Failed to delete temp subtitle $path: $e');
      }
    }
    tempSubtitleFiles.clear();
  }

  /// Fetch Stremio addon subtitles proactively and auto-select if no embedded subtitle was applied.
  /// This mirrors the Android TV behavior where subtitles are always fetched on playback start.
  Future<void> fetchAndMaybeAutoSelectAddonSubtitle() async {
    if (CustomSeriesIdentity.isCustom(_host.effectiveContentImdbId) &&
        _host.manualContentImdbId == null) {
      return;
    }
    // Capture token at start to detect if content changes during async operations
    final fetchToken = _host.addonSubtitleFetchToken;

    try {
      // Get content info for Stremio subtitle fetch
      final seriesPlaylist = _host.seriesPlaylist;
      String? imdbId;
      String contentType;
      int? season;
      int? episode;

      if (_host.manualContentImdbId != null &&
          _host.manualContentImdbId!.isNotEmpty) {
        imdbId = _host.manualContentImdbId;
        contentType = _host.manualContentType == 'series' ? 'series' : 'movie';
        if (contentType == 'series') {
          season = _host.manualContentSeason;
          episode = _host.manualContentEpisode;
          if ((season == null || episode == null) &&
              seriesPlaylist != null &&
              seriesPlaylist.isSeries) {
            final currentEp = _host.findSeriesEpisodeForCurrentIndex(
              seriesPlaylist,
            );
            season ??= currentEp?.seriesInfo.season;
            episode ??= currentEp?.seriesInfo.episode;
          }
          season ??= _host.currentStremioTvContentSeason ?? _host.contentSeason;
          episode ??=
              _host.currentStremioTvContentEpisode ?? _host.contentEpisode;
        }
      } else if (seriesPlaylist != null && seriesPlaylist.isSeries) {
        imdbId = seriesPlaylist.imdbId ?? _host.effectiveContentImdbId;
        contentType = 'series';
        // Get current episode info from playlist using current index
        final currentEp = _host.findSeriesEpisodeForCurrentIndex(
          seriesPlaylist,
        );
        if (currentEp != null) {
          season = currentEp.seriesInfo.season;
          episode = currentEp.seriesInfo.episode;
        }
      } else {
        // Use widget's content IMDB ID or single file IMDB ID
        imdbId = _host.effectiveContentImdbId ?? _host.singleFileImdbId;
        // Single-file series playback: use widget params for S/E
        if (_host.effectiveContentType == 'series' &&
            _host.effectiveContentSeason != null &&
            _host.effectiveContentEpisode != null) {
          contentType = 'series';
          season = _host.effectiveContentSeason;
          episode = _host.effectiveContentEpisode;
        } else {
          contentType = 'movie';
        }
      }

      // Need IMDB ID to fetch Stremio subtitles
      if (imdbId == null || imdbId.isEmpty) {
        await applySubtitleSourcePriority(
          const [],
          fetchToken,
          discoveryReady: false,
        );
        return;
      }
      debugPrint(
        'SubAuto: addon auto-select start — imdb=$imdbId type=$contentType s=$season e=$episode',
      );

      // Build cache key
      final cacheKey = season != null && episode != null
          ? '$imdbId:$season:$episode'
          : imdbId;

      // Check if we have cached subtitles
      List<StremioSubtitle> subtitles;
      if (_host.cachedSubtitleKey == cacheKey &&
          _host.cachedStremioSubtitles != null) {
        subtitles = _host.cachedStremioSubtitles!;
        debugPrint(
          'VideoPlayer: Using ${subtitles.length} cached addon subtitles',
        );
      } else {
        // Fetch Stremio subtitles proactively (per-addon slots, so the
        // sheet's addon groups are warm when opened)
        debugPrint('VideoPlayer: Fetching addon subtitles (IMDB: $imdbId)');
        final slots = await StremioSubtitleService.instance.fetchSubtitleSlots(
          type: contentType,
          imdbId: imdbId,
          season: season,
          episode: episode,
          onUpdate: (slots) {
            if (!_host.mounted || fetchToken != _host.addonSubtitleFetchToken) {
              return;
            }
            unawaited(applySubtitleSourcePriority(slots, fetchToken));
          },
        );
        subtitles = AddonSubtitleSlot.flatten(slots);

        // Check if content changed during fetch
        if (fetchToken != _host.addonSubtitleFetchToken) {
          debugPrint(
            'VideoPlayer: Content changed during addon subtitle fetch, discarding results',
          );
          return;
        }

        // Cache the results
        _host.cachedStremioSubtitles = subtitles;
        _host.cachedAddonSlots = slots;
        _host.cachedSubtitleKey = cacheKey;
        debugPrint(
          'VideoPlayer: Fetched and cached ${subtitles.length} addon subtitles',
        );
      }

      await applySubtitleSourcePriority(
        _host.cachedAddonSlots ?? const [],
        fetchToken,
      );
    } catch (e) {
      debugPrint('SubAuto: auto-select FAILED with exception: $e');
    }
  }

  Future<void> applySubtitleSourcePriority(
    List<AddonSubtitleSlot> slots,
    int token, {
    bool discoveryReady = true,
  }) async {
    if (!_host.mounted || token != _host.addonSubtitleFetchToken) return;
    await subtitlePrioritySelectionQueue.submit(
      SubtitlePriorityUpdate(token, slots, discoveryReady: discoveryReady),
      applySubtitlePriorityUpdate,
    );
  }

  Future<void> applySubtitlePriorityUpdate(
    SubtitlePriorityUpdate update,
  ) async {
    final audioRevision = _host.subtitleAudioRevision;
    bool valid() =>
        audioRevision == _host.subtitleAudioRevision &&
        _host.audioAllowsAutomaticSubtitles &&
        _host.mounted &&
        update.token == _host.addonSubtitleFetchToken &&
        _host.trackPreferencesReadyForAddonSubtitles &&
        !_host.embeddedSubtitleApplied &&
        !_host.userManuallySelectedSubtitle &&
        _host.selectedStremioSubtitleId == null;
    if (!valid()) return;
    try {
      final language =
          await SubtitleSettingsStorage.getDefaultSubtitleLanguage();
      if (_host.subtitleForcedOnly) {
        if (valid()) await _host.applyForcedSubtitle(language, valid);
        return;
      }
      final saved = await SubtitleSettingsStorage.getSubtitleSourcePriority();
      String? selectedPath;
      final result = await selectSubtitleBySourcePriority(
        saved: saved,
        language: language,
        slots: update.slots,
        discoveryReady: update.discoveryReady,
        isCurrent: valid,
        tryEmbedded: () async {
          // A manual title search explicitly asks for online subtitles.
          if (_host.manualContentImdbId?.isNotEmpty == true) return false;
          return _host.applyDefaultSubtitleLanguage(ignoreSourcePriority: true);
        },
        tryAddon: (sub) async {
          final path = await downloadStremioSubtitleToTempFile(sub);
          if (!valid() || path == null) return false;
          final applied = await applyExternalSubtitleTrack(
            mk.SubtitleTrack.uri(
              path,
              title: sub.displayName,
              language: sub.lang,
            ),
            isCurrent: valid,
          );
          if (applied) selectedPath = path;
          return applied;
        },
      );
      if (!valid() || result == null) return;
      if (result.addon case final sub?) {
        _host.selectedStremioSubtitleId = sub.id;
        _host.setActiveExternalSubtitlePath(selectedPath!);
      } else if (!result.provisional) {
        _host.embeddedSubtitleApplied = true;
      }
    } catch (e) {
      debugPrint('SubAuto: source priority apply failed: $e');
    }
  }
}
