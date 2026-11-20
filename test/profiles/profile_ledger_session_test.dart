import 'dart:async';
import 'dart:io';

import 'package:debrify/features/ledger/models/ledger_brand.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/services/ledger/ledger_api.dart';
import 'package:debrify/services/ledger/ledger_auth_api.dart';
import 'package:debrify/services/ledger/ledger_service.dart';
import 'package:debrify/services/ledger/ledger_session.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/storage/ledger_storage.dart';
import 'package:debrify/services/profiles/profile_preference_portability.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage/tracker_episode_progress_storage.dart';
import 'package:debrify/services/storage/tracking_source_storage.dart';
import 'package:debrify/services/tracking_source_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  // Ledger is behind a feature flag (off in builds).
  setUp(() => debugLedgerEnabled = true);
  tearDown(() => debugLedgerEnabled = null);

  late Directory temporaryDirectory;
  late ProfileRegistry registry;
  late MemoryDeviceSecretCipher cipher;
  late String adminId;
  late String memberId;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'ledger-session-test-',
    );
    registry = await ProfileRegistry.open(
      path: p.join(temporaryDirectory.path, 'profiles.db'),
    );
    adminId = (await registry.createProfile(
      name: 'Admin',
      role: UserProfileRole.admin,
    )).id;
    memberId = (await registry.createProfile(
      name: 'Member',
      role: UserProfileRole.member,
    )).id;
    await registry.commitBootstrap(
      activeProfileId: adminId,
      migratedLegacyInstall: false,
    );
    cipher = MemoryDeviceSecretCipher(List<int>.generate(32, (i) => i));
    await cipher.initialize();
    DeviceKeyProvider.debugInstallCipher(cipher);
    ProfileBootstrap.debugInstallRegistry(registry);
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeCommitted(
      ProfileScope(profileId: adminId, dataGeneration: 1, sessionEpoch: 1),
    );
  });

  tearDown(() async {
    ProfileRuntime.debugReset();
    ProfileBootstrap.debugInstallRegistry(null);
    DeviceKeyProvider.debugReset();
    await registry.close();
    await temporaryDirectory.delete(recursive: true);
  });

  Future<void> switchTo(String profileId, int epoch) async {
    await registry.setActiveProfile(profileId);
    ProfileRuntime.publish(
      ProfileScope(
        profileId: profileId,
        dataGeneration: 1,
        sessionEpoch: epoch,
      ),
    );
  }

  Future<void> signIn({int expiryMs = 1}) => LedgerStorage.setSession(
    accessToken: 'access',
    refreshToken: 'refresh',
    expiryMs: expiryMs,
  );

  LedgerSession session(http.Client client) => LedgerSession(
    authApi: LedgerAuthApi(client: client, baseUrl: 'https://ledger.test'),
  );

  http.Response tokens(String access, String refresh) => http.Response(
    '{"access_token":"$access","refresh_token":"$refresh",'
    '"expires_in":3600,"token_type":"Bearer"}',
    200,
  );

  test('a session belongs to one profile on this device only', () async {
    await signIn(expiryMs: 42);
    expect(await LedgerStorage.getAccessToken(), 'access');
    expect(await LedgerStorage.getRefreshToken(), 'refresh');
    expect(await LedgerStorage.getTokenExpiry(), 42);
    // Not a connection resource: nothing to share, sync, import or export.
    expect(
      await registry.getBoundResourceId(adminId, 'tracker.ledger'),
      isNull,
    );
    // Sealed with the device key and never part of a portable package.
    final prefs = await ProfilePreferences.instance();
    expect(
      prefs.getString('ledger_refresh_token'),
      startsWith(SecretVault.prefix),
    );
    for (final key in [
      'ledger_access_token',
      'ledger_refresh_token',
      'ledger_username',
      'ledger_token_expiry',
    ]) {
      expect(ProfilePreferencePortability.allowsKey(key), isFalse, reason: key);
    }
    await switchTo(memberId, 2);
    expect(await LedgerStorage.hasCredential(), isFalse);
    expect(await LedgerStorage.getAccessToken(), isNull);
  });

  test(
    'concurrent callers renew an expired session with one exchange',
    () async {
      await signIn();
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        expect(request.url.path, '/oauth/token');
        expect(request.bodyFields['grant_type'], 'refresh_token');
        expect(request.bodyFields['refresh_token'], 'refresh');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return tokens('new-access', 'new-refresh');
      });
      final s = session(client);
      expect(await Future.wait([s.accessToken(), s.accessToken()]), [
        'new-access',
        'new-access',
      ]);
      expect(calls, 1, reason: 'a replayed refresh token revokes the session');
      expect(await LedgerStorage.getRefreshToken(), 'new-refresh');
      expect(await s.accessToken(), 'new-access');
      expect(calls, 1);
    },
  );

  test(
    'a refresh that finishes after a profile switch lands in its profile',
    () async {
      await signIn();
      final release = Completer<void>();
      final client = MockClient((request) async {
        await release.future;
        return tokens('admin-new', 'admin-refresh-2');
      });
      final s = session(client);
      final pending = s.refresh();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await switchTo(memberId, 2);
      release.complete();
      await pending;
      expect(await LedgerStorage.getAccessToken(), isNull);
      await switchTo(adminId, 3);
      expect(await LedgerStorage.getAccessToken(), 'admin-new');
      expect(await LedgerStorage.getRefreshToken(), 'admin-refresh-2');
    },
  );

  test('a refused refresh token signs the profile out locally', () async {
    await signIn();
    await TrackerEpisodeProgressStorage.saveEpisodeLedgerProgress(
      imdbId: 'tt1',
      percents: {'1_1': 50},
    );
    var changed = 0;
    final s = session(
      MockClient((_) async => http.Response('{"error":"invalid_grant"}', 400)),
    )..onAccountChanged = () => changed++;
    expect(await s.refresh(), isFalse);
    expect(await LedgerStorage.hasCredential(), isFalse);
    expect(changed, 1);
    expect(
      await TrackerEpisodeProgressStorage.getEpisodeLedgerProgress(
        imdbId: 'tt1',
      ),
      isEmpty,
      reason: 'no Ledger progress outlives the connection',
    );
  });

  test('a network failure keeps the session for the next try', () async {
    await signIn();
    final s = session(MockClient((_) async => http.Response('', 503)));
    expect(await s.refresh(), isFalse);
    expect(await LedgerStorage.getAccessToken(), 'access');
    expect(await LedgerStorage.getRefreshToken(), 'refresh');
  });

  test('sign-out revokes the session and forgets it', () async {
    await signIn();
    final paths = <String>[];
    final s = session(
      MockClient((request) async {
        paths.add(request.url.path);
        return http.Response('{}', 200);
      }),
    );
    await s.signOut();
    expect(paths, ['/v1/sessions:revoke']);
    expect(await LedgerStorage.hasCredential(), isFalse);
  });

  test('a request keeps its profile across a switch while it is out', () async {
    await signIn(
      expiryMs: DateTime.now()
          .add(const Duration(hours: 1))
          .millisecondsSinceEpoch,
    );
    await switchTo(memberId, 2);
    await LedgerStorage.setSession(
      accessToken: 'member-access',
      refreshToken: 'member-refresh',
      expiryMs: DateTime.now()
          .add(const Duration(hours: 1))
          .millisecondsSinceEpoch,
    );
    await switchTo(adminId, 3);
    final firstSent = Completer<void>();
    final release = Completer<void>();
    final auth = <String?>[];
    final client = MockClient((request) async {
      if (request.url.path == '/oauth/token') {
        expect(request.bodyFields['refresh_token'], 'refresh');
        return tokens('admin-access-2', 'admin-refresh-2');
      }
      auth.add(request.headers['Authorization']);
      if (auth.length == 1) {
        firstSent.complete();
        await release.future;
        return http.Response('{"code":16}', 401);
      }
      return http.Response('{}', 200);
    });
    final ledgerSession = LedgerSession(
      authApi: LedgerAuthApi(client: client, baseUrl: 'https://ledger.test'),
    );
    final service = LedgerService.forTesting(
      session: ledgerSession,
      api: LedgerApi(
        tokens: ledgerSession,
        client: client,
        baseUrl: 'https://ledger.test',
      ),
    );
    final write = service.markWatched('tt0133093', 'movie');
    await firstSent.future;
    await switchTo(memberId, 4);
    release.complete();
    expect(await write, isTrue);
    expect(auth, ['Bearer access', 'Bearer admin-access-2']);
    expect(await LedgerStorage.getAccessToken(), 'member-access');
    await switchTo(adminId, 5);
    expect(await LedgerStorage.getAccessToken(), 'admin-access-2');
  });

  test(
    'a synced Ledger progress source is never rewritten without a session',
    () async {
      await TrackingSourceStorage.setWatchProgressSource(
        WatchProgressSource.ledger,
      );
      final policy = await TrackingSourcePolicy.load();
      expect(policy.progressSource, WatchProgressSource.smart);
      expect(
        await TrackingSourceStorage.getWatchProgressSource(),
        WatchProgressSource.ledger,
        reason: 'the connected device keeps its choice',
      );
      expect(
        await TrackingSourceStorage.takeTrackingProgressFallbackNotice(),
        isFalse,
      );
      await signIn();
      expect(
        (await TrackingSourcePolicy.load()).progressSource,
        WatchProgressSource.ledger,
      );
      await LedgerStorage.clearAuth();
      expect(
        await TrackingSourceStorage.getWatchProgressSource(),
        WatchProgressSource.ledger,
        reason: 'signing out here leaves the synced choice alone',
      );
    },
  );

  test(
    'Home reads a synced Ledger choice without a session as Smart',
    () async {
      await TrackingSourceStorage.setWatchProgressSource(
        WatchProgressSource.trakt,
      );
      expect(
        await TrackingSourceStorage.getEffectiveWatchProgressSource(),
        WatchProgressSource.trakt,
        reason: 'other choices are returned as stored',
      );
      await TrackingSourceStorage.setWatchProgressSource(
        WatchProgressSource.ledger,
      );
      expect(
        await TrackingSourceStorage.getEffectiveWatchProgressSource(),
        WatchProgressSource.smart,
      );
      await signIn();
      expect(
        await TrackingSourceStorage.getEffectiveWatchProgressSource(),
        WatchProgressSource.ledger,
      );
    },
  );

  test(
    'refreshes from before and after a re-entry share one exchange',
    () async {
      await signIn();
      final release = Completer<void>();
      var calls = 0;
      final s = session(
        MockClient((_) async {
          calls++;
          await release.future;
          return tokens('new-access', 'new-refresh');
        }),
      );
      final first = s.refresh();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await switchTo(memberId, 2);
      await switchTo(adminId, 3);
      final second = s.refresh();
      release.complete();
      expect(await Future.wait([first, second]), [true, true]);
      expect(calls, 1, reason: 'a second exchange would replay the token');
    },
  );
}
