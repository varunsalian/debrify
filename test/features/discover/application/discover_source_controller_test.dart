import 'dart:async';
import 'package:debrify/features/discover/application/discover_source_controller.dart';
import 'package:debrify/features/discover/application/discover_providers.dart';
import 'package:debrify/features/discover/data/discover_source_repository.dart';
import 'package:debrify/features/discover/models/discover_source_state.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

StremioAddon addon(String id, {bool browsable = true}) => StremioAddon(
  id: id,
  name: id,
  baseUrl: 'https://fixture.invalid',
  manifestUrl: 'https://fixture.invalid/manifest.json',
  catalogs: browsable
      ? [
          const StremioAddonCatalog(
            id: 'catalog',
            type: 'movie',
            name: 'Catalog',
          ),
        ]
      : [],
);

void main() {
  late ProviderContainer container;
  late DiscoverSourceController controller;
  late DiscoverSourceSession key;
  late Completer<String?> configured;
  late Completer<List<StremioAddon>> inventory;
  final writes = <({String source, bool Function() current})>[];
  var reads = 0;
  var paints = 0;
  var metadataReads = 0;
  List<StremioAddon> hydrated = [];
  void mount({bool handoff = false, String last = 'cw'}) {
    configured = Completer<String?>();
    inventory = Completer<List<StremioAddon>>();
    writes.clear();
    reads = 0;
    paints = 0;
    metadataReads = 0;
    hydrated = [];
    key = (
      owner: ProfileSessionMemory.captureOwner(),
      viewIdentity: Object(),
      initialSource: handoff ? 'mdblist' : 'cw',
      hasHandoff: handoff,
    );
    container = ProviderContainer.test(
      overrides: [
        discoverSourceRepositoryProvider.overrideWith(
          (ref, session) => DiscoverSourceRepository(
            readDefault: () => configured.future,
            readLast: () async => last,
            readAddons: () {
              reads++;
              return inventory.future;
            },
            writeLast: (source, current) async {
              writes.add((source: source, current: current));
            },
          ),
        ),
      ],
    );
    container.listen(discoverSourceProvider(key), (_, _) {});
    controller = container.read(discoverSourceProvider(key).notifier);
  }

  Future<void> flush() => Future<void>.delayed(Duration.zero);
  Future<void> load({
    bool Function()? current,
    Future<bool> Function()? enabled,
    bool mdblist = true,
  }) => controller.load(
    isCurrent: current ?? () => true,
    mdblistEnabled: mdblist,
    discoveryEnabled:
        enabled ??
        () async {
          metadataReads++;
          return true;
        },
    onInventory: (all) => hydrated = all,
    onChanged: () => paints++,
  );
  bool select(
    String source, {
    bool discovery = true,
    void Function()? before,
  }) => controller.select(
    source,
    discoveryEnabled: discovery,
    isCurrent: () => true,
    beforeChange: before ?? () {},
    onChanged: () => paints++,
  );
  test(
    'fixed landing paints before addon hydration and keeps complete inventory',
    () async {
      mount();
      expect(reads, 0);
      expect(writes, isEmpty);
      final pending = load();
      configured.complete('trakt');
      await flush();
      expect(controller.current.source, 'trakt');
      expect(paints, 1);
      expect(reads, 1);
      expect(writes.single.source, 'trakt');
      expect(metadataReads, 0);
      final all = [addon('visible'), addon('hidden', browsable: false)];
      inventory.complete(all);
      await pending;
      expect(hydrated, all);
      expect(controller.current.addons.map((a) => a.id), ['visible']);
      expect(() => controller.current.addons.clear(), throwsUnsupportedError);
      all.clear();
      expect(controller.current.addons.length, 1);
      expect(hydrated.length, 2);
      expect(paints, 2);
      expect(writes.length, 1);
    },
  );
  for (final available in [true, false]) {
    test(
      'remembered addon waits for inventory; available=$available',
      () async {
        mount(last: 'a:chosen');
        final pending = load();
        configured.complete(null);
        await flush();
        expect(controller.current.source, 'cw');
        expect(writes, isEmpty);
        inventory.complete([addon(available ? 'chosen' : 'other')]);
        await pending;
        expect(controller.current.source, available ? 'a:chosen' : 'cw');
        expect(writes.single.source, controller.current.source);
      },
    );
  }
  test(
    'explicit choice beats late landing while addon hydration still completes',
    () async {
      mount();
      final pending = load();
      expect(select('simkl'), isTrue);
      configured.complete('trakt');
      await flush();
      inventory.complete([addon('visible')]);
      await pending;
      expect(controller.current.source, 'simkl');
      expect(controller.current.addons.length, 1);
      expect(writes.map((w) => w.source), ['simkl']);
    },
  );
  test(
    'Search handoff owns the initial source and persistence without build effects',
    () async {
      mount(handoff: true);
      expect(controller.current.source, 'mdblist');
      expect(writes, isEmpty);
      await controller.rememberCurrent(isCurrent: () => true);
      final pending = load();
      configured.complete('trakt');
      await flush();
      inventory.complete([addon('visible')]);
      await pending;
      expect(controller.current.source, 'mdblist');
      expect(writes.single.source, 'mdblist');
    },
  );
  test(
    'TMDB awaits policy and falls back before addon hydration when disabled',
    () async {
      mount();
      final policy = Completer<bool>();
      final pending = load(enabled: () => policy.future);
      configured.complete('tmdb');
      await flush();
      expect(reads, 0);
      policy.complete(false);
      await flush();
      expect(writes.single.source, 'cw');
      inventory.complete([]);
      await pending;
      expect(controller.current.source, 'cw');
      expect(select('tmdb', discovery: false), isFalse);
    },
  );
  test(
    'selection clears presentation before publication and retires older queued writes',
    () async {
      mount();
      await controller.rememberCurrent(isCurrent: () => true);
      expect(
        select('trakt', before: () => expect(controller.current.source, 'cw')),
        isTrue,
      );
      expect(controller.current.source, 'trakt');
      expect(writes.first.current(), isFalse);
      expect(writes.last.current(), isTrue);
      expect(select('trakt'), isFalse);
      expect(writes.length, 2);
    },
  );
  for (final reason in ['profile', 'view', 'dispose', 'recompute']) {
    test(
      '$reason retires pending inventory and queued startup persistence',
      () async {
        mount();
        var current = true;
        final pending = load(current: () => current);
        configured.complete('trakt');
        await flush();
        switch (reason) {
          case 'profile':
            ProfileSessionMemory.clearAll();
          case 'view':
            current = false;
          case 'dispose':
            container.dispose();
          case 'recompute':
            container.invalidate(discoverSourceProvider(key));
            container.read(discoverSourceProvider(key));
        }
        inventory.complete([addon('late')]);
        await pending;
        expect(controller.current.addons, isEmpty);
        expect(hydrated, isEmpty);
        expect(writes.single.current(), isFalse);
      },
    );
  }
  test(
    'failed addon read produces the existing missing-addon fallback',
    () async {
      mount();
      final pending = load();
      configured.complete('a:missing');
      await flush();
      inventory.completeError(StateError('manifest'));
      await pending;
      expect(controller.current.source, 'cw');
      expect(writes.single.source, 'cw');
    },
  );
  test(
    'preference failure propagates without reading addons or changing state',
    () async {
      mount();
      final pending = load();
      configured.completeError(StateError('preferences'));
      await expectLater(pending, throwsStateError);
      expect(reads, 0);
      expect(writes, isEmpty);
      expect(paints, 0);
    },
  );
  test(
    'overlapping startup loads retire the older preference continuation',
    () async {
      mount();
      final older = load();
      final newer = load();
      configured.complete('trakt');
      await flush();
      expect(reads, 1);
      inventory.complete([addon('visible')]);
      await Future.wait([older, newer]);
      expect(paints, 2);
      expect(writes.map((write) => write.source), ['trakt']);
      expect(controller.current.addons.length, 1);
    },
  );
  test(
    'recomputation retains the accepted source and inventory without replay',
    () async {
      mount();
      final pending = load();
      configured.complete('a:visible');
      await flush();
      inventory.complete([addon('visible')]);
      await pending;
      final accepted = controller.current;
      final priorPaints = paints;
      container.invalidate(discoverSourceProvider(key));
      expect(container.read(discoverSourceProvider(key)), same(accepted));
      expect(reads, 1);
      expect(writes.length, 1);
      expect(paints, priorPaints);
    },
  );
}
