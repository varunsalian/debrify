import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:android_intent_plus/android_intent.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models/movie_collection.dart';
import '../services/external_player_service.dart';
import '../utils/deovr_utils.dart' as deovr;
import '../models/playlist_view_mode.dart';
import '../models/series_playlist.dart';
import '../screens/video_player_screen.dart';
import '../services/android_native_downloader.dart';
import '../services/android_tv_player_bridge.dart';
import '../services/debrid_service.dart';
import '../services/episode_info_service.dart';
import '../services/main_page_bridge.dart';
import '../services/storage_service.dart';
import '../services/torbox_service.dart';
import '../services/pikpak_api_service.dart';
import '../utils/series_parser.dart';

final Map<String, String> _resolvedStreamCache = <String, String>{};
final Map<String, String> _redirectCache = <String, String>{};

void _cacheResolvedStream(String? resumeId, String url) {
  if (resumeId == null) return;
  if (url.isEmpty) return;
  _resolvedStreamCache[resumeId] = url;
}

/// Resolve redirects for a URL (for TV player HLS streams).
/// Returns the final URL after following redirects, or original URL if no redirect.
/// Only resolves URLs that look like they might be short redirect URLs.
Future<String> _resolveRedirectUrl(String url) async {
  debugPrint('[RedirectResolver] Input URL: $url');

  // Check cache first
  if (_redirectCache.containsKey(url)) {
    final cached = _redirectCache[url]!;
    debugPrint('[RedirectResolver] Cache HIT: $url -> $cached');
    return cached;
  }
  debugPrint('[RedirectResolver] Cache MISS, checking URL...');

  // Skip resolution for URLs that are unlikely to be redirects:
  // - Already have media extensions
  // - Known debrid CDN domains
  final uri = Uri.tryParse(url);
  if (uri == null) {
    debugPrint('[RedirectResolver] SKIP: Invalid URL, using original');
    return url;
  }

  final path = uri.path.toLowerCase();
  final host = uri.host.toLowerCase();
  debugPrint('[RedirectResolver] Host: $host, Path: $path');

  // Skip if already has a media extension
  if (path.endsWith('.m3u8') ||
      path.endsWith('.mp4') ||
      path.endsWith('.mkv') ||
      path.endsWith('.ts') ||
      path.endsWith('.mpd')) {
    debugPrint('[RedirectResolver] SKIP: Has media extension, using original');
    return url;
  }

  // Skip known debrid CDN domains (they don't redirect)
  if (host.contains('real-debrid') ||
      host.contains('torbox') ||
      host.contains('pikpak') ||
      host.contains('1fichier') ||
      host.contains('rapidgator')) {
    debugPrint('[RedirectResolver] SKIP: Known debrid CDN domain, using original');
    return url;
  }

  debugPrint('[RedirectResolver] Attempting HEAD request to resolve redirects...');

  try {
    // Use a client that doesn't follow redirects automatically
    final client = http.Client();
    try {
      final request = http.Request('HEAD', uri);
      request.followRedirects = false;
      request.headers['User-Agent'] =
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';

      final response = await client.send(request).timeout(
        const Duration(seconds: 5),
      );

      debugPrint('[RedirectResolver] Response status: ${response.statusCode}');
      debugPrint('[RedirectResolver] Response headers: ${response.headers}');

      // Check if it's a redirect
      if (response.statusCode == 301 ||
          response.statusCode == 302 ||
          response.statusCode == 303 ||
          response.statusCode == 307 ||
          response.statusCode == 308) {
        final location = response.headers['location'];
        debugPrint('[RedirectResolver] Redirect detected! Location: $location');

        if (location != null && location.isNotEmpty) {
          // Handle relative URLs
          final resolvedUri = uri.resolve(location);
          final resolvedUrl = resolvedUri.toString();
          debugPrint('[RedirectResolver] SUCCESS: Resolved $url -> $resolvedUrl');

          // Cache the result
          _redirectCache[url] = resolvedUrl;
          return resolvedUrl;
        } else {
          debugPrint('[RedirectResolver] WARNING: Redirect but no Location header');
        }
      } else {
        debugPrint('[RedirectResolver] No redirect (status ${response.statusCode}), using original');
      }
    } finally {
      client.close();
    }
  } catch (e) {
    debugPrint('[RedirectResolver] ERROR: $e');
    debugPrint('[RedirectResolver] Falling back to original URL');
  }

  // No redirect or error - use original URL
  _redirectCache[url] = url;
  debugPrint('[RedirectResolver] Final URL (no change): $url');
  return url;
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
  final String? torboxTorrentId;
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
  final PlaylistViewMode? viewMode;
  // Content metadata for fetching external subtitles from Stremio addons
  final String? contentImdbId;
  final String? contentType; // 'movie' or 'series'
  final int? contentSeason;
  final int? contentEpisode;

  const VideoPlayerLaunchArgs({
    required this.videoUrl,
    required this.title,
    this.subtitle,
    this.playlist,
    this.startIndex,
    this.rdTorrentId,
    this.torboxTorrentId,
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
    this.contentImdbId,
    this.contentType,
    this.contentSeason,
    this.contentEpisode,
  });

  VideoPlayerScreen toWidget() {
    return VideoPlayerScreen(
      videoUrl: videoUrl,
      title: title,
      subtitle: subtitle,
      playlist: playlist,
      startIndex: startIndex,
      rdTorrentId: rdTorrentId,
      torboxTorrentId: torboxTorrentId,
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
      contentImdbId: contentImdbId,
      contentType: contentType,
      contentSeason: contentSeason,
      contentEpisode: contentEpisode,
    );
  }
}

class VideoPlayerLauncher {
  static Future<void> push(BuildContext context, VideoPlayerLaunchArgs args) async {
    // Log playlist entries to trace relativePath
    if (args.playlist != null && args.playlist!.isNotEmpty) {
      debugPrint('🚀 VideoPlayerLauncher.push: Launching with ${args.playlist!.length} entries');
      for (int i = 0; i < args.playlist!.length && i < 5; i++) {
        final entry = args.playlist![i];
        debugPrint('  Entry[$i]: title="${entry.title}", relativePath="${entry.relativePath}"');
      }
    }

    // Check default player mode
    final defaultPlayerMode = await StorageService.getDefaultPlayerMode();

    if (defaultPlayerMode == 'external') {
      final launched = await _launchWithExternalPlayer(context, args);
      if (launched) {
        return;
      }
      // If external player failed, fall through to in-app player
    } else if (defaultPlayerMode == 'deovr' && Platform.isAndroid) {
      final launched = await _launchWithDeoVR(context, args);
      if (launched) {
        return;
      }
      // If DeoVR failed, fall through to in-app player
    }

    final isTv = await _isAndroidTv(args.isAndroidTvOverride);
    if (isTv) {
      final launched = await _launchOnAndroidTv(args);
      if (launched) {
        return;
      }
    }

    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => args.toWidget()),
    );
  }

  /// Launch video with external player based on platform
  /// Returns true if successfully launched, false if should fall back to in-app player
  static Future<bool> _launchWithExternalPlayer(
    BuildContext context,
    VideoPlayerLaunchArgs args,
  ) async {
    final url = args.videoUrl;
    final title = args.title;

    if (Platform.isMacOS) {
      // macOS: Use configured external player
      final result = await ExternalPlayerService.launchWithPreferredPlayer(
        url,
        title: title,
      );

      if (result.success) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Opening with ${result.usedPlayer?.displayName ?? "external player"}...'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
        return true;
      } else {
        // Show error but fall back to in-app player
        debugPrint('External player failed: ${result.errorMessage}');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.errorMessage ?? 'Failed to open external player'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
        return false;
      }
    } else if (Platform.isAndroid) {
      // Android: Show Intent chooser for video player apps
      try {
        final intent = AndroidIntent(
          action: 'action_view',
          data: url,
          type: 'video/*',
        );
        await intent.launch();
        return true;
      } catch (e) {
        debugPrint('Failed to launch external player on Android: $e');
        return false;
      }
    }

    // Other platforms: not supported, use in-app player
    return false;
  }

  /// Launch video with DeoVR player (Android only)
  /// Returns true if successfully launched, false if should fall back to in-app player
  static Future<bool> _launchWithDeoVR(
    BuildContext context,
    VideoPlayerLaunchArgs args,
  ) async {
    final url = args.videoUrl;
    final title = args.title;

    try {
      // Load VR settings
      final vrAutoDetectFormat = await StorageService.getQuickPlayVrAutoDetectFormat();
      final vrShowDialog = await StorageService.getQuickPlayVrShowDialog();
      final vrDefaultScreenType = await StorageService.getQuickPlayVrDefaultScreenType();
      final vrDefaultStereoMode = await StorageService.getQuickPlayVrDefaultStereoMode();

      // Detect or use default format
      String selectedScreenType = vrDefaultScreenType;
      String selectedStereoMode = vrDefaultStereoMode;

      if (vrAutoDetectFormat) {
        final detected = deovr.detectVRFormat(title);
        selectedScreenType = detected.screenType;
        selectedStereoMode = detected.stereoMode;
      }

      // Show format selection dialog if enabled
      if (vrShowDialog && context.mounted) {
        final result = await _showDeoVRFormatDialog(
          context,
          title: title,
          initialScreenType: selectedScreenType,
          initialStereoMode: selectedStereoMode,
        );

        if (result == null) {
          // User cancelled
          return false;
        }

        selectedScreenType = result.screenType;
        selectedStereoMode = result.stereoMode;
      }

      // Generate DeoVR JSON
      final json = deovr.generateDeoVRJson(
        videoUrl: url,
        title: title,
        screenType: selectedScreenType,
        stereoMode: selectedStereoMode,
      );
      final jsonString = jsonEncode(json);

      debugPrint('DeoVR JSON content: $jsonString');

      // Upload JSON to jsonblob.com
      final response = await http.post(
        Uri.parse('https://jsonblob.com/api/jsonBlob'),
        headers: {'Content-Type': 'application/json'},
        body: jsonString,
      );

      if (response.statusCode != 201) {
        throw Exception('Failed to upload JSON: ${response.statusCode}');
      }

      final location = response.headers['location'];
      if (location == null) {
        throw Exception('No location header in response');
      }

      final jsonUrl = 'https://jsonblob.com$location';
      debugPrint('DeoVR JSON uploaded to: $jsonUrl');

      // Launch DeoVR with the public URL
      final deOvrUri = 'deovr://$jsonUrl';
      debugPrint('Launching DeoVR with URI: $deOvrUri');

      final intent = AndroidIntent(
        action: 'action_view',
        data: deOvrUri,
      );
      await intent.launch();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Launching DeoVR...'),
            duration: Duration(seconds: 2),
          ),
        );
      }

      return true;
    } catch (e) {
      debugPrint('Failed to launch DeoVR: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to open DeoVR: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return false;
    }
  }

  /// Show DeoVR format selection dialog
  static Future<({String screenType, String stereoMode})?> _showDeoVRFormatDialog(
    BuildContext context, {
    required String title,
    required String initialScreenType,
    required String initialStereoMode,
  }) async {
    String selectedScreenType = initialScreenType;
    String selectedStereoMode = initialStereoMode;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('DeoVR Format'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 16),
              const Text('Screen Type', style: TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: selectedScreenType,
                isExpanded: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                items: deovr.screenTypeLabels.entries
                    .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => selectedScreenType = value);
                },
              ),
              const SizedBox(height: 16),
              const Text('Stereo Mode', style: TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: selectedStereoMode,
                isExpanded: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                items: deovr.stereoModeLabels.entries
                    .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => selectedStereoMode = value);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Play'),
            ),
          ],
        ),
      ),
    );

    if (result != true) {
      return null;
    }

    return (screenType: selectedScreenType, stereoMode: selectedStereoMode);
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
      _fetchAndPushMetadataAsync(
        result.payload,
        result.entries,
        sessionId,
        args.viewMode,
        rdTorrentId: args.rdTorrentId,
        torboxTorrentId: args.torboxTorrentId,
        pikpakCollectionId: args.pikpakCollectionId,
        contentImdbId: args.contentImdbId,
        contentType: args.contentType,
      );

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
    PlaylistViewMode? viewMode, {
    String? rdTorrentId,
    String? torboxTorrentId,
    String? pikpakCollectionId,
    String? contentImdbId,
    String? contentType,
  }) {
    debugPrint('TVMazeAsync: _fetchAndPushMetadataAsync CALLED');
    debugPrint('TVMazeAsync: contentType=${payload.contentType}, title=${payload.title}');
    debugPrint('TVMazeAsync: entries.length=${entries.length}, viewMode=$viewMode, imdbId=$contentImdbId');

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
        // Determine forceSeries: prefer viewMode, then use contentType from catalog
        bool? forceSeries = viewMode?.toForceSeries();
        if (forceSeries == null && contentType != null) {
          forceSeries = contentType == 'series';
        }

        debugPrint('TVMazeAsync: Creating SeriesPlaylist from ${playlistEntries.length} entries');
        final seriesPlaylist = SeriesPlaylist.fromPlaylistEntries(
          playlistEntries,
          collectionTitle: payload.title,
          forceSeries: forceSeries,
        );

        debugPrint('TVMazeAsync: SeriesPlaylist created - isSeries=${seriesPlaylist.isSeries}, seriesTitle=${seriesPlaylist.seriesTitle}');
        debugPrint('TVMazeAsync: allEpisodes.length=${seriesPlaylist.allEpisodes.length}');

        if (!seriesPlaylist.isSeries) {
          // For non-series content, try to fetch movie metadata to get IMDB ID
          debugPrint('MovieAsync: Not a series, attempting movie metadata fetch');
          await seriesPlaylist.fetchMovieMetadata();

          final discoveredImdbId = seriesPlaylist.imdbId;
          if (discoveredImdbId != null) {
            debugPrint('MovieAsync: Found IMDB ID $discoveredImdbId, pushing to native player');

            // Check if this session is still current
            if (!AndroidTvPlayerBridge.isCurrentSession(sessionId)) {
              debugPrint('MovieAsync: DISCARDED - session $sessionId is no longer current');
              return;
            }

            // Store and push IMDB ID to native player (no episode metadata for movies)
            AndroidTvPlayerBridge.storePendingMetadataUpdates(
              [],
              sessionId: sessionId,
              imdbId: discoveredImdbId,
            );

            await AndroidTvPlayerBridge.updateEpisodeMetadata(
              [],
              sessionId: sessionId,
              imdbId: discoveredImdbId,
            );
            debugPrint('MovieAsync: IMDB ID pushed to native player');
          } else {
            debugPrint('MovieAsync: No IMDB ID discovered, cannot fetch subtitles');
          }
          return;
        }

        debugPrint('TVMazeAsync: Calling fetchEpisodeInfo() with imdbId=$contentImdbId');
        await seriesPlaylist.fetchEpisodeInfo(imdbId: contentImdbId);
        debugPrint('TVMazeAsync: fetchEpisodeInfo() completed');

        // Save series poster to playlist item (if we have series info)
        await _saveSeriesPosterToPlaylist(
          seriesPlaylist,
          rdTorrentId: rdTorrentId,
          torboxTorrentId: torboxTorrentId,
          pikpakCollectionId: pikpakCollectionId,
        );

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

        // Get discovered IMDB ID from TVMaze (may have been extracted from externals)
        final discoveredImdbId = seriesPlaylist.imdbId;
        debugPrint('TVMazeAsync: Discovered IMDB ID from TVMaze: $discoveredImdbId');

        if (metadataUpdates.isEmpty && discoveredImdbId == null) {
          debugPrint('TVMazeAsync: SKIPPED push - no metadata updates and no IMDB ID');
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
        debugPrint('TVMazeAsync: Storing ${metadataUpdates.length} pending metadata updates for fallback (imdbId=$discoveredImdbId)');
        AndroidTvPlayerBridge.storePendingMetadataUpdates(
          metadataUpdates,
          sessionId: sessionId,
          imdbId: discoveredImdbId,
        );

        // Push metadata updates directly to native player (don't wait for request)
        // Include discovered IMDB ID for Stremio subtitle fetching
        debugPrint('TVMazeAsync: Pushing ${metadataUpdates.length} metadata updates to native player (imdbId=$discoveredImdbId)');
        await AndroidTvPlayerBridge.updateEpisodeMetadata(
          metadataUpdates,
          sessionId: sessionId,
          imdbId: discoveredImdbId,
        );
        debugPrint('TVMazeAsync: Metadata push complete');
      } catch (e, stack) {
        debugPrint('TVMazeAsync: ERROR - $e');
        debugPrint('TVMazeAsync: Stack - $stack');
      }
    }();
  }

  /// Save series poster URL to playlist item (Android TV flow)
  static Future<void> _saveSeriesPosterToPlaylist(
    SeriesPlaylist seriesPlaylist, {
    String? rdTorrentId,
    String? torboxTorrentId,
    String? pikpakCollectionId,
  }) async {
    debugPrint('🎬 _saveSeriesPosterToPlaylist (Android TV) called');
    debugPrint('  seriesTitle: ${seriesPlaylist.seriesTitle}');

    if (seriesPlaylist.seriesTitle == null) {
      debugPrint('  ⚠️ No series title, skipping poster save');
      return;
    }

    debugPrint('  rdTorrentId: $rdTorrentId');
    debugPrint('  torboxTorrentId: $torboxTorrentId');
    debugPrint('  pikpakCollectionId: $pikpakCollectionId');

    // Need at least one identifier to save poster
    if ((rdTorrentId == null || rdTorrentId.isEmpty) &&
        (torboxTorrentId == null || torboxTorrentId.isEmpty) &&
        (pikpakCollectionId == null || pikpakCollectionId.isEmpty)) {
      debugPrint('  ⚠️ No valid identifier found, skipping poster save');
      return;
    }

    // Try to get series info to extract poster URL
    try {
      debugPrint('  Fetching series info from TVMaze...');
      final seriesInfo = await EpisodeInfoService.getSeriesInfo(
        seriesPlaylist.seriesTitle!,
      );

      if (seriesInfo != null && seriesInfo['image'] != null) {
        final posterUrl =
            seriesInfo['image']['original'] ?? seriesInfo['image']['medium'];
        debugPrint('  Poster URL from TVMaze: $posterUrl');

        if (posterUrl != null && posterUrl.isNotEmpty) {
          // Find the playlist item by ID
          debugPrint('  Looking for playlist item...');
          final items = await StorageService.getPlaylistItemsRaw();
          Map<String, dynamic>? targetItem;

          for (final item in items) {
            bool matches = false;

            if (rdTorrentId != null && rdTorrentId.isNotEmpty) {
              matches = (item['rdTorrentId'] as String?) == rdTorrentId;
            } else if (torboxTorrentId != null && torboxTorrentId.isNotEmpty) {
              final torboxId = item['torboxTorrentId'];
              matches = torboxId != null && torboxId.toString() == torboxTorrentId.toString();
            } else if (pikpakCollectionId != null && pikpakCollectionId.isNotEmpty) {
              final pikpakFileId = item['pikpakFileId'] as String?;
              final pikpakFileIds = item['pikpakFileIds'] as List<dynamic>?;
              matches = pikpakFileId == pikpakCollectionId ||
                        (pikpakFileIds != null && pikpakFileIds.isNotEmpty &&
                         pikpakFileIds[0].toString() == pikpakCollectionId);
            }

            if (matches) {
              targetItem = item;
              debugPrint('  ✅ Found playlist item');
              break;
            }
          }

          if (targetItem != null) {
            debugPrint('  Saving poster override...');
            await StorageService.savePlaylistPosterOverride(
              playlistItem: targetItem,
              posterUrl: posterUrl,
            );
            debugPrint('  ✅ Poster save SUCCESS');
          } else {
            debugPrint('  ❌ Playlist item not found');
          }
        } else {
          debugPrint('  ⚠️ No poster URL found in series info');
        }
      } else {
        debugPrint('  ⚠️ No series info or image found from TVMaze');
      }
    } catch (e) {
      debugPrint('  ❌ Error saving poster: $e');
      // Silently fail - poster is optional
    }
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
      // For direct stream URLs, resolve redirects to get final URL
      // (needed for HLS streams behind short URL redirects like USATV)
      return await _resolveRedirectUrl(entry.url);
    }

    final provider = entry.provider?.toLowerCase();
    final hasTorboxMetadata =
        entry.torboxTorrentId != null && entry.torboxFileId != null;
    final hasTorboxWebDownloadMetadata =
        entry.torboxWebDownloadId != null && entry.torboxFileId != null;

    if (provider == 'torbox' || hasTorboxMetadata || hasTorboxWebDownloadMetadata) {
      final torrentId = entry.torboxTorrentId;
      final webDownloadId = entry.torboxWebDownloadId;
      final fileId = entry.torboxFileId;
      if (fileId == null || (torrentId == null && webDownloadId == null)) {
        throw Exception('Torbox file metadata missing');
      }
      final apiKey = await StorageService.getTorboxApiKey();
      if (apiKey == null || apiKey.isEmpty) {
        throw Exception('Missing Torbox API key');
      }
      String url;
      if (webDownloadId != null) {
        // Web download - use web download API
        url = await TorboxService.requestWebDownloadFileLink(
          apiKey: apiKey,
          webId: webDownloadId,
          fileId: fileId,
        );
      } else {
        // Torrent - use torrent API
        url = await TorboxService.requestFileDownloadLink(
          apiKey: apiKey,
          torrentId: torrentId!,
          fileId: fileId,
        );
      }
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
  final List<_AndroidTvCollectionGroup>? collectionGroups;
  final String? imdbId;

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
    this.collectionGroups,
    this.imdbId,
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
      'nextEpisodeMap': nextEpisodeMap.map((k, v) => MapEntry(k.toString(), v)),
      'prevEpisodeMap': prevEpisodeMap.map((k, v) => MapEntry(k.toString(), v)),
      'collectionGroups': collectionGroups?.map((e) => e.toMap()).toList(),
      'imdbId': imdbId,
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

class _AndroidTvCollectionGroup {
  final String name;
  final List<int> fileIndices;

  const _AndroidTvCollectionGroup({
    required this.name,
    required this.fileIndices,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'fileIndices': fileIndices,
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

    // Build collection groups for movie collections
    List<_AndroidTvCollectionGroup>? collectionGroups;
    if (contentType == _PlaybackContentType.collection && launcherEntries.isNotEmpty) {
      // Extract PlaylistEntry objects from _LauncherEntry wrappers
      final playlistEntries = launcherEntries.map((e) => e.entry).toList();

      // Create MovieCollection based on view mode:
      // - Raw: Preserve folder structure as-is
      // - Sorted: Files are already sorted A-Z in playlist, create single group
      // - Series/Other: Use Main/Extras grouping (40% threshold)
      debugPrint('🎬 MovieCollection: viewMode=${args.viewMode}, contentType=$contentType');
      final MovieCollection movieCollection;
      if (args.viewMode == PlaylistViewMode.raw) {
        debugPrint('🎬 Using fromFolderStructure (Raw mode)');
        movieCollection = MovieCollection.fromFolderStructure(
          playlist: playlistEntries,
          title: args.title,
        );
      } else if (args.viewMode == PlaylistViewMode.sorted) {
        debugPrint('🎬 Using fromSortedPlaylist (Sort A-Z mode)');
        movieCollection = MovieCollection.fromSortedPlaylist(
          playlist: playlistEntries,
          title: args.title,
        );
      } else {
        debugPrint('🎬 Using fromPlaylistWithMainExtras (Main/Extras mode) - viewMode is ${args.viewMode}');
        movieCollection = MovieCollection.fromPlaylistWithMainExtras(
          playlist: playlistEntries,
          title: args.title,
        );
      }

      // Convert to Android TV collection groups
      collectionGroups = movieCollection.groups
          .where((group) => group.fileIndices.isNotEmpty) // Only include non-empty groups
          .map((group) => _AndroidTvCollectionGroup(
                name: group.name,
                fileIndices: group.fileIndices,
              ))
          .toList();

      debugPrint('VideoPlayerLauncher: Created ${collectionGroups.length} collection groups for Android TV');
      for (final group in collectionGroups) {
        debugPrint('  - ${group.name}: ${group.fileIndices.length} files');
      }
    }

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
      collectionGroups: collectionGroups,
      imdbId: args.contentImdbId,
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

      // For start index entry, always resolve (handles redirects for direct streams)
      if (i == startIndex) {
        final resolved = await VideoPlayerLauncher._resolveEntryUrl(entry, args);
        if (resolved.isEmpty) {
          throw Exception('Failed to resolve initial stream');
        }
        // Only create new entry if URL changed
        if (resolved != entry.url) {
          prepared.add(
            PlaylistEntry(
              url: resolved,
              title: entry.title,
              relativePath: entry.relativePath,
              restrictedLink: entry.restrictedLink,
              torrentHash: entry.torrentHash,
              sizeBytes: entry.sizeBytes,
              provider: entry.provider,
              torboxTorrentId: entry.torboxTorrentId,
              torboxWebDownloadId: entry.torboxWebDownloadId,
              torboxFileId: entry.torboxFileId,
              pikpakFileId: entry.pikpakFileId,
              rdTorrentId: entry.rdTorrentId,
              rdLinkIndex: entry.rdLinkIndex,
            ),
          );
        } else {
          prepared.add(entry);
        }
        continue;
      }

      // Non-start entries are added as-is (will be resolved lazily if needed)
      prepared.add(entry);
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
      // Determine forceSeries: prefer viewMode, then use contentType from catalog
      bool? forceSeries = args.viewMode?.toForceSeries();
      if (forceSeries == null && args.contentType != null) {
        // Use catalog content type: 'series' -> force series, 'movie' -> force not series
        forceSeries = args.contentType == 'series';
      }

      final playlist = SeriesPlaylist.fromPlaylistEntries(
        entries,
        collectionTitle: args.title, // Pass collection/torrent title as fallback
        forceSeries: forceSeries,
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
      final candidate = playlist.getFirstEpisodeOriginalIndex();
      if (candidate == -1) {
        return args.startIndex ?? 0;
      }
      final maxIndex = playlist.allEpisodes.length - 1;
      return candidate.clamp(0, maxIndex).toInt();
    }
    final originalIndex = playlist.findOriginalIndexBySeasonEpisode(
      lastEpisode['season'] as int,
      lastEpisode['episode'] as int,
    );
    if (originalIndex != -1) {
      return originalIndex;
    }
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
    // If auto-resume is disabled, use explicit start index
    if (args.disableAutoResume) {
      debugPrint('AndroidTV: auto-resume disabled for collection, using startIndex=${args.startIndex ?? 0}');
      return args.startIndex ?? 0;
    }

    // Find most recently watched item
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

    // Raw mode: start at first file (index 0)
    if (args.viewMode == PlaylistViewMode.raw) {
      return 0;
    }

    // Sorted/collection mode: start at first Main group file
    final indices = _getMainGroupIndices(entries);
    if (indices.isNotEmpty) {
      return indices.first;
    }

    return args.startIndex ?? 0;
  }

  List<_AndroidTvSeriesSeason> _buildSeriesSeasons(SeriesPlaylist? playlist) {
    if (playlist == null) {
      return const [];
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
      final yearA = yearOf(a);
      final yearB = yearOf(b);
      if (yearA != null && yearB != null) {
        return yearA.compareTo(yearB);
      }
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
    final name = entry.title.isNotEmpty ? entry.title : args.title;
    return _generateFilenameHash(name);
  }

  String? _torboxResumeKeyForEntry(PlaylistEntry entry) {
    final provider = entry.provider?.toLowerCase();
    if (provider == 'torbox') {
      final torrentId = entry.torboxTorrentId;
      final webDownloadId = entry.torboxWebDownloadId;
      final fileId = entry.torboxFileId;
      if (webDownloadId != null && fileId != null) {
        return 'torbox_web_${webDownloadId}_$fileId';
      }
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
