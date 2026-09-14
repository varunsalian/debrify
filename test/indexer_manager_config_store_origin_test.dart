import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:debrify/models/indexer_manager_config.dart';
import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/services/profiles/connection_resource_service.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_collection_resource_facade.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Public facade characterization pinned on upstream 75b53ef3. Synthetic-only credentials, never real resources.
// No copied adapter/authorization logic; local transports exercise actual APIs.
const _key = 'indexer_manager_configs_v1';
const _limit = Duration(seconds: 5);
IndexerManagerConfig _config(
  String id, {
  IndexerManagerType type = IndexerManagerType.jackett,
}) => IndexerManagerConfig(
  id: id,
  name: id,
  type: type,
  baseUrl: 'https://synthetic.invalid',
  apiKey: 'synthetic-test-only',
);

class _Prefs extends InMemorySharedPreferencesStore {
  _Prefs(super.data) : super.withData();
  final entered = Completer<void>();
  final release = Completer<void>();
  final failure = StateError('synthetic preference write failure');
  int writes = 0;
  int otherWrites = 0;
  bool hold = false;
  String outcome = 'ok';
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key != 'flutter.$_key') {
      otherWrites++;
      return super.setValue(type, key, value);
    }
    writes++;
    if (hold) {
      entered.complete();
      await release.future.timeout(_limit);
    }
    if (outcome == 'throw') throw failure;
    if (outcome == 'false') return false;
    return super.setValue(type, key, value);
  }

  Future<Map<String, Object>> durable() => super.getAllWithParameters(
    GetAllParameters(filter: PreferencesFilter(prefix: 'flutter.')),
  );
}

class _HeldCipher implements DeviceSecretCipher {
  _HeldCipher(this.delegate, {this.sealFirst = false});
  final DeviceSecretCipher delegate;
  final bool sealFirst;
  final entered = Completer<void>();
  final release = Completer<void>();
  bool used = false;
  Future<void> barrier(bool sealing) async {
    if (used || sealing != sealFirst) return;
    used = true;
    entered.complete();
    await release.future.timeout(_limit);
  }

  @override
  Future<void> initialize() => delegate.initialize();
  @override
  Future<List<int>> open(
    String envelope, {
    required List<int> associatedData,
  }) async {
    await barrier(false);
    return delegate.open(envelope, associatedData: associatedData);
  }

  @override
  Future<String> seal(
    List<int> plaintext, {
    required List<int> associatedData,
  }) async {
    await barrier(true);
    return delegate.seal(plaintext, associatedData: associatedData);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferencesStorePlatform previous;
  late _Prefs prefsBackend;
  Directory? directory;
  ProfileRegistry? registry;
  late MemoryDeviceSecretCipher cipher;
  late String admin;
  late String member;
  final held = <_HeldCipher>[];
  int epoch = 1;

  void install(Map<String, Object> values) {
    SharedPreferences.resetStatic();
    prefsBackend = _Prefs({
      for (final e in values.entries) 'flutter.${e.key}': e.value,
    });
    SharedPreferencesStorePlatform.instance = prefsBackend;
  }

  Future<void> canonical() async {
    directory = await Directory.systemTemp.createTemp('indexer-origin-');
    registry = await ProfileRegistry.open(
      path: p.join(directory!.path, 'profiles.db'),
    );
    admin = (await registry!.createProfile(
      name: 'Owner',
      role: UserProfileRole.admin,
    )).id;
    member = (await registry!.createProfile(
      name: 'Borrower',
      role: UserProfileRole.member,
    )).id;
    await registry!.commitBootstrap(
      activeProfileId: admin,
      migratedLegacyInstall: false,
    );
    cipher = MemoryDeviceSecretCipher(List<int>.generate(32, (i) => i + 1));
    await cipher.initialize();
    DeviceKeyProvider.debugInstallCipher(cipher);
    ProfileBootstrap.debugInstallRegistry(registry);
    ProfileRuntime.initializeCommitted(
      ProfileScope(profileId: admin, dataGeneration: 1, sessionEpoch: epoch),
    );
  }

  void publish(String id) => ProfileRuntime.publish(
    ProfileScope(profileId: id, dataGeneration: 1, sessionEpoch: ++epoch),
  );
  Future<ConnectionResource> create(
    String id, {
    IndexerManagerType type = IndexerManagerType.jackett,
    bool malformed = false,
  }) async =>
      ConnectionResourceService(registry: registry!, cipher: cipher).create(
        context: await ProfileAuthorizationContext.capture(registry!),
        type: type == IndexerManagerType.jackett
            ? ConnectionResourceType.jackett
            : ConnectionResourceType.prowlarr,
        label: id,
        publicConfig: {'managerName': id},
        secretConfig: {
          ..._config(id, type: type).toJson(),
          if (malformed) 'enabled': 'wrong-type',
        },
      );

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() {
    previous = SharedPreferencesStorePlatform.instance;
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    DeviceKeyProvider.debugReset();
    SecretVault.debugReset(deviceIdOverride: 'synthetic-indexer-origin');
    install({});
    epoch = 1;
  });
  tearDown(() async {
    if (!prefsBackend.release.isCompleted) prefsBackend.release.complete();
    for (final gate in held) {
      if (!gate.release.isCompleted) gate.release.complete();
    }
    held.clear();
    ProfileRuntime.debugReset();
    ProfileBootstrap.debugInstallRegistry(null);
    DeviceKeyProvider.debugReset();
    SecretVault.debugReset();
    await registry?.close();
    registry = null;
    await directory?.delete(recursive: true);
    directory = null;
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = previous;
  });

  test(
    'legacy absent returns growable empty; wrong physical type escapes',
    () async {
      final empty = await StorageService.getIndexerManagerConfigs();
      empty.add(_config('local'));
      expect(await StorageService.getIndexerManagerConfigs(), isEmpty);
      install({_key: true});
      await expectLater(
        StorageService.getIndexerManagerConfigs(),
        throwsA(isA<TypeError>()),
      );
    },
  );

  test(
    'legacy per-row JSON failures skip in order and clean plaintext reseals',
    () async {
      install({
        _key: [
          jsonEncode(_config('a').toJson()),
          '{',
          jsonEncode(_config('b').toJson()),
          '[]',
        ],
      });
      final result = await StorageService.getIndexerManagerConfigs();
      expect(result.map((e) => e.id), ['a', 'b']);
      result.add(_config('mutable'));
      final raw = (await prefsBackend.durable())['flutter.$_key'] as List;
      expect(raw.length, 4);
      expect(raw.every((e) => SecretVault.isSealed(e as String)), isTrue);
      expect(prefsBackend.writes, 1);
    },
  );

  test(
    'legacy decrypt failure drops row and prevents clean-legacy rewrite',
    () async {
      final raw = [jsonEncode(_config('a').toJson()), 'enc1:invalid'];
      install({_key: raw});
      expect(
        (await StorageService.getIndexerManagerConfigs()).map((e) => e.id),
        ['a'],
      );
      expect(prefsBackend.writes, 0);
      expect(
        jsonEncode((await prefsBackend.durable())['flutter.$_key']) ==
            jsonEncode(raw),
        isTrue,
      );
    },
  );

  for (final outcome in ['ok', 'false', 'throw']) {
    test(
      'legacy held write $outcome retains prewrite snapshot and late live readback',
      () async {
        prefsBackend.hold = true;
        prefsBackend.outcome = outcome;
        final input = [_config('before')];
        final result = StorageService.setIndexerManagerConfigs(input);
        List<IndexerManagerConfig>? returned;
        final observed = outcome == 'throw'
            ? expectLater(result, throwsA(same(prefsBackend.failure)))
            : result.then<void>((value) {
                returned = value;
              });
        await prefsBackend.entered.future.timeout(_limit);
        input.add(_config('after'));
        prefsBackend.release.complete();
        await observed;
        if (returned != null) {
          expect(returned!.map((e) => e.id), ['before', 'after']);
          expect(
            () => returned!.add(_config('rejected')),
            throwsUnsupportedError,
          );
        }
        final durable = await prefsBackend.durable();
        expect(durable.containsKey('flutter.$_key'), outcome == 'ok');
        // SDK updates its cached list before platform completion, even on false/throw.
        expect(
          (await StorageService.getIndexerManagerConfigs()).map((e) => e.id),
          ['before'],
        );
      },
    );
  }

  test(
    'canonical both types return stable current authority and fixed-length readback',
    () async {
      await canonical();
      final input = [
        _config('a'),
        _config('b', type: IndexerManagerType.prowlarr),
      ];
      final saved = await StorageService.setIndexerManagerConfigs(input);
      expect(
        saved.map((e) => e.type).toSet(),
        IndexerManagerType.values.toSet(),
      );
      expect(
        saved.every(
          (e) =>
              e.id == e.connectionResourceId &&
              e.connectionResourceRevision != null,
        ),
        isTrue,
      );
      expect(() => saved.add(_config('no')), throwsUnsupportedError);
      final first = saved.first;
      final updated = await StorageService.setIndexerManagerConfigs([
        for (final e in saved) e.copyWith(maxResults: 77),
      ]);
      final current = updated.singleWhere((e) => e.id == first.id);
      expect(
        current.connectionResourceRevision!,
        greaterThan(first.connectionResourceRevision!),
      );
      expect(current.maxResults, 77);
      await ProfileCollectionResourceFacade.authorizeExecution(
        resourceId: current.connectionResourceId,
        resourceRevision: current.connectionResourceRevision,
        acceptedTypes: {
          ConnectionResourceType.jackett,
          ConnectionResourceType.prowlarr,
        },
        feature: ProfileFeature.torrentSearch,
      );
      expect(
        (await prefsBackend.durable()).containsKey('flutter.$_key'),
        isFalse,
      );
    },
  );

  test(
    'canonical default settings redact borrower; execution and remote obey different grants',
    () async {
      await canonical();
      final resource = await create('shared');
      final service = ConnectionResourceService(
        registry: registry!,
        cipher: cipher,
      );
      await service.grant(
        actor: await ProfileAuthorizationContext.capture(registry!),
        targetProfileId: member,
        resourceId: resource.id,
        permissions: {ResourcePermission.use},
      );
      publish(member);
      final settings = (await StorageService.getIndexerManagerConfigs()).single;
      expect(
        settings.connectionReadOnly && settings.credentialsRedacted,
        isTrue,
      );
      expect(settings.apiKey.isEmpty && settings.baseUrl.isEmpty, isTrue);
      final operational = (await StorageService.getIndexerManagerConfigs(
        forSettings: false,
      )).single;
      expect(operational.apiKey.isNotEmpty, isTrue);
      expect(
        await StorageService.getIndexerManagerConfigs(forRemoteTransfer: true),
        isEmpty,
      );
      publish(admin);
      await service.grant(
        actor: await ProfileAuthorizationContext.capture(registry!),
        targetProfileId: member,
        resourceId: resource.id,
        permissions: {ResourcePermission.use, ResourcePermission.writeRemote},
      );
      publish(member);
      final remote = (await StorageService.getIndexerManagerConfigs(
        forRemoteTransfer: true,
      )).single;
      expect(remote.apiKey.isNotEmpty, isTrue);
    },
  );

  test(
    'canonical disabled setting hides execution but remains visible in settings',
    () async {
      await canonical();
      final resource = await create('disabled');
      await ProfileCollectionResourceFacade.setLocalEnabled(
        resourceId: resource.id,
        resourceRevision: resource.authorizationRevision,
        feature: ProfileFeature.torrentSearch,
        enabled: false,
      );
      expect(
        await StorageService.getIndexerManagerConfigs(forSettings: false),
        isEmpty,
      );
      expect(
        (await StorageService.getIndexerManagerConfigs()).single.enabled,
        isFalse,
      );
    },
  );

  test('canonical execution requires feature even with a use grant', () async {
    await canonical();
    final actor = await ProfileAuthorizationContext.capture(registry!);
    final restricted = (await registry!.createProfile(
      name: 'Restricted',
      actingProfileId: actor.profileId,
      actingAuthorizationRevision: actor.authorizationRevision,
      actingSessionEpoch: actor.sessionEpoch,
      role: UserProfileRole.member,
      policy: const ProfilePolicy(enabled: {}),
    )).id;
    final resource = await create('feature');
    await ConnectionResourceService(registry: registry!, cipher: cipher).grant(
      actor: await ProfileAuthorizationContext.capture(registry!),
      targetProfileId: restricted,
      resourceId: resource.id,
      permissions: {ResourcePermission.use},
    );
    publish(restricted);
    await expectLater(
      StorageService.getIndexerManagerConfigs(forSettings: false),
      throwsA(isA<ResourceAuthorizationException>()),
    );
  });

  test(
    'canonical malformed model propagates instead of falling back to legacy',
    () async {
      install({
        _key: [jsonEncode(_config('legacy').toJson())],
      });
      await canonical();
      await create('malformed', malformed: true);
      await expectLater(
        StorageService.getIndexerManagerConfigs(),
        throwsA(isA<TypeError>()),
      );
      expect(prefsBackend.writes, 0);
    },
  );

  for (final saving in [false, true]) {
    test(
      'canonical held ${saving ? 'save' : 'read'} cannot return across session change',
      () async {
        await canonical();
        await create('existing');
        final gate = _HeldCipher(cipher, sealFirst: saving);
        held.add(gate);
        DeviceKeyProvider.debugInstallCipher(gate);
        final result = saving
            ? StorageService.setIndexerManagerConfigs([_config('new')])
            : StorageService.getIndexerManagerConfigs();
        final observed = expectLater(
          result,
          throwsA(
            anyOf(isA<StateError>(), isA<ResourceAuthorizationException>()),
          ),
        );
        await gate.entered.future.timeout(_limit);
        publish(member);
        gate.release.complete();
        await observed;
        expect(prefsBackend.writes, 0);
      },
    );
  }
}
