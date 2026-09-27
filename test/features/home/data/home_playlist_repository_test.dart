import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import '../fixtures/playlist_fixture.dart';

void main() {
  test(
    'initial reads are parallel; sort and distinct poster keys precede progress',
    () async {
      final items = Completer<PlaylistRows>();
      final favorites = Completer<Set<String>>();
      final posters = Completer<Map<String, String>>();
      final calls = <String>[];
      final old = playlistItem('old', addedAt: -1)..['posterUrl'] = 'keep';
      final recent = playlistItem('new', addedAt: 9);
      final missing = playlistItem('missing')..remove('addedAt');
      final source = [old, recent, missing];
      final r = repository(
        items: () {
          calls.add('items');
          return items.future;
        },
        favorites: () {
          calls.add('favorites');
          return favorites.future;
        },
        posters: () {
          calls.add('posters');
          return posters.future;
        },
        progress: (rows) async {
          calls.add('progress');
          expect(rows.map((r) => r['id']), ['new', 'missing', 'old']);
          expect(rows.first['posterUrl'], 'override');
          expect(rows.last['posterUrl'], 'keep');
          return {
            'play:new': {'positionMs': 50, 'durationMs': 100},
          };
        },
      );
      final read = r.read(isCurrent: () => true);
      expect(calls, ['items', 'favorites', 'posters']);
      items.complete(source);
      favorites.complete({'play:new'});
      await Future<void>.delayed(Duration.zero);
      expect(calls.length, 3);
      posters.complete({
        'poster:new': 'override',
        'poster:old': '',
        'play:missing': 'wrong key',
      });
      final state = (await read)!;
      expect(calls.last, 'progress');
      expect(state.items.map((i) => i.dedupeKey), [
        'play:new',
        'play:missing',
        'play:old',
      ]);
      expect(state.items.first.posterUrl, 'override');
      expect(state.items[1].posterUrl, isNull);
      expect(state.items.last.posterUrl, 'keep');
      expect(state.isFavorite(state.items.first), isTrue);
      expect(state.progressFor(state.items.first), 0.5);
      expect(source.first, same(old));
      expect(recent.containsKey('posterUrl'), isFalse);
    },
  );

  test(
    'empty items still read favourites/posters and perform progress lookup',
    () async {
      var progressReads = 0;
      final r = repository(
        items: () async => [],
        favorites: () async => {'stale'},
        progress: (rows) async {
          progressReads++;
          expect(rows, isEmpty);
          return {};
        },
      );
      final result = (await r.read(isCurrent: () => true))!;
      expect(result.items, isEmpty);
      expect(result.favorites, {'stale'});
      expect(progressReads, 1);
    },
  );

  for (final stage in ['before', 'initial', 'progress']) {
    test('retirement at $stage stops follow-up work/publication', () async {
      var current = stage != 'before';
      var initial = 0;
      var progress = 0;
      final r = repository(
        items: () async {
          initial++;
          if (stage == 'initial') current = false;
          return [playlistItem('a')];
        },
        progress: (_) async {
          progress++;
          current = false;
          return {};
        },
      );
      expect(await r.read(isCurrent: () => current), isNull);
      expect(initial, stage == 'before' ? 0 : 1);
      expect(progress, stage == 'progress' ? 1 : 0);
    });
  }

  test(
    'initial and progress failures propagate without fabricated empty snapshots',
    () async {
      var progressReads = 0;
      final r = repository(
        items: () async => throw StateError('items'),
        progress: (_) async {
          progressReads++;
          return {};
        },
      );
      await expectLater(r.read(isCurrent: () => true), throwsStateError);
      expect(progressReads, 0);
      final p = repository(
        items: () async => [playlistItem('a')],
        progress: (_) async => throw StateError('progress'),
      );
      await expectLater(p.read(isCurrent: () => true), throwsStateError);
    },
  );
}
