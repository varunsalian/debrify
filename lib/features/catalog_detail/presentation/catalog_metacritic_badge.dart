import 'package:flutter/material.dart';

class _MetacriticBadge extends StatelessWidget {
  final int score;
  const _MetacriticBadge({required this.score});

  @override
  Widget build(BuildContext context) {
    final Color bg;
    if (score >= 61) {
      bg = const Color(0xFF66CC33);
    } else if (score >= 40) {
      bg = const Color(0xFFFFCC33);
    } else {
      bg = const Color(0xFFFF0000);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        '$score',
        style: TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w900,
          height: 1.3,
        ),
      ),
    );
  }
}

typedef CatalogMetacriticBadge = _MetacriticBadge;

const catalogMetacriticBadgeConstructor = _MetacriticBadge.new;
