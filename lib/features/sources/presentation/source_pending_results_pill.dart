import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_theme_scope.dart';
import '../../../utils/tv_keys.dart';

/// Presents parked results without owning their state or adjacent focus nodes.
class SourcePendingResultsPill extends StatelessWidget {
  const SourcePendingResultsPill({
    super.key,
    required this.count,
    required this.focusNode,
    required this.onAdopt,
    required this.onNavigateDown,
    required this.onNavigateUp,
  });

  final int count;

  /// Borrowed from the view; the view retains disposal ownership.
  final FocusNode focusNode;
  final VoidCallback onAdopt;
  final VoidCallback onNavigateDown;

  /// Returns false when the toolbar is absent, allowing normal key bubbling.
  final bool Function() onNavigateUp;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final accent = app.home.chromeAccent;
    final n = count;
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, e) {
        if (e is! KeyDownEvent) return KeyEventResult.ignored;
        if (isActivateKey(e.logicalKey)) {
          onAdopt();
          onNavigateDown();
          return KeyEventResult.handled;
        }
        if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
          onNavigateDown();
          return KeyEventResult.handled;
        }
        if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
          return onNavigateUp()
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
        }
        return KeyEventResult.ignored;
      },
      child: ListenableBuilder(
        listenable: focusNode,
        builder: (context, _) {
          final focused = focusNode.hasFocus;
          return GestureDetector(
            onTap: () {
              onAdopt();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: focused ? app.core.tx : accent,
                borderRadius: app.shape.brPill,
                border: Border.all(
                  color: focused ? app.core.tx : Colors.transparent,
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.arrow_upward_rounded,
                    size: 14,
                    // Same rule as the keyword pill: unfocused the fill is the
                    // accent, so the ink is scored against it rather than
                    // hardcoded white.
                    color: focused
                        ? const Color(0xFF17131F)
                        : app.inkOn(accent),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$n new source${n == 1 ? '' : 's'}',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: focused
                          ? const Color(0xFF17131F)
                          : app.inkOn(accent),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
