import 'package:debrify/features/home/presentation/home_hero_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'region rejects unusable bounds and retains width-led minimum geometry',
    () {
      for (final (w, h) in [
        (0.0, 300.0),
        (-1.0, 300.0),
        (800.0, 0.0),
        (double.infinity, 300.0),
        (800.0, double.nan),
        (479.0, 300.0),
        (800.0, 169.0),
      ]) {
        expect(homeHeroTrailerRegionRect(w, h), isNull);
      }
      expect(
        homeHeroTrailerRegionRect(480, 170),
        const Rect.fromLTWH(120, 0, 360, 170),
      );
      expect(
        homeHeroTrailerRegionRect(1000, 300),
        const Rect.fromLTWH(440, 0, 560, 300),
      );
    },
  );

  test('edge feather retains eased alpha and stop progression', () {
    final box =
        homeHeroEdgeFeather(
              Alignment.centerLeft,
              Alignment.centerRight,
              Colors.black,
              0.16,
            )
            as DecoratedBox;
    final gradient =
        (box.decoration as BoxDecoration).gradient! as LinearGradient;
    expect(gradient.begin, Alignment.centerLeft);
    expect(gradient.end, Alignment.centerRight);
    expect(gradient.colors.map((c) => c.a), [1, 0.86, 0.42, 0.13, 0]);
    expect(gradient.stops, [0.0, 0.16 * 0.28, 0.16 * 0.56, 0.16 * 0.80, 0.16]);
  });
}
