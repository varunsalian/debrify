import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_values_state.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/tv_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef PlaybackNightModeSectionDependencies = ({
  BuildContext Function() context,
  Future<void> Function(int index) setNightModeIndex,
  PlaybackValuesState values,
});

class PlaybackNightModeSection {
  final PlaybackNightModeSectionDependencies _deps;
  PlaybackNightModeSection(this._deps);

  static const List<String> nightModeLabels = [
    'Off',
    'Low',
    'Medium',
    'High',
    'Higher',
    'Extreme',
    'Max',
    'Sleeping Baby',
  ];

  List<Widget> nightModeSettings() {
    final theme = Theme.of(_deps.context());
    final t = AppThemeScope.of(_deps.context()).settings;
    return [
      // Night Mode (Android TV only)
      if (_deps.values.isAndroidTv) ...[
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.nightlight_round, color: t.accent, size: 24),
                    const SizedBox(width: 8),
                    Text(
                      'Night Mode',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Boosts quiet sounds for late-night viewing without disturbing others',
                  style: theme.textTheme.bodySmall?.copyWith(color: t.dim),
                ),
                const SizedBox(height: 16),
                ...List.generate(nightModeLabels.length, (index) {
                  final isSelected = _deps.values.nightModeIndex == index;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Focus(
                      // Observer only: the InkWell below is the
                      // focus stop; a focusable wrapper would make
                      // each row cost two DPAD presses.
                      canRequestFocus: false,
                      skipTraversal: true,
                      onKeyEvent: (node, event) {
                        if (event is KeyDownEvent) {
                          if (isActivateKey(event.logicalKey)) {
                            _deps.setNightModeIndex(index);
                            return KeyEventResult.handled;
                          }
                        }
                        return KeyEventResult.ignored;
                      },
                      child: Builder(
                        builder: (context) {
                          final isFocused = Focus.of(context).hasFocus;
                          return InkWell(
                            onTap: () => _deps.setNightModeIndex(index),
                            borderRadius: BorderRadius.circular(8),
                            // Snap, don't tween (TV GPU rule).
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? t.panel2
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isFocused
                                      ? t.accent
                                      : isSelected
                                      ? t.accent
                                      : t.line,
                                  width: isFocused || isSelected ? 2 : 1,
                                ),
                                boxShadow: isFocused
                                    ? [
                                        BoxShadow(
                                          color: t.accent.withValues(
                                            alpha: 0.25,
                                          ),
                                          blurRadius: 12,
                                          offset: const Offset(0, 4),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Row(
                                children: [
                                  // Single focus stop per row —
                                  // keep the Radio off the DPAD
                                  // traversal order.
                                  ExcludeFocus(
                                    child: Radio<int>(
                                      value: index,
                                      groupValue: _deps.values.nightModeIndex,
                                      onChanged: (v) =>
                                          _deps.setNightModeIndex(v!),
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    nightModeLabels[index],
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: isSelected || isFocused
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                    ),
                                  ),
                                  if (index == 0) ...[
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
                                        'Recommended',
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                              color: t.accent,
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ],
    ];
  }
}
