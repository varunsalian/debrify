import 'dart:async';

import 'package:debrify/features/home/models/home_board_configuration.dart';
import 'package:debrify/features/home/models/home_catalog_preferences.dart';
import 'package:debrify/models/home_collection.dart';
import 'package:debrify/models/home_preferences.dart';
import 'package:debrify/services/home_collection_rows.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/home_board_load_fixture.dart';

void main() {
  late BoardLoadFixture fixture;
  setUp(() => fixture = BoardLoadFixture());
  tearDown(() => fixture.dispose());

  test(
    'configuration precedes data work and pinned/list/collection/catalog order is retained',
    () async {
      fixture.extras = [(id: 'traktlist:watchlist', title: 'Watchlist')];
      fixture.savedCollections = [
        const HomeCollection(
          id: 'normal',
          title: 'Normal',
          folders: [HomeCollectionFolder(id: 'n', title: 'N')],
        ),
        const HomeCollection(
          id: 'pin',
          title: 'Pin',
          pinToTop: true,
          folders: [HomeCollectionFolder(id: 'p', title: 'P')],
        ),
        const HomeCollection(
          id: 'off',
          title: 'Off',
          enabled: false,
          folders: [HomeCollectionFolder(id: 'o', title: 'O')],
        ),
      ];
      final retained = trackerRow('traktlist:watchlist');
      await fixture.run(
        previousLists: [retained, trackerRow('traktlist:removed')],
      );
      expect(fixture.trace, [
        'disabled',
        'extras',
        'order',
        'hero',
        'collections',
        'signature',
        'lists',
        'addons',
        'claimed',
        'inventory',
        'fetch:a',
        'completed',
      ]);
      final rows = fixture.completedRows!;
      expect((rows[0] as HomeCollectionSection).collection.id, 'pin');
      expect(rows[1], same(retained));
      expect((rows[2] as HomeCollectionSection).collection.id, 'normal');
      expect(rows[3].catalog.id, 'a');
      expect(rows, hasLength(4));
      expect(
        fixture.catalog.current.configuration.collectionsSignature,
        'fixture-signature',
      );
    },
  );

  test(
    'retirement during configuration hashing starts no tracker or catalog work',
    () async {
      final barrier = Completer<void>();
      fixture.signatureBarrier = barrier.future;
      fixture.extras = [(id: 'traktlist:watchlist', title: 'Watchlist')];
      final pending = fixture.run();
      await fixture.signatureStarted.future;
      fixture.current = false;
      barrier.complete();
      await pending;
      expect(fixture.trace, isNot(contains('lists')));
      expect(fixture.trace, isNot(contains('addons')));
      expect(fixture.completed, isFalse);
      expect(fixture.catalog.current.configuration.collectionsSignature, '');
    },
  );

  test(
    'watched snapshot gates discovery and retirement prevents further work',
    () async {
      final watched = Completer<void>();
      fixture.hideWatched = true;
      fixture.watchedSnapshot = watched.future;
      final pending = fixture.run();
      await fixture.watchedStarted.future;
      expect(fixture.trace, isNot(contains('addons')));
      fixture.current = false;
      watched.complete();
      await pending;
      expect(fixture.trace, isNot(contains('addons')));
      expect(fixture.completed, isFalse);
    },
  );

  testWidgets('watched wait keeps the existing 1500ms bound', (tester) async {
    fixture.signatureBarrier = Future.value();
    fixture.hideWatched = true;
    fixture.watchedSnapshot = Completer<void>().future;
    var done = false;
    fixture.run().then((_) => done = true);
    await tester.pump();
    expect(fixture.trace, contains('watched-start'));
    await tester.pump(const Duration(milliseconds: 1499));
    expect(fixture.trace, isNot(contains('addons')));
    await tester.pump(const Duration(milliseconds: 1));
    expect(done, isTrue);
    expect(fixture.completed, isTrue);
  });

  test(
    'inventory planning reads accepted settings after discovery awaits',
    () async {
      final discovered = Completer<void>();
      final barrier = Completer<void>();
      fixture.readAddons = () async {
        discovered.complete();
        await barrier.future;
        return [fixture.addon];
      };
      final pending = fixture.run();
      await discovered.future;
      fixture.catalog.applyConfiguration(
        HomeBoardConfiguration(
          preferences: HomeCatalogPreferences(
            disabled: {'fixture:movie:a'},
            extras: [],
            rowOrder: ['fixture:movie:c', 'fixture:movie:b'],
            heroSource: (mode: HomeHeroSourceMode.auto, ids: []),
          ),
          collections: [],
          collectionsSignature: 'new',
          hideWatched: false,
        ),
      );
      barrier.complete();
      await pending;
      expect(fixture.claimedDisabled, {'fixture:movie:a'});
      expect(fixture.trace, isNot(contains('fetch:a')));
      expect(fixture.completedRows!.single.catalog.id, 'c');
      expect(fixture.catalog.current.configuration.collectionsSignature, 'new');
    },
  );

  test('tab mode remains live across addon discovery', () async {
    final discovered = Completer<void>();
    final barrier = Completer<void>();
    fixture.savedCollections = [
      const HomeCollection(
        id: 'collection',
        title: 'Collection',
        folders: [HomeCollectionFolder(id: 'folder', title: 'Folder')],
      ),
    ];
    fixture.readAddons = () async {
      discovered.complete();
      await barrier.future;
      return [fixture.addon];
    };
    final pending = fixture.run();
    await discovered.future;
    fixture.isHome = false;
    barrier.complete();
    await pending;
    expect(fixture.claimedShowsCollections, isFalse);
    expect(fixture.completedRows!.whereType<HomeCollectionSection>(), isEmpty);
    expect(fixture.completedRows!.single.catalog.id, 'a');
  });

  test(
    'tracker updates remain eligible after catalog failure until retirement',
    () async {
      fixture.extras = [(id: 'traktlist:watchlist', title: 'Watchlist')];
      fixture.readAddons = () async => throw StateError('fixture');
      await expectLater(fixture.run(), throwsStateError);
      fixture.operation.finish();
      final rows = [trackerRow('traktlist:watchlist')];
      fixture.listsUpdate!(rows);
      expect(fixture.lateLists.single, same(rows));
      fixture.current = false;
      fixture.listsUpdate!([]);
      expect(fixture.lateLists, hasLength(1));
      fixture.listsResponse.completeError(StateError('tracker fixture'));
      await Future<void>.delayed(Duration.zero);
    },
  );

  test(
    'refresh preserves vertical extent across an empty intermediate batch',
    () async {
      fixture.fetch = (id) async => id == 'b' ? [] : [boardItem(id)];
      await fixture.run(previouslyLoaded: 3);
      expect(fixture.trace.where((event) => event.startsWith('fetch:')), [
        'fetch:a',
        'fetch:b',
        'fetch:c',
      ]);
      expect(fixture.completedRows!.map((row) => row.catalog.id), ['a', 'c']);
      expect(fixture.catalog.current.committed!.cursor, 3);
    },
  );

  test(
    'progressive load commits zero before reserving and completes after publication',
    () async {
      await fixture.run(progressive: true);
      expect(
        fixture.trace.indexOf('reset'),
        lessThan(fixture.trace.indexOf('inventory')),
      );
      expect(
        fixture.trace.indexOf('inventory'),
        lessThan(fixture.trace.indexOf('fetch:a')),
      );
      expect(fixture.commits, [0, 0, 1, 1]);
      expect(fixture.completed, isTrue);
      expect(fixture.completedRows, isNull);
      expect(fixture.published.last.single.catalog.id, 'a');
    },
  );
}
