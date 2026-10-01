import 'dart:async';

import 'package:debrify/features/home/application/home_catalog_controller.dart';
import 'package:debrify/features/home/application/home_board_providers.dart';
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
StremioMeta item(String id) => StremioMeta(id: id, type: 'movie', name: id);

typedef Fetch = Future<List<StremioMeta>> Function(String id);

HomeCatalogRepository repository(Fetch fetch) => HomeCatalogRepository(
  readAddons: () async => [addon],
  readHides: () => null,
  fetchPage: (addon, catalog, skip, raw) async {
    final items = await fetch(catalog.id);
    raw(items.length);
    return items;
  },
);

HomeCatalogController mount(
  ProviderContainer container,
  HomeCatalogSession key,
) {
  container.listen(homeCatalogProvider(key), (_, _) {});
  return container.read(homeCatalogProvider(key).notifier);
}

void main() {
  late HomeCatalogSession session;
  setUp(() {
    session = HomeCatalogSession(
      owner: ProfileSessionMemory.captureOwner(),
      viewIdentity: Object(),
    );
  });

  test(
    'empty and excluded batches commit before continuing to a new row',
    () async {
      final requests = <String>[];
      final container = ProviderContainer.test(
        overrides: [
          homeCatalogRepositoryProvider.overrideWithValue(
            repository((id) async {
              requests.add(id);
              return id == 'empty' ? [] : [item(id)];
            }),
          ),
        ],
      );
      final controller = mount(container, session);
      expect(await controller.readAddons(), [addon]);
      controller.install([row('empty'), row('existing'), row('fresh')]);
      final commits = <int>[];
      final published = <String>[];
      final pending = controller.fetchUntilNonEmpty(
        1,
        generation: controller.generation,
        isCurrent: () => true,
        canContinue: () => true,
        excludeRows: {'fixture:movie:existing'},
        onSection: (row) => published.add(row.catalog.id),
        onBatchComplete: () {
          controller.commit({'fixture': addon});
          commits.add(controller.current.committed!.cursor);
        },
      );
      expect(controller.current.cursor, 1);
      final result = await pending;
      expect(requests, ['empty', 'existing', 'fresh']);
      expect(published, ['existing', 'fresh']);
      expect(commits, [1, 2, 3]);
      expect(result.single.catalog.id, 'fresh');
    },
  );

  test(
    'covered empty batch pauses and later resumes from its next cursor',
    () async {
      final requests = <String>[];
      final container = ProviderContainer.test(
        overrides: [
          homeCatalogRepositoryProvider.overrideWithValue(
            repository((id) async {
              requests.add(id);
              return id == 'empty' ? [] : [item(id)];
            }),
          ),
        ],
      );
      final controller = mount(container, session);
      controller.install([row('empty'), row('fresh')]);
      var checks = 0;
      final empty = await controller.fetchUntilNonEmpty(
        1,
        generation: controller.generation,
        isCurrent: () => true,
        canContinue: () {
          checks++;
          return false;
        },
      );
      expect(empty, isEmpty);
      expect(requests, ['empty']);
      expect(controller.current.cursor, 1);
      final result = await controller.fetchUntilNonEmpty(
        1,
        generation: controller.generation,
        isCurrent: () => true,
        canContinue: () {
          checks++;
          return false;
        },
      );
      expect(result.single.catalog.id, 'fresh');
      expect(requests, ['empty', 'fresh']);
      // A non-empty accepted batch returns before checking route continuation.
      expect(checks, 1);
    },
  );

  test(
    'retired completion cannot commit or consume a replacement inventory',
    () async {
      final response = Completer<List<StremioMeta>>();
      final requests = <String>[];
      final container = ProviderContainer.test(
        overrides: [
          homeCatalogRepositoryProvider.overrideWithValue(
            repository((id) {
              requests.add(id);
              return response.future;
            }),
          ),
        ],
      );
      final controller = mount(container, session);
      controller.install([row('old'), row('old-tail')]);
      var current = true;
      var commits = 0;
      final published = <CatalogSection>[];
      final pending = controller.fetchUntilNonEmpty(
        1,
        generation: controller.generation,
        isCurrent: () => current,
        canContinue: () => true,
        onSection: published.add,
        onBatchComplete: () => commits++,
      );
      current = false;
      controller.install([row('replacement')]);
      response.complete([item('late')]);
      expect(await pending, isEmpty);
      expect(commits, 0);
      expect(published, isEmpty);
      expect(requests, ['old']);
      expect(controller.current.cursor, 0);
      expect(controller.current.references.single.$2.id, 'replacement');
    },
  );

  test(
    'disposal while fetching cannot publish, commit or start another batch',
    () async {
      final response = Completer<List<StremioMeta>>();
      final requests = <String>[];
      final container = ProviderContainer(
        overrides: [
          homeCatalogRepositoryProvider.overrideWithValue(
            repository((id) {
              requests.add(id);
              return response.future;
            }),
          ),
        ],
      );
      final controller = mount(container, session);
      controller.install([row('first'), row('tail')]);
      var commits = 0;
      final published = <CatalogSection>[];
      final pending = controller.fetchUntilNonEmpty(
        1,
        generation: controller.generation,
        isCurrent: () => true,
        canContinue: () => true,
        onSection: published.add,
        onBatchComplete: () => commits++,
      );
      container.dispose();
      response.complete([item('late')]);
      expect(await pending, isEmpty);
      expect(requests, ['first']);
      expect(commits, 0);
      expect(published, isEmpty);
    },
  );

  test(
    'rejected reservation leaves inventory available and makes no request',
    () async {
      final requests = <String>[];
      final container = ProviderContainer.test(
        overrides: [
          homeCatalogRepositoryProvider.overrideWithValue(
            repository((id) async {
              requests.add(id);
              return [item(id)];
            }),
          ),
        ],
      );
      final controller = mount(container, session);
      controller.install([row('first')]);
      expect(
        await controller.fetchBatch(
          1,
          generation: controller.generation - 1,
          isCurrent: () => true,
        ),
        isEmpty,
      );
      expect(controller.current.cursor, 0);
      expect(requests, isEmpty);
      final rows = await controller.fetchBatch(
        1,
        generation: controller.generation,
        isCurrent: () => true,
      );
      expect(rows.single.catalog.id, 'first');
      expect(requests, ['first']);
    },
  );

  test(
    'explicit child scopes use their own catalog repository and cursor',
    () async {
      final requests = <String>[];
      HomeCatalogRepository scoped(String label) => repository((id) async {
        requests.add('$label:$id');
        return [item(label)];
      });
      final parent = ProviderContainer.test(
        overrides: [
          homeCatalogRepositoryProvider.overrideWithValue(scoped('parent')),
        ],
      );
      final original = mount(parent, session);
      original.install([row('a'), row('b')]);
      for (final label in ['one', 'two']) {
        final child = ProviderContainer.test(
          parent: parent,
          overrides: [
            homeCatalogRepositoryProvider.overrideWithValue(scoped(label)),
            homeCatalogProvider(
              session,
            ).overrideWith(() => HomeCatalogController(session)),
          ],
        );
        final controller = mount(child, session);
        controller.install([row('child')]);
        final rows = await controller.fetchBatch(
          1,
          generation: controller.generation,
          isCurrent: () => true,
        );
        expect(rows.single.items.single.id, label);
        expect(original.current.cursor, 0);
      }
      final rows = await original.fetchBatch(
        1,
        generation: original.generation,
        isCurrent: () => true,
      );
      expect(rows.single.items.single.id, 'parent');
      expect(original.current.cursor, 1);
      expect(requests, ['one:child', 'two:child', 'parent:a']);
    },
  );
}
