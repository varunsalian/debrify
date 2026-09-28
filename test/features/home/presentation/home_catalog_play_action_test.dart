import 'dart:async';

import 'package:debrify/features/home/data/home_catalog_episode_identity.dart';
import 'package:debrify/features/home/data/home_catalog_origin_repository.dart';
import 'package:debrify/features/home/data/home_catalog_playback_resolver.dart';
import 'package:debrify/features/home/data/home_tracking_policy_repository.dart';
import 'package:debrify/features/home/models/home_catalog_origin.dart';
import 'package:debrify/features/home/models/home_series_resume_signals.dart';
import 'package:debrify/features/home/presentation/home_catalog_play_action.dart';
import 'package:debrify/features/home/presentation/home_playback_artwork.dart';
import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/models/trakt_continue_watching_item.dart';
import 'package:debrify/services/native_series_metadata_service.dart';
import 'package:debrify/services/tracking_source_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const item = StremioMeta(
  id: 'tt123',
  name: 'Fixture',
  type: 'series',
  year: '2020',
);
const selection = AdvancedSearchSelection(
  imdbId: 'tt123',
  isSeries: true,
  title: 'Fixture',
  season: 2,
  episode: 3,
  traktProgressPercent: 42,
);
const promise = (started: true, season: 2, episode: 3);
final addon = NativeSeriesMetadataService.addon;
const policy = TrackingSourcePolicy(
  scrobbleTargets: {},
  progressSource: WatchProgressSource.smart,
  homeTickSources: {},
);

class Origin extends Fake implements HomeCatalogOriginRepository {
  Origin(this.h);
  final Harness h;
  @override
  Future<HomeCatalogOrigin> prepare(
    StremioMeta value,
    StremioAddon source, {
    required bool Function() isCurrent,
  }) async {
    expect(value, same(item));
    expect(source, same(addon));
    await h.step('origin');
    return switch (h.scenario) {
      'unverified' => const HomeCatalogOrigin.unverified(item),
      'unavailable' => const HomeCatalogOrigin.unavailable(item),
      _ => HomeCatalogOrigin.ready(item, addon),
    };
  }
}

class Policies extends Fake implements HomeTrackingPolicyRepository {
  Policies(this.h);
  final Harness h;
  @override
  Future<TrackingSourcePolicy?> loadForContent(
    String? id, {
    required bool Function() isCurrent,
  }) async {
    expect(id, item.progressId);
    await h.step('policy');
    return policy;
  }
}

class Targets extends Fake implements HomeCatalogPlaybackResolver {
  Targets(this.h);
  final Harness h;
  @override
  Future<HomeCatalogPlaybackTarget?> resolve(
    StremioMeta value,
    StremioAddon source, {
    required TrackingSourcePolicy trackingPolicy,
    required HomeResumeAvailability Function() availability,
    required TraktContinueWatchingItem? Function() cachedTrakt,
    required bool Function() isCurrent,
    bool isTraktSource = false,
    bool isMdblistSource = false,
    bool startFromBeginning = false,
    bool skipEpisodeFallback = false,
    bool preferTraktResume = false,
    ({bool started, int season, int episode})? promisedTarget,
  }) async {
    expect(value, same(item));
    expect(source, same(addon));
    expect(trackingPolicy, same(policy));
    expect(availability(), (trakt: true, simkl: false, mdblist: true));
    expect(cachedTrakt(), isNull);
    expect(isTraktSource, isTrue);
    expect(isMdblistSource, isTrue);
    expect(startFromBeginning, isTrue);
    expect(skipEpisodeFallback, isTrue);
    expect(preferTraktResume, h.scenario != 'no-loader');
    expect(promisedTarget, promise);
    await h.step('target');
    if (h.scenario == 'null-target') return null;
    return h.scenario == 'episodes'
        ? const HomeCatalogPlaybackTarget.episodes()
        : const HomeCatalogPlaybackTarget.play(selection);
  }
}

class Identity extends Fake implements HomeCatalogEpisodeIdentity {
  Identity(this.h);
  final Harness h;
  @override
  Future<AdvancedSearchSelection?> resolve(
    AdvancedSearchSelection value,
    StremioMeta catalog,
    StremioAddon source, {
    required bool Function() isCurrent,
  }) async {
    expect(value, same(selection));
    expect(catalog, same(item));
    expect(source, same(addon));
    await h.step('identity');
    return h.scenario == 'null-identity' ? null : selection;
  }
}

class Harness {
  Harness(this.scenario);
  final String scenario;
  final events = <String>[];
  final messages = <String>[];
  bool current = true;
  VoidCallback? cancel;
  Future<void> Function(String)? afterStep;
  late BuildContext context;
  final error = StateError('fixture failure');
  Future<void> step(String phase) async {
    events.add(phase);
    await Future<void>.value();
    await afterStep?.call(phase);
    if (scenario == 'retire-$phase') current = false;
    if (scenario == 'cancel-$phase') cancel!();
    if (scenario == 'throw-$phase') throw error;
  }

  Future<void> mount(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (value) {
          context = value;
          return const SizedBox();
        },
      ),
    ),
  );
  void checkLaunch(
    AdvancedSearchSelection value,
    String id,
    StremioMeta catalog,
  ) {
    expect(value, same(selection));
    expect(id, addon.id);
    expect(catalog.id, item.id);
    expect(catalog.sourceAddon, same(addon));
  }

  Future<void> run() =>
      HomeCatalogPlayAction(
        origin: Origin(this),
        policies: Policies(this),
        targets: Targets(this),
        identity: Identity(this),
        artwork: HomePlaybackArtwork(),
        log: (_) {},
        showLoader:
            (context, {required meta, required title, required onCancel}) {
              events.add('loader');
              expect(title, item.name);
              expect(meta.imdbId, item.progressId);
              expect(meta.addonId, addon.id);
              cancel = onCancel;
              return () => events.add('dismiss');
            },
      ).run(
        context,
        item,
        addon,
        isCurrent: () => current,
        availability: () => (trakt: true, simkl: false, mdblist: true),
        cachedTrakt: (value) {
          expect(value, same(item));
          return null;
        },
        showMessage: messages.add,
        activateAddon: (id) {
          expect(id, addon.id);
          events.add('activate');
        },
        openEpisodes:
            (
              value,
              source, {
              required isTraktSource,
              required isMdblistSource,
            }) {
              expect(value, same(item));
              expect(source, same(addon));
              expect(isTraktSource && isMdblistSource, isTrue);
              events.add('episodes');
            },
        browse: (value, {required metadataAddonId, required catalogItem}) {
          checkLaunch(value, metadataAddonId, catalogItem);
          events.add('browse');
        },
        play: (value, {required metadataAddonId, required catalogItem}) {
          checkLaunch(value, metadataAddonId, catalogItem);
          return step('play');
        },
        isTraktSource: true,
        isMdblistSource: true,
        startFromBeginning: true,
        skipEpisodeFallback: true,
        preferTraktResume: scenario != 'no-loader',
        promisedTarget: promise,
        browseSourcesOnly: scenario == 'browse',
      );
}

void main() {
  testWidgets('player handoff stays awaited after the loader is dismissed', (
    tester,
  ) async {
    final h = Harness('play');
    final entered = Completer<void>(), release = Completer<void>();
    h.afterStep = (phase) async {
      if (phase == 'play') {
        entered.complete();
        await release.future;
      }
    };
    await h.mount(tester);
    var completed = false;
    final pending = h.run().then((_) => completed = true);
    await entered.future;
    expect(completed, isFalse);
    expect(h.events.where((e) => e == 'dismiss').length, 1);
    release.complete();
    await pending;
    expect(completed, isTrue);
    expect(h.events.last, 'dismiss');
  });
  testWidgets('unmounted view cleans up its loader without launching', (
    tester,
  ) async {
    final h = Harness('play');
    h.afterStep = (phase) async {
      if (phase == 'target') await tester.pumpWidget(const SizedBox());
    };
    await h.mount(tester);
    await h.run();
    expect(h.events.last, 'dismiss');
    expect(h.events, isNot(contains('identity')));
    expect(h.events, isNot(contains('play')));
  });

  for (final scenario in [
    'play',
    'browse',
    'episodes',
    'no-loader',
    'unverified',
    'unavailable',
    'retire-origin',
    'retire-policy',
    'cancel-target',
    'retire-target',
    'retire-identity',
    'null-target',
    'null-identity',
    'throw-target',
    'throw-identity',
    'throw-play',
  ]) {
    testWidgets(
      'catalog presentation preserves $scenario ownership and handoff',
      (tester) async {
        final h = Harness(scenario);
        await h.mount(tester);
        if (scenario.startsWith('throw-')) {
          await expectLater(h.run(), throwsA(same(h.error)));
          expect(h.events.last, 'dismiss');
          return;
        }
        await h.run();
        if (['play', 'browse', 'no-loader'].contains(scenario)) {
          expect(h.events, [
            'origin',
            'policy',
            if (scenario != 'no-loader') 'loader',
            'activate',
            'target',
            'identity',
            if (scenario != 'no-loader') 'dismiss',
            scenario == 'browse' ? 'browse' : 'play',
            if (scenario != 'no-loader') 'dismiss',
          ]);
        } else if (scenario == 'episodes') {
          expect(h.events, [
            'origin',
            'policy',
            'loader',
            'activate',
            'target',
            'episodes',
            'dismiss',
          ]);
        } else {
          expect(h.events, isNot(contains('play')));
          expect(h.events, isNot(contains('browse')));
          expect(h.events, isNot(contains('episodes')));
          if (h.events.contains('loader')) expect(h.events.last, 'dismiss');
        }
        expect(
          h.messages.length,
          ['unverified', 'unavailable'].contains(scenario) ? 1 : 0,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
