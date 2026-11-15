import 'package:flutter/material.dart';

/// "RT 93%" — the Rotten Tomatoes Tomatometer, red when Fresh (60% and up)
/// and green when Rotten, the site's own two colours. Text only: no logo.
class RottenTomatoesBadge extends StatelessWidget {
  final int score;
  final double fontSize;

  const RottenTomatoesBadge({
    super.key,
    required this.score,
    this.fontSize = 11,
  });

  static bool isFresh(int score) => score >= 60;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Rotten Tomatoes $score percent',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: isFresh(score)
              ? const Color(0xFFFA320A)
              : const Color(0xFF0A8F3C),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          'RT $score%',
          style: TextStyle(
            color: Colors.white,
            fontSize: fontSize,
            fontWeight: FontWeight.w900,
            height: 1.3,
          ),
        ),
      ),
    );
  }
}
