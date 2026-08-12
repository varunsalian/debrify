import 'dart:async';

import 'package:debrify/services/engine/remote_engine_manager.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/widgets/initial_setup_flow.dart';
import 'package:debrify/widgets/onboarding/key_codec.dart';
import 'package:debrify/widgets/onboarding/onboarding_models.dart';
import 'package:debrify/widgets/onboarding/onboarding_theme.dart';
import 'package:debrify/widgets/tv_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'onboarding_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('key canonicalisation preserves nonav and ignores visual grouping', () {
    const raw = 'abcdefghijklmnop';
    expect(parseOnboardingKey(raw).key, raw);
    expect(parseOnboardingKey('abcd efgh ijkl mnop').key, raw);
    final provisioned = parseOnboardingKey('nonav:abcd efgh ijkl mnop');
    expect(provisioned.key, raw);
    expect(provisioned.hideFromNav, isTrue);
    expect(formatOnboardingKey('nonav:$raw'), 'nonav:abcd efgh ijkl mnop');
  });

  test('formatter keeps a collapsed caret at the formatted end', () {
    const formatter = OnboardingKeyFormatter();
    final value = formatter.formatEditUpdate(
      TextEditingValue.empty,
      const TextEditingValue(text: 'abcdefgh'),
    );
    expect(value.text, 'abcd efgh');
    expect(value.selection.baseOffset, value.text.length);
  });

  test('formatter preserves nonav while it is typed incrementally', () {
    const formatter = OnboardingKeyFormatter();
    var value = TextEditingValue.empty;
    for (final character in 'nonav:abcdefgh'.split('')) {
      final proposed = value.copyWith(
        text: '${value.text}$character',
        selection: TextSelection.collapsed(
          offset: value.text.length + character.length,
        ),
      );
      value = formatter.formatEditUpdate(value, proposed);
      if (character == 'v') expect(value.text, 'nonav');
    }

    expect(value.text, 'nonav:abcd efgh');
    expect(parseOnboardingKey(value.text).key, 'abcdefgh');
    expect(parseOnboardingKey(value.text).hideFromNav, isTrue);
    expect(parseOnboardingKey('nona v:abcd efgh').hideFromNav, isTrue);
  });

  testWidgets('public insertText shares formatter and onChanged path', (
    tester,
  ) async {
    final key = GlobalKey<TvTextFieldState>();
    final controller = TextEditingController();
    var changed = '';
    await tester.pumpWidget(
      onboardingApp(
        TvTextField(
          key: key,
          controller: controller,
          inputFormatters: const [OnboardingKeyFormatter()],
          onChanged: (value) => changed = value,
        ),
      ),
    );
    key.currentState!.insertText('abcdefgh');
    await tester.pump();
    expect(controller.text, 'abcd efgh');
    expect(changed, 'abcd efgh');
    controller.dispose();
  });

  testWidgets('Paste uses the formatter and preserves the nonav side effect', (
    tester,
  ) async {
    final token = List<String>.filled(40, 'a').join();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => call.method == 'Clipboard.getData'
          ? <String, Object>{'text': 'nonav:$token'}
          : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.binding.setSurfaceSize(const Size(360, 740));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final engines = FakeRemoteEngineManager(const <RemoteEngineInfo>[]);

    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingTheme.scope(
          InitialSetupFlow(
            isTelevisionOverride: false,
            engineManager: engines,
            validationOverride: (type, value, secondary) async {
              expect(type, IntegrationType.realDebrid);
              expect(value, token);
              return true;
            },
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

    expect(find.text('Paste'), findsOneWidget);
    expect(find.text('Open token page'), findsOneWidget);
    await tester.tap(find.text('Paste'));
    await tester.pump();
    final field = tester.widget<TvTextField>(find.byType(TvTextField));
    expect(field.controller.text, formatOnboardingKey('nonav:$token'));
    await tester.tap(find.text('Connect'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(await StorageService.getRealDebridHiddenFromNav(), isTrue);
    expect(find.textContaining('Where should'), findsOneWidget);
  });

  testWidgets('PikPak password has a password-specific hint', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.binding.setSurfaceSize(const Size(360, 740));
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
    await tester.tap(find.text('PikPak'));
    await tester.pump();
    await tester.tap(find.textContaining('Continue'));
    await tester.pump(const Duration(milliseconds: 50));

    final fields = tester.widgetList<TvTextField>(find.byType(TvTextField));
    expect(fields, hasLength(2));
    expect(fields.first.decoration?.hintText, 'you@example.com');
    expect(fields.last.decoration?.hintText, 'Enter your PikPak password');
  });

  testWidgets('unknown-length providers report the live character count', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.binding.setSurfaceSize(const Size(360, 740));
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
    await tester.tap(find.text('TorBox'));
    await tester.pump();
    await tester.tap(find.textContaining('Continue'));
    await tester.pump(const Duration(milliseconds: 50));

    tester
        .state<TvTextFieldState>(find.byType(TvTextField))
        .insertText('abcdefgh');
    await tester.pump();
    expect(find.text('8 characters'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('validation locks every exit until the request resolves', (
    tester,
  ) async {
    final validation = Completer<bool>();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.binding.setSurfaceSize(const Size(800, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingTheme.scope(
          InitialSetupFlow(
            isTelevisionOverride: false,
            engineManager: FakeRemoteEngineManager(const <RemoteEngineInfo>[]),
            validationOverride: (_, __, ___) => validation.future,
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
    tester
        .state<TvTextFieldState>(find.byType(TvTextField))
        .insertText(List<String>.filled(40, 'a').join());
    await tester.pump();
    await tester.tap(find.text('Connect'));
    await tester.pump();
    expect(find.textContaining('Checking with'), findsOneWidget);
    expect(
      tester.widget<TvTextField>(find.byType(TvTextField)).enabled,
      isFalse,
    );

    await tester.tap(find.text('Skip'), warnIfMissed: false);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('Real-Debrid'), findsOneWidget);
    expect(find.text('TorBox'), findsNothing);

    validation.complete(false);
    await tester.pump();
    await tester.pump();
    expect(
      tester.widget<TvTextField>(find.byType(TvTextField)).enabled,
      isTrue,
    );
    await tester.tap(find.text('Skip'));
    await tester.pump();
    expect(find.text('TorBox'), findsOneWidget);
    expect(find.textContaining('Where should'), findsNothing);
  });
}
