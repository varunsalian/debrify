import 'dart:async';
import 'package:debrify/features/home/data/home_stremio_favorites_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import '../fixtures/stremio_favorites_fixture.dart';

void main() {
  test(
    'parallel rotations precede discovery; only ordered favourites load; snapshots detach',
    () async {
      final movie = Completer<int>();
      final series = Completer<int>();
      final calls = <String>[];
      final records = [
        channel('b', type: 'series'),
        channel('other'),
        channel('a'),
      ];
      final repository = HomeStremioFavoritesRepository(
        favoriteIds: () async {
          calls.add('ids');
          return {'a', 'b'};
        },
        rotationMinutes: () {
          calls.add('movie');
          return movie.future;
        },
        seriesRotationMinutes: () {
          calls.add('series');
          return series.future;
        },
        discover: () async {
          calls.add('discover');
          return records;
        },
        loadItems: (channels) async {
          calls.add('items');
          expect(channels.map((c) => c.id), ['b', 'a']);
          channels.first.items = [records.last.items.single];
        },
      );
      final read = repository.read(isCurrent: () => true);
      await Future<void>.delayed(Duration.zero);
      expect(calls, ['ids', 'movie', 'series']);
      movie.complete(120);
      await Future<void>.delayed(Duration.zero);
      expect(calls, ['ids', 'movie', 'series']);
      series.complete(30);
      final result = (await read)!;
      expect(calls, ['ids', 'movie', 'series', 'discover', 'items']);
      expect(result.hasFavoriteIds, isTrue);
      final snapshot = result.favorites;
      expect(snapshot.rotationMinutes, 120);
      expect(snapshot.seriesRotationMinutes, 30);
      expect(snapshot.channels.map((c) => c.id), ['b', 'a']);
      expect(snapshot.channels.first.type, 'series');
      expect(snapshot.channels.first.displayName, 'One');
      expect(
        snapshot.channels.first.items.single,
        same(records.last.items.single),
      );
      records.first.id = 'mutated';
      records.first.items.clear();
      records.clear();
      expect(snapshot.channels.first.id, 'b');
      expect(snapshot.channels.first.items.single.id, 'item:a');
      expect(snapshot.channels.clear, throwsUnsupportedError);
      expect(snapshot.channels.first.items.clear, throwsUnsupportedError);
    },
  );

  test(
    'empty IDs bypass all later reads; unmatched IDs still run item loading',
    () async {
      var ids = <String>{};
      final calls = <String>[];
      final repository = HomeStremioFavoritesRepository(
        favoriteIds: () async => ids,
        rotationMinutes: () async {
          calls.add('movie');
          return 90;
        },
        seriesRotationMinutes: () async {
          calls.add('series');
          return 45;
        },
        discover: () async {
          calls.add('discover');
          return [channel('a')];
        },
        loadItems: (channels) async {
          calls.add('items');
          expect(channels, isEmpty);
        },
      );
      final empty = (await repository.read(isCurrent: () => true))!;
      expect(empty.hasFavoriteIds, isFalse);
      expect(empty.favorites.channels, isEmpty);
      expect(calls, isEmpty);
      ids = {'missing'};
      final missing = (await repository.read(isCurrent: () => true))!;
      expect(missing.hasFavoriteIds, isTrue);
      expect(missing.favorites.channels, isEmpty);
      expect(calls, ['movie', 'series', 'discover', 'items']);
    },
  );

  for (final stage in ['before', 'ids', 'rotations', 'discover', 'items']) {
    test('retirement at $stage stops subsequent work/publication', () async {
      var current = stage != 'before';
      final calls = <String>[];
      void mark(String at) {
        calls.add(at);
        if (stage == at) current = false;
      }

      final repository = HomeStremioFavoritesRepository(
        favoriteIds: () async {
          mark('ids');
          return {'a'};
        },
        rotationMinutes: () async {
          mark('rotations');
          return 90;
        },
        seriesRotationMinutes: () async => 45,
        discover: () async {
          mark('discover');
          return [channel('a')];
        },
        loadItems: (_) async {
          mark('items');
        },
      );
      expect(await repository.read(isCurrent: () => current), isNull);
      final stages = ['ids', 'rotations', 'discover', 'items'];
      expect(
        calls,
        stages.take(stage == 'before' ? 0 : stages.indexOf(stage) + 1),
      );
    });
  }
}
