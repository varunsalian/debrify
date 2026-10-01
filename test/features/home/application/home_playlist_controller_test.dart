import 'dart:async';
import 'package:debrify/features/home/application/home_playlist_controller.dart';
import 'package:debrify/features/home/application/home_saved_content_providers.dart';
import 'package:debrify/features/home/models/home_favorites_session.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../fixtures/playlist_fixture.dart';

HomeFavoritesSession session() =>
    (owner: ProfileSessionMemory.captureOwner(), viewIdentity: Object());
HomePlaylistController mount(ProviderContainer c, HomeFavoritesSession key) {
  c.listen(homePlaylistProvider(key), (_, _) {});
  return c.read(homePlaylistProvider(key).notifier);
}

Future<void> load(
  HomePlaylistController c, {
  bool Function()? current,
  void Function()? rows,
}) => c.load(isCurrent: current ?? () => true, onRows: rows ?? () {});

void main() {
  test(
    'read-free construction; coherent publication; failure retains all fields; empty succeeds',
    () async {
      var reads = 0;
      var failed = false;
      var empty = false;
      final c = ProviderContainer.test(
        overrides: [
          homePlaylistRepositoryProvider.overrideWithValue(
            repository(
              items: () async {
                reads++;
                if (failed) throw StateError('storage');
                return empty ? [] : [playlistItem('a')];
              },
              favorites: () async => {'play:a'},
              posters: () async => {'poster:a': 'poster'},
              progress: (_) async => {
                'play:a': {'positionMs': 50, 'durationMs': 100},
              },
            ),
          ),
        ],
      );
      final controller = mount(c, session());
      expect(reads, 0);
      await load(
        controller,
        rows: () {
          final row = controller.current.items.single;
          expect(row.posterUrl, 'poster');
          expect(controller.current.isFavorite(row), isTrue);
          expect(controller.current.progressFor(row), 0.5);
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
      expect(controller.current.items, isEmpty);
      expect(effects, 1);
      expect(reads, 3);
    },
  );

  test(
    'newest refresh owns items and progress even when older progress completes last',
    () async {
      final pending = Completer<Map<String, Map<String, dynamic>>>();
      final entered = Completer<void>();
      var reads = 0;
      final c = ProviderContainer.test(
        overrides: [
          homePlaylistRepositoryProvider.overrideWithValue(
            repository(
              items: () async => [playlistItem(++reads == 1 ? 'old' : 'new')],
              progress: (items) {
                if (items.single['id'] == 'old') {
                  entered.complete();
                  return pending.future;
                }
                return Future.value({});
              },
            ),
          ),
        ],
      );
      final controller = mount(c, session());
      final old = load(controller, rows: () => fail('old repaint'));
      await entered.future;
      await load(controller);
      pending.complete({
        'play:old': {'positionMs': 1, 'durationMs': 2},
      });
      await old;
      expect(controller.current.items.single.dedupeKey, 'play:new');
      expect(controller.current.progress, isEmpty);
    },
  );

  for (final reason in ['profile', 'dispose', 'view', 'recompute']) {
    test(
      '$reason during initial reads prevents progress access and publication',
      () async {
        final pending = Completer<PlaylistRows>();
        var progressReads = 0;
        final c = ProviderContainer.test(
          overrides: [
            homePlaylistRepositoryProvider.overrideWithValue(
              repository(
                items: () => pending.future,
                progress: (_) async {
                  progressReads++;
                  return {};
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
            c.invalidate(homePlaylistProvider(key));
            c.read(homePlaylistProvider(key));
        }
        pending.complete([playlistItem('late')]);
        await request;
        expect(progressReads, 0);
        expect(controller.current.items, isEmpty);
      },
    );
  }

  test('nested repository override and sibling views isolate state', () async {
    final key = session();
    final parent = ProviderContainer.test(
      overrides: [
        homePlaylistRepositoryProvider.overrideWithValue(
          repository(items: () async => [playlistItem('parent')]),
        ),
      ],
    );
    final root = mount(parent, key);
    await load(root);
    final sibling = mount(parent, session());
    final child = ProviderContainer.test(
      parent: parent,
      overrides: [
        homePlaylistRepositoryProvider.overrideWithValue(
          repository(items: () async => [playlistItem('child')]),
        ),
        homePlaylistProvider(
          key,
        ).overrideWith(() => HomePlaylistController(key)),
      ],
    );
    final scoped = mount(child, key);
    await load(scoped);
    expect(root.current.items.single.title, 'parent');
    expect(scoped.current.items.single.title, 'child');
    expect(sibling.current.items, isEmpty);
  });
}
