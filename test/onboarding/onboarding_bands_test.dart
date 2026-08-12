import 'package:debrify/services/engine/remote_engine_manager.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/widgets/initial_setup_flow.dart';
import 'package:debrify/widgets/onboarding/onboarding_models.dart';
import 'package:debrify/widgets/onboarding/onboarding_theme.dart';
import 'package:debrify/widgets/tv_keyboard.dart';
import 'package:debrify/widgets/tv_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'onboarding_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PlatformUtil.debugSetAndroidTvCached(true);
    StorageService.tvKeyboardEnabledCached = true;
  });

  tearDown(() => PlatformUtil.debugSetAndroidTvCached(null));

  for (final scale in <double>[1, 1.3]) {
    testWidgets('TV key bands never overlap at text scale $scale', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(960, 540));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final engines = FakeRemoteEngineManager(const <RemoteEngineInfo>[]);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: OnboardingTheme.scope(
            InitialSetupFlow(
              isTelevisionOverride: true,
              engineManager: engines,
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

      final panel = tester.widget<TvKeyboardPanel>(
        find.byType(TvKeyboardPanel),
      );
      panel.controller.showNotice(
        'A notice that increases the measured panel height',
      );
      await tester.pump();

      final fieldBand = tester.getRect(
        find.byKey(const ValueKey('onboarding-field-band')),
      );
      final keyboardBand = tester.getRect(
        find.byKey(const ValueKey('onboarding-keyboard-band')),
      );
      final panelRect = tester.getRect(
        find.byKey(const ValueKey('onboarding-keyboard-panel')),
      );
      expect(fieldBand.bottom, lessThanOrEqualTo(keyboardBand.top));
      expect(panelRect.left, greaterThanOrEqualTo(keyboardBand.left));
      expect(panelRect.top, greaterThanOrEqualTo(keyboardBand.top));
      expect(panelRect.right, lessThanOrEqualTo(keyboardBand.right));
      expect(panelRect.bottom, lessThanOrEqualTo(keyboardBand.bottom));
      expect(tester.takeException(), isNull);
    });

    testWidgets('phone CTA clears the soft keyboard at text scale $scale', (
      tester,
    ) async {
      PlatformUtil.debugSetAndroidTvCached(false);
      const size = Size(360, 740);
      const keyboardInset = 280.0;
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              viewInsets: const EdgeInsets.only(bottom: keyboardInset),
            ),
            child: child!,
          ),
          home: OnboardingTheme.scope(
            InitialSetupFlow(
              isTelevisionOverride: false,
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
      await tester.pump(const Duration(milliseconds: 200));

      final connect = tester.getRect(find.text('Connect'));
      expect(connect.bottom, lessThanOrEqualTo(size.height - keyboardInset));
      expect(find.byType(TvKeyboardPanel), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  test('responsive resolver gives television priority over width', () {
    expect(
      resolveOnboardLayout(isTelevision: true, size: const Size(360, 740)),
      OnboardLayout.stage,
    );
    expect(
      resolveOnboardLayout(isTelevision: true, size: const Size(960, 540)),
      OnboardLayout.stage,
    );
    expect(
      resolveOnboardLayout(isTelevision: false, size: const Size(360, 740)),
      OnboardLayout.phone,
    );
  });
}
