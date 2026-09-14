import 'dart:async';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/home_catalog_refresh.dart';
import 'package:debrify/services/home_load_deadline.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'a stalled credential read terminates and retires before error handling',
    (tester) async {
      final stalled = Completer<void>();
      var retired = false;
      Object? error;
      final load =
          runHomeLoadWithDeadline(
            load: () => stalled.future,
            retire: () => retired = true,
          ).catchError((Object e) {
            expectSync(retired, isTrue);
            error = e;
          });
      await tester.pump(const Duration(seconds: 24));
      expect(error, isNull);
      await tester.pump(const Duration(seconds: 1));
      await load;
      expect(error, isA<TimeoutException>());
      // A late native failure must be consumed, not become an unhandled error.
      stalled.completeError(StateError('engine detached'));
      await tester.pump();
    },
  );

  testWidgets(
    'late catalog completion cannot replace a successful retry or fetch more pages',
    (tester) async {
      const catalog = StremioAddonCatalog(
        id: 'popular',
        type: 'movie',
        name: 'Popular',
      );
      final oldAddon = StremioAddon(
        id: 'test',
        name: 'Test',
        manifestUrl: 'https://old.invalid/manifest.json',
        baseUrl: 'https://old.invalid',
        addedAt: DateTime.utc(2026),
        catalogs: [catalog],
      );
      final newAddon = StremioAddon(
        id: 'test',
        name: 'Test',
        manifestUrl: 'https://new.invalid/manifest.json',
        baseUrl: 'https://new.invalid',
        addedAt: DateTime.utc(2026),
        catalogs: [catalog],
      );
      final previous = CatalogSection(
        title: 'Popular',
        addon: oldAddon,
        catalog: catalog,
        items: [],
        nextSkip: 200,
      );
      final slowPage = Completer<List<StremioMeta>>();
      var generation = 1;
      var fetches = 0;
      CatalogSection? visible;
      final first = runHomeLoadWithDeadline(
        retire: () => generation++,
        load: () async {
          final row = await loadHomeCatalogSection(
            addon: newAddon,
            catalog: catalog,
            previous: previous,
            isCurrent: () => generation == 1,
            fetch: (skip, rawCount) {
              fetches++;
              rawCount(100);
              return slowPage.future;
            },
          );
          if (generation == 1) visible = row;
        },
      ).catchError((Object e) => expectSync(e, isA<TimeoutException>()));
      await tester.pump(const Duration(seconds: 25));
      await first;
      await runHomeLoadWithDeadline(
        retire: () => generation++,
        load: () async {
          visible = await loadHomeCatalogSection(
            addon: newAddon,
            catalog: catalog,
            isCurrent: () => generation == 2,
            fetch: (_, count) async {
              count(1);
              return [StremioMeta(id: 'retry', type: 'movie', name: 'Retry')];
            },
          );
        },
      );
      slowPage.complete([
        StremioMeta(id: 'stale', type: 'movie', name: 'Stale'),
      ]);
      await tester.pump();
      expect(visible!.items.single.id, 'retry');
      expect(fetches, 1);
    },
  );

  testWidgets('completed loads do not retire later', (tester) async {
    var retired = false;
    await runHomeLoadWithDeadline(
      load: () async {},
      retire: () => retired = true,
    );
    await tester.pump(const Duration(seconds: 30));
    expect(retired, isFalse);
  });
  testWidgets(
    'timed-out refresh restores remaining rows without accepting stale paging',
    (tester) async {
      final refs = ['row1', 'row2', 'row3', 'row4'];
      var cursor = 2; // The first two rows are already visible.
      final addons = {'original': 'original source'};
      final snapshot = HomeBoardSnapshot(refs, cursor, addons);
      // A pagination request can reserve another row before refresh begins.
      // Recovery uses the committed cursor, not that in-flight reservation.
      cursor = 3;
      var generation = 1;
      final blocked = Completer<void>();
      final refresh = runHomeLoadWithDeadline(
        retire: () {
          generation++;
          cursor = snapshot.restore(refs, addons);
        },
        load: () async {
          // Refresh starts to rebuild the live pagination before getting stuck.
          refs
            ..clear()
            ..add('replacement');
          cursor = 1;
          await blocked.future;
          if (generation != 1) return;
          refs
            ..clear()
            ..add('late');
          cursor = 1;
        },
      ).catchError((Object e) => expectSync(e, isA<TimeoutException>()));
      await tester.pump(const Duration(seconds: 25));
      await refresh;
      expect(refs.sublist(cursor), ['row3', 'row4']);
      // Scrolling must be able to advance from the restored position.
      expect(refs[cursor++], 'row3');
      blocked.complete();
      await tester.pump();
      expect(refs.sublist(cursor), ['row4']);
    },
  );
  testWidgets('overlapping refresh timeouts restore the last committed board', (
    tester,
  ) async {
    final refs = ['row1', 'row2', 'row3', 'row4'];
    final addons = {'original': 'original source'};
    var cursor = 2;
    var committed = HomeBoardSnapshot(refs, cursor, addons);
    var generation = 0;
    final firstResponse = Completer<void>();
    final secondResponse = Completer<void>();

    Future<void> refresh(String replacement, Completer<void> response) {
      final previousBoard = committed;
      final token = ++generation;
      return runHomeLoadWithDeadline(
        retire: () {
          if (token != generation) return;
          generation++;
          cursor = previousBoard.restore(refs, addons);
        },
        load: () async {
          refs
            ..clear()
            ..add(replacement);
          addons
            ..clear()
            ..addAll({replacement: 'tentative source'});
          cursor = 1;
          await response.future;
          if (token != generation) return;
          committed = HomeBoardSnapshot(refs, cursor, addons);
        },
      ).catchError((Object e) => expectSync(e, isA<TimeoutException>()));
    }

    final first = refresh('tentative A', firstResponse);
    await tester.pump(const Duration(seconds: 1));
    final second = refresh('tentative B', secondResponse);
    await tester.pump(const Duration(seconds: 24));
    await first;
    // An older timeout cannot interfere with the currently loading refresh.
    expect(refs, ['tentative B']);
    await tester.pump(const Duration(seconds: 1));
    await second;
    expect(refs, ['row1', 'row2', 'row3', 'row4']);
    expect(refs.sublist(cursor), ['row3', 'row4']);
    expect(addons, {'original': 'original source'});
    firstResponse.complete();
    secondResponse.complete();
    await tester.pump();
    expect(refs.sublist(cursor), ['row3', 'row4']);
    expect(committed.references, ['row1', 'row2', 'row3', 'row4']);
    expect(committed.addons, {'original': 'original source'});
  });
}
