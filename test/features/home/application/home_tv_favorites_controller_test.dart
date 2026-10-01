import 'dart:async';
import 'package:debrify/features/home/application/home_tv_favorites_controller.dart';
import 'package:debrify/features/home/application/home_saved_content_providers.dart';
import 'package:debrify/features/home/data/home_tv_favorites_repository.dart';
import 'package:debrify/features/home/models/home_favorites_session.dart';
import 'package:debrify/models/debrify_tv_channel_record.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../fixtures/tv_favorites_fixture.dart';

HomeFavoritesSession session() =>
    (owner: ProfileSessionMemory.captureOwner(), viewIdentity: Object());
HomeTvFavoritesController mount(ProviderContainer c, HomeFavoritesSession key) {
  c.listen(homeTvFavoritesProvider(key), (_, _) {});
  return c.read(homeTvFavoritesProvider(key).notifier);
}

Future<void> load(
  HomeTvFavoritesController c, {
  bool Function()? current,
  void Function(bool)? rows,
}) => c.load(isCurrent: current ?? () => true, onRows: rows ?? (_) {});

void main() {
  test(
    'publishes before effects; failures retain rows; empty IDs and unmatched IDs differ',
    () async {
      var ids = {'a'};
      var failed = false;
      var reads = 0;
      final c = ProviderContainer.test(
        overrides: [
          homeTvFavoritesRepositoryProvider.overrideWithValue(
            HomeTvFavoritesRepository(
              favoriteIds: () async => ids,
              channels: () async {
                reads++;
                if (failed) throw StateError('database');
                return [channel('a')];
              },
            ),
          ),
        ],
      );
      final controller = mount(c, session());
      expect(reads, 0);
      await load(
        controller,
        rows: (hasIds) {
          expect(hasIds, isTrue);
          expect(controller.current.single.id, 'a');
        },
      );
      final accepted = controller.current;
      failed = true;
      await load(controller, rows: (_) => fail('Failed load published'));
      expect(controller.current, same(accepted));
      expect(reads, 2);
      ids = {};
      await load(controller, rows: (hasIds) => expect(hasIds, isFalse));
      expect(controller.current, isEmpty);
      expect(reads, 2);
      failed = false;
      ids = {'missing'};
      await load(controller, rows: (hasIds) => expect(hasIds, isTrue));
      expect(controller.current, isEmpty);
      expect(reads, 3);
    },
  );

  test('newer load wins and older response cannot repaint', () async {
    final pending = Completer<List<DebrifyTvChannelRecord>>();
    final entered = Completer<void>();
    var reads = 0;
    final c = ProviderContainer.test(
      overrides: [
        homeTvFavoritesRepositoryProvider.overrideWithValue(
          HomeTvFavoritesRepository(
            favoriteIds: () async => {'old', 'new'},
            channels: () {
              if (++reads == 1) {
                entered.complete();
                return pending.future;
              }
              return Future.value([channel('new')]);
            },
          ),
        ),
      ],
    );
    final controller = mount(c, session());
    final old = load(controller, rows: (_) => fail('Older response published'));
    await entered.future;
    await load(controller);
    pending.complete([channel('old')]);
    await old;
    expect(controller.current.single.id, 'new');
  });

  for (final reason in ['profile', 'dispose', 'view', 'recompute']) {
    test('$reason while IDs are pending prevents channel access', () async {
      final pending = Completer<Set<String>>();
      var reads = 0;
      final c = ProviderContainer.test(
        overrides: [
          homeTvFavoritesRepositoryProvider.overrideWithValue(
            HomeTvFavoritesRepository(
              favoriteIds: () => pending.future,
              channels: () async {
                reads++;
                return [channel('a')];
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
        rows: (_) => fail('Retired response published'),
      );
      switch (reason) {
        case 'profile':
          ProfileSessionMemory.clearAll();
        case 'dispose':
          c.dispose();
        case 'view':
          active = false;
        case 'recompute':
          c.invalidate(homeTvFavoritesProvider(key));
          c.read(homeTvFavoritesProvider(key));
      }
      pending.complete({'a'});
      await request;
      expect(reads, 0);
      expect(controller.current, isEmpty);
    });
  }

  test(
    'explicit nested override and sibling views retain separate favourites',
    () async {
      HomeTvFavoritesRepository repository(String id) =>
          HomeTvFavoritesRepository(
            favoriteIds: () async => {id},
            channels: () async => [channel(id)],
          );
      final key = session();
      final parent = ProviderContainer.test(
        overrides: [
          homeTvFavoritesRepositoryProvider.overrideWithValue(
            repository('parent'),
          ),
        ],
      );
      final root = mount(parent, key);
      await load(root);
      final sibling = mount(parent, session());
      final child = ProviderContainer.test(
        parent: parent,
        overrides: [
          homeTvFavoritesRepositoryProvider.overrideWithValue(
            repository('child'),
          ),
          homeTvFavoritesProvider(
            key,
          ).overrideWith(() => HomeTvFavoritesController(key)),
        ],
      );
      final scoped = mount(child, key);
      await load(scoped);
      expect(root.current.single.id, 'parent');
      expect(scoped.current.single.id, 'child');
      expect(sibling.current, isEmpty);
    },
  );
}
