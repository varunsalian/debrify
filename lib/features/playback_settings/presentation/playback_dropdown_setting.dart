import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Widget buildDropdownSetting(
  BuildContext context, {
  required String label,
  required String value,
  required Map<String, String> items,
  required Function(String) onChanged,
  FocusNode? focusNode,
  bool isFocused = false,
  bool enabled = true,
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
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: enabled ? null : t.dim2,
              ),
            ),
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
                  color: enabled && isFocused ? t.accent : t.line,
                  width: enabled && isFocused ? 2 : 1,
                ),
                boxShadow: enabled && isFocused
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
                child: DropdownButton<String>(
                  value: value,
                  focusNode: focusNode,
                  isExpanded: true,
                  icon: Icon(
                    Icons.keyboard_arrow_down,
                    color: enabled ? t.dim : t.dim2,
                  ),
                  items: items.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(
                            e.value,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: enabled
                      ? (v) {
                          if (v != null) onChanged(v);
                        }
                      : null,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
