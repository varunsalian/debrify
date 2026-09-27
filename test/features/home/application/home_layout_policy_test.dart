import 'package:debrify/features/home/application/home_layout_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'layout capabilities preserve independent preview and theater choices',
    () {
      const expectations = {
        // Stage/live preview, catalog trailer, shell art, theater.
        'classic': (false, false, false, false),
        'spotlight': (true, true, true, true),
        'canvas': (true, true, true, true),
        'atrium': (true, true, false, false),
        'mosaic': (true, false, false, false),
        'promenade': (true, true, true, true),
        'deck': (true, true, false, true),
        'tonight': (true, true, false, false),
        // Unknown persisted values retain legacy dispatch rather than normalization.
        'future-layout': (true, false, false, false),
        '': (true, false, false, false),
        'Classic': (true, false, false, false),
      };
      for (final entry in expectations.entries) {
        expect(
          (
            isHomeStageLayout(entry.key),
            homeStageWantsAmbient(entry.key),
            homeStagePublishesShellArt(entry.key),
            homeStageTheaterEligible(entry.key),
          ),
          entry.value,
          reason: entry.key,
        );
      }
    },
  );

  test(
    'off-TV fallback depends on exact stored style and content readiness',
    () {
      for (final style in [
        'classic',
        'spotlight',
        'canvas',
        'atrium',
        'mosaic',
        'promenade',
        'deck',
        'tonight',
        'future-layout',
        '',
        'Spotlight',
      ]) {
        expect(
          effectiveOffTvHomeStyle(style),
          style == 'spotlight' ? 'spotlight' : 'classic',
        );
        for (final loading in [true, false]) {
          for (final hasHero in [true, false]) {
            expect(
              shouldUseOffTvSpotlightShell(
                rawStyle: style,
                loading: loading,
                hasHero: hasHero,
              ),
              style == 'spotlight' && (loading || hasHero),
              reason: '$style loading=$loading hasHero=$hasHero',
            );
          }
        }
      }
    },
  );
}
