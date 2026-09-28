import 'package:flutter/material.dart';

class StremioTvFocusFrame extends StatelessWidget {
  const StremioTvFocusFrame({
    super.key,
    required this.focusNode,
    required this.child,
  });
  final FocusNode focusNode;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: focusNode,
      builder: (context, _) {
        final isFocused = focusNode.hasFocus;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: isFocused
                ? Border.all(color: Colors.white, width: 2)
                : null,
            boxShadow: isFocused
                ? [
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.18),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: child,
        );
      },
    );
  }
}
