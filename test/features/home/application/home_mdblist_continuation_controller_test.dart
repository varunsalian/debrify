import 'dart:async';
import 'package:debrify/features/home/application/home_mdblist_continuation_controller.dart';
import 'package:debrify/features/home/application/home_continuation_providers.dart';
import 'package:debrify/features/home/data/home_mdblist_continuation_repository.dart';
import 'package:debrify/features/home/models/home_continuation_session.dart';
import 'package:debrify/features/home/models/home_mdblist_continuation.dart';
import 'package:debrify/models/mdblist_continue_watching.dart';
import 'package:debrify/services/mdblist/mdblist_models.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/models/advanced_search_selection.dart';

typedef Result = MdblistResult<MdblistContinueWatchingSnapshot>;
Result rows(String id) => MdblistResult.partial(
  MdblistContinueWatchingSnapshot(
    shows: [
      MdblistContinueWatchingItem(
        selection: AdvancedSearchSelection(
          imdbId: id,
          isSeries: true,
          title: id,
          mdblistProgressPercent: 50,
          season: 2,
          episode: 3,
        ),
        paused: true,
      ),
    ],
  ),
);
HomeContinuationSession session() => HomeContinuationSession(
  owner: ProfileSessionMemory.captureOwner(),
  viewIdentity: Object(),
);
HomeMdblistContinuationController mount(
  ProviderContainer c,
  HomeContinuationSession key,
) {
  c.listen(homeMdblistContinuationProvider(key), (_, _) {});
  return c.read(homeMdblistContinuationProvider(key).notifier);
}

HomeMdblistContinuationRepository repository(Future<Result> Function() read) =>
    HomeMdblistContinuationRepository(
      clear: (_) async => false,
      invalidate: () {},
      synchronizeInvalidations: () async => false,
      fetch: ({required force}) => read(),
    );
Future<void> load(
  HomeMdblistContinuationController c, {
  bool enabled = true,
  bool force = false,
  bool Function()? current,
  Future<void> Function()? layout,
  DateTime Function()? now,
  void Function(HomeMdblistContinuation)? beforeRows,
  void Function(HomeMdblistContinuation, bool)? onRows,
  void Function()? disabled,
}) => c.load(
  enabled: enabled,
  force: force,
  refreshBound: true,
  isCurrent: current ?? () => true,
  ensureLayout: layout ?? () async {},
  now: now ?? () => DateTime.utc(2026),
  trace: (_) {},
  beforeRows: beforeRows ?? (_) {},
  onRows: onRows ?? (_, _) {},
  onDisabled: disabled ?? () {},
);

void main() {
  test(
    'partial rows publish after focus; only accepted forced loads update freshness',
    () async {
      final order = <String>[];
      Result result = rows('tt1');
      final c = ProviderContainer.test(
        overrides: [
          homeMdblistContinuationRepositoryProvider.overrideWithValue(
            repository(() async {
              order.add('read');
              return result;
            }),
          ),
        ],
      );
      final controller = mount(c, session());
      expect(order, isEmpty);
      final stamp = DateTime.utc(2026, 2);
      await load(
        controller,
        force: true,
        now: () => stamp,
        layout: () async {
          order.add('layout');
        },
        beforeRows: (next) {
          expect(controller.current.all, isEmpty);
          expect(next.series.single.id, 'tt1');
          expect(controller.forcedLoadAt, isNull);
          order.add('focus');
        },
        onRows: (next, hadRows) {
          expect(controller.current, same(next));
          expect(hadRows, isFalse);
          expect(controller.forcedLoadAt, stamp);
          order.add('rows');
        },
      );
      expect(order, ['read', 'layout', 'focus', 'rows']);
      final accepted = controller.current;
      order.clear();
      result = const MdblistResult.failure(MdblistResultKind.transientFailure);
      await load(
        controller,
        force: true,
        layout: () async {
          order.add('layout');
        },
        beforeRows: (_) => fail('Failed response changed focus'),
        onRows: (_, _) => fail('Failed response published'),
      );
      expect(order, ['read', 'layout']);
      expect(controller.current, same(accepted));
      expect(controller.forcedLoadAt, stamp);
      result = const MdblistResult.success(MdblistContinueWatchingSnapshot());
      await load(controller, onRows: (_, hadRows) => expect(hadRows, isTrue));
      expect(controller.current.all, isEmpty);
      expect(controller.forcedLoadAt, stamp);
    },
  );

  test(
    'disable hides rows and lookup but retains progress, episode and timestamp',
    () async {
      var reads = 0;
      final c = ProviderContainer.test(
        overrides: [
          homeMdblistContinuationRepositoryProvider.overrideWithValue(
            repository(() async {
              reads++;
              return rows('tt1');
            }),
          ),
        ],
      );
      final controller = mount(c, session());
      await load(controller, force: true);
      final stamp = controller.forcedLoadAt;
      var disabled = 0;
      await load(
        controller,
        enabled: false,
        force: true,
        layout: () => throw StateError('disabled layout'),
        beforeRows: (_) => fail('disabled focus'),
        onRows: (_, _) => fail('disabled rows'),
        disabled: () => disabled++,
      );
      expect(reads, 1);
      expect(disabled, 1);
      expect(controller.current.all, isEmpty);
      expect(controller.current.byImdb, isEmpty);
      expect(controller.current.progress, {'tt1': .5});
      expect(controller.current.episode, {'tt1': 'S2 · E3'});
      expect(controller.forcedLoadAt, stamp);
    },
  );

  test('older forced response cannot overwrite newer data or stamp', () async {
    final pending = Completer<Result>();
    final entered = Completer<void>();
    var reads = 0;
    final c = ProviderContainer.test(
      overrides: [
        homeMdblistContinuationRepositoryProvider.overrideWithValue(
          repository(() {
            if (++reads == 1) {
              entered.complete();
              return pending.future;
            }
            return Future.value(rows('tt2'));
          }),
        ),
      ],
    );
    final controller = mount(c, session());
    var layouts = 0;
    final old = load(
      controller,
      force: true,
      layout: () async {
        layouts++;
      },
      onRows: (_, _) => fail('stale publication'),
    );
    await entered.future;
    await load(controller);
    pending.complete(rows('tt1'));
    await old;
    expect(layouts, 1); // Preserve layout warming after a completed stale read.
    expect(controller.current.series.single.id, 'tt2');
    expect(controller.forcedLoadAt, isNull);
  });

  for (final reason in ['dispose', 'profile', 'recompute', 'view']) {
    test('$reason retires publication and freshness during layout', () async {
      final c = ProviderContainer.test(
        overrides: [
          homeMdblistContinuationRepositoryProvider.overrideWithValue(
            repository(() async => rows('tt1')),
          ),
        ],
      );
      final key = session();
      final controller = mount(c, key);
      final entered = Completer<void>();
      final pending = Completer<void>();
      var active = true;
      final request = load(
        controller,
        force: true,
        current: () => active,
        layout: () {
          entered.complete();
          return pending.future;
        },
        beforeRows: (_) => fail('retired focus'),
        onRows: (_, _) => fail('retired publication'),
      );
      await entered.future;
      switch (reason) {
        case 'dispose':
          c.dispose();
        case 'profile':
          ProfileSessionMemory.clearAll();
        case 'recompute':
          c.invalidate(homeMdblistContinuationProvider(key));
          c.read(homeMdblistContinuationProvider(key));
        case 'view':
          active = false;
      }
      pending.complete();
      await request;
      expect(controller.current.all, isEmpty);
      expect(controller.forcedLoadAt, isNull);
    });
  }
  test(
    'explicit child scope and sibling views retain independent rows',
    () async {
      final key = session();
      final parent = ProviderContainer.test(
        overrides: [
          homeMdblistContinuationRepositoryProvider.overrideWithValue(
            repository(() async => rows('parent')),
          ),
        ],
      );
      final root = mount(parent, key);
      await load(root);
      final sibling = mount(parent, session());
      final child = ProviderContainer.test(
        parent: parent,
        overrides: [
          homeMdblistContinuationRepositoryProvider.overrideWithValue(
            repository(() async => rows('child')),
          ),
          homeMdblistContinuationProvider(
            key,
          ).overrideWith(() => HomeMdblistContinuationController(key)),
        ],
      );
      final scoped = mount(child, key);
      await load(scoped);
      expect(root.current.series.single.id, 'parent');
      expect(scoped.current.series.single.id, 'child');
      expect(sibling.current.all, isEmpty);
    },
  );
}
