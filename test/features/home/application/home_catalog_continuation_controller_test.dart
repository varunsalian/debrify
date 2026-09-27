import 'dart:async';

import 'package:debrify/features/home/application/home_catalog_continuation_controller.dart';
import 'package:debrify/features/home/models/home_catalog_session.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final addon = StremioAddon(
  id: 'fixture',
  name: 'Fixture',
  manifestUrl: 'https://fixture.invalid/manifest.json',
  baseUrl: 'https://fixture.invalid',
  addedAt: DateTime.utc(2026),
);

class PagingHarness {
  final container = ProviderContainer.test();
  final session = HomeCatalogSession(
    owner: ProfileSessionMemory.captureOwner(),
    viewIdentity: Object(),
  );
  late final HomeCatalogContinuationController controller;
  final rows = List.generate(
    6,
    (i) => CatalogSection(
      title: '$i',
      addon: addon,
      catalog: StremioAddonCatalog(id: '$i', type: 'movie', name: '$i'),
      items: [],
      pagingPaused: true,
    ),
  );
  final calls = <String>[];
  final states = <bool>[];
  Future<void> Function(CatalogSection)? onRow;
  Future<void> Function()? onMore;
  bool current = true, boardLoading = false, hasMore = true;

  PagingHarness() {
    container.listen(
      homeCatalogContinuationProvider(session),
      (_, next) => states.add(next),
    );
    controller = container.read(
      homeCatalogContinuationProvider(session).notifier,
    );
  }

  Future<void>? start({bool more = false}) => controller.start(
    moreCatalogs: more,
    boardLoading: boardLoading,
    rows: rows,
    hasMoreCatalogs: () => hasMore,
    isCurrent: () => current,
    loadMoreCatalogs: () async {
      calls.add('more');
      await onMore?.call();
    },
    resumeRow: (row) async {
      calls.add(row.title);
      await onRow?.call(row);
    },
  );
}

void main() {
  late PagingHarness paging;
  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    paging = PagingHarness();
  });
  tearDown(ProfileRuntime.debugReset);

  test(
    'four-row windows rotate and adapt to the current pending inventory',
    () async {
      expect(paging.calls, isEmpty);
      await paging.start();
      expect(paging.calls, ['0', '1', '2', '3']);
      paging.calls.clear();
      await paging.start();
      expect(paging.calls, ['4', '5', '0', '1']);
      paging.rows[0].exhausted = true;
      paging.rows[1].pagingPaused = false;
      paging.rows[2].exhausted = true;
      paging.calls.clear();
      await paging.start();
      expect(paging.calls, ['5', '3', '4']);
      expect(paging.states, [true, false, true, false, true, false]);
    },
  );

  test(
    'rows run sequentially and both repeat action types are rejected while busy',
    () async {
      final wait = Completer<void>();
      paging.onRow = (_) => wait.future;
      final pending = paging.start();
      expect(paging.controller.busy, isTrue);
      expect(paging.calls, ['0']);
      expect(paging.start(), isNull);
      expect(paging.start(more: true), isNull);
      await pumpEventQueue();
      expect(paging.calls, ['0']);
      wait.complete();
      await pending;
      expect(paging.calls, ['0', '1', '2', '3']);
      expect(paging.controller.busy, isFalse);
    },
  );

  test(
    'board or pending row loading rejects both actions without consuming the cursor',
    () async {
      paging.boardLoading = true;
      expect(paging.start(), isNull);
      expect(paging.start(more: true), isNull);
      paging.boardLoading = false;
      paging.rows.last.loadingMore = true;
      expect(paging.start(), isNull);
      expect(paging.start(more: true), isNull);
      expect(paging.states, isEmpty);
      paging.rows.last.exhausted = true;
      await paging.start();
      expect(paging.calls, ['0', '1', '2', '3']);
    },
  );

  test(
    'more catalogs waits for its loader and leaves the row cursor untouched',
    () async {
      final wait = Completer<void>();
      paging.onMore = () => wait.future;
      final pending = paging.start(more: true);
      expect(paging.calls, ['more']);
      expect(paging.controller.busy, isTrue);
      wait.complete();
      await pending;
      paging.hasMore = false;
      await paging.start(more: true);
      expect(paging.calls, ['more']);
      await paging.start();
      expect(paging.calls, ['more', '0', '1', '2', '3']);
    },
  );

  test('an accepted empty inventory releases busy without fetching', () async {
    paging.rows.clear();
    expect(paging.start(), isNotNull);
    await pumpEventQueue();
    expect(paging.calls, isEmpty);
    expect(paging.states, [true, false]);
  });

  test(
    'row and vertical failures propagate once and release the latch',
    () async {
      final error = StateError('page failed');
      paging.onRow = (_) async => throw error;
      await expectLater(paging.start(), throwsA(same(error)));
      expect(paging.calls, ['0']);
      expect(paging.controller.busy, isFalse);
      paging.onRow = null;
      await paging.start();
      expect(paging.calls, ['0', '4', '5', '0', '1']);
      paging.onMore = () async => throw error;
      await expectLater(paging.start(more: true), throwsA(same(error)));
      expect(paging.controller.busy, isFalse);
      expect(paging.calls.where((c) => c == 'more'), hasLength(1));
    },
  );

  for (final retirement in ['view', 'profile', 'dispose']) {
    test(
      '$retirement retirement stops an accepted batch after its pending row',
      () async {
        final wait = Completer<void>();
        paging.onRow = (_) => wait.future;
        final pending = paging.start();
        switch (retirement) {
          case 'view':
            paging.current = false;
          case 'profile':
            ProfileRuntime.debugReset();
          case 'dispose':
            paging.container.dispose();
        }
        wait.complete();
        await pending;
        expect(paging.calls, ['0']);
        expect(paging.start(), isNull);
        expect(paging.controller.busy, isFalse);
      },
    );
  }

  test(
    'recomputation retires an old batch without releasing a newer busy action',
    () async {
      final oldWait = Completer<void>(), newWait = Completer<void>();
      paging.onRow = (_) => oldWait.future;
      final old = paging.start();
      paging.container.invalidate(
        homeCatalogContinuationProvider(paging.session),
      );
      expect(
        paging.container.read(homeCatalogContinuationProvider(paging.session)),
        isFalse,
      );
      paging.onRow = (_) => newWait.future;
      final newer = paging.start();
      expect(paging.calls, ['0', '4']);
      oldWait.complete();
      await old;
      expect(paging.controller.busy, isTrue);
      expect(paging.calls, ['0', '4']);
      newWait.complete();
      await newer;
      expect(paging.calls, ['0', '4', '5', '0', '1']);
      expect(paging.controller.busy, isFalse);
    },
  );

  test(
    'independent mounted views do not share busy state or rotation',
    () async {
      final wait = Completer<void>();
      paging.onRow = (_) => wait.future;
      final pending = paging.start();
      final other = PagingHarness();
      await other.start();
      expect(other.calls, ['0', '1', '2', '3']);
      expect(paging.calls, ['0']);
      wait.complete();
      await pending;
    },
  );
}
