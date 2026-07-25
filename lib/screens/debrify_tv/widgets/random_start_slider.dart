import 'package:flutter/material.dart';

// Constants for random start percentage limits
const int randomStartPercentMin = 10;
const int randomStartPercentMax = 90;
const int _randomStartPercentStep = 5;

int clampRandomStartPercent(int? value, {int defaultValue = 20}) {
  final candidate = value ?? defaultValue;
  if (candidate < randomStartPercentMin) {
    return randomStartPercentMin;
  }
  if (candidate > randomStartPercentMax) {
    return randomStartPercentMax;
  }
  return candidate;
}

/// Picker for the random start percentage (10–90% in steps of 5).
///
/// A discrete [DropdownButtonFormField] rather than a slider: a slider traps
/// D-pad focus (left/right stepping fights the surrounding grid), so the remote
/// could never move past it. The dropdown just takes focus and opens on select.
/// [isAndroidTv] is kept for call-site compatibility but no longer branches the
/// UI — the dropdown is D-pad friendly everywhere.
class RandomStartSlider extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  final ValueChanged<int>? onChangeEnd;
  final bool isAndroidTv;

  const RandomStartSlider({
    super.key,
    required this.value,
    required this.isAndroidTv,
    required this.onChanged,
    this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textStyle = theme.textTheme.bodyMedium?.copyWith(
      color: Colors.white70,
      fontWeight: FontWeight.w600,
    );
    final helperStyle = theme.textTheme.bodySmall?.copyWith(
      color: Colors.white60,
    );

    final current = clampRandomStartPercent(value);
    // The 5-step grid, plus the current value if a legacy save ever landed
    // off-grid — so `value:` is always present in `items` (else Dropdown throws).
    final base = <int>[
      for (int v = randomStartPercentMin;
          v <= randomStartPercentMax;
          v += _randomStartPercentStep)
        v,
    ];
    final options = base.contains(current) ? base : ([...base, current]..sort());

    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: color, width: width),
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Random start within first $current%', style: textStyle),
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(
            value: current,
            isExpanded: true,
            dropdownColor: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(12),
            icon: const Icon(Icons.arrow_drop_down, color: Colors.white60),
            style: textStyle,
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: const Color(0xFF2A2A2A),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              // Visible accent border on focus so the remote's position is
              // obvious — the whole reason for the slider→dropdown swap.
              enabledBorder: border(Colors.white12, 1),
              focusedBorder: border(Colors.white, 2),
              border: border(Colors.white12, 1),
            ),
            items: [
              for (final v in options)
                DropdownMenuItem<int>(value: v, child: Text('$v%')),
            ],
            onChanged: (v) {
              if (v == null) return;
              final next = clampRandomStartPercent(v);
              onChanged(next);
              // A dropdown pick is a single discrete commit — fire the persist
              // callback too (the slider only persisted on change-end).
              onChangeEnd?.call(next);
            },
          ),
          const SizedBox(height: 8),
          Text(
            'Videos will jump to a random moment inside the first $current% of playback.',
            style: helperStyle,
          ),
        ],
      ),
    );
  }
}
