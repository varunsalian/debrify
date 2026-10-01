import 'package:debrify/services/profiles/profile_playback_preparation.dart';
import 'package:debrify/services/profiles/profile_local_writes.dart';
import 'package:debrify/services/android_tv_player_bridge.dart';
import 'dart:async';
import 'dart:convert';
import 'package:debrify/services/storage/continue_watching_storage.dart';
import 'package:debrify/services/storage/playlist_storage.dart';
import 'package:debrify/services/storage/real_debrid_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:debrify/features/sources/data/source_playlist.dart';
import 'package:debrify/features/sources/models/acquired_source.dart';

import 'package:debrify/features/sources/data/automatic_source_bindings.dart';
import 'package:debrify/features/sources/data/source_binding_committer.dart';
import 'package:debrify/models/playback_meta.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/services/resolved_playback_link_cache.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/series_source_service.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_tombstones.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const id = 'tt1234567';
const movie = PlaybackMeta(imdbId: id, contentType: 'movie');
Torrent source(String hash, {bool direct = false}) => Torrent(
  rowid: 0,
  infohash: hash,
  name: 'Fixture.S01E01',
  sizeBytes: 1,
  createdUnix: 0,
  seeders: 0,
  leechers: 0,
  completed: 0,
  scrapedDate: 0,
  streamType: direct ? StreamType.directUrl : StreamType.torrent,
  directUrl: direct ? 'https://fixture.test/$hash.mp4' : null,
  stremioAddonId: direct ? 'addon' : null,
  stremioAddonKey: direct ? 'configuration' : null,
  stremioStreamKey: direct ? hash : null,
  stremioVideoId: direct ? id : null,
  stremioStreamIndex: direct ? 0 : null,
);

class ObservedBindings extends AutomaticSourceBindings {
  ObservedBindings() : super.capture();
  final enteredCache = Completer<void>();
  @override
  Future<void> cacheDirect(
    PlaybackMeta? meta,
    Torrent source, {
    required bool Function() canContinue,
  }) {
    if (!enteredCache.isCompleted) enteredCache.complete();
    return super.cacheDirect(meta, source, canContinue: canContinue);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProfileRegistry registry;
  late ProfileScope origin;
  late ProfileScope incoming;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    ProfileRuntime.debugReset();
    SharedPreferences.setMockInitialValues({});
    registry = await ProfileRegistry.open(path: inMemoryDatabasePath);
    final first = await registry.createProfile(
      name: 'First',
      role: UserProfileRole.admin,
    );
    final second = await registry.createProfile(
      name: 'Second',
      role: UserProfileRole.admin,
    );
    origin = ProfileScope(
      profileId: first.id,
      dataGeneration: 1,
      sessionEpoch: 1,
    );
    incoming = ProfileScope(
      profileId: second.id,
      dataGeneration: 1,
      sessionEpoch: 2,
    );
    ProfileBootstrap.debugInstallRegistry(registry);
    DeviceKeyProvider.debugInstallCipher(
      MemoryDeviceSecretCipher(List<int>.generate(32, (i) => i + 1)),
    );
    SecretVault.debugReset(deviceIdOverride: 'automatic-binding-fixture');
    ProfileRuntime.initializeCommitted(origin);
    WebDavSyncTombstoneRecorder.debugInstall(sink: (_, _) {});
  });
  tearDown(() async {
    ProfileRuntime.debugReset();
    ProfileBootstrap.debugInstallRegistry(null);
    DeviceKeyProvider.debugReset();
    SecretVault.debugReset();
    WebDavSyncTombstoneRecorder.debugReset();
    await registry.close();
  });

  SourceBindingCommitter committer({
    AutomaticSourceBindings? bindings,
    bool lazy = false,
    Future<String?> Function(bool Function())? choose,
  }) => SourceBindingCommitter(
    bindings: bindings ?? AutomaticSourceBindings.capture(),
    meta: movie,
    provider: lazy ? null : 'debrid',
    lazy: lazy,
    chooseProvider: choose ?? (_) async => 'debrid',
  );
  Future<List<SeriesSource>> pins(ProfileScope scope) =>
      ProfileRuntime.withCapturedScope(
        scope,
        () => SeriesSourceService.getSources(id),
      );

  test(
    'queued commits retain origin even when invoked from another captured scope',
    () async {
      final writer = committer();
      await ProfileRuntime.withCapturedScope(incoming, () async {
        await writer(source('first'));
        await writer(source('second'));
      });
      expect((await pins(origin)).single.torrentHash, 'second');
      expect(await pins(incoming), isEmpty);
    },
  );

  for (final retired in ['close', 'profile']) {
    test(
      '$retired retires pending provider selection and later queue entries',
      () async {
        final entered = Completer<void>();
        final release = Completer<String?>();
        var selections = 0;
        final writer = committer(
          lazy: true,
          choose: (active) {
            selections++;
            entered.complete();
            return release.future;
          },
        );
        final first = writer(source('first'));
        await entered.future;
        final second = writer(source('second'));
        if (retired == 'close') {
          writer.close();
        } else {
          ProfileRuntime.publish(incoming);
        }
        release.complete('debrid');
        await Future.wait([first, second]);
        expect(selections, 1);
        expect(await pins(origin), isEmpty);
        expect(await pins(incoming), isEmpty);
      },
    );

    test(
      '$retired at encrypted cache barrier prevents both cache and pin writes',
      () async {
        final bindings = ObservedBindings();
        final writer = committer(bindings: bindings);
        final entered = Completer<void>();
        final release = Completer<void>();
        final snapshot = ProfilePreferences.captureMutationSnapshot((_) async {
          entered.complete();
          await release.future;
        });
        await entered.future;
        final pending = writer(source('direct', direct: true));
        await bindings.enteredCache.future;
        await Future<void>.delayed(Duration.zero);
        if (retired == 'close') {
          writer.close();
        } else {
          ProfileRuntime.publish(incoming);
        }
        release.complete();
        await snapshot;
        await pending;
        final raw = await SharedPreferences.getInstance();
        expect(
          raw.getString(
            origin.preferenceKey(ResolvedPlaybackLinkCache.preferenceKey),
          ),
          isNull,
        );
        expect(
          raw.getString(
            incoming.preferenceKey(ResolvedPlaybackLinkCache.preferenceKey),
          ),
          isNull,
        );
        expect(await pins(origin), isEmpty);
        expect(await pins(incoming), isEmpty);
      },
    );
  }

  test(
    'profile switch during replacement tombstone cannot write incoming or replace origin pins',
    () async {
      final original = AutomaticSourceBindings.describe(
        source('old'),
        'debrid',
      )!;
      await SeriesSourceService.setSources(id, [original]);
      final writer = committer();
      final entered = Completer<void>();
      final release = Completer<void>();
      String? tombstoneOwner;
      WebDavSyncTombstoneRecorder.debugInstall(
        sink: (profile, keys) async {
          tombstoneOwner = profile;
          entered.complete();
          await release.future;
        },
      );
      final pending = writer(source('new'));
      await entered.future;
      ProfileRuntime.publish(incoming);
      release.complete();
      await pending;
      expect(tombstoneOwner, origin.profileId);
      expect((await pins(origin)).single.torrentHash, 'old');
      expect(await pins(incoming), isEmpty);
    },
  );

  test(
    'closing one player does not retire another player in the same profile',
    () async {
      final bindings = AutomaticSourceBindings.capture();
      final first = committer(bindings: bindings);
      final second = committer(bindings: bindings);
      first.close();
      await first(source('retired'));
      await second(source('current'));
      expect((await pins(origin)).single.torrentHash, 'current');
    },
  );
  test(
    'invalid-source removal stays in origin when called from a foreign scope',
    () async {
      final pin = AutomaticSourceBindings.describe(
        source('invalid'),
        'debrid',
      )!;
      await SeriesSourceService.setSources(id, [pin]);
      final bindings = AutomaticSourceBindings.capture();
      await ProfileRuntime.withCapturedScope(
        incoming,
        () => bindings.removeInvalid(id, pin, canContinue: () => true),
      );
      expect(await pins(origin), isEmpty);
      expect(await pins(incoming), isEmpty);
    },
  );

  test('retirement at removal tombstone preserves origin pins', () async {
    final pin = AutomaticSourceBindings.describe(source('invalid'), 'debrid')!;
    await SeriesSourceService.setSources(id, [pin]);
    final bindings = AutomaticSourceBindings.capture();
    final entered = Completer<void>();
    final release = Completer<void>();
    WebDavSyncTombstoneRecorder.debugInstall(
      sink: (_, _) async {
        entered.complete();
        await release.future;
      },
    );
    final pending = bindings.removeInvalid(id, pin, canContinue: () => true);
    final checked = expectLater(pending, throwsStateError);
    await entered.future;
    ProfileRuntime.publish(incoming);
    release.complete();
    await checked;
    expect((await pins(origin)).single.bindingKey, pin.bindingKey);
    expect(await pins(incoming), isEmpty);
  });

  test(
    'cache removal rechecks retirement at the actual preference barrier',
    () async {
      final direct = source('cached', direct: true);
      final pin = AutomaticSourceBindings.describe(
        direct,
        SeriesSource.addonDirectService,
      )!;
      final bindings = AutomaticSourceBindings.capture();
      await bindings.cacheDirect(movie, direct, canContinue: () => true);
      expect(
        (await ResolvedPlaybackLinkCache.get(
          id: id,
          type: 'movie',
          pin: pin,
        ))?.directUrl,
        direct.directUrl,
      );
      final entered = Completer<void>();
      final release = Completer<void>();
      final barrier = ProfilePreferences.captureMutationSnapshot((_) async {
        entered.complete();
        await release.future;
      });
      await entered.future;
      final pending = bindings.removeCachedLink(
        id: id,
        type: 'movie',
        pin: pin,
        canContinue: () => true,
      );
      await Future<void>.delayed(Duration.zero);
      ProfileRuntime.publish(incoming);
      release.complete();
      await barrier;
      await pending;
      final retained = await ProfileRuntime.withCapturedScope(
        origin,
        () => ResolvedPlaybackLinkCache.get(id: id, type: 'movie', pin: pin),
      );
      expect(retained?.directUrl, direct.directUrl);
    },
  );
  test(
    'playlist add retains origin under foreign scope and deduplicates',
    () async {
      final playlist = SourcePlaylist(
        owner: ProfileSessionMemory.captureOwner(),
        canContinue: () => true,
      );
      await ProfileRuntime.withCapturedScope(incoming, () async {
        expect(
          await playlist.add(
            const AcquiredSource(
              title: 'Title',
              torboxTorrentId: 42,
              torboxFileId: 1,
            ),
            source('hash'),
            'torbox',
          ),
          isTrue,
        );
        expect(
          await playlist.add(
            const AcquiredSource(
              title: 'Title',
              torboxTorrentId: 42,
              torboxFileId: 1,
            ),
            source('hash'),
            'torbox',
          ),
          isFalse,
        );
      });
      expect(
        (await ProfileRuntime.withCapturedScope(
          origin,
          PlaylistStorage.getPlaylistItemsRaw,
        )).single['torboxTorrentId'],
        42,
      );
      expect(
        await ProfileRuntime.withCapturedScope(
          incoming,
          PlaylistStorage.getPlaylistItemsRaw,
        ),
        isEmpty,
      );
    },
  );

  test(
    'playlist add rejects retirement while waiting for actual write barrier',
    () async {
      final playlist = SourcePlaylist(
        owner: ProfileSessionMemory.captureOwner(),
        canContinue: () => true,
      );
      final entered = Completer<void>();
      final release = Completer<void>();
      final barrier = ProfilePreferences.captureMutationSnapshot((_) async {
        entered.complete();
        await release.future;
      });
      await entered.future;
      final pending = playlist.add(
        const AcquiredSource(title: 'Title', torboxTorrentId: 42),
        source('hash'),
        'torbox',
      );
      await Future<void>.delayed(Duration.zero);
      ProfileRuntime.publish(incoming);
      release.complete();
      await barrier;
      expect(await pending, isFalse);
      expect(
        await ProfileRuntime.withCapturedScope(
          origin,
          PlaylistStorage.getPlaylistItemsRaw,
        ),
        isEmpty,
      );
      expect(
        await ProfileRuntime.withCapturedScope(
          incoming,
          PlaylistStorage.getPlaylistItemsRaw,
        ),
        isEmpty,
      );
    },
  );
  test(
    'playlist retirement during RD enrichment cannot persist either profile',
    () async {
      await registry.commitBootstrap(
        activeProfileId: origin.profileId,
        migratedLegacyInstall: false,
      );
      await RealDebridStorage.saveApiKey('original-key');
      final playlist = SourcePlaylist(
        owner: ProfileSessionMemory.captureOwner(),
        canContinue: () => true,
      );
      var requests = 0;
      final client = MockClient((request) async {
        requests++;
        expect(request.headers['Authorization'], 'Bearer original-key');
        ProfileRuntime.publish(incoming);
        return http.Response(jsonEncode({'hash': 'enriched-hash'}), 200);
      });
      addTearDown(client.close);
      final saved = await http.runWithClient(
        () => playlist.add(
          const AcquiredSource(title: 'Title', rdTorrentId: 'rd-id'),
          source('hash'),
          'debrid',
        ),
        () => client,
      );
      expect(requests, 1);
      expect(saved, isFalse);
      expect(
        await ProfileRuntime.withCapturedScope(
          origin,
          PlaylistStorage.getPlaylistItemsRaw,
        ),
        isEmpty,
      );
      expect(
        await ProfileRuntime.withCapturedScope(
          incoming,
          PlaylistStorage.getPlaylistItemsRaw,
        ),
        isEmpty,
      );
    },
  );
  test(
    'native launch return keeps source commits alive until session drains',
    () async {
      final writer = committer();
      final session = StremioSourcePersistenceSession(
        1,
        onRetired: writer.retain(),
      );
      writer
          .close(); // Android launch returned; native playback is still active.
      expect(writer.isCurrent, isTrue);
      await session.enqueue(() => writer(source('native-initial')));
      expect((await pins(origin)).single.torrentHash, 'native-initial');
      final release = Completer<void>();
      final queued = session.enqueue(() async {
        await release.future;
        await writer(source('native-switch'));
      });
      final draining = session.closeAndDrain();
      expect(writer.isCurrent, isTrue);
      release.complete();
      await queued;
      await draining;
      expect((await pins(origin)).single.torrentHash, 'native-switch');
      expect(writer.isCurrent, isFalse);
      await writer(source('late'));
      expect((await pins(origin)).single.torrentHash, 'native-switch');
    },
  );

  test(
    'failed native handoff releases only its lease, preserving player fallback',
    () async {
      final writer = committer();
      final session = StremioSourcePersistenceSession(
        2,
        onRetired: writer.retain(),
      );
      session.retire();
      session.retire();
      expect(writer.isCurrent, isTrue);
      await writer(source('fallback'));
      expect((await pins(origin)).single.torrentHash, 'fallback');
      writer.close();
      expect(writer.isCurrent, isFalse);
    },
  );
  test(
    'playback preparation writes to origin from a foreign callback scope',
    () async {
      final preparation = ProfilePlaybackPreparation(
        owner: ProfileSessionMemory.captureOwner(),
        canContinue: () => true,
      );
      await ProfileRuntime.withCapturedScope(
        incoming,
        () => preparation.write(
          () => ContinueWatchingStorage.saveContinueWatchingItem(
            imdbId: 'tt123',
            title: 'Original',
            contentType: 'movie',
          ),
        ),
      );
      final original = await ProfileRuntime.withCapturedScope(
        origin,
        ContinueWatchingStorage.getContinueWatchingItems,
      );
      final other = await ProfileRuntime.withCapturedScope(
        incoming,
        ContinueWatchingStorage.getContinueWatchingItems,
      );
      expect(original.single['title'], 'Original');
      expect(other, isEmpty);
    },
  );
  test(
    'playback preparation rejects a write retired at the mutation barrier',
    () async {
      final preparation = ProfilePlaybackPreparation(
        owner: ProfileSessionMemory.captureOwner(),
        canContinue: () => true,
      );
      final entered = Completer<void>();
      final release = Completer<void>();
      final barrier = ProfilePreferences.captureMutationSnapshot((_) async {
        entered.complete();
        await release.future;
      });
      await entered.future;
      var wrote = false;
      final pending = preparation.write(() async {
        wrote = true;
      });
      await Future<void>.delayed(Duration.zero);
      ProfileRuntime.publish(incoming);
      release.complete();
      await barrier;
      await pending;
      expect(wrote, isFalse);
      await expectLater(
        preparation.run(() async {}),
        throwsA(isA<PlaybackPreparationRetired>()),
      );
    },
  );
  test(
    'accepted preparation write drains in origin after profile retirement',
    () async {
      final preparation = ProfilePlaybackPreparation(
        owner: ProfileSessionMemory.captureOwner(),
        canContinue: () => true,
      );
      final entered = Completer<void>();
      final release = Completer<void>();
      final pending = preparation.write(() async {
        entered.complete();
        await release.future;
        await ContinueWatchingStorage.saveContinueWatchingItem(
          imdbId: 'tt123',
          title: 'Accepted',
          contentType: 'movie',
        );
      });
      await entered.future;
      ProfileRuntime.publish(incoming);
      var drained = false;
      final drain = ProfileLocalWrites.drain().then((_) {
        drained = true;
      });
      await Future<void>.delayed(Duration.zero);
      expect(drained, isFalse);
      release.complete();
      await pending;
      await drain;
      expect(
        (await ProfileRuntime.withCapturedScope(
          origin,
          ContinueWatchingStorage.getContinueWatchingItems,
        )).single['title'],
        'Accepted',
      );
      expect(
        await ProfileRuntime.withCapturedScope(
          incoming,
          ContinueWatchingStorage.getContinueWatchingItems,
        ),
        isEmpty,
      );
    },
  );
}
