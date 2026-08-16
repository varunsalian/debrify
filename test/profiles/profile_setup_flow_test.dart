import 'dart:io';

import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/screens/profiles/profile_setup_flow.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The questionnaire is the policy AUTHOR — these tests drive the real
/// widget over a real registry and assert what a walk-through writes.
void main() {
  late Directory root;
  late ProfileRegistry registry;
  late ProfileAuthorizationContext authorization;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    ProfileRuntime.debugReset();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    root = await Directory.systemTemp.createTemp('setup-flow-');
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
  });

  tearDown(() async {
    ProfileBootstrap.debugInstallRegistry(null);
    ProfileRuntime.debugReset();
    await registry.close();
    await root.delete(recursive: true);
  });

  Widget host({dynamic profile}) => MaterialApp(
    home: ProfileSetupFlow(
      registry: registry,
      authorization: authorization,
      profile: profile,
    ),
  );

  // Two constraints shape this helper (the edit_profile_screen_test idiom):
  // real IO — the flow saves through sqflite — only advances inside runAsync
  // windows, and pumps are BOUNDED, never settled: a focused text field's
  // cursor blink schedules frames forever, so a settle would hang the suite.
  Future<void> pumpFrames(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  // Registry reads from a test body live in the fake-async zone too.
  Future<T> io<T>(WidgetTester tester, Future<T> Function() body) async =>
      (await tester.runAsync(body)) as T;

  Future<void> nextByLabel(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await pumpFrames(tester);
  }

  testWidgets('the Kid walk-through writes the preset policy', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(host());
    await pumpFrames(tester);

    // Identity.
    await tester.enterText(find.byType(TextField).first, 'Maya');
    await nextByLabel(tester, 'Next');

    // Role: Kid — the preset pre-answers everything after this.
    await tester.tap(find.text('Kid'));
    await pumpFrames(tester);
    await nextByLabel(tester, 'Next'); // → search
    await nextByLabel(tester, 'Next'); // → sources
    await nextByLabel(tester, 'Next'); // → abilities
    await nextByLabel(tester, 'Review'); // → review
    expect(find.text("Maya's corner of Debrify"), findsOneWidget);

    await nextByLabel(tester, 'Create Maya');

    final profiles = await io(tester, registry.listProfiles);
    final maya = profiles.singleWhere((p) => p.name == 'Maya');
    expect(maya.role, UserProfileRole.child);
    expect(
      maya.policy.enabled,
      ProfilePolicy.defaultsFor(UserProfileRole.child).enabled,
      reason: 'an untouched Kid walk-through IS the preset',
    );
    expect(maya.allows(ProfileFeature.debrifyTv), isTrue);
    expect(maya.allows(ProfileFeature.keywordSearch), isFalse);
    expect(maya.allows(ProfileFeature.iptv), isFalse);
    // Operations stay on: curated playback keeps working.
    expect(maya.allows(ProfileFeature.cloud), isTrue);
    expect(maya.allows(ProfileFeature.torrentSearch), isTrue);
  });

  testWidgets('divergence from the preset is unceremonious', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(host());
    await pumpFrames(tester);

    await tester.enterText(find.byType(TextField).first, 'Sam');
    await nextByLabel(tester, 'Next');
    await tester.tap(find.text('Kid'));
    await pumpFrames(tester);
    await nextByLabel(tester, 'Next'); // search
    await nextByLabel(tester, 'Next'); // sources
    // Allow YouTube for this kid — one tap on the source tile.
    await tester.tap(find.text('YouTube'));
    await pumpFrames(tester);
    await nextByLabel(tester, 'Next'); // abilities
    await nextByLabel(tester, 'Review');
    await nextByLabel(tester, 'Create Sam');

    final profiles = await io(tester, registry.listProfiles);
    final sam = profiles.singleWhere((p) => p.name == 'Sam');
    expect(sam.allows(ProfileFeature.youtube), isTrue);
    expect(sam.allows(ProfileFeature.iptv), isFalse, reason: 'others stay');
  });

  testWidgets('edit mode opens on Review seeded from the CURRENT policy', (
    tester,
  ) async {
    // A DIVERGED policy pins the seeding: youtube added (an asked feature
    // off the Kid preset) and trackersAndDiscovery removed (a feature the
    // questionnaire never asks about). An untouched save must round-trip
    // BOTH — the asked one via seeding, the unasked one because edit-saves
    // base on the stored policy, not the role preset.
    final diverged = Set<ProfileFeature>.from(
      ProfilePolicy.defaultsFor(UserProfileRole.child).enabled,
    )
      ..add(ProfileFeature.youtube)
      ..remove(ProfileFeature.trackersAndDiscovery);
    final kid = await io(
      tester,
      () => registry.createProfile(
        name: 'Noor',
        role: UserProfileRole.child,
        policy: ProfilePolicy(enabled: diverged),
        actingProfileId: authorization.profileId,
        actingAuthorizationRevision: authorization.authorizationRevision,
        actingSessionEpoch: authorization.sessionEpoch,
      ),
    );
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(host(profile: kid));
    await pumpFrames(tester);

    // Lands on review, speaking Can/Can't for the stored policy.
    expect(find.text("Noor's corner of Debrify"), findsOneWidget);
    expect(find.text('CAN'), findsOneWidget);
    expect(find.text("CAN'T"), findsOneWidget);
    // Debrify TV is a Can; Live TV a Can't (one chip each).
    expect(find.text('Debrify TV'), findsOneWidget);
    expect(find.text('Live TV'), findsOneWidget);

    await nextByLabel(tester, 'Save changes');
    final saved = await io(tester, () => registry.getProfile(kid.id));
    expect(
      saved!.policy.enabled,
      diverged,
      reason: 'an untouched edit round-trips the stored policy exactly — '
          'including features the questionnaire never asks about',
    );
  });
}
