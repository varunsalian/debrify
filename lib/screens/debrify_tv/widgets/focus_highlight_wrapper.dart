import 'package:flutter/material.dart';

/// Wraps a child widget with an animated highlight border for Android TV focus indication.
///
/// When [enabled] is true and a descendant widget has focus, displays an animated
/// border and shadow around the child.
class FocusHighlightWrapper extends StatefulWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final bool enabled;
  final String debugLabel;

  const FocusHighlightWrapper({
    super.key,
    required this.child,
    required this.borderRadius,
    required this.debugLabel,
    this.enabled = false,
  });

  @override
  State<FocusHighlightWrapper> createState() => _FocusHighlightWrapperState();
}

class _FocusHighlightWrapperState extends State<FocusHighlightWrapper> {
  late final FocusNode _focusNode;
  bool _hasFocusedDescendant = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(
      debugLabel: widget.debugLabel,
      canRequestFocus: false,
      skipTraversal: true,
    )..addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant FocusHighlightWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.debugLabel != oldWidget.debugLabel) {
      _focusNode.debugLabel = widget.debugLabel;
    }
    if (!widget.enabled && _hasFocusedDescendant) {
      setState(() {
        _hasFocusedDescendant = false;
      });
    }
  }

  void _handleFocusChange() {
    final next = _focusNode.hasFocus;
    if (next != _hasFocusedDescendant) {
      setState(() {
        _hasFocusedDescendant = next;
      });
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return widget.child;
    }
    final highlightColor = Theme.of(context).colorScheme.primary;
    return Focus(
      focusNode: _focusNode,
      canRequestFocus: false,
      skipTraversal: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          borderRadius: widget.borderRadius,
          border: Border.all(
            color: _hasFocusedDescendant ? highlightColor : Colors.transparent,
            width: 2,
          ),
          boxShadow: _hasFocusedDescendant
              ? [
                  BoxShadow(
                    color: highlightColor.withValues(alpha: 0.35),
                    blurRadius: 26,
                    offset: const Offset(0, 12),
                  ),
                ]
              : null,
        ),
        child: widget.child,
      ),
    );
  }
}
