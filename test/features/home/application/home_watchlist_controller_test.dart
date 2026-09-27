import 'dart:async';
import 'package:debrify/features/home/application/home_watchlist_controller.dart';
import 'package:debrify/features/home/application/home_watchlist_dependencies.dart';
import 'package:debrify/features/home/models/home_favorites_session.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

StremioMeta item(String id, {String type = 'movie'}) =>
    StremioMeta(id: id, type: type, name: id);
HomeFavoritesSession session() =>
    (owner: ProfileSessionMemory.captureOwner(), viewIdentity: Object());
HomeWatchlistController mount(ProviderContainer c, HomeFavoritesSession key) {
  c.listen(homeWatchlistProvider(key), (_, _) {});
  return c.read(homeWatchlistProvider(key).notifier);
}

Future<void> load(
  HomeWatchlistController c, {
  bool Function()? current,
  void Function()? rows,
}) => c.load(isCurrent: current ?? () => true, onRows: rows ?? () {});

void main() {
  test(
    'read-free construction, grouped publication before effects, failure retention and empty refresh',
    () async {
      var reads = 0;
      var failed = false;
      var empty = false;
      final movie = item('m');
      final series = item('s', type: 'SERIES');
      final c = ProviderContainer.test(
        overrides: [
          homeWatchlistReaderProvider.overrideWithValue(() async {
            reads++;
            if (failed) throw StateError('storage');
            return empty ? [] : [series, movie];
          }),
        ],
      );
      final controller = mount(c, session());
      expect(reads, 0);
      await load(
        controller,
        rows: () {
          expect(controller.current.movies.single, same(movie));
          expect(controller.current.series.single, same(series));
        },
      );
      final accepted = controller.current;
      failed = true;
      await load(controller, rows: () => fail('failed read published'));
      expect(controller.current, same(accepted));
      failed = false;
      empty = true;
      var effects = 0;
      await load(controller, rows: () => effects++);
      expect(controller.current.movies, isEmpty);
      expect(controller.current.series, isEmpty);
      expect(effects, 1);
      expect(reads, 3);
    },
  );

  test('newer load wins across both movie and series rows', () async {
    final pending = Completer<List<StremioMeta>>();
    var reads = 0;
    final c = ProviderContainer.test(
      overrides: [
        homeWatchlistReaderProvider.overrideWithValue(
          () => ++reads == 1
              ? pending.future
              : Future.value([item('new', type: 'series')]),
        ),
      ],
    );
    final controller = mount(c, session());
    final old = load(controller, rows: () => fail('old repaint'));
    await load(controller);
    pending.complete([item('old')]);
    await old;
    expect(controller.current.movies, isEmpty);
    expect(controller.current.series.single.id, 'new');
  });

  for (final reason in ['profile', 'dispose', 'view', 'recompute']) {
    test('$reason during read rejects rows and effects', () async {
      final pending = Completer<List<StremioMeta>>();
      final c = ProviderContainer.test(
        overrides: [
          homeWatchlistReaderProvider.overrideWithValue(() => pending.future),
        ],
      );
      final key = session();
      final controller = mount(c, key);
      var active = true;
      final request = load(
        controller,
        current: () => active,
        rows: () => fail('retired repaint'),
      );
      switch (reason) {
        case 'profile':
          ProfileSessionMemory.clearAll();
        case 'dispose':
          c.dispose();
        case 'view':
          active = false;
        case 'recompute':
          c.invalidate(homeWatchlistProvider(key));
          c.read(homeWatchlistProvider(key));
      }
      pending.complete([item('late')]);
      await request;
      expect(controller.current.movies, isEmpty);
      expect(controller.current.series, isEmpty);
    });
  }

  test(
    'nested reader override and sibling views keep separate state',
    () async {
      final key = session();
      final parent = ProviderContainer.test(
        overrides: [
          homeWatchlistReaderProvider.overrideWithValue(
            () async => [item('parent')],
          ),
        ],
      );
      final root = mount(parent, key);
      await load(root);
      final sibling = mount(parent, session());
      final child = ProviderContainer.test(
        parent: parent,
        overrides: [
          homeWatchlistReaderProvider.overrideWithValue(
            () async => [item('child')],
          ),
          homeWatchlistProvider(
            key,
          ).overrideWith(() => HomeWatchlistController(key)),
        ],
      );
      final scoped = mount(child, key);
      await load(scoped);
      expect(root.current.movies.single.id, 'parent');
      expect(scoped.current.movies.single.id, 'child');
      expect(sibling.current.movies, isEmpty);
    },
  );
}
