import 'package:debrify/services/storage/playback_progress_store.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/iptv_playlist.dart';
import '../../models/series_playlist.dart';
import '../../services/local_playback_resume_resolver.dart';
import '../../services/resume_write_guard.dart';
import '../../services/storage_service.dart';
import '../../services/tracking_source_policy.dart';
import '../../utils/episode_progress_merge.dart';
import '../../utils/series_parser.dart';
import 'constants/timing_constants.dart';
import 'models/gesture_state.dart';
import 'models/playlist_entry.dart';
import 'utils/aspect_mode_utils.dart';

/// `(entry, position, duration)` snapshot the resume path persists and seeks.
class ResumeContext {
  const ResumeContext({
    required this.entry,
    required this.position,
    required this.duration,
  });

  final PlaylistEntry? entry;
  final Duration position;
  final Duration duration;
}

/// Live player state the moved resume functions read and write.
///
/// Implemented by the player State. Named without host `_` prefixes so this
/// file compiles with those members removed (gate g).
abstract class ResumeSession {
  ResumeWriteGuard get writeGuard;
  int get resumeVerifyEpoch;

  List<PlaylistEntry>? get activePlaylist;
  int get currentIndex;
  List<IptvChannel>? get effectiveIptvChannels;
  int get currentIptvIndex;

  String get videoUrl;
  String get title;
  PlaybackResumePolicy get resumePolicy;
  double? get traktProgressPercent;
  double? get simklProgressPercent;
  double? get mdblistProgressPercent;
  String? get contentImdbId;

  bool get isAutoAdvancing;
  set isAutoAdvancing(bool value);
  bool get isManualEpisodeSelection;
  bool get allowResumeForManualSelection;
  bool get launchTraktPercentSpent;
  set launchTraktPercentSpent(bool value);
  bool get launchSimklPercentSpent;
  set launchSimklPercentSpent(bool value);
  bool get launchMdblistPercentSpent;
  set launchMdblistPercentSpent(bool value);

  Duration get position;
  Duration get duration;
  Duration get playerPosition;
  Future<void> seek(Duration target);
  Future<void> setRate(double speed);
  double get playbackSpeed;
  set playbackSpeed(double value);
  AspectMode get aspectMode;
  set aspectMode(AspectMode value);
  Future<void> applyAspectVideoZoom();
  Future<void> waitForDuration();

  Future<double?> currentEpisodeTraktPercent({bool forGuide = false});
  Future<double?> currentEpisodeSimklPercent({bool forGuide = false});
  Future<double?> currentEpisodeMdblistPercent({bool forGuide = false});

  String? get currentLocalMovieImdbId;
  SeriesPlaylist? get seriesPlaylist;
  String? get effectiveContentImdbId;
  String? get effectiveContentType;
  int? get effectiveContentSeason;
  int? get effectiveContentEpisode;
  String? get effectiveContentTitle;
  String? get currentStremioTvContentTitle;
  String? get currentStreamUrl;

  bool get validationGateActive;
  bool get isReady;
  bool get isTransitioning;
  bool get currentMovieMarkedAsFinished;
  double? get speedBeforeHold;

  bool get isMounted;
  bool get screenDisposed;
  String generateFilenameHash(String filename);
}

/// Player resume: keys, restore, guarded seek, enhanced+legacy persist.
///
/// Bodies moved from `_VideoPlayerScreenState` `_resumeKey` through
/// `_saveResume`. No setState — mutations go through [ResumeSession].
class ResumeController {
  ResumeController(this.session);

  final ResumeSession session;
  final Set<_ResumeVerificationJob> _resumeVerificationJobs = {};
  bool _resumeVerificationDisposed = false;

  /// Stops the current jobs synchronously; acknowledges their final retirement.
  /// An already-issued seek must settle before its job can retire.
  Future<void> cancelResumeVerification() {
    final jobs = _resumeVerificationJobs.toList(growable: false);
    for (final job in jobs) {
      job.cancel();
    }
    return Future.wait<void>(jobs.map((job) => job.settled)).then<void>((_) {});
  }

  /// Prevents later verifier admission, including after a held initial seek.
  Future<void> dispose() {
    _resumeVerificationDisposed = true;
    return cancelResumeVerification();
  }

  Future<void> _runResumeVerification(_ResumeVerificationJob job) async {
    try {
      await _verifyResumeLanding(job.targetMs, job.epoch, job);
    } finally {
      // A retiring job must never remove or cancel a newer job.
      _resumeVerificationJobs.remove(job);
      job.finish();
    }
  }

  ResumeContext get context {
    PlaylistEntry? entry;
    final playlist = session.activePlaylist;
    if (playlist != null &&
        playlist.isNotEmpty &&
        session.currentIndex >= 0 &&
        session.currentIndex < playlist.length) {
      entry = playlist[session.currentIndex];
    }
    return ResumeContext(
      entry: entry,
      position: session.position,
      duration: session.duration,
    );
  }

  String get key {
    if (session.activePlaylist != null &&
        session.activePlaylist!.isNotEmpty &&
        session.currentIndex >= 0 &&
        session.currentIndex < session.activePlaylist!.length) {
      final entry = session.activePlaylist![session.currentIndex];

      // Check for Torbox-specific key
      final torboxKey = torboxKeyForEntry(entry);
      if (torboxKey != null) {
        debugPrint(
          'ResumeKey: using torbox key $torboxKey for index ${session.currentIndex}',
        );
        return torboxKey;
      }

      // Check for PikPak-specific key
      final pikpakKey = pikpakKeyForEntry(entry);
      if (pikpakKey != null) {
        debugPrint(
          'ResumeKey: using pikpak key $pikpakKey for index ${session.currentIndex}',
        );
        return pikpakKey;
      }
    }

    // Use playlist-specific resume ID for other items
    if (session.activePlaylist != null &&
        session.activePlaylist!.isNotEmpty &&
        session.currentIndex >= 0 &&
        session.currentIndex < session.activePlaylist!.length) {
      final id = idForEntry(session.activePlaylist![session.currentIndex]);
      debugPrint(
        'ResumeKey: using playlist entry id $id for index ${session.currentIndex}',
      );
      return id;
    }

    // IPTV launches carry no playlist, so the fallback below would key every
    // channel in the session to the URL the player was OPENED with — zap to
    // another channel and its position would be filed under the first one's
    // name. Key on the channel actually playing instead. (Identical to the
    // fallback until the user zaps, so existing resume points still resolve.)
    final iptvChannels = session.effectiveIptvChannels;
    if (iptvChannels != null &&
        session.currentIptvIndex >= 0 &&
        session.currentIptvIndex < iptvChannels.length) {
      return iptvChannels[session.currentIptvIndex].url;
    }

    // Fallback to videoUrl for single items
    // Note: This is the expected path for Debrify TV mode
    return session.videoUrl;
  }

  String? torboxKeyForEntry(PlaylistEntry entry) {
    final provider = entry.provider?.toLowerCase();
    if (provider == 'torbox') {
      final torrentId = entry.torboxTorrentId;
      final webDownloadId = entry.torboxWebDownloadId;
      final fileId = entry.torboxFileId;
      if (webDownloadId != null && fileId != null) {
        debugPrint(
          'ResumeKey: torbox web download detected web=$webDownloadId file=$fileId',
        );
        return 'torbox_web_${webDownloadId}_$fileId';
      }
      if (torrentId != null && fileId != null) {
        debugPrint(
          'ResumeKey: torbox entry detected torrent=$torrentId file=$fileId',
        );
        return 'torbox_${torrentId}_$fileId';
      }
      debugPrint(
        'ResumeKey: torbox entry missing IDs torrent=$torrentId web=$webDownloadId file=$fileId',
      );
    }
    return null;
  }

  String? pikpakKeyForEntry(PlaylistEntry entry) {
    final provider = entry.provider?.toLowerCase();
    if (provider == 'pikpak') {
      final fileId = entry.pikpakFileId;
      if (fileId != null && fileId.isNotEmpty) {
        debugPrint('ResumeKey: pikpak entry detected fileId=$fileId');
        return 'pikpak_$fileId';
      }
      debugPrint('ResumeKey: pikpak entry missing fileId');
    }
    return null;
  }

  String idForEntry(PlaylistEntry entry) {
    // Check for Torbox-specific key
    final torboxKey = torboxKeyForEntry(entry);
    if (torboxKey != null) {
      return torboxKey;
    }
    // Check for PikPak-specific key
    final pikpakKey = pikpakKeyForEntry(entry);
    if (pikpakKey != null) {
      return pikpakKey;
    }
    // Fallback to filename hash
    final name = entry.title.isNotEmpty ? entry.title : session.title;
    return session.generateFilenameHash(name);
  }

  /// [preferLocalResume]: a source switch landed on the SAME content and
  /// checkpointed the live position — resume exactly there (any position, even
  /// past the 90% cutoff, matching the native TV player) and skip Trakt.
  /// Threaded as a parameter, not ambient state, so an early return or throw
  /// anywhere in the load path can never leak it into a later load.
  ///
  /// [verifyLanding]: this is the initial open, where the startup gate commits
  /// a candidate after ~40ms of decoded media and the seek can be answered with
  /// a stream restart. Confirm the seek took and re-issue once. See
  /// [seekForResume].
  Future<void> maybeRestoreResume({
    bool preferLocalResume = false,
    bool verifyLanding = false,
  }) async {
    // Every item load lands here, so this is where a previous item's unlanded
    // resume target stops applying — including on the paths below that return
    // without arming a new one (auto-advance, manual episode pick).
    session.writeGuard.clear();
    // If this is auto-advancing, don't restore position
    if (session.isAutoAdvancing) {
      session.isAutoAdvancing = false; // Reset the flag
      return;
    }

    // If this is a manual episode selection, only restore if we have saved progress
    if (session.isManualEpisodeSelection &&
        !session.allowResumeForManualSelection) {
      // Don't reset _isManualEpisodeSelection here - let it be reset after a delay
      return;
    }
    final trackingPolicy = await TrackingSourcePolicy.load();
    // The launched item's widget percent is a first-load-only signal; capture it
    // before marking it spent so it can't apply to a later switched-to episode.
    final firstLoad = !session.launchTraktPercentSpent;
    session.launchTraktPercentSpent = true;
    final simklFirstLoad = !session.launchSimklPercentSpent;
    session.launchSimklPercentSpent = true;
    final mdblistFirstLoad = !session.launchMdblistPercentSpent;
    session.launchMdblistPercentSpent = true;

    await session.waitForDuration();
    final dur = session.duration;

    // Trakt candidate (cross-device %), skipped for a source switch. Launched
    // item uses the widget percent (first load); a switched item uses its own
    // per-episode store percent. The widget percent is an EXPLICIT promise —
    // the details-screen Resume button advertised this position — so when
    // seekable it wins outright below (never silently overridden by local).
    double? traktPct;
    double? traktProviderPct;
    double? simklProviderPct;
    double? mdblistProviderPct;
    var explicitLaunch = false;
    if (!preferLocalResume &&
        trackingPolicy.progressFrom(TrackingSource.trakt)) {
      final launchPct = firstLoad ? session.traktProgressPercent : null;
      if (launchPct != null) {
        traktPct = launchPct;
        traktProviderPct = launchPct;
        explicitLaunch = true;
      } else {
        traktPct = await session.currentEpisodeTraktPercent();
        traktProviderPct = traktPct;
      }
    }
    if (!preferLocalResume &&
        trackingPolicy.progressFrom(TrackingSource.mdblist)) {
      final explicitMdblistPct = mdblistFirstLoad
          ? session.mdblistProgressPercent
          : null;
      final mdblistPct =
          explicitMdblistPct ?? await session.currentEpisodeMdblistPercent();
      mdblistProviderPct = mdblistPct;
      if (mdblistPct != null && (traktPct == null || mdblistPct > traktPct)) {
        traktPct = mdblistPct;
        explicitLaunch = explicitMdblistPct != null;
      }
    }
    // Simkl candidate: the explicit launch promise on first load, otherwise
    // this episode's launch-time snapshot. Folded into the same candidate as
    // Trakt so the furthest remote progress wins.
    if (!preferLocalResume &&
        trackingPolicy.progressFrom(TrackingSource.simkl)) {
      final explicitSimklPct = simklFirstLoad
          ? session.simklProgressPercent
          : null;
      final simklPct =
          explicitSimklPct ?? await session.currentEpisodeSimklPercent();
      simklProviderPct = simklPct;
      if (simklPct != null && (traktPct == null || simklPct > traktPct)) {
        traktPct = simklPct;
        explicitLaunch = explicitSimklPct != null;
      }
    }
    final int traktMs =
        (traktPct != null &&
            traktPct > 0 &&
            traktPct < 100 &&
            dur > Duration.zero)
        ? (dur.inMilliseconds * traktPct / 100).floor()
        : 0;

    // Local candidate + speed/aspect restore (enhanced state preferred, else the
    // legacy resume store). Speed/aspect are restored regardless of the seek.
    int localMs = 0;
    final allowLocalResume =
        preferLocalResume || trackingPolicy.progressFrom(TrackingSource.local);
    final localMovieImdbId = session.currentLocalMovieImdbId;
    final locallyFinishedMovie =
        !preferLocalResume &&
        localMovieImdbId != null &&
        await PlaybackProgressStore.isMovieFinished(localMovieImdbId);
    // Speed/aspect are device prefs riding in the resume record — restore
    // them in EVERY progress mode; only the POSITION is a policy-gated
    // resume candidate.
    final state = locallyFinishedMovie
        ? null
        : await _getEnhancedPlaybackState() ??
              await StorageService.getVideoResume(key);
    if (state != null) {
      if (allowLocalResume) {
        localMs = (state['positionMs'] ?? 0) as int;
      }
      final speed = (state['speed'] ?? 1.0) as double;
      final aspect = (state['aspect'] ?? 'contain') as String;
      if (speed != 1.0) {
        await session.setRate(speed);
        session.playbackSpeed = speed;
      }
      session.aspectMode = AspectModeUtils.stringToAspectMode(aspect);
      await session.applyAspectVideoZoom();
    }

    if (dur <= Duration.zero) return;

    // Source switch on the same content: come back EXACTLY where you were —
    // no resumable-window gating (you might be 93% in, mid-credits), matching
    // the native TV player's source-switch semantics.
    if (preferLocalResume) {
      if (localMs > 0 && localMs < dur.inMilliseconds) {
        await seekForResume(localMs, verifyLanding: verifyLanding);
      }
      return;
    }

    final loMs =
        VideoPlayerTimingConstants.minimumPlaybackPosition.inMilliseconds;
    final hiMs = (dur.inMilliseconds * 0.9).floor();
    // Legacy builds persisted Trakt watched history as if it were a local
    // completion. A current partial Trakt session is a rewatch, so that stale
    // completed position must not force a fresh start. Keep this migration
    // in-memory; the old record has no provenance and may be genuine local
    // history. Independent Simkl/MDBList completion still wins.
    if (localMs >= hiMs) {
      // The rewatch detector consumes the same policy-masked inputs as guide
      // rendering (ticks AND partials both follow the Progress source since
      // 2026-08-27) — a non-selected provider's session can't un-tick local
      // completion.
      traktProviderPct ??= await session.currentEpisodeTraktPercent(
        forGuide: true,
      );
      simklProviderPct ??= await session.currentEpisodeSimklPercent(
        forGuide: true,
      );
      mdblistProviderPct ??= await session.currentEpisodeMdblistPercent(
        forGuide: true,
      );
      if (hasActiveTraktEpisodeRewatch(
        traktPercent: traktProviderPct,
        simklPercent: simklProviderPct,
        mdblistPercent: mdblistProviderPct,
      )) {
        localMs = 0;
      }
    }
    // The details-screen Resume promised THIS position — honour it outright when
    // seekable (matching the pre-rework launched-item behaviour), even over a
    // deeper/stale local. An unseekable promise falls through to furthest-wins.
    if (explicitLaunch && traktMs > loMs && traktMs < hiMs) {
      debugPrint('Resume: explicit tracker percent -> ${traktMs}ms');
      await seekForResume(traktMs, verifyLanding: verifyLanding);
      return;
    }
    // FURTHEST-WATCHED WINS: seek the deeper of the local position and the Trakt
    // percent, provided it's in the resumable window (past the first 2s, before
    // the last 10%). If neither qualifies, start fresh.
    // Locally FINISHED (past the 90% cutoff on this device): start fresh, and
    // never let a shallower/stale Trakt percent yank a restarted episode into
    // its middle — local IS the furthest position, it's just not seekable.
    if (localMs >= hiMs && localMs > 0) return;
    final traktCand = (traktMs > loMs && traktMs < hiMs) ? traktMs : 0;
    final localCand = (localMs > loMs && localMs < hiMs) ? localMs : 0;
    final target = traktCand > localCand ? traktCand : localCand;
    if (target > 0) {
      debugPrint(
        'Resume: furthest of remote=${traktMs}ms local=${localMs}ms -> ${target}ms',
      );
      await seekForResume(target, verifyLanding: verifyLanding);
    }
  }

  /// Single exit for every resume seek: arms the write guard so a seek that
  /// never lands cannot have its own bookmark overwritten, and — on the startup
  /// path only — confirms the position actually moved.
  ///
  /// [verifyLanding] is opt-in because only the startup path seeks into a
  /// stream the gate committed after ~40ms of decoded media. mpv can answer
  /// that seek by restarting the remote stream at 0 (observed on a debrid link
  /// via the pinned-source ladder), which leaves playback at the beginning with
  /// no error to react to. Re-issuing once, after the stream has warmed up,
  /// recovers it. Mid-session seeks (source switch, episode change) already run
  /// against a settled stream and keep their existing single-shot behaviour.
  Future<void> seekForResume(int targetMs, {bool verifyLanding = false}) async {
    // Never GUARD a near-finished target (≥80% of a known duration — the
    // trackers' stop-scrobble threshold, below the 90% local finished cutoff):
    // substituting one would scrobble a watched mark and store a finished-
    // looking position for content that may be playing at 0:00. The seek
    // itself still happens; such a start just plays unguarded.
    final durMs = session.duration.inMilliseconds;
    final nearFinished = durMs > 0 && targetMs >= (durMs * 0.8).floor();
    if (nearFinished) {
      session.writeGuard.clear();
    } else {
      session.writeGuard.arm(targetMs);
    }
    final target = Duration(milliseconds: targetMs);
    await session.seek(target);
    // Without an armed guard the verifier would abort on its first check.
    if (!verifyLanding || nearFinished) return;
    // Deliberately NOT awaited: the caller is the startup chain, and the
    // "Checking stream…" gate does not come down until it returns. Blocking
    // here would hold that overlay over the video for the whole verification
    // window on exactly the runs that already went wrong.
    if (_resumeVerificationDisposed) return;
    final job = _ResumeVerificationJob(targetMs, session.resumeVerifyEpoch);
    _resumeVerificationJobs.add(job);
    unawaited(_runResumeVerification(job));
  }

  /// Confirms a startup resume seek took, re-issuing it once if it did not.
  ///
  /// Aborts the moment its media stops being current — [epoch] changed (item
  /// change, source switch), the guard stopped pointing at [targetMs] (user
  /// seek), or the position reached the target — so a late retry can never
  /// yank playback away from where the user put it or seek a replacement
  /// stream it was never watching.
  Future<void> _verifyResumeLanding(
    int targetMs,
    int epoch,
    _ResumeVerificationJob job,
  ) async {
    if (job.cancelled) return;
    // A viewer who sees playback start from 0 decides "broken" within a couple
    // of seconds — a single retry after 5s (the first version of this) lost
    // the race against the user's own quit on the observed phone repro. Check
    // early and re-issue up to three times: the first retry catches the common
    // case (mpv restarted a barely-warmed debrid stream at 0), the later ones
    // land on a progressively warmer stream. Every cycle keeps the same abort
    // conditions, so a user seek, item change, or dispose stops it instantly.
    const waits = [
      Duration(milliseconds: 1500),
      Duration(milliseconds: 1500),
      Duration(seconds: 3),
    ];
    for (var attempt = 0; attempt < waits.length; attempt++) {
      if (await _resumeSeekLanded(targetMs, epoch, job, timeout: waits[attempt])) {
        return;
      }
      if (job.cancelled) return;
      if (!session.isMounted || session.screenDisposed) return;
      if (epoch != session.resumeVerifyEpoch) return;
      if (session.writeGuard.pendingTargetMs != targetMs) return;
      debugPrint(
        'Resume: seek did not land '
        '(position=${session.playerPosition.inMilliseconds}ms '
        'target=${targetMs}ms) — re-issuing (${attempt + 1}/${waits.length})',
      );
      await session.seek(Duration(milliseconds: targetMs));
      if (job.cancelled) return;
    }
    if (await _resumeSeekLanded(targetMs, epoch, job)) return;
    if (job.cancelled) return;
    // Still adrift: leave playback where it is rather than fighting the stream.
    // The write guard keeps the stored resume point intact either way.
    debugPrint(
      'Resume: seek still unlanded after retries — leaving playback in place',
    );
  }

  /// Polls for the resume target within a bounded window. Landing is judged
  /// with the same tolerance the write guard uses, since a seek resolves to the
  /// nearest keyframe rather than the exact millisecond.
  ///
  /// Returns true for "stop verifying", which covers landing as well as the
  /// cases where the target stopped being ours: the screen went away, the
  /// epoch moved on, the user seeked, or another item loaded.
  Future<bool> _resumeSeekLanded(
    int targetMs,
    int epoch,
    _ResumeVerificationJob job, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (job.cancelled) return true;
    const interval = Duration(milliseconds: 200);
    // mpv can MASK a seek: it reports the target position for a moment, then
    // a cold debrid stream answers the actual seek by restarting at 0 — the
    // observed "seekbar at halfway for a few ms" phone repro. A single
    // position reading is therefore worthless as landing proof: require the
    // position to still be at the target after a beat, or keep watching.
    const confirmDelay = Duration(milliseconds: 800);
    bool atTarget() =>
        session.playerPosition.inMilliseconds >=
        targetMs - session.writeGuard.toleranceMs;
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (job.cancelled) return true;
      if (!session.isMounted || session.screenDisposed) return true;
      if (epoch != session.resumeVerifyEpoch) return true;
      if (session.writeGuard.pendingTargetMs != targetMs) return true;
      if (atTarget()) {
        final confirmation = await job.wait(confirmDelay);
        if (job.cancelled || confirmation == _ResumeWaitOutcome.stop) return true;
        if (!session.isMounted || session.screenDisposed) return true;
        if (epoch != session.resumeVerifyEpoch) return true;
        if (session.writeGuard.pendingTargetMs != targetMs) return true;
        if (atTarget()) return true;
        debugPrint(
          'Resume: landing was transient (masked seek unwound to '
          '${session.playerPosition.inMilliseconds}ms) — still watching',
        );
        continue;
      }
      final poll = await job.wait(interval);
      if (job.cancelled || poll == _ResumeWaitOutcome.stop) return true;
    }
    if (job.cancelled) return true;
    return false;
  }

  /// Get enhanced playback state for current content
  Future<Map<String, dynamic>?> _getEnhancedPlaybackState() async {
    try {
      final seriesPlaylist = session.seriesPlaylist;
      if (seriesPlaylist != null && seriesPlaylist.isSeries) {
        // For series, get the current episode info
        if (session.currentIndex >= 0 &&
            session.currentIndex < session.activePlaylist!.length) {
          final currentEpisode = seriesPlaylist.allEpisodes.firstWhere(
            (episode) => episode.originalIndex == session.currentIndex,
            orElse: () => seriesPlaylist.allEpisodes.first,
          );

          if (currentEpisode.seriesInfo.season != null &&
              currentEpisode.seriesInfo.episode != null) {
            // Catalog series follow IMDb + S/E across release-title aliases;
            // generic packs keep their exact title-keyed record.
            return await LocalPlaybackResumeResolver.episode(
              seriesTitle: seriesPlaylist.seriesTitle ?? 'Unknown Series',
              season: currentEpisode.seriesInfo.season!,
              episode: currentEpisode.seriesInfo.episode!,
              imdbId: seriesPlaylist.imdbId ?? session.effectiveContentImdbId,
              policy: session.resumePolicy,
            );
          }
        }
      }

      PlaylistEntry? currentEntry;
      final activePlaylist = session.activePlaylist;
      if (activePlaylist != null &&
          session.currentIndex >= 0 &&
          session.currentIndex < activePlaylist.length) {
        currentEntry = activePlaylist[session.currentIndex];
      }

      // A lone series stream has no SeriesPlaylist, but its catalog S/E is
      // authoritative. Prefer the canonical episode record for catalog play;
      // generic playback retains its exact video/source lookup first.
      if (session.effectiveContentType == 'series') {
        if (session.resumePolicy == PlaybackResumePolicy.sourceSpecific &&
            currentEntry != null) {
          final exactVideo = await StorageService.getVideoPlaybackState(
            videoTitle: idForEntry(currentEntry),
          );
          if (exactVideo != null) return exactVideo;
        }

        if (session.effectiveContentSeason != null &&
            session.effectiveContentEpisode != null) {
          final episodeState = await LocalPlaybackResumeResolver.episode(
            seriesTitle: session.effectiveContentTitle ?? session.title,
            season: session.effectiveContentSeason!,
            episode: session.effectiveContentEpisode!,
            imdbId: session.effectiveContentImdbId,
            policy: session.resumePolicy,
          );
          if (episodeState != null) return episodeState;
        }

        // Legacy single-episode launches may only have the mirrored video row.
        if (currentEntry != null) {
          return await StorageService.getVideoPlaybackState(
            videoTitle: idForEntry(currentEntry),
          );
        }
        final legacyTitle = session.title.isNotEmpty
            ? session.title
            : 'Unknown Video';
        return await StorageService.getVideoPlaybackState(videoTitle: legacyTitle);
      }

      final resumeId = currentEntry != null
          ? idForEntry(currentEntry)
          : ((session.currentStremioTvContentTitle ?? session.title).isNotEmpty
                ? (session.currentStremioTvContentTitle ?? session.title)
                : 'Unknown Video');
      // A multi-file movie/collection must keep an existing per-file bookmark
      // ahead of the one catalog IMDb bookmark. ExoPlayer already restricts
      // canonical movie resume to `_PlaybackContentType.single`; mirror that
      // boundary here while retaining the legacy IMDb fallback for unseen files.
      final isSingleLogicalMovie =
          activePlaylist == null || activePlaylist.length <= 1;
      final moviePolicy =
          session.resumePolicy == PlaybackResumePolicy.catalogCanonical &&
              isSingleLogicalMovie
          ? PlaybackResumePolicy.catalogCanonical
          : PlaybackResumePolicy.sourceSpecific;
      debugPrint(
        'Resume Load: fetching state for resumeId=$resumeId '
        'policy=${moviePolicy.name}',
      );
      final videoState = await LocalPlaybackResumeResolver.movie(
        resumeId: resumeId,
        imdbId: session.effectiveContentImdbId,
        policy: moviePolicy,
      );
      if (videoState != null) {
        debugPrint(
          'Resume Load: found state for resumeId=$resumeId '
          'updatedAt=${videoState['updatedAt']}',
        );
      }
      return videoState;
    } catch (e) {
      // Origin: swallow — a failed enhanced-state read falls through to null.
    }
    return null;
  }

  Future<void> saveResume({bool debounced = false}) async {
    if (session.validationGateActive || !session.isReady) {
      return;
    }

    // An IPTV zap flips _currentIptvIndex — and therefore _resumeKey — before
    // the incoming stream opens, while _position/_duration still describe the
    // OUTGOING one (_isReady is never cleared for the gap). A tick landing in
    // that window would file the old movie's position under the new channel's
    // key, which the Continue-watching shelf would then show as real progress.
    // Nothing is lost by skipping: the next tick saves once the switch lands.
    if (session.effectiveIptvChannels != null && session.isTransitioning) {
      return;
    }

    // If this is a manual episode selection and it's been less than 30 seconds, skip saving
    // This gives the user time to seek to where they want
    if (session.isManualEpisodeSelection && debounced) {
      return;
    }

    var pos = session.position;
    final dur = session.duration;
    if (dur <= Duration.zero) {
      return;
    }

    // A resume seek was requested and playback is still nowhere near it: the
    // seek did not land, so the live position describes a stream that
    // restarted at the beginning. Filing it would destroy the very bookmark we
    // tried to resume from — persist the REQUESTED target instead, which keeps
    // the bookmark where it was while still recording speed/aspect changes
    // made in the window (this is their only persistence route). The guard
    // self-releases once the seek lands, the user seeks, or they have watched
    // from here long enough for it to be their real position.
    if (!session.writeGuard.allowsPersist(pos.inMilliseconds)) {
      // allowsPersist(false) implies an armed target.
      final heldTarget = session.writeGuard.pendingTargetMs!;
      if (heldTarget >= dur.inMilliseconds) {
        // _duration mirrors mpv live and can briefly read short on a fresh
        // remote stream. Writing the target against that duration would store
        // a ≥100% (finished-looking) position, so skip this tick entirely —
        // including speed/aspect, which the next tick (or exit save) persists
        // once the duration settles. Deliberate trade: a rare few-second delay
        // beats a bookmark that reads as watched.
        return;
      }
      pos = Duration(milliseconds: heldTarget);
    }

    // Completion clears local movie resume/CW state. Do not let the autosave
    // tick immediately recreate that state while end credits keep playing.
    if (session.currentMovieMarkedAsFinished &&
        session.currentLocalMovieImdbId != null) {
      return;
    }

    final aspectStr = AspectModeUtils.aspectModeToString(session.aspectMode);
    // While the user is holding for temporary 2x boost, persist the prior speed
    // so a kill/dispose mid-hold doesn't strand 2x as the resume value.
    final persistedSpeed = session.speedBeforeHold ?? session.playbackSpeed;

    // Save to enhanced playback state system
    try {
      final seriesPlaylist = session.seriesPlaylist;
      if (seriesPlaylist != null && seriesPlaylist.isSeries) {
        // For series content
        if (session.currentIndex >= 0 &&
            session.currentIndex < session.activePlaylist!.length) {
          final currentEpisode = seriesPlaylist.allEpisodes.firstWhere(
            (episode) => episode.originalIndex == session.currentIndex,
            orElse: () => seriesPlaylist.allEpisodes.first,
          );

          if (currentEpisode.seriesInfo.season != null &&
              currentEpisode.seriesInfo.episode != null) {
            await PlaybackProgressStore.saveSeriesPlaybackState(
              seriesTitle: seriesPlaylist.seriesTitle ?? 'Unknown Series',
              season: currentEpisode.seriesInfo.season!,
              episode: currentEpisode.seriesInfo.episode!,
              positionMs: pos.inMilliseconds,
              durationMs: dur.inMilliseconds,
              speed: persistedSpeed,
              aspect: aspectStr,
              imdbId: seriesPlaylist.imdbId ?? session.contentImdbId,
            );
          }
        }
      } else {
        // For non-series content
        if (session.activePlaylist != null &&
            session.activePlaylist!.isNotEmpty) {
          PlaylistEntry? currentEntry;
          if (session.currentIndex >= 0 &&
              session.currentIndex < session.activePlaylist!.length) {
            currentEntry = session.activePlaylist![session.currentIndex];
          }

          if (currentEntry != null) {
            final resumeId = idForEntry(currentEntry);
            debugPrint(
              'Resume Save: storing state resumeId=$resumeId pos=${pos.inMilliseconds} dur=${dur.inMilliseconds}',
            );
            String currentVideoUrl = '';
            if (session.currentStreamUrl != null &&
                session.currentStreamUrl!.isNotEmpty) {
              currentVideoUrl = session.currentStreamUrl!;
            } else if (currentEntry.url.isNotEmpty) {
              currentVideoUrl = currentEntry.url;
            } else if (session.videoUrl.isNotEmpty) {
              currentVideoUrl = session.videoUrl;
            }

            await PlaybackProgressStore.saveVideoPlaybackState(
              videoTitle: resumeId,
              videoUrl: currentVideoUrl,
              positionMs: pos.inMilliseconds,
              durationMs: dur.inMilliseconds,
              speed: persistedSpeed,
              aspect: aspectStr,
              imdbId: session.contentImdbId,
            );

            // ALSO save in collection format for playlist progress tracking
            // This allows the playlist screen to display progress indicators
            debugPrint(
              '💾 Collection Save Check: seriesPlaylist=${seriesPlaylist != null}, seriesTitle="${seriesPlaylist?.seriesTitle}", isSeries=${seriesPlaylist?.isSeries}',
            );
            if (seriesPlaylist != null && seriesPlaylist.seriesTitle != null) {
              // Parse season/episode from filename for consistent progress tracking across view modes
              final seriesInfo = SeriesParser.parseFilename(currentEntry.title);
              final season = seriesInfo.season ?? 0;
              final episode = seriesInfo.episode ?? (session.currentIndex + 1);

              await PlaybackProgressStore.saveSeriesPlaybackState(
                seriesTitle: seriesPlaylist.seriesTitle!,
                season: season, // Parsed from filename, fallback to 0
                episode: episode, // Parsed from filename, fallback to index
                positionMs: pos.inMilliseconds,
                durationMs: dur.inMilliseconds,
                speed: persistedSpeed,
                aspect: aspectStr,
                imdbId: seriesPlaylist.imdbId ?? session.contentImdbId,
              );
              debugPrint(
                '✅ Collection Save: title="${seriesPlaylist.seriesTitle}" S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')} (index=${session.currentIndex}) filename="${currentEntry.title}"',
              );
            } else {
              debugPrint(
                '❌ Collection Save SKIPPED: seriesPlaylist is null or has no title',
              );
            }
          }
        } else {
          // Single video file (no playlist)
          // If it's a series episode (from Quick Play next episode), save as series state
          if (session.effectiveContentType == 'series' &&
              session.effectiveContentSeason != null &&
              session.effectiveContentEpisode != null) {
            await PlaybackProgressStore.saveSeriesPlaybackState(
              seriesTitle: session.effectiveContentTitle ?? session.title,
              season: session.effectiveContentSeason!,
              episode: session.effectiveContentEpisode!,
              positionMs: pos.inMilliseconds,
              durationMs: dur.inMilliseconds,
              speed: persistedSpeed,
              aspect: aspectStr,
              imdbId: session.effectiveContentImdbId,
            );
          } else {
            final currentUrl =
                (session.currentStreamUrl != null &&
                    session.currentStreamUrl!.isNotEmpty)
                ? session.currentStreamUrl!
                : session.videoUrl;
            final title = session.currentStremioTvContentTitle ?? session.title;
            final videoTitle = title.isNotEmpty ? title : 'Unknown Video';

            await PlaybackProgressStore.saveVideoPlaybackState(
              videoTitle: videoTitle,
              videoUrl: currentUrl,
              positionMs: pos.inMilliseconds,
              durationMs: dur.inMilliseconds,
              speed: persistedSpeed,
              aspect: aspectStr,
              imdbId: session.effectiveContentImdbId,
            );
          }
        }
      }
    } catch (e) {
      // Origin: swallow — enhanced persist must not block the legacy upsert.
    }

    // Also save to legacy system for backward compatibility
    await StorageService.upsertVideoResume(key, {
      'positionMs': pos.inMilliseconds,
      'speed': persistedSpeed,
      'aspect': aspectStr,
      'durationMs': dur.inMilliseconds,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    });
  }
}

enum _ResumeWaitOutcome { elapsed, stop }

/// One verification run owns its waits through completion or cancellation.
class _ResumeVerificationJob {
  _ResumeVerificationJob(this.targetMs, this.epoch);

  final int targetMs;
  final int epoch;
  bool _cancelled = false;
  Timer? _timer;
  Completer<_ResumeWaitOutcome>? _waiting;
  final Completer<void> _settled = Completer<void>();

  bool get cancelled => _cancelled;
  Future<void> get settled => _settled.future;

  Future<_ResumeWaitOutcome> wait(Duration duration) async {
    if (_cancelled) return _ResumeWaitOutcome.stop;
    final waiting = Completer<_ResumeWaitOutcome>();
    _waiting = waiting;
    _timer = Timer(duration, () {
      if (!waiting.isCompleted) waiting.complete(_ResumeWaitOutcome.elapsed);
    });
    try {
      final outcome = await waiting.future;
      // Cancellation wins even if the timer fired before this continuation.
      return _cancelled ? _ResumeWaitOutcome.stop : outcome;
    } finally {
      if (identical(_waiting, waiting)) {
        _waiting = null;
        _timer = null;
      }
    }
  }

  void cancel() {
    _cancelled = true;
    _timer?.cancel();
    final waiting = _waiting;
    if (waiting != null && !waiting.isCompleted) {
      waiting.complete(_ResumeWaitOutcome.stop);
    }
  }

  void finish() {
    if (!_settled.isCompleted) _settled.complete();
  }
}
