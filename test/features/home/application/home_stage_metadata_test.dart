import 'package:debrify/features/home/application/home_stage_metadata.dart';
import 'package:debrify/features/home/application/home_tonight_caption_policy.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'logo derivation preserves explicit identity precedence and absence',
    () {
      expect(
        homeStageLogoUrl(const StremioMeta(id: 'a', type: 'movie', name: 'A')),
        isNull,
      );
      expect(
        homeStageLogoUrl(
          const StremioMeta(id: 'tt123', type: 'movie', name: 'A'),
        ),
        'https://images.metahub.space/logo/medium/tt123/img',
      );
      expect(
        homeStageLogoUrl(
          const StremioMeta(
            id: 'tt123',
            imdbId: 'tt456',
            type: 'movie',
            name: 'A',
          ),
        ),
        'https://images.metahub.space/logo/medium/tt456/img',
      );
    },
  );
  test(
    'enrichment accepts raw or canonical identity and rejects unrelated titles',
    () {
      const original = StremioMeta(
        id: 'tmdb:603',
        imdbId: 'tt0133093',
        type: 'movie',
        name: 'Original',
      );
      expect(
        sameHomeStageTitle(
          original,
          const StremioMeta(id: 'tmdb:603', type: 'movie', name: 'Same'),
        ),
        isTrue,
      );
      expect(
        sameHomeStageTitle(
          original,
          const StremioMeta(id: 'tt0133093', type: 'movie', name: 'Canonical'),
        ),
        isTrue,
      );
      expect(
        sameHomeStageTitle(
          original,
          const StremioMeta(
            id: 'other',
            imdbId: 'tt0133093',
            type: 'movie',
            name: 'Alias',
          ),
        ),
        isTrue,
      );
      expect(
        sameHomeStageTitle(
          original,
          const StremioMeta(id: 'other', type: 'movie', name: 'Unrelated'),
        ),
        isFalse,
      );
      expect(
        sameHomeStageTitle(
          const StremioMeta(id: 'a', type: 'movie', name: 'A'),
          const StremioMeta(id: 'b', type: 'movie', name: 'B'),
        ),
        isFalse,
      );
    },
  );
  test(
    'remaining-time display retains minute parsing, rounding and progress bounds',
    () {
      for (final (runtime, progress, expected) in <(String?, double?, String?)>[
        (null, .5, null), ('60 min', null, null), ('60 min', 0, null),
        ('60 min', -.1, null), ('60 min', .25, '45 min left'),
        ('61 min', .5, '31 min left'), ('60 min', 1, null),
        ('60 min', 2, null), ('unknown', .5, null), ('0 min', .5, null),
        // Preserve the existing first-number parser; broader runtime parsing is separate work.
        ('2h 30m', .5, '1 min left'),
      ]) {
        expect(
          homeTonightTimeLeft(runtime, progress),
          expected,
          reason: '$runtime at $progress',
        );
      }
    },
  );
}
