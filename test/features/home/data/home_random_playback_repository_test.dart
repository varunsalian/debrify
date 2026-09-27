import 'dart:async';

import 'package:debrify/features/home/data/home_random_episode_selector.dart';
import 'package:debrify/features/home/data/home_random_playback_repository.dart';
import 'package:debrify/features/home/models/home_random_playback_preparation.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:flutter_test/flutter_test.dart';

StremioAddon source(
  String id, {
  String base = 'https://fixture.invalid',
  bool meta = true,
}) => StremioAddon(
  id: id,
  name: id,
  baseUrl: base,
  manifestUrl: '$base/manifest.json',
  resources: meta ? ['meta'] : [],
  addedAt: DateTime.utc(2026),
);
const title = StremioMeta(
  id: 'tmdb:series:123',
  imdbId: 'tt123',
  type: 'series',
  name: 'Title',
);
final videos = <Map<String, dynamic>>[
  {'season': 2, 'number': 3},
];

class PreparationHarness {
  final calls = <String>[];
  final errors = <Object>[];
  final native = source('builtin', base: '', meta: false);
  bool current = true, ownerCurrent = true;
  List<Map<String, dynamic>>? inventory;
  bool Function()? commitGuard;
  Future<List<StremioAddon>> Function() read = () async => [];
  Future<List<Map<String, dynamic>>?> Function() fetch = () async => videos;
  Future<void> Function() record = () async {};
  late final repository = HomeRandomPlaybackRepository(
    nativeAddon: native,
    readAddons: () {
      calls.add('addons');
      return read();
    },
    fetchEpisodes: (addon, id) {
      calls.add('fetch:${addon.id}:$id');
      return fetch();
    },
    recordInventory: (id, name, raw, guard) {
      calls.add('record:$id:$name');
      inventory = raw;
      commitGuard = guard;
      return record();
    },
    selector: HomeRandomEpisodeSelector(
      videoIdFor: StremioService.randomEpisodeVideoId,
      isCanonicalEpisode: StremioService.isCanonicalEpisodeId,
      chooseIndex: (_) {
        calls.add('select');
        return 0;
      },
    ),
    isOwnerCurrent: () => ownerCurrent,
    onInventoryError: (error, _) => errors.add(error),
  );
  Future<HomeRandomPlaybackPreparation> run({
    StremioMeta item = title,
    StremioAddon? addon,
    String? id = 'tt123',
    bool continuous = false,
  }) => repository.prepare(
    item: item,
    addon: addon ?? source('origin'),
    progressId: id,
    continuous: continuous,
    isCurrent: () => current,
  );
}

void main() {
  test(
    'preferred metadata preserves catalog ID and starts recording before selection',
    () async {
      final h = PreparationHarness();
      final result = await h.run(continuous: true);
      expect(h.calls, [
        'fetch:origin:tmdb:series:123',
        'record:tt123:Title',
        'select',
      ]);
      expect(h.inventory, same(videos));
      expect(result.status, HomeRandomPlaybackStatus.ready);
      expect(result.selection!.initialContinuousShuffle, isTrue);
      expect((result.selection!.season, result.selection!.episode), (2, 3));
    },
  );

  test(
    'fallback picks first enabled usable metadata addon and changes content identity',
    () async {
      final h = PreparationHarness();
      h.read = () async => [
        source('no-meta', meta: false),
        source('empty', base: ''),
        source('first'),
        source('second'),
      ];
      final result = await h.run(addon: source('origin', meta: false));
      expect(result.status, HomeRandomPlaybackStatus.ready);
      expect(h.calls, [
        'addons',
        'fetch:first:tt123',
        'record:tt123:Title',
        'select',
      ]);
    },
  );

  test(
    'built-in preferred addon bypasses enabled-addons even without URL or meta resource',
    () async {
      final h = PreparationHarness();
      await h.run(addon: h.native);
      expect(h.calls.first, 'fetch:builtin:tmdb:series:123');
      expect(h.calls, isNot(contains('addons')));
    },
  );

  test(
    'native title without origin URL uses built-in metadata directly',
    () async {
      final h = PreparationHarness();
      const item = StremioMeta(id: 'tmdb:123', type: 'series', name: 'Native');
      final result = await h.run(
        item: item,
        addon: source('empty', base: '', meta: false),
        id: 'tmdb:123',
      );
      expect(h.calls.first, 'fetch:builtin:tmdb:123');
      expect(h.calls, isNot(contains('addons')));
      expect(result.status, HomeRandomPlaybackStatus.ready);
    },
  );

  test(
    'missing addon or null metadata is empty without inventory writes',
    () async {
      final missing = PreparationHarness();
      expect(
        (await missing.run(addon: source('none', meta: false))).status,
        HomeRandomPlaybackStatus.noEpisodes,
      );
      expect(missing.calls, ['addons']);
      final noMeta = PreparationHarness()..fetch = () async => null;
      expect((await noMeta.run()).status, HomeRandomPlaybackStatus.noEpisodes);
      expect(noMeta.calls, ['fetch:origin:tmdb:series:123']);
    },
  );

  test(
    'empty inventory is recorded while missing progress ID skips recording',
    () async {
      final empty = PreparationHarness()..fetch = () async => [];
      expect((await empty.run()).status, HomeRandomPlaybackStatus.noEpisodes);
      expect(empty.calls, [
        'fetch:origin:tmdb:series:123',
        'record:tt123:Title',
      ]);
      final unknown = PreparationHarness()
        ..fetch = () async => [
          {'season': 1, 'number': 1, 'id': 'custom'},
        ];
      expect(
        (await unknown.run(id: null)).status,
        HomeRandomPlaybackStatus.ready,
      );
      expect(unknown.calls, ['fetch:origin:tmdb:series:123', 'select']);
    },
  );

  test(
    'metadata errors become load failures but addon discovery errors retain propagation',
    () async {
      final error = StateError('network');
      final fetch = PreparationHarness()..fetch = () async => throw error;
      expect((await fetch.run()).status, HomeRandomPlaybackStatus.loadFailed);
      expect(fetch.calls, ['fetch:origin:tmdb:series:123']);
      final read = PreparationHarness()..read = () async => throw error;
      await expectLater(
        read.run(addon: source('none', meta: false)),
        throwsA(same(error)),
      );
    },
  );

  test(
    'inventory recording does not delay selection and asynchronous failure is observed',
    () async {
      final wait = Completer<void>();
      final h = PreparationHarness()..record = () => wait.future;
      final result = await h.run();
      expect(result.status, HomeRandomPlaybackStatus.ready);
      expect(wait.isCompleted, isFalse);
      final error = StateError('disk');
      wait.completeError(error);
      await pumpEventQueue();
      expect(h.errors, [same(error)]);
    },
  );

  for (final owner in [false, true]) {
    test(
      'retired ${owner ? 'owner' : 'view'} stops before IO and after addon discovery',
      () async {
        final h = PreparationHarness();
        void retire() {
          if (owner) {
            h.ownerCurrent = false;
          } else {
            h.current = false;
          }
        }

        final wait = Completer<List<StremioAddon>>();
        h.read = () => wait.future;
        final pending = h.run(addon: source('none', meta: false));
        expect(h.calls, ['addons']);
        retire();
        wait.complete([source('fallback')]);
        expect((await pending).status, HomeRandomPlaybackStatus.retired);
        expect((await h.run()).status, HomeRandomPlaybackStatus.retired);
        expect(h.calls, ['addons']);
      },
    );
  }

  for (final fails in [false, true]) {
    test(
      'retirement during metadata ${fails ? 'failure' : 'success'} suppresses writes and selection',
      () async {
        final wait = Completer<List<Map<String, dynamic>>?>();
        final h = PreparationHarness()..fetch = () => wait.future;
        final pending = h.run();
        await pumpEventQueue();
        h.current = false;
        if (fails) {
          wait.completeError(StateError('network'));
        } else {
          wait.complete(videos);
        }
        expect((await pending).status, HomeRandomPlaybackStatus.retired);
        expect(h.calls, ['fetch:origin:tmdb:series:123']);
      },
    );
  }

  test('queued inventory keeps a live guard after a ready result', () async {
    final h = PreparationHarness();
    await h.run();
    expect(h.commitGuard!(), isTrue);
    h.current = false;
    expect(h.commitGuard!(), isFalse);
    h.current = true;
    h.ownerCurrent = false;
    expect(h.commitGuard!(), isFalse);
  });

  test(
    'overlapping active actions prepare independently without a competing latch',
    () async {
      final first = Completer<List<Map<String, dynamic>>?>();
      final second = Completer<List<Map<String, dynamic>>?>();
      var reads = 0;
      final h = PreparationHarness()
        ..fetch = () => reads++ == 0 ? first.future : second.future;
      final a = h.run(), b = h.run();
      await pumpEventQueue();
      second.complete(videos);
      expect((await b).status, HomeRandomPlaybackStatus.ready);
      first.complete(videos);
      expect((await a).status, HomeRandomPlaybackStatus.ready);
      expect(h.calls.where((e) => e == 'select'), hasLength(2));
    },
  );
}
