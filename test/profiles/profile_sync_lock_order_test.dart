import 'dart:async';
import 'dart:io';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'registry deletion waits outside SQLite while a sync snapshot reads',
    () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      SharedPreferences.setMockInitialValues({});
      final dir = await Directory.systemTemp.createTemp('loading-review-');
      final registry = await ProfileRegistry.open(
        path: '${dir.path}/profiles.db',
      );
      final admin = await registry.createProfile(
        name: 'Admin',
        role: UserProfileRole.admin,
      );
      final profile = await registry.createProfile(
        name: 'Member',
        role: UserProfileRole.member,
      );
      await registry.commitBootstrap(
        activeProfileId: admin.id,
        migratedLegacyInstall: false,
      );
      ProfileRuntime.initializeCommitted(
        ProfileScope(profileId: admin.id, dataGeneration: 1, sessionEpoch: 1),
      );
      final actor = await ProfileAuthorizationContext.capture(registry);
      final held = Completer<void>();
      final queryNow = Completer<void>();
      var deletionFinished = false;
      var readTimedOut = false;
      final snapshot = ProfilePreferences.captureMutationSnapshot((_) async {
        held.complete();
        await queryNow.future;
        try {
          await registry.listProfiles().timeout(
            const Duration(milliseconds: 300),
          );
        } on TimeoutException {
          readTimedOut = true;
        }
      });
      await held.future;
      final deletion = registry
          .deleteProfileWithDisposition(
            id: profile.id,
            deleteOwnedResources: true,
            detachPublicArtifacts: true,
            actingProfileId: actor.profileId,
            actingAuthorizationRevision: actor.authorizationRevision,
            actingSessionEpoch: actor.sessionEpoch,
          )
          .then((_) => deletionFinished = true);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(deletionFinished, isFalse);
      queryNow.complete();
      await snapshot;
      expect(
        readTimedOut,
        isFalse,
        reason: 'Waiting for sync must not hold the registry transaction.',
      );
      await deletion.timeout(const Duration(seconds: 3));
      expect(deletionFinished, isTrue);
      await registry.close();
      await dir.delete(recursive: true);
      ProfileRuntime.debugReset();
    },
  );
}
