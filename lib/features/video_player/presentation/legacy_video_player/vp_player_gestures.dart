import 'dart:async';
import 'dart:math' as math;

import 'package:debrify/screens/video_player/constants/timing_constants.dart';
import 'package:debrify/screens/video_player/models/gesture_state.dart';
import 'package:debrify/screens/video_player/models/hud_state.dart';
import 'package:debrify/services/player_display_controls.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' as mk;

abstract interface class VpPlayerGesturesHost {
  ValueNotifier<bool> get controlsVisible;
  Duration get duration;
  mk.Player get player;
  Duration get position;
  set ripple(DoubleTapRipple? v);
  ValueNotifier<SeekHudState?> get seekHud;
  ValueNotifier<VerticalHudState?> get verticalHud;
  double dockBand(double legacy);
  bool get mounted;
  BuildContext get context;
  void setState(VoidCallback fn);
  void mdblistScrobbleSeek(Duration target);
  void simklScrobbleSeek(Duration seekTarget);
  void traktScrobbleSeek(Duration seekTarget);
}

class VpPlayerGestures {
  VpPlayerGestures(this._host);
  final VpPlayerGesturesHost _host;

  bool panIgnore = false;

  // Gesture state
  GestureMode mode = GestureMode.none;
  Offset gestureStartPosition = Offset.zero;
  Duration gestureStartVideoPosition = Duration.zero;
  double gestureStartVolume = 0.0;
  double gestureStartBrightness = 0.0;

  Future<void> handleDoubleTap(TapDownDetails details) async {
    final box = _host.context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final size = box.size;
    final localPos = details.localPosition;
    // Avoid edge conflicts with system back gesture by requiring a margin
    const edgeGuard = 24.0;
    if (localPos.dx < edgeGuard || localPos.dx > size.width - edgeGuard) return;
    // If controls visible, ignore double-taps near top/bottom bars to not clash with buttons/slider
    if (_host.controlsVisible.value) {
      const topBar = 72.0;
      final bottomBar = _host.dockBand(72.0);
      if (localPos.dy < topBar || localPos.dy > size.height - bottomBar) return;
    }

    // Default seek behavior for left/right taps
    final isLeft = localPos.dx < size.width / 2;
    final delta = VideoPlayerTimingConstants.seekDelta;
    final target = _host.position + (isLeft ? -delta : delta);
    final minPos = Duration.zero;
    final maxPos = _host.duration;
    final clamped = target < minPos
        ? minPos
        : (target > maxPos ? maxPos : target);
    await _host.player.seek(clamped);
    _host.traktScrobbleSeek(clamped);
    _host.simklScrobbleSeek(clamped);
    _host.mdblistScrobbleSeek(clamped);
    _host.ripple = DoubleTapRipple(
      center: localPos,
      icon: isLeft ? Icons.replay_10_rounded : Icons.forward_10_rounded,
    );
    _host.setState(() {});
    Future.delayed(const Duration(milliseconds: 450), () {
      if (_host.mounted) _host.setState(() => _host.ripple = null);
    });
  }

  void onPanStart(DragStartDetails details) async {
    // If controls are visible, ignore pans that begin within top/bottom bars so buttons and slider work unaffected
    panIgnore = false;
    if (_host.controlsVisible.value) {
      final box = _host.context.findRenderObject() as RenderBox?;
      if (box != null) {
        final size = box.size;
        const topBar = 72.0;
        final bottomBar = _host.dockBand(72.0);
        final dy = details.localPosition.dy;
        if (dy < topBar || dy > size.height - bottomBar) {
          panIgnore = true;
          return;
        }
      }
    }
    gestureStartPosition = details.localPosition;
    gestureStartVideoPosition = _host.position;
    gestureStartVolume = (_host.player.state.volume / 100.0).clamp(0.0, 1.0);
    gestureStartBrightness = await PlayerDisplayControls.instance.brightness();
    if (!_host.mounted) return;
    mode = GestureMode.none;
    _host.verticalHud.value = null;
    _host.seekHud.value = null;
  }

  void onPanUpdate(DragUpdateDetails details) {
    if (panIgnore) return;
    final dx = details.localPosition.dx - gestureStartPosition.dx;
    final dy = details.localPosition.dy - gestureStartPosition.dy;
    final absDx = dx.abs();
    final absDy = dy.abs();
    final size = (_host.context.findRenderObject() as RenderBox).size;

    // Decide mode on first significant movement
    if (mode == GestureMode.none) {
      if (absDx > 12 && absDx > absDy) {
        mode = GestureMode.seek;
      } else if (absDy > 12) {
        final isLeftHalf = gestureStartPosition.dx < size.width / 2;
        if (isLeftHalf && !PlayerDisplayControls.supportsBrightness) return;
        mode = isLeftHalf ? GestureMode.brightness : GestureMode.volume;
      }
    }

    if (mode == GestureMode.seek) {
      final duration = _host.duration;
      if (duration == Duration.zero) return;
      // Map horizontal delta to seconds, proportional to width
      final totalSeconds = duration.inSeconds.toDouble();
      final seekSeconds = (dx / size.width) * math.min(120.0, totalSeconds);
      var newPos =
          gestureStartVideoPosition + Duration(seconds: seekSeconds.round());
      if (newPos < Duration.zero) newPos = Duration.zero;
      if (newPos > duration) newPos = duration;
      _host.seekHud.value = SeekHudState(
        target: newPos,
        base: _host.position,
        isForward: newPos >= _host.position,
      );
    } else if (mode == GestureMode.volume) {
      var newVol = (gestureStartVolume - dy / size.height).clamp(0.0, 1.0);
      _host.player.setVolume((newVol * 100).clamp(0.0, 100.0));
      _host.verticalHud.value = VerticalHudState(
        kind: VerticalKind.volume,
        value: newVol,
      );
    } else if (mode == GestureMode.brightness) {
      var newBright = (gestureStartBrightness - dy / size.height).clamp(
        0.0,
        1.0,
      );
      unawaited(PlayerDisplayControls.instance.setBrightness(newBright));
      _host.verticalHud.value = VerticalHudState(
        kind: VerticalKind.brightness,
        value: newBright,
      );
    }
  }

  void onPanEnd(DragEndDetails details) {
    if (panIgnore) return;
    if (mode == GestureMode.seek && _host.seekHud.value != null) {
      final target = _host.seekHud.value!.target;
      _host.player.seek(target);
      _host.traktScrobbleSeek(target);
      _host.simklScrobbleSeek(target);
      _host.mdblistScrobbleSeek(target);
    }
    mode = GestureMode.none;
    Future.delayed(const Duration(milliseconds: 250), () {
      if (_host.mounted) {
        _host.seekHud.value = null;
        _host.verticalHud.value = null;
      }
    });
  }
}
