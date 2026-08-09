import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../theme/app_theme_scope.dart';
import '../../../utils/platform_util.dart';
import '../../../utils/tv_keys.dart';

/// TV-optimized focusable card.
///
/// A card widget with focus highlighting, long press support for Android TV,
/// and visual hints. Supports both tap and long press actions.
class TvFocusableCard extends StatefulWidget {
  final VoidCallback onPressed;
  final VoidCallback? onLongPress;
  final Widget child;
  final bool showLongPressHint;

  const TvFocusableCard({
    super.key,
    required this.onPressed,
    required this.child,
    this.onLongPress,
    this.showLongPressHint = false,
  });

  @override
  State<TvFocusableCard> createState() => _TvFocusableCardState();
}

class _TvFocusableCardState extends State<TvFocusableCard> {
  bool _isFocused = false;
  Timer? _longPressTimer;
  bool _longPressTriggered = false;
  DateTime? _lastLongPressTime;
  bool _keyDownReceived = false; // Track if we received KeyDown while focused

  @override
  void dispose() {
    _longPressTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final tv = app.debrifyTv;
    return Focus(
      onFocusChange: (focused) {
        setState(() {
          _isFocused = focused;
        });
        if (!focused) {
          _longPressTimer?.cancel();
          _longPressTriggered = false;
          _keyDownReceived = false; // Reset when losing focus
        }
      },
      onKeyEvent: (node, event) {
        // Handle Select/Enter button press
        if (isActivateKey(event.logicalKey)) {
          if (event is KeyDownEvent) {
            _keyDownReceived = true; // Mark that we received KeyDown while focused
            _longPressTriggered = false;

            // Start timer for long press (800ms)
            _longPressTimer?.cancel();
            _longPressTimer = Timer(const Duration(milliseconds: 800), () {
              _longPressTriggered = true;
              _lastLongPressTime = DateTime.now();
              if (widget.onLongPress != null) {
                widget.onLongPress!();
              }
            });

            return KeyEventResult.handled;
          } else if (event is KeyUpEvent) {
            _longPressTimer?.cancel();

            // CRITICAL: Only process KeyUp if we received KeyDown while focused
            // This prevents phantom triggers when focus changes during a key press
            if (!_keyDownReceived) {
              return KeyEventResult.handled;
            }

            // Check if we recently triggered a long press (within last 300ms)
            final timeSinceLongPress = _lastLongPressTime != null
                ? DateTime.now().difference(_lastLongPressTime!).inMilliseconds
                : 999999;

            // If not a long press and not immediately after closing dialog, trigger regular press
            if (!_longPressTriggered && timeSinceLongPress > 300) {
              widget.onPressed();
            }
            _longPressTriggered = false;
            _keyDownReceived = false; // Reset after processing

            return KeyEventResult.handled;
          }
        }

        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          // Ignore taps that occur too soon after a dialog was dismissed
          final timeSinceLongPress = _lastLongPressTime != null
              ? DateTime.now().difference(_lastLongPressTime!).inMilliseconds
              : 999999;
          if (timeSinceLongPress <= 300) {
            return;
          }
          widget.onPressed();
        },
        onLongPress: widget.onLongPress != null
            ? () {
                _lastLongPressTime = DateTime.now();
                widget.onLongPress!();
              }
            : null,
        child: RepaintBoundary(
          child: Stack(
          children: [
            AnimatedContainer(
              // TV: snap instead of animating — a 200ms tween of a blurred
              // shadow + gradient repaints the card every frame of every
              // focus move, the main jank source in the channel grid.
              duration: PlatformUtil.isTelevision
                  ? Duration.zero
                  : const Duration(milliseconds: 200),
              width: double.infinity,
              height: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  // The resting gradient's deep stop is `dialogBg` — the only
                  // role holding this value. A role stretch (it is a card
                  // gradient, not a dialog ground), taken because the
                  // alternative is a near-black bottom edge on a paper theme.
                  colors: _isFocused
                      ? [tv.cardFocusBg, tv.cardBg]
                      : [tv.cardBg, tv.dialogBg],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _isFocused ? tv.focusRing : tv.hairline,
                  width: _isFocused ? 3 : 1,
                ),
                // TV: the 3px white border is the focus cue; blurred shadows
                // are the expensive part of the repaint, so skip them there.
                boxShadow: PlatformUtil.isTelevision
                    ? null
                    : _isFocused
                    ? [
                        BoxShadow(
                          // The focus ring bled out. 51 = the source's
                          // `withOpacity(0.2)` (see TvFocusableButton).
                          color: tv.focusRing.withAlpha(51),
                          blurRadius: 24,
                          spreadRadius: 0,
                        ),
                      ]
                    : [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 8,
                          spreadRadius: 0,
                        ),
                      ],
              ),
              child: widget.child,
            ),
            // Long press hint (bottom-right when focused)
            if (_isFocused &&
                widget.showLongPressHint &&
                widget.onLongPress != null)
              Positioned(
                bottom: 8,
                right: 8,
                child: AnimatedOpacity(
                  opacity: _isFocused ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      // Black glass floating over the card's artwork — it stays
                      // black on every theme, so its ink is `onGlass`.
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: app.onGlass.withAlpha(77),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.more_vert_rounded,
                          size: 14,
                          color: app.onGlass.withAlpha(230),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Long press for options',
                          style: TextStyle(
                            color: app.onGlass.withAlpha(230),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
          ),
        ),
      ),
    );
  }
}
