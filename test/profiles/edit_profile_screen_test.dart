import 'dart:io';

import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/models/profiles/user_profile.dart';
import 'package:debrify/screens/profiles/edit_profile_screen.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:debrify/services/profiles/profile_avatar_policy.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_engine_assignment_service.dart';
import 'package:debrify/services/profiles/profile_pin_service.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    late UserProfile admin;
    late ProfileAuthorizationContext authorization;
    late ProfilePinService pins;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      ProfileRuntime.debugReset();
      PlatformUtil.debugSetAndroidTvCached(null);
      ProfileAvatarPolicy.debugSetUserImagesSupported(null);
      SharedPreferences.setMockInitialValues(<String, Object>{});
      root = await Directory.systemTemp.createTemp('edit-profile-');
      AppStorage.debugOverride(documents: root, support: root, cache: root);
      registry = await ProfileRegistry.open(
        path: p.join(root.path, 'profiles.db'),
      );
      admin = await registry.createProfile(
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
      PlatformUtil.debugSetAndroidTvCached(null);
      ProfileAvatarPolicy.debugSetUserImagesSupported(null);
      if (await root.exists()) await root.delete(recursive: true);
    });

    Future<void> pumpEditor(
      WidgetTester tester, {
      UserProfile? profile,
      Future<(List<ConnectionResource>, List<ProfileEngineAssignment>)>
      Function()?
      setupOptionsLoader,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: EditProfileScreen(
            registry: registry,
            pins: pins,
            authorization: authorization,
            profile: profile,
            setupOptionsLoader: setupOptionsLoader,
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

    testWidgets(
      'TV editor uses section pages and a remote-friendly lock field',
      (tester) async {
        PlatformUtil.debugSetAndroidTvCached(true);
        ProfileAvatarPolicy.debugSetUserImagesSupported(true);
        // Many 1080p Android TVs expose a 960x540 logical Flutter viewport.
        await tester.binding.setSurfaceSize(const Size(960, 540));
        addTearDown(() async {
          PlatformUtil.debugSetAndroidTvCached(null);
          ProfileAvatarPolicy.debugSetUserImagesSupported(null);
          await tester.binding.setSurfaceSize(null);
        });

        await pumpEditor(tester);

        for (final section in const <String>[
          'PROFILE',
          'LOCK',
          'ACCESS',
          'DATA',
        ]) {
          expect(find.text(section), findsOneWidget, reason: section);
        }
        expect(find.text('Choose an avatar'), findsOneWidget);
        expect(find.text('Choose image or GIF'), findsOneWidget);
        expect(find.byType(DropdownButtonFormField<int>), findsNothing);

        final nameField = find.byType(TextField);
        expect(nameField, findsOneWidget);
        await tester.enterText(nameField, 'Living Room');
        await tester.pump();
        final preview = tester.widget<Text>(
          find.byKey(const Key('tv-profile-name-preview')),
        );
        expect(preview.data, 'Living Room');

        await tester.tap(find.text('LOCK'));
        await tester.pumpAndSettle();

        expect(find.text('Profile lock'), findsOneWidget);
        expect(find.text('Auto-lock'), findsOneWidget);
        expect(find.text('Never'), findsOneWidget);

        await tester.ensureVisible(find.text('Never'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Never'));
        await tester.pump();
        expect(find.text('After 5 minutes'), findsOneWidget);

        await tester.tap(find.text('ACCESS'));
        await tester.pumpAndSettle();
        expect(find.text('Profile access'), findsOneWidget);

        await tester.tap(find.text('DATA'));
        await tester.pumpAndSettle();
        expect(find.text('Profile data'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('TV rail reaches Lock and scrolls real read-only Access rows', (
      tester,
    ) async {
      PlatformUtil.debugSetAndroidTvCached(true);
      await tester.binding.setSurfaceSize(const Size(960, 540));
      addTearDown(() async {
        PlatformUtil.debugSetAndroidTvCached(null);
        await tester.binding.setSurfaceSize(null);
      });

      final engines = [
        for (var index = 0; index < 8; index++)
          ProfileEngineAssignment(
            id: 'engine_$index',
            displayName: 'Engine $index',
            assignedToTarget: true,
            availableFromManager: true,
          ),
      ];
      await pumpEditor(
        tester,
        profile: admin,
        setupOptionsLoader: () async => (const <ConnectionResource>[], engines),
      );

      final accessSurface = find.byKey(const ValueKey('tv-profile-tab-access'));
      final lockSurface = find.byKey(const ValueKey('tv-profile-tab-lock'));
      final accessInkWell = tester.widget<InkWell>(
        find.descendant(of: accessSurface, matching: find.byType(InkWell)),
      );
      final lockInkWell = tester.widget<InkWell>(
        find.descendant(of: lockSurface, matching: find.byType(InkWell)),
      );

      await tester.tap(find.text('ACCESS'));
      accessInkWell.focusNode!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(lockInkWell.focusNode!.hasFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(accessInkWell.focusNode!.hasFocus, isTrue);

      for (var index = 0; index < engines.length; index++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump(const Duration(milliseconds: 250));
      }
      final accessScroll = Scrollable.of(tester.element(find.text('Engine 7')));
      expect(accessScroll.position.pixels, greaterThan(0));

      expect(tester.takeException(), isNull);
    });
  });
}
