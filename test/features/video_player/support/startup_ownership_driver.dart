import 'dart:async';

import 'package:debrify/features/sources/data/automatic_source_bindings.dart';
import 'package:debrify/features/sources/models/resolved_source.dart';
import 'package:debrify/features/sources/presentation/legacy_playback/source_player_launch.dart';
import 'package:debrify/models/playback_meta.dart';
import 'package:debrify/models/series_source.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/resolved_playback_link_cache.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage/real_debrid_storage.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_tombstones.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Existing resolved transport; no app dependency changes.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'local_completion_driver.dart';
import 'startup_driver.dart';
import 'vp_fixture_actions.dart';
import 'trakt_transport.dart';

const ownershipId = 'tt9200016';
Torrent ownershipSource(String name, {bool torrent = false}) => Torrent(
  rowid: 0,
  infohash: torrent ? 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' : '',
  name: name,
  sizeBytes: 1,
  createdUnix: 0,
  seeders: 0,
  leechers: 0,
  completed: 0,
  scrapedDate: 0,
  streamType: torrent ? StreamType.torrent : StreamType.directUrl,
  directUrl: torrent ? null : 'https://ownership.test/$name.mp4',
  stremioAddonId: torrent ? null : 'p16-addon',
  stremioAddonKey: torrent ? null : 'p16-config',
  stremioStreamKey: torrent ? null : name,
  stremioVideoId: torrent ? null : ownershipId,
  stremioStreamIndex: torrent ? null : 0,
);

class OwnershipPhysicalWrites extends CompletionWrites {
  OwnershipPhysicalWrites(super.values, this.driver);
  final StartupOwnershipDriver driver;
  bool armed = false;
  bool entered = false;
  Completer<void>? gate;
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (armed && key.endsWith(ResolvedPlaybackLinkCache.preferenceKey)) {
      armed = false;
      entered = true;
      final activity = driver.f.actions.begin(
        'admitted physical source-cache write',
        held: true,
      );
      try {
        await gate!.future;
      } finally {
        activity.complete();
      }
    }
    return super.setValue(type, key, value);
  }
}

class StartupOwnershipDriver extends StartupDriver {
  StartupOwnershipDriver(super.t) : super(autoFrame: true);
  final caught = <String>[];
  T observeErrors<T>(T Function() body) => runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      registerBinaryCallback:
          <R, A, B>(self, parent, zone, R Function(A, B) callback) {
            return parent.registerBinaryCallback(zone, (A a, B b) {
              caught.add(a.toString());
              return callback(a, b);
            });
          },
    ),
  );
  final oldStore = SharedPreferencesStorePlatform.instance;
  late OwnershipPhysicalWrites store;
  late ProfileScope origin, incoming;
  late AutomaticSourceBindings bindings;
  VpFixtureTask<void>? launch;
  final first = ownershipSource('first');
  final second = ownershipSource('second');
  final third = ownershipSource('third');

  Future<void> setup() async {
    await initialize();
    TraktTestTransport.instance.attach(f);
    SecretVault.debugReset(deviceIdOverride: 'p16-source-ownership');
    WebDavSyncTombstoneRecorder.debugInstall(sink: (_, _) {});
    final a = ProfileRuntime.capture();
    incoming = await completionIncomingProfile(t, f);
    await f.finish(
      t,
      ProfileRuntime.withCapturedScope(incoming, () async {
        final prefs = await ProfilePreferences.instance();
        await prefs.setString('p16_source_sentinel', 'incoming-untouched');
      }),
    );
    origin = await completionActivate(t, f, a);
    store = OwnershipPhysicalWrites(
      await f.finish(t, SharedPreferencesStorePlatform.instance.getAll()),
      this,
    );
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = store;
    bindings = AutomaticSourceBindings.capture();
  }

  Future<void> start({bool lazy = false, List<Torrent>? sources}) =>
      observe(() async {
        late BuildContext context;
        t.view.physicalSize = const Size(1280, 800);
        t.view.devicePixelRatio = 1;
        await t.pumpWidget(
          MaterialApp(
            navigatorKey: f.navigator,
            theme: ThemeData.dark(),
            home: Builder(
              builder: (c) {
                context = c;
                return const Scaffold(body: Text('Production source launcher'));
              },
            ),
          ),
        );
        launch = f.actions.start(
          'real SourcePlayerLaunch',
          () => SourcePlayerLaunch.launch(
            context,
            ResolvedSource(title: 'P16 owned movie', playUrl: first.directUrl),
            'P16 owned movie',
            provider: lazy ? SeriesSource.localService : 'debrid',
            meta: const PlaybackMeta(imdbId: ownershipId, contentType: 'movie'),
            sources: sources ?? [first, second, third],
            sourceBindings: bindings,
          ),
          held: true,
        );
        await f.until(t, () => f.players.isNotEmpty);
        player.deliverReady();
        await openEntered();
        await initialized();
        await settle();
        await f.until(
          t,
          () => store.writes.any(
            (r) => r.$1.endsWith('series_source_$ownershipId'),
          ),
        );
        expect(await pins(origin), contains('first'));
        expect(await cache(origin), contains(first.directUrl));
      });

  Future<String> pins(ProfileScope scope) async =>
      (await store.physical(scope, 'series_source_$ownershipId')) as String? ??
      '';
  Future<String> cache(ProfileScope scope) async {
    final raw =
        await store.physical(scope, ResolvedPlaybackLinkCache.preferenceKey)
            as String?;
    final plain = await f.finish<String?>(t, SecretVault.open(raw));
    return plain ?? '';
  }

  Future<Map<String, Object?>> physical(ProfileScope scope) async => {
    'binding': await pins(scope),
    'cache': await cache(scope),
    'sentinel': await store.physical(scope, 'p16_source_sentinel'),
  };
  Future<void>? deletion;
  Future<void> crossing(String crossing, {bool pendingDelete = false}) async {
    if (crossing == 'none') return;
    if (crossing == 'route close') {
      f.navigator.currentState!.pop();
      await f.finish(t, launch!.future);
      await tick(const Duration(milliseconds: 400));
      await f.until(t, () => player.disposed.isCompleted);
      return;
    }
    await completionActivate(t, f, incoming);
    if (crossing == 'A to B to A') await completionActivate(t, f, origin);
    if (crossing == 'delete A') {
      final actor = await f.finish(
        t,
        ProfileAuthorizationContext.capture(f.registry!),
      );
      deletion = f.registry!.deleteProfileWithDisposition(
        id: origin.profileId,
        deleteOwnedResources: true,
        detachPublicArtifacts: true,
        actingProfileId: actor.profileId,
        actingAuthorizationRevision: actor.authorizationRevision,
        actingSessionEpoch: actor.sessionEpoch,
      );
      if (pendingDelete) {
        await tick();
        return;
      }
      await f.finish(t, deletion!);
      expect(
        await f.finish(t, f.registry!.getProfile(origin.profileId)),
        isNull,
      );
    }
  }

  Future<void> credential() async {
    await f.finish(t, RealDebridStorage.saveApiKey('p16-synthetic-rd-key'));
    await f.finish(t, RealDebridStorage.saveFileSelection('all'));
    // Seed this synthetic credential for A only, so the real profile deletion
    // has no unrelated shared-connection disposition to settle mid-barrier.
    final grants = await f.finish(t, f.registry!.listAllResourceGrants());
    final owned = await f.finish(
      t,
      f.registry!.listOwnedResourcesIncludingDisabled(origin.profileId),
    );
    for (final resource in owned) {
      for (final grant in grants.where(
        (g) =>
            g['resource_id'] == resource.id &&
            g['profile_id'] != origin.profileId,
      )) {
        await f.finish(
          t,
          f.registry!.revokeGrant(grant['profile_id'] as String, resource.id),
        );
      }
    }
  }

  @override
  Future<void> close() async {
    store.gate?.completeIfPending();
    try {
      if (launch != null && !launch!.isCompleted) {
        if (f.navigator.currentState?.canPop() == true) {
          f.navigator.currentState!.pop();
        }
        await f.finish(t, launch!.future);
      }
      await super.close();
    } finally {
      SharedPreferencesStorePlatform.instance = oldStore;
      TraktTestTransport.instance.recorder = null;
      SecretVault.debugReset();
      WebDavSyncTombstoneRecorder.debugReset();
    }
  }
}
