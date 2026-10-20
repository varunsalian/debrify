import 'dart:async';
import 'dart:math' as math;

import 'package:debrify/features/video_player/presentation/vp_random_choice_tile.dart';
import 'package:debrify/models/playlist_entry.dart';
import 'package:debrify/models/playlist_view_mode.dart';
import 'package:debrify/models/series_playlist.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:debrify/services/series_source_fetcher.dart';
import 'package:debrify/utils/episode_playback_request.dart';
import 'package:debrify/utils/show_shuffle.dart';
import 'package:flutter/material.dart';

abstract interface class VpShuffleHost {
  List<PlaylistEntry>? get activePlaylist;
  bool get canFetchEpisodes;
  bool get continuousShuffleEnabled;
  set continuousShuffleEnabled(bool v);
  int get currentIndex;
  String? get currentSeriesImdbId;
  bool get episodeFetchInProgress;
  Future<void>? get episodeMetadataReady;
  set episodeMetadataReady(Future<void>? v);
  int get episodeNavigationGeneration;
  Timer? get hideTimer;
  set isAutoAdvancing(bool v);
  bool get isTransitioning;
  set isTransitioning(bool v);
  int get playlistIdentityToken;
  math.Random get random;
  SeriesPlaylist? get seriesPlaylist;
  int get showShuffleGeneration;
  set showShuffleGeneration(int v);
  bool get sleepStopLatched;
  SeriesPlaylist? get syntheticGuidePlaylist;
  void scheduleAutoHide();
  ({int? season, int? episode}) traktSeasonEpisode();
  Map<String, dynamic>? constructPlaylistItemData();
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
  List<int> getMainGroupIndices(List<PlaylistEntry> entries);
  Future<void> preloadEpisodeInfo();
  bool get mounted;
  BuildContext get context;
  void setState(VoidCallback fn);
  SeriesSourceFetcher? get seriesSourceFetcher;
  PlaylistViewMode? get viewMode;
  void openPlayerMenuQuick(PlayerMenuSection section);
  (SeriesPlaylist, List<PlaylistEntry>)? buildSyntheticGuide();
  Future<EpisodePlaybackOutcome> fetchAndPlayEpisode(
    int season,
    int episode, {
    int? shuffleGeneration,
    bool autoAdvance = false,
    EpisodePlaybackRequest? request,
  });
}

class VpShuffle {
  VpShuffle(this._host);
  final VpShuffleHost _host;

  final List<int> shuffleBag = [];
  final ShowShuffle showShuffle = ShowShuffle();
  bool showShuffleInProgress = false;
  int? activeShowShuffleGeneration;

  Future<void> showRandomPlaybackMenu() async {
    final entries = _host.activePlaylist ?? const [];
    if (entries.isEmpty && !_host.canFetchEpisodes) {
      ScaffoldMessenger.of(_host.context).showSnackBar(
        const SnackBar(content: Text('No playlist items available')),
      );
      return;
    }

    if (kUnifiedPlayerMenuEnabled) {
      _host.openPlayerMenuQuick(PlayerMenuSection.shuffle);
      return;
    }

    _host.hideTimer?.cancel();
    final choice = await showDialog<String>(
      context: _host.context,
      builder: (context) {
        final shuffleLabel = _host.continuousShuffleEnabled
            ? 'Turn Off Continuous Shuffle'
            : 'Shuffle Continuously';
        final shuffleSubtitle = _host.continuousShuffleEnabled
            ? 'Return to normal ordered playback'
            : 'Keep picking random items after each episode ends';

        return AlertDialog(
          backgroundColor: const Color(0xFF141824),
          title: const Text(
            'Shuffle Playback',
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              VpRandomChoiceTile(
                icon: Icons.shuffle_rounded,
                title: 'Play Random Once',
                subtitle: 'Pick one random item, then resume normal order',
                onTap: () => Navigator.of(context).pop('once'),
              ),
              const SizedBox(height: 8),
              VpRandomChoiceTile(
                icon: _host.continuousShuffleEnabled
                    ? Icons.check_circle_rounded
                    : Icons.all_inclusive_rounded,
                title: shuffleLabel,
                subtitle: shuffleSubtitle,
                onTap: () => Navigator.of(context).pop('continuous'),
              ),
            ],
          ),
        );
      },
    );

    if (!_host.mounted) return;
    _host.scheduleAutoHide();

    if (choice == 'once') {
      await playRandomOnce(disableContinuousShuffle: true);
    } else if (choice == 'continuous') {
      await toggleContinuousShuffle();
    }
  }

  Future<void> toggleContinuousShuffle() async {
    if (_host.continuousShuffleEnabled) {
      _host.setState(() {
        _host.continuousShuffleEnabled = false;
        shuffleBag.clear();
        showShuffle.clear();
        _host.showShuffleGeneration++;
      });
      ScaffoldMessenger.of(
        _host.context,
      ).showSnackBar(const SnackBar(content: Text('Continuous shuffle off')));
    } else {
      _host.setState(() {
        _host.continuousShuffleEnabled = true;
        shuffleBag.clear();
        showShuffle.clear();
        _host.showShuffleGeneration++;
      });
      ScaffoldMessenger.of(
        _host.context,
      ).showSnackBar(const SnackBar(content: Text('Continuous shuffle on')));
      await playRandomOnce(disableContinuousShuffle: false);
    }
  }

  Future<void> playRandomOnce({required bool disableContinuousShuffle}) async {
    if (disableContinuousShuffle) {
      if (_host.continuousShuffleEnabled) {
        _host.setState(() {
          _host.continuousShuffleEnabled = false;
          shuffleBag.clear();
          showShuffle.clear();
          _host.showShuffleGeneration++;
        });
      } else {
        shuffleBag.clear();
        showShuffle.clear();
        _host.showShuffleGeneration++;
      }
    }

    if (await playShowShuffle()) return;
    final nextIndex = pickShuffleIndex();
    if (nextIndex == null) return;
    _host.setManualSelectionMode();
    await _host.loadPlaylistIndex(nextIndex, autoplay: true);
  }

  /// Returns true when show-wide shuffle owns this request, including failure.
  /// Never fall through to ordered playback after exhausting random candidates.
  Future<bool> playShowShuffle({bool autoAdvance = false}) async {
    if (!_host.canFetchEpisodes) return false;
    final generation = _host.showShuffleGeneration;
    final navigation = _host.episodeNavigationGeneration;
    while (showShuffleInProgress || _host.episodeFetchInProgress) {
      if (showShuffleInProgress && activeShowShuffleGeneration == generation) {
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
      if (!_host.mounted ||
          generation != _host.showShuffleGeneration ||
          navigation != _host.episodeNavigationGeneration) {
        return true;
      }
    }
    showShuffleInProgress = true;
    activeShowShuffleGeneration = generation;
    bool requestIsCurrent() =>
        _host.mounted &&
        generation == _host.showShuffleGeneration &&
        (!autoAdvance || !_host.sleepStopLatched);
    final request = EpisodePlaybackRequest(
      currentIdentity: () => _host.playlistIdentityToken,
      currentNavigation: () => _host.episodeNavigationGeneration,
      isActive: requestIsCurrent,
    );
    try {
      final customInventory =
          _host.seriesSourceFetcher?.loadCustomEpisodeInventory;
      final List<Map<String, dynamic>> full;
      if (customInventory != null) {
        full = await customInventory();
      } else {
        await (_host.episodeMetadataReady ??= _host.preloadEpisodeInfo());
        if (!request.isCurrent) return true;
        if (_host.seriesPlaylist == null) {
          final synthetic = _host.buildSyntheticGuide();
          if (synthetic != null && synthetic.$1.fullTvmazeEpisodes.isEmpty) {
            await synthetic.$1.fetchEpisodeInfo(
              playlistItem: _host.constructPlaylistItemData(),
              imdbId: _host.currentSeriesImdbId,
            );
          }
        }
        if (!request.isCurrent) return true;
        full = _host.seriesPlaylist?.fullTvmazeEpisodes.isNotEmpty == true
            ? _host.seriesPlaylist!.fullTvmazeEpisodes
            : (_host.syntheticGuidePlaylist?.fullTvmazeEpisodes ??
                  const <Map<String, dynamic>>[]);
      }
      if (!request.isCurrent) return true;
      if (full.isEmpty && customInventory == null) return false;
      final eligible = full
          .where((m) => isShuffleEpisodeEligible(m))
          .map((m) => (m['season'] as int, m['number'] as int))
          .toList();
      final attempted = <ShuffleEpisode>{};
      for (var attempt = 0; attempt < 3; attempt++) {
        final current = _host.traktSeasonEpisode();
        final target = showShuffle.pick(
          eligible,
          current.season == null || current.episode == null
              ? null
              : (current.season!, current.episode!),
          excluded: attempted,
        );
        if (target == null) break;
        attempted.add(target);
        final index =
            _host.seriesPlaylist?.findOriginalIndexBySeasonEpisode(
              target.$1,
              target.$2,
            ) ??
            -1;
        if (index >= 0) {
          // EOF loads must retain sleep-stop and start-from-zero semantics,
          // including when URL resolution outlasts the manual-selection timer.
          _host.isAutoAdvancing = autoAdvance;
          if (!autoAdvance) _host.setManualSelectionMode();
          final outcome = await request.attempt(
            () => _host.loadPlaylistIndex(
              index,
              autoplay: true,
              suppressResume: true,
              request: request,
            ),
          );
          if (outcome != EpisodePlaybackOutcome.unavailable) return true;
          // A pack entry can have an unavailable URL. Try another source for
          // this episode before moving on to the next random candidate.
        }
        final outcome = await _host.fetchAndPlayEpisode(
          target.$1,
          target.$2,
          shuffleGeneration: generation,
          autoAdvance: autoAdvance,
          request: request,
        );
        if (outcome != EpisodePlaybackOutcome.unavailable) return true;
      }
      if (_host.mounted) {
        _host.setState(() => _host.isTransitioning = false);
        ScaffoldMessenger.of(_host.context).showSnackBar(
          const SnackBar(
            content: Text('No other playable episode found for shuffle'),
          ),
        );
      }
      return true;
    } catch (error) {
      debugPrint('Show shuffle failed: $error');
      if (_host.mounted) {
        _host.setState(() => _host.isTransitioning = false);
        ScaffoldMessenger.of(_host.context).showSnackBar(
          const SnackBar(content: Text('Could not load a random episode')),
        );
      }
      return true;
    } finally {
      showShuffleInProgress = false;
      activeShowShuffleGeneration = null;
      if (_host.mounted &&
          generation != _host.showShuffleGeneration &&
          _host.isTransitioning) {
        _host.setState(() => _host.isTransitioning = false);
      }
    }
  }

  List<int> shuffleEligibleIndices() {
    final entries = _host.activePlaylist;
    if (entries == null || entries.isEmpty) return const [];

    final seriesPlaylist = _host.seriesPlaylist;
    if (seriesPlaylist != null && seriesPlaylist.isSeries) {
      final indices = seriesPlaylist.allEpisodes
          .map((episode) => episode.originalIndex)
          .where((index) => index >= 0 && index < entries.length)
          .toSet()
          .toList();
      if (indices.isNotEmpty) return indices;
    }

    if (_host.viewMode == PlaylistViewMode.raw ||
        _host.viewMode == PlaylistViewMode.sorted) {
      return List<int>.generate(entries.length, (index) => index);
    }

    final mainIndices = _host
        .getMainGroupIndices(entries)
        .where((index) => index >= 0 && index < entries.length)
        .toList();
    if (mainIndices.isNotEmpty) return mainIndices;

    return List<int>.generate(entries.length, (index) => index);
  }

  int? pickShuffleIndex() {
    final eligible = shuffleEligibleIndices();
    if (eligible.isEmpty) return null;
    if (eligible.length == 1) return eligible.first;

    final eligibleSet = eligible.toSet();
    shuffleBag.removeWhere(
      (index) => !eligibleSet.contains(index) || index == _host.currentIndex,
    );

    if (shuffleBag.isEmpty) {
      shuffleBag.addAll(
        eligible.where((index) => index != _host.currentIndex).toList()
          ..shuffle(_host.random),
      );
    }

    if (shuffleBag.isEmpty) return null;
    return shuffleBag.removeLast();
  }
}
