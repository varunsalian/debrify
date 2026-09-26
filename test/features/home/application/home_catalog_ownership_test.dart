import 'dart:async';

import 'package:debrify/features/home/application/home_catalog_controller.dart';
import 'package:debrify/features/home/application/home_catalog_dependencies.dart';
import 'package:debrify/features/home/data/home_catalog_repository.dart';
import 'package:debrify/features/home/models/home_catalog_plan.dart';
import 'package:debrify/features/home/models/home_catalog_session.dart';
import 'package:debrify/models/stremio_addon.dart';
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
HomeCatalogReference row(String id) =>
    (addon, StremioAddonCatalog(id: id, type: 'movie', name: id));

void main() {
  late ProviderContainer container;
  late HomeCatalogSession session;
  late HomeCatalogController controller;
  late Completer<List<StremioMeta>> response;
  setUp(() {
    response = Completer<List<StremioMeta>>();
    container = ProviderContainer.test(
      overrides: [
        homeCatalogRepositoryProvider.overrideWithValue(
          HomeCatalogRepository(
            readAddons: () async => [addon],
            readHides: () => null,
            fetchPage: (_, _, _, raw) {
              raw(1);
              return response.future;
            },
          ),
        ),
      ],
    );
    session = HomeCatalogSession(
      owner: ProfileSessionMemory.captureOwner(),
      viewIdentity: Object(),
    );
    container.listen(homeCatalogProvider(session), (_, _) {});
    controller = container.read(homeCatalogProvider(session).notifier);
  });

  test(
    'cold bootstrap starts a generation without a lifecycle notification',
    () {
      final cold = HomeCatalogSession(
        owner: session.owner,
        viewIdentity: Object(),
        initiallyRefreshing: true,
      );
      var updates = 0;
      container.listen(homeCatalogProvider(cold), (_, _) => updates++);
      final owner = container.read(homeCatalogProvider(cold).notifier);
      final initial = owner.current;
      final generation = owner.beginLoad();
      expect(owner.owns(generation), isTrue);
      expect(owner.current, same(initial));
      expect(owner.current.refreshing, isTrue);
      expect(owner.current.loadingMore, isFalse);
      expect(updates, 0);
      owner.finishLoad(generation);
      expect(owner.current.refreshing, isFalse);
      expect(updates, 1);
    },
  );

  test('old refresh and page finalizers cannot clear a newer loading flag', () {
    controller.install([row('a'), row('b')]);
    final previous = controller.generation;
    expect(controller.beginPage(previous), isTrue);
    expect(controller.beginPage(previous), isFalse);
    final refresh = controller.beginLoad();
    expect(controller.current.refreshing, isTrue);
    expect(controller.current.loadingMore, isFalse);
    controller.finishPage(previous);
    controller.finishLoad(previous);
    expect(controller.current.refreshing, isTrue);
    expect(controller.beginPage(refresh), isFalse);
    controller.finishLoad(refresh);
    expect(controller.beginPage(refresh), isTrue);
    controller.finishPage(previous);
    expect(controller.current.loadingMore, isTrue);
    controller.finishPage(refresh);
    expect(controller.current.loadingMore, isFalse);
    controller.reserve(2);
    expect(controller.beginPage(refresh), isFalse);
  });

  test(
    'timeout retires requests without granting a stale timeout new ownership',
    () {
      final first = controller.beginLoad();
      final second = controller.beginLoad();
      expect(controller.retireLoad(first), isNull);
      expect(controller.owns(second), isTrue);
      final completion = controller.retireLoad(second)!;
      expect(controller.owns(second), isFalse);
      expect(controller.current.refreshing, isTrue);
      controller.finishLoad(second);
      expect(controller.current.refreshing, isTrue);
      controller.finishLoad(completion);
      expect(controller.current.refreshing, isFalse);
    },
  );

  test(
    'superseded batch is rejected even when its external predicate stays true',
    () async {
      final first = controller.beginLoad();
      controller.install([row('old'), row('old-tail')]);
      final published = <CatalogSection>[];
      var commits = 0;
      final pending = controller.fetchUntilNonEmpty(
        1,
        generation: first,
        isCurrent: () => true,
        canContinue: () => true,
        onSection: published.add,
        onBatchComplete: () => commits++,
      );
      final second = controller.beginLoad();
      controller.install([row('new')]);
      response.complete([StremioMeta(id: 'late', type: 'movie', name: 'Late')]);
      expect(await pending, isEmpty);
      expect(published, isEmpty);
      expect(commits, 0);
      expect(controller.current.cursor, 0);
      expect(controller.current.references.single.$2.id, 'new');
      controller.finishLoad(first);
      expect(controller.current.refreshing, isTrue);
      controller.finishLoad(second);
      expect(controller.current.refreshing, isFalse);
    },
  );

  test(
    'cached bootstrap is idle and retains its accepted cursor during refresh',
    () {
      controller.install([row('a'), row('b')]);
      controller.reserve(1);
      controller.commit({'fixture': addon});
      final saved = controller.current.committed!;
      final returning = HomeCatalogSession(
        owner: session.owner,
        viewIdentity: Object(),
        initialBoard: saved,
      );
      container.listen(homeCatalogProvider(returning), (_, _) {});
      final owner = container.read(homeCatalogProvider(returning).notifier);
      expect(owner.current.refreshing, isFalse);
      expect(owner.current.loadingMore, isFalse);
      final generation = owner.beginLoad();
      owner.install([row('replacement')]);
      final completion = owner.retireLoad(generation)!;
      owner.restore(saved);
      owner.finishLoad(completion);
      expect(owner.current.cursor, 1);
      expect(owner.current.committed, same(saved));
      expect(owner.current.refreshing, isFalse);
      expect(owner.reserve(1).single.$2.id, 'b');
    },
  );

  test(
    'provider rebuild retires pending work before installing fresh state',
    () async {
      final first = controller.beginLoad();
      controller.install([row('old')]);
      final pending = controller.fetchBatch(
        1,
        generation: first,
        isCurrent: () => true,
      );
      container.invalidate(homeCatalogProvider(session));
      final replacement = container.read(homeCatalogProvider(session).notifier);
      final next = replacement.beginLoad();
      replacement.install([row('new')]);
      response.complete([StremioMeta(id: 'late', type: 'movie', name: 'Late')]);
      expect(await pending, isEmpty);
      expect(replacement.current.cursor, 0);
      expect(replacement.current.references.single.$2.id, 'new');
      expect(replacement.owns(next), isTrue);
    },
  );
}
