import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// TV-optimized focusable button.
///
/// A larger button with icon and label that scales on focus, designed
/// for Android TV navigation with D-pad support.
class TvFocusableButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final String label;
  final Color backgroundColor;
  final double? width;

  const TvFocusableButton({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
    required this.backgroundColor,
    this.width,
  });

  @override
  State<TvFocusableButton> createState() => _TvFocusableButtonState();
}

class _TvFocusableButtonState extends State<TvFocusableButton> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (focused) {
        setState(() {
          _isFocused = focused;
        });
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter)) {
          widget.onPressed?.call();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedScale(
        scale: _isFocused ? 1.1 : 1.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        child: Container(
          width: widget.width,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: _isFocused
                ? [
                    BoxShadow(
                      color: Colors.white.withOpacity(0.3),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
            border: _isFocused
                ? Border.all(color: Colors.white, width: 3)
                : null,
          ),
          child: FilledButton.icon(
            onPressed: widget.onPressed,
            icon: Icon(widget.icon, size: 20),
            label: Text(
              widget.label,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: widget.backgroundColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
