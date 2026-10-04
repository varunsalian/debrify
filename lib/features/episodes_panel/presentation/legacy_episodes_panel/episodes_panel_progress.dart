import 'dart:async';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_auth.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_deps.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_services.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_view_state.dart';
import 'package:debrify/models/media_identity.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/diagnostic_log.dart';
import 'package:debrify/services/storage/episode_resume_storage.dart';
import 'package:debrify/services/tracking_source_policy.dart';
import 'package:debrify/utils/episode_progress_merge.dart';
import 'package:debrify/utils/series_rewatch.dart';
import 'package:flutter/material.dart';

class EpisodesPanelProgress {
  final EpisodesPanelDeps _deps;
  EpisodesPanelProgress(this._deps);
  EpisodesPanelViewState get _s => _deps.parts.viewState;
  EpisodesPanelAuth get _a => _deps.parts.auth;
  EpisodesPanelServices get _sv => _deps.parts.services;
  bool get mounted => _deps.mounted();

  Map<String, double> episodeWatchProgress = {};

  TrackingSourcePolicy trackingPolicy = const TrackingSourcePolicy(
    scrobbleTargets: <TrackingSource>{
      TrackingSource.local,
      TrackingSource.trakt,
      TrackingSource.simkl,
      TrackingSource.mdblist,
    },
    progressSource: WatchProgressSource.smart,
    homeTickSources: <TrackingSource>{
      TrackingSource.local,
      TrackingSource.trakt,
      TrackingSource.simkl,
      TrackingSource.mdblist,
    },
  );

  Map<String, int> episodeMdblistRatings = {};

  /// Load episode watch progress for the selected show.
  ///
  /// Merges two sources so both local (in-app, offline) and Trakt-tracked
  /// watches are reflected — the old inline Trakt episode view only read Trakt,
  /// the old catalog view only read local storage; a series opened from
  /// Discover→Trakt needs both. All three sources key episodes as
  /// `'<season>-<episode>'`, so they merge directly.
  Future<void> loadEpisodeWatchProgress(
    StremioMeta show,
    int generation,
  ) async {
    final policy = (await TrackingSourcePolicy.load()).forContent(
      show.progressId,
    );
    if (!mounted || generation != _s.episodeModeGeneration) return;
    trackingPolicy = policy;
    // Direct-source mode: the host owns progress (URL-keyed player positions
    // mapped to S-E), and none of the IMDb-keyed sources below can know these
    // episodes.
    final progressLoader = _deps.watchProgressLoader();
    if (progressLoader != null) {
      try {
        final map = await progressLoader();
        if (!mounted || generation != _s.episodeModeGeneration) return;
        logEpisodeProgress(
          map,
          {'direct_local': map},
          {'direct_local': 'loaded'},
        );
        _deps.setState(() => episodeWatchProgress = map);
      } catch (e) {
        debugPrint('EpisodesPanel: direct progress fetch failed: $e');
      }
      return;
    }

    final imdbId = show.progressId;
    if (imdbId == null) return;

    // Ticks and bars BOTH follow the Progress source (2026-08-27 decision —
    // supersedes ticks-always-merged): each source contributes only when the
    // policy admits it, so one map serves rendering and resume arbitration.
    final merged = <String, double>{
      if (policy.progressFrom(TrackingSource.local))
        ...await EpisodeResumeStorage.getEpisodeWatchProgressByImdbId(imdbId),
    };
    if (!mounted || generation != _s.episodeModeGeneration) return;

    final inputs = <String, Map<String, double>>{'local': Map.of(merged)};
    final statuses = <String, String>{
      for (final source in TrackingSource.values)
        source.name: policy.progressFrom(source)
            ? 'not_connected'
            : 'excluded_by_policy',
      'local': policy.progressFrom(TrackingSource.local)
          ? 'loaded'
          : 'excluded_by_policy',
    };

    // Overlay Trakt state when connected — gated on auth like the Simkl block
    // below (fresh storage read, not a raced field). The fetches were already
    // empty no-ops without a token, but they logged "failed (null)" on every
    // refresh — indistinguishable from a real API failure, which sent a whole
    // debugging session chasing a phantom credential after a disconnect.
    if (policy.progressFrom(TrackingSource.trakt) &&
        await _sv.traktService.isAuthenticated()) {
      if (!mounted || generation != _s.episodeModeGeneration) return;
      try {
        final watched = await _sv.traktService.fetchWatchedShowEpisodes(imdbId);
        if (!mounted || generation != _s.episodeModeGeneration) return;
        final playback = await _sv.traktService.fetchEpisodePlaybackProgress(
          imdbId,
        );
        if (!mounted || generation != _s.episodeModeGeneration) return;

        // Fully-watched episodes win outright.
        inputs['trakt'] = {...playback, for (final key in watched) key: 100.0};
        statuses['trakt'] = 'loaded';
        for (final key in watched) {
          merged[key] = 100.0;
        }
        // Partial playback overlays, but never downgrades a completed episode
        // and only when it's meaningful and higher than what we already have.
        for (final entry in playback.entries) {
          final existing = merged[entry.key] ?? 0;
          if (existing >= 100.0) continue;
          if (entry.value > 5.0 && entry.value > existing) {
            merged[entry.key] = entry.value;
          }
        }
      } catch (e) {
        statuses['trakt'] = 'error';
        debugPrint('EpisodesPanel: Trakt episode progress fetch failed: $e');
      }
    }

    // Overlay Simkl state — a third source, same merge rules as Trakt's
    // (watched wins outright, partials only raise). Skipped entirely when
    // Simkl isn't connected so disconnected users pay zero extra calls.
    //
    // Asked FRESH rather than read off [_isSimklAuthenticated]: that field is
    // resolved concurrently from initState, and this loader used to win the
    // race against it — silently skipping the Simkl overlay on first open.
    // It only STARTED losing when the profiles/at-rest-encryption work turned
    // the token read from one SharedPreferences hop into ProfilePreferences +
    // SecretVault, which is exactly when "no ticks on a fresh install with
    // only Simkl history" was reported (2026-08-16). Nothing re-runs this
    // loader when the field flips later, so losing the race wasn't a delay —
    // it was a miss. One storage read here keeps the no-API-when-disconnected
    // intent without racing anybody; the field keeps gating the episode MENU
    // rows, where by open-time it has long settled.
    if (policy.progressFrom(TrackingSource.simkl) &&
        await _sv.simklService.isAuthenticated()) {
      try {
        final watched = await _sv.simklService.fetchWatchedShowEpisodes(imdbId);
        if (!mounted || generation != _s.episodeModeGeneration) return;
        final playback = await _sv.simklService.fetchEpisodePlaybackProgress(
          imdbId,
        );
        if (!mounted || generation != _s.episodeModeGeneration) return;

        inputs['simkl'] = {...playback, for (final key in watched) key: 100.0};
        statuses['simkl'] = 'loaded';
        for (final key in watched) {
          merged[key] = 100.0;
        }
        for (final entry in playback.entries) {
          final existing = merged[entry.key] ?? 0;
          if (existing >= 100.0) continue;
          if (entry.value > 5.0 && entry.value > existing) {
            merged[entry.key] = entry.value;
          }
        }
      } catch (e) {
        statuses['simkl'] = 'error';
        debugPrint('EpisodesPanel: Simkl episode progress fetch failed: $e');
      }
    }

    if ((MediaIdentity.isImdb(imdbId) || MediaIdentity.isNative(imdbId)) &&
        await _sv.mdblistService.isAuthenticated()) {
      if (policy.progressFrom(TrackingSource.mdblist)) {
        try {
          final result = await _sv.mdblistService.fetchShowEpisodeProgress(
            imdbId,
          );
          if (!mounted || generation != _s.episodeModeGeneration) return;
          if (result.isUsable) {
            inputs['mdblist'] = Map.of(result.data!);
            statuses['mdblist'] = 'loaded';
            for (final entry in result.data!.entries) {
              final existing = merged[entry.key] ?? 0;
              if (entry.value >= 100 || entry.value > existing) {
                merged[entry.key] = entry.value;
              }
            }
          } else {
            statuses['mdblist'] = 'unavailable';
          }
        } catch (e) {
          statuses['mdblist'] = 'error';
          debugPrint(
            'EpisodesPanel: MDBList episode progress fetch failed: $e',
          );
        }
      }
      try {
        final result = await _sv.mdblistService.fetchShowEpisodeRatings(imdbId);
        if (!mounted || generation != _s.episodeModeGeneration) return;
        if (result.isUsable) {
          episodeMdblistRatings = result.data!;
        }
      } catch (e) {
        debugPrint('EpisodesPanel: MDBList episode ratings fetch failed: $e');
      }
    }

    if (mounted && generation == _s.episodeModeGeneration) {
      final next = mergedUpNext(merged, _s.trackerNextRaw);
      logEpisodeProgress(merged, inputs, statuses, next: next);
      _deps.setState(() {
        episodeWatchProgress = merged;
        _s.nextEpisode = next;
      });
      if (next != null) publishNextEpisode(next);
      publishSeriesCompletion();
    }
  }

  /// Refresh-time diagnostics; never logs tokens, URLs, or episode titles.
  void logEpisodeProgress(
    Map<String, double> merged,
    Map<String, Map<String, double>> inputs,
    Map<String, String> statuses, {
    EpisodeCoordinate? next,
  }) {
    final keys = <String>{
      ...merged.keys,
      for (final input in inputs.values) ...input.keys,
      for (final season in _s.episodeSeasons)
        for (final episode in season.episodes)
          '${episode.season}-${episode.number}',
    };
    final refresh = DateTime.now().microsecondsSinceEpoch;
    for (final key in keys) {
      final coordinate = RegExp(r'^(\d+)[_-](\d+)$').firstMatch(key);
      if (coordinate == null) continue;
      final season = int.parse(coordinate.group(1)!);
      final episode = int.parse(coordinate.group(2)!);
      final progress = merged[key] ?? 0;
      final winners = inputs.entries
          .where((entry) {
            final value = entry.value[key];
            return value != null &&
                value > 0 &&
                value == progress &&
                (!const ['trakt', 'simkl'].contains(entry.key) || value > 5);
          })
          .map((entry) => entry.key)
          .toList();
      final fields = <String, Object?>{
        'refresh': refresh,
        'season': season,
        'episode': episode,
        'display_percent': progress,
        'watched': progress >= 100,
        'up_next': next?.season == season && next?.episode == episode,
        'winning_sources': DiagnosticLabel(
          winners.isEmpty ? 'none' : winners.join('+'),
        ),
        for (final entry in statuses.entries)
          '${entry.key}_status': DiagnosticLabel(entry.value),
        for (final entry in inputs.entries)
          '${entry.key}_percent': entry.value[key],
      };
      DiagnosticLog.instance.recordEvent(
        source: 'episode_progress',
        event: 'detail_merge',
        fields: fields,
      );
      debugPrint(
        'EpisodeProgress: refresh=$refresh S${season}E$episode '
        'inputs=${{for (final entry in inputs.entries) entry.key: entry.value[key]}} '
        'status=$statuses displayed=$progress winners=${winners.join('+')} '
        'watched=${progress >= 100} upNext=${fields['up_next']}',
      );
    }
  }

  ({int season, int episode})? mergedUpNext(
    Map<String, double> progress,
    ({int season, int episode})? trackerNext,
  ) => mergedEpisodeUpNext(
    episodes: [
      for (final season in _s.episodeSeasons)
        for (final episode in season.episodes)
          (season: episode.season, episode: episode.number),
    ],
    progress: progress,
    trackerNext: trackerNext,
  );

  void publishNextEpisode(EpisodeCoordinate next, {bool mutation = false}) {
    _deps.onNextEpisodeChanged()?.call(
      episodeResumeTarget(next: next, progress: episodeWatchProgress),
      mutation: mutation,
    );
  }

  void publishSeriesCompletion() {
    _deps.onSeriesCompletedChanged()?.call(
      !_a.isDirectSource &&
          isSeriesFullyWatched({
            for (final s in _s.episodeSeasons)
              s.number: s.episodes.map((e) => e.number),
          }, episodeWatchProgress),
    );
  }
}
