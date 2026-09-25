import 'dart:async';

import 'package:debrify/services/tracker_identity_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'IMDb and TMDB IDs retain their provider and movie/show namespace',
    () async {
      final service = TrackerIdentityService(
        fetchSimkl: (_) async => fail('Unexpected lookup'),
      );
      expect(await service.resolve('tt1234567', 'series'), {
        'imdb': 'tt1234567',
      });
      expect(await service.resolve('tmdb:237243', 'series'), {'tmdb': 237243});
      expect(await service.resolve('tmdb:movie:237243', 'movie'), {
        'tmdb': 237243,
      });
      expect(await service.resolve('tmdb:movie:237243', 'series'), isNull);
      expect(await service.resolve('custom:237243', 'series'), isNull);
      expect(await service.resolve('Big Brother', 'series'), isNull);
    },
  );

  test('Simkl details must echo the requested ID and type', () async {
    for (final response in <Object?>[
      null,
      {
        'type': 'show',
        'ids': {'simkl': 123, 'tmdb': 10160},
      },
      {
        'type': 'movie',
        'ids': {'simkl': 2274121, 'tmdb': 237243},
      },
      {
        'type': 'show',
        'ids': {'simkl': 2274121},
      },
      [
        {
          'type': 'show',
          'ids': {'simkl': 2274121, 'tmdb': 237243},
        },
        {
          'type': 'show',
          'ids': {'simkl': 2274121, 'tmdb': 10160},
        },
      ],
    ]) {
      final service = TrackerIdentityService(
        fetchSimkl: (url) async {
          expect(url, 'https://api.simkl.com/tv/2274121');
          return response;
        },
      );
      expect(await service.resolve('simkl:2274121', 'series'), isNull);
    }
  });

  test(
    'Simkl lookup prefers exact TMDB ID over a stale IMDb association',
    () async {
      final response = Completer<dynamic>();
      var calls = 0;
      final service = TrackerIdentityService(
        fetchSimkl: (_) {
          calls++;
          return response.future;
        },
      );
      final first = service.resolve('simkl:2274121', 'series');
      final second = service.resolve('simkl:2274121', 'series');
      response.complete({
        'type': 'show',
        'ids': {'simkl': 2274121, 'tmdb': 237243, 'imdb': 'tt0251497'},
      });
      expect(await first, {'tmdb': 237243});
      expect(await second, {'tmdb': 237243});
      expect(await service.resolve('simkl:2274121', 'series'), {
        'tmdb': 237243,
      });
      expect(calls, 1);
    },
  );

  test(
    'failed mapping retries and movie results cannot satisfy show lookups',
    () async {
      var calls = 0;
      final service = TrackerIdentityService(
        fetchSimkl: (url) async {
          calls++;
          if (calls == 1) throw StateError('unavailable');
          return {
            'type': url.contains('/movies/') ? 'movie' : 'show',
            'ids': {'simkl': 42, 'tmdb': url.contains('/movies/') ? 7 : 8},
          };
        },
      );
      expect(await service.resolve('simkl:42', 'movie'), isNull);
      expect(await service.resolve('simkl:42', 'movie'), {'tmdb': 7});
      expect(await service.resolve('simkl:42', 'series'), {'tmdb': 8});
      expect(calls, 3);
    },
  );

  test(
    'Simkl can use an explicitly mapped IMDb or TVDB ID without searching',
    () async {
      for (final ids in [
        {'simkl': 42, 'imdb': 'tt1234567'},
        {'simkl': 42, 'tvdb': 440642},
      ]) {
        final service = TrackerIdentityService(
          fetchSimkl: (_) async => {'type': 'show', 'ids': ids},
        );
        expect(
          await service.resolve('simkl:42', 'series'),
          Map.of(ids)..remove('simkl'),
        );
      }
    },
  );
}
