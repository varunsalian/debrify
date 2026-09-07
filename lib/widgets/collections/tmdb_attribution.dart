import 'package:flutter/material.dart';

/// Official approved blue-short logo, rasterized without changing its colors
/// or proportions. Source: themoviedb.org/about/logos-attribution.
class TmdbAttribution extends StatelessWidget {
  const TmdbAttribution({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Image.asset(
          'assets/images/tmdb-logo.png',
          width: 110,
          semanticLabel: 'TMDB',
        ),
        const SizedBox(height: 10),
        const Text(
          'This product uses the TMDB API but is not endorsed or certified by TMDB.',
          style: TextStyle(fontSize: 12),
        ),
      ],
    ),
  );
}
