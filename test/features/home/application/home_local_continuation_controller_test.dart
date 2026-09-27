import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import '../fixtures/home_continuation_fixture.dart';

void main() {
  test(
    'source setting precedes loading and focus precedes atomic row publication',
    () async {
      final trace = <String>[];
      final container = ProviderContainer.test(
        overrides: [
          homeLocalContinuationRepositoryProvider.overrideWithValue(
            continuationRepository(
              readSource: () async {
                trace.add('source');
                return WatchProgressSource.local;
              },
              readEnabled: () async {
                trace.add('enabled');
                return true;
              },
              readItems: () async {
                trace.add('items');
                return history('recent');
              },
            ),
          ),
        ],
      );
      final controller = mountContinuation(container, continuationSession());
      expect(
        trace,
        isEmpty,
        reason: 'provider construction does not start reads',
      );
      final initial = controller.current;
      await loadContinuation(
        controller,
        sourceChanged: () {
          expect(controller.current.progressSource, WatchProgressSource.local);
          expect(controller.current.data.items, isEmpty);
          trace.add('source repaint');
        },
        beforeEnabledRows: () async {
          trace.add('merge');
        },
        beforeRows: (next) {
          expect(controller.current.data.items, isEmpty);
          expect(next.movies.single.id, 'recent');
          expect(next.series.single.id, 'recent-series');
          trace.add('focus');
        },
        onRows: (next, current) {
          expect(controller.current, same(next));
          expect(current(), isTrue);
          trace.add('rows');
        },
      );
      expect(trace, [
        'source',
        'enabled',
        'source repaint',
        'items',
        'merge',
        'focus',
        'rows',
      ]);
      expect(initial.progressSource, WatchProgressSource.smart);
      expect(initial.data.items, isEmpty);
      expect(() => controller.current.movies.clear(), throwsUnsupportedError);
    },
  );

  test(
    'disabled refresh releases focus before clearing state and skips data/merge',
    () async {
      var enabled = true;
      var reads = 0;
      final container = ProviderContainer.test(
        overrides: [
          homeLocalContinuationRepositoryProvider.overrideWithValue(
            continuationRepository(
              readEnabled: () async => enabled,
              readItems: () async {
                reads++;
                return history('saved');
              },
            ),
          ),
        ],
      );
      final controller = mountContinuation(container, continuationSession());
      await loadContinuation(controller);
      final accepted = controller.current;
      enabled = false;
      var before = false;
      var after = false;
      await loadContinuation(
        controller,
        beforeEnabledRows: () => throw StateError('Unexpected merge wait'),
        beforeRows: (next) {
          before = true;
          expect(controller.current, same(accepted));
          expect(next.enabled, isFalse);
          expect(next.movies, isEmpty);
          expect(next.series, isEmpty);
        },
        onRows: (next, _) {
          after = true;
          expect(next.data.ids, isEmpty);
        },
      );
      expect(before && after, isTrue);
      expect(reads, 1);
      expect(controller.current.enabled, isFalse);
      expect(accepted.data.items, hasLength(2));
    },
  );

  test(
    'newer load wins during merge wait and retires old artwork acceptance',
    () async {
      final mergeEntered = Completer<void>();
      final merge = Completer<void>();
      var reads = 0;
      bool Function()? oldArtwork;
      final container = ProviderContainer.test(
        overrides: [
          homeLocalContinuationRepositoryProvider.overrideWithValue(
            continuationRepository(
              readItems: () async => history('read${++reads}'),
            ),
          ),
        ],
      );
      final controller = mountContinuation(container, continuationSession());
      await loadContinuation(
        controller,
        onRows: (_, current) => oldArtwork = current,
      );
      expect(oldArtwork!(), isTrue);
      var stalePublications = 0;
      final old = loadContinuation(
        controller,
        beforeEnabledRows: () {
          mergeEntered.complete();
          return merge.future;
        },
        beforeRows: (_) => stalePublications++,
        onRows: (_, _) => stalePublications++,
      );
      expect(oldArtwork!(), isFalse);
      await mergeEntered.future;
      await loadContinuation(controller);
      merge.complete();
      await old;
      expect(stalePublications, 0);
      expect(controller.current.movies.single.id, 'read3');
    },
  );

  test(
    'failed refresh retains rows and accepted source without automatic retries',
    () async {
      var fail = false;
      var reads = 0;
      final error = StateError('read failed');
      final container = ProviderContainer.test(
        overrides: [
          homeLocalContinuationRepositoryProvider.overrideWithValue(
            continuationRepository(
              readSource: () async =>
                  fail ? WatchProgressSource.simkl : WatchProgressSource.local,
              readItems: () async {
                reads++;
                if (fail) throw error;
                return history('saved');
              },
            ),
          ),
        ],
      );
      final controller = mountContinuation(container, continuationSession());
      await loadContinuation(controller);
      final rows = controller.current.data;
      fail = true;
      await expectLater(loadContinuation(controller), throwsA(same(error)));
      await Future<void>.delayed(Duration.zero);
      expect(controller.current.data, same(rows));
      expect(controller.current.progressSource, WatchProgressSource.simkl);
      expect(reads, 2);
    },
  );

  for (final retirement in ['dispose', 'recompute', 'profile']) {
    test(
      '$retirement retires pending data before focus or publication',
      () async {
        final entered = Completer<void>();
        final response = Completer<List<Map<String, dynamic>>>();
        final container = ProviderContainer.test(
          overrides: [
            homeLocalContinuationRepositoryProvider.overrideWithValue(
              continuationRepository(
                readItems: () {
                  entered.complete();
                  return response.future;
                },
              ),
            ),
          ],
        );
        final session = continuationSession();
        final controller = mountContinuation(container, session);
        var publications = 0;
        final pending = loadContinuation(
          controller,
          beforeRows: (_) => publications++,
          onRows: (_, _) => publications++,
        );
        await entered.future;
        switch (retirement) {
          case 'dispose':
            container.dispose();
          case 'recompute':
            container.invalidate(homeLocalContinuationProvider(session));
            container.read(homeLocalContinuationProvider(session));
          case 'profile':
            ProfileSessionMemory.clearAll();
        }
        response.complete(history('retired'));
        await pending;
        expect(publications, 0);
        expect(controller.current.data.items, isEmpty);
      },
    );
  }

  test(
    'retirement during focus callback prevents stale state publication',
    () async {
      var visible = true;
      final container = ProviderContainer.test(
        overrides: [
          homeLocalContinuationRepositoryProvider.overrideWithValue(
            continuationRepository(readItems: () async => history('retired')),
          ),
        ],
      );
      final controller = mountContinuation(container, continuationSession());
      await loadContinuation(
        controller,
        isCurrent: () => visible,
        beforeRows: (_) => visible = false,
        onRows: (_, _) => fail('retired publication'),
      );
      expect(controller.current.data.items, isEmpty);
    },
  );
}
