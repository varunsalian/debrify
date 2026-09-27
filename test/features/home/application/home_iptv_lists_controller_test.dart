import 'dart:async';
import 'package:debrify/features/home/application/home_iptv_lists_controller.dart';
import 'package:debrify/features/home/application/home_iptv_lists_dependencies.dart';
import 'package:debrify/features/home/models/home_favorites_session.dart';
import 'package:debrify/features/home/models/home_iptv_list.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../fixtures/iptv_lists_fixture.dart';

HomeFavoritesSession session() =>
    (owner: ProfileSessionMemory.captureOwner(), viewIdentity: Object());
HomeIptvListsController mount(ProviderContainer c, HomeFavoritesSession key) {
  c.listen(homeIptvListsProvider(key), (_, _) {});
  return c.read(homeIptvListsProvider(key).notifier);
}

Future<void> load(
  HomeIptvListsController c, {
  bool Function()? current,
  void Function(List<HomeIptvList>)? before,
  void Function()? rows,
}) => c.load(
  isCurrent: current ?? () => true,
  beforeRows: before ?? (_) {},
  onRows: rows ?? () {},
);

void main() {
  test(
    'later-list failure retains complete snapshot without partial focus effects',
    () async {
      var reads = 0;
      var failLater = false;
      var title = 'Old';
      final c = ProviderContainer.test(
        overrides: [
          homeIptvListsRepositoryProvider.overrideWithValue(
            repository(
              extras: () async => [
                (id: 'iptvlist:a', title: ''),
                (id: 'iptvlist:b', title: ''),
              ],
              lists: () async => [meta('a', title: title), meta('b')],
              channels: (id) async {
                reads++;
                if (failLater && id == 'b') throw StateError('second list');
                return saved(id);
              },
            ),
          ),
        ],
      );
      final controller = mount(c, session());
      expect(reads, 0);
      final effects = <String>[];
      await load(
        controller,
        before: (rows) {
          expect(controller.current, isEmpty);
          expect(rows.length, 2);
          effects.add('focus');
        },
        rows: () {
          expect(controller.current.first.title, 'Old');
          effects.add('repaint');
        },
      );
      expect(effects, ['focus', 'repaint']);
      final accepted = controller.current;
      failLater = true;
      title = 'New';
      await load(
        controller,
        before: (_) => fail('partial focus update'),
        rows: () => fail('partial repaint'),
      );
      expect(controller.current, same(accepted));
      expect(controller.current.first.title, 'Old');
      expect(reads, 4);
    },
  );

  test(
    'no opt-ins is a no-op only when already empty; unmatched opt-ins publish',
    () async {
      var enabled = false;
      var unmatched = false;
      final c = ProviderContainer.test(
        overrides: [
          homeIptvListsRepositoryProvider.overrideWithValue(
            repository(
              extras: () async =>
                  enabled ? [(id: 'iptvlist:a', title: '')] : [],
              lists: () async => unmatched ? [] : [meta('a')],
              channels: (_) async => saved('One'),
            ),
          ),
        ],
      );
      final controller = mount(c, session());
      var effects = 0;
      Future<void> refresh() => load(controller, rows: () => effects++);
      await refresh();
      expect(effects, 0);
      enabled = true;
      await refresh();
      expect(controller.current.length, 1);
      expect(effects, 1);
      enabled = false;
      await refresh();
      expect(controller.current, isEmpty);
      expect(effects, 2);
      await refresh();
      expect(effects, 2);
      enabled = true;
      unmatched = true;
      await refresh();
      expect(controller.current, isEmpty);
      expect(effects, 3);
    },
  );

  test('newest multi-list load alone reconciles and publishes', () async {
    final pending = Completer<SavedChannels>();
    final entered = Completer<void>();
    var reads = 0;
    final c = ProviderContainer.test(
      overrides: [
        homeIptvListsRepositoryProvider.overrideWithValue(
          repository(
            channels: (_) {
              if (++reads == 1) {
                entered.complete();
                return pending.future;
              }
              return Future.value(saved('New'));
            },
          ),
        ),
      ],
    );
    final controller = mount(c, session());
    final old = load(
      controller,
      before: (_) => fail('old focus update'),
      rows: () => fail('old repaint'),
    );
    await entered.future;
    await load(controller);
    pending.complete(saved('Old'));
    await old;
    expect(controller.current.single.channels.single.name, 'New');
  });

  for (final reason in ['profile', 'dispose', 'view', 'recompute']) {
    test(
      '$reason during channel read rejects rows and focus effects',
      () async {
        final pending = Completer<SavedChannels>();
        final entered = Completer<void>();
        final c = ProviderContainer.test(
          overrides: [
            homeIptvListsRepositoryProvider.overrideWithValue(
              repository(
                channels: (_) {
                  entered.complete();
                  return pending.future;
                },
              ),
            ),
          ],
        );
        final key = session();
        final controller = mount(c, key);
        var active = true;
        final request = load(
          controller,
          current: () => active,
          before: (_) => fail('retired focus'),
          rows: () => fail('retired repaint'),
        );
        await entered.future;
        switch (reason) {
          case 'profile':
            ProfileSessionMemory.clearAll();
          case 'dispose':
            c.dispose();
          case 'view':
            active = false;
          case 'recompute':
            c.invalidate(homeIptvListsProvider(key));
            c.read(homeIptvListsProvider(key));
        }
        pending.complete(saved('One'));
        await request;
        expect(controller.current, isEmpty);
      },
    );
  }

  test(
    'nested dependency override and sibling views isolate snapshots',
    () async {
      final key = session();
      final parent = ProviderContainer.test(
        overrides: [
          homeIptvListsRepositoryProvider.overrideWithValue(
            repository(channels: (_) async => saved('Parent')),
          ),
        ],
      );
      final root = mount(parent, key);
      await load(root);
      final sibling = mount(parent, session());
      final child = ProviderContainer.test(
        parent: parent,
        overrides: [
          homeIptvListsRepositoryProvider.overrideWithValue(
            repository(channels: (_) async => saved('Child')),
          ),
          homeIptvListsProvider(
            key,
          ).overrideWith(() => HomeIptvListsController(key)),
        ],
      );
      final scoped = mount(child, key);
      await load(scoped);
      expect(root.current.single.channels.single.name, 'Parent');
      expect(scoped.current.single.channels.single.name, 'Child');
      expect(sibling.current, isEmpty);
    },
  );
}
