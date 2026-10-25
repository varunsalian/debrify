import 'dart:async';

import 'package:debrify/screens/video_player/constants/timing_constants.dart';
import 'package:debrify/screens/video_player/widgets/iptv_channel_sheet.dart';
import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart' as mk;

abstract interface class VpControlsRuntimeHost {
  set activeMediaShouldPlay(bool v);
  set activeMediaUserPaused(bool v);
  bool get anyPlayerOverlayOpen;
  ValueNotifier<bool> get controlsVisible;
  bool get engineFlagOn;
  Timer? get hideTimer;
  set hideTimer(Timer? v);
  GlobalKey<IptvChannelSheetState> get iptvSheetKey;
  bool get isAnyOverlayOpen;
  bool get isPlaying;
  bool get isReady;
  mk.Player get player;
  GlobalKey<PlayerMenuPanelState> get playerMenuKey;
  Duration get position;
  bool get showChannelGuide;
  bool get showIptvChannelSheet;
  bool get showPlayerMenu;
  bool get showSourceSheet;
  bool get showStremioTvGuide;
  bool get showSyncOverlay;
  set sleepStopLatched(bool v);
  FocusScopeNode get tvBarScope;
  FocusNode get tvPlayPauseFocus;
  FocusNode get tvRootFocus;
  Duration? get tvScrubTarget;
  bool get mounted;
  BuildContext get context;
  void hideDebrifyBanner({bool immediate = false});
  void syncPlaybackClockVisibility();
  void hideChannelGuideOverlay();
  void hideIptvZapBanner({bool immediate = false});
  void syncIptvBannerTicker();
  void hideIptvChannelSheet();
  void hidePlayerMenu();
  Future<void> refreshEngineRecordingState();
  Future<void> saveResume({bool debounced = false, Duration? positionOverride});
  void hideSourceSheet();
  void hideStremioTvGuide();
  void hideSyncOverlay();
}

class VpControlsRuntime {
  VpControlsRuntime(this._host);
  final VpControlsRuntimeHost _host;

  /// Overlays inside the player share its route scope, which already has a
  /// focused child (the player root) — so their `autofocus` is silently
  /// discarded and the first OK does nothing. Releasing the current focus as
  /// the overlay appears lets its autofocus node claim it.
  void tvReleaseFocusForOverlay() {
    if (!PlatformUtil.isTelevision) return;
    FocusManager.instance.primaryFocus?.unfocus();
  }

  /// True while the auto-hide poll is being held off by a scrub, a pause, a
  /// route or an overlay — so the tick that finds the blocker gone can grant a
  /// full interval instead of hiding on the spot.
  bool tvAutoHideBlocked = false;

  void scheduleAutoHide() {
    _host.hideTimer?.cancel();
    _host.hideTimer = Timer(
      VideoPlayerTimingConstants.controlsAutoHideDuration,
      () {
        if (!_host.mounted) return;
        // Televisions dismiss the dock on INACTIVITY, the way an OTT transport
        // bar does, and only while something is actually playing. A paused TV
        // bar staying up is correct — BACK is how you dismiss that one.
        if (PlatformUtil.isTelevision) {
          // Nothing on screen to dismiss — let the timer lapse rather than
          // re-arming one that would poll forever behind a hidden bar.
          if (!_host.controlsVisible.value) return;
          // BLOCKED, not finished. A tracks/episodes sheet is a ROUTE: it takes
          // focus, and the bar would be excluded underneath it, leaving nothing
          // sane to focus when the sheet closes. A scrub owns the bar outright,
          // and a paused player is meant to keep it.
          //
          // Re-arm instead of returning: this is a one-shot Timer, so a bare
          // return SPENT it — a scrub or a sheet lasting longer than the
          // interval meant the dock never auto-hid again for the rest of the
          // session. Re-arming makes the block a pause, not a cancellation.
          final route = ModalRoute.of(_host.context);
          if (_host.tvScrubTarget != null ||
              !_host.isPlaying ||
              (route != null && !route.isCurrent) ||
              _host.anyPlayerOverlayOpen) {
            tvAutoHideBlocked = true;
            scheduleAutoHide();
            return;
          }
          if (tvAutoHideBlocked) {
            // The blocker cleared somewhere inside the last poll. Start the
            // interval again from NOW: closing a sheet must not be met by a
            // countdown that already ran out behind it.
            tvAutoHideBlocked = false;
            scheduleAutoHide();
            return;
          }
          // Deliberately NOT gated on "focus is inside the bar". Raising the bar
          // always focuses Play/Pause, so that test is true for the entire life
          // of the bar and the timer could never fire — the dock sat over
          // playing video until the user pressed BACK. Every key that reaches
          // the player and every bar action reschedules this timer, so what
          // actually elapses here is INACTIVITY, which is what an OTT dock
          // dismisses on. Route through _tvHideBar so focus leaves the bar
          // before it is excluded; setting the flag alone would strand the
          // remote on a node that no longer exists.
          tvHideBar();
          return;
        }
        _host.controlsVisible.value = false;
      },
    );
  }

  // ---- Television transport bar -------------------------------------------

  /// Raise the bar and put focus on Play/Pause (not the first button — the
  /// control you want 90% of the time should be under the thumb already).
  void tvShowBar() {
    _host.controlsVisible.value = true;
    // A fresh raise starts from a clean slate: a stale "was blocked" left over
    // from the previous time the bar was up would silently buy this one an
    // extra interval before it could hide.
    tvAutoHideBlocked = false;
    scheduleAutoHide();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_host.mounted || !_host.controlsVisible.value) return;
      // An open overlay owns the remote — the bar must not pull focus out
      // from under it.
      if (_host.anyPlayerOverlayOpen) return;
      if (!_host.tvBarScope.hasFocus) _host.tvPlayPauseFocus.requestFocus();
    });
  }

  /// Lower the bar and take focus back to the player root. Without the second
  /// half the focused control is excluded from the tree and the remote dies.
  void tvHideBar() {
    _host.controlsVisible.value = false;
    // With an overlay up, focus belongs to the overlay (its claim may still
    // be a frame away) — grabbing the root here would strand its DPAD.
    if (!_host.anyPlayerOverlayOpen) _host.tvRootFocus.requestFocus();
  }

  /// Closes the topmost overlay and returns focus to the player root, which the
  /// individual hide methods do not do on their own.
  void closeTopPlayerOverlay() {
    if (_host.showPlayerMenu) {
      // Delegate: BACK inside the menu walks values -> rail before closing
      // (tvOS Menu arrives here via PopScope, never as a key).
      if (_host.playerMenuKey.currentState?.handleHostBack() != true) {
        _host.hidePlayerMenu();
      }
      // Still open means the press was spent on a pane change.
      if (_host.showPlayerMenu) return;
    } else if (_host.showSyncOverlay) {
      _host.hideSyncOverlay();
    } else if (_host.showChannelGuide) {
      _host.hideChannelGuideOverlay();
    } else if (_host.showIptvChannelSheet) {
      // Delegate: the guide's own back walks schedule -> channels first, and
      // its close restores a search-interrupted category.
      if (_host.iptvSheetKey.currentState?.handleHostBack() != true) {
        _host.hideIptvChannelSheet();
      }
      // It may still be open (pane change rather than close). Taking focus to
      // the player root would leave its DPAD dead.
      if (_host.showIptvChannelSheet) return;
    } else if (_host.showSourceSheet) {
      _host.hideSourceSheet();
    } else if (_host.showStremioTvGuide) {
      _host.hideStremioTvGuide();
    } else {
      return;
    }
    if (PlatformUtil.isTelevision) _host.tvRootFocus.requestFocus();
  }

  void toggleControls() {
    _host.controlsVisible.value = !_host.controlsVisible.value;
    if (_host.controlsVisible.value) {
      scheduleAutoHide();
      // Identity rides IN the bar (IPTV zap panel / Debrify TV banner both
      // embed as the dock's info panel), so nothing floats when it rises.
    }
  }

  void onControlsVisibilityChanged() {
    _host.syncPlaybackClockVisibility();
    // The dock carries its own copy of the panel, so the floating one goes the
    // instant the dock opens. Fading it would cross-dissolve two copies of the
    // same panel at two different heights.
    if (_host.controlsVisible.value) {
      _host.hideIptvZapBanner(immediate: true);
      _host.hideDebrifyBanner(immediate: true);
      // The Record button is about to be looked at — make sure it reflects
      // engine captures stopped from the notification (which this screen
      // otherwise never hears about).
      if (_host.engineFlagOn) unawaited(_host.refreshEngineRecordingState());
    }
    // Return focus to the player root whenever the bar goes down, so the
    // remote is never left pointing at a control that has just been excluded
    // from the tree.
    if (PlatformUtil.isTelevision) {
      // Not while an overlay is up: the source / guide / channel sheets
      // autofocus their own KeyboardListener and drive a virtual focus index,
      // so taking focus back here would leave them unable to see any keys.
      if (!_host.controlsVisible.value &&
          _host.tvBarScope.hasFocus &&
          !_host.anyPlayerOverlayOpen) {
        _host.tvRootFocus.requestFocus();
      }
    }
    _host.syncIptvBannerTicker();
  }

  void togglePlay() {
    if (!_host.isReady) return;
    if (_host.isPlaying) {
      _host.activeMediaUserPaused = true;
      _host.activeMediaShouldPlay = false;
      _host.player.pause();
      unawaited(_host.saveResume(positionOverride: _host.position));
    } else {
      // An explicit press is the one thing that clears a sleep stop.
      _host.sleepStopLatched = false;
      _host.activeMediaUserPaused = false;
      _host.activeMediaShouldPlay = true;
      _host.player.play();
    }
    scheduleAutoHide();
  }

  /// Called on mouse movement: reveal controls (and the cursor) if hidden and
  /// (re)start the auto-hide countdown so continuous movement keeps them alive.
  void wakeControlsOnPointer() {
    // Don't disturb the base controls while an overlay owns the screen; the
    // cursor is already kept visible by _isAnyOverlayOpen in the builder.
    if (_host.isAnyOverlayOpen) return;
    if (!_host.controlsVisible.value) {
      _host.controlsVisible.value = true;
    }
    scheduleAutoHide();
  }
}
