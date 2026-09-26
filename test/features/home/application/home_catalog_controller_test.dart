import 'package:debrify/features/home/application/home_catalog_controller.dart';
import 'package:debrify/features/home/models/home_catalog_plan.dart';
import 'package:debrify/features/home/models/home_catalog_state.dart';
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
  late ProviderSubscription<HomeCatalogState> subscription;
  setUp(() {
    container = ProviderContainer.test();
    session = HomeCatalogSession(
      owner: ProfileSessionMemory.captureOwner(),
      viewIdentity: Object(),
    );
    subscription = container.listen(homeCatalogProvider(session), (_, _) {});
    controller = container.read(homeCatalogProvider(session).notifier);
  });

  test(
    'reservation is synchronous, disjoint and bounded without committing',
    () {
      final rows = [row('a'), row('b'), row('c')];
      controller.install(rows);
      expect(controller.reserve(2), rows.take(2));
      final reserved = subscription.read();
      expect(reserved.cursor, 2);
      expect(reserved.committed, isNull);
      expect(controller.reserve(2), [rows.last]);
      expect(controller.current.hasMore, isFalse);
      expect(controller.reserve(2), isEmpty);
      expect(reserved.cursor, 2);
      expect(reserved.hasMore, isTrue);
    },
  );

  test('overlapping refresh reservations recover only the accepted board', () {
    final original = [row('a'), row('b'), row('c')];
    final lookup = {'fixture': addon};
    controller.install(original);
    controller.reserve(1);
    controller.commit(lookup);
    final accepted = controller.current.committed!;
    original.clear();
    lookup.clear();
    controller.reserve(1);
    controller.install([row('new-a'), row('new-b')]);
    controller.reserve(2);
    expect(controller.current.committed, same(accepted));
    controller.install([row('newer')]);
    controller.reserve(1);
    controller.restore(accepted);
    expect(controller.current.cursor, 1);
    expect(controller.current.references.map((r) => r.$2.id), ['a', 'b', 'c']);
    expect(controller.current.committed!.addons, {'fixture': addon});
    expect(controller.reserve(2).map((r) => r.$2.id), ['b', 'c']);
  });

  test('accepted progressive batches replace the recovery point', () {
    controller.install([row('a'), row('b'), row('c')]);
    controller.commit({'fixture': addon});
    final empty = controller.current.committed!;
    controller.reserve(1);
    controller.commit({'fixture': addon});
    final first = controller.current.committed!;
    controller.reserve(2);
    controller.restore(first);
    expect(empty.cursor, 0);
    expect(first.cursor, 1);
    expect(controller.current.cursor, 1);
    expect(controller.reserve(1).single.$2.id, 'b');
  });

  test('published inventory and committed containers cannot be mutated', () {
    final input = [row('a'), row('b')];
    controller.install(input);
    final initial = subscription.read();
    input.clear();
    expect(initial.references, hasLength(2));
    expect(() => initial.references.clear(), throwsUnsupportedError);
    controller.reserve(1);
    expect(controller.current.references, same(initial.references));
    controller.commit({'fixture': addon});
    final snapshot = controller.current.committed!;
    expect(() => snapshot.references.clear(), throwsUnsupportedError);
    expect(() => snapshot.addons.clear(), throwsUnsupportedError);
  });

  test('independent views and profile epochs do not share inventory', () {
    controller.install([row('original')]);
    final otherView = HomeCatalogSession(
      owner: session.owner,
      viewIdentity: Object(),
    );
    container.listen(homeCatalogProvider(otherView), (_, _) {});
    final second = container.read(homeCatalogProvider(otherView).notifier);
    second.install([row('second')]);
    second.reserve(1);
    ProfileSessionMemory.clearAll();
    final newEpoch = HomeCatalogSession(
      owner: ProfileSessionMemory.captureOwner(),
      viewIdentity: session.viewIdentity,
    );
    container.listen(homeCatalogProvider(newEpoch), (_, _) {});
    final third = container.read(homeCatalogProvider(newEpoch).notifier);
    expect(third.current.references, isEmpty);
    expect(controller.current.cursor, 0);
    expect(controller.current.references.single.$2.id, 'original');
    expect(second.current.references.single.$2.id, 'second');
    expect(second.current.cursor, 1);
  });

  test(
    'return snapshot survives disposal without retaining live state',
    () async {
      controller.install([row('a'), row('b')]);
      controller.reserve(1);
      controller.commit({'fixture': addon});
      final saved = controller.current.committed!;
      subscription.close();
      await container.pump();
      expect(container.exists(homeCatalogProvider(session)), isFalse);
      expect(controller.reserve(2), isEmpty);
      controller.install([row('late')]);
      controller.commit({'fixture': addon});
      controller.restore(saved);
      expect(controller.current.references, isEmpty);
      final returning = HomeCatalogSession(
        owner: session.owner,
        viewIdentity: Object(),
        initialBoard: saved,
      );
      container.listen(homeCatalogProvider(returning), (_, _) {});
      final next = container.read(homeCatalogProvider(returning).notifier);
      expect(next.current.committed, same(saved));
      expect(next.reserve(1).single.$2.id, 'b');
      expect(saved.cursor, 1);
    },
  );
}
