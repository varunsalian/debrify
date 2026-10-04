import 'package:debrify/widgets/detail/theme/detail_theme.dart';
import 'package:flutter/material.dart';

// ─── Season stepper (compact header ‹ ›) ─────────────────────────────────────
class _SeasonStepButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _SeasonStepButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // IconButton (not a bare InkWell) so the disabled state at the first/last
    // season keeps its button semantics for screen readers; the state-resolved
    // style adds the gold DPAD focus ring the default overlay lacks.
    // Hoisted out of the resolver closure, which is not build-time code.
    final t = DetailThemeScope.maybeOf(context);
    return IconButton(
      visualDensity: VisualDensity.compact,
      style: ButtonStyle(
        side: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.focused)
              ? BorderSide(color: t.focus, width: 2)
              : null,
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.focused)
              ? Colors.white.withValues(alpha: 0.10)
              : null,
        ),
      ),
      icon: Icon(
        icon,
        color: enabled ? Colors.white : Colors.white.withValues(alpha: 0.22),
      ),
      onPressed: enabled ? onTap : null,
    );
  }
}

typedef EpisodesPanelSeasonStep = _SeasonStepButton;
