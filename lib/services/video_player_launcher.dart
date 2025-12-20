import 'dart:async';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

import '../models/series_playlist.dart';
import '../models/rd_file_node.dart';
import '../screens/video_player_screen.dart';
import '../services/android_native_downloader.dart';
import '../services/android_tv_player_bridge.dart';
import '../services/debrid_service.dart';
import '../services/main_page_bridge.dart';
import '../services/storage_service.dart';
import '../services/torbox_service.dart';
import '../services/pikpak_api_service.dart';
import '../utils/series_parser.dart';
import '../widgets/view_mode_dropdown.dart';

final Map<String, String> _resolvedStreamCache = <String, String>{};

void _cacheResolvedStream(String? resumeId, String url) {
  if (resumeId == null) return;
  if (url.isEmpty) return;
  _resolvedStreamCache[resumeId] = url;
}

void _clearResolvedStreams(Iterable<String?> resumeIds) {
  for (final id in resumeIds) {
    if (id == null) continue;
    _resolvedStreamCache.remove(id);
  }
}

class VideoPlayerLaunchArgs {
  final String videoUrl;
  final String title;
  final String? subtitle;
  final List<PlaylistEntry>? playlist;
  final int? startIndex;
  final String? rdTorrentId;
  final String? pikpakCollectionId;
  final Future<Map<String, String>?> Function()? requestMagicNext;
  final Future<Map<String, dynamic>?> Function()? requestNextChannel;
  final bool startFromRandom;
  final int randomStartMaxPercent;
  final bool hideSeekbar;
  final bool showChannelName;
  final String? channelName;
  final int? channelNumber;
  final bool showVideoTitle;
  final bool hideOptions;
  final bool hideBackButton;
  final bool Function()? isAndroidTvOverride;
  final bool disableAutoResume;
  final FolderViewMode? viewMode;
  final RDFileNode? folderTree;

  const VideoPlayerLaunchArgs({
    required this.videoUrl,
    required this.title,
    this.subtitle,
    this.playlist,
    this.startIndex,
    this.rdTorrentId,
    this.pikpakCollectionId,
    this.requestMagicNext,
    this.requestNextChannel,
    this.startFromRandom = false,
    this.randomStartMaxPercent = 40,
    this.hideSeekbar = false,
    this.showChannelName = false,
    this.channelName,
    this.channelNumber,
    this.showVideoTitle = true,
    this.hideOptions = false,
    this.hideBackButton = false,
    this.isAndroidTvOverride,
    this.disableAutoResume = false,
    this.viewMode,
    this.folderTree,
  });

  VideoPlayerScreen toWidget() {
    return VideoPlayerScreen(
      videoUrl: videoUrl,
      title: title,
      subtitle: subtitle,
      playlist: playlist,
      startIndex: startIndex,
      rdTorrentId: rdTorrentId,
      pikpakCollectionId: pikpakCollectionId,
      requestMagicNext: requestMagicNext,
      requestNextChannel: requestNextChannel,
      startFromRandom: startFromRandom,
      randomStartMaxPercent: randomStartMaxPercent,
      hideSeekbar: hideSeekbar,
      showChannelName: showChannelName,
      channelName: channelName,
      channelNumber: channelNumber,
      showVideoTitle: showVideoTitle,
      hideOptions: hideOptions,
      hideBackButton: hideBackButton,
      disableAutoResume: disableAutoResume,
      viewMode: viewMode,
      folderTree: folderTree,
    );
  }
}

class VideoPlayerLauncher {
  static Future<void> push(BuildContext context, VideoPlayerLaunchArgs args) async {
    // Apply view mode ordering to playlist BEFORE launching player
    // This ensures navigation order matches what user sees in UI
    final reorderedArgs = _applyViewModeOrdering(args);

    final isTv = await _isAndroidTv(reorderedArgs.isAndroidTvOverride);
    if (isTv) {
      final launched = await _launchOnAndroidTv(reorderedArgs);
      if (launched) {
        return;
      }
    }

    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => reorderedArgs.toWidget()),
    );
  }

  /// Apply view mode ordering to playlist entries
  /// This ensures navigation order matches the selected view mode
  static VideoPlayerLaunchArgs _applyViewModeOrdering(VideoPlayerLaunchArgs args) {
    // If no view mode or no playlist, return as-is
    if (args.viewMode == null || args.playlist == null || args.playlist!.isEmpty) {
      return args;
    }

    final viewMode = args.viewMode!;
    final rawPlaylist = args.playlist!;

    // Apply ordering based on view mode
    List<PlaylistEntry> reorderedPlaylist;
    int newStartIndex = args.startIndex ?? 0;

    switch (viewMode) {
      case FolderViewMode.raw:
        // Keep original order
        return args;

      case FolderViewMode.sortedAZ:
        // Sort alphabetically with numerical handling
        reorderedPlaylist = List<PlaylistEntry>.from(rawPlaylist);
        reorderedPlaylist.sort((a, b) {
          final aNum = _extractLeadingNumber(a.title);
          final bNum = _extractLeadingNumber(b.title);

          if (aNum != null && bNum != null) return aNum.compareTo(bNum);
          if (aNum != null) return -1;
          if (bNum != null) return 1;
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        });
        break;

      case FolderViewMode.seriesArrange:
        // Parse filenames and sort by season/episode
        final parsed = SeriesParser.parsePlaylist(rawPlaylist.map((e) => e.title).toList());

        // Create list of (originalIndex, parsedInfo) tuples
        final indexed = <({int originalIndex, PlaylistEntry entry, SeriesInfo info})>[];
        for (int i = 0; i < rawPlaylist.length; i++) {
          indexed.add((originalIndex: i, entry: rawPlaylist[i], info: parsed[i]));
        }

        // Sort by season/episode
        indexed.sort((a, b) {
          final aSeason = a.info.season ?? 9999;
          final bSeason = b.info.season ?? 9999;
          if (aSeason != bSeason) return aSeason.compareTo(bSeason);

          final aEpisode = a.info.episode ?? 9999;
          final bEpisode = b.info.episode ?? 9999;
          if (aEpisode != bEpisode) return aEpisode.compareTo(bEpisode);

          // Fallback to title comparison
          return a.entry.title.toLowerCase().compareTo(b.entry.title.toLowerCase());
        });

        reorderedPlaylist = indexed.map((item) => item.entry).toList();
        break;
    }

    // Find the new index of the originally selected item
    if (newStartIndex >= 0 && newStartIndex < rawPlaylist.length) {
      final originalEntry = rawPlaylist[newStartIndex];
      newStartIndex = reorderedPlaylist.indexWhere(
        (entry) => entry.title == originalEntry.title &&
                   entry.url == originalEntry.url,
      );
      if (newStartIndex < 0) newStartIndex = 0; // Fallback if not found
    }

    debugPrint('VideoPlayerLauncher: Applied viewMode=$viewMode ordering, startIndex ${args.startIndex} -> $newStartIndex');

    // Return new args with reordered playlist and updated start index
    return VideoPlayerLaunchArgs(
      videoUrl: args.videoUrl,
      title: args.title,
      subtitle: args.subtitle,
      playlist: reorderedPlaylist,
      startIndex: newStartIndex,
      rdTorrentId: args.rdTorrentId,
      pikpakCollectionId: args.pikpakCollectionId,
      requestMagicNext: args.requestMagicNext,
      requestNextChannel: args.requestNextChannel,
      startFromRandom: args.startFromRandom,
      randomStartMaxPercent: args.randomStartMaxPercent,
      hideSeekbar: args.hideSeekbar,
      showChannelName: args.showChannelName,
      channelName: args.channelName,
      channelNumber: args.channelNumber,
      showVideoTitle: args.showVideoTitle,
      hideOptions: args.hideOptions,
      hideBackButton: args.hideBackButton,
      isAndroidTvOverride: args.isAndroidTvOverride,
      disableAutoResume: args.disableAutoResume,
      viewMode: args.viewMode,
      folderTree: args.folderTree,
    );
  }

  /// Extract leading number from filename for numerical sorting
  static int? _extractLeadingNumber(String filename) {
    final pattern = RegExp(r'^(\d+)[\s._-]');
    final match = pattern.firstMatch(filename);
    if (match != null && match.groupCount >= 1) {
      return int.tryParse(match.group(1)!);
    }
    return null;
  }

  static Future<bool> _isAndroidTv(bool Function()? override) async {
    if (override != null) {
      try {
        return override();
      } catch (_) {}
    }
    try {
      return await AndroidNativeDownloader.isTelevision();
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _launchOnAndroidTv(VideoPlayerLaunchArgs args) async {
    try {
      final builder = _AndroidTvPlaybackPayloadBuilder(args);
      final result = await builder.build();
      if (result == null) {
        return false;
      }

      final resolver = _AndroidTvPlaylistResolver(
        entries: result.entries,
        resolveEntry: (entry) => _resolveEntryUrl(entry, args),
      );

      // Generate a unique session ID for this playback launch
      // This prevents stale metadata from previous sessions being sent to new sessions
      final sessionId = '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(999999)}';
      AndroidTvPlayerBridge.setCurrentSessionId(sessionId);
      debugPrint('VideoPlayerLauncher: Generated session ID: $sessionId');

      // Hide auto-launch overlay before launching player
      MainPageBridge.notifyPlayerLaunching();

      final launched = await AndroidTvPlayerBridge.launchTorrentPlayback(
        payload: result.payload.toMap(),
        onProgress: (progress) => _handleProgressUpdate(result.payload, progress),
        onFinished: () async {
          await _handlePlaybackFinished(result.payload);
          resolver.dispose();
        },
        onRequestStream: resolver.handleRequest,
      );

      if (!launched) {
        resolver.dispose();
        return false;
      }

      // Async TVMaze metadata fetch - don't block initial playback
      // This mirrors mobile video_player_screen.dart behavior
      // Pass sessionId to ensure stale metadata from previous sessions is discarded
      _fetchAndPushMetadataAsync(result.payload, result.entries, sessionId);

      return true;
    } catch (e) {
      debugPrint('VideoPlayerLauncher: Android TV launch failed: $e');
      return false;
    }
  }

  /// Fetch TVMaze metadata asynchronously and push updates to native player
  /// This doesn't block initial playback - updates are pushed when available
  /// The sessionId parameter ensures stale metadata from previous sessions is discarded
  static void _fetchAndPushMetadataAsync(
    _AndroidTvPlaybackPayload payload,
    List<_LauncherEntry> entries,
    String sessionId,
  ) {
    debugPrint('TVMazeAsync: _fetchAndPushMetadataAsync CALLED');
    debugPrint('TVMazeAsync: contentType=${payload.contentType}, title=${payload.title}');
    debugPrint('TVMazeAsync: entries.length=${entries.length}');

    if (payload.contentType != _PlaybackContentType.series) {
      debugPrint('TVMazeAsync: SKIPPED - not series content (contentType=${payload.contentType})');
      return;
    }

    // Create SeriesPlaylist for TVMaze lookup
    final playlistEntries = entries.map((e) => e.entry).toList();
    if (playlistEntries.length < 2) {
      debugPrint('TVMazeAsync: SKIPPED - less than 2 entries (${playlistEntries.length})');
      return;
    }

    debugPrint('TVMazeAsync: Starting background fetch...');

    // Run in background - don't await
    () async {
      try {
        debugPrint('TVMazeAsync: Creating SeriesPlaylist from ${playlistEntries.length} entries');
        final seriesPlaylist = SeriesPlaylist.fromPlaylistEntries(
          playlistEntries,
          collectionTitle: payload.title,
        );

        debugPrint('TVMazeAsync: SeriesPlaylist created - isSeries=${seriesPlaylist.isSeries}, seriesTitle=${seriesPlaylist.seriesTitle}');
        debugPrint('TVMazeAsync: allEpisodes.length=${seriesPlaylist.allEpisodes.length}');

        if (!seriesPlaylist.isSeries) {
          debugPrint('TVMazeAsync: SKIPPED - SeriesPlaylist says not a series');
          return;
        }

        debugPrint('TVMazeAsync: Calling fetchEpisodeInfo()...');
        await seriesPlaylist.fetchEpisodeInfo();
        debugPrint('TVMazeAsync: fetchEpisodeInfo() completed');

        // Build metadata updates for each item
        final metadataUpdates = <Map<String, dynamic>>[];
        int episodesWithInfo = 0;
        int episodesWithoutInfo = 0;
        for (final episode in seriesPlaylist.allEpisodes) {
          if (episode.episodeInfo == null) {
            episodesWithoutInfo++;
            continue;
          }
          episodesWithInfo++;

          final info = episode.episodeInfo!;
          metadataUpdates.add({
            'originalIndex': episode.originalIndex,
            'title': info.title,
            'description': info.plot,
            'artwork': info.poster,
            'rating': info.rating,
          });
        }

        debugPrint('TVMazeAsync: Episodes with info=$episodesWithInfo, without info=$episodesWithoutInfo');

        if (metadataUpdates.isEmpty) {
          debugPrint('TVMazeAsync: SKIPPED push - metadataUpdates is empty');
          return;
        }

        // Check if this session is still current before sending metadata
        // This prevents stale metadata from Series A being sent to Series B
        if (!AndroidTvPlayerBridge.isCurrentSession(sessionId)) {
          debugPrint('TVMazeAsync: DISCARDED - session $sessionId is no longer current (current: ${AndroidTvPlayerBridge.currentSessionId})');
          return;
        }

        // Store pending updates for fallback (in case broadcast arrives before receiver is registered)
        // AND push directly to native player
        debugPrint('TVMazeAsync: Storing ${metadataUpdates.length} pending metadata updates for fallback');
        AndroidTvPlayerBridge.storePendingMetadataUpdates(metadataUpdates, sessionId: sessionId);

        // Push metadata updates directly to native player (don't wait for request)
        debugPrint('TVMazeAsync: Pushing ${metadataUpdates.length} metadata updates to native player');
        await AndroidTvPlayerBridge.updateEpisodeMetadata(metadataUpdates, sessionId: sessionId);
        debugPrint('TVMazeAsync: Metadata push complete');
      } catch (e, stack) {
        debugPrint('TVMazeAsync: ERROR - $e');
        debugPrint('TVMazeAsync: Stack - $stack');
      }
    }();
  }

  static Future<void> _handleProgressUpdate(
    _AndroidTvPlaybackPayload payload,
    Map<String, dynamic> progress,
  ) async {
    try {
      final positionMs = (progress['positionMs'] ?? 0) as int;
      final durationMs = (progress['durationMs'] ?? 0) as int;
      final speed = (progress['speed'] ?? 1.0) as double;
      final aspect = (progress['aspect'] ?? 'contain') as String;
      final completed = progress['completed'] == true;
      final resumeId = progress['resumeId'] as String?;
      final itemIndex = progress['itemIndex'] as int? ?? 0;
      final progressUrl = progress['url'] as String?;

      if (resumeId != null && progressUrl != null && progressUrl.isNotEmpty) {
        _cacheResolvedStream(resumeId, progressUrl);
      }

      if (payload.contentType == _PlaybackContentType.series) {
        final season = progress['season'] as int?;
        final episode = progress['episode'] as int?;
        final seriesTitle = payload.seriesTitle ?? payload.title;
        if (season != null && episode != null) {
          await StorageService.saveSeriesPlaybackState(
            seriesTitle: seriesTitle,
            season: season,
            episode: episode,
            positionMs: positionMs,
            durationMs: durationMs,
            speed: speed,
            aspect: aspect,
          );

          if (completed) {
            await StorageService.markEpisodeAsFinished(
              seriesTitle: seriesTitle,
              season: season,
              episode: episode,
            );
          }
        }

        if (resumeId != null && payload.items.isNotEmpty) {
          final fallbackIndex = itemIndex.clamp(0, payload.items.length - 1).toInt();
          final item = payload.items.firstWhere(
            (i) => i.resumeId == resumeId,
            orElse: () => payload.items[fallbackIndex],
          );
          final persistedUrl = progressUrl ??
              (resumeId != null ? _resolvedStreamCache[resumeId] : null) ??
              item.url;

          await StorageService.saveVideoPlaybackState(
            videoTitle: resumeId,
            videoUrl: persistedUrl,
            positionMs: positionMs,
            durationMs: durationMs,
            speed: speed,
            aspect: aspect,
          );
        }

        return;
      }

      final items = payload.items;
      if (items.isEmpty) return;
      final fallbackIndex = itemIndex.clamp(0, items.length - 1).toInt();
      final item = resumeId != null
          ? items.firstWhere(
              (i) => i.resumeId == resumeId,
              orElse: () => items[fallbackIndex],
            )
          : items[fallbackIndex];

      final videoTitle = item.resumeId ?? item.title;
      final persistedUrl = progressUrl ??
          (resumeId != null ? _resolvedStreamCache[resumeId] : null) ??
          item.url;

      await StorageService.saveVideoPlaybackState(
        videoTitle: videoTitle,
        videoUrl: persistedUrl,
        positionMs: positionMs,
        durationMs: durationMs,
        speed: speed,
        aspect: aspect,
      );

      if (payload.contentType == _PlaybackContentType.single) {
        await StorageService.upsertVideoResume(videoTitle, {
          'positionMs': positionMs,
          'durationMs': durationMs,
          'speed': speed,
          'aspect': aspect,
          'updatedAt': DateTime.now().millisecondsSinceEpoch,
        });
      }

      // ALSO save in collection format for Android TV playlist progress tracking
      // This allows the playlist screen to display progress indicators for collections
      if (payload.contentType == _PlaybackContentType.collection &&
          payload.seriesTitle != null) {
        debugPrint('📺 AndroidTV Collection Save Check: seriesTitle="${payload.seriesTitle}", itemIndex=$fallbackIndex');

        await StorageService.saveSeriesPlaybackState(
          seriesTitle: payload.seriesTitle!,
          season: 0, // Use season 0 for non-series collections
          episode: fallbackIndex + 1, // Use 1-based index as episode number
          positionMs: positionMs,
          durationMs: durationMs,
          speed: speed,
          aspect: aspect,
        );

        debugPrint('✅ AndroidTV Collection Save: title="${payload.seriesTitle}" S0E${fallbackIndex + 1} pos=${positionMs}ms');

        // Mark as finished if completed
        if (completed) {
          await StorageService.markEpisodeAsFinished(
            seriesTitle: payload.seriesTitle!,
            season: 0,
            episode: fallbackIndex + 1,
          );
          debugPrint('✅ AndroidTV Collection: Marked S0E${fallbackIndex + 1} as finished');
        }
      }
    } catch (e) {
      debugPrint('VideoPlayerLauncher: failed to persist progress: $e');
    }
  }

  static Future<void> _handlePlaybackFinished(
    _AndroidTvPlaybackPayload payload,
  ) async {
    debugPrint(
      'VideoPlayerLauncher: Android TV playback finished for "${payload.title}"',
    );
  }

  static Future<String> _resolveEntryUrl(
    PlaylistEntry entry,
    VideoPlayerLaunchArgs args,
  ) async {
    if (entry.url.isNotEmpty) {
      return entry.url;
    }

    final provider = entry.provider?.toLowerCase();
    final hasTorboxMetadata =
        entry.torboxTorrentId != null && entry.torboxFileId != null;

    if (provider == 'torbox' || hasTorboxMetadata) {
      final torrentId = entry.torboxTorrentId;
      final fileId = entry.torboxFileId;
      if (torrentId == null || fileId == null) {
        throw Exception('Torbox file metadata missing');
      }
      final apiKey = await StorageService.getTorboxApiKey();
      if (apiKey == null || apiKey.isEmpty) {
        throw Exception('Missing Torbox API key');
      }
      final url = await TorboxService.requestFileDownloadLink(
        apiKey: apiKey,
        torrentId: torrentId,
        fileId: fileId,
      );
      if (url.isEmpty) {
        throw Exception('Torbox returned an empty stream URL');
      }
      return url;
    }

    // PikPak lazy resolution
    final hasPikPakMetadata = entry.pikpakFileId != null;
    if (provider == 'pikpak' || hasPikPakMetadata) {
      final fileId = entry.pikpakFileId;
      if (fileId == null) {
        throw Exception('PikPak file metadata missing');
      }
      final pikpak = PikPakApiService.instance;
      final fileData = await pikpak.getFileDetails(fileId);
      final url = pikpak.getStreamingUrl(fileData);
      if (url == null || url.isEmpty) {
        throw Exception('PikPak returned an empty stream URL');
      }
      return url;
    }

    if (entry.restrictedLink != null && entry.restrictedLink!.isNotEmpty) {
      final apiKey = await StorageService.getApiKey();
      if (apiKey == null || apiKey.isEmpty) {
        throw Exception('Missing Real Debrid API key');
      }
      final unrestrictResult = await DebridService.unrestrictLink(
        apiKey,
        entry.restrictedLink!,
      );
      final url = unrestrictResult['download']?.toString() ?? '';
      if (url.isEmpty) {
        throw Exception('Real Debrid returned an empty stream URL');
      }
      return url;
    }

    if (args.videoUrl.isNotEmpty) {
      return args.videoUrl;
    }

    throw Exception('No URL metadata available for this entry');
  }
}

enum _PlaybackContentType { single, collection, series }

class _AndroidTvPlaybackPayload {
  final _PlaybackContentType contentType;
  final String title;
  final String? subtitle;
  final List<_AndroidTvPlaybackItem> items;
  final int startIndex;
  final String? seriesTitle;
  final List<_AndroidTvSeriesSeason> seasons;
  final Map<int, int> nextEpisodeMap;
  final Map<int, int> prevEpisodeMap;

  const _AndroidTvPlaybackPayload({
    required this.contentType,
    required this.title,
    required this.subtitle,
    required this.items,
    required this.startIndex,
    required this.seriesTitle,
    required this.seasons,
    this.nextEpisodeMap = const {},
    this.prevEpisodeMap = const {},
  });

  Map<String, dynamic> toMap() {
    return {
      'version': 1,
      'title': title,
      'subtitle': subtitle,
      'contentType': contentType.name,
      'startIndex': startIndex,
      'seriesTitle': seriesTitle,
      'items': items.map((e) => e.toMap()).toList(),
      'seasons': seasons.map((e) => e.toMap()).toList(),
      // Navigation maps for series playback (mirrors mobile video_player_screen.dart)
      'nextEpisodeMap': nextEpisodeMap.map((k, v) => MapEntry(k.toString(), v)),
      'prevEpisodeMap': prevEpisodeMap.map((k, v) => MapEntry(k.toString(), v)),
    };
  }
}

class _AndroidTvPlaybackItem {
  final String id;
  final String title;
  final String url;
  final int index;
  final int? season;
  final int? episode;
  final String? artwork;
  final String? description;
  final int? sizeBytes;
  final int resumePositionMs;
  final int durationMs;
  final int updatedAt;
  final String? resumeId;
  final String? provider;

  const _AndroidTvPlaybackItem({
    required this.id,
    required this.title,
    required this.url,
    required this.index,
    required this.season,
    required this.episode,
    required this.artwork,
    required this.description,
    required this.sizeBytes,
    required this.resumePositionMs,
    required this.durationMs,
    required this.updatedAt,
    required this.resumeId,
    required this.provider,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'url': url,
      'index': index,
      'season': season,
      'episode': episode,
      'artwork': artwork,
      'description': description,
      'sizeBytes': sizeBytes,
      'resumePositionMs': resumePositionMs,
      'durationMs': durationMs,
      'updatedAt': updatedAt,
      'resumeId': resumeId,
      'provider': provider,
    };
  }
}

class _AndroidTvSeriesSeason {
  final int seasonNumber;
  final List<_AndroidTvSeriesEpisode> episodes;

  const _AndroidTvSeriesSeason({
    required this.seasonNumber,
    required this.episodes,
  });

  Map<String, dynamic> toMap() {
    return {
      'seasonNumber': seasonNumber,
      'episodes': episodes.map((e) => e.toMap()).toList(),
    };
  }
}

class _AndroidTvSeriesEpisode {
  final String title;
  final int? season;
  final int? episode;
  final String? description;
  final String? artwork;

  const _AndroidTvSeriesEpisode({
    required this.title,
    required this.season,
    required this.episode,
    required this.description,
    required this.artwork,
  });

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'season': season,
      'episode': episode,
      'description': description,
      'artwork': artwork,
    };
  }
}

class _AndroidTvPlaybackPayloadResult {
  final _AndroidTvPlaybackPayload payload;
  final List<_LauncherEntry> entries;

  const _AndroidTvPlaybackPayloadResult({
    required this.payload,
    required this.entries,
  });
}

class _LauncherEntry {
  final PlaylistEntry entry;
  final String resumeId;
  final int index;

  const _LauncherEntry({
    required this.entry,
    required this.resumeId,
    required this.index,
  });
}

class _AndroidTvPlaylistResolver {
  final List<_LauncherEntry> entries;
  final Future<String> Function(PlaylistEntry entry) resolveEntry;

  _AndroidTvPlaylistResolver({
    required this.entries,
    required this.resolveEntry,
  });

  Future<Map<String, dynamic>?> handleRequest(
    Map<String, dynamic> request,
  ) async {
    debugPrint('AndroidTvPlaylistResolver: handleRequest called with: $request');
    debugPrint('AndroidTvPlaylistResolver: total entries: ${entries.length}');

    _LauncherEntry? target;
    final resumeId = request['resumeId'] as String?;
    final index = request['index'] as int?;

    debugPrint('AndroidTvPlaylistResolver: looking for - resumeId: $resumeId, index: $index');

    if (resumeId != null) {
      target = entries.firstWhereOrNull((entry) => entry.resumeId == resumeId);
      debugPrint('AndroidTvPlaylistResolver: found by resumeId: ${target != null}');
    }
    if (target == null && index != null && index >= 0 && index < entries.length) {
      target = entries[index];
      debugPrint('AndroidTvPlaylistResolver: found by index: ${target != null}, entry: ${target?.entry.title}');
    }
    if (target == null) {
      debugPrint('AndroidTvPlaylistResolver: ERROR - target not found!');
      debugPrint('AndroidTvPlaylistResolver: Available entries:');
      for (int i = 0; i < entries.length; i++) {
        debugPrint('  [$i] resumeId=${entries[i].resumeId}, title=${entries[i].entry.title}');
      }
      return null;
    }

    debugPrint('AndroidTvPlaylistResolver: resolving entry for: ${target.entry.title}');
    final url = await resolveEntry(target.entry);
    debugPrint('AndroidTvPlaylistResolver: resolved URL: ${url.isNotEmpty ? url.substring(0, min(50, url.length)) : "EMPTY"}');

    if (url.isEmpty) {
      debugPrint('AndroidTvPlaylistResolver: ERROR - resolved URL is empty!');
      return null;
    }

    _cacheResolvedStream(target.resumeId, url);
    debugPrint('AndroidTvPlaylistResolver: returning success - url length: ${url.length}');
    return {
      'url': url,
      'resumeId': target.resumeId,
      'index': target.index,
      'provider': target.entry.provider,
    };
  }

  void dispose() {
    _clearResolvedStreams(entries.map((e) => e.resumeId));
  }
}

class _AndroidTvPlaybackPayloadBuilder {
  final VideoPlayerLaunchArgs args;

  const _AndroidTvPlaybackPayloadBuilder(this.args);

  Future<_AndroidTvPlaybackPayloadResult?> build() async {
    final playlistEntries = _normalizePlaylist();
    final seriesPlaylist = await _buildSeriesPlaylist(playlistEntries);
    final contentType = _determineContentType(seriesPlaylist, playlistEntries);
    final perItemStates = await _fetchPerItemPlaybackState(playlistEntries);
    final startIndex = await _determineStartIndex(
      contentType,
      seriesPlaylist,
      playlistEntries,
      perItemStates,
    );

    final preparedEntries = await _prepareEntries(playlistEntries, startIndex);
    final seasons = _buildSeriesSeasons(seriesPlaylist);

    final launcherEntries = <_LauncherEntry>[];
    final items = <_AndroidTvPlaybackItem>[];

    for (int i = 0; i < preparedEntries.length; i++) {
      final entry = preparedEntries[i];
      final resumeId = _resumeIdForEntry(entry);
      if (entry.url.isNotEmpty) {
        _cacheResolvedStream(resumeId, entry.url);
      }
      launcherEntries.add(
        _LauncherEntry(entry: entry, resumeId: resumeId, index: i),
      );

      final resumeInfo = i < perItemStates.length
          ? perItemStates[i]
          : const _PerItemState();

      SeriesEpisode? episodeInfo;
      if (seriesPlaylist != null) {
        episodeInfo = seriesPlaylist.allEpisodes.firstWhereOrNull(
          (episode) => episode.originalIndex == i,
        );
      }
      episodeInfo ??= SeriesEpisode(
        url: entry.url,
        title: entry.title,
        filename: entry.title,
        seriesInfo: SeriesParser.parseFilename(entry.title),
        originalIndex: i,
      );

      // Use TVMaze episode title if available, otherwise fallback to entry title
      final displayTitle = episodeInfo.episodeInfo?.title?.isNotEmpty == true
          ? episodeInfo.episodeInfo!.title!
          : entry.title;

      items.add(
        _AndroidTvPlaybackItem(
          id: entry.url.isNotEmpty ? entry.url : '${entry.title}_$i',
          title: displayTitle,
          url: entry.url,
          index: i,
          season: episodeInfo.seriesInfo.season,
          episode: episodeInfo.seriesInfo.episode,
          artwork: episodeInfo.episodeInfo?.poster,
          description: episodeInfo.episodeInfo?.plot,
          sizeBytes: entry.sizeBytes,
          resumePositionMs: resumeInfo.positionMs,
          durationMs: resumeInfo.durationMs,
          updatedAt: resumeInfo.updatedAt,
          resumeId: resumeId,
          provider: entry.provider,
        ),
      );
    }

    // Build navigation maps based on SeriesPlaylist.allEpisodes ordering
    // This mirrors mobile video_player_screen.dart's navigation exactly
    final navigationMaps = _buildNavigationMaps(seriesPlaylist, items);

    final payload = _AndroidTvPlaybackPayload(
      contentType: contentType,
      title: args.title,
      subtitle: args.subtitle,
      items: items,
      startIndex: startIndex,
      seriesTitle: seriesPlaylist?.seriesTitle,
      seasons: seasons,
      nextEpisodeMap: navigationMaps.nextMap,
      prevEpisodeMap: navigationMaps.prevMap,
    );

    return _AndroidTvPlaybackPayloadResult(
      payload: payload,
      entries: launcherEntries,
    );
  }

  /// Build navigation maps based on SeriesPlaylist.allEpisodes ordering
  /// Maps originalIndex -> nextOriginalIndex and originalIndex -> prevOriginalIndex
  /// This mirrors exactly how mobile video_player_screen.dart navigates episodes
  _NavigationMaps _buildNavigationMaps(
    SeriesPlaylist? seriesPlaylist,
    List<_AndroidTvPlaybackItem> items,
  ) {
    final nextMap = <int, int>{};
    final prevMap = <int, int>{};

    if (seriesPlaylist == null || !seriesPlaylist.isSeries) {
      // For non-series content, use simple sequential navigation
      for (int i = 0; i < items.length; i++) {
        if (i + 1 < items.length) {
          nextMap[i] = i + 1;
        }
        if (i > 0) {
          prevMap[i] = i - 1;
        }
      }
      return _NavigationMaps(nextMap: nextMap, prevMap: prevMap);
    }

    // For series content, use SeriesPlaylist.allEpisodes ordering
    // allEpisodes is already sorted by season/episode in SeriesPlaylist.fromPlaylistEntries
    final allEpisodes = seriesPlaylist.allEpisodes;

    for (int i = 0; i < allEpisodes.length; i++) {
      final currentOriginalIndex = allEpisodes[i].originalIndex;

      if (i + 1 < allEpisodes.length) {
        final nextOriginalIndex = allEpisodes[i + 1].originalIndex;
        nextMap[currentOriginalIndex] = nextOriginalIndex;
      }

      if (i > 0) {
        final prevOriginalIndex = allEpisodes[i - 1].originalIndex;
        prevMap[currentOriginalIndex] = prevOriginalIndex;
      }
    }

    debugPrint('VideoPlayerLauncher: Built navigation maps - next: ${nextMap.length}, prev: ${prevMap.length}');
    return _NavigationMaps(nextMap: nextMap, prevMap: prevMap);
  }

  List<PlaylistEntry> _normalizePlaylist() {
    final playlist = args.playlist;
    if (playlist != null && playlist.isNotEmpty) {
      return playlist;
    }
    return [
      PlaylistEntry(
        url: args.videoUrl,
        title: args.title,
      ),
    ];
  }

  Future<List<PlaylistEntry>> _prepareEntries(
    List<PlaylistEntry> entries,
    int startIndex,
  ) async {
    final prepared = <PlaylistEntry>[];
    for (int i = 0; i < entries.length; i++) {
      final entry = entries[i];
      if (entry.url.isNotEmpty || i != startIndex) {
        prepared.add(entry);
        continue;
      }
      final resolved = await VideoPlayerLauncher._resolveEntryUrl(entry, args);
      if (resolved.isEmpty) {
        throw Exception('Failed to resolve initial stream');
      }
      prepared.add(
        PlaylistEntry(
          url: resolved,
          title: entry.title,
          restrictedLink: entry.restrictedLink,
          torrentHash: entry.torrentHash,
          sizeBytes: entry.sizeBytes,
          provider: entry.provider,
          torboxTorrentId: entry.torboxTorrentId,
          torboxFileId: entry.torboxFileId,
        ),
      );
    }
    return prepared;
  }

  Future<List<_PerItemState>> _fetchPerItemPlaybackState(
    List<PlaylistEntry> entries,
  ) async {
    final result = <_PerItemState>[];
    for (final entry in entries) {
      final resumeId = _resumeIdForEntry(entry);
      result.add(await _readVideoState(resumeId));
    }
    return result;
  }

  Future<_PerItemState> _readVideoState(String resumeId) async {
    final data = await StorageService.getVideoPlaybackState(
      videoTitle: resumeId,
    );
    if (data == null) {
      return const _PerItemState();
    }
    return _PerItemState(
      positionMs: (data['positionMs'] ?? 0) as int,
      durationMs: (data['durationMs'] ?? 0) as int,
      updatedAt: (data['updatedAt'] ?? 0) as int,
    );
  }

  Future<SeriesPlaylist?> _buildSeriesPlaylist(List<PlaylistEntry> entries) async {
    if (entries.length < 2) {
      return null;
    }
    try {
      final playlist = SeriesPlaylist.fromPlaylistEntries(
        entries,
        collectionTitle: args.title, // Pass collection/torrent title as fallback
      );
      // DO NOT await fetchEpisodeInfo() here - TVMaze loading is now async
      // Metadata will be fetched and pushed separately after playback launches
      // This mirrors mobile behavior where TVMaze doesn't block initial playback
      return playlist;
    } catch (_) {
      return null;
    }
  }

  _PlaybackContentType _determineContentType(
    SeriesPlaylist? seriesPlaylist,
    List<PlaylistEntry> entries,
  ) {
    if (seriesPlaylist != null && seriesPlaylist.isSeries) {
      return _PlaybackContentType.series;
    }
    if (entries.length > 1) {
      return _PlaybackContentType.collection;
    }
    return _PlaybackContentType.single;
  }

  Future<int> _determineStartIndex(
    _PlaybackContentType contentType,
    SeriesPlaylist? seriesPlaylist,
    List<PlaylistEntry> entries,
    List<_PerItemState> perItemState,
  ) async {
    switch (contentType) {
      case _PlaybackContentType.series:
        return await _determineSeriesStartIndex(seriesPlaylist);
      case _PlaybackContentType.collection:
        return _determineCollectionStartIndex(entries, perItemState);
      case _PlaybackContentType.single:
        return args.startIndex ?? 0;
    }
  }

  Future<int> _determineSeriesStartIndex(SeriesPlaylist? playlist) async {
    // If auto-resume is disabled, use startIndex directly
    if (args.disableAutoResume) {
      debugPrint('AndroidTV: auto-resume disabled, using startIndex=${args.startIndex ?? 0}');
      return args.startIndex ?? 0;
    }

    if (playlist == null || playlist.allEpisodes.isEmpty) {
      return args.startIndex ?? 0;
    }

    final lastEpisode = await StorageService.getLastPlayedEpisode(
      seriesTitle: playlist.seriesTitle ?? 'Unknown Series',
    );

    if (lastEpisode == null) {
      // No resume data - determine start based on view mode
      // In Raw view: start from index 0 (first file in original order)
      // In Sort/Series view: start from first episode (S01E01)
      if (args.viewMode == FolderViewMode.raw) {
        debugPrint('VideoPlayerLauncher: No resume data, Raw view mode - starting from index 0');
        return 0;
      }

      // For Sort/Series view modes, start from first episode
      final candidate = playlist.getFirstEpisodeOriginalIndex();
      if (candidate == -1) {
        return args.startIndex ?? 0;
      }
      final maxIndex = playlist.allEpisodes.length - 1;
      debugPrint('VideoPlayerLauncher: No resume data, viewMode=${args.viewMode} - starting from first episode (index $candidate)');
      return candidate.clamp(0, maxIndex).toInt();
    }

    // Resume from last played episode
    final originalIndex = playlist.findOriginalIndexBySeasonEpisode(
      lastEpisode['season'] as int,
      lastEpisode['episode'] as int,
    );
    if (originalIndex != -1) {
      return originalIndex;
    }

    // Fallback to first episode
    final fallback = playlist.getFirstEpisodeOriginalIndex();
    if (fallback == -1) {
      return args.startIndex ?? 0;
    }
    final maxIndex = playlist.allEpisodes.isEmpty
        ? 0
        : (playlist.allEpisodes.length - 1);
    return (fallback.clamp(0, maxIndex) as num).toInt();
  }

  int _determineCollectionStartIndex(
    List<PlaylistEntry> entries,
    List<_PerItemState> perItemState,
  ) {
    // If auto-resume is disabled, use startIndex directly
    if (args.disableAutoResume) {
      debugPrint('AndroidTV: auto-resume disabled for collection, using startIndex=${args.startIndex ?? 0}');
      return args.startIndex ?? 0;
    }

    // Check for most recently played file
    int bestIndex = -1;
    int bestUpdatedAt = -1;
    for (int i = 0; i < entries.length; i++) {
      final state = perItemState[i];
      if (state.updatedAt > bestUpdatedAt && state.updatedAt > 0) {
        bestUpdatedAt = state.updatedAt;
        bestIndex = i;
      }
    }
    if (bestIndex != -1) {
      return bestIndex;
    }

    // No resume data - determine start based on view mode
    // In Raw view: start from index 0 (first file in original order)
    // In Sort/Series view: use intelligent filtering (main group)
    if (args.viewMode == FolderViewMode.raw) {
      debugPrint('VideoPlayerLauncher: No resume data for collection, Raw view mode - starting from index 0');
      return 0;
    }

    // For Sort/Series view modes, use main group filtering
    final indices = _getMainGroupIndices(entries);
    if (indices.isNotEmpty) {
      debugPrint('VideoPlayerLauncher: No resume data for collection, viewMode=${args.viewMode} - starting from main group (index ${indices.first})');
      return indices.first;
    }
    return args.startIndex ?? 0;
  }

  List<_AndroidTvSeriesSeason> _buildSeriesSeasons(SeriesPlaylist? playlist) {
    if (playlist == null) {
      // Check if we should build folder-based structure
      return _buildFolderSeasons();
    }
    final seasons = <_AndroidTvSeriesSeason>[];
    for (final season in playlist.seasons) {
      final episodes = season.episodes.map((episode) {
        return _AndroidTvSeriesEpisode(
          title: episode.displayTitle,
          season: episode.seriesInfo.season,
          episode: episode.seriesInfo.episode,
          description: episode.episodeInfo?.plot,
          artwork: episode.episodeInfo?.poster,
        );
      }).toList();
      seasons.add(
        _AndroidTvSeriesSeason(
          seasonNumber: season.seasonNumber,
          episodes: episodes,
        ),
      );
    }
    return seasons;
  }

  List<_AndroidTvSeriesSeason> _buildFolderSeasons() {
    // Only build folder structure for raw/sortedAZ view modes
    if (args.folderTree == null ||
        args.viewMode == null ||
        args.viewMode == FolderViewMode.seriesArrange) {
      return const [];
    }

    final entries = _normalizePlaylist();
    if (entries.isEmpty) return const [];

    // Group files by their parent folder
    final folderGroups = <String, List<int>>{};

    for (int i = 0; i < entries.length; i++) {
      final entry = entries[i];

      // Find matching file node
      try {
        final folderTree = args.folderTree;
        if (folderTree == null) {
          folderGroups.putIfAbsent('Files', () => []).add(i);
          continue;
        }

        final allFiles = folderTree.getAllFiles();
        if (allFiles.isEmpty) {
          folderGroups.putIfAbsent('Files', () => []).add(i);
          continue;
        }

        final fileNode = allFiles.firstWhere(
          (node) => node.name == entry.title,
          orElse: () => RDFileNode.file(name: '', fileId: -1, path: '', bytes: 0, linkIndex: -1),
        );

        if (fileNode.name.isEmpty) continue;

        // Use relativePath if available
        final pathToUse = fileNode.relativePath ?? fileNode.path;
        if (pathToUse == null || pathToUse.isEmpty) {
          // Fallback to root group
          folderGroups.putIfAbsent('Files', () => []).add(i);
          continue;
        }

        // Parse path: "Series Name/Season 1/Episode 1.mkv"
        final parts = pathToUse.split('/');

        if (parts.length <= 1) {
          // Flat structure - use root group
          folderGroups.putIfAbsent('Files', () => []).add(i);
        } else {
          // Skip top-level folder, use next level as group
          final folderName = parts[1];
          folderGroups.putIfAbsent(folderName, () => []).add(i);
        }
      } catch (e) {
        // On error, add to root group
        folderGroups.putIfAbsent('Files', () => []).add(i);
      }
    }

    // Convert folder groups to "seasons"
    final seasons = <_AndroidTvSeriesSeason>[];
    int seasonNum = 1;

    // Sort folder names for consistent ordering
    final sortedFolders = folderGroups.keys.toList()..sort();

    for (final folderName in sortedFolders) {
      final indices = folderGroups[folderName]!;
      final episodes = indices.map((idx) {
        final entry = entries[idx];
        return _AndroidTvSeriesEpisode(
          title: entry.title,
          season: seasonNum,
          episode: indices.indexOf(idx) + 1,
          description: null,
          artwork: null,
        );
      }).toList();

      seasons.add(
        _AndroidTvSeriesSeason(
          seasonNumber: seasonNum,
          episodes: episodes,
        ),
      );
      seasonNum++;
    }

    return seasons;
  }

  List<int> _getMainGroupIndices(List<PlaylistEntry> entries) {
    int maxSize = -1;
    for (final e in entries) {
      final s = e.sizeBytes ?? -1;
      if (s > maxSize) maxSize = s;
    }
    final double threshold = maxSize > 0 ? maxSize * 0.40 : -1;
    final main = <int>[];
    for (int i = 0; i < entries.length; i++) {
      final e = entries[i];
      final isSmall =
          threshold > 0 && (e.sizeBytes != null && e.sizeBytes! < threshold);
      if (!isSmall) main.add(i);
    }
    int sizeOf(int idx) => entries[idx].sizeBytes ?? -1;
    int? yearOf(int idx) {
      final m = RegExp(r'\b(19|20)\d{2}\b').firstMatch(entries[idx].title);
      if (m != null) return int.tryParse(m.group(0)!);
      return null;
    }

    main.sort((a, b) {
      final yearA = yearOf(a) ?? 0;
      final yearB = yearOf(b) ?? 0;
      if (yearA != yearB) return yearA.compareTo(yearB);
      return sizeOf(b).compareTo(sizeOf(a));
    });

    if (main.isEmpty) {
      return List<int>.generate(entries.length, (i) => i);
    }
    return main;
  }

  /// Generate resume ID for a playlist entry - MUST match mobile video_player_screen.dart
  /// This ensures Android TV and mobile share the same resume state
  String _resumeIdForEntry(PlaylistEntry entry) {
    // Check for Torbox-specific key
    final torboxKey = _torboxResumeKeyForEntry(entry);
    if (torboxKey != null) {
      return torboxKey;
    }
    // Check for PikPak-specific key
    final pikpakKey = _pikpakResumeKeyForEntry(entry);
    if (pikpakKey != null) {
      return pikpakKey;
    }
    // Fallback to filename hash
    // Use relativePath if available to avoid collisions (e.g., Season 1/Episode 1.mkv vs Season 2/Episode 1.mkv)
    if (entry.relativePath != null && entry.relativePath!.isNotEmpty) {
      return _generateFilenameHash(entry.relativePath!);
    }
    final name = entry.title.isNotEmpty ? entry.title : args.title;
    return _generateFilenameHash(name);
  }

  String? _torboxResumeKeyForEntry(PlaylistEntry entry) {
    final provider = entry.provider?.toLowerCase();
    if (provider == 'torbox') {
      final torrentId = entry.torboxTorrentId;
      final fileId = entry.torboxFileId;
      if (torrentId != null && fileId != null) {
        return 'torbox_${torrentId}_$fileId';
      }
    }
    return null;
  }

  String? _pikpakResumeKeyForEntry(PlaylistEntry entry) {
    final provider = entry.provider?.toLowerCase();
    if (provider == 'pikpak') {
      final fileId = entry.pikpakFileId;
      if (fileId != null && fileId.isNotEmpty) {
        return 'pikpak_$fileId';
      }
    }
    return null;
  }

  String _generateFilenameHash(String filename) {
    final nameWithoutExt = filename.replaceAll(RegExp(r'\.[^.]*$'), '');
    final hash = nameWithoutExt.hashCode.toString();
    return hash;
  }
}

class _PerItemState {
  final int positionMs;
  final int durationMs;
  final int updatedAt;

  const _PerItemState({
    this.positionMs = 0,
    this.durationMs = 0,
    this.updatedAt = 0,
  });
}

/// Navigation maps for series playback
/// Maps originalIndex -> next/prev originalIndex based on SeriesPlaylist.allEpisodes order
class _NavigationMaps {
  final Map<int, int> nextMap;
  final Map<int, int> prevMap;

  const _NavigationMaps({
    required this.nextMap,
    required this.prevMap,
  });
}
