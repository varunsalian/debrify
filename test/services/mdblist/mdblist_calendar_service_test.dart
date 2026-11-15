import 'dart:async';

import 'package:debrify/models/trakt/trakt_calendar_entry.dart';
import 'package:debrify/services/mdblist/mdblist_calendar_service.dart';
import 'package:debrify/services/mdblist/mdblist_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('MDBList calendar parser accepts episodes and rejects other events', () {
    final resolved = {
      'year': 1999,
      'ids': {'imdb': 'tt0388629', 'trakt': 37696},
    };
    final episode = TraktCalendarEntry.fromMdblistCalendarJson(
      _episodeEvent(),
      resolvedShow: resolved,
    );
    expect(episode, isNotNull);
    expect(episode!.showImdbId, 'tt0388629');
    expect(episode.seasonNumber, 23);
    expect(episode.episodeNumber, 1175);
    expect(episode.firstAiredLocal, DateTime(2026, 8, 23));
    expect(
      TraktCalendarEntry.fromMdblistCalendarJson({
        ..._episodeEvent(),
        'type': 'movie',
      }),
      isNull,
    );
  });

  test(
    'calendar resolves each show once and preserves last good on failure',
    () async {
      var failing = false;
      var resolveCalls = 0;
      final service = MdblistCalendarService.forTesting(
        fetcher: (_, _) async => failing
            ? const MdblistResult.failure(MdblistResultKind.transientFailure)
            : MdblistResult.success([
                _episodeEvent(),
                {..._episodeEvent(), 'episode_number': 1176},
                {..._episodeEvent(), 'type': 'movie'},
              ]),
        resolver: (_) async {
          resolveCalls++;
          return const MdblistResult.success({
            'year': 1999,
            'ids': {'imdb': 'tt0388629'},
          });
        },
      );

      // The rollout flag deliberately keeps the singleton offline; the test
      // constructor still exercises parsing through its injected collaborators.
      final entries = await service.debugLoadForTesting(
        DateTime(2026, 8, 1),
        DateTime(2026, 8, 31),
      );
      expect(entries.values.expand((e) => e), hasLength(2));
      expect(resolveCalls, 1);

      failing = true;
      final retained = await service.debugLoadForTesting(
        DateTime(2026, 8, 1),
        DateTime(2026, 8, 31),
        force: true,
      );
      expect(retained.values.expand((e) => e), hasLength(2));
    },
  );

  group('strict reads and profile switches', () {
    MdblistCalendarService service({
      required Future<MdblistResult<List<Map<String, dynamic>>>> Function()
      fetch,
    }) => MdblistCalendarService.forTesting(
      fetcher: (_, _) => fetch(),
      resolver: (_) async => const MdblistResult.success({
        'year': 1999,
        'ids': {'imdb': 'tt0388629'},
      }),
    );
    final start = DateTime(2026, 8, 1);
    final end = DateTime(2026, 8, 31);

    test('a failed read throws when strict and is empty otherwise', () async {
      final calendar = service(
        fetch: () async =>
            const MdblistResult.failure(MdblistResultKind.transientFailure),
      );
      await expectLater(
        calendar.getRange(start, end, strict: true),
        throwsStateError,
      );
      expect(await calendar.getRange(start, end), isEmpty);
    });

    test('a strict and a plain caller sharing one read each get their own '
        'answer', () async {
      final gate = Completer<MdblistResult<List<Map<String, dynamic>>>>();
      final calendar = service(fetch: () => gate.future);
      final strict = calendar.getRange(start, end, strict: true);
      final plain = calendar.getRange(start, end);
      gate.complete(
        const MdblistResult.failure(MdblistResultKind.transientFailure),
      );
      await expectLater(strict, throwsStateError);
      expect(await plain, isEmpty);
    });

    test('a read that started before a profile switch is not cached', () async {
      var calls = 0;
      final gate = Completer<void>();
      final calendar = service(
        fetch: () async {
          calls++;
          if (calls == 1) await gate.future;
          return MdblistResult.success([_episodeEvent()]);
        },
      );
      final stale = calendar.getRange(start, end);
      calendar.resetProfileScope();
      gate.complete();
      await stale;
      await calendar.getRange(start, end);
      expect(calls, 2);
    });
  });
}

Map<String, dynamic> _episodeEvent() => {
  'id': 'episode-7550211-2026-08-23',
  'type': 'episode',
  'start': '2026-08-23',
  'title': 'One Piece',
  'episode_title': 'Elbaph in Flames!',
  'description': 'Episode overview',
  'show_tmdb': 37854,
  'season_number': 23,
  'episode_number': 1175,
  'poster': 'https://image.tmdb.org/poster.jpg',
};
