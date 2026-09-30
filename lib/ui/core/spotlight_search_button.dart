import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// The Spotlight shell's floating search button — a frosted circle over the
/// hero, mirroring the approved mock. Deliberately plain Material ink-free
/// (the board underneath is a photograph; a splash reads as damage).
class SpotlightSearchButton extends StatelessWidget {
  final VoidCallback onTap;
  const SpotlightSearchButton({super.key, required this.onTap});

  /// The button's geometry, named so the trailer layer's status chips can
  /// clear it by DERIVATION — a bare 66 over there would silently regress
  /// the clipped-"AMBIE…" overlap the moment this button moved or grew.
  static const double rightInset = 14;
  static const double diameter = 40;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipOval(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: diameter,
            height: diameter,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0x8C1E1E20),
              border: Border.all(color: const Color(0x1FFFFFFF)),
            ),
            child: const Icon(
              Icons.search_rounded,
              size: 20,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
