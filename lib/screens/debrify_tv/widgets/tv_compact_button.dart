import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// TV-optimized compact button for top bar.
///
/// A small button with icon and optional label, with focus scaling and
/// Android TV D-pad support.
class TvCompactButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final String? label;
  final Color backgroundColor;

  const TvCompactButton({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
    required this.backgroundColor,
  });

  @override
  State<TvCompactButton> createState() => _TvCompactButtonState();
}

class _TvCompactButtonState extends State<TvCompactButton> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final isDisabled = widget.onPressed == null;

    return Focus(
      onFocusChange: (focused) {
        setState(() {
          _isFocused = focused;
        });
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          // Handle both select and enter keys
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter) {
            widget.onPressed?.call();
            return KeyEventResult.handled;
          }
          // Also handle context menu button as a secondary action
          if (event.logicalKey == LogicalKeyboardKey.contextMenu &&
              widget.label == null) {
            // Only for settings button
            widget.onPressed?.call();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _isFocused ? 1.05 : 1.0,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 36,
            padding: EdgeInsets.symmetric(
              horizontal: widget.label != null ? 12 : 10,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: isDisabled
                  ? Colors.grey.withOpacity(0.3)
                  : widget.backgroundColor.withOpacity(_isFocused ? 1.0 : 0.8),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _isFocused
                    ? Colors.white
                    : (isDisabled
                          ? Colors.grey.withOpacity(0.2)
                          : Colors.white24),
                width: _isFocused ? 2 : 1,
              ),
              boxShadow: _isFocused
                  ? [
                      BoxShadow(
                        color: widget.backgroundColor.withOpacity(0.3),
                        blurRadius: 8,
                        spreadRadius: 0,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.icon,
                  color: isDisabled ? Colors.grey : Colors.white,
                  size: 16,
                ),
                if (widget.label != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    widget.label!,
                    style: TextStyle(
                      color: isDisabled ? Colors.grey : Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
