import 'package:flutter/material.dart';

import '../../theme/app_theme_scope.dart';

/// The row heading's provenance chip — "CINEMETA", "TRAKT" — the answer to
/// "filled by what?", demoted from the heading it used to open ("Cinemeta:
/// Popular") to a footnote beside the one it now follows ("Popular Movies").
///
/// Deliberately small: a hairline border and sub-caption type, so it is
/// visible without occupying the heading's space or reading as a button.
/// It is display-only on every device — the heading (and its chevron, off
/// TV) carries the interaction; the pill just states a fact.
///
/// Shared by both Home renderers (the Spotlight board's shelf titles and the
/// classic rails' [_railHeader]) so the two paths can't drift apart.
class RowTagPill extends StatelessWidget {
  final String text;

  /// Callers size this off their heading, not a global constant — the pill
  /// has to stay a footnote next to a 22px phone heading AND next to the TV
  /// board's quieter labels.
  final double fontSize;

  const RowTagPill(this.text, {super.key, this.fontSize = 10});

  @override
  Widget build(BuildContext context) {
    final tx = AppThemeScope.of(context).core.tx;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: fontSize * 0.7,
        vertical: fontSize * 0.28,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: tx.withValues(alpha: 0.22)),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        text.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          letterSpacing: fontSize * 0.1,
          height: 1.0,
          color: tx.withValues(alpha: 0.55),
        ),
      ),
    );
  }
}
