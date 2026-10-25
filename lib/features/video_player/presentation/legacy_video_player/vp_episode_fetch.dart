import 'dart:async';

import 'package:debrify/features/video_player/application/vp_format.dart';
import 'package:debrify/features/video_player/models/vp_season_episode_selection.dart';
import 'package:debrify/models/playlist_entry.dart';
import 'package:debrify/models/series_playlist.dart';
import 'package:debrify/models/source_playlist_resolver.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/series_source_fetcher.dart';
import 'package:debrify/services/source_selection_diagnostics.dart';
import 'package:debrify/utils/episode_playback_request.dart';
import 'package:debrify/utils/series_parser.dart';
import 'package:flutter/material.dart';

abstract interface class VpEpisodeFetchHost {
  set augmentedSources(List<Torrent>? v);
  bool get canFetchEpisodes;
  int get currentSourceIndex;
  set currentSourceIndex(int v);
  Duration get duration;
  List<Torrent>? get effectiveSources;
  bool get episodeFetchInProgress;
  set episodeFetchInProgress(bool v);
  int get episodeNavigationGeneration;
  set episodeNavigationGeneration(int v);
  set isAutoAdvancing(bool v);
  bool get isPlaying;
  bool get isTransitioning;
  set isTransitioning(bool v);
  int get playlistIdentityToken;
  Duration get position;
  int get showShuffleGeneration;
  bool get sleepStopLatched;
  bool get validationGateActive;
  void setManualSelectionMode({bool allowResume = false});
  bool get mounted;
  BuildContext get context;
  void setState(VoidCallback fn);
  SeriesSourceFetcher? get seriesSourceFetcher;
  SourcePlaylistResolve? get resolveSourceToPlaylist;
  String get title;
  Future<bool> switchToSourcePlaylist(
    int sourceIndex,
    List<PlaylistEntry> newPlaylist, {
    int? targetSeason,
    int? targetEpisode,
    bool validateExplicitSelection = false,
    bool suppressResume = false,
    EpisodePlaybackRequest? request,
  });
  VpSeasonEpisodeSelection? currentSeasonEpisodeForIdentity();
}

class VpEpisodeFetch {
  VpEpisodeFetch(this._host);
  final VpEpisodeFetchHost _host;

  bool packCoversSeason(Torrent t, int season) {
    switch (t.coverageType) {
      case 'completeSeries':
        final start = t.startSeason;
        final end = t.endSeason;
        if (start == null && end == null) return true;
        return season >= (start ?? 1) && season <= (end ?? season);
      case 'multiSeasonPack':
        final start = t.startSeason;
        final end = t.endSeason;
        return start != null && end != null && season >= start && season <= end;
      case 'seasonPack':
        return t.seasonNumber == season;
      default:
        return false;
    }
  }

  /// Quick-play an episode that isn't in the current playlist, WITHOUT
  /// leaving the player: try packs already in the source list, then an
  /// episode-targeted fetch, then a fresh pack search — switching to the
  /// first candidate that resolves and actually contains the episode.
  Future<EpisodePlaybackOutcome> fetchAndPlayEpisode(
    int season,
    int episode, {
    int? shuffleGeneration,
    bool autoAdvance = false,
    EpisodePlaybackRequest? request,
  }) async {
    if (!_host.canFetchEpisodes || _host.episodeFetchInProgress) {
      // A next/prev press may have raised the transition curtain already;
      // never leave it up when the request can't run.
      if (_host.mounted && _host.isTransitioning) {
        _host.setState(() => _host.isTransitioning = false);
      }
      return EpisodePlaybackOutcome.cancelled;
    }
    if (request == null) _host.episodeNavigationGeneration++;
    request ??= EpisodePlaybackRequest(
      currentIdentity: () => _host.playlistIdentityToken,
      currentNavigation: () => _host.episodeNavigationGeneration,
      isActive: () =>
          _host.mounted &&
          (!autoAdvance || !_host.sleepStopLatched) &&
          (shuffleGeneration == null ||
              shuffleGeneration == _host.showShuffleGeneration),
    );
    final fetcher = _host.seriesSourceFetcher!;
    _host.episodeFetchInProgress = true;
    final messenger = ScaffoldMessenger.of(_host.context);
    final label = 'S${vpPad2(season)}E${vpPad2(episode)}';
    messenger.showSnackBar(
      SnackBar(
        content: Text('Fetching $label…'),
        duration: const Duration(seconds: 2),
      ),
    );
    try {
      final pinned = fetcher.pinnedDirectCandidates;
      if (pinned != null) {
        await for (final candidate in pinned(
          season,
          episode,
          onPreferredMissing: () {
            if (!request!.isCurrent || !_host.mounted) return;
            messenger.showSnackBar(
              const SnackBar(
                content: Text(
                  'Your previous source is unavailable for this episode. Trying other sources.',
                ),
              ),
            );
          },
        )) {
          if (!request.isCurrent) {
            return EpisodePlaybackOutcome.cancelled;
          }
          final sources = List<Torrent>.of(_host.effectiveSources ?? const []);
          final index = sources.length;
          sources.add(candidate);
          _host.setState(() => _host.augmentedSources = sources);
          final outcome = await tryEpisodeCandidate(
            index,
            candidate,
            season,
            episode,
            request,
            shuffleGeneration: shuffleGeneration,
            autoAdvance: autoAdvance,
          );
          if (outcome != EpisodePlaybackOutcome.unavailable) return outcome;
          if (!request.isCurrent) {
            return EpisodePlaybackOutcome.cancelled;
          }
        }
      }

      // 1. Try what's already in the source list: exact-episode singles and
      // packs covering the season (often already unlocked on the account).
      final existing = List<Torrent>.of(
        _host.effectiveSources ?? const <Torrent>[],
      );
      var attempts = 0;
      for (var i = 0; i < existing.length && attempts < 4; i++) {
        if (i == _host.currentSourceIndex) continue;
        final t = existing[i];
        if (t.streamType == StreamType.externalUrl) continue;
        final info = SeriesParser.parseFilename(t.displayTitle);
        final matchesEpisode = info.season == season && info.episode == episode;
        final coversAsPack =
            t.streamType == StreamType.torrent && packCoversSeason(t, season);
        if (!matchesEpisode && !coversAsPack) continue;
        attempts++;
        final outcome = await tryEpisodeCandidate(
          i,
          t,
          season,
          episode,
          request,
          shuffleGeneration: shuffleGeneration,
          autoAdvance: autoAdvance,
        );
        if (outcome != EpisodePlaybackOutcome.unavailable) return outcome;
        if (!request.isCurrent) {
          return EpisodePlaybackOutcome.cancelled;
        }
      }

      // 2. Episode-targeted fetch (direct links resolve instantly).
      List<Torrent>? fetched;
      try {
        fetched = await fetcher.fetch(
          SeriesSourceFetcher.modeEpisodes,
          season: season,
          episode: episode,
        );
      } catch (_) {
        fetched = null;
      }
      if (!request.isCurrent) {
        return EpisodePlaybackOutcome.cancelled;
      }
      if (fetched != null && fetched.isNotEmpty) {
        final base = _host.effectiveSources ?? const <Torrent>[];
        final merged = SeriesSourceFetcher.mergeSources(base, fetched);
        _host.setState(() => _host.augmentedSources = merged);
        attempts = 0;
        for (var i = base.length; i < merged.length && attempts < 5; i++) {
          final t = merged[i];
          if (t.streamType == StreamType.externalUrl) continue;
          attempts++;
          final outcome = await tryEpisodeCandidate(
            i,
            t,
            season,
            episode,
            request,
            shuffleGeneration: shuffleGeneration,
            autoAdvance: autoAdvance,
          );
          if (outcome != EpisodePlaybackOutcome.unavailable) return outcome;
          if (!request.isCurrent) {
            return EpisodePlaybackOutcome.cancelled;
          }
        }
      }

      // 3. Last resort: a fresh pack search for that season.
      List<Torrent>? packs;
      try {
        packs = await fetcher.fetch(
          SeriesSourceFetcher.modePacks,
          season: season,
          episode: episode,
        );
      } catch (_) {
        packs = null;
      }
      if (!request.isCurrent) {
        return EpisodePlaybackOutcome.cancelled;
      }
      if (packs != null && packs.isNotEmpty) {
        final base = _host.effectiveSources ?? const <Torrent>[];
        final merged = SeriesSourceFetcher.mergeSources(base, packs);
        _host.setState(() => _host.augmentedSources = merged);
        attempts = 0;
        for (var i = base.length; i < merged.length && attempts < 3; i++) {
          final t = merged[i];
          if (t.streamType != StreamType.torrent) continue;
          // Pack-search results are season-targeted; only skip ones whose
          // detected coverage positively excludes the season.
          if (t.coverageType != null && !packCoversSeason(t, season)) {
            continue;
          }
          attempts++;
          final outcome = await tryEpisodeCandidate(
            i,
            t,
            season,
            episode,
            request,
            shuffleGeneration: shuffleGeneration,
            autoAdvance: autoAdvance,
          );
          if (outcome != EpisodePlaybackOutcome.unavailable) return outcome;
          if (!request.isCurrent) {
            return EpisodePlaybackOutcome.cancelled;
          }
        }
      }

      if (request.isCurrent) {
        // A next/prev press raised the transition curtain before calling in
        // here — drop it, or a failed fetch leaves the screen black.
        if (_host.isTransitioning) {
          _host.setState(() => _host.isTransitioning = false);
        }
        messenger.showSnackBar(
          SnackBar(content: Text('No playable source found for $label')),
        );
      }
      return EpisodePlaybackOutcome.unavailable;
    } finally {
      _host.episodeFetchInProgress = false;
    }
  }

  /// Resolve one candidate and switch to it when it actually contains the
  /// target episode, reporting failure independently of playlist replacement.
  Future<EpisodePlaybackOutcome> tryEpisodeCandidate(
    int sourceIndex,
    Torrent t,
    int season,
    int episode,
    EpisodePlaybackRequest request, {
    int? shuffleGeneration,
    bool autoAdvance = false,
  }) async {
    logSourceSelection(
      'next_episode_candidate',
      source: t,
      index: sourceIndex,
      season: season,
      episode: episode,
      player: 'mpv',
    );
    if (!await _host.seriesSourceFetcher!.allowsCandidate(t)) {
      return EpisodePlaybackOutcome.unavailable;
    }
    if (!request.isCurrent) return EpisodePlaybackOutcome.cancelled;
    List<PlaylistEntry>? playlist;
    try {
      playlist = await _host.resolveSourceToPlaylist!(
        t,
        canContinue: () => request.isCurrent,
      );
    } catch (_) {
      playlist = null;
    }
    if (!request.isCurrent) return EpisodePlaybackOutcome.cancelled;
    if (playlist == null || playlist.isEmpty) {
      logSourceSelection(
        'next_episode_candidate_rejected',
        source: t,
        index: sourceIndex,
        season: season,
        episode: episode,
        player: 'mpv',
        reason: 'no_playlist',
      );
      return EpisodePlaybackOutcome.unavailable;
    }
    if (playlist.length == 1) {
      final info = SeriesParser.parseFilename(playlist.first.title);
      if (info.season == null || info.episode == null) {
        // Unparseable single stream: stamp the target identity into the
        // title so parsing (titles, scrobbling, the guide) stays coherent.
        playlist = [
          playlist.first.copyWithTitle(
            'S${vpPad2(season)}E${vpPad2(episode)} ${playlist.first.title}',
          ),
        ];
      } else if (info.season != season || info.episode != episode) {
        return EpisodePlaybackOutcome
            .unavailable; // resolves to a DIFFERENT episode — wrong result
      }
    } else {
      final sp = SeriesPlaylist.fromPlaylistEntries(
        playlist,
        collectionTitle: _host.title,
        forceSeries: true,
      );
      if (sp.findOriginalIndexBySeasonEpisode(season, episode) < 0) {
        return EpisodePlaybackOutcome
            .unavailable; // pack without the target — try the next candidate
      }
    }
    _host.setManualSelectionMode(allowResume: true);
    _host.isAutoAdvancing = autoAdvance;
    final resolvedPlaylist = playlist;
    final outcome = await request.attempt(
      () => _host.switchToSourcePlaylist(
        sourceIndex,
        resolvedPlaylist,
        targetSeason: season,
        targetEpisode: episode,
        suppressResume: autoAdvance || shuffleGeneration != null,
        request: request,
      ),
    );
    if (outcome == EpisodePlaybackOutcome.committed &&
        _host.mounted &&
        request.isCurrent) {
      final retained = SeriesSourceFetcher.retainForEpisode(
        _host.effectiveSources ?? const <Torrent>[],
        season,
        episode,
      );
      var retainedIndex = retained.indexWhere((source) => identical(source, t));
      retainedIndex = retainedIndex >= 0
          ? retainedIndex
          : retained.indexWhere(
              (source) =>
                  SeriesSourceFetcher.sourceKey(source) ==
                  SeriesSourceFetcher.sourceKey(t),
            );
      if (retainedIndex >= 0) {
        _host.setState(() {
          _host.augmentedSources = retained;
          _host.currentSourceIndex = retainedIndex;
        });
      }
    }
    logSourceSelection(
      'next_episode_candidate_outcome',
      source: t,
      index: sourceIndex,
      season: season,
      episode: episode,
      player: 'mpv',
      reason: outcome.name,
    );
    return outcome;
  }

  void prepareNextDirectEpisode() {
    final fetcher = _host.seriesSourceFetcher;
    final sources = _host.effectiveSources;
    if (fetcher == null ||
        _host.validationGateActive ||
        !_host.isPlaying ||
        _host.isTransitioning ||
        sources == null ||
        _host.currentSourceIndex < 0 ||
        _host.currentSourceIndex >= sources.length) {
      return;
    }
    final current = _host.currentSeasonEpisodeForIdentity();
    if (current == null) return;
    unawaited(
      fetcher.prepareFromProgress(
        source: sources[_host.currentSourceIndex],
        season: current.season,
        episode: current.episode,
        positionMs: _host.position.inMilliseconds,
        durationMs: _host.duration.inMilliseconds,
      ),
    );
  }
}
