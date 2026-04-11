import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/models/trakt/trakt_calendar_entry.dart';

void main() {
  group('TraktCalendarEntry.fromTraktJson', () {
    Map<String, dynamic> sampleJson({
      String? firstAired = '2026-04-15T02:00:00.000Z',
      int season = 2,
      int episode = 5,
      String showTitle = 'Severance',
      String? imdb = 'tt11280740',
      int? traktId = 12345,
    }) =>
        {
          'first_aired': firstAired,
          'episode': {
            'season': season,
            'number': episode,
            'title': 'Chikhai Bardo',
            'overview': 'An episode overview.',
            'runtime': 55,
          },
          'show': {
            'title': showTitle,
            'year': 2022,
            'ids': {
              'imdb': imdb,
              'trakt': traktId,
            },
          },
        };

    test('parses a valid Trakt calendar entry', () {
      final entry = TraktCalendarEntry.fromTraktJson(sampleJson());
      expect(entry, isNotNull);
      expect(entry!.showTitle, 'Severance');
      expect(entry.showImdbId, 'tt11280740');
      expect(entry.showTraktId, 12345);
      expect(entry.seasonNumber, 2);
      expect(entry.episodeNumber, 5);
      expect(entry.episodeTitle, 'Chikhai Bardo');
      expect(entry.runtimeMinutes, 55);
      expect(entry.firstAiredUtc.isUtc, isTrue);
      expect(entry.firstAiredUtc.year, 2026);
      expect(entry.firstAiredUtc.month, 4);
      expect(entry.firstAiredUtc.day, 15);
    });

    test('isNewShow is true for S01E01', () {
      final entry = TraktCalendarEntry.fromTraktJson(
        sampleJson(season: 1, episode: 1),
      );
      expect(entry!.isNewShow, isTrue);
      expect(entry.isSeasonPremiere, isTrue);
    });

    test('isSeasonPremiere is true for any SxxE01', () {
      final entry = TraktCalendarEntry.fromTraktJson(
        sampleJson(season: 3, episode: 1),
      );
      expect(entry!.isNewShow, isFalse);
      expect(entry.isSeasonPremiere, isTrue);
    });

    test('regular episode has neither flag', () {
      final entry = TraktCalendarEntry.fromTraktJson(
        sampleJson(season: 2, episode: 5),
      );
      expect(entry!.isNewShow, isFalse);
      expect(entry.isSeasonPremiere, isFalse);
    });

    test('returns null when first_aired is missing', () {
      final entry = TraktCalendarEntry.fromTraktJson(
        sampleJson(firstAired: null),
      );
      expect(entry, isNull);
    });

    test('returns null when first_aired is malformed', () {
      final json = sampleJson();
      json['first_aired'] = 'not-a-date';
      final entry = TraktCalendarEntry.fromTraktJson(json);
      expect(entry, isNull);
    });

    test('returns null when show title is missing', () {
      final entry = TraktCalendarEntry.fromTraktJson(
        sampleJson(showTitle: ''),
      );
      expect(entry, isNull);
    });

    test('returns null when episode number is missing', () {
      final json = sampleJson();
      (json['episode'] as Map).remove('number');
      final entry = TraktCalendarEntry.fromTraktJson(json);
      expect(entry, isNull);
    });

    test('handles missing optional fields gracefully', () {
      final json = sampleJson();
      (json['episode'] as Map).remove('overview');
      (json['episode'] as Map).remove('runtime');
      final entry = TraktCalendarEntry.fromTraktJson(json);
      expect(entry, isNotNull);
      expect(entry!.episodeOverview, isNull);
      expect(entry.runtimeMinutes, isNull);
    });

    test('falls back to metahub poster when imdb is present', () {
      final entry = TraktCalendarEntry.fromTraktJson(sampleJson());
      expect(
        entry!.posterUrl,
        'https://images.metahub.space/poster/medium/tt11280740/img',
      );
    });

    test('poster is null when imdb is missing', () {
      final entry = TraktCalendarEntry.fromTraktJson(sampleJson(imdb: null));
      expect(entry!.posterUrl, isNull);
    });

    test('firstAiredLocal is the local-converted UTC', () {
      final entry = TraktCalendarEntry.fromTraktJson(sampleJson());
      expect(entry!.firstAiredLocal, entry.firstAiredUtc.toLocal());
    });
  });
}
