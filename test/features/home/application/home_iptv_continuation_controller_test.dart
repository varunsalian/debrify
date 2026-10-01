import 'dart:async';

import 'package:debrify/features/home/application/home_iptv_continuation_controller.dart';
import 'package:debrify/features/home/application/home_continuation_providers.dart';
import 'package:debrify/features/home/models/home_continuation_session.dart';
import 'package:debrify/services/iptv_cw_history.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

HomeContinuationSession session() => HomeContinuationSession(
  owner: ProfileSessionMemory.captureOwner(),
  viewIdentity: Object(),
);
HomeIptvContinuationController mount(
  ProviderContainer container,
  HomeContinuationSession key,
) {
  container.listen(homeIptvContinuationProvider(key), (_, _) {});
  return container.read(homeIptvContinuationProvider(key).notifier);
}

List<Map<String, dynamic>> history(String id) => [
  {
    'url': 'https://fixture.invalid/$id',
    'name': id,
    'progress': 0.5,
    'positionMs': 60000.9,
    'durationMs': 180001.9,
  },
  {
    'seriesId': id,
    'playlistId': 'provider',
    'seriesName': 'Series $id',
    'season': 2,
    'episode': 5,
    'progress': 0.8,
  },
];
Future<void> load(HomeIptvContinuationController controller) =>
    controller.load(isCurrent: () => true, beforeRows: (_) {}, onRows: () {});

void main() {
  test(
    'projection preserves routing keys and publishes after focus allocation',
    () async {
      var reads = 0;
      final container = ProviderContainer.test(
        overrides: [
          homeIptvContinuationRepositoryProvider.overrideWithValue(
            IptvCwHistory(
              readHistory: () async {
                reads++;
                return history('new');
              },
            ),
          ),
        ],
      );
      final controller = mount(container, session());
      expect(reads, 0);
      final initial = controller.current;
      final order = <String>[];
      await controller.load(
        isCurrent: () => true,
        beforeRows: (next) {
          expect(controller.current, same(initial));
          expect(next.movies.single.id, 'https://fixture.invalid/new');
          expect(next.movies.single.imdbId, isNull);
          expect(next.series.single.id, 'xtream-series://provider/new');
          expect(next.series.single.type, 'series');
          order.add('focus');
        },
        onRows: () {
          expect(controller.current.movies.single.name, 'new');
          order.add('rows');
        },
      );
      expect(order, ['focus', 'rows']);
      expect(controller.current.progress['https://fixture.invalid/new'], 0.5);
      expect(
        controller.current.episode['xtream-series://provider/new'],
        'S2 · E5',
      );
      expect(
        controller.current.remainingMinutes['https://fixture.invalid/new'],
        3,
      );
      expect(
        controller
            .current
            .byKey['xtream-series://provider/new']!
            .raw['seriesId'],
        'new',
      );
      expect(initial.movies, isEmpty);
      expect(() => controller.current.movies.clear(), throwsUnsupportedError);
      expect(() => controller.current.byKey.clear(), throwsUnsupportedError);
    },
  );

  test(
    'newer load wins and failed refresh retains the accepted snapshot',
    () async {
      final pending = Completer<List<Map<String, dynamic>>>();
      var reads = 0;
      final error = StateError('fixture');
      final container = ProviderContainer.test(
        overrides: [
          homeIptvContinuationRepositoryProvider.overrideWithValue(
            IptvCwHistory(
              readHistory: () {
                reads++;
                if (reads == 1) return pending.future;
                if (reads == 2) return Future.value(history('new'));
                return Future.error(error);
              },
            ),
          ),
        ],
      );
      final controller = mount(container, session());
      var stale = 0;
      final old = controller.load(
        isCurrent: () => true,
        beforeRows: (_) => stale++,
        onRows: () => stale++,
      );
      await load(controller);
      final accepted = controller.current;
      pending.complete(history('old'));
      await old;
      expect(stale, 0);
      expect(controller.current, same(accepted));
      await expectLater(load(controller), throwsA(same(error)));
      expect(controller.current, same(accepted));
      expect(reads, 3);
    },
  );

  for (final reason in ['dispose', 'profile', 'recompute', 'view']) {
    test('$reason retires pending rows before UI callbacks', () async {
      final pending = Completer<List<Map<String, dynamic>>>();
      final container = ProviderContainer.test(
        overrides: [
          homeIptvContinuationRepositoryProvider.overrideWithValue(
            IptvCwHistory(readHistory: () => pending.future),
          ),
        ],
      );
      final key = session();
      final controller = mount(container, key);
      var visible = true;
      var callbacks = 0;
      final request = controller.load(
        isCurrent: () => visible,
        beforeRows: (_) => callbacks++,
        onRows: () => callbacks++,
      );
      switch (reason) {
        case 'dispose':
          container.dispose();
        case 'profile':
          ProfileSessionMemory.clearAll();
        case 'recompute':
          container.invalidate(homeIptvContinuationProvider(key));
          container.read(homeIptvContinuationProvider(key));
        case 'view':
          visible = false;
      }
      pending.complete(history('retired'));
      await request;
      expect(callbacks, 0);
      expect(controller.current.movies, isEmpty);
    });
  }

  test(
    'child overrides and sibling views own distinct accepted rows',
    () async {
      final key = session();
      final parent = ProviderContainer.test(
        overrides: [
          homeIptvContinuationRepositoryProvider.overrideWithValue(
            IptvCwHistory(readHistory: () async => history('parent')),
          ),
        ],
      );
      final root = mount(parent, key);
      await load(root);
      final sibling = mount(parent, session());
      for (final id in ['one', 'two']) {
        final child = ProviderContainer.test(
          parent: parent,
          overrides: [
            homeIptvContinuationRepositoryProvider.overrideWithValue(
              IptvCwHistory(readHistory: () async => history(id)),
            ),
            homeIptvContinuationProvider(
              key,
            ).overrideWith(() => HomeIptvContinuationController(key)),
          ],
        );
        final scoped = mount(child, key);
        await load(scoped);
        expect(scoped.current.movies.single.name, id);
        expect(root.current.movies.single.name, 'parent');
        expect(sibling.current.movies, isEmpty);
        child.dispose();
      }
    },
  );
}
