import 'dart:async';
import 'package:debrify/features/home/data/home_mdblist_continuation_repository.dart';
import 'package:debrify/models/mdblist_continue_watching.dart';
import 'package:debrify/services/mdblist/mdblist_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'waits for invalidation even when polling fails, forwards force and partial result unchanged',
    () async {
      final pending = Completer<bool>();
      final calls = <Object>[];
      const result = MdblistResult.partial(
        MdblistContinueWatchingSnapshot(),
        statusCode: 206,
        headers: {'fixture': 'value'},
      );
      final repository = HomeMdblistContinuationRepository(
        clear: (_) async => false,
        invalidate: () {},
        synchronizeInvalidations: () {
          calls.add('sync');
          return pending.future;
        },
        fetch: ({required force}) async {
          calls.add(force);
          return result;
        },
      );
      expect(calls, isEmpty);
      final request = repository.read(force: true, isCurrent: () => true);
      expect(calls, ['sync']);
      pending.complete(false);
      expect(await request, same(result));
      expect(calls, ['sync', true]);
      expect(
        await repository.read(force: false, isCurrent: () => true),
        same(result),
      );
      expect(calls, ['sync', true, 'sync', false]);
    },
  );

  for (final stage in ['before', 'sync']) {
    test('retirement $stage prevents fetch', () async {
      var current = stage != 'before';
      var syncs = 0;
      final repository = HomeMdblistContinuationRepository(
        clear: (_) async => false,
        invalidate: () {},
        synchronizeInvalidations: () async {
          syncs++;
          current = false;
          return true;
        },
        fetch: ({required force}) => throw StateError('Unexpected fetch'),
      );
      expect(
        await repository.read(force: false, isCurrent: () => current),
        isNull,
      );
      expect(syncs, stage == 'before' ? 0 : 1);
    });
  }

  for (final stage in ['sync', 'fetch']) {
    test('$stage exceptions propagate without retries', () async {
      final error = StateError(stage);
      var syncs = 0;
      var fetches = 0;
      final repository = HomeMdblistContinuationRepository(
        clear: (_) async => false,
        invalidate: () {},
        synchronizeInvalidations: () async {
          syncs++;
          if (stage == 'sync') throw error;
          return true;
        },
        fetch: ({required force}) async {
          fetches++;
          throw error;
        },
      );
      await expectLater(
        repository.read(force: false, isCurrent: () => true),
        throwsA(same(error)),
      );
      expect(syncs, 1);
      expect(fetches, stage == 'fetch' ? 1 : 0);
    });
  }

  test(
    'finished response keeps its kind for caller-side retirement diagnostics',
    () async {
      var current = true;
      const result = MdblistResult<MdblistContinueWatchingSnapshot>.failure(
        MdblistResultKind.rateLimited,
        statusCode: 429,
        retryAfter: Duration(seconds: 3),
      );
      final repository = HomeMdblistContinuationRepository(
        clear: (_) async => false,
        invalidate: () {},
        synchronizeInvalidations: () async => true,
        fetch: ({required force}) async {
          current = false;
          return result;
        },
      );
      expect(
        await repository.read(force: true, isCurrent: () => current),
        same(result),
      );
      expect(current, isFalse);
    },
  );
}
