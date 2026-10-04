import 'dart:async';
import 'dart:io';

import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/services/engine/local_engine_storage.dart';
import 'package:debrify/services/profiles/connection_resource_service.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

import 'addon_hub_fixture.dart';

class AddonHubProfiles {
  AddonHubProfiles(this.fixture);
  final AddonHubFixture fixture;
  late ProfileScope a;
  late ProfileScope b;
  Future<void> open({bool seed = false}) async {
    a = ProfileRuntime.capture();
    final p = fixture.profiles!;
    final admin = (await p.registry.getProfile(p.a))!;
    final second = await p.registry.createProfile(
      name: 'B',
      role: UserProfileRole.admin,
      actingProfileId: p.a,
      actingAuthorizationRevision: admin.authorizationRevision,
      actingSessionEpoch: a.sessionEpoch,
    );
    b = ProfileScope(profileId: second.id, dataGeneration: 1, sessionEpoch: 2);
    if (seed) {
      fixture.setup = true;
      try {
        for (final addon in fixture.installed) {
          await StremioService.instance.addAddon(addon.manifestUrl);
        }
      } finally {
        fixture.setup = false;
      }
    }
    fixture.sync.clear();
  }

  Future<void> publish(ProfileScope scope) async {
    await fixture.profiles!.registry.setActiveProfile(scope.profileId);
    ProfileRuntime.publish(scope);
    LocalEngineStorage.instance.resetProfileScope();
    StremioService.instance.invalidateCache();
  }

  Future<void> grantFirst() async {
    final addon = (await StremioService.instance.getAddonsForManagement())
        .singleWhere((e) => e.name == 'Zulu');
    final p = fixture.profiles!;
    await ConnectionResourceService(
      registry: p.registry,
      cipher: p.cipher,
    ).grant(
      actor: await ProfileAuthorizationContext.capture(p.registry),
      targetProfileId: b.profileId,
      resourceId: addon.storageKey,
      permissions: {ResourcePermission.use},
    );
  }

  Future<List<String>> engineIds(ProfileScope scope) async {
    final path = scope.storageDirectory(fixture.profiles!.root, 'documents');
    return (await LocalEngineStorage.forDirectory(
      Directory('${path.path}/engines'),
    ).getImportedEngines()).map((e) => e.id).toList();
  }

  Future<List<String>> addonIds(ProfileScope scope) async =>
      (await fixture.profiles!.registry.listGrantedResources(scope.profileId))
          .where((e) => e.type == ConnectionResourceType.stremioAddon)
          .map((e) => e.label)
          .toList();
}

class AddonHubHeldPreferences extends InMemorySharedPreferencesStore {
  AddonHubHeldPreferences(super.values) : super.withData();
  Completer<void>? read;
  Completer<void>? write;
  String? failKey;
  final reads = <String>[];
  final writes = <(String, Object)>[];
  @override
  Future<Map<String, Object>> getAllWithParameters(GetAllParameters p) async {
    reads.add('getAll');
    final snapshot = await super.getAllWithParameters(p);
    await read?.future;
    return snapshot;
  }

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    writes.add((key, value));
    await write?.future;
    if (key.endsWith(failKey ?? '\u0000')) {
      throw StateError('fixture rejected write');
    }
    return super.setValue(type, key, value);
  }

  static Future<AddonHubHeldPreferences> install() async {
    final prefs = await SharedPreferences.getInstance();
    final store = AddonHubHeldPreferences({
      for (final key in prefs.getKeys()) 'flutter.$key': prefs.get(key)!,
    });
    SharedPreferencesStorePlatform.instance = store;
    return store;
  }
}
