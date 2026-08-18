import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:debrify/services/profiles/connection_resource_service.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/profiles/native_profile_projection.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_lock_controller.dart';
import 'package:debrify/services/profiles/profile_native_lock_bridge.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory temporaryDirectory;
  late ProfileRegistry registry;
  late String adminId;
  late ProfileScope scope;
  late MemoryDeviceSecretCipher cipher;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    NativeProfileProjection.debugAfterInvalidation = null;
    NativeProfileProjection.debugBeforeAddonRead = null;
    ProfileNativeLockBridge.debugReset();
    ProfileLockController.instance.dispose();
    ProfileRuntime.debugReset();
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'native-profile-projection-test-',
    );
    registry = await ProfileRegistry.open(
      path: p.join(temporaryDirectory.path, 'profiles.db'),
    );
    adminId = (await registry.createProfile(
      name: 'Admin',
      role: UserProfileRole.admin,
    )).id;
    await registry.commitBootstrap(
      activeProfileId: adminId,
      migratedLegacyInstall: false,
    );
    ProfileBootstrap.debugInstallRegistry(registry);
    cipher = MemoryDeviceSecretCipher(List<int>.generate(32, (i) => i + 17));
    await cipher.initialize();
    DeviceKeyProvider.debugInstallCipher(cipher);
    scope = ProfileScope(
      profileId: adminId,
      dataGeneration: 1,
      sessionEpoch: 1,
    );
    ProfileRuntime.initializeCommitted(scope);
  });

  tearDown(() async {
    NativeProfileProjection.debugAfterInvalidation = null;
    NativeProfileProjection.debugBeforeAddonRead = null;
    ProfileNativeLockBridge.debugReset();
    ProfileLockController.instance.dispose();
    await NativeProfileProjection.clear();
    ProfileRuntime.debugReset();
    ProfileBootstrap.debugInstallRegistry(null);
    DeviceKeyProvider.debugReset();
    await registry.close();
    await temporaryDirectory.delete(recursive: true);
  });

  test(
    'lock, unlock, and unlocked disposal synchronize native authority',
    () async {
      final profile = (await registry.getProfile(adminId))!;
      ProfileNativeLockBridge.initialize();

      ProfileLockController.instance.activate(profile, unlocked: false);
      await ProfileNativeLockBridge.debugSynchronize();
      var prefs = await SharedPreferences.getInstance();
      var projection =
          jsonDecode(prefs.getString(NativeProfileProjection.deviceKey)!)
              as Map<String, dynamic>;
      expect(projection['state'], 'denied');

      ProfileLockController.instance.unlock(profile);
      await ProfileNativeLockBridge.debugSynchronize();
      prefs = await SharedPreferences.getInstance();
      projection =
          jsonDecode(prefs.getString(NativeProfileProjection.deviceKey)!)
              as Map<String, dynamic>;
      expect(projection['state'], 'active');
      expect(projection['profileId'], adminId);

      // Disposal clears an already-null lockedProfileId, so the explicit
      // authority revision—not ValueNotifier equality—must drive revocation.
      ProfileLockController.instance.dispose();
      await ProfileNativeLockBridge.debugSynchronize();
      prefs = await SharedPreferences.getInstance();
      projection =
          jsonDecode(prefs.getString(NativeProfileProjection.deviceKey)!)
              as Map<String, dynamic>;
      expect(projection['state'], 'denied');
    },
  );

  test(
    'native preference writes refresh the active projection immediately',
    () async {
      final profile = (await registry.getProfile(adminId))!;
      ProfileLockController.instance.activate(profile, unlocked: true);
      ProfileNativeLockBridge.initialize();
      await NativeProfileProjection.publish(scope);

      final profilePrefs = await ProfilePreferences.instance();
      await profilePrefs.setString('player_default_subtitle_language', 'es');
      await profilePrefs.setString('player_default_audio_language', 'ja');
      await profilePrefs.setInt('subtitle_color_index', 3);
      await profilePrefs.setBool('subtitle_bold', true);
      await profilePrefs.setString('subtitle_selected_font_id', 'roboto');

      final prefs = await SharedPreferences.getInstance();
      var projection =
          jsonDecode(prefs.getString(NativeProfileProjection.deviceKey)!)
              as Map<String, dynamic>;
      var values = projection['values'] as Map<String, dynamic>;
      expect(values['player_default_subtitle_language'], 'es');
      expect(values['player_default_audio_language'], 'ja');
      expect(values['subtitle_color_index'], 3);
      expect(values['subtitle_bold'], isTrue);
      expect(values['subtitle_selected_font_id'], 'roboto');

      await profilePrefs.remove('player_default_subtitle_language');
      projection =
          jsonDecode(prefs.getString(NativeProfileProjection.deviceKey)!)
              as Map<String, dynamic>;
      values = projection['values'] as Map<String, dynamic>;
      expect(values, isNot(contains('player_default_subtitle_language')));
      expect(values['player_default_audio_language'], 'ja');
    },
  );

  test('a profile switch cannot relabel an in-flight addon read', () async {
    final actor = await ProfileAuthorizationContext.capture(registry);
    await ConnectionResourceService(registry: registry, cipher: cipher).create(
      context: actor,
      type: ConnectionResourceType.stremioAddon,
      label: 'Admin subtitles',
      publicConfig: const <String, dynamic>{'addonName': 'Admin subtitles'},
      secretConfig: const <String, dynamic>{
        'id': 'admin.subtitles',
        'name': 'Admin subtitles',
        'base_url': 'https://admin-subtitles.invalid',
        'resources': <String>['subtitles'],
        'enabled': true,
      },
    );
    final manager = await ProfileAuthorizationContext.capture(registry);
    final member = await registry.createProfile(
      name: 'Member',
      role: UserProfileRole.member,
      actingProfileId: manager.profileId,
      actingAuthorizationRevision: manager.authorizationRevision,
      actingSessionEpoch: manager.sessionEpoch,
    );
    await NativeProfileProjection.publish(scope);
    final prefs = await SharedPreferences.getInstance();
    final before = prefs.getString(NativeProfileProjection.deviceKey);
    final readStarted = Completer<void>();
    final releaseRead = Completer<void>();
    NativeProfileProjection.debugBeforeAddonRead = () async {
      readStarted.complete();
      await releaseRead.future;
    };

    final publishing = NativeProfileProjection.publish(scope);
    await readStarted.future;
    ProfileRuntime.publish(
      ProfileScope(
        profileId: member.id,
        dataGeneration: member.visibleDataGeneration,
        sessionEpoch: 2,
      ),
    );
    releaseRead.complete();

    await expectLater(publishing, throwsStateError);
    expect(
      prefs.getString(NativeProfileProjection.deviceKey),
      before,
      reason: 'the old scope must never publish data after the switch',
    );
  });

  test('projects migrated subtitle addons from connection resources', () async {
    final actor = await ProfileAuthorizationContext.capture(registry);
    await ConnectionResourceService(registry: registry, cipher: cipher).create(
      context: actor,
      type: ConnectionResourceType.stremioAddon,
      label: 'OpenSubtitles v3',
      publicConfig: const <String, dynamic>{
        'addonName': 'OpenSubtitles v3',
        'contentKinds': <String>['movie', 'series'],
      },
      secretConfig: const <String, dynamic>{
        'id': 'org.stremio.opensubtitlesv3',
        'name': 'OpenSubtitles v3',
        'manifest_url': 'https://opensubtitles-v3.strem.io/manifest.json',
        'base_url': 'https://opensubtitles-v3.strem.io',
        'resources': <String>['subtitles'],
        'types': <String>['movie', 'series'],
        'enabled': true,
      },
    );

    await NativeProfileProjection.publish(scope);

    final prefs = await SharedPreferences.getInstance();
    final projection =
        jsonDecode(prefs.getString(NativeProfileProjection.deviceKey)!)
            as Map<String, dynamic>;
    final values = projection['values'] as Map<String, dynamic>;
    final addons = jsonDecode(values['stremio_addons_v1'] as String) as List;
    expect(addons, hasLength(1));
    // Profile collections expose their stable connection-resource id as the
    // compatibility model id; native only needs a stable grouping id here.
    expect(addons.single['id'], startsWith('resource-'));
    expect(
      addons.single['manifest_url'],
      'https://opensubtitles-v3.strem.io/manifest.json',
    );
    expect(addons.single['resources'], contains('subtitles'));
    expect(addons.single['enabled'], isTrue);
  });

  test('projects URL-only restored addons for native hydration', () async {
    final actor = await ProfileAuthorizationContext.capture(registry);
    await ConnectionResourceService(registry: registry, cipher: cipher).create(
      context: actor,
      type: ConnectionResourceType.stremioAddon,
      label: 'Restored addon',
      publicConfig: const <String, dynamic>{
        'addonName': 'Restored addon',
        'contentKinds': <String>[],
      },
      secretConfig: const <String, dynamic>{
        'manifestUrl': 'https://subtitles.invalid/config/manifest.json',
      },
    );

    await NativeProfileProjection.publish(scope);

    final prefs = await SharedPreferences.getInstance();
    final projection =
        jsonDecode(prefs.getString(NativeProfileProjection.deviceKey)!)
            as Map<String, dynamic>;
    final values = projection['values'] as Map<String, dynamic>;
    final addons = jsonDecode(values['stremio_addons_v1'] as String) as List;
    expect(addons, hasLength(1));
    expect(
      addons.single['manifest_url'],
      'https://subtitles.invalid/config/manifest.json',
    );
    expect(addons.single['base_url'], 'https://subtitles.invalid/config');
    expect(addons.single['resources'], isEmpty);
  });

  test(
    'addon denial publishes an empty list without revoking native state',
    () async {
      var actor = await ProfileAuthorizationContext.capture(registry);
      await ConnectionResourceService(
        registry: registry,
        cipher: cipher,
      ).create(
        context: actor,
        type: ConnectionResourceType.stremioAddon,
        label: 'OpenSubtitles v3',
        publicConfig: const <String, dynamic>{'addonName': 'OpenSubtitles v3'},
        secretConfig: const <String, dynamic>{
          'id': 'org.stremio.opensubtitlesv3',
          'name': 'OpenSubtitles v3',
          'base_url': 'https://opensubtitles-v3.strem.io',
          'resources': <String>['subtitles'],
          'enabled': true,
        },
      );
      final profilePrefs = await ProfilePreferences.instance();
      await profilePrefs.setInt('player_night_mode_index', 2);
      actor = await ProfileAuthorizationContext.capture(registry);
      final current = (await registry.getProfile(adminId))!;
      await registry.updateProfile(
        id: adminId,
        policy: ProfilePolicy(
          enabled: current.policy.enabled
              .where((feature) => feature != ProfileFeature.addonUse)
              .toSet(),
        ),
        actingProfileId: actor.profileId,
        actingAuthorizationRevision: actor.authorizationRevision,
        actingSessionEpoch: actor.sessionEpoch,
      );

      await NativeProfileProjection.publish(scope);

      final prefs = await SharedPreferences.getInstance();
      final projection =
          jsonDecode(prefs.getString(NativeProfileProjection.deviceKey)!)
              as Map<String, dynamic>;
      final values = projection['values'] as Map<String, dynamic>;
      expect(projection['state'], 'active');
      expect(values['player_night_mode_index'], 2);
      expect(jsonDecode(values['stremio_addons_v1'] as String), isEmpty);
    },
  );

  test(
    'failed post-mutation publication leaves native authority denied',
    () async {
      await NativeProfileProjection.publish(scope);
      registry.authorityWillChangeCallback = NativeProfileProjection.invalidate;
      registry.authorityChangedCallback = () =>
          NativeProfileProjection.publish(scope);
      NativeProfileProjection.debugAfterInvalidation = (_) async {
        throw StateError('injected publication failure');
      };
      final actor = await ProfileAuthorizationContext.capture(registry);

      await expectLater(
        registry.updateProfile(
          id: adminId,
          name: 'Changed',
          actingProfileId: actor.profileId,
          actingAuthorizationRevision: actor.authorizationRevision,
          actingSessionEpoch: actor.sessionEpoch,
        ),
        throwsStateError,
      );

      final prefs = await SharedPreferences.getInstance();
      final sequence = prefs.getInt(NativeProfileProjection.sequenceKey);
      final projection =
          jsonDecode(prefs.getString(NativeProfileProjection.deviceKey)!)
              as Map<String, dynamic>;
      expect((await registry.getProfile(adminId))!.name, 'Changed');
      expect(projection['state'], 'denied');
      expect(projection['publication'], isNot(sequence));
    },
  );

  test('an older delayed build cannot overwrite a newer snapshot', () async {
    final firstInvalidated = Completer<void>();
    final releaseFirst = Completer<void>();
    var calls = 0;
    NativeProfileProjection.debugAfterInvalidation = (_) async {
      calls++;
      if (calls == 1) {
        firstInvalidated.complete();
        await releaseFirst.future;
      }
    };

    final older = NativeProfileProjection.publish(scope);
    await firstInvalidated.future;
    final actor = await ProfileAuthorizationContext.capture(registry);
    final updated = await registry.updateProfile(
      id: adminId,
      name: 'Newer',
      actingProfileId: actor.profileId,
      actingAuthorizationRevision: actor.authorizationRevision,
      actingSessionEpoch: actor.sessionEpoch,
    );
    final newer = NativeProfileProjection.publish(scope);
    releaseFirst.complete();
    await Future.wait(<Future<void>>[older, newer]);

    final prefs = await SharedPreferences.getInstance();
    final sequence = prefs.getInt(NativeProfileProjection.sequenceKey);
    final projection =
        jsonDecode(prefs.getString(NativeProfileProjection.deviceKey)!)
            as Map<String, dynamic>;
    final authorization = projection['authorization'] as Map<String, dynamic>;
    final active = authorization[adminId] as Map<String, dynamic>;
    expect(projection['state'], 'active');
    expect(projection['publication'], sequence);
    expect(active['revision'], updated.authorizationRevision);
  });
}
