import 'dart:async';

class StartupStreamPolicy {
  static const Duration aioStreamsErrorSlateMaxDuration = Duration(minutes: 3);

  /// Channel playback keeps the player's own network/error handling. Other
  /// initial playback retains its startup validator. Manual source picks have
  /// a separate validation path and must not use this initial-open routing.
  static Future<bool> openInitialMedia({
    required bool hasResolvedUrl,
    required bool hasExternalAudio,
    required bool isLiveIptv,
    required bool isStremioTv,
    required Future<void> Function() openDirect,
    required Future<bool> Function() openValidated,
  }) async {
    if (hasResolvedUrl && (hasExternalAudio || isLiveIptv || isStremioTv)) {
      await openDirect();
      return true;
    }
    return openValidated();
  }

  static bool isAioStreams({String? addonId, String? sourceName, String? url}) {
    final identity = [
      addonId,
      sourceName,
      Uri.tryParse(url ?? '')?.host,
    ].whereType<String>().join(' ').toLowerCase();
    return identity.contains('aiostreams');
  }

  static bool isLikelyAioStreamsErrorSlate({
    String? addonId,
    String? sourceName,
    String? url,
    required Duration duration,
  }) {
    return duration > Duration.zero &&
        duration < aioStreamsErrorSlateMaxDuration &&
        isAioStreams(addonId: addonId, sourceName: sourceName, url: url);
  }

  /// Whether a resolved fallback playlist must prove it contains the exact
  /// requested episode. Only multi-file series packs can silently substitute
  /// the wrong episode; a singleton was already episode-scoped by the search
  /// that found it, and its lone filename often has no parseable SxxEyy.
  static bool requiresExactEpisodeMatch({
    required bool isSeries,
    required int playlistLength,
  }) {
    return isSeries && playlistLength > 1;
  }

  /// Returns the exact resolved row to open. Series fallbacks must prove that
  /// they contain the requested episode; other VOD playlists start at row 0.
  static int? resolvedPlaylistIndex({
    required bool requiresEpisodeMatch,
    int? matchedEpisodeIndex,
  }) {
    if (!requiresEpisodeMatch) return 0;
    if (matchedEpisodeIndex == null || matchedEpisodeIndex < 0) return null;
    return matchedEpisodeIndex;
  }

  static ({int sourceIndex, int attempts}) rankedFailoverStart({
    required int selectedSourceIndex,
    required bool initialAttemptAlreadyFailed,
  }) {
    return (
      sourceIndex: selectedSourceIndex + (initialAttemptAlreadyFailed ? 1 : 0),
      attempts: initialAttemptAlreadyFailed ? 1 : 0,
    );
  }

  /// PikPak may enqueue cold storage before resolution returns. Therefore an
  /// empty/failed initial resolution still consumes the session's single
  /// torrent-acquisition allowance.
  static bool initialPikPakAcquisitionAttempted({
    required bool isPikPakResolver,
    required bool initialSourceIsTorrent,
    required bool hasResolvedInitialUrl,
    required bool initialAttemptAlreadyFailed,
  }) {
    return isPikPakResolver &&
        initialSourceIsTorrent &&
        (hasResolvedInitialUrl || initialAttemptAlreadyFailed);
  }
}

/// Keeps a channel's initial slot position until duration becomes available.
/// A new media open or a user seek cancels it; duration updates consume it once.
class DeferredStartupSeek {
  double? _fraction;
  int? _epoch;

  void arm(double? fraction, {required int epoch}) {
    _fraction = fraction != null && fraction > 0
        ? fraction.clamp(0.0, 0.99)
        : null;
    _epoch = epoch;
  }

  Duration? take(Duration duration, {required int epoch}) {
    if (epoch != _epoch) cancel();
    final fraction = _fraction;
    if (fraction == null || duration <= Duration.zero) return null;
    cancel();
    final milliseconds = (duration.inMilliseconds * fraction).floor();
    return milliseconds > 0 ? Duration(milliseconds: milliseconds) : null;
  }

  /// A renderer rebuild opens the same media under a new epoch. Never revive
  /// a position already consumed or cancelled by navigation or a user seek.
  void carryTo({required int fromEpoch, required int toEpoch}) {
    if (_epoch == fromEpoch) {
      _epoch = toEpoch;
    } else {
      cancel();
    }
  }

  void cancel() {
    _fraction = null;
    _epoch = null;
  }
}

/// Observes an initial channel open without imposing a network deadline.
/// media-kit reports connection failures on its error stream after open()
/// returns. Stop observing once video actually advances or the media changes.
class ChannelStartupWatch {
  ChannelStartupWatch({
    required Stream<String> errors,
    required Stream<int?> widths,
    required Stream<Duration> positions,
    required Stream<Duration> durations,
    required Stream<bool> completed,
    required this.isCurrent,
    required this.onFailure,
    this.onReady,
    String? addonId,
    String? sourceName,
    String? url,
    bool Function(String error)? shouldDeferError,
  }) : _isAioStreams = StartupStreamPolicy.isAioStreams(
         addonId: addonId,
         sourceName: sourceName,
         url: url,
       ) {
    _subscriptions.addAll([
      errors.listen((error) {
        if (isCurrent() && shouldDeferError?.call(error) == true) return;
        fail();
      }),
      widths.listen((width) {
        _width = width ?? 0;
        _checkPlayback();
      }),
      positions.listen((position) {
        _position = position;
        _checkPlayback();
      }),
      durations.listen((duration) {
        _duration = duration;
        _checkPlayback();
      }),
      completed.listen((done) {
        if (done && _isAioStreams && _pending) fail();
      }),
    ]);
  }

  final bool Function() isCurrent;
  final void Function() onFailure;
  final void Function()? onReady;
  final bool _isAioStreams;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  bool _pending = true;
  bool _failed = false;
  bool _accepted = false;
  int _width = 0;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Timer? _durationGrace;

  bool get isPending => _pending;
  bool get hasFailed => _failed;
  // Disposal alone must not release an unvalidated clip's final checkpoint.
  bool get blocksProgress => _isAioStreams && !_accepted;

  void _checkPlayback() {
    if (!_pending) return;
    if (!isCurrent()) {
      dispose();
      return;
    }
    if (_isAioStreams &&
        _duration > Duration.zero &&
        _duration < StartupStreamPolicy.aioStreamsErrorSlateMaxDuration) {
      fail();
      return;
    }
    if (_width > 0 && _position.inMilliseconds >= 40) {
      if (_isAioStreams && _duration <= Duration.zero) {
        // Match the VOD validator's metadata grace after playback starts.
        // This never times out a channel still waiting for its first data.
        _durationGrace ??= Timer(const Duration(seconds: 1), _accept);
      } else {
        _accept();
      }
    }
  }

  void _accept() {
    if (!_pending) return;
    if (!isCurrent()) {
      dispose();
      return;
    }
    _accepted = true;
    dispose();
    onReady?.call();
  }

  void fail() {
    if (!_pending) return;
    final current = isCurrent();
    _failed = current;
    dispose();
    if (current) onFailure();
  }

  void dispose() {
    _pending = false;
    _durationGrace?.cancel();
    _durationGrace = null;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
  }
}
