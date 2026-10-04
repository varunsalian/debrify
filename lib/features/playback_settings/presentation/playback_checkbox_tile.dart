import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Widget buildCheckboxTile(
  BuildContext context, {
  required String title,
  required String subtitle,
  required bool value,
  required Function(bool) onChanged,
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
      // Snap, don't tween — animated focus decorations jank TVs.
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: isFocused ? t.panel2 : null,
          border: isFocused ? Border.all(color: t.accent, width: 2) : null,
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
        child: InkWell(
          focusNode: focusNode,
          onTap: () => onChanged(!value),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                // The row's InkWell is the single focus stop — the inner
                // Checkbox must not add a second DPAD stop.
                ExcludeFocus(
                  child: Checkbox(
                    value: value,
                    onChanged: (v) => onChanged(v ?? false),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: t.dim,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
