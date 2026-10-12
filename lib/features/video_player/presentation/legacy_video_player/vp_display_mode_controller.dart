import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:debrify/screens/video_player/models/gesture_state.dart';
import 'package:debrify/screens/video_player/models/hud_state.dart';
import 'package:debrify/screens/video_player/utils/aspect_mode_utils.dart';
import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';

abstract interface class VpDisplayModeHost {
  bool get mounted;
  BuildContext get context;
  void setState(VoidCallback fn);
  mk.Player get player;
  void scheduleAutoHide();
  Future<void> saveResume();
  void openPlayerMenuQuick(PlayerMenuSection section);
  ValueNotifier<AspectRatioHudState?> get aspectRatioHud;
  ValueNotifier<bool> get speedHoldHud;
  bool get isPlaying;
  ValueNotifier<bool> get controlsVisible;
  double dockBand(double legacy);
  bool get hideBackButton;
  bool get hideOptions;
}

class VpDisplayModeController {
  VpDisplayModeController(this._host);
  final VpDisplayModeHost _host;

  // Aspect / speed
  AspectMode aspectMode = AspectMode.contain;
  double playbackSpeed = 1.0;

  // Press-and-hold for 2x speed
  double? speedBeforeHold;

  // Orientation
  bool landscapeLocked = false;

  Future<void> applyAspectVideoZoom() async {
    final platform = _host.player.platform;
    if (platform is! mk.NativePlayer) return;
    final scale = AspectModeUtils.getScaleForMode(aspectMode);
    final zoom = math.log(scale) / math.ln2;
    try {
      await platform.setProperty('video-zoom', zoom.toStringAsFixed(6));
    } catch (e) {
      debugPrint('VideoPlayer: aspect zoom apply failed: $e');
    }
  }

  void cycleAspectMode() {
    AspectMode newMode;
    String modeName;
    IconData modeIcon;

    switch (aspectMode) {
      case AspectMode.contain:
        newMode = AspectMode.cover;
        modeName = 'Cover';
        modeIcon = Icons.crop_free_rounded;
        break;
      case AspectMode.cover:
        newMode = AspectMode.fitWidth;
        modeName = 'Fit Width';
        modeIcon = Icons.fit_screen_rounded;
        break;
      case AspectMode.fitWidth:
        newMode = AspectMode.fitHeight;
        modeName = 'Fit Height';
        modeIcon = Icons.fit_screen_rounded;
        break;
      case AspectMode.fitHeight:
        newMode = AspectMode.aspect16_9;
        modeName = '16:9';
        modeIcon = Icons.aspect_ratio_rounded;
        break;
      case AspectMode.aspect16_9:
        newMode = AspectMode.aspect4_3;
        modeName = '4:3';
        modeIcon = Icons.aspect_ratio_rounded;
        break;
      case AspectMode.aspect4_3:
        newMode = AspectMode.aspect21_9;
        modeName = '21:9';
        modeIcon = Icons.aspect_ratio_rounded;
        break;
      case AspectMode.aspect21_9:
        newMode = AspectMode.aspect1_1;
        modeName = '1:1';
        modeIcon = Icons.crop_square_rounded;
        break;
      case AspectMode.aspect1_1:
        newMode = AspectMode.aspect3_2;
        modeName = '3:2';
        modeIcon = Icons.aspect_ratio_rounded;
        break;
      case AspectMode.aspect3_2:
        newMode = AspectMode.aspect5_4;
        modeName = '5:4';
        modeIcon = Icons.aspect_ratio_rounded;
        break;
      case AspectMode.aspect5_4:
        newMode = AspectMode.cinemaZoom;
        modeName = 'Cinema Zoom';
        modeIcon = Icons.zoom_in_map_rounded;
        break;
      case AspectMode.cinemaZoom:
        newMode = AspectMode.contain;
        modeName = 'Contain';
        modeIcon = Icons.crop_free_rounded;
        break;
    }

    _host.setState(() {
      aspectMode = newMode;
    });
    unawaited(applyAspectVideoZoom());

    // Show elegant HUD feedback
    _host.aspectRatioHud.value = AspectRatioHudState(
      aspectRatio: modeName,
      icon: modeIcon,
    );

    // Auto-hide the HUD after 1.5 seconds
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (_host.mounted) {
        _host.aspectRatioHud.value = null;
      }
    });

    _host.scheduleAutoHide();
    _host.saveResume();
  }

  void changeSpeed() {
    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
    final idx = speeds.indexOf(playbackSpeed);
    final next = speeds[(idx + 1) % speeds.length];
    _host.player.setRate(next);
    _host.setState(() => playbackSpeed = next);
    _host.scheduleAutoHide();
    _host.saveResume();
  }

  /// Speed button: the menu's Speed pane when the unified menu is on, the
  /// old blind cycle otherwise. Keyboard/long-press cycling is untouched.
  void onSpeedButton() {
    if (kUnifiedPlayerMenuEnabled) {
      _host.openPlayerMenuQuick(PlayerMenuSection.speed);
      return;
    }
    changeSpeed();
  }

  void onAspectButton() {
    if (kUnifiedPlayerMenuEnabled) {
      _host.openPlayerMenuQuick(PlayerMenuSection.aspect);
      return;
    }
    cycleAspectMode();
  }

  void setPlaybackSpeed(double v) {
    _host.player.setRate(v);
    _host.setState(() => playbackSpeed = v);
    _host.saveResume();
  }

  void setAspectModeDirect(AspectMode m) {
    if (m == aspectMode) return;
    _host.setState(() => aspectMode = m);
    unawaited(applyAspectVideoZoom());
    _host.saveResume();
  }

  void onLongPressStart(LongPressStartDetails details) {
    // Respect the same lock used by the single-tap path
    if (_host.hideBackButton && _host.hideOptions) return;
    // Only engage during playback so a pause-hold doesn't strand speed at 2x
    if (!_host.isPlaying) return;
    final box = _host.context.findRenderObject() as RenderBox?;
    if (box != null) {
      final size = box.size;
      final localPos = details.localPosition;
      // Avoid edge conflicts with the system back gesture
      const edgeGuard = 24.0;
      if (localPos.dx < edgeGuard || localPos.dx > size.width - edgeGuard) {
        return;
      }
      // When controls are visible, skip top/bottom bar regions so buttons/slider win
      if (_host.controlsVisible.value) {
        const topBar = 72.0;
        final bottomBar = _host.dockBand(72.0);
        if (localPos.dy < topBar || localPos.dy > size.height - bottomBar) {
          return;
        }
      }
    }
    speedBeforeHold = playbackSpeed;
    _host.player.setRate(2.0);
    _host.setState(() => playbackSpeed = 2.0);
    _host.speedHoldHud.value = true;
    HapticFeedback.mediumImpact();
  }

  void onLongPressEnd(LongPressEndDetails details) {
    final prior = speedBeforeHold;
    if (prior == null) return;
    speedBeforeHold = null;
    if (!_host.mounted) return;
    _host.player.setRate(prior);
    _host.setState(() => playbackSpeed = prior);
    _host.speedHoldHud.value = false;
  }

  Future<void> toggleOrientation() async {
    if (landscapeLocked) {
      await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
        DeviceOrientation.portraitUp,
      ]);
      landscapeLocked = false;
    } else {
      await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      landscapeLocked = true;
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    if (_host.mounted) _host.setState(() {});
    _host.scheduleAutoHide();
  }

  BoxFit currentFit() => AspectModeUtils.getBoxFitForMode(aspectMode);

  // Get the custom aspect ratio for specific modes
  double? getCustomAspectRatio() =>
      AspectModeUtils.getAspectRatioValue(aspectMode);
}
