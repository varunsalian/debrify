import 'package:debrify/features/home/data/home_tv_favorites_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import '../fixtures/tv_favorites_fixture.dart';

void main() {
  test(
    'preserves database order and metadata while detaching immutable results',
    () async {
      final keywords = ['keep spaces ', ''];
      final records = [
        channel('b', keywords: keywords),
        channel('other'),
        channel('a'),
      ];
      final calls = <String>[];
      final repository = HomeTvFavoritesRepository(
        favoriteIds: () async {
          calls.add('ids');
          return {'a', 'b', 'missing'};
        },
        channels: () async {
          calls.add('channels');
          return records;
        },
      );
      expect(calls, isEmpty);
      final result = (await repository.read(isCurrent: () => true))!;
      expect(calls, ['ids', 'channels']);
      expect(result.hasFavoriteIds, isTrue);
      expect(result.channels.map((c) => c.id), ['b', 'a']);
      expect(result.channels.first.name, 'Channel b');
      expect(result.channels.first.channelNumber, 0);
      expect(result.channels.first.avoidNsfw, isTrue);
      expect(result.channels.first.createdAt, DateTime.utc(2026));
      expect(result.channels.first.updatedAt, DateTime.utc(2026, 2));
      keywords.clear();
      records.clear();
      expect(result.channels.first.keywords, ['keep spaces ', '']);
      expect(result.channels.clear, throwsUnsupportedError);
      expect(result.channels.first.keywords.clear, throwsUnsupportedError);
    },
  );

  test(
    'no favourite IDs skips channels, unmatched IDs retain their distinction',
    () async {
      var ids = <String>{};
      var reads = 0;
      final repository = HomeTvFavoritesRepository(
        favoriteIds: () async => ids,
        channels: () async {
          reads++;
          return [];
        },
      );
      final empty = (await repository.read(isCurrent: () => true))!;
      expect(empty.channels, isEmpty);
      expect(empty.hasFavoriteIds, isFalse);
      expect(reads, 0);
      ids = {'missing'};
      final unmatched = (await repository.read(isCurrent: () => true))!;
      expect(unmatched.channels, isEmpty);
      expect(unmatched.hasFavoriteIds, isTrue);
      expect(reads, 1);
    },
  );

  for (final stage in ['before', 'ids', 'channels']) {
    test(
      'retirement at $stage stops subsequent reads and publication',
      () async {
        var current = stage != 'before';
        var reads = 0;
        final repository = HomeTvFavoritesRepository(
          favoriteIds: () async {
            reads++;
            if (stage == 'ids') current = false;
            return {'a'};
          },
          channels: () async {
            reads++;
            current = false;
            return [channel('a')];
          },
        );
        expect(await repository.read(isCurrent: () => current), isNull);
        expect(
          reads,
          stage == 'before'
              ? 0
              : stage == 'ids'
              ? 1
              : 2,
        );
      },
    );
  }
}
