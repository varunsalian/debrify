import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart' as mk;

import 'player_transport_visibility.dart';

/// Owns TV scrub state, input admission and invalidation; borrows UI resources.
class PlayerScrubSession {
  PlayerScrubSession({
    required mk.Player Function() readPlayer,
    required Duration Function() readPosition,
    required Duration Function() readDuration,
    required bool Function() readIsPlaying,
    required bool Function() readNoTimeline,
    required bool Function() isMounted,
    required bool Function() anyOverlayOpen,
    required void Function(VoidCallback) commitState,
    required ValueChanged<Duration> onSeek,
    required PlayerTransportVisibility transport,
    required FocusNode progressFocus,
    required FocusNode playPauseFocus,
  }) : _readPlayer = readPlayer,
       _readPosition = readPosition,
       _readDuration = readDuration,
       _readIsPlaying = readIsPlaying,
       _readNoTimeline = readNoTimeline,
       _isMounted = isMounted,
       _anyOverlayOpen = anyOverlayOpen,
       _commitState = commitState,
       _onSeek = onSeek,
       _transport = transport,
       _progressFocus = progressFocus,
       _playPauseFocus = playPauseFocus;

  // Reads stay lazy: media transitions can replace the player between events.
  final mk.Player Function() _readPlayer;
  final Duration Function() _readPosition;
  final Duration Function() _readDuration;
  final bool Function() _readIsPlaying;
  final bool Function() _readNoTimeline;
  final bool Function() _isMounted;
  final bool Function() _anyOverlayOpen;
  final void Function(VoidCallback) _commitState;
  final ValueChanged<Duration> _onSeek;
  final PlayerTransportVisibility _transport;
  final FocusNode _progressFocus;
  final FocusNode _playPauseFocus;

  /// Cinema scrub, matching the native TV player: holding LEFT/RIGHT pauses
  /// playback and previews a destination that OK confirms and BACK cancels.
  /// [_target] non-null means a scrub is in flight.
  Duration? _target;

  /// When the last LEFT/RIGHT arrived, so a held key (fast repeats) can be
  /// told from deliberate taps without needing key-up, which the tvOS fork
  /// does not reliably deliver.
  DateTime? _lastArrowAt;
  bool _wasPlaying = false;
  int _repeats = 0;

  /// Bumped on every transition and on dispose. A confirm carrying a stale
  /// generation is dropped, so a scrub started before a source switch can
  /// never seek the item that replaced it.
  int _generation = 0;

  /// The generation in force when the current scrub began.
  int _startedGeneration = 0;

  Duration? get preview => _target;

  void invalidateAndAbandon() {
    _generation++;
    _abandon();
  }

  // Disposal bumps only; unlike media replacement it does not clear the preview.
  void invalidateOnly() => _generation++;

  bool handleActiveKey(LogicalKeyboardKey key) {
    if (_target == null) return false;
    final isLeft = key == LogicalKeyboardKey.arrowLeft;
    final isRight = key == LogicalKeyboardKey.arrowRight;
    final activate = <LogicalKeyboardKey>{
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.numpadEnter,
      LogicalKeyboardKey.select,
      LogicalKeyboardKey.gameButtonA,
    };
    final isBack =
        key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack;
    if (isLeft || isRight) {
      _step(isRight ? 1 : -1);
    } else if (activate.contains(key)) {
      _confirm();
    } else if (isBack || key == LogicalKeyboardKey.arrowDown) {
      cancel();
    }
    return true;
  }

  bool handleHiddenArrow(int direction) {
    // Third quick arrow enters scrub; slower taps keep their ordinary nudges.
    final now = DateTime.now();
    final last = _lastArrowAt;
    _repeats =
        (last != null && now.difference(last).inMilliseconds < 400)
        ? _repeats + 1
        : 0;
    _lastArrowAt = now;
    if (_repeats >= 2 && _readDuration() > Duration.zero) {
      _repeats = 0;
      begin(direction);
      return true;
    }
    return false;
  }

  /// Cinema scrub: hold LEFT/RIGHT to pause and preview a destination, OK to
  /// confirm, BACK/DOWN to cancel. One seek on confirm, so the trackers and
  /// resume see a single jump instead of a burst.
  void begin(int direction) {
    if (_readNoTimeline()) return;
    _startedGeneration = _generation;
    _wasPlaying = _readIsPlaying();
    if (_readIsPlaying()) _readPlayer().pause();
    _target = _readPosition();
    _transport.showBar();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isMounted() && _target != null) _progressFocus.requestFocus();
    });
    _step(direction);
  }

  void _step(int direction) {
    final base = _target;
    if (base == null) return;
    // Accelerate with the hold: fine control at first, then long strides so a
    // two-hour remux is crossable without holding the key for a minute.
    final step = _repeats < 8
        ? 10
        : _repeats < 16
        ? 30
        : 60;
    _repeats++;
    final next = base + Duration(seconds: step * direction);
    _commitState(() {
      _target = next < Duration.zero
          ? Duration.zero
          : (next > _readDuration() ? _readDuration() : next);
    });
    _transport.scheduleAutoHide();
  }

  void _confirm() {
    final target = _target;
    // Captured when the scrub STARTED. Reading it here would always match and
    // the guard would never fire — a scrub begun before a source switch would
    // happily seek whatever replaced it.
    final generation = _startedGeneration;
    if (target == null) return;
    _commitState(() => _target = null);
    _repeats = 0;
    // A source switch or dispose bumps the generation; a confirm that lands
    // afterwards must not seek whatever replaced the item being scrubbed.
    if (generation != _generation || !_isMounted()) return;
    _readPlayer().seek(target);
    _onSeek(target);
    if (_wasPlaying) _readPlayer().play();
    if (!_anyOverlayOpen()) _playPauseFocus.requestFocus();
    // Fresh interval: the countdown that was running belonged to the scrub,
    // and inheriting its remainder could drop the bar the instant OK lands.
    _transport.scheduleAutoHide();
  }

  /// Drop a scrub without seeking and without touching playback — the item it
  /// belonged to is going away. Restoring "was playing" here would fight the
  /// transition, which drives play/pause itself.
  void _abandon() {
    if (_target == null) return;
    _target = null;
    _repeats = 0;
  }

  void cancel() {
    if (_target == null) return;
    _commitState(() => _target = null);
    _repeats = 0;
    if (_wasPlaying) _readPlayer().play();
    if (!_anyOverlayOpen()) _playPauseFocus.requestFocus();
    _transport.scheduleAutoHide();
  }
}
