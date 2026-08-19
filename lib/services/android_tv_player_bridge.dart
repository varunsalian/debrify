import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

// For debugPrint
import 'package:flutter/material.dart' show debugPrint;

import '../utils/movie_parser.dart';
import 'analytics_service.dart';
import 'iptv_epg_service.dart';
import 'storage_service.dart';
import 'movie_metadata_service.dart';
import 'stremio_iptv_service.dart';
import 'stremio_service.dart';
import 'subtitle_font_service.dart';
import 'profiles/profile_preferences.dart';
import 'profiles/profile_runtime.dart';

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

  /// The platform channel hands headers back as a plain dynamic map; a stored
  /// channel replays from this metadata alone, so a UA/Referer-guarded stream
  /// is unplayable if it doesn't survive the crossing.
  static Map<String, String> _iptvHeadersFromArgs(Object? raw) {
    if (raw is! Map) return const {};
    final headers = <String, String>{};
    raw.forEach((key, value) {
      if (key is String && value != null) headers[key] = value.toString();
    });
    return headers;
  }

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
  // Series source tabs: fetches the not-yet-loaded category ('packs' |
  // 'episodes') for the currently playing season/episode and returns the full
  // updated source list + fetch flags.
  static Future<Map<String, dynamic>?> Function(
    String, {
    int? season,
    int? episode,
  })?
  _moreSourcesProvider;
  // Per-addon fetch for the source browser's placeholder groups: mode
  // 'episodes' fetches + merges the group's addons' episode results (a group
  // can hold several same-named addons) and names which ids returned torrent
  // magnets (packAddonIds); mode 'packs' runs the lazy season-pack probe for
  // exactly those ids as a follow-up call.
  static Future<Map<String, dynamic>?> Function(
    List<String> addonIds,
    String mode, {
    int? season,
    int? episode,
  })?
  _addonSourcesProvider;
  // Episode-guide fetch: quick-plays an absent (season, episode) without
  // leaving the native player — resolves it to a ready playlist plus the
  // grown source list; null/throw keeps native on its old finish fallback.
  static Future<Map<String, dynamic>?> Function(int season, int episode)?
  _episodeFetchProvider;
  static Future<Map<String, dynamic>?> Function(List<String>)?
  _stremioTvGuideDataProvider;
  static Future<Map<String, dynamic>?> Function(String)?
  _stremioTvChannelSwitchProvider;
  static StremioTvNextProvider? _stremioTvNextProvider;
  static Future<Map<String, dynamic>?> Function(Map<String, dynamic>)?
  _iptvBrowseProvider;

  // Quick Play next episode result from Android TV player
  static Map<String, dynamic>? _quickPlayNextEpisodeResult;

  // Store pending metadata updates for when activity requests them
  static List<Map<String, dynamic>>? _pendingMetadataUpdates;
  // Full-show episode guide (TVMaze) pending alongside the metadata updates.
  static List<Map<String, dynamic>>? _pendingGuideEpisodes;
  // Store pending IMDB ID discovered from TVMaze (for Stremio subtitles)
  static String? _pendingImdbId;

  // Session ID to track which launch the metadata belongs to
  // Prevents stale metadata from previous sessions being sent to new sessions
  static String? _currentSessionId;

  // Throttle for analytics playback heartbeats fed from the native TV player's
  // high-frequency progress pings (fires every ~5s). We only forward one
  // heartbeat per [AnalyticsService.heartbeatInterval] so the analytics session
  // stays alive without flooding events.
  static DateTime? _lastPlaybackHeartbeat;
  static Future<void> _subtitleAppearanceSaveQueue = Future<void>.value();

  static Future<void> _saveSubtitleAppearance(
    Map<String, dynamic> values,
  ) async {
    final operation = _subtitleAppearanceSaveQueue.then((_) async {
      final expectedProfileId = values['profileId'];
      final expectedGeneration = values['dataGeneration'];
      final expectedSessionEpoch = values['sessionEpoch'];
      final current = ProfileRuntime.capture();
      if (expectedProfileId != current.profileId ||
          expectedGeneration != current.dataGeneration ||
          expectedSessionEpoch != current.sessionEpoch) {
        throw StateError('Stale native subtitle appearance authority');
      }
      final size = values['subtitle_size_index'];
      final style = values['subtitle_style_index'];
      final color = values['subtitle_color_index'];
      final background = values['subtitle_bg_index'];
      final outline = values['subtitle_outline_color_index'];
      final elevation = values['subtitle_elevation_index'];
      final bold = values['subtitle_bold'];
      final fontId = values['subtitle_selected_font_id'];
      final update = <String, Object>{};
      if (size is int) update['subtitle_size_index'] = size.clamp(0, 6);
      if (style is int) update['subtitle_style_index'] = style.clamp(0, 4);
      if (color is int) update['subtitle_color_index'] = color.clamp(0, 7);
      if (background is int) {
        update['subtitle_bg_index'] = background.clamp(0, 4);
      }
      if (outline is int) {
        update['subtitle_outline_color_index'] = outline.clamp(0, 9);
      }
      if (elevation is int) {
        update['subtitle_elevation_index'] = elevation.clamp(0, 4);
      }
      if (bold is bool) update['subtitle_bold'] = bold;
      if (fontId is String && fontId.isNotEmpty) {
        final fonts = await SubtitleFontService.instance.getAllFonts();
        if (fonts.any((font) => font.id == fontId)) {
          update['subtitle_selected_font_id'] = fontId;
        }
      }
      if (update.isNotEmpty) {
        final prefs = await ProfilePreferences.instance();
        if (!await prefs.setNativeProjectionBatch(update)) {
          throw StateError('Could not save native subtitle appearance');
        }
      }
    });
    _subtitleAppearanceSaveQueue = operation.catchError((_) {});
    await operation;
  }

  static void _maybeSendPlaybackHeartbeat(String player) {
    final now = DateTime.now();
    final last = _lastPlaybackHeartbeat;
    if (last != null &&
        now.difference(last) < AnalyticsService.heartbeatInterval) {
      return;
    }
    _lastPlaybackHeartbeat = now;
    AnalyticsService.playbackHeartbeat(player);
  }

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
        case 'analyticsHeartbeat':
          // Dedicated keep-alive ping from the Java (Torbox/Real-Debrid/stream)
          // TV player, which has no periodic progress channel of its own.
          AnalyticsService.playbackHeartbeat('torbox_tv');
          return null;
        case 'saveIptvSeriesAudio':
          // The native TV player captured the user's audio-language pick for an
          // Xtream series — persist it under the same per-series key the phone/
          // desktop player uses, so both surfaces remember the same choice.
          if (call.arguments is Map) {
            final m = call.arguments as Map;
            final key = m['seriesKey'] as String?;
            final lang = m['lang'] as String?;
            if (key != null &&
                key.isNotEmpty &&
                lang != null &&
                lang.isNotEmpty) {
              await StorageService.setIptvSeriesAudioLanguage(key, lang);
            }
          }
          return null;
        case 'saveSubtitleAppearance':
          final raw = call.arguments;
          if (raw is! Map) {
            throw PlatformException(
              code: 'invalid_subtitle_appearance',
              message: 'Expected a subtitle appearance map',
            );
          }
          final values = Map<String, dynamic>.from(raw);
          await _saveSubtitleAppearance(values);
          return true;
        case 'torboxPlaybackFinished':
        case 'realDebridPlaybackFinished':
        case 'streamPlaybackFinished':
          _lastPlaybackHeartbeat =
              null; // reset so the next watch isn't throttled
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
          // Keep the analytics session alive during native TV playback (the
          // Flutter UI is backgrounded, so this progress ping is our activity
          // signal). The native player pings even while paused, so gate on the
          // isPlaying flag to match the Dart/Java players; throttled so we emit
          // at most one heartbeat per interval.
          if (call.arguments is Map &&
              (call.arguments as Map)['isPlaying'] == true) {
            _maybeSendPlaybackHeartbeat('android_tv');
          }
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
        case 'requestMoreTorrentSources':
          // Series source tabs: the native player asked for the not-yet-
          // fetched category. A null/failed fetch throws so the native side
          // keeps its "Load more" button up for a retry.
          debugPrint(
            'AndroidTvPlayerBridge: requestMoreTorrentSources received - args: ${call.arguments}',
          );
          final moreProvider = _moreSourcesProvider;
          if (moreProvider == null) {
            debugPrint(
              'AndroidTvPlayerBridge: no more-sources provider registered',
            );
            return null;
          }
          final moreArgs = call.arguments;
          final mode = (moreArgs is Map) ? moreArgs['mode'] as String? : null;
          if (mode == null || mode.isEmpty) return null;
          final curSeason = (moreArgs as Map)['season'] as int?;
          final curEpisode = moreArgs['episode'] as int?;
          try {
            final result = await moreProvider(
              mode,
              season: curSeason,
              episode: curEpisode,
            );
            debugPrint(
              'AndroidTvPlayerBridge: more-sources fetch returned: '
              '${result != null ? "${(result['stremioSources'] as List?)?.length} sources" : "null"}',
            );
            if (result == null) {
              throw PlatformException(
                code: 'more_sources_failed',
                message: 'Source search failed',
              );
            }
            return result;
          } on PlatformException {
            rethrow;
          } catch (e, stack) {
            debugPrint(
              'AndroidTvPlayerBridge: more-sources provider error $e\n$stack',
            );
            throw PlatformException(
              code: 'more_sources_failed',
              message: e.toString(),
            );
          }
        case 'requestAddonTorrentSources':
          // Per-addon fetch from the source browser. A null/failed episode
          // fetch throws so the native Fetch row flips to its failed/retry
          // state; the pack mode is best-effort and returns the current list.
          final addonProvider = _addonSourcesProvider;
          if (addonProvider == null) return null;
          final addonArgs = call.arguments;
          if (addonArgs is! Map) return null;
          final addonIds = (addonArgs['addonIds'] as List?)
              ?.whereType<String>()
              .toList();
          final addonMode = addonArgs['mode'] as String?;
          if (addonIds == null || addonIds.isEmpty || addonMode == null) {
            return null;
          }
          try {
            final result = await addonProvider(
              addonIds,
              addonMode,
              season: addonArgs['season'] as int?,
              episode: addonArgs['episode'] as int?,
            );
            if (result == null) {
              throw PlatformException(
                code: 'addon_fetch_failed',
                message: 'Addon fetch failed',
              );
            }
            return result;
          } on PlatformException {
            rethrow;
          } catch (e) {
            throw PlatformException(
              code: 'addon_fetch_failed',
              message: e.toString(),
            );
          }
        case 'requestEpisodeFetch':
          // Episode-guide fetch: an absent episode was clicked (or next/prev
          // crossed the pack boundary). Null/failed throws so native can fall
          // back or surface the failure.
          final episodeFetchProvider = _episodeFetchProvider;
          if (episodeFetchProvider == null) return null;
          final episodeFetchArgs = call.arguments;
          if (episodeFetchArgs is! Map) return null;
          final fetchSeason = episodeFetchArgs['season'] as int?;
          final fetchEpisode = episodeFetchArgs['episode'] as int?;
          if (fetchSeason == null || fetchEpisode == null) return null;
          try {
            final result = await episodeFetchProvider(fetchSeason, fetchEpisode);
            if (result == null) {
              throw PlatformException(
                code: 'episode_fetch_failed',
                message: 'No playable source found',
              );
            }
            return result;
          } on PlatformException {
            rethrow;
          } catch (e) {
            throw PlatformException(
              code: 'episode_fetch_failed',
              message: e.toString(),
            );
          }
        case 'torrentPlaybackFinished':
          _lastPlaybackHeartbeat =
              null; // reset so the next watch isn't throttled
          final finishedTorrent = _torrentFinishedCallback;
          _torrentProgressCallback = null;
          _torrentFinishedCallback = null;
          _torrentStreamProvider = null;
          _movieMetadataProvider = null;
          _stremioSourceResolver = null;
          _sourcePlaylistResolver = null;
          _moreSourcesProvider = null;
          _addonSourcesProvider = null;
          _episodeFetchProvider = null;
          _stremioTvGuideDataProvider = null;
          _stremioTvChannelSwitchProvider = null;
          _stremioTvNextProvider = null;
          _iptvBrowseProvider = null;
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
        case 'requestIptvStreamUrls':
          // Native IPTV player hit a Stremio-addon channel (its `url` is a
          // stremio-tv:// key, not a stream). Resolve the ordered candidate
          // list; the native side tries them serially. Stateless — no
          // per-session provider, the resolver service holds the caches.
          final iptvArgs = call.arguments;
          String? iptvChannelUrl;
          String? iptvChannelName;
          if (iptvArgs is Map) {
            final raw = iptvArgs['channelUrl'];
            if (raw is String) iptvChannelUrl = raw;
            final rawName = iptvArgs['channelName'];
            if (rawName is String && rawName.trim().isNotEmpty) {
              iptvChannelName = rawName.trim();
            }
          }
          if (iptvChannelUrl == null ||
              !StremioIptvService.isStremioChannelUrl(iptvChannelUrl)) {
            return null;
          }
          try {
            // A native zap is an explicit play intent — bypass a cached-empty
            // resolve. An empty answer ships a specific toast message
            // (addon unreachable vs. no streams) for the native side to show.
            final candidates = await StremioIptvService.instance
                .resolveCandidates(iptvChannelUrl, refreshIfEmpty: true);
            return {
              'candidates': [
                for (final c in candidates) {'url': c.url, 'label': c.label},
              ],
              if (candidates.isEmpty)
                'message': StremioIptvService.instance.unplayableMessage(
                  iptvChannelUrl,
                  iptvChannelName ?? 'This channel',
                ),
            };
          } catch (e) {
            throw PlatformException(
              code: 'iptv_stream_resolve_failed',
              message: e.toString(),
            );
          }
        case 'requestIptvEpg':
          // Native IPTV player wants guide data for a channel. Stateless like
          // requestIptvStreamUrls: credentials are recovered from the channel
          // URL itself and the EPG service holds the caches, so nothing needs
          // registering per session. Answers {now, next, schedule?}; empty map
          // when the channel has no guide data.
          final epgArgs = call.arguments;
          String? epgChannelUrl;
          var includeSchedule = false;
          if (epgArgs is Map) {
            final raw = epgArgs['channelUrl'];
            if (raw is String) epgChannelUrl = raw;
            includeSchedule = epgArgs['includeSchedule'] == true;
          }
          if (epgChannelUrl == null ||
              !IptvEpgService.isEpgCapableUrl(epgChannelUrl)) {
            return <String, dynamic>{};
          }
          try {
            final nowNext = await IptvEpgService.instance.nowNext(
              epgChannelUrl,
            );
            return <String, dynamic>{
              if (nowNext.now != null) 'now': nowNext.now!.toBridgeMap(),
              if (nowNext.next != null) 'next': nowNext.next!.toBridgeMap(),
              if (includeSchedule)
                'schedule': [
                  for (final p in await IptvEpgService.instance.schedule(
                    epgChannelUrl,
                  ))
                    p.toBridgeMap(),
                ],
            };
          } catch (e) {
            debugPrint('AndroidTvPlayerBridge: requestIptvEpg failed: $e');
            return <String, dynamic>{};
          }
        case 'requestIptvBrowse':
          final provider = _iptvBrowseProvider;
          final rawArgs = call.arguments;
          if (provider == null || rawArgs is! Map) return null;
          try {
            return await provider(Map<String, dynamic>.from(rawArgs));
          } catch (e, stack) {
            debugPrint(
              'AndroidTvPlayerBridge: IPTV browse provider failed: $e\n$stack',
            );
            throw PlatformException(
              code: 'iptv_browse_failed',
              message: e.toString(),
            );
          }
        case 'requestIptvCatchup':
          final args = call.arguments;
          if (args is! Map) return null;
          final channelUrl = args['channelUrl'] as String?;
          final startMs = (args['startMs'] as num?)?.toInt();
          if (channelUrl == null || startMs == null) return null;
          try {
            final schedule = await IptvEpgService.instance.schedule(channelUrl);
            EpgProgramme? programme;
            for (final item in schedule) {
              if (item.start.millisecondsSinceEpoch == startMs) {
                programme = item;
                break;
              }
            }
            if (programme == null ||
                !programme.hasArchive ||
                !programme.stop.isBefore(DateTime.now())) {
              return null;
            }
            final url = await IptvEpgService.instance.catchupUrl(
              channelUrl,
              programme,
            );
            if (url == null) return null;
            final headers = <String, String>{};
            final rawHeaders = args['httpHeaders'];
            if (rawHeaders is Map) {
              rawHeaders.forEach((key, value) {
                if (key is String && value != null) {
                  headers[key] = value.toString();
                }
              });
            }
            await StorageService.recordIptvWatch(
              url,
              channelName: programme.title,
              logoUrl: args['logoUrl'] as String?,
              group: args['channelName'] as String?,
              playlistId: args['playlistId'] as String?,
              httpHeaders: headers.isEmpty ? null : headers,
            );
            final resumePositions = await StorageService.getIptvResumePositions(
              [url],
            );
            return <String, dynamic>{
              'url': url,
              'title': programme.title,
              'resumePositionMs': resumePositions[url] ?? 0,
            };
          } catch (e) {
            debugPrint('AndroidTvPlayerBridge: requestIptvCatchup failed: $e');
            return null;
          }
        case 'recordIptvWatch':
          final watchArgs = call.arguments;
          if (watchArgs is! Map) return false;
          final url = watchArgs['url'] as String?;
          if (url == null || url.isEmpty) return false;
          final headers = <String, String>{};
          final rawHeaders = watchArgs['httpHeaders'];
          if (rawHeaders is Map) {
            rawHeaders.forEach((key, value) {
              if (key is String && value != null) {
                headers[key] = value.toString();
              }
            });
          }
          await StorageService.recordIptvWatch(
            url,
            channelName: watchArgs['name'] as String?,
            logoUrl: watchArgs['logoUrl'] as String?,
            group: watchArgs['group'] as String?,
            playlistId: watchArgs['sourceId'] as String?,
            httpHeaders: headers.isEmpty ? null : headers,
            seriesId: watchArgs['seriesId'] as String?,
            seriesName: watchArgs['seriesName'] as String?,
            season: (watchArgs['season'] as num?)?.toInt(),
            episode: (watchArgs['episode'] as num?)?.toInt(),
            hasNextEpisode: watchArgs['hasNextEpisode'] as bool?,
          );
          return true;
        // Startup-channel memory. Fired by the native player once a LIVE
        // channel has been playing for its settle window — deliberately not
        // routed through 'recordIptvWatch' above, which feeds the on-demand
        // Continue Watching shelf and skips live entirely.
        case 'noteIptvLiveChannel':
          final liveArgs = call.arguments;
          if (liveArgs is! Map) return false;
          final url = liveArgs['url'] as String?;
          final name = liveArgs['name'] as String?;
          if (url == null || url.isEmpty || name == null) return false;
          await StorageService.setIptvLastLiveChannel(
            url,
            name: name,
            playlistId: liveArgs['sourceId'] as String?,
            channelNumber: (liveArgs['channelNumber'] as num?)?.toInt(),
            group: liveArgs['group'] as String?,
            logoUrl: liveArgs['logoUrl'] as String?,
            httpHeaders: _iptvHeadersFromArgs(liveArgs['httpHeaders']),
          );
          return true;
        case 'setIptvFavorite':
          final favoriteArgs = call.arguments;
          if (favoriteArgs is! Map) return false;
          final url = favoriteArgs['url'] as String?;
          final isFavorite = favoriteArgs['isFavorite'] == true;
          if (url == null || url.isEmpty) return false;
          await StorageService.setIptvChannelFavorited(
            url,
            isFavorite,
            channelName: favoriteArgs['name'] as String?,
            logoUrl: favoriteArgs['logoUrl'] as String?,
            group: favoriteArgs['group'] as String?,
            playlistId: favoriteArgs['sourceId'] as String?,
            channelNumber: (favoriteArgs['channelNumber'] as num?)?.toInt(),
            contentType: favoriteArgs['contentType'] as String?,
            duration: (favoriteArgs['duration'] as num?)?.toInt(),
            httpHeaders: _iptvHeadersFromArgs(favoriteArgs['httpHeaders']),
          );
          return true;
        case 'setIptvChannelInList':
          final listArgs = call.arguments;
          if (listArgs is! Map) return false;
          final url = listArgs['url'] as String?;
          final listId = listArgs['listId'] as String?;
          if (url == null || url.isEmpty) return false;
          if (listId == null || listId.isEmpty) return false;
          await StorageService.setIptvChannelInList(
            listId,
            url,
            listArgs['inList'] == true,
            channelName: listArgs['name'] as String?,
            logoUrl: listArgs['logoUrl'] as String?,
            group: listArgs['group'] as String?,
            playlistId: listArgs['sourceId'] as String?,
            channelNumber: (listArgs['channelNumber'] as num?)?.toInt(),
            contentType: listArgs['contentType'] as String?,
            duration: (listArgs['duration'] as num?)?.toInt(),
            httpHeaders: _iptvHeadersFromArgs(listArgs['httpHeaders']),
          );
          return true;
        case 'getIptvChannelListMembership':
          // Fetched per channel when the native picker opens rather than
          // shipped with every channel at launch — that payload is already
          // capped for size.
          final membershipArgs = call.arguments;
          final url = membershipArgs is Map
              ? membershipArgs['url'] as String?
              : null;
          if (url == null || url.isEmpty) return <String>[];
          return (await StorageService.getIptvListsForChannel(url)).toList();
        case 'reportIptvStreamResult':
          // Feedback from the native serial ladder: cache the URL that
          // actually played, or drop the stale candidate list when every
          // candidate died so the next attempt re-resolves fresh links.
          final reportArgs = call.arguments;
          if (reportArgs is Map) {
            final channelUrl = reportArgs['channelUrl'];
            final playedUrl = reportArgs['url'];
            final success = reportArgs['success'] == true;
            if (channelUrl is String &&
                StremioIptvService.isStremioChannelUrl(channelUrl)) {
              if (success && playedUrl is String && playedUrl.isNotEmpty) {
                StremioIptvService.instance.markWinner(channelUrl, playedUrl);
              } else if (!success) {
                StremioIptvService.instance.invalidate(channelUrl);
              }
            }
          }
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
          final pendingGuide = _pendingGuideEpisodes;
          if ((pending != null && pending.isNotEmpty) ||
              pendingImdb != null ||
              (pendingGuide != null && pendingGuide.isNotEmpty)) {
            debugPrint(
              'TVMazeUpdate: Sending ${pending?.length ?? 0} pending metadata updates, imdbId=$pendingImdb',
            );
            // Send the pending updates via broadcast (including IMDB ID for subtitles)
            await updateEpisodeMetadata(
              pending ?? [],
              imdbId: pendingImdb,
              guideEpisodes: pendingGuide,
            );
            // Clear pending updates after sending
            _pendingMetadataUpdates = null;
            _pendingImdbId = null;
            _pendingGuideEpisodes = null;
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
    _iptvBrowseProvider = null;
  }

  static void clearStreamProvider() {
    _streamNextProvider = null;
    _channelSwitchProvider = null;
    _channelByIdSwitchProvider = null;
    _playbackFinishedCallback = null;
    _stremioTvNextProvider = null;
    _iptvBrowseProvider = null;
  }

  static Future<bool> launchTorrentPlayback({
    required Map<String, dynamic> payload,
    AndroidTvProgressCallback? onProgress,
    PlaybackFinishedCallback? onFinished,
    TorrentStreamProvider? onRequestStream,
    MovieMetadataProvider? onRequestMovieMetadata,
    Future<String?> Function(int)? onResolveStremioSource,
    Future<List<Map<String, dynamic>>?> Function(int)? onResolveSourcePlaylist,
    Future<Map<String, dynamic>?> Function(String, {int? season, int? episode})?
    onRequestMoreSources,
    Future<Map<String, dynamic>?> Function(
      List<String> addonIds,
      String mode, {
      int? season,
      int? episode,
    })?
    onRequestAddonSources,
    Future<Map<String, dynamic>?> Function(int season, int episode)?
    onRequestEpisodeFetch,
    Future<Map<String, dynamic>?> Function(List<String>)?
    onRequestStremioTvGuideData,
    Future<Map<String, dynamic>?> Function(String)?
    onRequestStremioTvChannelSwitch,
    StremioTvNextProvider? onRequestStremioTvNext,
    Future<Map<String, dynamic>?> Function(Map<String, dynamic>)?
    onRequestIptvBrowse,
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
    _moreSourcesProvider = onRequestMoreSources;
    _addonSourcesProvider = onRequestAddonSources;
    _episodeFetchProvider = onRequestEpisodeFetch;
    _stremioTvGuideDataProvider = onRequestStremioTvGuideData;
    _stremioTvChannelSwitchProvider = onRequestStremioTvChannelSwitch;
    _stremioTvNextProvider = onRequestStremioTvNext;
    _iptvBrowseProvider = onRequestIptvBrowse;

    // Clear any stale pending metadata from previous sessions
    _pendingMetadataUpdates = null;
    _pendingImdbId = null;
    _pendingGuideEpisodes = null;

    try {
      // Get custom font info for Android TV player
      final fontInfo = await _getCustomFontInfo();

      // Add font info to payload
      final payloadWithFont = Map<String, dynamic>.from(payload);
      if (fontInfo['customFontPath'] != null) {
        payloadWithFont['customFontPath'] = fontInfo['customFontPath'];
        payloadWithFont['customFontName'] = fontInfo['customFontName'];
      }

      // Network & Buffering presets (Settings → Playback) ride every launch.
      // Sent only when non-standard; the activity treats absence exactly as
      // 'standard' = stock configuration untouched. A prefs failure must not
      // block a launch — tuning is strictly optional.
      try {
        final patience = await StorageService.getNetworkConnectPatience();
        final buffer = await StorageService.getNetworkBufferSize();
        if (patience != 'standard') {
          payloadWithFont['networkPatience'] = patience;
        }
        if (buffer != 'standard') {
          payloadWithFont['networkBuffer'] = buffer;
        }
      } catch (e) {
        debugPrint('AndroidTvPlayerBridge: network tuning read failed: $e');
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
    _moreSourcesProvider = null;
    _addonSourcesProvider = null;
    _episodeFetchProvider = null;
    _stremioTvGuideDataProvider = null;
    _stremioTvChannelSwitchProvider = null;
    _stremioTvNextProvider = null;
    _iptvBrowseProvider = null;
    return false;
  }

  /// Store pending metadata updates to be sent when the activity requests them
  /// The sessionId parameter ensures updates from stale sessions are discarded
  /// The imdbId parameter stores discovered IMDB ID for Stremio subtitle fetching
  static void storePendingMetadataUpdates(
    List<Map<String, dynamic>> updates, {
    String? sessionId,
    String? imdbId,
    List<Map<String, dynamic>>? guideEpisodes,
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
    _pendingGuideEpisodes = guideEpisodes;
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
    List<Map<String, dynamic>>? guideEpisodes,
  }) async {
    if (!Platform.isAndroid) {
      return false;
    }
    if (metadataUpdates.isEmpty &&
        imdbId == null &&
        (guideEpisodes == null || guideEpisodes.isEmpty)) {
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
        {
          'updates': metadataUpdates,
          if (imdbId != null) 'imdbId': imdbId,
          if (guideEpisodes != null && guideEpisodes.isNotEmpty)
            'guideEpisodes': guideEpisodes,
        },
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
