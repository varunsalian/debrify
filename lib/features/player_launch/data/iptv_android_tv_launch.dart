import 'package:debrify/features/player_launch/models/video_player_launch_args.dart';
import 'package:debrify/services/android_tv_player_bridge.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/storage/iptv_audio_storage.dart';
import 'package:debrify/services/storage/iptv_favorites_storage.dart';
import 'package:debrify/services/storage/iptv_history_storage.dart';
import 'package:debrify/services/storage/video_resume_storage.dart';
import 'package:flutter/foundation.dart';

final class IptvAndroidTvLaunch {
  /// Launch IPTV playlist on Android TV using existing launchTorrentPlayback bridge
  static Future<bool> launchIptvOnAndroidTv(VideoPlayerLaunchArgs args) async {
    try {
      final channels = args.iptvChannels!;
      final startIndex = args.iptvStartIndex ?? 0;

      // The source's FULL category list (provider order). Only fall back to
      // deriving from the windowed channels when the caller didn't supply it —
      // deriving only ever saw the ~1500-channel window, so the picker showed a
      // truncated set of categories.
      var categories = args.iptvCategories ?? const <String>[];
      if (categories.isEmpty) {
        final categorySet = <String>{};
        for (final c in channels) {
          if (c.group != null && c.group!.isNotEmpty) {
            categorySet.add(c.group!);
          }
        }
        categories = categorySet.toList()..sort();
      }

      // Saved positions for the on-demand items in this payload, so a movie
      // picks up where it was left off — and so does one the user zaps to
      // from the in-player guide. Attached alongside each channel rather than
      // baked into IptvChannel.toJson(): a resume point is session state, not
      // a property of the channel.
      final resumePositions = await IptvHistoryStorage.getIptvResumePositions([
        for (final c in channels)
          if (!c.isLive) c.url,
      ]);
      final favoriteUrls = await IptvFavoritesStorage.getIptvFavoriteChannelUrls();

      // Per-series audio memory: Xtream series episodes carry a series identity
      // (series_id + series_playlist_id) in their attributes. The native player
      // has no per-series audio store of its own — resolve the remembered
      // language here and hand it the same `<playlistId>::<seriesId>` key so a
      // native audio pick round-trips back to the shared store.
      String? seriesAudioKey;
      String? preferredAudioLang;
      for (final c in channels) {
        final sid = c.attributes['series_id'];
        if (sid != null && sid.isNotEmpty) {
          final pid = c.attributes['series_playlist_id'] ?? '';
          seriesAudioKey = '$pid::$sid';
          break;
        }
      }
      if (seriesAudioKey != null) {
        preferredAudioLang = await IptvAudioStorage.getIptvSeriesAudioLanguage(
          seriesAudioKey,
        );
      }

      final activeChannel = channels.isEmpty
          ? null
          : channels[startIndex.clamp(0, channels.length - 1)];
      final inferredContentType = activeChannel == null
          ? 'live'
          : activeChannel.attributes['series_id']?.isNotEmpty == true
          ? 'episodes'
          : activeChannel.isLive
          ? 'live'
          : 'vod';

      final payload = <String, dynamic>{
        'mode': 'iptv',
        'initialUrl': args.videoUrl,
        'title': args.title,
        'subtitle': args.subtitle ?? 'IPTV',
        'startIndex': startIndex,
        if (args.iptvSourceId != null) 'sourceId': args.iptvSourceId,
        if (args.iptvSourceName != null) 'sourceName': args.iptvSourceName,
        if (args.iptvSelectedCategory != null) 'selectedCategory': args.iptvSelectedCategory,
        'contentType': args.iptvContentType ?? inferredContentType,
        if (args.iptvSources != null) 'sources': args.iptvSources,
        if (args.iptvLists != null) 'lists': args.iptvLists,
        'channels': [
          for (final c in channels)
            {
              ...c.toJson(),
              if (c.attributes['source_playlist_id']?.isNotEmpty == true)
                'sourceId': c.attributes['source_playlist_id']
              else if (c.attributes['series_playlist_id']?.isNotEmpty == true)
                'sourceId': c.attributes['series_playlist_id'],
              if (c.attributes['series_id']?.isNotEmpty == true)
                'seriesId': c.attributes['series_id'],
              if (c.attributes['series_name']?.isNotEmpty == true)
                'seriesName': c.attributes['series_name'],
              if (int.tryParse(c.attributes['season'] ?? '') != null)
                'season': int.parse(c.attributes['season']!),
              if (int.tryParse(c.attributes['episode'] ?? '') != null)
                'episode': int.parse(c.attributes['episode']!),
              if (c.attributes['has_next_episode'] != null)
                'hasNextEpisode': c.attributes['has_next_episode'] == 'true',
              if (c.attributes['tv_archive'] != null) 'tvArchive': c.attributes['tv_archive'],
              if (int.tryParse(c.attributes['tv_archive_duration'] ?? '') != null)
                'tvArchiveDuration': int.parse(
                  c.attributes['tv_archive_duration']!,
                ),
              'isFavorite': favoriteUrls.contains(c.url),
              if ((resumePositions[c.url] ?? 0) > 0) 'resumePositionMs': resumePositions[c.url],
            },
        ],
        'categories': categories,
        if (seriesAudioKey != null) 'seriesAudioKey': seriesAudioKey,
        if (preferredAudioLang != null) 'preferredAudioLang': preferredAudioLang,
      };

      // Hide auto-launch overlay before launching player
      MainPageBridge.notifyPlayerLaunching();

      final launched = await AndroidTvPlayerBridge.launchTorrentPlayback(
        payload: payload,
        onProgress: IptvAndroidTvLaunch.handleIptvProgressUpdate,
        onFinished: () async {
          debugPrint('VideoPlayerLauncher: IPTV Android TV playback finished');
        },
        onRequestIptvBrowse: args.iptvBrowseProvider,
      );

      return launched;
    } catch (e) {
      debugPrint('VideoPlayerLauncher: IPTV Android TV launch failed: $e');
      if (e is NativePlayerSettingsUnavailable) rethrow;
      return false;
    }
  }

  /// Persist the native TV player's position for an on-demand IPTV item.
  ///
  /// Writes to the same `video_resume_v1` store, under the same key (the
  /// stream URL), that the in-app player already uses for IPTV — so a movie
  /// started on the phone and finished on the TV is one entry, not two.
  ///
  /// Live channels are ignored: the Kotlin side reports an unset duration for
  /// them, and a resume point on a live stream is meaningless anyway.
  static Future<void> handleIptvProgressUpdate(
    Map<String, dynamic> progress,
  ) async {
    try {
      final url = progress['url'] as String?;
      if (url == null || url.isEmpty) return;

      final positionMs = (progress['positionMs'] as num?)?.toInt() ?? 0;
      final durationMs = (progress['durationMs'] as num?)?.toInt() ?? 0;
      if (durationMs <= 0 || positionMs <= 0) return;

      await VideoResumeStorage.upsertVideoResume(url, {
        'positionMs': positionMs,
        'durationMs': durationMs,
        'speed': (progress['speed'] as num?)?.toDouble() ?? 1.0,
        'aspect': (progress['aspect'] as String?) ?? 'contain',
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      }, sourceId: progress['sourceId'] as String?);
    } catch (e) {
      debugPrint('VideoPlayerLauncher: IPTV progress save failed: $e');
    }
  }
}
