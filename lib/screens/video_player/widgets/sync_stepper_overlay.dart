import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../utils/platform_util.dart';
import '../services/subtitle_settings_service.dart';

/// Subtitle sync for embedded subtitles — a bottom stepper pill in the
/// Spotlight grammar, replacing the old Material slider panel. The video
/// stays fully visible: the picture IS the reference being synced against.
///
/// DPAD: LEFT/RIGHT nudge ±0.1s, holding accelerates to ±0.5s steps; OK
/// resets to zero; BACK closes (handled by the host, which owns
/// `_showSyncOverlay`). Touch: tap the chevrons / Reset / Done.
class SyncStepperOverlay extends StatefulWidget {
  final int offsetMs;
  final ValueChanged<int> onOffsetChanged;
  final VoidCallback onDismiss;

  const SyncStepperOverlay({
    super.key,
    required this.offsetMs,
    required this.onOffsetChanged,
    required this.onDismiss,
  });

  @override
  State<SyncStepperOverlay> createState() => _SyncStepperOverlayState();
}

class _SyncStepperOverlayState extends State<SyncStepperOverlay> {
  static const _ink = Colors.white;
  static const _glass = Color(0xFF101012);
  static const _stepMs = SubtitleSettingsService.syncOffsetStepMs;

  /// Repeats before a held key switches to the coarse step.
  static const _accelAfterRepeats = 8;
  static const _coarseFactor = 5;

  final FocusNode _keyboardFocusNode = FocusNode(
    debugLabel: 'sync-stepper-overlay',
  );

  int _heldRepeats = 0;

  /// Which chevron flashes from a key press: -1 left, 1 right, 0 none.
  int _flash = 0;
  Timer? _flashTimer;

  @override
  void initState() {
    super.initState();
    // Same claim-on-mount as every in-player overlay: the player root
    // already holds focus, so autofocus alone would be discarded.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _keyboardFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _flashTimer?.cancel();
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  void _nudge(int direction, {required bool held}) {
    final step = held && _heldRepeats >= _accelAfterRepeats
        ? _stepMs * _coarseFactor
        : _stepMs;
    final next = (widget.offsetMs + direction * step).clamp(
      SubtitleSettingsService.syncOffsetMinMs,
      SubtitleSettingsService.syncOffsetMaxMs,
    );
    widget.onOffsetChanged(next);
    setState(() => _flash = direction);
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(milliseconds: 140), () {
      if (mounted) setState(() => _flash = 0);
    });
  }

  /// CONSUMES the keys it handles — a KeyboardListener cannot, so every
  /// arrow press also ran directional focus traversal, which could move
  /// focus onto the hidden TV bar and kill the stepper (same failure as the
  /// player menu, measured on the Apple TV).
  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) {
      _heldRepeats = 0;
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final isRepeat = event is KeyRepeatEvent;
    if (isRepeat) {
      _heldRepeats++;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _nudge(-1, held: isRepeat);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _nudge(1, held: isRepeat);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.gameButtonA) {
      if (!isRepeat) widget.onOffsetChanged(0);
      return KeyEventResult.handled;
    }
    // BACK/ESC deliberately not handled: it bubbles to the player root,
    // which hides the overlay (and tvOS Menu comes via PopScope anyway).
    return KeyEventResult.ignored;
  }

  String get _valueLabel {
    final ms = widget.offsetMs;
    if (ms == 0) return '0.0s';
    final sign = ms > 0 ? '+' : '−';
    return '$sign${(ms.abs() / 1000).toStringAsFixed(1)}s';
  }

  String get _directionLabel {
    final ms = widget.offsetMs;
    if (ms == 0) return 'in sync';
    return ms > 0 ? 'later' : 'earlier';
  }

  @override
  Widget build(BuildContext context) {
    final onTv = PlatformUtil.isTelevision;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Focus(
        focusNode: _keyboardFocusNode,
        onKeyEvent: _handleKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(child: _buildPill(onTv)),
            const SizedBox(height: 10),
            Text(
              onTv
                  ? '◀ ▶ adjust · hold for bigger steps · OK reset · BACK done'
                  : 'Adjust until the words match the voices',
              style: TextStyle(
                color: _ink.withValues(alpha: 0.40),
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildPill(bool onTv) {
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
      decoration: BoxDecoration(
        color: PlatformUtil.isAndroidTvCached
            ? const Color(0xF5101012)
            : _glass.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _ink.withValues(alpha: 0.14), width: 0.75),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 26,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'SUBTITLE SYNC',
            style: TextStyle(
              color: _ink.withValues(alpha: 0.50),
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.8,
            ),
          ),
          const SizedBox(width: 18),
          _StepButton(
            icon: Icons.remove_rounded,
            lit: _flash < 0,
            onTap: () => _nudge(-1, held: false),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 96),
            child: Column(
              children: [
                Text(
                  _valueLabel,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 23,
                    fontWeight: FontWeight.w700,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  _directionLabel.toUpperCase(),
                  style: TextStyle(
                    color: _ink.withValues(alpha: 0.42),
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
          _StepButton(
            icon: Icons.add_rounded,
            lit: _flash > 0,
            onTap: () => _nudge(1, held: false),
          ),
          if (!onTv) ...[
            const SizedBox(width: 16),
            _TextPillButton(label: 'Reset', onTap: () => widget.onOffsetChanged(0)),
            const SizedBox(width: 8),
            _TextPillButton(label: 'Done', onTap: widget.onDismiss, solid: true),
          ],
        ],
      ),
    );
    if (PlatformUtil.isAndroidTvCached) return content;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: content,
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final bool lit;
  final VoidCallback onTap;

  const _StepButton({required this.icon, required this.lit, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 34,
        height: 34,
        margin: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: lit ? Colors.white : Colors.transparent,
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: lit ? 1 : 0.30),
            width: 0.75,
          ),
        ),
        child: Icon(
          icon,
          size: 17,
          color: lit ? Colors.black : Colors.white.withValues(alpha: 0.85),
        ),
      ),
    );
  }
}

class _TextPillButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool solid;

  const _TextPillButton({
    required this.label,
    required this.onTap,
    this.solid = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: solid ? Colors.white : Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: solid ? Colors.black : Colors.white.withValues(alpha: 0.85),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
