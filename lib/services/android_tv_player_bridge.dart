import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

// For debugPrint
import 'package:flutter/material.dart' show debugPrint;

import '../utils/movie_parser.dart';
import 'movie_metadata_service.dart';
import 'stremio_service.dart';
import 'subtitle_font_service.dart';

typedef StreamNextProvider = Future<Map<String, String>?> Function();
typedef TorboxNextProvider = StreamNextProvider; // Backward compatibility
typedef ChannelSwitchProvider = Future<Map<String, dynamic>?> Function();
typedef ChannelByIdSwitchProvider =
    Future<Map<String, dynamic>?> Function(String channelId);
typedef StremioTvNextProvider =
    Future<Map<String, dynamic>?> Function(String channelId);
typedef PlaybackFinishedCallback = Future<void> Function();
typedef AndroidTvProgressCallback =
    Future<void> Function(Map<String, dynamic> progress);
typedef TorrentStreamProvider =
    Future<Map<String, dynamic>?> Function(Map<String, dynamic> request);
typedef MovieMetadataProvider =
    Future<String?> Function(int index, String filename);

/// Bridge helper for launching native Android TV playback using ExoPlayer.
///
/// Supports both Torbox and Real-Debrid providers.
/// When active, native playback requests additional streams via the
/// [StreamNextProvider] callback.
class AndroidTvPlayerBridge {
  static const MethodChannel _channel = MethodChannel(
    'com.debrify.app/android_tv_player',
  );

  static StreamNextProvider? _streamNextProvider;
  static ChannelSwitchProvider? _channelSwitchProvider;
  static ChannelByIdSwitchProvider? _channelByIdSwitchProvider;
  static PlaybackFinishedCallback? _playbackFinishedCallback;
  static bool _handlerInitialized = false;
  static AndroidTvProgressCallback? _torrentProgressCallback;
  static PlaybackFinishedCallback? _torrentFinishedCallback;
  static TorrentStreamProvider? _torrentStreamProvider;
  static MovieMetadataProvider? _movieMetadataProvider;
  static Future<String?> Function(int)? _stremioSourceResolver;
  static Future<List<Map<String, dynamic>>?> Function(int)?
  _sourcePlaylistResolver;
  static Future<Map<String, dynamic>?> Function(List<String>)?
  _stremioTvGuideDataProvider;
  static Future<Map<String, dynamic>?> Function(String)?
  _stremioTvChannelSwitchProvider;
  static StremioTvNextProvider? _stremioTvNextProvider;

  // Quick Play next episode result from Android TV player
  static Map<String, dynamic>? _quickPlayNextEpisodeResult;

  // Store pending metadata updates for when activity requests them
  static List<Map<String, dynamic>>? _pendingMetadataUpdates;
  // Store pending IMDB ID discovered from TVMaze (for Stremio subtitles)
  static String? _pendingImdbId;

  // Session ID to track which launch the metadata belongs to
  // Prevents stale metadata from previous sessions being sent to new sessions
  static String? _currentSessionId;

  // Deprecated: use _streamNextProvider
  static StreamNextProvider? get _torboxNextProvider => _streamNextProvider;
  static set _torboxNextProvider(StreamNextProvider? provider) =>
      _streamNextProvider = provider;

  // Deprecated: use _playbackFinishedCallback
  static PlaybackFinishedCallback? get _torboxFinishedCallback =>
      _playbackFinishedCallback;
  static set _torboxFinishedCallback(PlaybackFinishedCallback? callback) =>
      _playbackFinishedCallback = callback;

  /// Get custom font info for Android TV player
  static Future<Map<String, String?>> _getCustomFontInfo() async {
    try {
      final font = await SubtitleFontService.instance.getSelectedFont();
      if (font.isCustom && font.path != null) {
        return {'customFontPath': font.path, 'customFontName': font.label};
      }
    } catch (e) {
      debugPrint('AndroidTvPlayerBridge: Error getting custom font info: $e');
    }
    return {};
  }

  static void _ensureInitialized() {
    if (_handlerInitialized) {
      return;
    }
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'requestTorboxNext':
        case 'requestRealDebridNext':
        case 'requestStreamNext':
          final provider = _streamNextProvider;
          if (provider == null) {
            return null;
          }
          try {
            return await provider();
          } catch (e) {
            throw PlatformException(
              code: 'stream_next_failed',
              message: e.toString(),
            );
          }
        case 'requestNextChannel':
          final channelProvider = _channelSwitchProvider;
          if (channelProvider == null) {
            return null;
          }
          try {
            return await channelProvider();
          } catch (e) {
            throw PlatformException(
              code: 'channel_switch_failed',
              message: e.toString(),
            );
          }
        case 'requestChannelById':
          final args = call.arguments;
          String? channelId;
          if (args is Map) {
            final raw = args['channelId'];
            if (raw is String) {
              channelId = raw.trim();
            }
          } else if (args is String) {
            channelId = args.trim();
          }
          final selectProvider = _channelByIdSwitchProvider;
          if (channelId == null ||
              channelId.isEmpty ||
              selectProvider == null) {
            return null;
          }
          try {
            return await selectProvider(channelId);
          } catch (e) {
            throw PlatformException(
              code: 'channel_select_failed',
              message: e.toString(),
            );
          }
        case 'torboxPlaybackFinished':
        case 'realDebridPlaybackFinished':
        case 'streamPlaybackFinished':
          final finished = _playbackFinishedCallback;
          _streamNextProvider = null;
          _channelSwitchProvider = null;
          _channelByIdSwitchProvider = null;
          _playbackFinishedCallback = null;
          if (finished != null) {
            try {
              await finished();
            } catch (e, stack) {
              debugPrint(
                'AndroidTvPlayerBridge: onFinished callback threw: $e\n$stack',
              );
            }
          }
          return null;
        case 'torrentPlaybackProgress':
          final handler = _torrentProgressCallback;
          if (handler == null) {
            return null;
          }
          final args = call.arguments;
          if (args is Map) {
            try {
              await handler(Map<String, dynamic>.from(args));
            } catch (e, stack) {
              debugPrint(
                'AndroidTvPlayerBridge: progress callback error $e\n$stack',
              );
            }
          }
          return null;
        case 'requestStremioSourceResolve':
          debugPrint(
            'AndroidTvPlayerBridge: requestStremioSourceResolve received - args: ${call.arguments}',
          );
          final stremioResolver = _stremioSourceResolver;
          if (stremioResolver == null) {
            debugPrint(
              'AndroidTvPlayerBridge: ERROR - no stremio source resolver registered!',
            );
            return null;
          }
          final stremioArgs = call.arguments;
          if (stremioArgs is Map) {
            final sourceIndex = stremioArgs['sourceIndex'] as int?;
            if (sourceIndex == null) {
              debugPrint('AndroidTvPlayerBridge: missing sourceIndex');
              return null;
            }
            try {
              final url = await stremioResolver(sourceIndex);
              debugPrint(
                'AndroidTvPlayerBridge: stremio source resolver returned: ${url != null ? "success" : "null"}',
              );
              return url != null ? {'url': url} : null;
            } catch (e, stack) {
              debugPrint(
                'AndroidTvPlayerBridge: stremio source resolver error $e\n$stack',
              );
              throw PlatformException(
                code: 'stremio_source_resolve_failed',
                message: e.toString(),
              );
            }
          }
          return null;
        case 'requestStremioTvGuideData':
          debugPrint(
            'AndroidTvPlayerBridge: requestStremioTvGuideData received',
          );
          final guideProvider = _stremioTvGuideDataProvider;
          if (guideProvider == null) {
            debugPrint(
              'AndroidTvPlayerBridge: no guide data provider registered',
            );
            return null;
          }
          final guideArgs = call.arguments;
          if (guideArgs is Map) {
            final channelIds = (guideArgs['channelIds'] as List?)
                ?.map((e) => e.toString())
                .toList();
            if (channelIds == null || channelIds.isEmpty) return null;
            try {
              final data = await guideProvider(channelIds);
              return data;
            } catch (e, stack) {
              debugPrint(
                'AndroidTvPlayerBridge: guide data provider error $e\n$stack',
              );
              throw PlatformException(
                code: 'stremio_tv_guide_data_failed',
                message: e.toString(),
              );
            }
          }
          return null;
        case 'requestStremioTvChannelSwitch':
          debugPrint(
            'AndroidTvPlayerBridge: requestStremioTvChannelSwitch received',
          );
          final switchProvider = _stremioTvChannelSwitchProvider;
          if (switchProvider == null) {
            debugPrint(
              'AndroidTvPlayerBridge: no channel switch provider registered',
            );
            return null;
          }
          final switchArgs = call.arguments;
          if (switchArgs is Map) {
            final channelId = switchArgs['channelId'] as String?;
            if (channelId == null || channelId.isEmpty) return null;
            try {
              final result = await switchProvider(channelId);
              debugPrint(
                'AndroidTvPlayerBridge: channel switch returned: ${result != null ? "success" : "null"}',
              );
              return result;
            } catch (e, stack) {
              debugPrint(
                'AndroidTvPlayerBridge: channel switch error $e\n$stack',
              );
              throw PlatformException(
                code: 'stremio_tv_channel_switch_failed',
                message: e.toString(),
              );
            }
          }
          return null;
        case 'requestStremioTvNext':
          debugPrint('AndroidTvPlayerBridge: requestStremioTvNext received');
          final nextProvider = _stremioTvNextProvider;
          if (nextProvider == null) {
            debugPrint(
              'AndroidTvPlayerBridge: no Stremio TV next provider registered',
            );
            return null;
          }
          final nextArgs = call.arguments;
          if (nextArgs is Map) {
            final channelId = nextArgs['channelId'] as String?;
            if (channelId == null || channelId.isEmpty) return null;
            try {
              final result = await nextProvider(channelId);
              debugPrint(
                'AndroidTvPlayerBridge: Stremio TV next returned: ${result != null ? "success" : "null"}',
              );
              return result;
            } catch (e, stack) {
              debugPrint(
                'AndroidTvPlayerBridge: Stremio TV next error $e\n$stack',
              );
              throw PlatformException(
                code: 'stremio_tv_next_failed',
                message: e.toString(),
              );
            }
          }
          return null;
        case 'requestSourcePlaylistResolve':
          debugPrint(
            'AndroidTvPlayerBridge: requestSourcePlaylistResolve received - args: ${call.arguments}',
          );
          final playlistResolver = _sourcePlaylistResolver;
          if (playlistResolver == null) {
            debugPrint(
              'AndroidTvPlayerBridge: ERROR - no source playlist resolver registered!',
            );
            return null;
          }
          final playlistArgs = call.arguments;
          if (playlistArgs is Map) {
            final sourceIndex = playlistArgs['sourceIndex'] as int?;
            if (sourceIndex == null) {
              debugPrint(
                'AndroidTvPlayerBridge: missing sourceIndex for playlist resolve',
              );
              return null;
            }
            try {
              final items = await playlistResolver(sourceIndex);
              debugPrint(
                'AndroidTvPlayerBridge: source playlist resolver returned: ${items != null ? "${items.length} items" : "null"}',
              );
              if (items != null && items.isNotEmpty) {
                return {'items': items};
              }
              return null;
            } catch (e, stack) {
              debugPrint(
                'AndroidTvPlayerBridge: source playlist resolver error $e\n$stack',
              );
              throw PlatformException(
                code: 'source_playlist_resolve_failed',
                message: e.toString(),
              );
            }
          }
          return null;
        case 'torrentPlaybackFinished':
          final finishedTorrent = _torrentFinishedCallback;
          _torrentProgressCallback = null;
          _torrentFinishedCallback = null;
          _torrentStreamProvider = null;
          _movieMetadataProvider = null;
          _stremioSourceResolver = null;
          _sourcePlaylistResolver = null;
          _stremioTvGuideDataProvider = null;
          _stremioTvChannelSwitchProvider = null;
          _stremioTvNextProvider = null;
          if (finishedTorrent != null) {
            try {
              await finishedTorrent();
            } catch (e, stack) {
              debugPrint(
                'AndroidTvPlayerBridge: torrent finished callback threw: $e\n$stack',
              );
            }
          }
          // Clear any unconsumed quick play next result to prevent stale state
          _quickPlayNextEpisodeResult = null;
          return null;
        case 'requestTorrentStream':
          debugPrint(
            'AndroidTvPlayerBridge: requestTorrentStream received - args: ${call.arguments}',
          );
          final resolver = _torrentStreamProvider;
          if (resolver == null) {
            debugPrint(
              'AndroidTvPlayerBridge: ERROR - no torrent stream provider registered!',
            );
            return null;
          }
          final args = call.arguments;
          if (args is Map) {
            try {
              final result = await resolver(Map<String, dynamic>.from(args));
              debugPrint(
                'AndroidTvPlayerBridge: stream provider returned: ${result != null ? "success (url length: ${result['url']?.toString().length ?? 0})" : "null"}',
              );
              return result;
            } catch (e, stack) {
              debugPrint(
                'AndroidTvPlayerBridge: stream provider error $e\n$stack',
              );
              throw PlatformException(
                code: 'torrent_stream_failed',
                message: e.toString(),
              );
            }
          }
          return null;
        case 'requestEpisodeMetadata':
          debugPrint(
            'TVMazeUpdate: requestEpisodeMetadata received from native',
          );
          final pending = _pendingMetadataUpdates;
          final pendingImdb = _pendingImdbId;
          if ((pending != null && pending.isNotEmpty) || pendingImdb != null) {
            debugPrint(
              'TVMazeUpdate: Sending ${pending?.length ?? 0} pending metadata updates, imdbId=$pendingImdb',
            );
            // Send the pending updates via broadcast (including IMDB ID for subtitles)
            await updateEpisodeMetadata(pending ?? [], imdbId: pendingImdb);
            // Clear pending updates after sending
            _pendingMetadataUpdates = null;
            _pendingImdbId = null;
          } else {
            debugPrint('TVMazeUpdate: No pending metadata updates to send');
          }
          return null;
        case 'requestMovieMetadata':
          debugPrint(
            'MovieMetadata: requestMovieMetadata received from native',
          );
          final provider = _movieMetadataProvider;
          if (provider == null) {
            debugPrint('MovieMetadata: No provider registered');
            return null;
          }
          final args = call.arguments;
          if (args is! Map) {
            debugPrint('MovieMetadata: Invalid arguments');
            return null;
          }
          final index = args['index'] as int?;
          final filename = args['filename'] as String?;
          if (index == null || filename == null) {
            debugPrint('MovieMetadata: Missing index or filename');
            return null;
          }
          try {
            debugPrint(
              'MovieMetadata: Fetching IMDB ID for index $index, filename: $filename',
            );
            final imdbId = await provider(index, filename);
            debugPrint('MovieMetadata: Provider returned IMDB ID: $imdbId');
            return imdbId != null ? {'imdbId': imdbId} : null;
          } catch (e) {
            debugPrint('MovieMetadata: Provider error: $e');
            return null;
          }
        case 'searchSubtitleCatalogs':
          debugPrint('AndroidTvPlayerBridge: searchSubtitleCatalogs received');
          final args = call.arguments;
          if (args is! Map) {
            debugPrint('AndroidTvPlayerBridge: Invalid subtitle search args');
            return <Map<String, dynamic>>[];
          }
          final query = args['query'] as String?;
          if (query == null || query.trim().isEmpty) {
            return <Map<String, dynamic>>[];
          }
          try {
            final metas = await StremioService.instance.searchCatalogs(query);
            final seen = <String>{};
            final results = <Map<String, dynamic>>[];

            for (final meta in metas) {
              final imdbId = meta.effectiveImdbId;
              final type = meta.type.toLowerCase();
              if (imdbId == null || !imdbId.startsWith('tt')) continue;
              if (type != 'movie' && type != 'series') continue;

              final key = '$type:$imdbId';
              if (!seen.add(key)) continue;

              results.add({
                'imdbId': imdbId,
                'type': type,
                'name': meta.name,
                if (meta.year != null && meta.year!.trim().isNotEmpty)
                  'year': meta.year,
                if (meta.sourceAddon?.name.trim().isNotEmpty == true)
                  'source': meta.sourceAddon!.name,
              });
            }

            debugPrint(
              'AndroidTvPlayerBridge: subtitle catalog search returned ${results.length} results',
            );
            return results;
          } catch (e, stack) {
            debugPrint(
              'AndroidTvPlayerBridge: subtitle catalog search failed: $e\n$stack',
            );
            throw PlatformException(
              code: 'subtitle_catalog_search_failed',
              message: e.toString(),
            );
          }
        case 'lookupMovieImdb':
          // Simple IMDB lookup for TorboxTvPlayerActivity (DebrifyTV)
          // Uses MovieMetadataService directly without needing a provider
          debugPrint('MovieMetadata: lookupMovieImdb received from native');
          final args = call.arguments;
          if (args is! Map) {
            debugPrint('MovieMetadata: Invalid arguments for lookupMovieImdb');
            return null;
          }
          final filename = args['filename'] as String?;
          if (filename == null || filename.isEmpty) {
            debugPrint('MovieMetadata: Missing filename');
            return null;
          }
          try {
            // Parse the filename to extract title and year
            final parsed = MovieParser.parseFilename(filename);
            debugPrint(
              'MovieMetadata: Parsed filename "$filename" -> title="${parsed.title}", year=${parsed.year}',
            );

            // Need a valid title to lookup
            if (parsed.title == null || parsed.title!.isEmpty) {
              debugPrint(
                'MovieMetadata: Could not extract title from "$filename"',
              );
              return null;
            }

            // Lookup the movie using MovieMetadataService
            final metadata = await MovieMetadataService.lookupMovie(
              parsed.title!,
              parsed.year,
            );
            if (metadata != null) {
              debugPrint(
                'MovieMetadata: Found IMDB ID ${metadata.imdbId} for "$filename"',
              );
              return {'imdbId': metadata.imdbId};
            } else {
              debugPrint('MovieMetadata: No IMDB ID found for "$filename"');
              return null;
            }
          } catch (e) {
            debugPrint('MovieMetadata: lookupMovieImdb error: $e');
            return null;
          }
        case 'requestQuickPlayNextEpisode':
          final args = call.arguments;
          if (args is Map) {
            final imdbId = args['imdbId'] as String?;
            final season = args['season'] as int?;
            final episode = args['episode'] as int?;
            if (imdbId != null && season != null && episode != null) {
              debugPrint(
                'AndroidTvPlayerBridge: Quick Play next episode requested after S${season}E$episode',
              );
              // Store the raw request only — the async NextEpisode lookup
              // happens in the onFinished callback to avoid racing with the
              // native Activity's finish() call (which was consuming a null
              // result before this handler's await had completed).
              _quickPlayNextEpisodeResult = {
                'quickPlayNext': true,
                'imdbId': imdbId,
                'currentSeason': season,
                'currentEpisode': episode,
              };
            }
          }
          return null;
        default:
          throw PlatformException(
            code: 'unimplemented',
            message: 'Method ${call.method} not handled on Flutter side.',
          );
      }
    });
    _handlerInitialized = true;
  }

  static Future<bool> launchTorboxPlayback({
    required String initialUrl,
    required String title,
    required List<Map<String, dynamic>> magnets,
    required TorboxNextProvider requestNext,
    ChannelSwitchProvider? requestChannelSwitch,
    ChannelByIdSwitchProvider? requestChannelById,
    PlaybackFinishedCallback? onFinished,
    bool startFromRandom = false,
    int randomStartMaxPercent = 40,
    double? startAtPercent,
    bool hideSeekbar = false,
    bool hideOptions = false,
    bool showVideoTitle = true,
    bool showChannelName = false,
    String? channelName,
    List<Map<String, dynamic>>? channels,
    String? currentChannelId,
    int? currentChannelNumber,
  }) async {
    if (!Platform.isAndroid) {
      return false;
    }
    if (initialUrl.isEmpty) {
      return false;
    }

    _ensureInitialized();
    _streamNextProvider = requestNext;
    _channelSwitchProvider = requestChannelSwitch;
    _channelByIdSwitchProvider = requestChannelById;
    _playbackFinishedCallback = onFinished;

    try {
      final List<Map<String, dynamic>>? channelDirectory = channels
          ?.map((entry) => Map<String, dynamic>.from(entry))
          .toList(growable: false);

      // Get custom font info for Android TV player
      final fontInfo = await _getCustomFontInfo();

      final bool? launched = await _channel.invokeMethod<bool>(
        'launchTorboxPlayback',
        {
          'initialUrl': initialUrl,
          'initialTitle': title,
          'magnets': magnets,
          'channelName': channelName,
          'currentChannelId': currentChannelId,
          'currentChannelNumber': currentChannelNumber,
          'channels': channelDirectory,
          'config': {
            'startFromRandom': startFromRandom,
            'randomStartMaxPercent': randomStartMaxPercent,
            if (startAtPercent != null && startAtPercent > 0)
              'startAtPercent': startAtPercent,
            'hideSeekbar': hideSeekbar,
            'hideOptions': hideOptions,
            'showVideoTitle': showVideoTitle,
            'showChannelName': showChannelName,
          },
          ...fontInfo,
        },
      );
      if (launched == true) {
        return true;
      }
    } on PlatformException {
      // Fall through to cleanup and return false.
    }

    _streamNextProvider = null;
    _channelSwitchProvider = null;
    _channelByIdSwitchProvider = null;
    _playbackFinishedCallback = null;
    return false;
  }

  static Future<bool> launchRealDebridPlayback({
    required String initialUrl,
    required String title,
    String? channelName,
    required StreamNextProvider requestNext,
    ChannelSwitchProvider? requestChannelSwitch,
    ChannelByIdSwitchProvider? requestChannelById,
    PlaybackFinishedCallback? onFinished,
    bool startFromRandom = false,
    int randomStartMaxPercent = 40,
    double? startAtPercent,
    bool hideSeekbar = false,
    bool hideOptions = false,
    bool showVideoTitle = true,
    bool showChannelName = false,
    List<Map<String, dynamic>>? channels,
    String? currentChannelId,
    int? currentChannelNumber,
  }) async {
    debugPrint('AndroidTvPlayerBridge: launchRealDebridPlayback() called');
    debugPrint(
      'AndroidTvPlayerBridge: Platform.isAndroid=${Platform.isAndroid}',
    );

    if (!Platform.isAndroid) {
      debugPrint(
        'AndroidTvPlayerBridge: Not Android platform, returning false',
      );
      return false;
    }
    if (initialUrl.isEmpty) {
      debugPrint('AndroidTvPlayerBridge: initialUrl is empty, returning false');
      return false;
    }

    debugPrint('AndroidTvPlayerBridge: Initializing method channel handler');
    _ensureInitialized();
    _streamNextProvider = requestNext;
    _channelSwitchProvider = requestChannelSwitch;
    _channelByIdSwitchProvider = requestChannelById;
    _playbackFinishedCallback = onFinished;

    try {
      debugPrint(
        'AndroidTvPlayerBridge: Invoking method channel "launchRealDebridPlayback"',
      );
      debugPrint(
        'AndroidTvPlayerBridge: URL=${initialUrl.substring(0, initialUrl.length > 50 ? 50 : initialUrl.length)}...',
      );
      debugPrint('AndroidTvPlayerBridge: title="$title"');
      debugPrint('AndroidTvPlayerBridge: provider=real_debrid');

      // Get custom font info for Android TV player
      final fontInfo = await _getCustomFontInfo();

      final bool? launched = await _channel.invokeMethod<bool>(
        'launchRealDebridPlayback',
        {
          'initialUrl': initialUrl,
          'initialTitle': title,
          'provider': 'real_debrid',
          'channelName': channelName,
          'currentChannelId': currentChannelId,
          'currentChannelNumber': currentChannelNumber,
          'channels': channels
              ?.map((entry) => Map<String, dynamic>.from(entry))
              .toList(growable: false),
          'config': {
            'startFromRandom': startFromRandom,
            'randomStartMaxPercent': randomStartMaxPercent,
            if (startAtPercent != null && startAtPercent > 0)
              'startAtPercent': startAtPercent,
            'hideSeekbar': hideSeekbar,
            'hideOptions': hideOptions,
            'showVideoTitle': showVideoTitle,
            'showChannelName': showChannelName,
          },
          ...fontInfo,
        },
      );

      debugPrint('AndroidTvPlayerBridge: Method channel returned: $launched');

      if (launched == true) {
        debugPrint('AndroidTvPlayerBridge: ✅ Launch successful');
        return true;
      } else {
        debugPrint('AndroidTvPlayerBridge: ❌ Launch returned false or null');
      }
    } on PlatformException catch (e) {
      debugPrint(
        'AndroidTvPlayerBridge: ❌ PlatformException: ${e.code} - ${e.message}',
      );
      debugPrint('AndroidTvPlayerBridge: Details: ${e.details}');
    } catch (e) {
      debugPrint('AndroidTvPlayerBridge: ❌ Unexpected exception: $e');
    }

    debugPrint('AndroidTvPlayerBridge: Cleaning up providers');
    _streamNextProvider = null;
    _channelSwitchProvider = null;
    _channelByIdSwitchProvider = null;
    _playbackFinishedCallback = null;
    return false;
  }

  /// Consume and return the Quick Play next episode result (if any).
  /// Returns null if no next episode was requested or found.
  static Map<String, dynamic>? consumeQuickPlayNextResult() {
    final result = _quickPlayNextEpisodeResult;
    _quickPlayNextEpisodeResult = null;
    return result;
  }

  static void clearTorboxProvider() {
    _streamNextProvider = null;
    _channelSwitchProvider = null;
    _channelByIdSwitchProvider = null;
    _playbackFinishedCallback = null;
    _stremioTvNextProvider = null;
  }

  static void clearStreamProvider() {
    _streamNextProvider = null;
    _channelSwitchProvider = null;
    _channelByIdSwitchProvider = null;
    _playbackFinishedCallback = null;
    _stremioTvNextProvider = null;
  }

  static Future<bool> launchTorrentPlayback({
    required Map<String, dynamic> payload,
    AndroidTvProgressCallback? onProgress,
    PlaybackFinishedCallback? onFinished,
    TorrentStreamProvider? onRequestStream,
    MovieMetadataProvider? onRequestMovieMetadata,
    Future<String?> Function(int)? onResolveStremioSource,
    Future<List<Map<String, dynamic>>?> Function(int)? onResolveSourcePlaylist,
    Future<Map<String, dynamic>?> Function(List<String>)?
    onRequestStremioTvGuideData,
    Future<Map<String, dynamic>?> Function(String)?
    onRequestStremioTvChannelSwitch,
    StremioTvNextProvider? onRequestStremioTvNext,
  }) async {
    if (!Platform.isAndroid) {
      return false;
    }
    if (payload.isEmpty) {
      return false;
    }

    _ensureInitialized();
    _torrentProgressCallback = onProgress;
    _torrentFinishedCallback = onFinished;
    _torrentStreamProvider = onRequestStream;
    _movieMetadataProvider = onRequestMovieMetadata;
    _stremioSourceResolver = onResolveStremioSource;
    _sourcePlaylistResolver = onResolveSourcePlaylist;
    _stremioTvGuideDataProvider = onRequestStremioTvGuideData;
    _stremioTvChannelSwitchProvider = onRequestStremioTvChannelSwitch;
    _stremioTvNextProvider = onRequestStremioTvNext;

    // Clear any stale pending metadata from previous sessions
    _pendingMetadataUpdates = null;
    _pendingImdbId = null;

    try {
      // Get custom font info for Android TV player
      final fontInfo = await _getCustomFontInfo();

      // Add font info to payload
      final payloadWithFont = Map<String, dynamic>.from(payload);
      if (fontInfo['customFontPath'] != null) {
        payloadWithFont['customFontPath'] = fontInfo['customFontPath'];
        payloadWithFont['customFontName'] = fontInfo['customFontName'];
      }

      final bool? launched = await _channel.invokeMethod<bool>(
        'launchTorrentPlayback',
        {'payload': payloadWithFont},
      );
      if (launched == true) {
        return true;
      }
    } on PlatformException catch (e) {
      debugPrint(
        'AndroidTvPlayerBridge: torrent launch failed: ${e.code} - ${e.message}',
      );
    } catch (e) {
      debugPrint('AndroidTvPlayerBridge: unexpected torrent launch error: $e');
    }

    _torrentProgressCallback = null;
    _torrentFinishedCallback = null;
    _torrentStreamProvider = null;
    _movieMetadataProvider = null;
    _stremioSourceResolver = null;
    _sourcePlaylistResolver = null;
    _stremioTvGuideDataProvider = null;
    _stremioTvChannelSwitchProvider = null;
    _stremioTvNextProvider = null;
    return false;
  }

  /// Store pending metadata updates to be sent when the activity requests them
  /// The sessionId parameter ensures updates from stale sessions are discarded
  /// The imdbId parameter stores discovered IMDB ID for Stremio subtitle fetching
  static void storePendingMetadataUpdates(
    List<Map<String, dynamic>> updates, {
    String? sessionId,
    String? imdbId,
  }) {
    // Discard updates if session ID doesn't match current session
    if (sessionId != null && sessionId != _currentSessionId) {
      debugPrint(
        'TVMazeUpdate: Discarding ${updates.length} updates - stale session (got: $sessionId, current: $_currentSessionId)',
      );
      return;
    }
    debugPrint(
      'TVMazeUpdate: Storing ${updates.length} pending metadata updates, imdbId=$imdbId',
    );
    _pendingMetadataUpdates = updates;
    _pendingImdbId = imdbId;
  }

  /// Set the current session ID for metadata tracking
  /// Call this when launching a new playback session
  static void setCurrentSessionId(String sessionId) {
    debugPrint('TVMazeUpdate: Setting current session ID: $sessionId');
    _currentSessionId = sessionId;
  }

  /// Get the current session ID
  static String? get currentSessionId => _currentSessionId;

  /// Check if a session ID matches the current session
  static bool isCurrentSession(String sessionId) {
    return sessionId == _currentSessionId;
  }

  /// Push episode metadata updates to native player (for async TVMaze loading)
  /// Each update contains: originalIndex, title, description, artwork, rating
  /// If sessionId is provided, updates will be discarded if it doesn't match current session
  /// If imdbId is provided, native player will use it to fetch Stremio subtitles
  static Future<bool> updateEpisodeMetadata(
    List<Map<String, dynamic>> metadataUpdates, {
    String? sessionId,
    String? imdbId,
  }) async {
    if (!Platform.isAndroid) {
      return false;
    }
    if (metadataUpdates.isEmpty && imdbId == null) {
      return false;
    }

    // Discard updates if session ID doesn't match current session
    if (sessionId != null && sessionId != _currentSessionId) {
      debugPrint(
        'AndroidTvPlayerBridge: Discarding ${metadataUpdates.length} metadata updates - stale session (got: $sessionId, current: $_currentSessionId)',
      );
      return false;
    }

    try {
      debugPrint(
        'AndroidTvPlayerBridge: Pushing ${metadataUpdates.length} metadata updates to native (imdbId=$imdbId)',
      );
      final bool? success = await _channel.invokeMethod<bool>(
        'updateEpisodeMetadata',
        {'updates': metadataUpdates, if (imdbId != null) 'imdbId': imdbId},
      );
      debugPrint('AndroidTvPlayerBridge: Metadata update result: $success');
      return success == true;
    } on PlatformException catch (e) {
      debugPrint(
        'AndroidTvPlayerBridge: metadata update failed: ${e.code} - ${e.message}',
      );
      return false;
    } catch (e) {
      debugPrint('AndroidTvPlayerBridge: unexpected metadata update error: $e');
      return false;
    }
  }
}
