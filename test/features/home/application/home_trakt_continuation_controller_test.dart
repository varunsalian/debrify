import 'dart:async';

import 'package:debrify/features/home/application/home_trakt_continuation_controller.dart';
import 'package:debrify/features/home/application/home_continuation_providers.dart';
import 'package:debrify/features/home/data/home_trakt_continuation_repository.dart';
import 'package:debrify/features/home/models/home_continuation_session.dart';
import 'package:debrify/features/home/models/home_trakt_continuation.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/models/trakt_continue_watching_item.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

HomeTraktContinuationScope scope({bool loading = false}) => (
  session: HomeContinuationSession(
    owner: ProfileSessionMemory.captureOwner(),
    viewIdentity: Object(),
  ),
  initiallyLoading: loading,
);
HomeTraktContinuationController mount(
  ProviderContainer container,
  HomeTraktContinuationScope key,
) {
  container.listen(homeTraktContinuationProvider(key), (_, _) {});
  return container.read(homeTraktContinuationProvider(key).notifier);
}

TraktContinueWatchingItem item(String id) => TraktContinueWatchingItem(
  meta: StremioMeta(id: id, name: id, type: 'movie'),
  traktContentType: 'movies',
);
HomeTraktContinuationRepository repository(
  Future<List<TraktContinueWatchingItem>?> Function() read,
) => HomeTraktContinuationRepository(
  isAuthenticated: () async => true,
  readMovies: read,
  readShows: () async => [],
);
Future<void> load(
  HomeTraktContinuationController controller, {
  bool Function()? current,
  Future<void> Function()? merge,
  void Function(HomeTraktContinuation)? beforeRows,
  void Function(HomeTraktContinuation, bool, bool, bool Function())? onRows,
  void Function(Object, bool)? onFailure,
  DateTime? attemptedAt,
}) => controller.load(
  attemptedAt: attemptedAt ?? DateTime(2026, 9, 27),
  isCurrent: current ?? () => true,
  beforeConnectedRows: merge ?? () async {},
  beforeRows: beforeRows ?? (_) {},
  onRows: onRows ?? (_, _, _, _) {},
  onFailure: onFailure ?? (_, _) {},
);

void main() {
  for (final initialLoading in [true, false]) {
    test(
      'initial loading $initialLoading avoids construction reads and preserves focus-before-publication',
      () async {
        var reads = 0;
        final pending = Completer<List<TraktContinueWatchingItem>?>();
        final container = ProviderContainer.test(
          overrides: [
            homeTraktContinuationRepositoryProvider.overrideWithValue(
              repository(() {
                reads++;
                return pending.future;
              }),
            ),
          ],
        );
        final key = scope(loading: initialLoading);
        final controller = mount(container, key);
        var updates = 0;
        container.listen(
          homeTraktContinuationProvider(key),
          (_, _) => updates++,
        );
        expect(reads, 0);
        expect(controller.lastAttemptAt, isNull);
        expect(controller.current.loading, initialLoading);
        final order = <String>[];
        final at = DateTime(2026, 9, 27, 12);
        final request = load(
          controller,
          attemptedAt: at,
          merge: () async {
            order.add('merge');
          },
          beforeRows: (next) {
            expect(controller.current.loading, isTrue);
            expect(controller.current.data.all, isEmpty);
            expect(next.movies.single.id, 'new');
            order.add('focus');
          },
          onRows: (next, connected, hadRows, current) {
            expect(controller.current.data, same(next));
            expect(controller.current.loading, isFalse);
            expect(connected, isTrue);
            expect(hadRows, isFalse);
            expect(current(), isTrue);
            order.add('rows');
          },
        );
        expect(controller.lastAttemptAt, at);
        expect(updates, initialLoading ? 0 : 1);
        pending.complete([item('new')]);
        await request;
        expect(reads, 1);
        expect(order, ['merge', 'focus', 'rows']);
        expect(updates, initialLoading ? 1 : 2);
      },
    );
  }

  test(
    'failed refresh retains accepted data; disconnect clears without merge or connected effects',
    () async {
      var authenticated = true;
      var shouldFail = false;
      final container = ProviderContainer.test(
        overrides: [
          homeTraktContinuationRepositoryProvider.overrideWithValue(
            HomeTraktContinuationRepository(
              isAuthenticated: () async => authenticated,
              readMovies: () async => shouldFail ? null : [item('accepted')],
              readShows: () async => [],
            ),
          ),
        ],
      );
      final controller = mount(container, scope());
      bool Function()? artworkCurrent;
      await load(
        controller,
        onRows: (_, _, _, current) => artworkCurrent = current,
      );
      final accepted = controller.current.data;
      expect(artworkCurrent!(), isTrue);
      shouldFail = true;
      var failures = 0;
      await load(
        controller,
        beforeRows: (_) => fail('Unexpected focus sync'),
        onFailure: (error, accepted) {
          failures++;
          expect(error, isStateError);
          expect(accepted, isTrue);
          expect(controller.current.loading, isFalse);
        },
      );
      expect(failures, 1);
      expect(controller.current.data, same(accepted));
      expect(artworkCurrent!(), isFalse);
      authenticated = false;
      await load(
        controller,
        merge: () => throw StateError('Unexpected preference read'),
        beforeRows: (next) {
          expect(controller.current.data, same(accepted));
          expect(next.all, isEmpty);
        },
        onRows: (next, connected, hadRows, current) {
          expect(connected, isFalse);
          expect(hadRows, isTrue);
          expect(controller.current.data.all, isEmpty);
        },
      );
      expect(controller.current.loading, isFalse);
    },
  );

  test(
    'old failures cannot clear a newer loading flag or publish rows',
    () async {
      final first = Completer<List<TraktContinueWatchingItem>?>();
      final second = Completer<List<TraktContinueWatchingItem>?>();
      final firstStarted = Completer<void>();
      var reads = 0;
      final container = ProviderContainer.test(
        overrides: [
          homeTraktContinuationRepositoryProvider.overrideWithValue(
            repository(() {
              if (++reads == 1) {
                firstStarted.complete();
                return first.future;
              }
              return second.future;
            }),
          ),
        ],
      );
      final controller = mount(container, scope());
      final failures = <bool>[];
      final old = load(
        controller,
        onFailure: (_, accepted) => failures.add(accepted),
      );
      await firstStarted.future;
      final newer = load(controller);
      first.completeError(StateError('old failure'));
      await old;
      expect(failures, [false]);
      expect(controller.current.loading, isTrue);
      second.complete([item('new')]);
      await newer;
      expect(controller.current.loading, isFalse);
      expect(controller.current.data.movies.single.id, 'new');
    },
  );

  for (final reason in ['dispose', 'profile', 'recompute', 'view']) {
    test('$reason retires request during merge-preference wait', () async {
      final container = ProviderContainer.test(
        overrides: [
          homeTraktContinuationRepositoryProvider.overrideWithValue(
            repository(() async => [item('old')]),
          ),
        ],
      );
      final key = scope(loading: true);
      final controller = mount(container, key);
      final entered = Completer<void>();
      final pending = Completer<void>();
      var active = true;
      var callbacks = 0;
      final request = load(
        controller,
        current: () => active,
        merge: () {
          entered.complete();
          return pending.future;
        },
        beforeRows: (_) => callbacks++,
        onRows: (_, _, _, _) => callbacks++,
      );
      await entered.future;
      switch (reason) {
        case 'dispose':
          container.dispose();
        case 'profile':
          ProfileSessionMemory.clearAll();
        case 'recompute':
          container.invalidate(homeTraktContinuationProvider(key));
          container.read(homeTraktContinuationProvider(key));
          expect(controller.current.loading, isFalse);
        case 'view':
          active = false;
      }
      pending.complete();
      await request;
      expect(callbacks, 0);
      expect(controller.current.data.all, isEmpty);
    });
  }

  test(
    'explicit child scopes and sibling views have independent state and attempts',
    () async {
      final key = scope();
      final parent = ProviderContainer.test(
        overrides: [
          homeTraktContinuationRepositoryProvider.overrideWithValue(
            repository(() async => [item('parent')]),
          ),
        ],
      );
      final root = mount(parent, key);
      await load(root);
      final sibling = mount(parent, scope());
      final child = ProviderContainer.test(
        parent: parent,
        overrides: [
          homeTraktContinuationRepositoryProvider.overrideWithValue(
            repository(() async => [item('child')]),
          ),
          homeTraktContinuationProvider(
            key,
          ).overrideWith(() => HomeTraktContinuationController(key)),
        ],
      );
      final scoped = mount(child, key);
      await load(scoped);
      expect(root.current.data.movies.single.id, 'parent');
      expect(scoped.current.data.movies.single.id, 'child');
      expect(sibling.current.data.all, isEmpty);
      expect(sibling.lastAttemptAt, isNull);
    },
  );
}
