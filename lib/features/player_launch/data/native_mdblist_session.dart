import 'package:debrify/features/player_launch/data/android_tv_playback_payload.dart';
import 'package:debrify/services/mdblist/mdblist_models.dart';
import 'package:debrify/services/mdblist/mdblist_scrobble_session.dart';
import 'package:debrify/services/mdblist/mdblist_service.dart';

final class NativeMdblistSession {
  /// A series frame whose season/episode hasn't been populated yet must not be
  /// scrobbled to Simkl — [SimklService._scrobble] would send the show id in a
  /// movie-shaped body, recording a bogus movie on the account. A movie
  /// legitimately reports (null, null), so this only blocks the series case.
  static bool simklSeriesSEUnresolved(
    AndroidTvPlaybackPayload payload,
    Map<String, dynamic> progress,
  ) {
    if (payload.trackingContentType != 'series') return false;
    return progress['season'] == null || progress['episode'] == null;
  }

  static MdblistScrobbleTarget? nativeMdblistTarget(
    AndroidTvPlaybackPayload payload, {
    int? season,
    int? episode,
  }) {
    final imdbId = payload.imdbId;
    if (imdbId == null || imdbId.isEmpty) return null;
    final ids = MdblistMediaIds.forContent(imdbId);
    if (payload.trackingContentType != 'series') {
      return MdblistScrobbleTarget.movie(ids);
    }
    if (season == null || episode == null) return null;
    return MdblistScrobbleTarget.episode(ids, season: season, episode: episode);
  }

  static Future<void> initializeNativeMdblist(
    AndroidTvPlaybackPayload payload, {
    MdblistService? service,
  }) async {
    service ??= MdblistService.instance;
    if (!payload.mdblistScrobble || !service.networkEnabled) return;
    if (payload.items.isEmpty) return;
    // Capture authorization at launch even if episode coordinates arrive later.
    // Session creation then stays synchronous and bound to this playback account.
    final capability = await service.capturePlaybackCapability();
    final playbackService = service;
    payload.mdblistSessionFactory = (target) => MdblistScrobbleSession.forService(
      service: playbackService,
      target: target,
      capability: capability,
    );
    final index = payload.startIndex.clamp(0, payload.items.length - 1);
    final item = payload.items[index];
    final target = NativeMdblistSession.nativeMdblistTarget(
      payload,
      season: item.season,
      episode: item.episode,
    );
    if (target != null) NativeMdblistSession.ensureNativeMdblistSession(payload, target);
  }

  static MdblistScrobbleSession? ensureNativeMdblistSession(
    AndroidTvPlaybackPayload payload,
    MdblistScrobbleTarget target,
  ) {
    if (payload.mdblistSession != null) return payload.mdblistSession;
    final create = payload.mdblistSessionFactory;
    if (create == null) return null;
    payload.mdblistSeason = target.season;
    payload.mdblistEpisode = target.episode;
    return payload.mdblistSession = create(target);
  }

  static Future<void> closeNativeMdblist(
    AndroidTvPlaybackPayload payload,
  ) async {
    // A late frame must not create another session after playback has ended.
    payload.mdblistSessionFactory = null;
    final session = payload.mdblistSession;
    payload.mdblistSession = null;
    payload.mdblistSeason = null;
    payload.mdblistEpisode = null;
    await session?.close();
  }
}
