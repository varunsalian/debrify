import 'dart:async';

import 'package:debrify/screens/video_player/constants/timing_constants.dart';
import 'package:debrify/screens/video_player/services/playback_ui_clock.dart';
import 'package:flutter/foundation.dart';

abstract interface class VpDebrifyTvBannerHost {
  bool get anyPlayerOverlayOpen;
  ValueNotifier<bool> get controlsVisible;
  bool get debrifyBannerFloatingMounted;
  set debrifyBannerFloatingMounted(bool v);
  bool get debrifyTvOwnsIdentity;
  bool get isTransitioning;
  PlaybackUiClockController get playbackUiClock;
  bool get showDebrifyBanner;
  set showDebrifyBanner(bool v);
  bool get mounted;
  void setState(VoidCallback fn);
  bool get hideSeekbar;
}

class VpDebrifyTvBanner {
  VpDebrifyTvBanner(this._host);
  final VpDebrifyTvBannerHost _host;

  Timer? debrifyBannerTimer;

  /// The clock is an optimization gate — it only publishes while something
  /// on screen reads it. That used to mean "the bar"; the floating Debrify
  /// banner's progress row reads it too (only when the session shows
  /// progress at all).
  void syncPlaybackClockVisibility() {
    _host.playbackUiClock.setVisible(
      _host.controlsVisible.value ||
          (_host.showDebrifyBanner &&
              _host.debrifyTvOwnsIdentity &&
              !_host.hideSeekbar),
    );
  }

  /// Raises the floating lower-third (tune, zap, launch). The hide timer
  /// re-arms while a channel switch is still resolving — the old corner
  /// badges timed out DURING the resolve, which is why tvOS never saw them.
  void raiseDebrifyBanner() {
    if (!_host.debrifyTvOwnsIdentity) return;
    if (_host.anyPlayerOverlayOpen || _host.controlsVisible.value) return;
    debrifyBannerTimer?.cancel();
    _host.setState(() {
      _host.showDebrifyBanner = true;
      _host.debrifyBannerFloatingMounted = true;
    });
    syncPlaybackClockVisibility();
    armDebrifyBannerTimer();
  }

  void armDebrifyBannerTimer() {
    // While resolving, poll fast — so the FULL display window is granted
    // from (roughly) the moment the new stream lands, not from zap start.
    final resolving = _host.isTransitioning;
    debrifyBannerTimer = Timer(
      resolving
          ? const Duration(milliseconds: 400)
          : VideoPlayerTimingConstants.badgeDisplayDuration,
      () {
        if (!_host.mounted) return;
        if (resolving || _host.isTransitioning) {
          // Either this was a resolve-poll, or a new switch began
          // mid-window: keep the identity up and re-evaluate.
          armDebrifyBannerTimer();
          return;
        }
        _host.setState(() => _host.showDebrifyBanner = false);
        syncPlaybackClockVisibility();
      },
    );
  }

  void hideDebrifyBanner({bool immediate = false}) {
    debrifyBannerTimer?.cancel();
    if (!_host.showDebrifyBanner &&
        !(immediate && _host.debrifyBannerFloatingMounted)) {
      return;
    }
    _host.setState(() {
      _host.showDebrifyBanner = false;
      if (immediate) _host.debrifyBannerFloatingMounted = false;
    });
    syncPlaybackClockVisibility();
  }
}
