import 'dart:async';

/// Phase 2 of the IPTV playback-resilience plan (dev/design/plans/
/// IPTV_FLAWLESS_PLAYBACK_PLAN.md): the ONE recovery state machine for live
/// IPTV playback in the Dart player — the mirror of the native player's
/// `IptvLiveRecovery.kt`, same episode semantics.
///
/// Every recovery source feeds this machine and nothing else re-tunes on its
/// own: live EOF (mpv `completed`), stream errors, the stall detector, and
/// the user's retry. One machine means one ladder — no two sources can ever
/// schedule competing re-opens.
///
/// Shape of a recovery episode:
///  - something fails → re-tune attempts at 0/1/3/5s, then every 10s;
///  - the episode turns VISIBLE (reconnect pill) once it has run ~2s — a
///    first instant re-tune that works stays invisible, which is the point;
///  - recovery is confirmed by [onProgress] advancing for [stableWindow] —
///    only then does the attempt counter reset. A stream that dies again in
///    5 seconds keeps climbing the ladder instead of hammering the origin;
///  - [surrenderBudget] of failing ends the episode in a surrendered state
///    with a visible retry affordance.
///
/// Eligibility is the owner's business ([isEligible]): current channel is
/// live, no zap superseded us (the switch ticket), playback is wanted. The
/// machine re-checks at every decision point.
class IptvLiveRecovery {
  IptvLiveRecovery({
    required this.isEligible,
    required this.performRetune,
    required this.onEpisodeVisible,
    required this.onRecovered,
    required this.onSurrender,
    this.now = DateTime.now,
  });

  /// Injectable clock: tests drive it with fake_async's zone clock
  /// (`DateTime.now()` is NOT faked by fake_async, `clock.now()` is).
  final DateTime Function() now;

  /// May this machine act right now? Re-checked before every attempt.
  final bool Function() isEligible;

  /// Re-open the CURRENT live channel (same URL + headers, live edge).
  final void Function(String source, int attempt) performRetune;

  /// The episode has run long enough to narrate ("Reconnecting…").
  final void Function(int attempt) onEpisodeVisible;

  /// Playback is back — hide the pill.
  final void Function() onRecovered;

  /// The machine gives up — visible failure state with a retry path.
  final void Function(String source) onSurrender;

  static const List<Duration> delays = [
    Duration.zero,
    Duration(seconds: 1),
    Duration(seconds: 3),
    Duration(seconds: 5),
  ];
  static const Duration lateDelay = Duration(seconds: 10);
  static const Duration stableWindow = Duration(seconds: 15);
  static const Duration visibleAfter = Duration(seconds: 2);
  static const Duration surrenderBudget = Duration(seconds: 75);

  /// No position advance for this long while playback is wanted =
  /// post-open stall (wedged demuxer, stopped byte flow).
  static const Duration stallWindow = Duration(seconds: 12);

  /// A tune that never produces a first frame at all gets this long before
  /// the machine re-tunes (mirror of the Kotlin pre-READY watchdog — codex
  /// round 2, finding 11: without it a socket that opens but never yields a
  /// frame or an error leaves the phone black forever).
  static const Duration tuneWatchdog = Duration(seconds: 20);

  /// Events landing within this of a re-tune are the OLD stream's queued
  /// death throes (a stale completed/error delivered while the new open is
  /// starting) — acting on them would double-schedule (codex r2, finding 2).
  static const Duration retuneDebounce = Duration(milliseconds: 300);

  /// True after the machine gave up; cleared by [userRetry] or a real zap.
  bool get isSurrendered => _surrendered;
  bool _surrendered = false;

  /// True while a recovery episode is open (for the owner's UI decisions).
  bool get episodeActive => _episodeActive;
  bool _episodeActive = false;

  late DateTime _episodeStart = now();
  bool _episodeVisible = false;
  int _attempt = 0;
  Timer? _pending;

  bool _firstFrameSeen = false;
  Duration _lastPosition = const Duration(milliseconds: -1);
  late DateTime _lastAdvance = now();
  DateTime? _stableSince;
  Timer? _tuneWatchdogTimer;
  DateTime? _lastRetuneAt;

  /// Set by the owner around a machine-driven re-open so [onTuneStarted]
  /// keeps the recovery episode instead of resetting it.
  bool expectRetune = false;

  // ── inputs ──────────────────────────────────────────────────────────────

  /// Every live media hand-off (zap, launch, recovery re-open). A real zap
  /// is a fresh start: any episode in progress belonged to the old tune.
  void onTuneStarted() {
    _firstFrameSeen = false;
    _lastPosition = const Duration(milliseconds: -1);
    _lastAdvance = now();
    _stableSince = null;
    _armTuneWatchdog();
    if (expectRetune) {
      expectRetune = false;
      return; // recovery's own re-open: the episode continues
    }
    _cancelPending();
    _episodeActive = false;
    _episodeVisible = false;
    _attempt = 0;
    _surrendered = false;
  }

  void _armTuneWatchdog() {
    _tuneWatchdogTimer?.cancel();
    _tuneWatchdogTimer = Timer(tuneWatchdog, () {
      _tuneWatchdogTimer = null;
      if (_firstFrameSeen || _surrendered || _pending != null) return;
      _requestRecovery('tune-watchdog');
    });
  }

  /// First sized frame — playback is visibly back.
  void onFirstFrame() {
    _firstFrameSeen = true;
    _tuneWatchdogTimer?.cancel();
    _tuneWatchdogTimer = null;
    if (_episodeActive) onRecovered();
  }

  /// Fed by the position stream. [wantsPlayback] must be "playback is
  /// wanted" (not user-paused) — a buffering wedge must count as a stall,
  /// a user pause must not.
  void onProgress(Duration position, {required bool wantsPlayback}) {
    final nowTs = now();
    if (position != _lastPosition) {
      _lastPosition = position;
      _lastAdvance = nowTs;
      // Advancing position IS playback — audio-only channels never produce
      // sized video params, and recovery must still count as recovered for
      // them (codex round 2, finding 12).
      if (!_firstFrameSeen && position > Duration.zero) {
        onFirstFrame();
      }
      if (_firstFrameSeen && wantsPlayback) {
        _stableSince ??= nowTs;
        if (_episodeActive && nowTs.difference(_stableSince!) >= stableWindow) {
          // Recovered for real: close the episode.
          _episodeActive = false;
          _episodeVisible = false;
          _attempt = 0;
        }
      }
      return;
    }
    _stableSince = null;
    if (!wantsPlayback || _surrendered || _pending != null) return;
    if (!_firstFrameSeen) return; // pre-open covered by open()'s own throw/error
    if (nowTs.difference(_lastAdvance) >= stallWindow) {
      _requestRecovery('stall');
    }
  }

  /// Live EOF — the origin closed the connection. Returns true when the
  /// machine takes ownership of what happens next.
  bool onEnded() {
    if (!isEligible()) return false;
    return _requestRecovery('ended');
  }

  /// A stream error mpv reported. Returns true when the machine takes
  /// ownership (the owner keeps its snackbar for the surrendered case).
  bool onError() {
    if (!isEligible()) return false;
    return _requestRecovery('error');
  }

  /// The user asked (retry action, lifecycle rejoin): fresh budget,
  /// immediate attempt.
  void userRetry(String source) {
    _cancelPending();
    _surrendered = false;
    _episodeActive = true;
    _episodeStart = now();
    _episodeVisible = false;
    _attempt = 0;
    _fire(source, immediate: true);
  }

  /// A real zap, playback teardown, or leaving the screen.
  void cancel() {
    _cancelPending();
    _tuneWatchdogTimer?.cancel();
    _tuneWatchdogTimer = null;
    _episodeActive = false;
    _episodeVisible = false;
    _attempt = 0;
    _surrendered = false;
  }

  // ── engine ──────────────────────────────────────────────────────────────

  bool _requestRecovery(String source) {
    if (_surrendered || _pending != null) return true; // already on it
    final lastRetune = _lastRetuneAt;
    if (lastRetune != null && now().difference(lastRetune) < retuneDebounce) {
      return true; // stale delivery from the stream we just replaced
    }
    if (!isEligible()) return false;
    final nowTs = now();
    if (!_episodeActive) {
      _episodeActive = true;
      _episodeStart = nowTs;
    }
    if (nowTs.difference(_episodeStart) > surrenderBudget) {
      _surrender(source);
      return true;
    }
    _fire(source, immediate: false);
    return true;
  }

  void _fire(String source, {required bool immediate}) {
    _attempt++;
    final delay = immediate
        ? Duration.zero
        : (_attempt - 1 < delays.length ? delays[_attempt - 1] : lateDelay);
    _maybeShowPill();
    _pending = Timer(delay, () {
      _pending = null;
      if (_surrendered || !isEligible()) return;
      _maybeShowPill();
      _lastRetuneAt = now();
      performRetune(source, _attempt);
    });
  }

  void _maybeShowPill() {
    if (!_episodeActive || _episodeVisible) return;
    if (now().difference(_episodeStart) >= visibleAfter ||
        _attempt >= 2) {
      _episodeVisible = true;
      onEpisodeVisible(_attempt);
    }
  }

  void _surrender(String source) {
    _cancelPending();
    _surrendered = true;
    _episodeActive = false;
    _episodeVisible = false;
    onSurrender(source);
  }

  void _cancelPending() {
    _pending?.cancel();
    _pending = null;
  }
}
