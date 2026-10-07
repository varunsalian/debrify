import 'package:debrify/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/spotlight_timeline_dependencies.dart';
import 'package:debrify/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/spotlight_timeline_guide_models.dart';
import 'package:debrify/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/spotlight_timeline_owners.dart';
import 'package:debrify/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/spotlight_timeline_sections.dart';
import 'package:debrify/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/spotlight_timeline_widget_view.dart';
import 'package:debrify/services/iptv_epg_service.dart';
import 'package:debrify/utils/tv_keys.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SpotlightTimelineWindow {
  final SpotlightTimelineDependencies _deps;
  SpotlightTimelineWindow(this._deps);
  SpotlightTimelineWidgetView get widget => _deps.view;
  SpotlightTimelineOwners get _owners => _deps.owners;
  SpotlightTimelineSections get _sections => _deps.sections();

  static const Duration _guideRefreshInterval = Duration(minutes: 30);

  DateTime defaultWindowStart([DateTime? at]) {
    final now = at ?? widget.now();
    final minute = now.minute < 30 ? 0 : 30;
    return DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      minute,
    ).subtract(const Duration(minutes: 30));
  }

  void onClockTick() {
    if (!_deps.mounted()) return;
    final now = widget.now();
    if (_owners.followNow) {
      _owners.windowStart = defaultWindowStart(now);
      // Until the user chooses a programme, RIGHT should enter the show that
      // is current at the time of the key press. Without advancing this anchor
      // it stayed pinned to widget creation and could select a show that ended
      // while the guide was left open.
      if (_owners.selectedProgrammeStartMs == null) {
        _owners.cursorTimeMs = now.millisecondsSinceEpoch;
      }
    }

    final guidesExpired =
        now.difference(_owners.lastGuideRefreshAt) >= _guideRefreshInterval;
    var selectionReset = false;
    if (guidesExpired) {
      _owners.lastGuideRefreshAt = now;
      // The service uses the same 30-minute TTL. Dropping only this widget's
      // bounded snapshots makes the next settled viewport request fresh data.
      _owners.guides.clear();
      _owners.pendingLoads.clear();
      if (_owners.cursorLane == SpotlightTimelineCursorLane.retry) {
        _owners.cursorLane = SpotlightTimelineCursorLane.identity;
        _owners.selectedProgrammeStartMs = null;
        selectionReset = true;
      }
      _sections.loading.armViewportLoad();
    }
    _deps.setState(() {});
    if (selectionReset) _sections.selection.announceSelection();
  }

  void ensureProgrammeVisible(EpgProgramme programme) {
    final startMs = _owners.windowStart.millisecondsSinceEpoch;
    final durationMs = widget.windowDuration.inMilliseconds;
    final endMs = startMs + durationMs;
    final programmeStart = programme.start.millisecondsSinceEpoch;
    final programmeStop = programme.stop.millisecondsSinceEpoch;
    if (programmeStart >= startMs && programmeStop <= endMs) return;

    // A programme longer than the viewport can never satisfy the containment
    // check above. If it already crosses the visible window, keep it clipped
    // in place instead of moving a follow-now guide away from the playhead.
    // Oversized programmes wholly outside the window still recenter below so
    // deliberate left/right navigation can reveal them.
    if (programmeStop - programmeStart >= durationMs &&
        programmeStop > startMs &&
        programmeStart < endMs) {
      return;
    }

    final lead = (durationMs * 0.12).round();
    final newStartMs = programmeStart < startMs
        ? programmeStart - lead
        : programmeStop - durationMs + lead;
    _owners.windowStart = DateTime.fromMillisecondsSinceEpoch(newStartMs);
    _owners.followNow = false;
  }

  void handlePointerSignal(PointerSignalEvent signal, double timelineWidth) {
    if (signal is! PointerScrollEvent || timelineWidth <= 0) return;
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    final shift =
        keys.contains(LogicalKeyboardKey.shiftLeft) ||
        keys.contains(LogicalKeyboardKey.shiftRight);
    // Match Flutter's axis swap for Shift + physical mouse wheel. Trackpad
    // axes remain independent even while Shift is pressed.
    final swapAxes = shift && signal.kind == PointerDeviceKind.mouse;
    final horizontal = swapAxes ? signal.scrollDelta.dy : signal.scrollDelta.dx;
    final vertical = swapAxes ? signal.scrollDelta.dx : signal.scrollDelta.dy;
    if (horizontal.abs() <= vertical.abs()) return;
    GestureBinding.instance.pointerSignalResolver.register(signal, (_) {
      panTimeline(horizontal, timelineWidth);
      signal.respond(allowPlatformDefault: false);
    });
  }

  void panTimeline(double deltaPixels, double timelineWidth) {
    if (timelineWidth <= 0) return;
    _sections.selection.cancelPointerSelection();
    _owners.lastTappedCell = null;
    final deltaMs =
        deltaPixels / timelineWidth * widget.windowDuration.inMilliseconds;
    _deps.setState(() {
      _owners.windowStart = DateTime.fromMillisecondsSinceEpoch(
        _owners.windowStart.millisecondsSinceEpoch + deltaMs.round(),
      );
      _owners.followNow = false;
    });
  }

  KeyEventResult onNowKeyEvent(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    if (isActivateOrSpaceKey(key)) {
      if (event is KeyDownEvent) jumpToNow();
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowRight) {
      _sections.selection.restoreFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp && widget.onExitUp != null) {
      widget.onExitUp!();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft && widget.onExitLeft != null) {
      widget.onExitLeft!();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void jumpToNow() {
    _sections.selection.cancelPointerSelection();
    _deps.setState(() {
      _owners.followNow = true;
      _owners.windowStart = defaultWindowStart(widget.now());
      _owners.cursorTimeMs = widget.now().millisecondsSinceEpoch;
      _owners.cursorLane = SpotlightTimelineCursorLane.identity;
      _owners.selectedProgrammeStartMs = null;
    });
    _sections.selection.restoreFocus();
  }
}
