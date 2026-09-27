import 'dart:async';
import 'package:debrify/features/home/application/home_stremio_favorites_controller.dart';
import 'package:debrify/features/home/application/home_stremio_favorites_dependencies.dart';
import 'package:debrify/features/home/data/home_stremio_favorites_repository.dart';
import 'package:debrify/features/home/models/home_favorites_session.dart';
import 'package:debrify/models/stremio_tv/stremio_tv_channel.dart';
import 'package:debrify/features/home/models/home_stremio_favorites.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../fixtures/stremio_favorites_fixture.dart';

HomeFavoritesSession session() =>
    (owner: ProfileSessionMemory.captureOwner(), viewIdentity: Object());
HomeStremioFavoritesController mount(
  ProviderContainer c,
  HomeFavoritesSession key,
) {
  c.listen(homeStremioFavoritesProvider(key), (_, _) {});
  return c.read(homeStremioFavoritesProvider(key).notifier);
}

Future<void> load(
  HomeStremioFavoritesController c, {
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
          homeStremioFavoritesRepositoryProvider.overrideWithValue(
            HomeStremioFavoritesRepository(
              favoriteIds: () async => ids,
              rotationMinutes: () async => 120,
              seriesRotationMinutes: () async => 30,
              loadItems: (_) async {},
              discover: () async {
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
          expect(controller.current.channels.single.id, 'a');
        },
      );
      final now = DateTime.utc(2026, 9, 27);
      final movie = controller.current.channels.single;
      final series = HomeStremioFavorite(
        id: movie.id,
        displayName: movie.displayName,
        type: 'series',
        items: movie.items,
      );
      final playingMovie = controller.playingAt(movie, now)!;
      final playingSeries = controller.playingAt(series, now)!;
      expect(
        playingMovie.slotEnd.difference(playingMovie.slotStart),
        const Duration(minutes: 120),
      );
      expect(
        playingSeries.slotEnd.difference(playingSeries.slotStart),
        const Duration(minutes: 30),
      );
      expect(playingMovie.item, same(movie.items.single));
      final accepted = controller.current;
      failed = true;
      await load(controller, rows: (_) => fail('Failed load published'));
      expect(controller.current, same(accepted));
      expect(reads, 2);
      expect(controller.current.rotationMinutes, 120);
      expect(controller.current.seriesRotationMinutes, 30);
      ids = {};
      await load(controller, rows: (hasIds) => expect(hasIds, isFalse));
      expect(controller.current.channels, isEmpty);
      expect(reads, 2);
      expect(controller.current.rotationMinutes, 120);
      expect(controller.current.seriesRotationMinutes, 30);
      failed = false;
      ids = {'missing'};
      await load(controller, rows: (hasIds) => expect(hasIds, isTrue));
      expect(controller.current.channels, isEmpty);
      expect(reads, 3);
    },
  );

  test('newer load wins and older response cannot repaint', () async {
    final pending = Completer<List<StremioTvChannel>>();
    final entered = Completer<void>();
    var reads = 0;
    final c = ProviderContainer.test(
      overrides: [
        homeStremioFavoritesRepositoryProvider.overrideWithValue(
          HomeStremioFavoritesRepository(
            favoriteIds: () async => {'old', 'new'},
            rotationMinutes: () async => 120,
            seriesRotationMinutes: () async => 30,
            loadItems: (_) async {},
            discover: () {
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
    expect(controller.current.channels.single.id, 'new');
  });

  for (final reason in ['profile', 'dispose', 'view', 'recompute']) {
    test('$reason while IDs are pending prevents channel access', () async {
      final pending = Completer<Set<String>>();
      var reads = 0;
      final c = ProviderContainer.test(
        overrides: [
          homeStremioFavoritesRepositoryProvider.overrideWithValue(
            HomeStremioFavoritesRepository(
              favoriteIds: () => pending.future,
              rotationMinutes: () async => 120,
              seriesRotationMinutes: () async => 30,
              loadItems: (_) async {},
              discover: () async {
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
          c.invalidate(homeStremioFavoritesProvider(key));
          c.read(homeStremioFavoritesProvider(key));
      }
      pending.complete({'a'});
      await request;
      expect(reads, 0);
      expect(controller.current.channels, isEmpty);
    });
  }

  test(
    'explicit nested override and sibling views retain separate favourites',
    () async {
      HomeStremioFavoritesRepository repository(String id) =>
          HomeStremioFavoritesRepository(
            favoriteIds: () async => {id},
            rotationMinutes: () async => 120,
            seriesRotationMinutes: () async => 30,
            loadItems: (_) async {},
            discover: () async => [channel(id)],
          );
      final key = session();
      final parent = ProviderContainer.test(
        overrides: [
          homeStremioFavoritesRepositoryProvider.overrideWithValue(
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
          homeStremioFavoritesRepositoryProvider.overrideWithValue(
            repository('child'),
          ),
          homeStremioFavoritesProvider(
            key,
          ).overrideWith(() => HomeStremioFavoritesController(key)),
        ],
      );
      final scoped = mount(child, key);
      await load(scoped);
      expect(root.current.channels.single.id, 'parent');
      expect(scoped.current.channels.single.id, 'child');
      expect(sibling.current.channels, isEmpty);
    },
  );
}
