import 'dart:async';

import 'package:debrify/services/engine/remote_engine_manager.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/widgets/initial_setup_flow.dart';
import 'package:debrify/widgets/onboarding/onboarding_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'onboarding_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'mode → services → engines off → trackers skip → done returns false',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await tester.binding.setSurfaceSize(const Size(800, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final engines = FakeRemoteEngineManager(
        List<RemoteEngineInfo>.generate(
          3,
          (index) => RemoteEngineInfo(
            id: 'engine_$index',
            fileName: 'engine_$index.yaml',
            displayName: 'Engine $index',
          ),
        ),
      );
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () async {
                  result = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => OnboardingTheme.scope(
                        InitialSetupFlow(
                          isTelevisionOverride: false,
                          engineManager: engines,
                        ),
                      ),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Set it up here'));
      await tester.pump();
      await tester.tap(find.text("I don't have any"));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('All 3 selected'), findsOneWidget);
      await tester.tap(find.text('Turn all off'));
      await tester.pump();
      await tester.tap(find.textContaining('Continue'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Skip both'));
      await tester.pump();
      expect(find.textContaining("You're ready"), findsOneWidget);
      await tester.tap(find.textContaining('Start watching'));
      await tester.pumpAndSettle();

      expect(result, isFalse);
      expect(await StorageService.isInitialSetupComplete(), isTrue);
    },
  );

  testWidgets('a successful default engine import returns true', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.binding.setSurfaceSize(const Size(800, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final engines = FakeRemoteEngineManager(<RemoteEngineInfo>[
      RemoteEngineInfo(
        id: 'alpha',
        fileName: 'alpha.yaml',
        displayName: 'Alpha',
      ),
    ]);
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              result = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => OnboardingTheme.scope(
                    InitialSetupFlow(
                      isTelevisionOverride: false,
                      engineManager: engines,
                      engineImportOverride: (_, __) async => true,
                    ),
                  ),
                ),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set it up here'));
    await tester.pump();
    await tester.tap(find.text("I don't have any"));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('All 1 selected'), findsOneWidget);
    await tester.tap(find.textContaining('Continue'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Skip both'));
    await tester.pump();
    await tester.tap(find.textContaining('Start watching'));
    await tester.pumpAndSettle();

    expect(result, isTrue);
    expect(await StorageService.isInitialSetupComplete(), isTrue);
  });

  testWidgets('Back cancels an in-flight engine import transition', (
    tester,
  ) async {
    final importResult = Completer<bool>();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.binding.setSurfaceSize(const Size(800, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingTheme.scope(
          InitialSetupFlow(
            isTelevisionOverride: false,
            engineManager: FakeRemoteEngineManager(<RemoteEngineInfo>[
              RemoteEngineInfo(
                id: 'alpha',
                fileName: 'alpha.yaml',
                displayName: 'Alpha',
              ),
            ]),
            engineImportOverride: (_, __) => importResult.future,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Set it up here'));
    await tester.pump();
    await tester.tap(find.text("I don't have any"));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.textContaining('Continue'));
    await tester.pump();
    expect(find.text('Importing…'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.textContaining('Which services'), findsOneWidget);
    importResult.complete(true);
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Which services'), findsOneWidget);
    expect(find.textContaining('Keep your'), findsNothing);
  });

  testWidgets('an offline engine catalogue can be skipped', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.binding.setSurfaceSize(const Size(800, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingTheme.scope(
          InitialSetupFlow(
            isTelevisionOverride: false,
            engineManager: _FailingRemoteEngineManager(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Set it up here'));
    await tester.pump();
    await tester.tap(find.text("I don't have any"));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Try again'), findsOneWidget);
    expect(find.textContaining('Skip engines'), findsOneWidget);
    await tester.tap(find.textContaining('Skip engines'));
    await tester.pump();
    expect(find.textContaining('Keep your'), findsOneWidget);
  });

  testWidgets('system Back on mode leaves and marks setup complete', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              result = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => OnboardingTheme.scope(
                    InitialSetupFlow(
                      isTelevisionOverride: false,
                      engineManager: FakeRemoteEngineManager(
                        const <RemoteEngineInfo>[],
                      ),
                    ),
                  ),
                ),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(result, isFalse);
    expect(await StorageService.isInitialSetupComplete(), isTrue);
  });
}

class _FailingRemoteEngineManager extends RemoteEngineManager {
  @override
  Future<List<RemoteEngineInfo>> fetchAvailableEngines() async {
    throw Exception('offline');
  }

  @override
  void dispose() {}
}
