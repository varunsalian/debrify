import 'dart:io';

import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/screens/profiles/profile_setup_flow.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
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
    // 10 windows: the staged create (staging insert → defaults copy →
    // engine probe → publish checkpoint) is the longest chain driven
    // through a single tap.
    for (var i = 0; i < 10; i++) {
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

  Future<void> openFlow(
    WidgetTester tester, {
    required ValueChanged<bool> onClosed,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                onClosed(await ProfileSetupFlow.show(context));
              },
              child: const Text('Add profile'),
            ),
          ),
        ),
      ),
    );
    await nextByLabel(tester, 'Add profile');
    expect(find.byType(ProfileSetupFlow), findsOneWidget);
  }

  testWidgets('Cancel exits an unnamed profile after validation fails', (
    tester,
  ) async {
    bool? result;
    await openFlow(tester, onClosed: (value) => result = value);
    await nextByLabel(tester, 'Next');
    expect(find.text('Give this profile a name first.'), findsOneWidget);

    await nextByLabel(tester, 'Cancel');

    expect(find.byType(ProfileSetupFlow), findsNothing);
    expect(find.text('Add profile'), findsOneWidget);
    expect(result, isFalse);
    expect(await io(tester, registry.listProfiles), hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Cancel exits Review without creating the draft profile', (
    tester,
  ) async {
    bool? result;
    await openFlow(tester, onClosed: (value) => result = value);
    await tester.enterText(find.byType(TextField).first, 'Maya');
    for (var step = 0; step < 4; step++) {
      await nextByLabel(tester, 'Next');
    }
    await nextByLabel(tester, 'Review');
    expect(find.text("Maya's corner of Debrify"), findsOneWidget);

    await nextByLabel(tester, 'Cancel');

    expect(find.byType(ProfileSetupFlow), findsNothing);
    expect(result, isFalse);
    expect(await io(tester, registry.listProfiles), hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Back and Escape retrace steps and preserve the entered name', (
    tester,
  ) async {
    bool? result;
    await openFlow(tester, onClosed: (value) => result = value);
    await tester.enterText(find.byType(TextField).first, 'Maya');
    await nextByLabel(tester, 'Next');
    await nextByLabel(tester, 'Next');
    expect(find.text('How can Maya search?'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await pumpFrames(tester);
    expect(find.text('Who is this for?'), findsOneWidget);
    expect(result, isNull);

    await nextByLabel(tester, 'Back');
    expect(find.text('Name them.'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      'Maya',
    );

    // Escape must also work while the desktop name field owns focus.
    await tester.tap(find.byType(TextField).first);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await pumpFrames(tester);
    expect(find.byType(ProfileSetupFlow), findsNothing);
    expect(result, isFalse);
    expect(await io(tester, registry.listProfiles), hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Escape exits before a desktop control has been focused', (
    tester,
  ) async {
    bool? result;
    await openFlow(tester, onClosed: (value) => result = value);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await pumpFrames(tester);

    expect(find.byType(ProfileSetupFlow), findsNothing);
    expect(result, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('arrow navigation reaches Cancel and returns to the content', (
    tester,
  ) async {
    bool? result;
    await openFlow(tester, onClosed: (value) => result = value);
    final nextNode = Focus.of(tester.element(find.text('Next')));
    nextNode.requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    final cancelNode = tester
        .widget<TextButton>(find.byType(TextButton).first)
        .focusNode!;
    expect(cancelNode.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(nextNode.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await pumpFrames(tester);
    expect(find.byType(ProfileSetupFlow), findsNothing);
    expect(result, isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final key in [LogicalKeyboardKey.enter, LogicalKeyboardKey.select]) {
    testWidgets('holding ${key.keyLabel} on Back does not cancel the draft', (
      tester,
    ) async {
      bool? result;
      await openFlow(tester, onClosed: (value) => result = value);
      await tester.enterText(find.byType(TextField).first, 'Maya');
      await nextByLabel(tester, 'Next');
      final backNode = tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Back'))
          .focusNode!;
      backNode.requestFocus();
      await tester.pump();

      await tester.sendKeyDownEvent(key);
      await tester.pump();
      expect(find.text('Name them.'), findsOneWidget);
      expect(backNode.hasFocus, isTrue);
      await tester.sendKeyRepeatEvent(key);
      await tester.pump();
      await tester.sendKeyUpEvent(key);
      await pumpFrames(tester);

      expect(find.byType(ProfileSetupFlow), findsOneWidget);
      expect(result, isNull);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'Maya',
      );
      expect(await io(tester, registry.listProfiles), hasLength(1));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('TV arrows reach intermediate Cancel and return to the form', (
    tester,
  ) async {
    bool? result;
    await openFlow(tester, onClosed: (value) => result = value);
    await tester.enterText(find.byType(TextField).first, 'Maya');
    PlatformUtil.debugSetAndroidTvCached(true);
    addTearDown(() => PlatformUtil.debugSetAndroidTvCached(null));
    await nextByLabel(tester, 'Next');
    final roleNode = Focus.of(tester.element(find.text('Member')));
    roleNode.requestFocus();
    await tester.pump();

    final backNode = tester
        .widget<TextButton>(find.widgetWithText(TextButton, 'Back'))
        .focusNode!;
    final cancelNode = Focus.of(tester.element(find.text('Cancel')));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(backNode.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(cancelNode.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(backNode.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(roleNode.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await pumpFrames(tester);
    expect(find.byType(ProfileSetupFlow), findsNothing);
    expect(result, isFalse);
    expect(await io(tester, registry.listProfiles), hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('small phone can correct an empty name with the keyboard open', (
    tester,
  ) async {
    const size = Size(320, 568);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Widget phone({double keyboardHeight = 0}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          padding: const EdgeInsets.only(top: 24),
          viewInsets: EdgeInsets.only(bottom: keyboardHeight),
        ),
        child: ProfileSetupFlow(
          registry: registry,
          authorization: authorization,
        ),
      ),
    );
    await tester.pumpWidget(phone());
    final nameField = find.byType(TextField).first;
    await tester.tap(nameField);
    await tester.pumpWidget(phone(keyboardHeight: 253));
    await nextByLabel(tester, 'Next');
    expect(find.text('Give this profile a name first.'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final scrollView = find.byType(SingleChildScrollView);
    expect(
      tester.getSize(scrollView).height,
      greaterThanOrEqualTo(tester.getSize(nameField).height),
    );
    await tester.ensureVisible(nameField);
    await tester.pump();
    expect(nameField.hitTestable(), findsOneWidget);
    expect(
      tester.getRect(scrollView).contains(tester.getCenter(nameField)),
      isTrue,
    );
    await tester.enterText(nameField, 'Maya');
    await nextByLabel(tester, 'Next');
    expect(find.text('Who is this for?'), findsOneWidget);
    expect(find.text('Give this profile a name first.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

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
