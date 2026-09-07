import 'package:flutter/material.dart';

import '../../models/playlist_entry.dart';
import '../../models/series_playlist.dart';
import '../../models/torrent.dart';
import '../../services/series_source_fetcher.dart';
import '../../utils/series_parser.dart';
import 'player_transition_session.dart';

/// Live player state the moved episode-ladder functions read and write.
///
/// Implemented by the player State (`_EpisodeLadderSession`). Named without
/// host `_` prefixes so this file compiles with those members removed.
abstract class EpisodeLadderSession {
  /// Host `mounted`.
  bool get isMounted;

  /// Host `context` (the ScaffoldMessenger is captured before the first
  /// await, as in the origin).
  BuildContext get hostContext;

  /// Host `setState`.
  void runSetState(VoidCallback updates);

  /// Host `_canFetchEpisodes`.
  bool get canFetchEpisodes;

  /// Host `_transition`.
  PlayerTransitionSession get transition;

  /// Origin `widget.seriesSourceFetcher`.
  SeriesSourceFetcher? get seriesSourceFetcher;

  /// Origin `widget.resolveSourceToPlaylist`.
  Future<List<PlaylistEntry>?> Function(Torrent)? get resolveSourceToPlaylist;

  /// Origin `widget.title`.
  String get title;

  /// Host `_playlistIdentityToken` (read only: bumped by the host switch).
  int get playlistIdentityToken;

  /// Host `_effectiveSources`.
  List<Torrent>? get effectiveSources;

  /// Host `_currentSourceIndex`.
  int get currentSourceIndex;

  /// Host `_augmentedSources` (the ladder only ever merges into it).
  set augmentedSources(List<Torrent>? value);

  /// Host `_setManualSelectionMode`.
  void setManualSelectionMode({required bool allowResume});

  /// Host `_switchToSourcePlaylist` (Media body; stays in the host).
  Future<void> switchToSourcePlaylist(
    int sourceIndex,
    List<PlaylistEntry> newPlaylist, {
    int? targetSeason,
    int? targetEpisode,
  });
}

/// Episode guide: in-player fetch of absent episodes — the candidate ladder
/// (listed sources, then an episode-targeted fetch, then a pack search) that
/// switches to the first candidate that resolves to the requested episode.
class EpisodeLadderController {
  EpisodeLadderController(this.session);

  final EpisodeLadderSession session;

  bool _episodeFetchInProgress = false;

  static String pad2(int n) => n.toString().padLeft(2, '0');

  bool _packCoversSeason(Torrent t, int season) {
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
  Future<void> fetchAndPlayEpisode(int season, int episode) async {
    if (!session.canFetchEpisodes || _episodeFetchInProgress) {
      // A next/prev press may have raised the transition curtain already;
      // never leave it up when the request can't run.
      if (session.isMounted && session.transition.blocking) {
        session.runSetState(() => session.transition.setBlocking(false));
      }
      return;
    }
    final fetcher = session.seriesSourceFetcher!;
    _episodeFetchInProgress = true;
    final messenger = ScaffoldMessenger.of(session.hostContext);
    final label = 'S${pad2(season)}E${pad2(episode)}';
    messenger.showSnackBar(
      SnackBar(
        content: Text('Fetching $label…'),
        duration: const Duration(seconds: 2),
      ),
    );
    try {
      final token = session.playlistIdentityToken;

      // 1. Try what's already in the source list: exact-episode singles and
      // packs covering the season (often already unlocked on the account).
      final existing = List<Torrent>.of(session.effectiveSources ?? const <Torrent>[]);
      var attempts = 0;
      for (var i = 0; i < existing.length && attempts < 4; i++) {
        if (i == session.currentSourceIndex) continue;
        final t = existing[i];
        if (t.streamType == StreamType.externalUrl) continue;
        final info = SeriesParser.parseFilename(t.displayTitle);
        final matchesEpisode = info.season == season && info.episode == episode;
        final coversAsPack =
            t.streamType == StreamType.torrent && _packCoversSeason(t, season);
        if (!matchesEpisode && !coversAsPack) continue;
        attempts++;
        if (await _tryEpisodeCandidate(i, t, season, episode, token)) return;
        if (!session.isMounted || token != session.playlistIdentityToken) return;
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
      if (!session.isMounted || token != session.playlistIdentityToken) return;
      if (fetched != null && fetched.isNotEmpty) {
        final base = session.effectiveSources ?? const <Torrent>[];
        final merged = SeriesSourceFetcher.mergeSources(base, fetched);
        session.runSetState(() => session.augmentedSources = merged);
        attempts = 0;
        for (var i = base.length; i < merged.length && attempts < 5; i++) {
          final t = merged[i];
          if (t.streamType == StreamType.externalUrl) continue;
          attempts++;
          if (await _tryEpisodeCandidate(i, t, season, episode, token)) return;
          if (!session.isMounted || token != session.playlistIdentityToken) return;
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
      if (!session.isMounted || token != session.playlistIdentityToken) return;
      if (packs != null && packs.isNotEmpty) {
        final base = session.effectiveSources ?? const <Torrent>[];
        final merged = SeriesSourceFetcher.mergeSources(base, packs);
        session.runSetState(() => session.augmentedSources = merged);
        attempts = 0;
        for (var i = base.length; i < merged.length && attempts < 3; i++) {
          final t = merged[i];
          if (t.streamType != StreamType.torrent) continue;
          // Pack-search results are season-targeted; only skip ones whose
          // detected coverage positively excludes the season.
          if (t.coverageType != null && !_packCoversSeason(t, season)) {
            continue;
          }
          attempts++;
          if (await _tryEpisodeCandidate(i, t, season, episode, token)) return;
          if (!session.isMounted || token != session.playlistIdentityToken) return;
        }
      }

      if (session.isMounted && token == session.playlistIdentityToken) {
        // A next/prev press raised the transition curtain before calling in
        // here — drop it, or a failed fetch leaves the screen black.
        if (session.transition.blocking) {
          session.runSetState(() => session.transition.setBlocking(false));
        }
        messenger.showSnackBar(
          SnackBar(content: Text('No playable source found for $label')),
        );
      }
    } finally {
      _episodeFetchInProgress = false;
    }
  }

  /// Resolve one candidate and switch to it when it actually contains the
  /// target episode. Returns true when playback switched (or when the
  /// attempt went stale and the loop must stop).
  Future<bool> _tryEpisodeCandidate(
    int sourceIndex,
    Torrent t,
    int season,
    int episode,
    int token,
  ) async {
    if (!await session.seriesSourceFetcher!.allowsCandidate(t)) return false;
    if (!session.isMounted || token != session.playlistIdentityToken) return true;
    List<PlaylistEntry>? playlist;
    try {
      playlist = await session.resolveSourceToPlaylist!(t);
    } catch (_) {
      playlist = null;
    }
    if (!session.isMounted || token != session.playlistIdentityToken) return true;
    if (playlist == null || playlist.isEmpty) return false;
    if (playlist.length == 1) {
      final info = SeriesParser.parseFilename(playlist.first.title);
      if (info.season == null || info.episode == null) {
        // Unparseable single stream: stamp the target identity into the
        // title so parsing (titles, scrobbling, the guide) stays coherent.
        playlist = [
          playlist.first.copyWithTitle(
            'S${pad2(season)}E${pad2(episode)} ${playlist.first.title}',
          ),
        ];
      } else if (info.season != season || info.episode != episode) {
        return false; // resolves to a DIFFERENT episode — wrong result
      }
    } else {
      final sp = SeriesPlaylist.fromPlaylistEntries(
        playlist,
        collectionTitle: session.title,
        forceSeries: true,
      );
      if (sp.findOriginalIndexBySeasonEpisode(season, episode) < 0) {
        return false; // pack without the target — try the next candidate
      }
    }
    session.setManualSelectionMode(allowResume: true);
    await session.switchToSourcePlaylist(
      sourceIndex,
      playlist,
      targetSeason: season,
      targetEpisode: episode,
    );
    return true;
  }
}
