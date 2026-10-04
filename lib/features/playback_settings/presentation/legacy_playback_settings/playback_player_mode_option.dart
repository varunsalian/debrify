import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_core_state.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';

typedef PlaybackPlayerModeOptionDependencies = ({
  PlaybackCoreState core,
  Future<void> Function(String mode) setDefaultPlayerMode,
});

class PlaybackPlayerModeOption {
  final PlaybackPlayerModeOptionDependencies _deps;
  PlaybackPlayerModeOption(this._deps);

  Widget buildPlayerModeOption(
    BuildContext context, {
    required String value,
    required String title,
    required String subtitle,
    required IconData icon,
    bool recommended = false,
    bool disabled = false,
    FocusNode? focusNode,
  }) {
    final t = AppThemeScope.of(context).settings;
    final theme = Theme.of(context);
    final isSelected = _deps.core.defaultPlayerMode == value;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      // Non-focusable wrapper only observes the InkWell's focus so the row
      // can paint a DPAD focus ring (same idiom as the Night Mode rows).
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        child: Builder(
          builder: (context) {
            final isFocused = Focus.of(context).hasFocus;
            return InkWell(
              focusNode: focusNode,
              canRequestFocus: !disabled,
              onTap: disabled ? null : () => _deps.setDefaultPlayerMode(value),
              borderRadius: BorderRadius.circular(12),
              // Snap, don't tween — per-keypress decoration lerps jank TVs.
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isSelected || isFocused
                      ? t.panel2
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isFocused || isSelected ? t.accent : t.line,
                    width: isFocused || isSelected ? 2 : 1,
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
                child: Row(
                  children: [
                    // The row is the single focus stop — the inner Radio must
                    // not add a second DPAD stop.
                    ExcludeFocus(
                      child: Radio<String>(
                        value: value,
                        groupValue: _deps.core.defaultPlayerMode,
                        onChanged: disabled
                            ? null
                            : (v) => _deps.setDefaultPlayerMode(v!),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      icon,
                      size: 20,
                      color: isSelected
                          ? t.accent
                          : disabled
                          ? t.dim2
                          : t.dim,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                title,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                  color: disabled ? t.dim2 : null,
                                ),
                              ),
                              if (recommended) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: t.accent.withValues(alpha: 0.16),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'Default',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: t.accent,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          Text(
                            subtitle,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: disabled ? t.dim2 : t.dim,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
