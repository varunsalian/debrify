import 'package:debrify/features/home/application/home_catalog_controller.dart';
import 'package:debrify/features/home/models/home_board_configuration.dart';
import 'package:debrify/features/home/models/home_catalog_preferences.dart';
import 'package:debrify/features/home/models/home_catalog_session.dart';
import 'package:debrify/models/home_collection.dart';
import 'package:debrify/models/home_preferences.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

HomeBoardConfiguration configuration(String id) => HomeBoardConfiguration(
  preferences: HomeCatalogPreferences(
    disabled: {id},
    extras: [(id: id, title: id)],
    rowOrder: [id],
    heroSource: (mode: HomeHeroSourceMode.custom, ids: [id]),
  ),
  collections: [HomeCollection(id: id, title: id)],
  collectionsSignature: id,
  hideWatched: true,
);

void main() {
  late ProviderContainer container;
  late HomeCatalogSession session;
  late HomeCatalogController controller;
  setUp(() {
    container = ProviderContainer.test();
    session = HomeCatalogSession(
      owner: ProfileSessionMemory.captureOwner(),
      viewIdentity: Object(),
    );
    container.listen(homeCatalogProvider(session), (_, _) {});
    controller = container.read(homeCatalogProvider(session).notifier);
  });

  test(
    'configuration detaches containers and preserves borrowed collection identity',
    () {
      const collection = HomeCollection(id: 'a', title: 'A');
      final collections = [collection];
      final disabled = {'hidden'};
      final heroIds = ['hero'];
      final value = HomeBoardConfiguration(
        preferences: HomeCatalogPreferences(
          disabled: disabled,
          extras: [],
          rowOrder: [],
          heroSource: (mode: HomeHeroSourceMode.custom, ids: heroIds),
        ),
        collections: collections,
        collectionsSignature: 'signature',
        hideWatched: true,
      );
      collections.clear();
      disabled.clear();
      heroIds.clear();
      expect(value.collections.single, same(collection));
      expect(value.preferences.disabled, {'hidden'});
      expect(value.preferences.heroSource.ids, ['hero']);
      expect(() => value.collections.clear(), throwsUnsupportedError);
      expect(() => value.preferences.disabled.clear(), throwsUnsupportedError);
      expect(
        () => value.preferences.heroSource.ids.clear(),
        throwsUnsupportedError,
      );
    },
  );

  test(
    'accepted configuration publishes atomically without altering older snapshots',
    () {
      final first = configuration('first');
      final second = configuration('second');
      final seen = <HomeBoardConfiguration>[];
      container.listen(
        homeCatalogProvider(session),
        (_, next) => seen.add(next.configuration),
      );
      controller.applyConfiguration(first);
      final oldState = controller.current;
      controller.applyConfiguration(second);
      expect(seen, [first, second]);
      expect(oldState.configuration, same(first));
      expect(controller.current.configuration, same(second));
      expect(oldState.configuration.preferences.extras.single.title, 'first');
      expect(controller.current.configuration.collectionsSignature, 'second');
    },
  );

  test(
    'catalog refresh, paging and timeout recovery retain accepted configuration',
    () {
      final config = configuration('accepted');
      controller.applyConfiguration(config);
      final addon = StremioAddon(
        id: 'a',
        name: 'A',
        manifestUrl: '',
        baseUrl: '',
      );
      controller.install([
        (addon, const StremioAddonCatalog(id: 'a', type: 'movie', name: 'A')),
      ]);
      controller.commit({'a': addon});
      final accepted = controller.current.committed!;
      final generation = controller.beginLoad();
      controller.reserve(1);
      final completion = controller.retireLoad(generation)!;
      controller.restore(accepted);
      controller.finishLoad(completion);
      expect(controller.beginPage(completion), isTrue);
      controller.finishPage(completion);
      expect(controller.current.configuration, same(config));
      expect(controller.current.cursor, 0);
    },
  );

  test(
    'cached configuration is available at creation without a follow-up update',
    () {
      final saved = configuration('saved');
      final returning = HomeCatalogSession(
        owner: session.owner,
        viewIdentity: Object(),
        initialConfiguration: saved,
      );
      var updates = 0;
      container.listen(homeCatalogProvider(returning), (_, _) => updates++);
      final next = container.read(homeCatalogProvider(returning).notifier);
      expect(next.current.configuration, same(saved));
      expect(updates, 0);
      next.applyConfiguration(configuration('new'));
      expect(saved.preferences.rowOrder, ['saved']);
      expect(saved.collections.single.id, 'saved');
      expect(updates, 1);
    },
  );

  test(
    'separate view and profile epochs do not inherit configuration',
    () async {
      final saved = configuration('outgoing');
      controller.applyConfiguration(saved);
      final sibling = HomeCatalogSession(
        owner: session.owner,
        viewIdentity: Object(),
      );
      container.listen(homeCatalogProvider(sibling), (_, _) {});
      final second = container.read(homeCatalogProvider(sibling).notifier);
      expect(second.current.configuration.preferences.disabled, isEmpty);
      ProfileSessionMemory.clearAll();
      final incoming = HomeCatalogSession(
        owner: ProfileSessionMemory.captureOwner(),
        viewIdentity: session.viewIdentity,
      );
      container.listen(homeCatalogProvider(incoming), (_, _) {});
      final third = container.read(homeCatalogProvider(incoming).notifier);
      expect(third.current.configuration.preferences.disabled, isEmpty);
      container.dispose();
      controller.applyConfiguration(configuration('late'));
      expect(controller.current.configuration.preferences.disabled, isEmpty);
      expect(saved.preferences.disabled, {'outgoing'});
    },
  );
}
