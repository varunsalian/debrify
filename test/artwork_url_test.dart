import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/utils/artwork_url.dart';

void main() {
  group('highQualityArtworkUrl', () {
    test('upgrades MetaHub medium posters and backdrops', () {
      expect(
        highQualityArtworkUrl(
          'https://images.metahub.space/poster/medium/tt123/img',
        ),
        'https://images.metahub.space/poster/large/tt123/img',
      );
      expect(
        highQualityArtworkUrl(
          'https://images.metahub.space/background/medium/tt123/img?foo=bar',
        ),
        'https://images.metahub.space/background/large/tt123/img?foo=bar',
      );
    });

    test('leaves other providers and already-large art alone', () {
      expect(
        highQualityArtworkUrl('https://image.tmdb.org/t/p/w500/poster.jpg'),
        'https://image.tmdb.org/t/p/w500/poster.jpg',
      );
      expect(
        highQualityArtworkUrl(
          'https://images.metahub.space/poster/large/tt123/img',
        ),
        'https://images.metahub.space/poster/large/tt123/img',
      );
    });

    test('preserves absent artwork', () {
      expect(highQualityArtworkUrl(null), isNull);
      expect(highQualityArtworkUrl(''), isEmpty);
    });
  });
}
