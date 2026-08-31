import 'dart:async';

import 'package:debrify/screens/settings/profile_backup_flows.dart';
import 'package:debrify/services/engine/remote_engine_manager.dart';
import 'package:debrify/services/mdblist/mdblist_service.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_restore_coordinator.dart';
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
      await tester.tap(
        find.text(kMdblistEnabled ? 'Skip trackers' : 'Skip both'),
      );
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
    await tester.tap(
      find.text(kMdblistEnabled ? 'Skip trackers' : 'Skip both'),
    );
    await tester.pump();
    await tester.tap(find.textContaining('Start watching'));
    await tester.pumpAndSettle();

    expect(result, isTrue);
    expect(await StorageService.isInitialSetupComplete(), isTrue);
  });

  testWidgets('backup restore only completes onboarding after success', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.binding.setSurfaceSize(const Size(800, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var restoreSucceeds = false;
    var restoreCalls = 0;
    var handoffCalls = 0;
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
                      backupRestoreOverride: () async {
                        restoreCalls++;
                        return restoreSucceeds
                            ? const ProfileBackupRestoreResult.singleProfile(
                                authorizingProfileId: 'profile-test',
                              )
                            : null;
                      },
                      backupHandoffOverride: (_) async => handoffCalls++,
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
    expect(find.text('Restore from a backup'), findsOneWidget);

    await tester.tap(find.text('Restore from a backup'));
    await tester.pump();
    expect(restoreCalls, 1);
    expect(result, isNull);
    expect(find.text('Restore from a backup'), findsOneWidget);
    expect(await StorageService.isInitialSetupComplete(), isFalse);

    restoreSucceeds = true;
    await tester.tap(find.text('Restore from a backup'));
    await tester.pumpAndSettle();
    expect(restoreCalls, 2);
    expect(handoffCalls, 0);
    expect(result, isTrue);
    expect(await StorageService.isInitialSetupComplete(), isTrue);
  });

  testWidgets(
    'device-graph restore clears setup before handing off authority',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await tester.binding.setSurfaceSize(const Size(800, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final report = ProfileGraphRestoreReport(
        profilesImported: 2,
        resourcesImported: 1,
        grantsImported: 1,
        bindingsImported: 0,
        pinResetsRequired: 0,
        importedProfileIds: const <String>[
          'profile-imported-admin',
          'profile-imported-member',
        ],
      );
      var handoffCalls = 0;
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
                        backupRestoreOverride: () async =>
                            ProfileBackupRestoreResult.deviceGraph(
                              authorizingProfileId:
                                  ProfileBootstrap.freshAdminId,
                              graphReport: report,
                            ),
                        backupHandoffOverride: (receivedReport) async {
                          handoffCalls++;
                          expect(receivedReport, same(report));
                          expect(
                            await StorageService.isInitialSetupComplete(),
                            isTrue,
                            reason:
                                'the bootstrap session must clear onboarding '
                                'before switching profiles',
                          );
                        },
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
      await tester.tap(find.text('Restore from a backup'));
      await tester.pumpAndSettle();

      expect(handoffCalls, 1);
      expect(result, isTrue);
      expect(await StorageService.isInitialSetupComplete(), isTrue);
    },
  );

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
