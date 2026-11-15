import 'package:debrify/services/imdb_enrichment_service.dart';
import 'package:debrify/services/mdblist/mdblist_rotten_tomatoes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MdblistRottenTomatoes.criticsScore', () {
    test('reads the tomatoes entry, not the audience popcorn score', () {
      final title = <String, dynamic>{
        'ratings': [
          {'source': 'imdb', 'value': 8.1, 'score': 81},
          {'source': 'popcorn', 'value': 71, 'score': 71},
          {'source': 'tomatoes', 'value': 93, 'score': 93},
        ],
      };
      expect(MdblistRottenTomatoes.criticsScore(title), 93);
    });

    test('a title with no Tomatometer has no score', () {
      expect(
        MdblistRottenTomatoes.criticsScore({
          'ratings': [
            {'source': 'tomatoes', 'value': null, 'score': null},
          ],
        }),
        isNull,
      );
      expect(MdblistRottenTomatoes.criticsScore({'ratings': []}), isNull);
      expect(MdblistRottenTomatoes.criticsScore({}), isNull);
      expect(MdblistRottenTomatoes.criticsScore(null), isNull);
    });

    test('0% is a real reading; out-of-range values are rejected', () {
      Map<String, dynamic> with_(Object value) => {
        'ratings': [
          {'source': 'tomatoes', 'value': value},
        ],
      };
      expect(MdblistRottenTomatoes.criticsScore(with_(0)), 0);
      expect(MdblistRottenTomatoes.criticsScore(with_('87')), 87);
      expect(MdblistRottenTomatoes.criticsScore(with_(140)), isNull);
    });
  });

  test('withRottenTomatoes keeps every IMDb readout', () {
    const imdb = ImdbEnrichment(
      rating: 7.9,
      voteCount: 1200,
      metacriticScore: 74,
      certificate: 'PG-13',
      runtimeMinutes: 118,
      top250Rank: 42,
      genres: ['Drama'],
    );
    final joined = imdb.withRottenTomatoes(91);
    expect(joined.rottenTomatoes, 91);
    expect(joined.rating, 7.9);
    expect(joined.voteCount, 1200);
    expect(joined.metacriticScore, 74);
    expect(joined.certificate, 'PG-13');
    expect(joined.runtimeMinutes, 118);
    expect(joined.top250Rank, 42);
    expect(joined.genres, ['Drama']);
    // Credits rebuilds keep the joined score too.
    expect(joined.withCredits(cast: const []).rottenTomatoes, 91);
  });
}
