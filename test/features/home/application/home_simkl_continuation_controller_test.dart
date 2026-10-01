import 'dart:async';
import 'package:debrify/features/home/application/home_simkl_continuation_controller.dart';
import 'package:debrify/features/home/application/home_continuation_providers.dart';
import 'package:debrify/features/home/data/home_simkl_continuation_reader.dart';
import 'package:debrify/features/home/models/home_continuation_session.dart';
import 'package:debrify/features/home/models/home_simkl_continuation.dart';
import 'package:debrify/models/simkl_continue_watching_item.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

HomeContinuationSession session() => HomeContinuationSession(
  owner: ProfileSessionMemory.captureOwner(),
  viewIdentity: Object(),
);
HomeSimklContinuationRows rows(String id) => (
  movies: [
    SimklContinueWatchingItem(
      meta: StremioMeta(id: id, name: id, type: 'movie'),
      progress: 50,
      season: null,
      episode: null,
      pausedAtMs: null,
      isMovie: true,
    ),
  ],
  shows: [],
);
HomeSimklContinuationController mount(
  ProviderContainer c,
  HomeContinuationSession key,
) {
  c.listen(homeSimklContinuationProvider(key), (_, _) {});
  return c.read(homeSimklContinuationProvider(key).notifier);
}

Future<void> load(
  HomeSimklContinuationController c, {
  bool Function()? current,
  Future<void> Function()? layout,
  void Function(HomeSimklContinuation)? beforeRows,
  void Function(HomeSimklContinuation, bool, bool Function())? onRows,
}) => c.load(
  isCurrent: current ?? () => true,
  ensureLayout: layout ?? () async {},
  beforeRows: beforeRows ?? (_) {},
  onRows: onRows ?? (_, _, _) {},
);

void main() {
  test(
    'read then layout then focus then publication; failed feed retains rows and warms layout',
    () async {
      final order = <String>[];
      HomeSimklContinuationRows? result = rows('first');
      final c = ProviderContainer.test(
        overrides: [
          homeSimklContinuationReaderProvider.overrideWithValue(() async {
            order.add('read');
            return result;
          }),
        ],
      );
      final controller = mount(c, session());
      expect(order, isEmpty);
      bool Function()? artworkCurrent;
      await load(
        controller,
        layout: () async {
          order.add('layout');
        },
        beforeRows: (next) {
          expect(controller.current.all, isEmpty);
          expect(next.movies.single.id, 'first');
          order.add('focus');
        },
        onRows: (next, hadRows, current) {
          expect(controller.current, same(next));
          expect(hadRows, isFalse);
          artworkCurrent = current;
          order.add('rows');
        },
      );
      expect(order, ['read', 'layout', 'focus', 'rows']);
      expect(artworkCurrent!(), isTrue);
      final accepted = controller.current;
      result = null;
      order.clear();
      await load(
        controller,
        layout: () async {
          order.add('layout');
        },
        beforeRows: (_) => fail('Failed feed must not clear rows'),
      );
      expect(order, ['read', 'layout']);
      expect(controller.current, same(accepted));
      expect(artworkCurrent!(), isFalse);
      result = (movies: [], shows: []);
      await load(
        controller,
        beforeRows: (next) {
          expect(controller.current, same(accepted));
          expect(next.all, isEmpty);
        },
        onRows: (next, hadRows, _) {
          expect(hadRows, isTrue);
          expect(controller.current.all, isEmpty);
        },
      );
    },
  );

  test(
    'newer load wins; stale response skips layout and publication',
    () async {
      final pending = Completer<HomeSimklContinuationRows?>();
      var reads = 0;
      final c = ProviderContainer.test(
        overrides: [
          homeSimklContinuationReaderProvider.overrideWithValue(
            () => ++reads == 1 ? pending.future : Future.value(rows('new')),
          ),
        ],
      );
      final controller = mount(c, session());
      var oldEffects = 0;
      final old = load(
        controller,
        layout: () async {
          oldEffects++;
        },
        onRows: (_, _, _) => oldEffects++,
      );
      await load(controller);
      pending.complete(rows('old'));
      await old;
      expect(oldEffects, 0);
      expect(controller.current.movies.single.id, 'new');
    },
  );

  test(
    'thrown reader failure propagates without layout, publication or retries',
    () async {
      var reads = 0;
      final error = StateError('reader');
      final c = ProviderContainer.test(
        overrides: [
          homeSimklContinuationReaderProvider.overrideWithValue(() async {
            reads++;
            throw error;
          }),
        ],
      );
      final controller = mount(c, session());
      await expectLater(
        load(
          controller,
          layout: () => throw StateError('layout should not run'),
        ),
        throwsA(same(error)),
      );
      expect(reads, 1);
      expect(controller.current.all, isEmpty);
    },
  );

  for (final reason in ['dispose', 'profile', 'recompute', 'view']) {
    test('$reason retires work during layout wait', () async {
      final c = ProviderContainer.test(
        overrides: [
          homeSimklContinuationReaderProvider.overrideWithValue(
            () async => rows('old'),
          ),
        ],
      );
      final key = session();
      final controller = mount(c, key);
      final entered = Completer<void>();
      final pending = Completer<void>();
      var active = true;
      var callbacks = 0;
      final request = load(
        controller,
        current: () => active,
        layout: () {
          entered.complete();
          return pending.future;
        },
        beforeRows: (_) => callbacks++,
        onRows: (_, _, _) => callbacks++,
      );
      await entered.future;
      switch (reason) {
        case 'dispose':
          c.dispose();
        case 'profile':
          ProfileSessionMemory.clearAll();
        case 'recompute':
          c.invalidate(homeSimklContinuationProvider(key));
          c.read(homeSimklContinuationProvider(key));
        case 'view':
          active = false;
      }
      pending.complete();
      await request;
      expect(callbacks, 0);
      expect(controller.current.all, isEmpty);
    });
  }

  test(
    'explicit child override and sibling views keep independent data',
    () async {
      final key = session();
      final parent = ProviderContainer.test(
        overrides: [
          homeSimklContinuationReaderProvider.overrideWithValue(
            () async => rows('parent'),
          ),
        ],
      );
      final root = mount(parent, key);
      await load(root);
      final sibling = mount(parent, session());
      final child = ProviderContainer.test(
        parent: parent,
        overrides: [
          homeSimklContinuationReaderProvider.overrideWithValue(
            () async => rows('child'),
          ),
          homeSimklContinuationProvider(
            key,
          ).overrideWith(() => HomeSimklContinuationController(key)),
        ],
      );
      final scoped = mount(child, key);
      await load(scoped);
      expect(root.current.movies.single.id, 'parent');
      expect(scoped.current.movies.single.id, 'child');
      expect(sibling.current.all, isEmpty);
    },
  );
}
