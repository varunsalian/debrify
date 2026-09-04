import 'dart:async';
import 'dart:typed_data';

import 'package:debrify/models/webdav_item.dart';
import 'package:debrify/screens/settings/profile_backup_flows.dart';
import 'package:debrify/services/engine/remote_engine_manager.dart';
import 'package:debrify/services/mdblist/mdblist_service.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_restore_coordinator.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/webdav_protocol_client.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_activation.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_binding_store.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_codec.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_connect_controller.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_engine.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_models.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_runtime.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_setup_authorization.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_setup_service.dart';
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

  testWidgets('cancelled WebDAV login leaves unrelated staging untouched', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    DeviceKeyProvider.debugInstallCipher(
      MemoryDeviceSecretCipher(List<int>.filled(32, 8)),
    );
    addTearDown(DeviceKeyProvider.debugReset);
    final store = WebDavSyncBindingStore();
    await store.stageBinding(
      location: WebDavSyncFolderLocation(
        endpoint: 'https://example.test/dav',
        folderPath: 'Debrify',
        serverName: 'Server',
      ),
      config: _webDavConfig,
      syncPassphrase: 'circle-secret',
      completeOnboarding: true,
    );
    final controller = createWebDavSyncConnectController(
      setupService: WebDavSyncSetupService(
        store: store,
        transportFactory: ({required endpoint, required credentials}) =>
            _OnboardingWebDavProbe(),
      ),
      authorization: const _OnboardingWebDavAuthorization(),
      activation: null,
    );
    final result = ValueNotifier<bool?>(null);
    addTearDown(result.dispose);
    await _pumpWebDavOnboarding(
      tester,
      controller: controller,
      result: result,
      login: (_, __) async => null,
    );

    await tester.tap(find.text('Log in with WebDAV'));
    await tester.pumpAndSettle();

    expect(find.text('Log in with WebDAV'), findsOneWidget);
    expect(result.value, isNull);
    expect((await store.load()).stagedBinding, isNotNull);
  });

  testWidgets('WebDAV authentication failure returns inline on mode', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    DeviceKeyProvider.debugInstallCipher(
      MemoryDeviceSecretCipher(List<int>.filled(32, 8)),
    );
    addTearDown(DeviceKeyProvider.debugReset);
    final store = WebDavSyncBindingStore();
    final controller = createWebDavSyncConnectController(
      setupService: WebDavSyncSetupService(
        store: store,
        transportFactory: ({required endpoint, required credentials}) =>
            _OnboardingWebDavProbe(
              error: const WebDavException(
                kind: WebDavErrorKind.authentication,
                message: 'login failed',
              ),
            ),
      ),
      authorization: const _OnboardingWebDavAuthorization(),
      activation: null,
    );
    final result = ValueNotifier<bool?>(null);
    addTearDown(result.dispose);
    await _pumpWebDavOnboarding(
      tester,
      controller: controller,
      result: result,
      login: (_, __) async => _webDavCredentials,
    );

    await tester.tap(find.text('Log in with WebDAV'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Could not connect this account. Check your details and try again.',
      ),
      findsOneWidget,
    );
    expect(find.text('Log in with WebDAV'), findsOneWidget);
    expect(result.value, isNull);
    expect((await store.load()).stagedBinding, isNull);
  });

  testWidgets('new-circle activation failure stays inline before handoff', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    DeviceKeyProvider.debugInstallCipher(
      MemoryDeviceSecretCipher(List<int>.filled(32, 8)),
    );
    addTearDown(DeviceKeyProvider.debugReset);
    final store = WebDavSyncBindingStore();
    final controller = createWebDavSyncConnectController(
      setupService: WebDavSyncSetupService(
        store: store,
        transportFactory: ({required endpoint, required credentials}) =>
            const _OnboardingWebDavProbe(),
      ),
      authorization: const _OnboardingWebDavAuthorization(),
      activation: const _FailingNewCircleActivation(),
    );
    final result = ValueNotifier<bool?>(null);
    addTearDown(result.dispose);
    await _pumpWebDavOnboarding(
      tester,
      controller: controller,
      result: result,
      login: (_, __) async => _webDavCredentials,
    );

    await tester.tap(find.text('Log in with WebDAV'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Could not connect this account. Check your details and try again.',
      ),
      findsOneWidget,
    );
    expect(find.text('Log in with WebDAV'), findsOneWidget);
    expect(result.value, isNull);
    expect(await StorageService.isInitialSetupComplete(), isFalse);
    expect((await store.load()).bindings, isEmpty);
  });

  testWidgets('inconclusive WebDAV setup stays open with retryable message', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    DeviceKeyProvider.debugInstallCipher(
      MemoryDeviceSecretCipher(List<int>.filled(32, 8)),
    );
    addTearDown(DeviceKeyProvider.debugReset);
    final store = WebDavSyncBindingStore();
    final controller = createWebDavSyncConnectController(
      setupService: WebDavSyncSetupService(
        store: store,
        transportFactory: ({required endpoint, required credentials}) =>
            const _OnboardingWebDavProbe(),
      ),
      authorization: const _OnboardingWebDavAuthorization(),
      activation: const _InconclusiveNewCircleActivation(),
    );
    final result = ValueNotifier<bool?>(null);
    addTearDown(result.dispose);
    await _pumpWebDavOnboarding(
      tester,
      controller: controller,
      result: result,
      login: (_, __) async => _webDavCredentials,
    );

    await tester.tap(find.text('Log in with WebDAV'));
    await tester.pumpAndSettle();

    expect(
      find.text(WebDavSyncSetupInconclusiveException.userMessage),
      findsOneWidget,
    );
    expect(find.text('Log in with WebDAV'), findsOneWidget);
    expect(result.value, isNull);
    expect(await StorageService.isInitialSetupComplete(), isFalse);
    expect((await store.load()).bindings, isEmpty);
  });

  testWidgets('new WebDAV circle blocks, then finishes onboarding normally', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    DeviceKeyProvider.debugInstallCipher(
      MemoryDeviceSecretCipher(List<int>.filled(32, 8)),
    );
    addTearDown(DeviceKeyProvider.debugReset);
    final store = WebDavSyncBindingStore();
    final activation = _NewCircleActivation(store);
    final controller = createWebDavSyncConnectController(
      setupService: WebDavSyncSetupService(
        store: store,
        transportFactory: ({required endpoint, required credentials}) =>
            _OnboardingWebDavProbe(),
      ),
      authorization: const _OnboardingWebDavAuthorization(),
      activation: activation,
    );
    final result = ValueNotifier<bool?>(null);
    addTearDown(result.dispose);
    await _pumpWebDavOnboarding(
      tester,
      controller: controller,
      result: result,
      login: (_, __) async => _webDavCredentials,
    );

    await tester.tap(find.text('Log in with WebDAV'));
    for (var i = 0; i < 10 && !activation.started.isCompleted; i++) {
      await tester.pump();
    }
    expect(activation.started.isCompleted, isTrue);
    expect(find.text('Connecting your setup…'), findsOneWidget);
    expect(find.text('Set it up here'), findsNothing);

    activation.release.complete();
    await tester.pumpAndSettle();

    expect(result.value, isTrue);
    expect(await StorageService.isInitialSetupComplete(), isTrue);
    expect((await store.load()).activeBinding?.completeOnboarding, isFalse);
  });

  testWidgets('adopted WebDAV join fails soft when handoff remounts the UI', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    DeviceKeyProvider.debugInstallCipher(
      MemoryDeviceSecretCipher(List<int>.filled(32, 8)),
    );
    addTearDown(DeviceKeyProvider.debugReset);
    final store = WebDavSyncBindingStore();
    final codec = WebDavSyncCodec(
      randomBytes: (length) => Uint8List.fromList(
        List<int>.generate(length, (index) => index & 0xff),
      ),
    );
    final marker = await codec.sealRoot(
      passphrase: 'circle-secret',
      circleId: 'existing-circle',
      createdAt: DateTime.utc(2026, 9, 1),
      memoryKiB: 8,
      iterations: 1,
    );
    final activation = _AdoptedCircleActivation(store);
    final controller = createWebDavSyncConnectController(
      setupService: WebDavSyncSetupService(
        store: store,
        codec: codec,
        runCryptoInBackground: false,
        transportFactory: ({required endpoint, required credentials}) =>
            _ExistingOnboardingWebDavProbe(marker),
      ),
      authorization: const _OnboardingWebDavAuthorization(),
      activation: activation,
    );
    final result = ValueNotifier<bool?>(null);
    addTearDown(result.dispose);
    await _pumpWebDavOnboarding(
      tester,
      controller: controller,
      result: result,
      login: (_, __) async => _webDavCredentials,
    );

    await tester.tap(find.text('Log in with WebDAV'));
    for (
      var i = 0;
      i < 20 && find.text('Use this synced setup?').evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.text('Use this synced setup?'), findsOneWidget);
    await tester.tap(find.text('Use synced setup'));
    for (var i = 0; i < 10 && !activation.started.isCompleted; i++) {
      await tester.pump();
    }

    expect(activation.started.isCompleted, isTrue);
    expect(activation.onboardingCompletedAtomically, isTrue);
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    activation.release.complete();
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('post-handoff failure completes already-committed onboarding', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    DeviceKeyProvider.debugInstallCipher(
      MemoryDeviceSecretCipher(List<int>.filled(32, 8)),
    );
    addTearDown(DeviceKeyProvider.debugReset);
    final store = WebDavSyncBindingStore();
    final codec = WebDavSyncCodec(
      randomBytes: (length) => Uint8List.fromList(
        List<int>.generate(length, (index) => index & 0xff),
      ),
    );
    final marker = await codec.sealRoot(
      passphrase: 'circle-secret',
      circleId: 'existing-circle',
      createdAt: DateTime.utc(2026, 9, 1),
      memoryKiB: 8,
      iterations: 1,
    );
    final controller = createWebDavSyncConnectController(
      setupService: WebDavSyncSetupService(
        store: store,
        codec: codec,
        runCryptoInBackground: false,
        transportFactory: ({required endpoint, required credentials}) =>
            _ExistingOnboardingWebDavProbe(marker),
      ),
      authorization: const _OnboardingWebDavAuthorization(),
      activation: const _PostHandoffActivation(),
    );
    final result = ValueNotifier<bool?>(null);
    addTearDown(result.dispose);
    await _pumpWebDavOnboarding(
      tester,
      controller: controller,
      result: result,
      login: (_, __) async => _webDavCredentials,
    );

    await tester.tap(find.text('Log in with WebDAV'));
    // The connecting spinner animates behind the awaited confirmation dialog,
    // so settling can never end; pump bounded frames until the dialog shows.
    for (
      var i = 0;
      i < 20 && find.text('Use synced setup').evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.tap(find.text('Use synced setup'));
    // The flow keeps its finishing spinner up after a committed handoff (the
    // profile remount replaces it in production), so settling never ends.
    // Pump bounded frames until the flow reports completion instead.
    for (var i = 0; i < 20 && result.value == null; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(result.value, isTrue);
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

const _webDavConfig = WebDavConfig(
  id: 'webdav-sync-login',
  name: 'Server',
  baseUrl: 'https://example.test/dav/',
  username: 'alice',
  password: 'secret',
);

final _webDavCredentials = WebDavSyncLoginCredentials(
  endpoint: Uri.parse(_webDavConfig.baseUrl),
  username: _webDavConfig.username,
  password: _webDavConfig.password,
  serverName: _webDavConfig.name,
);

Future<void> _pumpWebDavOnboarding(
  WidgetTester tester, {
  required WebDavSyncConnectController controller,
  required ValueNotifier<bool?> result,
  required OnboardingWebDavSyncLoginOverride login,
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => FilledButton(
          onPressed: () async {
            result.value = await Navigator.of(context).push<bool>(
              MaterialPageRoute(
                builder: (_) => OnboardingTheme.scope(
                  InitialSetupFlow(
                    isTelevisionOverride: false,
                    engineManager: FakeRemoteEngineManager(
                      const <RemoteEngineInfo>[],
                    ),
                    webDavSyncConnectController: controller,
                    webDavSyncLoginOverride: login,
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
}

final class _OnboardingWebDavAuthorization
    implements WebDavSyncSetupAuthorization {
  const _OnboardingWebDavAuthorization();

  @override
  Future<void> requireAdmin() async {}

  @override
  Future<T> runForAdminSession<T>(
    Future<T> Function(Future<void> Function()? beforeSend) body,
  ) => body(null);

  @override
  Future<T> runForActiveBinding<T>(
    Future<T> Function(Future<void> Function()? beforeSend) body,
  ) => body(null);
}

final class _OnboardingWebDavProbe implements WebDavSyncProbeTransport {
  const _OnboardingWebDavProbe({this.error});

  final WebDavException? error;

  @override
  Future<WebDavBytesResult> readRootMarker({
    required String path,
    Future<void> Function()? beforeSend,
  }) async =>
      throw error ??
          const WebDavException(
            kind: WebDavErrorKind.notFound,
            message: 'missing',
          );

  @override
  Future<WebDavBytesResult> readRootKey({
    required String path,
    Future<void> Function()? beforeSend,
  }) async =>
      throw error ??
          const WebDavException(
            kind: WebDavErrorKind.notFound,
            message: 'missing',
          );

  @override
  void close() {}
}

final class _ExistingOnboardingWebDavProbe implements WebDavSyncProbeTransport {
  _ExistingOnboardingWebDavProbe(this.marker);

  final Uint8List marker;

  WebDavBytesResult _result(Uint8List bytes, String path) => WebDavBytesResult(
    bytes: bytes,
    metadata: WebDavResponseMetadata(
      statusCode: 200,
      uri: Uri.parse('https://example.test/dav/$path'),
      headers: const <String, String>{},
    ),
  );

  @override
  Future<WebDavBytesResult> readRootMarker({
    required String path,
    Future<void> Function()? beforeSend,
  }) async => _result(marker, path);

  @override
  Future<WebDavBytesResult> readRootKey({
    required String path,
    Future<void> Function()? beforeSend,
  }) async => _result(
    WebDavSyncRootKeyFile(syncPassphrase: 'circle-secret').encode(),
    path,
  );

  @override
  void close() {}
}

final class _NewCircleActivation implements WebDavSyncActivationController {
  _NewCircleActivation(this.store);

  final WebDavSyncBindingStore store;
  final Completer<void> started = Completer<void>();
  final Completer<void> release = Completer<void>();

  @override
  Future<WebDavSyncInitializationOutcome> initializeNew(
    String bindingId,
  ) async {
    started.complete();
    await release.future;
    final verified = await store.markRootVerified(
      bindingId: bindingId,
      root: WebDavSyncRootDocument(
        circleId: 'new-circle',
        createdAt: DateTime.utc(2026, 9, 4),
        schemaFloor: 1,
        kdfSalt: Uint8List(16),
      ),
      markerBytes: const <int>[1, 2, 3],
    );
    final active = await store.activateAndPromoteStaged(verified.id);
    return WebDavSyncInitialized(active);
  }

  @override
  Future<void> inspectExisting(String bindingId) async {}

  @override
  Future<WebDavSyncBinding> connectExisting(
    String bindingId, {
    required bool replacementConfirmed,
  }) => throw UnimplementedError();

  @override
  Future<WebDavSyncCycleReport> syncNow() => throw UnimplementedError();
}

final class _FailingNewCircleActivation
    implements WebDavSyncActivationController {
  const _FailingNewCircleActivation();

  @override
  Future<WebDavSyncInitializationOutcome> initializeNew(String bindingId) =>
      throw StateError('seed upload failed');

  @override
  Future<void> inspectExisting(String bindingId) async {}

  @override
  Future<WebDavSyncBinding> connectExisting(
    String bindingId, {
    required bool replacementConfirmed,
  }) => throw UnimplementedError();

  @override
  Future<WebDavSyncCycleReport> syncNow() => throw UnimplementedError();
}

final class _InconclusiveNewCircleActivation
    implements WebDavSyncActivationController {
  const _InconclusiveNewCircleActivation();

  @override
  Future<WebDavSyncInitializationOutcome> initializeNew(String bindingId) =>
      throw const WebDavSyncSetupInconclusiveException();

  @override
  Future<void> inspectExisting(String bindingId) async {}

  @override
  Future<WebDavSyncBinding> connectExisting(
    String bindingId, {
    required bool replacementConfirmed,
  }) => throw UnimplementedError();

  @override
  Future<WebDavSyncCycleReport> syncNow() => throw UnimplementedError();
}

final class _PostHandoffActivation implements WebDavSyncActivationController {
  const _PostHandoffActivation();

  @override
  Future<void> inspectExisting(String bindingId) async {}

  @override
  Future<WebDavSyncBinding> connectExisting(
    String bindingId, {
    required bool replacementConfirmed,
  }) async {
    await StorageService.setInitialSetupComplete(true);
    throw WebDavSyncPostHandoffException(StateError('warmup failed'));
  }

  @override
  Future<WebDavSyncInitializationOutcome> initializeNew(String bindingId) =>
      throw UnimplementedError();

  @override
  Future<WebDavSyncCycleReport> syncNow() => throw UnimplementedError();
}

final class _AdoptedCircleActivation implements WebDavSyncActivationController {
  _AdoptedCircleActivation(this.store);

  final WebDavSyncBindingStore store;
  final Completer<void> started = Completer<void>();
  final Completer<void> release = Completer<void>();
  bool onboardingCompletedAtomically = false;

  @override
  Future<void> inspectExisting(String bindingId) async {}

  @override
  Future<WebDavSyncBinding> connectExisting(
    String bindingId, {
    required bool replacementConfirmed,
  }) async {
    expect(replacementConfirmed, isTrue);
    onboardingCompletedAtomically = true;
    started.complete();
    await release.future;
    await store.activateAndPromoteStaged(bindingId);
    await store.acknowledgeOnboardingIntent(bindingId);
    return (await store.load()).activeBinding!;
  }

  @override
  Future<WebDavSyncInitializationOutcome> initializeNew(String bindingId) =>
      throw UnimplementedError();

  @override
  Future<WebDavSyncCycleReport> syncNow() => throw UnimplementedError();
}
