import 'package:flutter/material.dart';

/// The compact hero's one button — white pill, black glyph, the phone idiom.
class SpotlightHeroOpenPill extends StatelessWidget {
  final VoidCallback onTap;
  const SpotlightHeroOpenPill({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 26),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(21),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.play_arrow_rounded, size: 20, color: Colors.black),
            SizedBox(width: 6),
            Text(
              'Open',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
