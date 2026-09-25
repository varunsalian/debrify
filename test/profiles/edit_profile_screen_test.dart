import 'dart:async';
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
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/widgets/tv_text_field.dart';
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
/// widget tests cover rendering and remote navigation through the actual TV
/// controls, including both keyboard modes and compact/full-HD layouts.
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

    test('the per-feature policy editor stays off on the phone form', () {
      // If this flips, policyFor starts honouring the selection and the
      // editor needs a Permissions section back.
      expect(EditProfileScreen.showFeaturePolicyControls, isFalse);
    });

    test('a touched Pages editor writes the selection (controlsShown)', () {
      // The TV Pages section passes controlsShown once the user actually
      // toggles something — only then does the selection become the author.
      final selection = <ProfileFeature>{
        ProfileFeature.cloud,
        ProfileFeature.debrifyTv,
      };
      expect(
        EditProfileScreen.policyFor(
          role: UserProfileRole.member,
          selected: selection,
          existing: ProfilePolicy.defaultsFor(UserProfileRole.member),
          controlsShown: true,
        ).enabled,
        selection,
      );
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
          // Match the app-level remote OK bindings in main.dart, including
          // repeats that stock Material buttons would otherwise activate.
          builder: (context, child) => Shortcuts(
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
              SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
              SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
            },
            child: child!,
          ),
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
      await tester.scrollUntilVisible(
        find.text('Member'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
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
          'PAGES',
          'ACCESS',
          'LOCK',
          'DATA',
        ]) {
          expect(find.text(section), findsOneWidget, reason: section);
        }
        expect(find.text('SAVE'), findsOneWidget);
        expect(find.text('Choose an avatar'), findsOneWidget);
        expect(
          find.text('Choose image or GIF (this device only)'),
          findsOneWidget,
        );
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
        await tester.pumpAndSettle();
        await tester.tap(find.text('After 5 minutes'));
        await tester.pumpAndSettle();
        expect(find.text('After 5 minutes'), findsOneWidget);

        await tester.tap(find.text('ACCESS'));
        await tester.pumpAndSettle();
        expect(find.text('Profile access'), findsOneWidget);

        await tester.tap(find.text('PAGES'));
        await tester.pumpAndSettle();
        expect(find.text('Pages & abilities'), findsOneWidget);
        expect(find.text('Keyword search'), findsOneWidget);

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
      await tester.pumpAndSettle();
      accessInkWell.focusNode!.requestFocus();
      await tester.pump();
      // The rail is vertical now: DOWN reaches the next section, UP returns.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(lockInkWell.focusNode!.hasFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(accessInkWell.focusNode!.hasFocus, isTrue);

      // RIGHT enters the content pane; DOWN then walks the engine rows.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(milliseconds: 250));
      for (var index = 0; index < engines.length; index++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump(const Duration(milliseconds: 250));
      }
      final accessScroll = Scrollable.of(tester.element(find.text('Engine 7')));
      expect(accessScroll.position.pixels, greaterThan(0));

      expect(tester.takeException(), isNull);
    });

    Finder keyed(String key) => find.byKey(ValueKey(key));

    bool focusedWithin(Finder finder) {
      final target = finder.evaluate().single;
      final context = FocusManager.instance.primaryFocus?.context;
      if (context == null) return false;
      var found = identical(context, target);
      context.visitAncestorElements((element) {
        if (identical(element, target)) found = true;
        return !found;
      });
      return found;
    }

    Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }

    Future<void> configureTv(
      WidgetTester tester, {
      bool tvos = false,
      Size size = const Size(960, 540),
    }) async {
      PlatformUtil.debugSetAndroidTvCached(!tvos);
      PlatformUtil.debugSetTvOS(tvos);
      ProfileAvatarPolicy.debugSetUserImagesSupported(false);
      final previousKeyboard = StorageService.tvKeyboardEnabledCached;
      StorageService.tvKeyboardEnabledCached = !tvos;
      await tester.binding.setSurfaceSize(size);
      addTearDown(() async {
        PlatformUtil.debugSetTvOS(null);
        StorageService.tvKeyboardEnabledCached = previousKeyboard;
        await tester.binding.setSurfaceSize(null);
      });
    }

    for (final tvos in [false, true]) {
      for (final size in [const Size(960, 540), const Size(1920, 1080)]) {
        testWidgets(
          '${tvos ? "tvOS" : "Android TV"} D-pad pane round trips at $size',
          (tester) async {
            await configureTv(tester, tvos: tvos, size: size);
            final engines = [
              for (var i = 0; i < 8; i++)
                ProfileEngineAssignment(
                  id: 'engine_$i',
                  displayName: 'Engine $i',
                  assignedToTarget: true,
                  availableFromManager: true,
                ),
            ];
            await pumpEditor(
              tester,
              profile: admin,
              setupOptionsLoader: () async =>
                  (const <ConnectionResource>[], engines),
            );
            await tester.pumpAndSettle();
            expect(focusedWithin(keyed('tv-profile-tab-profile')), isTrue);
            await press(tester, LogicalKeyboardKey.arrowRight);
            expect(
              focusedWithin(keyed('tv-profile-avatar-art:snack_popcorn')),
              isTrue,
            );
            await press(tester, LogicalKeyboardKey.arrowRight);
            expect(
              focusedWithin(keyed('tv-profile-avatar-art:snack_soda')),
              isTrue,
            );
            await press(tester, LogicalKeyboardKey.arrowLeft);
            expect(
              focusedWithin(keyed('tv-profile-avatar-art:snack_popcorn')),
              isTrue,
            );
            await press(tester, LogicalKeyboardKey.arrowLeft);
            expect(focusedWithin(keyed('tv-profile-tab-profile')), isTrue);
            await press(tester, LogicalKeyboardKey.arrowRight);
            expect(
              focusedWithin(keyed('tv-profile-avatar-art:snack_popcorn')),
              isTrue,
            );
            await press(tester, LogicalKeyboardKey.arrowUp);
            expect(
              focusedWithin(keyed('tv-profile-avatar-art:snack_popcorn')),
              isTrue,
            );

            for (
              var i = 0;
              i < 60 && !focusedWithin(keyed('tv-profile-name'));
              i++
            ) {
              await press(tester, LogicalKeyboardKey.arrowDown);
            }
            expect(focusedWithin(keyed('tv-profile-name')), isTrue);
            // tvOS's system field retains caret movement before the left edge.
            final field = tester.widget<TvTextField>(keyed('tv-profile-name'));
            field.controller.selection = const TextSelection.collapsed(
              offset: 0,
            );
            await press(tester, LogicalKeyboardKey.arrowLeft);
            expect(focusedWithin(keyed('tv-profile-tab-profile')), isTrue);
            await press(tester, LogicalKeyboardKey.arrowRight);
            expect(focusedWithin(keyed('tv-profile-name')), isTrue);
            field.controller.selection = const TextSelection.collapsed(
              offset: 0,
            );
            await press(tester, LogicalKeyboardKey.arrowLeft);
            await press(tester, LogicalKeyboardKey.arrowDown);
            expect(focusedWithin(keyed('tv-profile-tab-pages')), isTrue);
            await press(tester, LogicalKeyboardKey.select);
            const features = [
              'keywordSearch',
              'debrifyTv',
              'stremioTv',
              'iptv',
              'youtube',
              'downloads',
              'remoteControl',
              'addonsAndEngines',
              'cloudFiles',
            ];
            for (var i = 0; i < features.length; i++) {
              final tile = keyed('tv-pages-${features[i]}');
              expect(focusedWithin(tile), isTrue, reason: features[i]);
              await press(tester, LogicalKeyboardKey.arrowRight);
              expect(
                focusedWithin(tile),
                isTrue,
                reason: 'right edge ${features[i]}',
              );
              await press(tester, LogicalKeyboardKey.arrowLeft);
              expect(focusedWithin(keyed('tv-profile-tab-pages')), isTrue);
              await press(tester, LogicalKeyboardKey.arrowRight);
              expect(
                focusedWithin(tile),
                isTrue,
                reason: 'restore ${features[i]}',
              );
              await press(tester, LogicalKeyboardKey.arrowDown);
            }
            expect(focusedWithin(keyed('tv-pages-cloudFiles')), isTrue);
            await press(tester, LogicalKeyboardKey.arrowLeft);
            await press(tester, LogicalKeyboardKey.arrowDown);
            expect(focusedWithin(keyed('tv-profile-tab-access')), isTrue);
            await press(tester, LogicalKeyboardKey.arrowRight);
            for (var i = 0; i < engines.length; i++) {
              final row = keyed('tv-profile-engine-engine_$i');
              expect(focusedWithin(row), isTrue, reason: 'read-only Engine $i');
              await press(tester, LogicalKeyboardKey.arrowLeft);
              expect(focusedWithin(keyed('tv-profile-tab-access')), isTrue);
              await press(tester, LogicalKeyboardKey.arrowRight);
              expect(focusedWithin(row), isTrue);
              await press(tester, LogicalKeyboardKey.arrowDown);
            }
            await press(tester, LogicalKeyboardKey.arrowLeft);
            await press(tester, LogicalKeyboardKey.arrowDown);
            expect(focusedWithin(keyed('tv-profile-tab-lock')), isTrue);
            await press(tester, LogicalKeyboardKey.arrowRight);
            expect(focusedWithin(keyed('tv-profile-pin')), isTrue);
            await press(tester, LogicalKeyboardKey.arrowLeft);
            expect(focusedWithin(keyed('tv-profile-tab-lock')), isTrue);
            await press(tester, LogicalKeyboardKey.arrowRight);
            await press(tester, LogicalKeyboardKey.arrowDown);
            await press(tester, LogicalKeyboardKey.arrowDown);
            expect(focusedWithin(keyed('tv-profile-auto-lock')), isTrue);
            await press(tester, LogicalKeyboardKey.arrowLeft);
            expect(focusedWithin(keyed('tv-profile-tab-lock')), isTrue);
            await press(tester, LogicalKeyboardKey.arrowRight);
            expect(focusedWithin(keyed('tv-profile-auto-lock')), isTrue);
            await press(tester, LogicalKeyboardKey.select);
            expect(find.byType(SimpleDialog), findsOneWidget);
            await press(tester, LogicalKeyboardKey.arrowDown);
            await press(tester, LogicalKeyboardKey.select);
            expect(find.byType(SimpleDialog), findsNothing);
            expect(find.text('After 5 minutes'), findsOneWidget);
            expect(focusedWithin(keyed('tv-profile-auto-lock')), isTrue);
            await press(tester, LogicalKeyboardKey.arrowLeft);
            await press(tester, LogicalKeyboardKey.arrowDown);
            expect(focusedWithin(keyed('tv-profile-tab-data')), isTrue);
            await press(tester, LogicalKeyboardKey.arrowRight);
            expect(
              focusedWithin(
                find.ancestor(
                  of: find.text('Diagnostics'),
                  matching: find.byType(InkWell),
                ),
              ),
              isTrue,
            );
            await press(tester, LogicalKeyboardKey.arrowLeft);
            expect(focusedWithin(keyed('tv-profile-tab-data')), isTrue);
            await press(tester, LogicalKeyboardKey.arrowDown);
            expect(focusedWithin(keyed('tv-profile-save')), isTrue);
            await press(tester, LogicalKeyboardKey.arrowDown);
            expect(focusedWithin(keyed('tv-profile-save')), isTrue);
            await press(tester, LogicalKeyboardKey.arrowRight);
            await press(tester, LogicalKeyboardKey.arrowLeft);
            expect(focusedWithin(keyed('tv-profile-tab-data')), isTrue);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }

    testWidgets(
      'held rail arrows visit sections without geometric fallthrough',
      (tester) async {
        await configureTv(tester);
        await pumpEditor(tester);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        for (final tab in ['access', 'lock', 'data']) {
          await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown);
          await tester.pumpAndSettle();
          expect(focusedWithin(keyed('tv-profile-tab-$tab')), isTrue);
        }
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(focusedWithin(keyed('tv-profile-save')), isTrue);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
        await press(tester, LogicalKeyboardKey.arrowUp);
        await press(tester, LogicalKeyboardKey.arrowRight);
        // A new profile has no Data action; focus stays on DATA.
        expect(focusedWithin(keyed('tv-profile-tab-data')), isTrue);
        await press(tester, LogicalKeyboardKey.arrowUp);
        await press(tester, LogicalKeyboardKey.arrowUp);
        await press(tester, LogicalKeyboardKey.arrowRight);
        expect(focusedWithin(keyed('tv-profile-tab-access')), isTrue);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('keyboard arrows and dismissal retain the name field focus', (
      tester,
    ) async {
      await configureTv(tester);
      await pumpEditor(tester);
      await press(tester, LogicalKeyboardKey.arrowRight);
      for (var i = 0; i < 60 && !focusedWithin(keyed('tv-profile-name')); i++) {
        await press(tester, LogicalKeyboardKey.arrowDown);
      }
      await press(tester, LogicalKeyboardKey.select);
      final state = tester.state<TvTextFieldState>(keyed('tv-profile-name'));
      expect(state.debugHasKeyboardOverlay, isTrue);
      for (final key in [
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowDown,
      ]) {
        await press(tester, key);
        expect(focusedWithin(keyed('tv-profile-name')), isTrue);
        expect(state.debugHasKeyboardOverlay, isTrue);
      }
      await press(tester, LogicalKeyboardKey.escape);
      expect(state.debugHasKeyboardOverlay, isFalse);
      expect(focusedWithin(keyed('tv-profile-name')), isTrue);
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(focusedWithin(keyed('tv-profile-tab-profile')), isTrue);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focusedWithin(keyed('tv-profile-name')), isTrue);
      expect(state.debugHasKeyboardOverlay, isFalse);
      expect(tester.takeException(), isNull);
    });

    for (final size in [const Size(960, 540), const Size(1920, 1080)]) {
      testWidgets('all avatar and role rows are reachable at $size', (
        tester,
      ) async {
        await configureTv(tester, size: size);
        await pumpEditor(tester);
        await press(tester, LogicalKeyboardKey.arrowRight);
        final avatarKeys = find
            .byWidgetPredicate(
              (widget) =>
                  widget.key is ValueKey<String> &&
                  (widget.key! as ValueKey<String>).value.startsWith(
                    'tv-profile-avatar-',
                  ),
            )
            .evaluate()
            .map((element) => element.widget.key! as ValueKey<String>)
            .toSet();
        final visited = <ValueKey<String>>{};
        // Sweep each visual row from the left; DOWN retains its column.
        for (
          var row = 0;
          row < 50 && !focusedWithin(keyed('tv-profile-name'));
          row++
        ) {
          for (var column = 0; column < avatarKeys.length; column++) {
            visited.addAll(
              avatarKeys.where((key) => focusedWithin(find.byKey(key))),
            );
            final before = FocusManager.instance.primaryFocus;
            await press(tester, LogicalKeyboardKey.arrowRight);
            if (FocusManager.instance.primaryFocus == before) break;
          }
          for (var column = 0; column < avatarKeys.length; column++) {
            final primary = FocusManager.instance.primaryFocus;
            final currentKey = avatarKeys.firstWhere(
              (key) => focusedWithin(find.byKey(key)),
            );
            final rect = tester.getRect(find.byKey(currentKey));
            final sameRowToLeft = avatarKeys.any((key) {
              final other = tester.getRect(find.byKey(key));
              return other.center.dx < rect.center.dx - 1 &&
                  (other.center.dy - rect.center.dy).abs() < 10;
            });
            if (!sameRowToLeft) break;
            await press(tester, LogicalKeyboardKey.arrowLeft);
            expect(FocusManager.instance.primaryFocus, isNot(primary));
          }
          await press(tester, LogicalKeyboardKey.arrowDown);
        }
        expect(visited, avatarKeys);
        expect(focusedWithin(keyed('tv-profile-name')), isTrue);
        await press(tester, LogicalKeyboardKey.arrowDown);
        // Wide layouts enter the middle role under the full-width name field.
        if (size.width > 1000) {
          await press(tester, LogicalKeyboardKey.arrowLeft);
        }
        expect(focusedWithin(keyed('tv-profile-role-admin')), isTrue);
        for (final role in ['member', 'child']) {
          await press(
            tester,
            size.width > 1000
                ? LogicalKeyboardKey.arrowRight
                : LogicalKeyboardKey.arrowDown,
          );
          expect(focusedWithin(keyed('tv-profile-role-$role')), isTrue);
        }
        await press(tester, LogicalKeyboardKey.select);
        expect(find.text('Kid'), findsNWidgets(2));
        await press(tester, LogicalKeyboardKey.arrowDown);
        final copyDefaults = find.ancestor(
          of: find.text('Copy appearance and playback defaults'),
          matching: find.byType(SwitchListTile),
        );
        expect(focusedWithin(copyDefaults), isTrue);
        await press(tester, LogicalKeyboardKey.select);
        expect(tester.widget<SwitchListTile>(copyDefaults).value, isFalse);
        await press(tester, LogicalKeyboardKey.arrowDown);
        expect(focusedWithin(copyDefaults), isTrue);
        await press(tester, LogicalKeyboardKey.arrowLeft);
        expect(focusedWithin(keyed('tv-profile-tab-profile')), isTrue);
        await press(tester, LogicalKeyboardKey.arrowRight);
        expect(focusedWithin(copyDefaults), isTrue);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets(
      'editable Access reaches All, None, rows and ownership action',
      (tester) async {
        await configureTv(tester);
        final member = await tester.runAsync(
          () => registry.createProfile(
            name: 'Member',
            actingProfileId: authorization.profileId,
            actingAuthorizationRevision: authorization.authorizationRevision,
            actingSessionEpoch: authorization.sessionEpoch,
            role: UserProfileRole.member,
            policy: ProfilePolicy.allAllowedFor(UserProfileRole.member),
          ),
        );
        final resources = [
          ConnectionResource(
            id: 'cloud',
            type: ConnectionResourceType.torbox,
            label: 'Shared cloud',
            ownerProfileId: admin.id,
            publicConfig: const {},
            authorizationRevision: 1,
            enabled: true,
          ),
        ];
        await pumpEditor(
          tester,
          profile: member,
          setupOptionsLoader: () async => (
            resources,
            [
              const ProfileEngineAssignment(
                id: 'one',
                displayName: 'First engine',
                assignedToTarget: false,
                availableFromManager: true,
              ),
              const ProfileEngineAssignment(
                id: 'two',
                displayName: 'Second engine',
                assignedToTarget: false,
                availableFromManager: true,
              ),
            ],
          ),
        );
        await press(tester, LogicalKeyboardKey.arrowDown);
        await press(tester, LogicalKeyboardKey.arrowDown);
        await press(tester, LogicalKeyboardKey.arrowRight);
        final all = find.widgetWithText(TextButton, 'All').first;
        final none = find.widgetWithText(TextButton, 'None').first;
        expect(focusedWithin(all), isTrue);
        await press(tester, LogicalKeyboardKey.arrowRight);
        expect(focusedWithin(none), isTrue);
        await press(tester, LogicalKeyboardKey.arrowRight);
        expect(focusedWithin(none), isTrue);
        await press(tester, LogicalKeyboardKey.arrowLeft);
        expect(focusedWithin(all), isTrue);
        await press(tester, LogicalKeyboardKey.select);
        await press(tester, LogicalKeyboardKey.arrowDown);
        expect(focusedWithin(keyed('tv-profile-engine-one')), isTrue);
        final engine = find.descendant(
          of: keyed('tv-profile-engine-one'),
          matching: find.byType(CheckboxListTile),
        );
        expect(tester.widget<CheckboxListTile>(engine).value, isTrue);
        await press(tester, LogicalKeyboardKey.select);
        expect(tester.widget<CheckboxListTile>(engine).value, isFalse);
        await press(tester, LogicalKeyboardKey.arrowDown);
        expect(focusedWithin(keyed('tv-profile-engine-two')), isTrue);
        await press(tester, LogicalKeyboardKey.arrowDown);
        expect(
          focusedWithin(find.widgetWithText(TextButton, 'All').last),
          isTrue,
        );
        await press(tester, LogicalKeyboardKey.arrowDown);
        expect(focusedWithin(keyed('tv-profile-connection-cloud')), isTrue);
        final transfer = find.byTooltip('Transfer ownership to this profile');
        await press(tester, LogicalKeyboardKey.arrowLeft);
        expect(focusedWithin(transfer), isTrue);
        await press(tester, LogicalKeyboardKey.arrowRight);
        expect(focusedWithin(keyed('tv-profile-connection-cloud')), isTrue);
        expect(focusedWithin(transfer), isFalse);
        await press(tester, LogicalKeyboardKey.arrowLeft);
        await press(tester, LogicalKeyboardKey.arrowLeft);
        expect(focusedWithin(keyed('tv-profile-tab-access')), isTrue);
        await press(tester, LogicalKeyboardKey.arrowRight);
        expect(focusedWithin(transfer), isTrue);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'loading and failed Access panes keep a usable rail and Retry',
      (tester) async {
        await configureTv(tester);
        final pending =
            Completer<
              (List<ConnectionResource>, List<ProfileEngineAssignment>)
            >();
        var loads = 0;
        await pumpEditor(
          tester,
          setupOptionsLoader: () {
            loads++;
            return loads == 1
                ? pending.future
                : Future.value((
                    const <ConnectionResource>[],
                    const <ProfileEngineAssignment>[],
                  ));
          },
        );
        await press(tester, LogicalKeyboardKey.arrowDown);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump(const Duration(milliseconds: 250));
        // Do not settle the in-flight progress indicator.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump(const Duration(milliseconds: 250));
        expect(focusedWithin(keyed('tv-profile-tab-access')), isTrue);
        pending.completeError(StateError('test load failure'));
        await tester.pumpAndSettle();
        await press(tester, LogicalKeyboardKey.arrowRight);
        expect(focusedWithin(find.widgetWithText(TextButton, 'Retry')), isTrue);
        await press(tester, LogicalKeyboardKey.arrowLeft);
        expect(focusedWithin(keyed('tv-profile-tab-access')), isTrue);
        await press(tester, LogicalKeyboardKey.arrowRight);
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        for (var i = 0; i < 6; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 40)),
          );
          await tester.pump();
        }
        await tester.pumpAndSettle();
        expect(loads, 2);
        expect(find.text('No torrent engines installed'), findsOneWidget);
        expect(focusedWithin(keyed('tv-profile-tab-access')), isTrue);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('short viewport scrolls the rail to Save', (tester) async {
      await configureTv(tester, size: const Size(960, 480));
      await pumpEditor(tester);
      for (var i = 0; i < 5; i++) {
        await press(tester, LogicalKeyboardKey.arrowDown);
      }
      expect(focusedWithin(keyed('tv-profile-save')), isTrue);
      expect(
        tester.getRect(keyed('tv-profile-save')).bottom,
        lessThanOrEqualTo(480),
      );
      await press(tester, LogicalKeyboardKey.select);
      // Validation leaves the editor usable and does not persist an empty name.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Create profile'), findsOneWidget);
      expect(focusedWithin(keyed('tv-profile-save')), isTrue);
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focusedWithin(keyed('tv-profile-tab-data')), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'Back is reachable and returns to the rail without trapping focus',
      (tester) async {
        await configureTv(tester);
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => EditProfileScreen(
                        registry: registry,
                        pins: pins,
                        authorization: authorization,
                        setupOptionsLoader: () async => (
                          const <ConnectionResource>[],
                          const <ProfileEngineAssignment>[],
                        ),
                      ),
                    ),
                  ),
                  child: const Text('Open editor'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open editor'));
        await tester.pumpAndSettle();
        expect(focusedWithin(keyed('tv-profile-tab-profile')), isTrue);
        await press(tester, LogicalKeyboardKey.arrowUp);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'Edit profile back',
        );
        await press(tester, LogicalKeyboardKey.arrowRight);
        expect(focusedWithin(keyed('tv-profile-tab-profile')), isTrue);
        await press(tester, LogicalKeyboardKey.arrowUp);
        await press(tester, LogicalKeyboardKey.select);
        expect(find.text('Open editor'), findsOneWidget);
        expect(find.byType(EditProfileScreen), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'tvOS system text editing keeps caret keys until the field edge',
      (tester) async {
        await configureTv(tester, tvos: true);
        await pumpEditor(tester, profile: admin);
        await press(tester, LogicalKeyboardKey.arrowRight);
        for (
          var i = 0;
          i < 60 && !focusedWithin(keyed('tv-profile-name'));
          i++
        ) {
          await press(tester, LogicalKeyboardKey.arrowDown);
        }
        final field = tester.widget<TvTextField>(keyed('tv-profile-name'));
        field.controller.selection = const TextSelection.collapsed(offset: 3);
        await press(tester, LogicalKeyboardKey.arrowLeft);
        expect(field.controller.selection.baseOffset, 2);
        expect(focusedWithin(keyed('tv-profile-name')), isTrue);
        await press(tester, LogicalKeyboardKey.arrowRight);
        expect(field.controller.selection.baseOffset, 3);
        expect(focusedWithin(keyed('tv-profile-name')), isTrue);
        field.controller.selection = const TextSelection.collapsed(offset: 0);
        await press(tester, LogicalKeyboardKey.arrowLeft);
        expect(focusedWithin(keyed('tv-profile-tab-profile')), isTrue);
      },
    );

    testWidgets('fast pane changes cancel pending content focus requests', (
      tester,
    ) async {
      await configureTv(tester);
      await pumpEditor(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(focusedWithin(keyed('tv-profile-tab-pages')), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(focusedWithin(keyed('tv-profile-pin')), isTrue);
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(focusedWithin(keyed('tv-profile-tab-lock')), isTrue);
    });

    testWidgets(
      'a failed Save restores the remote to Save after unlocking the form',
      (tester) async {
        await configureTv(tester);
        await pumpEditor(tester, profile: admin);
        for (var i = 0; i < 5; i++) {
          await press(tester, LogicalKeyboardKey.arrowDown);
        }
        // Invalidate the session after loading so authorization fails during Save.
        ProfileRuntime.debugReset();
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pump();
        for (var i = 0; i < 6; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 40)),
          );
          await tester.pump();
        }
        await tester.pumpAndSettle();
        expect(find.text('Could not save this profile'), findsOneWidget);
        expect(focusedWithin(keyed('tv-profile-save')), isTrue);
        await press(tester, LogicalKeyboardKey.arrowUp);
        expect(focusedWithin(keyed('tv-profile-tab-data')), isTrue);
        expect(tester.takeException(), isNull);
      },
    );

    for (final tvos in [false, true]) {
      for (final key in [LogicalKeyboardKey.enter, LogicalKeyboardKey.select]) {
        final platform = tvos ? 'tvOS' : 'Android TV';
        testWidgets(
          '$platform held ${key.keyLabel} entering Access does not select engines',
          (tester) async {
            final member = await tester.runAsync(
              () => registry.createProfile(
                name: 'Member',
                role: UserProfileRole.member,
                actingProfileId: authorization.profileId,
                actingAuthorizationRevision:
                    authorization.authorizationRevision,
                actingSessionEpoch: authorization.sessionEpoch,
              ),
            );
            expect(member, isNotNull);
            // Build the registry fixture before enabling the tvOS UI override;
            // fixture writes do not have the native recovery plugin in tests.
            await configureTv(tester, tvos: tvos);
            await pumpEditor(
              tester,
              profile: member,
              setupOptionsLoader: () async => (
                const <ConnectionResource>[],
                [
                  for (var i = 0; i < 2; i++)
                    ProfileEngineAssignment(
                      id: 'engine_$i',
                      displayName: 'Engine $i',
                      assignedToTarget: false,
                      availableFromManager: true,
                    ),
                ],
              ),
            );
            await press(tester, LogicalKeyboardKey.arrowDown);
            await press(tester, LogicalKeyboardKey.arrowDown);
            await tester.sendKeyDownEvent(key);
            await tester.pumpAndSettle();
            final all = find.widgetWithText(TextButton, 'All');
            expect(focusedWithin(all), isTrue);
            expect(
              tester
                  .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
                  .map((tile) => tile.value),
              [false, false],
            );
            for (var i = 0; i < 3; i++) {
              await tester.sendKeyRepeatEvent(key);
              await tester.pumpAndSettle();
              expect(
                tester
                    .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
                    .map((tile) => tile.value),
                everyElement(isFalse),
              );
            }
            await tester.sendKeyUpEvent(key);
            await tester.pumpAndSettle();
            expect(focusedWithin(all), isTrue);
            expect(
              tester
                  .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
                  .map((tile) => tile.value),
              everyElement(isFalse),
            );
            // Releasing and deliberately pressing OK still performs the action.
            await press(tester, key);
            expect(
              tester
                  .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
                  .map((tile) => tile.value),
              everyElement(isTrue),
            );
            expect(tester.takeException(), isNull);
          },
        );

        testWidgets(
          '$platform held ${key.keyLabel} keeps Auto-lock open until a fresh press',
          (tester) async {
            await configureTv(tester, tvos: tvos);
            await pumpEditor(tester);
            for (var i = 0; i < 3; i++) {
              await press(tester, LogicalKeyboardKey.arrowDown);
            }
            await press(tester, LogicalKeyboardKey.arrowRight);
            await press(tester, LogicalKeyboardKey.arrowDown);
            await press(tester, LogicalKeyboardKey.arrowDown);
            expect(focusedWithin(keyed('tv-profile-auto-lock')), isTrue);
            await tester.sendKeyDownEvent(key);
            await tester.pumpAndSettle();
            for (var i = 0; i < 3; i++) {
              await tester.sendKeyRepeatEvent(key);
              await tester.pumpAndSettle();
              expect(find.byType(SimpleDialog), findsOneWidget);
            }
            await tester.sendKeyUpEvent(key);
            await tester.pumpAndSettle();
            expect(find.byType(SimpleDialog), findsOneWidget);
            await press(tester, LogicalKeyboardKey.arrowDown);
            await press(tester, key);
            expect(find.byType(SimpleDialog), findsNothing);
            expect(find.text('After 5 minutes'), findsOneWidget);
            expect(focusedWithin(keyed('tv-profile-auto-lock')), isTrue);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  });
}
