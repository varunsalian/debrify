import 'package:flutter/material.dart';
import '../../../theme/app_theme_scope.dart';

const double _kTonightTitleSize = 26;
const double _kTonightHeaderPad = 34;

double homeTonightHeaderHeight(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(_kTonightTitleSize) * 1.35 +
    _kTonightHeaderPad;

Widget buildHomeTonightHeader({
  required BuildContext context,
  required int inProgress,
  required DateTime now,
}) {
  final app = AppThemeScope.of(context);
  const days = [
    'MONDAY',
    'TUESDAY',
    'WEDNESDAY',
    'THURSDAY',
    'FRIDAY',
    'SATURDAY',
    'SUNDAY',
  ];
  // A weekday word, not a clock: a minute-accurate label would need a timer
  // ticking on the home board for the whole session.
  final day = days[(now.weekday - 1).clamp(0, 6)];
  return Align(
    alignment: Alignment.bottomLeft,
    child: Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            'Tonight',
            style: TextStyle(
              color: app.core.tx,
              fontSize: _kTonightTitleSize,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(width: 14),
          Text(
            day,
            style: TextStyle(
              color: app.fade(app.core.tx, 0.40),
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.2,
            ),
          ),
          const Spacer(),
          if (inProgress > 0)
            Text(
              '$inProgress IN PROGRESS',
              style: TextStyle(
                color: app.fade(app.core.tx, 0.40),
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 2.2,
              ),
            ),
        ],
      ),
    ),
  );
}
