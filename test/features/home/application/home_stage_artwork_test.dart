import 'package:debrify/features/home/application/home_stage_metadata.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'wide artwork preserves background, derived still, poster and empty precedence',
    () {
      StremioMeta item({
        String id = 'a',
        String? imdb,
        String? background,
        String? poster,
      }) => StremioMeta(
        id: id,
        imdbId: imdb,
        type: 'movie',
        name: 'A',
        background: background,
        poster: poster,
      );
      expect(
        homeStageWideArtwork(
          item(id: 'tt1', background: 'background', poster: 'poster'),
        ),
        'background',
      );
      expect(
        homeStageWideArtwork(
          item(id: 'tt1', imdb: 'tt2', background: '', poster: 'poster'),
        ),
        'https://images.metahub.space/background/medium/tt2/img',
      );
      expect(
        homeStageWideArtwork(item(id: 'tt1', poster: 'poster')),
        'https://images.metahub.space/background/medium/tt1/img',
      );
      expect(homeStageWideArtwork(item(poster: 'poster')), 'poster');
      expect(homeStageWideArtwork(item(background: '', poster: '')), isNull);
      expect(homeStageWideArtwork(item()), isNull);
    },
  );
  test('stage field fallback preserves nonempty strings without trimming', () {
    expect(homeStageFirstNonEmpty('fresh', 'old'), 'fresh');
    expect(homeStageFirstNonEmpty('', 'old'), 'old');
    expect(homeStageFirstNonEmpty(null, ''), isNull);
    expect(homeStageFirstNonEmpty(null, null), isNull);
    expect(homeStageFirstNonEmpty(' ', 'old'), ' ');
  });
}
