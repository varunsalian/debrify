import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../models/hud_state.dart';
import '../painters/double_tap_ripple_painter.dart';
import 'aspect_ratio_hud.dart';
import 'auto_sync_pill.dart';
import 'buffering_indicator.dart';
import 'seek_hud.dart';
import 'vertical_hud.dart';

/// The player's display-only HUD band: the double-tap ripple and the seven
/// HUD slots (seek, vertical volume/brightness, aspect ratio, 2x speed hold,
/// subtitle auto-sync pill, IPTV reconnect pill, buffering indicator) in the
/// host's Stack order.
///
/// Returned as a list for the host to spread into its own
/// `Stack(fit: StackFit.expand)` rather than wrapped in a widget of its own,
/// so the render tree, layout and hit-testing are exactly what the inline
/// band produced: every slot is an `IgnorePointer`, the ripple is present
/// only while [ripple] is non-null, and each `ValueListenableBuilder` keeps
/// its own subtree alive across host rebuilds. [startupGateShowing] is the
/// host's `_startupGateActive && !_startupGateOverlayHidden` sampled at the
/// host's build; both flags are only ever written immediately before a host
/// `setState`, so the buffering slot sees the same value the inline closure
/// read.
List<Widget> buildPlayerHudLayer({
  required DoubleTapRipple? ripple,
  required ValueListenable<SeekHudState?> seekHud,
  required ValueListenable<VerticalHudState?> verticalHud,
  required ValueListenable<AspectRatioHudState?> aspectRatioHud,
  required ValueListenable<bool> speedHoldHud,
  required ValueListenable<AutoSyncPillModel?> autoSyncPill,
  required ValueListenable<String?> iptvReconnectText,
  required ValueListenable<bool> showBufferingIndicator,
  required bool startupGateShowing,
  required String Function(Duration) format,
}) {
  return [
    // Double-tap ripple
    if (ripple != null)
      IgnorePointer(
        child: CustomPaint(
          painter: DoubleTapRipplePainter(ripple),
        ),
      ),
    // HUDs
    ValueListenableBuilder<SeekHudState?>(
      valueListenable: seekHud,
      builder: (context, hud, _) {
        return IgnorePointer(
          ignoring: true,
          child: AnimatedOpacity(
            opacity: hud == null ? 0 : 1,
            duration: const Duration(milliseconds: 120),
            child: Center(
              child: hud == null
                  ? const SizedBox.shrink()
                  : SeekHud(hud: hud, format: format),
            ),
          ),
        );
      },
    ),
    ValueListenableBuilder<VerticalHudState?>(
      valueListenable: verticalHud,
      builder: (context, hud, _) {
        return IgnorePointer(
          ignoring: true,
          child: AnimatedOpacity(
            opacity: hud == null ? 0 : 1,
            duration: const Duration(milliseconds: 120),
            child: Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 24),
                child: hud == null
                    ? const SizedBox.shrink()
                    : VerticalHud(hud: hud),
              ),
            ),
          ),
        );
      },
    ),
    ValueListenableBuilder<AspectRatioHudState?>(
      valueListenable: aspectRatioHud,
      builder: (context, hud, _) {
        return IgnorePointer(
          ignoring: true,
          child: AnimatedOpacity(
            opacity: hud == null ? 0 : 1,
            duration: const Duration(milliseconds: 200),
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 80, right: 24),
                child: hud == null
                    ? const SizedBox.shrink()
                    : AspectRatioHud(hud: hud),
              ),
            ),
          ),
        );
      },
    ),
    ValueListenableBuilder<bool>(
      valueListenable: speedHoldHud,
      builder: (context, active, _) {
        return IgnorePointer(
          ignoring: true,
          child: AnimatedOpacity(
            opacity: active ? 1 : 0,
            duration: const Duration(milliseconds: 150),
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 80),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.fast_forward_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Text(
                        '2× Speed',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ),
    // Subtitle auto-sync countdown pill: quiet bottom-right glass,
    // display-only, outside the subtitle reading zone. TV keeps it
    // inside the overscan safe area.
    AutoSyncPillSlot(autoSyncPill: autoSyncPill),
    // IPTV live reconnect pill (Phase 5 of the resilience plan):
    // only a recovery episode that has run >2s shows it — the
    // invisible fast reconnects stay invisible.
    ValueListenableBuilder<String?>(
      valueListenable: iptvReconnectText,
      builder: (context, text, _) {
        return IgnorePointer(
          ignoring: true,
          child: AnimatedOpacity(
            opacity: text != null ? 1 : 0,
            duration: const Duration(milliseconds: 150),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 56),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Text(
                    text ?? '',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ),
    // Buffering indicator (OTT-style centered spinner)
    ValueListenableBuilder<bool>(
      valueListenable: showBufferingIndicator,
      builder: (context, show, _) {
        // The startup gate has its own spinner and explanatory
        // status. Keeping the ordinary buffering indicator above
        // it produces two overlapping loaders while candidates
        // are being rejected and retried.
        if (startupGateShowing) {
          return const SizedBox.shrink();
        }
        return IgnorePointer(
          ignoring: true,
          child: AnimatedOpacity(
            opacity: show ? 1 : 0,
            duration: show
                ? const Duration(milliseconds: 250)
                : const Duration(milliseconds: 200),
            child: const Center(child: BufferingIndicator()),
          ),
        );
      },
    ),
  ];
}

/// The subtitle auto-sync pill slot. Stateful only for the fade memo: the
/// slot keeps the last non-null model so the dismiss fade has content to
/// fade out (the host State used to hold this field).
class AutoSyncPillSlot extends StatefulWidget {
  const AutoSyncPillSlot({super.key, required this.autoSyncPill});

  final ValueListenable<AutoSyncPillModel?> autoSyncPill;

  @override
  State<AutoSyncPillSlot> createState() => _AutoSyncPillSlotState();
}

class _AutoSyncPillSlotState extends State<AutoSyncPillSlot> {
  // Last non-null model, kept so the dismiss fade has content to fade out.
  AutoSyncPillModel? _autoSyncPillLastShown;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AutoSyncPillModel?>(
      valueListenable: widget.autoSyncPill,
      builder: (context, model, _) {
        if (model != null) _autoSyncPillLastShown = model;
        // Fade out over the LAST shown model — swapping to an
        // empty box here would make the dismiss fade invisible.
        final display = model ?? _autoSyncPillLastShown;
        return IgnorePointer(
          ignoring: true,
          child: AnimatedOpacity(
            opacity: model == null ? 0 : 1,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
            child: Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: EdgeInsets.only(
                  right: AutoSyncPill.cornerInset,
                  bottom: AutoSyncPill.cornerInset,
                ),
                child: display == null
                    ? const SizedBox.shrink()
                    : AutoSyncPill(model: display),
              ),
            ),
          ),
        );
      },
    );
  }
}
