import 'package:debrify/features/ledger/models/ledger_brand.dart';
import 'package:debrify/features/home/models/home_ledger_continuation.dart';
import 'package:debrify/features/ledger/models/ledger_tracking.dart';
import 'package:flutter_test/flutter_test.dart';

LedgerUpNextEntry _entry(Map<String, Object?> json) =>
    LedgerUpNextEntry.fromJson(json)!;

Map<String, Object?> _movie(String imdb) => {
  'kind': 'MEDIA_KIND_MOVIE',
  'name': 'Movie $imdb',
  'year': 1999,
  'ids': {'imdb': imdb},
};

Map<String, Object?> _episode(String showImdb, int season, int number) => {
  'kind': 'MEDIA_KIND_EPISODE',
  'ids': {'tvdb': '1'},
  'show': {
    'kind': 'MEDIA_KIND_SHOW',
    'name': 'Show $showImdb',
    'ids': {'imdb': showImdb},
  },
  'season': season,
  'number': number,
};

void main() {
  // Ledger is behind a feature flag (off in builds).
  setUp(() => debugLedgerEnabled = true);
  tearDown(() => debugLedgerEnabled = null);

  test('a resumed movie carries its percent and playback id', () {
    final item = HomeLedgerContinuationItem.fromEntry(
      _entry({
        'item': _movie('tt0133093'),
        'reason': 'UP_NEXT_REASON_RESUME',
        'progress': 42,
        'playbackId': 'pb',
      }),
    )!;
    expect(item.isMovie, isTrue);
    expect(item.progress, 42);
    expect(item.playbackId, 'pb');
    expect(item.meta.year, '1999');
    final selection = item.selection;
    expect(selection.ledgerSource, isTrue);
    expect(selection.ledgerProgressPercent, 42);
    expect(selection.isSeries, isFalse);
  });

  test("a show's next episode is up next: no progress, no playback", () {
    final item = HomeLedgerContinuationItem.fromEntry(
      _entry({
        'item': _episode('tt0944947', 1, 3),
        'reason': 'UP_NEXT_REASON_NEXT',
      }),
    )!;
    expect(item.isUpNext, isTrue);
    expect(item.meta.id, 'tt0944947', reason: 'cards key on the show');
    expect((item.season, item.episode), (1, 3));
    expect(item.playbackId, isNull);
    expect(item.selection.ledgerProgressPercent, isNull);
  });

  test('items without an IMDb title id are skipped', () {
    expect(
      HomeLedgerContinuationItem.fromEntry(
        _entry({
          'item': {
            'kind': 'MEDIA_KIND_MOVIE',
            'ids': {'tvdb': '5'},
          },
          'reason': 'UP_NEXT_REASON_RESUME',
          'progress': 10,
        }),
      ),
      isNull,
    );
  });

  test('the shelf keeps server order, dedups titles and labels episodes', () {
    final items = [
      for (final json in [
        {
          'item': _episode('tt1', 2, 5),
          'reason': 'UP_NEXT_REASON_RESUME',
          'progress': 30,
        },
        {
          'item': _movie('tt2'),
          'reason': 'UP_NEXT_REASON_RESUME',
          'progress': 0,
        },
        {'item': _episode('tt1', 2, 6), 'reason': 'UP_NEXT_REASON_NEXT'},
      ])
        HomeLedgerContinuationItem.fromEntry(_entry(json))!,
    ];
    final shelf = HomeLedgerContinuation.fromItems(items);
    expect(shelf.all.map((m) => m.id), ['tt1', 'tt2']);
    expect(shelf.progress, {'tt1': 0.3}, reason: '0% has nothing to resume');
    expect(shelf.episode.keys, ['tt1']);
    expect(shelf.episodeRefs['tt1'], (season: 2, episode: 5));
    expect(shelf.byKey['tt1']!.episode, 5);
  });
}
