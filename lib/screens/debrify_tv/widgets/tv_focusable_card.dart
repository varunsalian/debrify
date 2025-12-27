import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  @override
  void dispose() {
    _longPressTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (focused) {
        print('[TvFocusableCard] Focus changed: $focused');
        setState(() {
          _isFocused = focused;
        });
        if (!focused) {
          _longPressTimer?.cancel();
          _longPressTriggered = false;
        }
      },
      onKeyEvent: (node, event) {
        // Handle Select/Enter button press
        if (event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter) {
          if (event is KeyDownEvent) {
            print(
              '[TvFocusableCard] Select/Enter key DOWN - starting long press timer',
            );
            _longPressTriggered = false;

            // Start timer for long press (800ms)
            _longPressTimer?.cancel();
            _longPressTimer = Timer(const Duration(milliseconds: 800), () {
              print(
                '[TvFocusableCard] Long press detected! Triggering onLongPress',
              );
              _longPressTriggered = true;
              _lastLongPressTime = DateTime.now();
              if (widget.onLongPress != null) {
                widget.onLongPress!();
              }
            });

            return KeyEventResult.handled;
          } else if (event is KeyUpEvent) {
            print('[TvFocusableCard] Select/Enter key UP');
            _longPressTimer?.cancel();

            // Check if we recently triggered a long press (within last 500ms)
            final timeSinceLongPress = _lastLongPressTime != null
                ? DateTime.now().difference(_lastLongPressTime!).inMilliseconds
                : 999999;

            // If not a long press and not immediately after closing dialog, trigger regular press
            if (!_longPressTriggered && timeSinceLongPress > 500) {
              print('[TvFocusableCard] Short press - triggering onPressed');
              widget.onPressed();
            } else if (timeSinceLongPress <= 500) {
              print(
                '[TvFocusableCard] Ignoring key up - too soon after long press dialog',
              );
            }
            _longPressTriggered = false;

            return KeyEventResult.handled;
          }
        }

        if (event is KeyDownEvent) {
          print(
            '[TvFocusableCard] Other key pressed: ${event.logicalKey.keyLabel} (${event.logicalKey.keyId})',
          );
        }

        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: () {
          print('[TvFocusableCard] GestureDetector onTap triggered');
          widget.onPressed();
        },
        onLongPress: widget.onLongPress != null
            ? () {
                print(
                  '[TvFocusableCard] GestureDetector onLongPress triggered!',
                );
                widget.onLongPress!();
              }
            : null,
        child: Stack(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: double.infinity,
              height: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: _isFocused
                      ? [const Color(0xFF2A2A2A), const Color(0xFF1A1A1A)]
                      : [const Color(0xFF1A1A1A), const Color(0xFF0F0F0F)],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _isFocused ? Colors.white : Colors.white12,
                  width: _isFocused ? 3 : 1,
                ),
                boxShadow: _isFocused
                    ? [
                        BoxShadow(
                          color: Colors.white.withOpacity(0.2),
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
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.more_vert_rounded,
                          size: 14,
                          color: Colors.white.withOpacity(0.9),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Long press for options',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
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
    );
  }
}
