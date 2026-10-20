import 'dart:async';

import 'package:debrify/models/playlist_entry.dart';
import 'package:debrify/models/playlist_view_mode.dart';
import 'package:debrify/models/series_playlist.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/next_episode_service.dart';
import 'package:debrify/services/series_source_fetcher.dart';
import 'package:debrify/utils/episode_playback_request.dart';
import 'package:flutter/material.dart';

abstract interface class VpEpisodeAdjacentHost {
  List<PlaylistEntry>? get activePlaylist;
  bool get canFetchEpisodes;
  int get currentIndex;
  bool get episodeFetchInProgress;
  int get episodeNavigationGeneration;
  set isTransitioning(bool v);
  int get playlistIdentityToken;
  SeriesPlaylist? get seriesPlaylist;
  bool get sleepStopLatched;
  SeriesPlaylist? get syntheticGuidePlaylist;
  int get tvScrubGeneration;
  set tvScrubGeneration(int v);
  void clearBufferingIndicator();
  void tvAbandonScrub();
  ({int? season, int? episode}) traktSeasonEpisode();
  Future<bool> loadPlaylistIndex(
    int index, {
    bool autoplay = false,
    EpisodePlaybackRequest? request,
    bool skipInitialSave = false,
    bool preferLocalResume = false,
    bool suppressResume = false,
    Torrent? manualValidationSource,
    int? manualValidationSourceIndex,
  });
  void setManualSelectionMode({bool allowResume = false});
  bool get mounted;
  void setState(VoidCallback fn);
  Future<Map<String, String>?> Function()? get requestMagicNext;
  String? get contentType;
  String? get contentImdbId;
  int? get contentSeason;
  SeriesSourceFetcher? get seriesSourceFetcher;
  PlaylistViewMode? get viewMode;
  Future<EpisodePlaybackOutcome> fetchAndPlayEpisode(
    int season,
    int episode, {
    int? shuffleGeneration,
    bool autoAdvance = false,
    EpisodePlaybackRequest? request,
  });
}

class VpEpisodeAdjacent {
  VpEpisodeAdjacent(this._host);
  final VpEpisodeAdjacentHost _host;

  /// Find the next logical episode index for auto-advance
  int findNextEpisodeIndex() {
    final seriesPlaylist = _host.seriesPlaylist;

    if (seriesPlaylist == null || !seriesPlaylist.isSeries) {
      // Raw mode OR Sorted mode: sequential navigation through all files
      // In sorted mode, files are already pre-sorted A-Z, so sequential = alphabetical
      if (_host.viewMode == PlaylistViewMode.raw ||
          _host.viewMode == PlaylistViewMode.sorted) {
        if (_host.activePlaylist == null || _host.activePlaylist!.isEmpty)
          return -1;
        if (_host.currentIndex + 1 < _host.activePlaylist!.length) {
          return _host.currentIndex + 1;
        }
        return -1;
      }

      // Collection mode (view mode not specified): navigate within Main group only
      if (_host.activePlaylist == null || _host.activePlaylist!.isEmpty)
        return -1;
      final indices = getMainGroupIndices(_host.activePlaylist!);
      if (indices.isEmpty) return -1;

      final currentPos = indices.indexOf(_host.currentIndex);
      if (currentPos == -1) {
        return indices.first;
      }

      if (currentPos + 1 < indices.length) {
        return indices[currentPos + 1];
      }

      return -1;
    }

    // Series mode: existing logic
    try {
      // Find current episode in the sorted allEpisodes list
      final currentEpisode = seriesPlaylist.allEpisodes.firstWhere(
        (episode) => episode.originalIndex == _host.currentIndex,
        orElse: () {
          if (seriesPlaylist.allEpisodes.isEmpty) {
            throw StateError('allEpisodes is empty');
          }
          return seriesPlaylist.allEpisodes.first;
        },
      );

      // Find the index of current episode in allEpisodes
      final currentEpisodeIndex = seriesPlaylist.allEpisodes.indexOf(
        currentEpisode,
      );

      if (currentEpisodeIndex == -1 ||
          currentEpisodeIndex + 1 >= seriesPlaylist.allEpisodes.length) {
        return -1;
      }

      // Get the next episode from the sorted list
      final nextEpisode = seriesPlaylist.allEpisodes[currentEpisodeIndex + 1];
      return nextEpisode.originalIndex;
    } catch (e) {
      return -1;
    }
  }

  /// Compute the Main group indices for movie collections (size >= 70% of largest)
  List<int> getMainGroupIndices(List<PlaylistEntry> entries) {
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
      final ya = yearOf(a);
      final yb = yearOf(b);
      if (ya != null && yb != null) return ya.compareTo(yb); // older first
      return sizeOf(b).compareTo(sizeOf(a));
    });
    return main;
  }

  /// Find the previous logical episode index
  int findPreviousEpisodeIndex() {
    final seriesPlaylist = _host.seriesPlaylist;

    if (seriesPlaylist == null || !seriesPlaylist.isSeries) {
      // Raw mode OR Sorted mode: sequential navigation through all files
      // In sorted mode, files are already pre-sorted A-Z, so sequential = alphabetical
      if (_host.viewMode == PlaylistViewMode.raw ||
          _host.viewMode == PlaylistViewMode.sorted) {
        if (_host.activePlaylist == null || _host.activePlaylist!.isEmpty)
          return -1;
        if (_host.currentIndex - 1 >= 0) {
          return _host.currentIndex - 1;
        }
        return -1;
      }

      // Collection mode (view mode not specified): navigate within Main group only
      if (_host.activePlaylist == null || _host.activePlaylist!.isEmpty)
        return -1;
      final indices = getMainGroupIndices(_host.activePlaylist!);
      if (indices.isEmpty) return -1;

      final currentPos = indices.indexOf(_host.currentIndex);
      if (currentPos == -1) {
        return indices.first;
      }

      if (currentPos - 1 >= 0) {
        return indices[currentPos - 1];
      }

      return -1;
    }

    // Series mode: existing logic
    try {
      // Find current episode in the sorted allEpisodes list
      final currentEpisode = seriesPlaylist.allEpisodes.firstWhere(
        (episode) => episode.originalIndex == _host.currentIndex,
        orElse: () {
          if (seriesPlaylist.allEpisodes.isEmpty) {
            throw StateError('allEpisodes is empty');
          }
          return seriesPlaylist.allEpisodes.first;
        },
      );

      // Find the index of current episode in allEpisodes
      final currentEpisodeIndex = seriesPlaylist.allEpisodes.indexOf(
        currentEpisode,
      );

      if (currentEpisodeIndex <= 0) {
        return -1;
      }

      // Get the previous episode from the sorted list
      final previousEpisode =
          seriesPlaylist.allEpisodes[currentEpisodeIndex - 1];
      return previousEpisode.originalIndex;
    } catch (e) {
      return -1;
    }
  }

  /// Check if there's a next episode available
  bool hasNextEpisode() {
    if (findNextEpisodeIndex() != -1) return true;
    if (_host.canFetchEpisodes) {
      final se = _host.traktSeasonEpisode();
      if (se.season != null && se.episode != null) return true;
    }
    // Series content may have a next episode discoverable via Stremio metadata.
    // Requires episode info from widget params or a parsed series playlist.
    if (_host.requestMagicNext == null &&
        _host.contentType == 'series' &&
        _host.contentImdbId != null &&
        (_host.contentSeason != null || _host.seriesPlaylist != null)) {
      return true;
    }
    return false;
  }

  /// Check if there's a previous episode available
  bool hasPreviousEpisode() {
    if (findPreviousEpisodeIndex() != -1) return true;
    // Beyond the pack's start: a previous episode may exist show-wide and be
    // fetchable in-player (metadata-list adjacency decides at press time).
    if (_host.canFetchEpisodes) {
      final se = _host.traktSeasonEpisode();
      if (se.season != null && se.episode != null) {
        return adjacentEpisode(se.season!, se.episode!, -1) != null ||
            (_host.seriesSourceFetcher?.resolveAdjacentEpisode != null &&
                (se.season! > 1 || se.episode! > 1));
      }
    }
    return false;
  }

  /// Shared manual/EOF path beyond the current pack. A handled fetch, including
  /// cancellation or failure, stays in-player rather than relaunching it.
  Future<bool> fetchNextEpisodeInPlayer({bool autoAdvance = false}) async {
    if (!_host.canFetchEpisodes) return false;
    if (_host.episodeFetchInProgress) return true;
    final identity = _host.playlistIdentityToken;
    final navigation = _host.episodeNavigationGeneration;
    bool stale() =>
        !_host.mounted ||
        identity != _host.playlistIdentityToken ||
        navigation != _host.episodeNavigationGeneration ||
        (autoAdvance && _host.sleepStopLatched);
    if (stale()) return true;
    final se = _host.traktSeasonEpisode();
    if (se.season == null || se.episode == null) return false;
    var next = adjacentEpisode(se.season!, se.episode!, 1);
    if (next == null) {
      final resolved = await resolveAdjacentWithCachedGuide(
        se.season!,
        se.episode!,
        1,
      );
      if (resolved != null) next = (resolved.season, resolved.episode);
    }
    if (next == null &&
        _host.seriesSourceFetcher?.resolveAdjacentEpisode == null &&
        _host.contentImdbId != null) {
      final episode = await NextEpisodeService.findNextEpisode(
        _host.contentImdbId!,
        se.season!,
        se.episode!,
      );
      if (episode != null) next = (episode.season, episode.episode);
    }
    if (stale()) return true;
    if (next == null) return false;
    debugPrint(
      'Player: Next episode S${next.$1}E${next.$2} in-player autoAdvance=$autoAdvance',
    );
    await _host.fetchAndPlayEpisode(next.$1, next.$2, autoAdvance: autoAdvance);
    return true;
  }

  /// Navigate to previous episode
  Future<void> goToPreviousEpisode() async {
    // Show black screen during transition to hide previous frame
    _host.clearBufferingIndicator();
    _host.setState(() {
      _host.isTransitioning = true;
      _host.tvScrubGeneration++;
      _host.tvAbandonScrub();
    });

    final previousIndex = findPreviousEpisodeIndex();
    if (previousIndex != -1) {
      // Mark this as a manual episode selection
      _host.setManualSelectionMode();
      await _host.loadPlaylistIndex(previousIndex, autoplay: true);
    } else {
      // Beyond the pack's start: fetch the previous episode in-player.
      if (_host.canFetchEpisodes) {
        final se = _host.traktSeasonEpisode();
        var prev = (se.season != null && se.episode != null)
            ? adjacentEpisode(se.season!, se.episode!, -1)
            : null;
        if (prev == null && se.season != null && se.episode != null) {
          final resolved = await resolveAdjacentWithCachedGuide(
            se.season!,
            se.episode!,
            -1,
          );
          if (resolved != null) prev = (resolved.season, resolved.episode);
        }
        if (prev != null) {
          await _host.fetchAndPlayEpisode(prev.$1, prev.$2);
          return;
        }
      }
      // Clear transition state if no previous episode found
      if (_host.mounted) {
        _host.setState(() {
          _host.isTransitioning = false;
        });
      }
    }
  }

  /// Resolve with the origin first; only an unavailable guide permits fallback.
  Future<({int season, int episode})?> resolveAdjacentWithCachedGuide(
    int season,
    int episode,
    int direction,
  ) async {
    final resolver = _host.seriesSourceFetcher?.resolveAdjacentEpisode;
    if (resolver == null) return null;
    return resolveAdjacentWithGuideFallback(
      resolver: resolver,
      season: season,
      episode: episode,
      direction: direction,
      cachedGuide: () {
        final target = adjacentEpisode(
          season,
          episode,
          direction,
          allowResolverFallback: true,
        );
        return target == null ? null : (season: target.$1, episode: target.$2);
      },
    );
  }

  (int, int)? adjacentEpisode(
    int season,
    int episode,
    int direction, {
    bool allowResolverFallback = false,
  }) {
    // Custom catalogs own their episode order, even after TVMaze fills the guide.
    if (!allowResolverFallback &&
        _host.seriesSourceFetcher?.resolveAdjacentEpisode != null)
      return null;
    final full = _host.seriesPlaylist?.fullTvmazeEpisodes.isNotEmpty == true
        ? _host.seriesPlaylist!.fullTvmazeEpisodes
        : (_host.syntheticGuidePlaylist?.fullTvmazeEpisodes ??
              const <Map<String, dynamic>>[]);
    final target = cachedGuideAdjacentEpisode(full, season, episode, direction);
    return target == null ? null : (target.season, target.episode);
  }
}
