import 'package:debrify/widgets/onboarding/onboarding_focus.dart';
import 'package:debrify/widgets/onboarding/onboarding_models.dart';
import 'package:debrify/widgets/onboarding/onboarding_stage.dart';
import 'package:debrify/widgets/onboarding/onboarding_theme.dart';
import 'package:debrify/widgets/onboarding/steps/key_step.dart';
import 'package:debrify/widgets/onboarding/steps/mode_step.dart';
import 'package:debrify/widgets/onboarding/tv_keyboard_slot.dart';
import 'package:debrify/widgets/initial_setup_flow.dart';
import 'package:debrify/widgets/tv_text_field.dart';
import 'package:debrify/services/engine/remote_engine_manager.dart';
import 'package:debrify/services/remote_control/remote_control_state.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'onboarding_test_harness.dart';

void main() {
  test('every step declares its expected landing cell', () {
    expect(onboardLandingCells, <OnboardStep, OnboardCell>{
      OnboardStep.mode: const OnboardCell(0, 0),
      OnboardStep.services: const OnboardCell(0, 0),
      OnboardStep.key: const OnboardCell(1, 0),
      OnboardStep.engines: const OnboardCell(0, 0),
      OnboardStep.trackers: const OnboardCell(0, 0),
      OnboardStep.importing: const OnboardCell(0, 0),
      OnboardStep.done: const OnboardCell(0, 0),
    });
  });

  testWidgets('explicit grid parks LEFT on Back and RIGHT returns', (
    tester,
  ) async {
    final controller = OnboardFocusController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingTheme.scope(
          Scaffold(
            body: Row(
              children: [
                Focus(
                  focusNode: controller.backNode,
                  onKeyEvent: (_, event) {
                    if (event is! KeyUpEvent &&
                        event.logicalKey == LogicalKeyboardKey.arrowRight) {
                      controller.returnFromBack();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: const Text('Back'),
                ),
                OnboardFocusable(
                  controller: controller,
                  cell: const OnboardCell(0, 0),
                  onActivate: () {},
                  builder: (_, focused) => Text('First $focused'),
                ),
                OnboardFocusable(
                  controller: controller,
                  cell: const OnboardCell(0, 1),
                  onActivate: () {},
                  builder: (_, focused) => Text('Second $focused'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    controller.move(const OnboardCell(0, 0), TraversalDirection.left);
    await tester.pump();
    expect(controller.backNode.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(controller.backNode.hasFocus, isFalse);
    controller.move(const OnboardCell(0, 0), TraversalDirection.right);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(find.text('Second true'), findsOneWidget);
  });

  testWidgets('Back control lets physical Back bubble to the route owner', (
    tester,
  ) async {
    final controller = OnboardFocusController();
    addTearDown(controller.dispose);
    var bubbled = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Focus(
          onKeyEvent: (_, event) {
            if (event is! KeyUpEvent &&
                (event.logicalKey == LogicalKeyboardKey.escape ||
                    event.logicalKey == LogicalKeyboardKey.goBack ||
                    event.logicalKey == LogicalKeyboardKey.browserBack)) {
              bubbled++;
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: OnboardBackControl(controller: controller, onPressed: () {}),
        ),
      ),
    );
    controller.backNode.requestFocus();
    await tester.pump();
    // flutter_test's desktop simulator has no physical-key mapping for
    // goBack/browserBack. Escape exercises the same production branch.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(bubbled, 1);
  });

  testWidgets('mode focus traverses WebDAV first, restore, then Skip', (
    tester,
  ) async {
    final controller = OnboardFocusController();
    addTearDown(controller.dispose);
    var restored = false;
    var webDavLogin = false;

    await tester.binding.setSurfaceSize(const Size(960, 540));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      onboardingApp(
        ModeStep(
          focusController: controller,
          onWebDavLogin: () => webDavLogin = true,
          onSetupHere: () {},
          onImport: () {},
          onRestore: () => restored = true,
          onSkip: () {},
        ),
      ),
    );

    controller.focusLanding(OnboardStep.mode);
    await tester.pump();
    expect(
      tester.binding.focusManager.primaryFocus?.debugLabel,
      'onboarding-0-0',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(webDavLogin, isTrue);
    expect(find.text('Log in with WebDAV'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Log in with WebDAV')).dy,
      lessThan(tester.getTopLeft(find.text('Set it up here')).dy),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(
      tester.binding.focusManager.primaryFocus?.debugLabel,
      'onboarding-3-0',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(restored, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(
      tester.binding.focusManager.primaryFocus?.debugLabel,
      'onboarding-4-0',
    );
  });

  testWidgets('mode omits file restore when no callback is available', (
    tester,
  ) async {
    final controller = OnboardFocusController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      onboardingApp(
        ModeStep(
          focusController: controller,
          onWebDavLogin: () {},
          onSetupHere: () {},
          onImport: () {},
          onSkip: () {},
        ),
      ),
    );

    expect(find.text('Restore from a backup'), findsNothing);
    expect(find.text('Log in with WebDAV'), findsOneWidget);
    controller.focusLanding(OnboardStep.mode);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(
      tester.binding.focusManager.primaryFocus?.debugLabel,
      'onboarding-3-0',
      reason: 'Skip closes the focus gap when restore is unavailable',
    );
  });

  testWidgets('keyboard Back-down and nav-channel pop do not step back twice', (
    tester,
  ) async {
    PlatformUtil.debugSetAndroidTvCached(true);
    StorageService.tvKeyboardEnabledCached = true;
    addTearDown(() => PlatformUtil.debugSetAndroidTvCached(null));
    await tester.binding.setSurfaceSize(const Size(960, 540));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingTheme.scope(
          InitialSetupFlow(
            isTelevisionOverride: true,
            engineManager: FakeRemoteEngineManager(const <RemoteEngineInfo>[]),
            validationOverride: (_, __, ___) async => true,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Set it up here'));
    await tester.pump();
    await tester.tap(find.text('Real-Debrid'));
    await tester.pump();
    await tester.tap(find.textContaining('Continue'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byType(TvTextField));
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(TvTextField), findsOneWidget);
    expect(find.textContaining('Which services'), findsNothing);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
  });

  testWidgets('TV method-chip DPAD cells match the wrapped visual rows', (
    tester,
  ) async {
    PlatformUtil.debugSetAndroidTvCached(true);
    StorageService.tvKeyboardEnabledCached = true;
    addTearDown(() => PlatformUtil.debugSetAndroidTvCached(null));
    await tester.binding.setSurfaceSize(const Size(960, 540));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final focus = OnboardFocusController();
    final session = TvKeyboardSession();
    final key = TextEditingController();
    final password = TextEditingController();

    await tester.pumpWidget(
      onboardingApp(
        KeyStep(
          layout: OnboardLayout.stage,
          isTelevision: true,
          focusController: focus,
          session: session,
          meta: integrationMeta[IntegrationType.realDebrid]!,
          index: 0,
          total: 1,
          controller: key,
          pikpakPasswordController: password,
          phase: KeyValidationPhase.idle,
          clipboardCandidate: List<String>.filled(40, 'a').join(),
          onChanged: (_) {},
          onConnect: () {},
          onSkip: () {},
          onImport: () {},
        ),
      ),
    );
    focus.focusLanding(OnboardStep.key);
    await tester.pump();
    expect(
      tester.binding.focusManager.primaryFocus?.debugLabel,
      'onboarding-0-1',
      reason: 'Paste is the landing chip',
    );
    focus.move(const OnboardCell(0, 1), TraversalDirection.down);
    await tester.pump();
    expect(
      tester.binding.focusManager.primaryFocus?.debugLabel,
      'onboarding-1-1',
      reason: 'DOWN from Paste reaches wrapped Skip',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(
      tester.binding.focusManager.primaryFocus?.debugLabel,
      'onboarding-1-0',
      reason: 'Open page and Skip are neighbours on visual row 1',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(
      tester.binding.focusManager.primaryFocus?.debugLabel,
      'onboarding-1-1',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(
      tester.binding.focusManager.primaryFocus?.debugLabel,
      'onboarding-key-field',
      reason: 'DOWN from Skip reaches the field spanning the shorter row',
    );
    focus.move(const OnboardCell(0, 1), TraversalDirection.right);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(
      tester.binding.focusManager.primaryFocus?.debugLabel,
      'onboarding-1-1',
      reason: 'DOWN from the final first-row chip reaches the nearest chip',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    focus.dispose();
    session.dispose();
    key.dispose();
    password.dispose();
  });

  testWidgets('PikPak Back parking returns to the password field', (
    tester,
  ) async {
    PlatformUtil.debugSetAndroidTvCached(true);
    StorageService.tvKeyboardEnabledCached = true;
    addTearDown(() => PlatformUtil.debugSetAndroidTvCached(null));
    await tester.binding.setSurfaceSize(const Size(960, 540));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final focus = OnboardFocusController();
    final session = TvKeyboardSession();
    final email = TextEditingController();
    final password = TextEditingController();

    await tester.pumpWidget(
      onboardingApp(
        Stack(
          children: [
            KeyStep(
              layout: OnboardLayout.stage,
              isTelevision: true,
              focusController: focus,
              session: session,
              meta: integrationMeta[IntegrationType.pikpak]!,
              index: 0,
              total: 1,
              controller: email,
              pikpakPasswordController: password,
              phase: KeyValidationPhase.idle,
              onChanged: (_) {},
              onConnect: () {},
              onSkip: () {},
              onImport: () {},
            ),
            OnboardBackControl(controller: focus, onPressed: () {}),
          ],
        ),
      ),
    );
    final fields = tester.widgetList<TvTextField>(find.byType(TvTextField));
    fields.last.focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(
      tester.binding.focusManager.primaryFocus?.debugLabel,
      'onboarding-back',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(
      tester.binding.focusManager.primaryFocus?.debugLabel,
      'onboarding-pikpak-password',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    focus.dispose();
    session.dispose();
    email.dispose();
    password.dispose();
  });

  testWidgets('failed TV validation restores the active password field', (
    tester,
  ) async {
    PlatformUtil.debugSetAndroidTvCached(true);
    StorageService.tvKeyboardEnabledCached = true;
    addTearDown(() => PlatformUtil.debugSetAndroidTvCached(null));
    await tester.binding.setSurfaceSize(const Size(960, 540));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final focus = OnboardFocusController();
    final session = TvKeyboardSession();
    final email = TextEditingController(text: 'viewer@example.com');
    final password = TextEditingController(text: 'secret');

    Widget buildStep(KeyValidationPhase phase) => onboardingApp(
      KeyStep(
        layout: OnboardLayout.stage,
        isTelevision: true,
        focusController: focus,
        session: session,
        meta: integrationMeta[IntegrationType.pikpak]!,
        index: 0,
        total: 1,
        controller: email,
        pikpakPasswordController: password,
        phase: phase,
        onChanged: (_) {},
        onConnect: () {},
        onSkip: () {},
        onImport: () {},
      ),
    );

    await tester.pumpWidget(buildStep(KeyValidationPhase.idle));
    final fields = tester.widgetList<TvTextField>(find.byType(TvTextField));
    fields.last.focusNode!.requestFocus();
    await tester.pump();
    expect(
      tester.binding.focusManager.primaryFocus?.debugLabel,
      'onboarding-pikpak-password',
    );

    await tester.pumpWidget(buildStep(KeyValidationPhase.validating));
    await tester.pump();
    expect(
      tester.binding.focusManager.primaryFocus?.debugLabel,
      isNot('onboarding-pikpak-password'),
    );

    await tester.pumpWidget(buildStep(KeyValidationPhase.failed));
    await tester.pump();
    expect(
      tester.binding.focusManager.primaryFocus?.debugLabel,
      'onboarding-pikpak-password',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    focus.dispose();
    session.dispose();
    email.dispose();
    password.dispose();
  });

  for (final caret in <int>[0, 4]) {
    testWidgets('keyboard Back exits at caret $caret and LEFT reaches Back', (
      tester,
    ) async {
      PlatformUtil.debugSetAndroidTvCached(true);
      StorageService.tvKeyboardEnabledCached = true;
      addTearDown(() => PlatformUtil.debugSetAndroidTvCached(null));
      await tester.binding.setSurfaceSize(const Size(960, 540));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingTheme.scope(
            InitialSetupFlow(
              isTelevisionOverride: true,
              engineManager: FakeRemoteEngineManager(
                const <RemoteEngineInfo>[],
              ),
              validationOverride: (_, __, ___) async => true,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Set it up here'));
      await tester.pump();
      await tester.tap(find.text('Real-Debrid'));
      await tester.pump();
      await tester.tap(find.textContaining('Continue'));
      await tester.pump(const Duration(milliseconds: 50));

      final controller = tester
          .widget<TvTextField>(find.byType(TvTextField))
          .controller;
      await tester.tap(find.byType(TvTextField));
      await tester.pump();
      controller.value = TextEditingValue(
        text: 'abcdefgh',
        selection: TextSelection.collapsed(offset: caret),
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(
        tester.binding.focusManager.primaryFocus?.debugLabel,
        'onboarding-key-field',
        reason: 'Back must close editing with the caret at $caret',
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(
        tester.binding.focusManager.primaryFocus?.debugLabel,
        'onboarding-back',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(
        tester.binding.focusManager.primaryFocus?.debugLabel,
        'onboarding-key-field',
      );
    });
  }

  testWidgets('system Back reverses provider traversal and import', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    PlatformUtil.debugSetAndroidTvCached(false);
    addTearDown(() => PlatformUtil.debugSetAndroidTvCached(null));
    final remote = RemoteControlState();
    await remote.debugResetForTesting();
    remote.debugReceiverStarter = (_) async {};
    remote.debugRoleStopper = () async {};

    await tester.binding.setSurfaceSize(const Size(800, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingTheme.scope(
          InitialSetupFlow(
            isTelevisionOverride: false,
            engineManager: FakeRemoteEngineManager(const <RemoteEngineInfo>[]),
            validationOverride: (_, __, ___) async => true,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Set it up here'));
    await tester.pump();
    await tester.tap(find.text('Real-Debrid'));
    await tester.tap(find.text('TorBox'));
    await tester.pump();
    await tester.tap(find.textContaining('Continue'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Real-Debrid'), findsOneWidget);

    await tester.tap(find.text('Skip'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('TorBox'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Real-Debrid'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.textContaining('Which services'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('Bring it from another device'), findsOneWidget);

    await tester.tap(find.text('Bring it from another device'));
    for (var i = 0; i < 5 && remote.debugReceiverLeaseCount == 0; i++) {
      await tester.pump();
    }
    await tester.pump();
    expect(remote.debugReceiverLeaseCount, 1);
    expect(find.text('Open Remote on the other device'), findsOneWidget);
    await tester.binding.handlePopRoute();
    for (var i = 0; i < 5 && remote.debugReceiverLeaseCount != 0; i++) {
      await tester.pump();
    }
    // The lease loop exits the moment the count hits zero — the mode step's
    // setState lands in the same turn and still needs one frame to paint.
    // (Non-TV used to get that frame for free from the landing-focus
    // request every transition scheduled; the focus gate removed it.)
    await tester.pump();
    expect(find.text('Set it up here'), findsOneWidget);
    expect(remote.debugReceiverLeaseCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await remote.debugResetForTesting();
  });
}
