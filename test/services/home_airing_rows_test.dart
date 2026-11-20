import 'dart:async';

import 'package:debrify/features/ledger/models/ledger_brand.dart';
import 'package:debrify/features/home/application/home_row_order.dart';
import 'package:debrify/features/home/data/home_board_services.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/models/trakt/trakt_calendar_entry.dart';
import 'package:debrify/services/home_airing_rows.dart';
import 'package:debrify/services/home_list_rows.dart';
import 'package:debrify/services/trakt/trakt_calendar_service.dart';
import 'package:flutter_test/flutter_test.dart';

// Friday 2026-11-13, 18:00 local.
final _now = DateTime(2026, 11, 13, 18);

TraktCalendarEntry _ep(
  String? imdb,
  DateTime local, {
  int season = 1,
  int episode = 1,
  String title = 'Show',
}) => TraktCalendarEntry(
  firstAiredUtc: local.toUtc(),
  firstAiredLocal: local,
  showTitle: title,
  showYear: 2024,
  showImdbId: imdb,
  showTraktId: null,
  seasonNumber: season,
  episodeNumber: episode,
  episodeTitle: null,
  episodeOverview: null,
  runtimeMinutes: null,
  posterUrl: 'https://img/$imdb.jpg',
);

const _empty = (items: <StremioMeta>[], failed: false);

void main() {
  group('HomeAiringSoon.build', () {
    test('one card per show for its soonest episode, soonest show first', () {
      final built = HomeAiringSoon.build(
        [
          _ep('tt2', DateTime(2026, 11, 16, 21), season: 3, episode: 2),
          _ep('tt1', DateTime(2026, 11, 14, 20), season: 2, episode: 6),
          _ep('tt1', DateTime(2026, 11, 14, 20), season: 2, episode: 5),
          _ep('tt1', DateTime(2026, 11, 15, 20), season: 2, episode: 7),
        ],
        now: _now,
        exactTimes: true,
      );
      expect(built.items.map((m) => m.id), ['tt1', 'tt2']);
      expect(built.episodes['tt1']!.label, 'Tomorrow · S2E5');
      expect(built.episodes['tt1']!.season, 2);
      expect(built.episodes['tt1']!.episode, 5);
      expect(built.episodes['tt2']!.label, 'Mon · S3E2');
      final card = built.items.first;
      expect(card.type, 'series');
      expect(card.imdbId, 'tt1');
      expect(card.poster, 'https://img/tt1.jpg');
    });

    test('with air times, an episode that already aired today is gone', () {
      final built = HomeAiringSoon.build(
        [
          _ep('tt1', DateTime(2026, 11, 13, 9)),
          _ep('tt2', DateTime(2026, 11, 13, 22)),
        ],
        now: _now,
        exactTimes: true,
      );
      expect(built.items.map((m) => m.id), ['tt2']);
      expect(built.episodes['tt2']!.label, 'Today · S1E1');
    });

    test('date-only calendars keep everything dated today', () {
      final built = HomeAiringSoon.build(
        [
          _ep('tt1', DateTime(2026, 11, 13)),
          _ep('tt0', DateTime(2026, 11, 12)),
        ],
        now: _now,
        exactTimes: false,
      );
      expect(built.items.map((m) => m.id), ['tt1']);
    });

    test('shows without an IMDb id are skipped; the row is capped', () {
      final built = HomeAiringSoon.build(
        [
          _ep(null, DateTime(2026, 11, 14)),
          for (var i = 0; i < HomeAiringSoon.maxShows + 5; i++)
            _ep('tt$i', DateTime(2026, 11, 14, 20, i)),
        ],
        now: _now,
        exactTimes: true,
      );
      expect(built.items, hasLength(HomeAiringSoon.maxShows));
      expect(built.items.every((m) => m.id.startsWith('tt')), isTrue);
    });
  });

  group('HomeAiringSoon.dayLabel', () {
    test('counts calendar days, not 24-hour spans', () {
      final today = DateTime(2027, 3, 13);
      expect(
        HomeAiringSoon.dayLabel(DateTime(2027, 3, 13, 23), today),
        'Today',
      );
      expect(
        HomeAiringSoon.dayLabel(DateTime(2027, 3, 14, 1), today),
        'Tomorrow',
      );
      // 2027-03-14 is a 23-hour day where clocks spring forward (US). Run
      // with TZ=America/New_York to exercise it.
      expect(
        HomeAiringSoon.dayLabel(
          DateTime(2027, 3, 15, 20),
          DateTime(2027, 3, 14),
        ),
        'Tomorrow',
      );
      expect(HomeAiringSoon.dayLabel(DateTime(2027, 3, 15, 20), today), 'Mon');
    });
  });

  group('calendar reads for the row', () {
    test(
      'a failed Trakt read throws in strict mode and is never cached',
      () async {
        var calls = 0;
        var fail = true;
        final service = TraktCalendarService.forTesting(
          fetcher: (start, days) async {
            calls++;
            if (fail) throw StateError('offline');
            return [_ep('tt1', DateTime(2026, 11, 14, 20))];
          },
        );
        final today = DateTime(2026, 11, 13);
        final end = DateTime(2026, 11, 20);
        await expectLater(
          service.getRange(today, end, strict: true),
          throwsStateError,
        );
        // The Calendar tab's non-strict read still gets an empty result.
        expect(await service.getRange(today, end), isEmpty);
        fail = false;
        final recovered = await service.getRange(today, end, strict: true);
        expect(recovered.values.expand((e) => e), hasLength(1));
        expect(calls, 3, reason: 'failures must not be cached');
      },
    );

    test(
      'a read that started before invalidate cannot refill the cache',
      () async {
        var calls = 0;
        final gate = Completer<void>();
        final service = TraktCalendarService.forTesting(
          fetcher: (start, days) async {
            calls++;
            if (calls == 1) await gate.future;
            return [_ep('tt1', DateTime(2026, 11, 14, 20))];
          },
        );
        final today = DateTime(2026, 11, 13);
        final stale = service.getRange(today, today);
        service.invalidate(); // e.g. a profile switch mid-read
        gate.complete();
        await stale;
        await service.getRange(today, today);
        expect(calls, 2, reason: 'the old read was not cached');
      },
    );

    test('a failed airing load keeps the row it already had', () async {
      final service = HomeListRowsService(
        traktLoad: (_) async => _empty,
        traktUserLists: () async => const [],
        simklLoad: (_) async => _empty,
        mdblistMine: () async => const [],
        mdblistLiked: () async => const [],
        mdblistTop: () async => const [],
        airingLoad: () async =>
            (items: <StremioMeta>[], row: null, failed: true),
      );
      final previous = HomeListSection(
        rowId: HomeExtraRowIds.airingSoon,
        title: 'Airing soon',
        items: [StremioMeta(id: 'tt1', type: 'series', name: 'One')],
        airing: const HomeAiringRow(episodes: {}, fromTrakt: true),
      );
      final rows = await service.resolve(
        const [(id: HomeExtraRowIds.airingSoon, title: 'Airing soon')],
        previous: [previous],
      );
      expect(rows, [same(previous)]);
    });
  });

  group('HomeListRowsService.resolve', () {
    HomeListRowsService service(
      Future<({List<StremioMeta> items, HomeAiringRow? row, bool failed})>
      Function()
      load,
    ) => HomeListRowsService(
      traktLoad: (_) async => _empty,
      traktUserLists: () async => const [],
      simklLoad: (_) async => _empty,
      mdblistMine: () async => const [],
      mdblistLiked: () async => const [],
      mdblistTop: () async => const [],
      airingLoad: load,
    );

    const enabled = [(id: HomeExtraRowIds.airingSoon, title: 'Airing soon')];

    test('an enabled row carries its cards and each next episode', () async {
      const row = HomeAiringRow(
        episodes: {
          'tt1': HomeAiringEpisode(season: 2, episode: 5, label: 'Fri · S2E5'),
        },
        fromTrakt: true,
      );
      final rows = await service(
        () async => (
          items: [StremioMeta(id: 'tt1', type: 'series', name: 'One')],
          row: row,
          failed: false,
        ),
      ).resolve(enabled);
      expect(rows, hasLength(1));
      final section = rows.single;
      expect(section.rowId, HomeExtraRowIds.airingSoon);
      expect(section.title, 'Airing soon');
      expect(section.isAiring, isTrue);
      expect(section.isTrakt, isFalse);
      expect(
        HomeBoardServices.episodeBadge(section, section.items.single),
        'Fri · S2E5',
      );
      expect(HomeBoardServices.hasSeeAll(section), isFalse);
    });

    test('nothing upcoming, or no tracker, means no row', () async {
      final rows = await service(
        () async => (items: <StremioMeta>[], row: null, failed: false),
      ).resolve(enabled);
      expect(rows, isEmpty);
    });

    test('the row costs nothing unless it is switched on', () async {
      var calls = 0;
      await service(() async {
        calls++;
        return (items: <StremioMeta>[], row: null, failed: false);
      }).resolve(const []);
      expect(calls, 0);
    });
  });

  group('HomeRowOrder.seedNewRows', () {
    test('a saved order gets Airing soon right after Continue Watching', () {
      expect(
        HomeRowOrder.seedNewRows([
          'cw:movies',
          'cw:series',
          'trakt:shows',
          'addon:x',
        ]),
        ['cw:movies', 'cw:series', 'trakt:shows', 'airing:soon', 'addon:x'],
      );
    });

    test('a position the user already chose is kept', () {
      expect(
        HomeRowOrder.seedNewRows(['addon:x', 'airing:soon', 'cw:movies']),
        ['addon:x', 'airing:soon', 'cw:movies'],
      );
    });

    test('new collections still land after CW when Airing soon was moved', () {
      expect(
        HomeRowOrder.seedCollections(
          ['cw:movies', 'addon:x', 'airing:soon'],
          ['collection:new'],
        ),
        ['cw:movies', 'collection:new', 'addon:x', 'airing:soon'],
      );
    });

    test('the Ledger row lands after the last saved tracker row', () {
      debugLedgerEnabled = true;
      addTearDown(() => debugLedgerEnabled = null);
      expect(
        HomeRowOrder.seedNewRows([
          'trakt:movies',
          'addon:x',
          'mdblist:shows',
          'iptv:movies',
        ]),
        [
          'trakt:movies',
          'addon:x',
          'mdblist:shows',
          'ledger:continue',
          'iptv:movies',
          'airing:soon',
        ],
      );
      expect(
        HomeRowOrder.seedNewRows(['addon:x', 'ledger:continue', 'cw:movies']),
        ['addon:x', 'ledger:continue', 'cw:movies', 'airing:soon'],
      );
    });

    test('the Ledger row is not seeded while Ledger is off', () {
      expect(HomeRowOrder.seedNewRows(['trakt:movies', 'mdblist:shows']), [
        'trakt:movies',
        'mdblist:shows',
        'airing:soon',
      ]);
    });

    test('an empty order stays empty, so the canonical order applies', () {
      expect(HomeRowOrder.seedNewRows(const []), isEmpty);
    });
  });
}
