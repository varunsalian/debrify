import 'dart:async';
import 'package:debrify/features/home/application/home_catalog_controller.dart';
import 'package:debrify/features/home/application/home_configuration_refresh.dart';
import 'package:debrify/features/home/data/home_catalog_preferences_repository.dart';
import 'package:debrify/features/home/data/home_collections_repository.dart';
import 'package:debrify/features/home/models/home_board_configuration.dart';
import 'package:debrify/features/home/models/home_catalog_preferences.dart';
import 'package:debrify/features/home/models/home_catalog_session.dart';
import 'package:debrify/models/home_collection.dart';
import 'package:debrify/models/home_preferences.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ProviderContainer container;
  late HomeCatalogController catalog;
  late HomeCatalogSession session;
  late List<String> calls;
  var current = true;
  var watched = false;
  var retireAt = '';
  var failAt = '';
  var readWarnings = 0;
  late HomeCatalogPreferences next;
  late List<HomeCollection> saved;
  Future<String> Function(List<HomeCollection>)? signature;

  setUp(() {
    container = ProviderContainer.test();
    session = HomeCatalogSession(
      owner: ProfileSessionMemory.captureOwner(),
      viewIdentity: Object(),
    );
    container.listen(homeCatalogProvider(session), (_, _) {});
    catalog = container.read(homeCatalogProvider(session).notifier);
    calls = [];
    current = true;
    watched = false;
    retireAt = '';
    failAt = '';
    readWarnings = 0;
    next = const HomeCatalogPreferences.empty();
    saved = const [];
    signature = null;
  });

  void step(String name) {
    calls.add(name);
    if (retireAt == name) current = false;
    if (failAt == name) throw StateError(name);
  }

  HomeConfigurationRefresh operation() => HomeConfigurationRefresh(
    catalog: catalog,
    preferences: HomeCatalogPreferencesRepository(
      readDisabled: () async {
        step('preferences');
        return next.disabled;
      },
      readExtras: () async => next.extras,
      readRowOrder: () async => next.rowOrder,
      readHeroSource: () async => next.heroSource,
    ),
    collections: HomeCollectionsRepository(
      read: () async {
        step('collections');
        return saved;
      },
      signature: (rows) async {
        step('signature');
        expect(rows, saved);
        return signature == null ? '' : await signature!(rows);
      },
      onReadFailure: () => readWarnings++,
    ),
    readHideWatched: () {
      step('watched');
      return watched;
    },
  );

  test(
    'sequential read accepts one complete snapshot before returning effects',
    () async {
      watched = true;
      saved = [const HomeCollection(id: 'a', title: 'A')];
      signature = (_) async => 'a';
      final seen = <HomeBoardConfiguration>[];
      container.listen(
        homeCatalogProvider(session),
        (_, state) => seen.add(state.configuration),
      );
      final changes = (await operation().run(
        isCurrent: () => current,
        isHome: true,
      ))!;
      expect(calls, ['preferences', 'collections', 'watched', 'signature']);
      expect(changes.reloadBoard, isTrue);
      expect(changes.reloadHero, isFalse);
      expect(seen, hasLength(1));
      expect(seen.single, same(catalog.current.configuration));
      expect(seen.single.collections.single, same(saved.single));
      expect(seen.single.collectionsSignature, 'a');
      expect(seen.single.hideWatched, isTrue);
      expect(() => seen.single.collections.clear(), throwsUnsupportedError);
    },
  );

  test(
    'unchanged values retain the accepted snapshot without notification',
    () async {
      final previous = catalog.current.configuration;
      var notifications = 0;
      container.listen(homeCatalogProvider(session), (_, _) => notifications++);
      final changes = await operation().run(
        isCurrent: () => current,
        isHome: true,
      );
      expect(changes, (
        changed: false,
        reloadBoard: false,
        reloadHero: false,
        reloadIptv: false,
      ));
      expect(catalog.current.configuration, same(previous));
      expect(notifications, 0);
    },
  );

  for (final isHome in [true, false]) {
    test(
      'hero/IPTV acceptance retains variant-specific effects: Home=$isHome',
      () async {
        next = HomeCatalogPreferences(
          disabled: {},
          extras: [(id: 'iptvlist:a', title: 'A')],
          rowOrder: [],
          heroSource: (mode: HomeHeroSourceMode.custom, ids: ['hero']),
        );
        final changes = (await operation().run(
          isCurrent: () => current,
          isHome: isHome,
        ))!;
        expect(changes, (
          changed: true,
          reloadBoard: false,
          reloadHero: isHome,
          reloadIptv: true,
        ));
        expect(catalog.current.configuration.preferences.heroSource.ids, [
          'hero',
        ]);
        expect(catalog.current.configuration.preferences.extras, next.extras);
      },
    );
  }

  for (final boundary in [
    'before',
    'preferences',
    'collections',
    'signature',
  ]) {
    test(
      'retirement at $boundary does not accept settings or start later operations',
      () async {
        watched = true;
        retireAt = boundary;
        if (boundary == 'before') current = false;
        final previous = catalog.current.configuration;
        expect(
          await operation().run(isCurrent: () => current, isHome: true),
          isNull,
        );
        expect(catalog.current.configuration, same(previous));
        expect(calls, switch (boundary) {
          'before' => <String>[],
          'preferences' => ['preferences'],
          'collections' => ['preferences', 'collections'],
          _ => ['preferences', 'collections', 'watched', 'signature'],
        });
      },
    );
  }

  for (final failure in ['preferences', 'signature']) {
    test(
      '$failure failure propagates without replacing accepted configuration',
      () async {
        failAt = failure;
        watched = true;
        final previous = catalog.current.configuration;
        await expectLater(
          operation().run(isCurrent: () => current, isHome: true),
          throwsStateError,
        );
        expect(catalog.current.configuration, same(previous));
      },
    );
  }

  test(
    'collection read failure keeps the existing empty-collection fallback',
    () async {
      failAt = 'collections';
      watched = true;
      final changes = (await operation().run(
        isCurrent: () => current,
        isHome: true,
      ))!;
      expect(changes.reloadBoard, isTrue);
      expect(readWarnings, 1);
      expect(catalog.current.configuration.collections, isEmpty);
      expect(catalog.current.configuration.hideWatched, isTrue);
    },
  );

  test(
    'hash overlap uses captured watched values and the latest other configuration',
    () async {
      final hashing = Completer<void>();
      final complete = Completer<String>();
      watched = true;
      next = HomeCatalogPreferences(
        disabled: {},
        extras: [],
        rowOrder: [],
        heroSource: (mode: HomeHeroSourceMode.custom, ids: ['hero']),
      );
      signature = (_) {
        hashing.complete();
        return complete.future;
      };
      final pending = operation().run(isCurrent: () => current, isHome: true);
      await hashing.future;
      watched = false;
      catalog.applyConfiguration(
        HomeBoardConfiguration(
          preferences: next,
          collections: [],
          collectionsSignature: 'new',
          hideWatched: true,
        ),
      );
      complete.complete('new');
      final changes = (await pending)!;
      expect(changes, (
        changed: true,
        reloadBoard: true,
        reloadHero: false,
        reloadIptv: false,
      ));
      expect(catalog.current.configuration.hideWatched, isTrue);
    },
  );
}
