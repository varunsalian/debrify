import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';

class _SpotlightMetaPill extends StatelessWidget {
  final String label;
  final String value;

  const _SpotlightMetaPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final tv = app.debrifyTv;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: tv.fillWeak,
        borderRadius: app.shape.br(13),
        border: Border.all(color: tv.hairline),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: tv.textFaint,
              fontFamily: 'JetBrainsMono',
              fontSize: 8,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: app.core.tx,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

typedef DebrifyTvMetaPill = _SpotlightMetaPill;
