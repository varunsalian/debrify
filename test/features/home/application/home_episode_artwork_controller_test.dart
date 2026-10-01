import 'dart:async';
import 'package:debrify/features/home/application/home_episode_artwork_controller.dart';
import 'package:debrify/features/home/application/home_continuation_providers.dart';
import 'package:debrify/features/home/data/home_episode_artwork_repository.dart';
import 'package:debrify/features/home/models/home_catalog_session.dart';
import 'package:debrify/features/home/models/home_episode_artwork.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const local = HomeEpisodeArtworkSource.local;
  const trakt = HomeEpisodeArtworkSource.trakt;
  late ProviderContainer container;
  late HomeCatalogSession key;
  late HomeEpisodeArtworkController controller;
  final pending = <Completer<String?>>[];
  final episodes = <int>[];
  setUp(() {
    pending.clear();
    episodes.clear();
    key = HomeCatalogSession(
      owner: ProfileSessionMemory.captureOwner(),
      viewIdentity: Object(),
    );
    container = ProviderContainer.test(
      overrides: [
        homeEpisodeArtworkRepositoryProvider.overrideWith(
          (ref, session) => HomeEpisodeArtworkRepository(({
            required imdbId,
            required season,
            required episode,
          }) {
            final response = Completer<String?>();
            episodes.add(episode);
            pending.add(response);
            return response.future;
          }),
        ),
      ],
    );
    container.listen(homeEpisodeArtworkProvider(key), (_, _) {});
    controller = container.read(homeEpisodeArtworkProvider(key).notifier);
  });
  Future<void> load({
    HomeEpisodeArtworkSource source = local,
    int episode = 1,
    bool Function()? current,
    void Function()? changed,
  }) => controller.load(
    source: source,
    refs: {'id': (season: 1, episode: episode)},
    isCurrent: current ?? () => true,
    onChanged: changed ?? () {},
  );
  test(
    'read-free construction; immutable accepted stills survive empty results',
    () async {
      expect(pending, isEmpty);
      var effects = 0;
      final first = load(changed: () => effects++);
      pending.single.complete('first');
      await first;
      final accepted = controller.current;
      expect(accepted[local], {'id': 'first'});
      expect(() => accepted.clear(), throwsUnsupportedError);
      expect(() => accepted[local]!.clear(), throwsUnsupportedError);
      final second = load(changed: () => fail('empty repaint'));
      pending.last.complete(null);
      await second;
      expect(controller.current, same(accepted));
      controller.clear(local);
      expect(controller.current, isEmpty);
      expect(accepted[local], {'id': 'first'});
      expect(effects, 1);
    },
  );
  test(
    'new episodes supersede older reads without cancelling another shelf',
    () async {
      final older = load(changed: () => fail('old repaint'));
      final other = load(source: trakt);
      final newer = load(episode: 2);
      pending[2].complete('new');
      await newer;
      pending[1].complete('trakt');
      await other;
      pending[0].complete('old');
      await older;
      expect(controller.current, {
        local: {'id': 'new'},
        trakt: {'id': 'trakt'},
      });
    },
  );
  test(
    'settings refresh clears first, retains captured refs and retires older batches',
    () async {
      final refs = {'id': (season: 1, episode: 3)};
      final older = controller.load(
        source: local,
        refs: refs,
        isCurrent: () => true,
        onChanged: () => fail('old repaint'),
      );
      refs['id'] = (season: 1, episode: 99);
      var effects = 0;
      controller.refresh(isCurrent: () => true, onChanged: () => effects++);
      expect(controller.current, isEmpty);
      expect(effects, 1);
      expect(episodes, [3, 3]);
      pending[0].complete('old');
      await older;
      expect(controller.current, isEmpty);
      pending[1].complete('refreshed');
      await Future<void>.delayed(Duration.zero);
      expect(controller.current[local], {'id': 'refreshed'});
      expect(effects, 2);
    },
  );
  test(
    'settings refresh clears stale shelves without reloading them',
    () async {
      var active = true;
      final first = load(current: () => active);
      pending.single.complete('first');
      await first;
      active = false;
      controller.refresh(isCurrent: () => true, onChanged: () {});
      expect(controller.current, isEmpty);
      expect(pending.length, 1);
    },
  );
  for (final reason in ['profile', 'view', 'dispose', 'recompute', 'clear']) {
    test('$reason prevents pending artwork publication', () async {
      var current = true;
      final first = load(
        current: () => current,
        changed: () => fail('retired repaint'),
      );
      switch (reason) {
        case 'profile':
          ProfileSessionMemory.clearAll();
        case 'view':
          current = false;
        case 'dispose':
          container.dispose();
        case 'recompute':
          container.invalidate(homeEpisodeArtworkProvider(key));
          container.read(homeEpisodeArtworkProvider(key));
        case 'clear':
          controller.clear(local);
      }
      pending.single.complete('old');
      await first;
      expect(controller.current, isEmpty);
    });
  }
  test(
    'publication callback cannot act after ownership changes in a listener',
    () async {
      container.listen(
        homeEpisodeArtworkProvider(key),
        (_, _) => ProfileSessionMemory.clearAll(),
      );
      final first = load(changed: () => fail('retired effect'));
      pending.single.complete('first');
      await first;
    },
  );
  test('recomputation keeps accepted stills without resolving again', () async {
    final first = load();
    pending.single.complete('first');
    await first;
    container.invalidate(homeEpisodeArtworkProvider(key));
    expect(container.read(homeEpisodeArtworkProvider(key))[local], {
      'id': 'first',
    });
    expect(pending.length, 1);
  });
}
