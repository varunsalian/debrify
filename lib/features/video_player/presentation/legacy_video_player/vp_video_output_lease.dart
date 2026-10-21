import 'dart:async';

import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/widgets/video_output_lease.dart';
import 'package:flutter/foundation.dart';

abstract interface class VpVideoOutputLeaseHost {
  bool get screenDisposed;
}

class VpVideoOutputLease {
  VpVideoOutputLease(this._host);
  final VpVideoOutputLeaseHost _host;

  /// This player's claim on the process's one video output.
  ///
  /// HELD for the controller's lifetime rather than taken as a momentary
  /// barrier. A barrier that released before construction left a gap: a trailer
  /// parked on the lease would be granted it and build its own output while
  /// this player was still constructing — the two-output case, which is a
  /// SIGABRT on tvOS.
  VideoOutputLeaseHandle? outputLease;

  /// Take the slot before building a controller.
  ///
  /// The ambient trailer surfaces tear down when playback launches, but the
  /// native release is asynchronous — "teardown was requested" is not "the
  /// output is gone".
  ///
  /// **Bounded, deliberately.** Review pushed back on this twice: a timeout
  /// that proceeds can, in principle, recreate the two-output case. The
  /// judgement here is that an unbounded wait turns a stuck native disposal
  /// into "video never plays again this session", which is a worse and far more
  /// likely outcome than the crash it guards against — and by the time three
  /// seconds have passed, something is already wrong. It logs, and it still
  /// takes the slot when it finally frees, so the player never ends up
  /// untracked.
  ///
  /// tvOS waits longer before giving up: proceeding into the overlap is a
  /// certain SIGABRT there, and since the native Dispose handshake became
  /// completion-gated (mpv render context freed before the channel call
  /// returns) a held lease reliably frees — a slow release is a wait, not a
  /// lockout.
  static final Duration outputLeaseTimeout = PlatformUtil.isTvOS
      ? const Duration(seconds: 10)
      : const Duration(seconds: 3);

  Future<void> claimVideoOutput() async {
    if (outputLease != null) return; // renderer fallback reuses the claim
    if (!VideoOutputLease.isHeld) {
      final handle = await VideoOutputLease.acquire(debugLabel: 'player');
      if (_host.screenDisposed) {
        handle.release();
        return;
      }
      outputLease = handle;
      return;
    }
    final pending = VideoOutputLease.acquire(debugLabel: 'player');
    VideoOutputLeaseHandle? handle;
    try {
      handle = await pending.timeout(outputLeaseTimeout);
    } on TimeoutException {
      debugPrint(
        'VideoOutputLease: player proceeding without the slot — a previous '
        'video output has not released after '
        '${outputLeaseTimeout.inSeconds}s.',
      );
      // The wait was abandoned, not cancelled. Take the slot whenever it does
      // arrive rather than handing it back: this player IS alive and holding a
      // video output, so releasing would leave it untracked and let a trailer
      // build a second one beside it.
      unawaited(
        pending.then((late) {
          if (_host.screenDisposed || outputLease != null) {
            late.release();
          } else {
            outputLease = late;
          }
        }),
      );
    }
    if (_host.screenDisposed) {
      handle?.release();
      return;
    }
    outputLease = handle;
  }

  void releaseVideoOutput() {
    outputLease?.release();
    outputLease = null;
  }
}
