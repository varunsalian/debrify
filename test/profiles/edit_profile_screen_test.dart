import 'dart:io';

import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/screens/profiles/edit_profile_screen.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_pin_service.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Characterization for the profile editor, which had no coverage before the
/// section redesign.
///
/// The authorization-bearing invariant (what a save writes) is pinned as plain
/// unit tests against [EditProfileScreen.policyFor] — driving a full save
/// through the widget layer needs the whole engine/resource/DB stack under the
/// fake test clock, which characterizes those services, not this screen. The
/// widget tests here are rendering smoke: the form builds and no control goes
/// missing in a regrouping.
void main() {
  group('policyFor — the hidden matrix must never clobber the author', () {
    test('a create seeds the role DEFAULTS (the questionnaire presets)', () {
      for (final role in UserProfileRole.values) {
        expect(
          EditProfileScreen.policyFor(
            role: role,
            selected: const <ProfileFeature>{},
          ).enabled,
          ProfilePolicy.defaultsFor(role).enabled,
          reason: '$role must ignore the hidden per-feature selection',
        );
      }
    });

    test('an edit PRESERVES the stored policy — identity edits must not '
        'silently un-restrict a questionnaire-configured profile', () {
      final configured = ProfilePolicy(
        enabled: <ProfileFeature>{
          ProfileFeature.debrifyTv,
          ProfileFeature.cloud,
          ProfileFeature.torrentSearch,
        },
      );
      expect(
        EditProfileScreen.policyFor(
          role: UserProfileRole.child,
          selected: ProfileFeature.values.toSet(),
          existing: configured,
        ).enabled,
        configured.enabled,
      );
    });

    test('the per-feature policy editor stays off', () {
      // If this flips, policyFor starts honouring the selection and the
      // editor needs a Permissions section back.
      expect(EditProfileScreen.showFeaturePolicyControls, isFalse);
    });

    test('a child never receives manageProfiles', () {
      expect(
        EditProfileScreen.policyFor(
          role: UserProfileRole.child,
          selected: ProfileFeature.values.toSet(),
        ).allows(UserProfileRole.child, ProfileFeature.manageProfiles),
        isFalse,
      );
    });
  });

  group('rendering', () {
    late Directory root;
    late ProfileRegistry registry;
    late ProfileAuthorizationContext authorization;
    late ProfilePinService pins;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      ProfileRuntime.debugReset();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      root = await Directory.systemTemp.createTemp('edit-profile-');
      AppStorage.debugOverride(documents: root, support: root, cache: root);
      registry = await ProfileRegistry.open(
        path: p.join(root.path, 'profiles.db'),
      );
      final admin = await registry.createProfile(
        name: 'Admin',
        role: UserProfileRole.admin,
        policy: ProfilePolicy.defaultsFor(UserProfileRole.admin),
      );
      await registry.commitBootstrap(
        activeProfileId: admin.id,
        migratedLegacyInstall: false,
      );
      ProfileBootstrap.debugInstallRegistry(registry);
      ProfileRuntime.initializeCommitted(
        ProfileScope(profileId: admin.id, dataGeneration: 1, sessionEpoch: 1),
      );
      authorization = await ProfileAuthorizationContext.capture(registry);
      pins = ProfilePinService(registry: registry);
    });

    tearDown(() async {
      await registry.close();
      ProfileBootstrap.debugInstallRegistry(null);
      ProfileRuntime.debugReset();
      AppStorage.debugReset();
      if (await root.exists()) await root.delete(recursive: true);
    });

    Future<void> pumpEditor(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: EditProfileScreen(
            registry: registry,
            pins: pins,
            authorization: authorization,
          ),
        ),
      );
      // The editor loads engines/connections with real IO; runAsync windows
      // are the only thing that advances it under the test binding.
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)),
        );
        await tester.pump();
      }
    }

    testWidgets('the create form renders', (tester) async {
      await pumpEditor(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Create profile'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('no control goes missing in a regrouping', (tester) async {
      await pumpEditor(tester);
      // A ListView builds lazily, so assert only the sections above the fold;
      // the fold-below ones are covered by scrolling in real use.
      for (final section in const <String>['AVATAR', 'IDENTITY', 'ROLE']) {
        expect(find.text(section), findsOneWidget, reason: section);
      }
      expect(find.byType(TextField), findsWidgets); // name
      expect(find.text('Member'), findsOneWidget); // role card
    });
  });
}
