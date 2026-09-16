/// A changed playlist is not proof that media opened successfully.
enum EpisodePlaybackOutcome { committed, unavailable, cancelled }

/// Keeps one episode request valid across its own playlist replacements while
/// rejecting cancellation and playlist changes initiated by another request.
class EpisodePlaybackRequest {
  EpisodePlaybackRequest({
    required this.currentIdentity,
    required this.isActive,
    this.currentNavigation,
  }) : _identity = currentIdentity(),
       _navigation = currentNavigation?.call();

  final int Function() currentIdentity;
  final bool Function() isActive;
  int _identity;
  final int Function()? currentNavigation;
  final int? _navigation;
  bool _mediaOpenStarted = false;

  bool get ownsPlaylist =>
      currentIdentity() == _identity &&
      currentNavigation?.call() == _navigation;
  bool get isCurrent => isActive() && ownsPlaylist;

  /// Call synchronously around a playlist mutation owned by this request.
  bool replacePlaylist(void Function() replace) {
    if (!isCurrent) return false;
    replace();
    _identity = currentIdentity();
    _mediaOpenStarted = false;
    return true;
  }

  /// Undo preparation only. Once native open starts, its media may already
  /// have replaced the outgoing stream, even if readiness fails or the request
  /// is cancelled. Keep that media's identity unless media is also restored.
  /// Never overwrite a newer navigation's playlist.
  bool restorePlaylist(void Function() restore) {
    if (!ownsPlaylist || _mediaOpenStarted) return false;
    restore();
    _identity = currentIdentity();
    return true;
  }

  Future<EpisodePlaybackOutcome> attempt(Future<bool> Function() load) async {
    if (!isCurrent) return EpisodePlaybackOutcome.cancelled;
    bool committed;
    try {
      committed = await load();
    } catch (_) {
      committed = false;
    }
    if (!isCurrent) return EpisodePlaybackOutcome.cancelled;
    return committed
        ? EpisodePlaybackOutcome.committed
        : EpisodePlaybackOutcome.unavailable;
  }

  /// Check at the actual media-open boundary, after asynchronous preparation.
  Future<bool> commit(Future<void> Function() open) async {
    if (!isCurrent) return false;
    // Mark before awaiting: native open can replace media before its Future
    // completes, and an exception does not guarantee the old media survived.
    _mediaOpenStarted = true;
    await open();
    return isCurrent;
  }
}

/// A timeout is a failed attempt, never proof that a source became playable.
Future<bool> waitForEpisodePlayback({
  required bool Function() isCurrent,
  required bool Function() isReady,
  bool Function()? isPaused,
  Future<void> Function()? wait,
  int attempts = 100,
}) async {
  var elapsedAttempts = 0;
  while (elapsedAttempts < attempts) {
    if (!isCurrent()) return false;
    if (isReady()) return true;
    // A user/lifecycle pause is not evidence of source failure. Resume the
    // timeout budget only when playback is allowed to progress again.
    final pausedBeforeWait = isPaused?.call() == true;
    await (wait?.call() ??
        Future<void>.delayed(const Duration(milliseconds: 100)));
    if (!pausedBeforeWait && isPaused?.call() != true) elapsedAttempts++;
  }
  return isCurrent() && isReady();
}
