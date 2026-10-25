import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:debrify/services/storage/tracker_episode_progress_storage.dart';
import 'package:debrify/services/tracking_source_policy.dart';
import 'package:debrify/services/mdblist/mdblist_service.dart';
import 'package:debrify/services/mdblist/mdblist_models.dart';
import 'package:debrify/services/mdblist/mdblist_scrobble_session.dart';

abstract interface class VpMdblistScrobblerHost {
  bool get mounted;
  bool get validationGateActive;
  bool get isPlaying;
  Duration get duration;
  String? get effectiveContentImdbId;
  String? get contentImdbId;
  String? get contentType;
  String? get currentSeriesImdbId;
  String? get episodeTrackerProgressImdbId;
  ({int? season, int? episode}) traktSeasonEpisode();
  void bindEpisodeTrackerProgressIdentity(String imdbId);
  bool get mdblistScrobble;
  Duration get position;
  Duration get persistablePosition;
  Future<void> get playerInitializationFuture;
}

class VpMdblistScrobbler {
  VpMdblistScrobbler(this._host);
  final VpMdblistScrobblerHost _host;

  Map<String, double>? mdblistEpisodeProgress;
  bool launchMdblistPercentSpent = false;
  MdblistScrobbleSession? mdblistSession;

  MdblistScrobbleTarget? mdblistTarget() {
    final imdbId = _host.contentImdbId;
    if (imdbId == null || imdbId.isEmpty) return null;
    final ids = MdblistMediaIds.forContent(imdbId);
    if (_host.contentType == 'movie') {
      return MdblistScrobbleTarget.movie(ids);
    }
    if (_host.contentType != 'series') return null;
    final se = _host.traktSeasonEpisode();
    if (se.season == null || se.episode == null) return null;
    return MdblistScrobbleTarget.episode(
      ids,
      season: se.season!,
      episode: se.episode!,
    );
  }

  Future<void> initMdblistScrobble() async {
    debugPrint(
      '[MDBListDiag] player init requested=${_host.mdblistScrobble} '
      'flag=$kMdblistEnabled imdb=${_host.contentImdbId} '
      'type=${_host.contentType}',
    );
    if (!_host.mdblistScrobble || !kMdblistEnabled) {
      debugPrint('[MDBListDiag] player init skipped: tracking not requested');
      return;
    }
    final policy = (await TrackingSourcePolicy.load()).forContent(
      _host.effectiveContentImdbId,
    );
    if (!policy.scrobbles(TrackingSource.mdblist)) return;
    // Playlist launches resolve their requested/resume episode asynchronously.
    // Before that finishes `_currentIndex` is still zero, so constructing the
    // MDBList target here used to scrobble S1E1 while the player actually
    // opened (for example) S1E8. Wait until `VpPlayerStartup.initializePlayer` publishes the
    // real initial index; its playing-state check below still starts tracking
    // immediately when media became ready during the wait.
    try {
      await _host.playerInitializationFuture;
    } catch (e) {
      debugPrint('[MDBListDiag] player init skipped: player setup failed $e');
      return;
    }
    if (!_host.mounted) return;
    // The launcher already resolved the effective sync+authentication setting
    // before deciding both remote ownership and local-completion suppression.
    // Re-resolving it here could disagree with that launch snapshot and leave
    // the play tracked nowhere; the session capability below still prevents a
    // stale profile/account from receiving writes.
    final target = mdblistTarget();
    if (target == null) {
      debugPrint('[MDBListDiag] player init skipped: invalid target metadata');
      return;
    }
    final capability = await MdblistService.instance
        .capturePlaybackCapability();
    if (!_host.mounted) {
      debugPrint('[MDBListDiag] player init abandoned: player unmounted');
      return;
    }
    final session = MdblistScrobbleSession.forService(
      service: MdblistService.instance,
      target: target,
      capability: capability,
    );
    session.updatePosition(_host.position, _host.duration);
    mdblistSession = session;
    debugPrint(
      '[MDBListDiag] player session ready imdb=${target.ids.imdb} '
      'episode=${target.isEpisode} playing=${_host.isPlaying} '
      'positionMs=${_host.position.inMilliseconds} '
      'durationMs=${_host.duration.inMilliseconds}',
    );
    if (!_host.validationGateActive &&
        _host.isPlaying &&
        _host.duration > Duration.zero) {
      session.play();
    }
  }

  void updateMdblistPosition() {
    if (_host.validationGateActive) return;
    // Held-target substitution, same reason as VpTraktScrobbler.traktProgress.
    mdblistSession?.updatePosition(_host.persistablePosition, _host.duration);
  }

  void mdblistPlay() {
    if (_host.validationGateActive) return;
    updateMdblistPosition();
    mdblistSession?.play();
  }

  void mdblistPause() {
    if (_host.validationGateActive) return;
    updateMdblistPosition();
    mdblistSession?.pause();
  }

  void mdblistStop({bool complete = false}) {
    if (_host.validationGateActive) return;
    updateMdblistPosition();
    debugPrint(
      '[MDBListDiag] player stop complete=$complete '
      'session=${mdblistSession != null} '
      'positionMs=${_host.position.inMilliseconds} '
      'durationMs=${_host.duration.inMilliseconds}',
    );
    if (complete) {
      mdblistSession?.complete();
    } else {
      mdblistSession?.exit();
    }
  }

  void mdblistScrobbleSeek(Duration target) {
    if (_host.validationGateActive) return;
    mdblistSession?.seek(target, _host.duration);
  }

  Future<void> switchMdblistTarget() async {
    if (_host.validationGateActive) return;
    final target = mdblistTarget();
    if (target == null) {
      mdblistSession?.exit();
      return;
    }
    await mdblistSession?.switchTarget(target);
  }

  Future<double?> currentEpisodeMdblistPercent({bool forGuide = false}) async {
    final policy = (await TrackingSourcePolicy.load()).forContent(
      _host.effectiveContentImdbId,
    );
    if (!forGuide && !policy.progressFrom(TrackingSource.mdblist)) return null;
    final imdbId = _host.currentSeriesImdbId;
    if (imdbId == null) return null;
    _host.bindEpisodeTrackerProgressIdentity(imdbId);
    if (mdblistEpisodeProgress == null) {
      final loaded =
          await TrackerEpisodeProgressStorage.getEpisodeMdblistProgress(
            imdbId: imdbId,
          );
      if (_host.episodeTrackerProgressImdbId != imdbId) return null;
      mdblistEpisodeProgress = loaded;
    }
    final se = _host.traktSeasonEpisode();
    if (se.season == null || se.episode == null) return null;
    final percent = mdblistEpisodeProgress!['${se.season}_${se.episode}'];
    return forGuide
        ? policy.guideProgressFrom(TrackingSource.mdblist, percent)
        : percent;
  }
}
