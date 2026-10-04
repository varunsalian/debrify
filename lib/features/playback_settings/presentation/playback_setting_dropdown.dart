import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Widget buildSettingDropdown(
  BuildContext context, {
  required String label,
  required int value,
  required List<String> items,
  required Function(int) onChanged,
  FocusNode? focusNode,
  bool isFocused = false,
}) {
  final t = AppThemeScope.of(context).settings;
  final theme = Theme.of(context);

  return Shortcuts(
    shortcuts: const <ShortcutActivator, Intent>{
      SingleActivator(LogicalKeyboardKey.arrowDown): NextFocusIntent(),
      SingleActivator(LogicalKeyboardKey.arrowUp): PreviousFocusIntent(),
    },
    child: Actions(
      actions: <Type, Action<Intent>>{
        NextFocusIntent: CallbackAction<NextFocusIntent>(
          onInvoke: (intent) {
            // Directional (non-wrapping): DOWN on the last row must not
            // jump back to the top of the page.
            FocusScope.of(context).focusInDirection(TraversalDirection.down);
            return null;
          },
        ),
        PreviousFocusIntent: CallbackAction<PreviousFocusIntent>(
          onInvoke: (intent) {
            FocusScope.of(context).focusInDirection(TraversalDirection.up);
            return null;
          },
        ),
      },
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(label, style: theme.textTheme.bodyMedium),
          ),
          Expanded(
            flex: 3,
            // Snap, don't tween — animated focus decorations jank TVs.
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: t.panel2,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isFocused ? t.accent : t.line,
                  width: isFocused ? 2 : 1,
                ),
                boxShadow: isFocused
                    ? [
                        BoxShadow(
                          color: t.accent.withValues(alpha: 0.25),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: value.clamp(0, items.length - 1),
                  focusNode: focusNode,
                  isExpanded: true,
                  icon: Icon(Icons.keyboard_arrow_down, color: t.dim),
                  items: List.generate(items.length, (index) {
                    return DropdownMenuItem<int>(
                      value: index,
                      child: Text(items[index]),
                    );
                  }),
                  onChanged: (v) {
                    if (v != null) onChanged(v);
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
