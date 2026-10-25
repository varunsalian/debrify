import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:debrify/models/custom_series_identity.dart';
import 'package:debrify/models/series_playlist.dart';
import 'package:debrify/services/skip_segment_service.dart';
import 'package:debrify/services/storage/skip_segments_storage.dart';
import 'package:debrify/screens/video_player/services/playback_ui_clock.dart';
import 'package:debrify/screens/video_player/services/skip_segment_ui_controller.dart';

abstract interface class VpSkipSegmentHost {
  bool get mounted;
  void setState(VoidCallback fn);
  String? get effectiveContentImdbId;
  String? get effectiveContentType;
  int? get effectiveContentSeason;
  int? get effectiveContentEpisode;
  bool get isTransitioning;
  Duration get duration;
  Duration get position;
  set position(Duration v);
  SeriesPlaylist? get seriesPlaylist;
  SeriesEpisode? findSeriesEpisodeForCurrentIndex(SeriesPlaylist sp);
  ({int? season, int? episode}) traktSeasonEpisode();
  bool get playerCreated;
  PlaybackUiClockController get playbackUiClock;
  mk.Player get player;
  SkipSegmentUiController get activeSkipSegmentUi;
  void traktScrobbleSeek(Duration target);
  void simklScrobbleSeek(Duration target);
  void mdblistScrobbleSeek(Duration target);
}

class VpSkipSegmentController {
  VpSkipSegmentController(this._host);
  final VpSkipSegmentHost _host;

  // Community intro/outro markers for the currently playing series episode.
  // The request key includes the stream duration because providers may use it
  // to distinguish releases, and timestamps are always validated against it.
  bool skipSegmentSettingsLoaded = false;
  bool skipSegmentsEnabled = false;
  String skipSegmentProviderId = SkipSegmentProviders.auto;
  SkipSegmentProvider? skipSegmentProvider;
  SkipSegments skipSegments = SkipSegments.empty;
  String? loadedSkipSegmentsKey;
  String? loadingSkipSegmentsKey;
  int skipSegmentsFetchGeneration = 0;
  final Map<String, SkipSegments> skipSegmentsCache = <String, SkipSegments>{};

  /// Whether _position/_duration describe the item currently selected, rather
  /// than the one being switched away from. The native player's equivalent is
  /// `hasEverBeenReady`.
  ///
  /// Cleared when a playlist switch starts and set again on the first real
  /// duration for the incoming media. It cannot stick: media_kit's `open()`
  /// pushes Duration.zero to the duration stream unconditionally, so a fresh
  /// duration always follows — even when the new episode runs exactly as long
  /// as the old one.
  bool skipSegmentsMediaReady = true;

  Future<void> loadSkipSegmentSettings() async {
    final values = await Future.wait<Object>([
      SkipSegmentsStorage.getSkipSegmentsEnabled(),
      SkipSegmentsStorage.getSkipSegmentProvider(),
    ]);
    if (!_host.mounted) return;

    final enabled = values[0] as bool;
    final storedProvider = values[1] as String;
    final providerId = SkipSegmentProviders.isAvailable(storedProvider)
        ? storedProvider
        : SkipSegmentProviders.auto;

    skipSegmentProvider?.close();
    skipSegmentProvider = enabled
        ? SkipSegmentProviders.create(providerId)
        : null;
    skipSegmentsEnabled = enabled;
    skipSegmentProviderId = providerId;
    skipSegmentSettingsLoaded = true;
    syncSkipSegmentsForCurrentContent();
  }

  ({String imdbId, int season, int episode, Duration duration, String key})?
  currentSkipSegmentRequest() {
    if (CustomSeriesIdentity.isCustom(_host.effectiveContentImdbId)) {
      return null;
    }
    // Two stale-media windows, both of which would judge the incoming item
    // against the outgoing one's clock:
    //
    // * _skipSegmentsMediaReady covers a playlist switch. _loadPlaylistIndex
    //   points _currentIndex at the new episode and only then saves resume and
    //   resolves the stream URL — a network round trip for debrid/PikPak
    //   links. Through all of that _position/_duration still describe the
    //   outgoing episode, and that position is usually deep enough to land
    //   inside a segment, so the button flashes on the moment next-episode is
    //   pressed. It also asks the provider for the new episode at the old
    //   episode's duration, which can select or validate the wrong release.
    // * _isTransitioning covers an IPTV zap / source switch, where the key
    //   flips before the incoming stream opens (the same window _saveResume
    //   guards against).
    if (!skipSegmentSettingsLoaded ||
        !skipSegmentsEnabled ||
        !skipSegmentsMediaReady ||
        _host.isTransitioning ||
        _host.duration <= Duration.zero) {
      return null;
    }

    final seriesPlaylist = _host.seriesPlaylist;
    final isSeries =
        _host.effectiveContentType == 'series' ||
        seriesPlaylist?.isSeries == true;
    if (!isSeries) return null;

    var imdbId = _host.effectiveContentImdbId?.trim();
    if (imdbId == null || !RegExp(r'^tt\d+$').hasMatch(imdbId)) {
      imdbId = seriesPlaylist?.imdbId?.trim();
    }
    if (imdbId == null || !RegExp(r'^tt\d+$').hasMatch(imdbId)) return null;

    int? season;
    int? episode;
    if (seriesPlaylist?.isSeries == true) {
      final current = _host.findSeriesEpisodeForCurrentIndex(seriesPlaylist!);
      season = current?.seriesInfo.season;
      episode = current?.seriesInfo.episode;
    }
    season ??= _host.effectiveContentSeason;
    episode ??= _host.effectiveContentEpisode;
    if (season == null || episode == null) {
      final parsed = _host.traktSeasonEpisode();
      season ??= parsed.season;
      episode ??= parsed.episode;
    }
    if (season == null || episode == null || season < 0 || episode < 1) {
      return null;
    }

    final durationSeconds = _host.duration.inSeconds;
    final key =
        '$skipSegmentProviderId:$imdbId:$season:$episode:$durationSeconds';
    return (
      imdbId: imdbId,
      season: season,
      episode: episode,
      duration: _host.duration,
      key: key,
    );
  }

  void syncSkipSegmentsForCurrentContent() {
    final request = currentSkipSegmentRequest();
    final provider = skipSegmentProvider;
    if (request == null || provider == null) return;
    if (loadedSkipSegmentsKey == request.key ||
        loadingSkipSegmentsKey == request.key) {
      return;
    }

    if (skipSegmentsCache.containsKey(request.key)) {
      final cached = skipSegmentsCache[request.key]!;
      if (_host.mounted) {
        _host.setState(() {
          skipSegments = cached;
          loadedSkipSegmentsKey = request.key;
        });
        syncActiveSkipSegmentUi();
      }
      return;
    }

    final generation = ++skipSegmentsFetchGeneration;
    loadingSkipSegmentsKey = request.key;
    provider
        .fetch(
          imdbId: request.imdbId,
          season: request.season,
          episode: request.episode,
          duration: request.duration,
        )
        .then((segments) {
          skipSegmentsCache[request.key] = segments;
          if (!_host.mounted || generation != skipSegmentsFetchGeneration) {
            return;
          }
          if (currentSkipSegmentRequest()?.key != request.key) return;
          _host.setState(() {
            skipSegments = segments;
            loadedSkipSegmentsKey = request.key;
          });
          syncActiveSkipSegmentUi();
        })
        .catchError((Object error) {
          // Missing skip data must never affect playback. Cache the miss for
          // this session so an offline API cannot be retried on every position
          // tick.
          skipSegmentsCache[request.key] = SkipSegments.empty;
          debugPrint(
            'SkipSegments: ${provider.displayName} fetch failed: $error',
          );
          if (!_host.mounted || generation != skipSegmentsFetchGeneration) {
            return;
          }
          if (currentSkipSegmentRequest()?.key != request.key) return;
          _host.setState(() {
            skipSegments = SkipSegments.empty;
            loadedSkipSegmentsKey = request.key;
          });
          syncActiveSkipSegmentUi();
        })
        .whenComplete(() {
          if (loadingSkipSegmentsKey == request.key) {
            loadingSkipSegmentsKey = null;
          }
        });
  }

  /// Forget the outgoing item's skip segments when switching playlist entries,
  /// and stop reading its clock until the incoming one opens. The native TV
  /// player does the same in playItem.
  ///
  /// The fetch cache survives on purpose: it's keyed per episode, so going
  /// back to one already looked up is instant.
  void resetSkipSegmentState() {
    skipSegmentsFetchGeneration++;
    loadingSkipSegmentsKey = null;
    loadedSkipSegmentsKey = null;
    skipSegments = SkipSegments.empty;
    skipSegmentsMediaReady = false;
    _host.activeSkipSegmentUi.clear();
  }

  SkipSegment? get activeSkipSegment {
    final request = currentSkipSegmentRequest();
    if (request == null || request.key != loadedSkipSegmentsKey) return null;
    return skipSegments.segmentAt(_host.position);
  }

  void syncActiveSkipSegmentUi() {
    _host.activeSkipSegmentUi.update(activeSkipSegment);
  }

  void skipActiveSegment() {
    final segment = activeSkipSegment;
    if (segment == null || !_host.playerCreated) return;
    final target =
        _host.duration > Duration.zero && segment.end > _host.duration
        ? _host.duration
        : segment.end;
    _host.position = target;
    _host.playbackUiClock.updatePosition(target, immediate: true);
    syncActiveSkipSegmentUi();
    unawaited(_host.player.seek(target));
    _host.traktScrobbleSeek(target);
    _host.simklScrobbleSeek(target);
    _host.mdblistScrobbleSeek(target);
    HapticFeedback.selectionClick();
  }
}
