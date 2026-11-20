import 'dart:async';

final class NativeScrobbleSession {
  static
  /// Trakt scrobble dedup guard for Android TV player (mirrors _traktLastScrobbleAction in VideoPlayerScreen)
  String? traktLastScrobbleAction;

  static double traktLastKnownProgress = 0.0;

  static int? traktLastKnownSeason;

  static int? traktLastKnownEpisode;

  static Timer? traktHeartbeatTimer;

  static
  /// Simkl scrobble state — fully parallel mirror of the Trakt vars above
  /// (independent dedup guard + heartbeat; the two trackers never share state).
  String? simklLastScrobbleAction;

  static double simklLastKnownProgress = 0.0;

  static int? simklLastKnownSeason;

  static int? simklLastKnownEpisode;

  static Timer? simklHeartbeatTimer;

  /// Forgets the Trakt session's dedup marker and last-known position.
  static void clearTraktState() {
    traktLastScrobbleAction = null;
    traktLastKnownProgress = 0.0;
    traktLastKnownSeason = null;
    traktLastKnownEpisode = null;
  }

  /// Forgets the Simkl session's dedup marker and last-known position.
  static void clearSimklState() {
    simklLastScrobbleAction = null;
    simklLastKnownProgress = 0.0;
    simklLastKnownSeason = null;
    simklLastKnownEpisode = null;
  }
}
