import 'dart:async';
import 'package:debrify/features/home/application/home_iptv_favorites_controller.dart';
import 'package:debrify/features/home/application/home_iptv_favorites_dependencies.dart';
import 'package:debrify/features/home/data/home_iptv_favorites_repository.dart';
import 'package:debrify/features/home/models/home_favorites_session.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

typedef Saved = Map<String, Map<String, dynamic>>;
Saved saved(String url) => {
  url: {'name': 'One'},
};
HomeFavoritesSession session() =>
    (owner: ProfileSessionMemory.captureOwner(), viewIdentity: Object());
HomeIptvFavoritesRepository repository(Future<Saved> Function() read) =>
    HomeIptvFavoritesRepository(
      favorites: read,
      headers: StorageService.iptvFavoriteHeaders,
    );
HomeIptvFavoritesController mount(
  ProviderContainer c,
  HomeFavoritesSession key,
) {
  c.listen(homeIptvFavoritesProvider(key), (_, _) {});
  return c.read(homeIptvFavoritesProvider(key).notifier);
}

Future<void> load(
  HomeIptvFavoritesController c, {
  bool Function()? current,
  void Function(bool)? rows,
}) => c.load(isCurrent: current ?? () => true, onRows: rows ?? (_) {});

void main() {
  test(
    'read-free construction; publish before focus; failed reads retain rows; empty clears',
    () async {
      var reads = 0;
      var failure = false;
      var empty = false;
      final c = ProviderContainer.test(
        overrides: [
          homeIptvFavoritesRepositoryProvider.overrideWithValue(
            repository(() async {
              reads++;
              if (failure) throw StateError('store');
              return empty ? {} : saved('url:a');
            }),
          ),
        ],
      );
      final controller = mount(c, session());
      expect(reads, 0);
      expect(controller.current, isEmpty);
      await load(
        controller,
        rows: (hasRows) {
          expect(hasRows, isTrue);
          expect(controller.current.single.url, 'url:a');
        },
      );
      final accepted = controller.current;
      failure = true;
      await load(controller, rows: (_) => fail('failed read published'));
      expect(controller.current, same(accepted));
      failure = false;
      empty = true;
      await load(controller, rows: (hasRows) => expect(hasRows, isFalse));
      expect(controller.current, isEmpty);
      expect(reads, 3);
    },
  );

  test('older completion cannot overwrite a newer accepted refresh', () async {
    final pending = Completer<Saved>();
    var reads = 0;
    final c = ProviderContainer.test(
      overrides: [
        homeIptvFavoritesRepositoryProvider.overrideWithValue(
          repository(
            () => ++reads == 1 ? pending.future : Future.value(saved('new')),
          ),
        ),
      ],
    );
    final controller = mount(c, session());
    final old = load(controller, rows: (_) => fail('old response published'));
    await load(controller);
    pending.complete(saved('old'));
    await old;
    expect(controller.current.single.url, 'new');
  });

  for (final reason in ['profile', 'dispose', 'view', 'recompute']) {
    test('$reason during read rejects publication and effects', () async {
      final pending = Completer<Saved>();
      final c = ProviderContainer.test(
        overrides: [
          homeIptvFavoritesRepositoryProvider.overrideWithValue(
            repository(() => pending.future),
          ),
        ],
      );
      final key = session();
      final controller = mount(c, key);
      var active = true;
      final request = load(
        controller,
        current: () => active,
        rows: (_) => fail('retired response published'),
      );
      switch (reason) {
        case 'profile':
          ProfileSessionMemory.clearAll();
        case 'dispose':
          c.dispose();
        case 'view':
          active = false;
        case 'recompute':
          c.invalidate(homeIptvFavoritesProvider(key));
          c.read(homeIptvFavoritesProvider(key));
      }
      pending.complete(saved('a'));
      await request;
      expect(controller.current, isEmpty);
    });
  }

  test(
    'nested dependency override and sibling view isolate accepted rows',
    () async {
      final key = session();
      final parent = ProviderContainer.test(
        overrides: [
          homeIptvFavoritesRepositoryProvider.overrideWithValue(
            repository(() async => saved('parent')),
          ),
        ],
      );
      final root = mount(parent, key);
      await load(root);
      final sibling = mount(parent, session());
      final child = ProviderContainer.test(
        parent: parent,
        overrides: [
          homeIptvFavoritesRepositoryProvider.overrideWithValue(
            repository(() async => saved('child')),
          ),
          homeIptvFavoritesProvider(
            key,
          ).overrideWith(() => HomeIptvFavoritesController(key)),
        ],
      );
      final scoped = mount(child, key);
      await load(scoped);
      expect(root.current.single.url, 'parent');
      expect(scoped.current.single.url, 'child');
      expect(sibling.current, isEmpty);
    },
  );
}
