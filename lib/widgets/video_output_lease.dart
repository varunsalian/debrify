import 'dart:async';

import 'package:flutter/foundation.dart';

/// Serialises creation of media_kit video outputs, of which this process may
/// hold exactly **one** at a time.
///
/// On tvOS a second `VideoOutput` constructed while another is alive aborts the
/// process — a SIGABRT inside the second one's constructor, at
/// `enableHardwareAcceleration`. That is not hypothetical: it is the crash seen
/// when the Home hero's trailer engine was still alive as the content player
/// built its own controller.
///
/// Ordering alone does not fix it. Teardown defers the native release to a
/// post-frame callback and does not await it, and `VideoOutputManager.Dispose`
/// is itself asynchronous — so "tear the old one down, then build the new one"
/// is a race that a delay only narrows. This makes the handoff explicit: the
/// next owner cannot begin until the previous owner's disposal has actually
/// completed.
///
/// ## Waiting, not bypassing
///
/// There is deliberately no timeout that gives up and proceeds. Proceeding is
/// precisely the two-output case this exists to prevent, so a bypass would
/// reintroduce the crash under exactly the conditions that make it most likely
/// (a slow disposal). Safety comes instead from the lease being impossible to
/// leak:
///
///   * the handle is idempotent, so a double release is harmless;
///   * every early return after acquiring releases;
///   * disposers release from `whenComplete`, so even a *failed* dispose frees
///     the slot.
///
/// A wait longer than [_warnAfter] logs, so a leak surfaces as a diagnostic
/// rather than as a silent hang.
///
/// Engines that do not create a media_kit output — Android TV's ExoPlayer path
/// — must not take the lease. They have their own decoder discipline and a
/// different failure mode (a starved hardware codec pool, not an abort).
class VideoOutputLease {
  VideoOutputLease._();

  static const Duration _warnAfter = Duration(seconds: 3);

  /// Completes when the current holder releases. Null when the slot is free.
  static Completer<void>? _holder;

  /// Waits for the slot, then takes it. Release the returned handle when the
  /// output has been disposed — not merely when disposal was requested.
  static Future<VideoOutputLeaseHandle> acquire({String debugLabel = ''}) async {
    final waitedFrom = _holder == null ? null : DateTime.now();
    // A loop, not a single await: several callers can be parked on the same
    // future, and only one of them can win the slot when it completes.
    while (_holder != null) {
      await _holder!.future;
    }
    if (waitedFrom != null) {
      final waited = DateTime.now().difference(waitedFrom);
      if (waited >= _warnAfter) {
        debugPrint(
          'VideoOutputLease: $debugLabel waited ${waited.inMilliseconds}ms — '
          'a previous video output was slow to release, or leaked.',
        );
      }
    }
    final c = Completer<void>();
    _holder = c;
    return VideoOutputLeaseHandle._(c);
  }

  /// Whether anything currently holds the slot. Diagnostics only.
  @visibleForTesting
  static bool get isHeld => _holder != null;

  @visibleForTesting
  static void debugReset() {
    final held = _holder;
    _holder = null;
    if (held != null && !held.isCompleted) held.complete();
  }
}

/// A taken lease. Releasing twice is a no-op, which is what makes it safe to
/// release from every exit path without tracking which one ran.
class VideoOutputLeaseHandle {
  VideoOutputLeaseHandle._(this._completer);

  final Completer<void> _completer;
  bool _released = false;

  bool get released => _released;

  void release() {
    if (_released) return;
    _released = true;
    if (VideoOutputLease._holder == _completer) {
      VideoOutputLease._holder = null;
    }
    if (!_completer.isCompleted) _completer.complete();
  }
}
