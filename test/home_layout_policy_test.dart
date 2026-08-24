import 'package:debrify/screens/settings/tv_home_style_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('off-TV Spotlight shell policy', () {
    test('retains Spotlight while a newly mounted Home is loading', () {
      expect(
        shouldUseOffTvSpotlightShell(
          rawStyle: 'spotlight',
          loading: true,
          hasHero: false,
        ),
        isTrue,
      );
    });

    test('keeps Spotlight after its hero arrives', () {
      expect(
        shouldUseOffTvSpotlightShell(
          rawStyle: 'spotlight',
          loading: false,
          hasHero: true,
        ),
        isTrue,
      );
    });

    test('falls back only when loading finishes without a hero', () {
      expect(
        shouldUseOffTvSpotlightShell(
          rawStyle: 'spotlight',
          loading: false,
          hasHero: false,
        ),
        isFalse,
      );
    });

    test('never changes Classic or TV-only off-TV fallbacks', () {
      for (final style in ['classic', 'canvas', 'mosaic']) {
        expect(
          shouldUseOffTvSpotlightShell(
            rawStyle: style,
            loading: true,
            hasHero: true,
          ),
          isFalse,
          reason: '$style resolves to Classic off-TV',
        );
      }
    });
  });
}
