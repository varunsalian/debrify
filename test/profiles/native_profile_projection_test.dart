import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/services/profiles/native_profile_projection.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
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

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    NativeProfileProjection.debugAfterInvalidation = null;
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
    scope = ProfileScope(
      profileId: adminId,
      dataGeneration: 1,
      sessionEpoch: 1,
    );
    ProfileRuntime.initializeCommitted(scope);
  });

  tearDown(() async {
    NativeProfileProjection.debugAfterInvalidation = null;
    await NativeProfileProjection.clear();
    ProfileRuntime.debugReset();
    ProfileBootstrap.debugInstallRegistry(null);
    await registry.close();
    await temporaryDirectory.delete(recursive: true);
  });

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
