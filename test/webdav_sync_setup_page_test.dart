import 'dart:convert';
import 'dart:typed_data';

import 'package:debrify/models/webdav_item.dart';
import 'package:debrify/screens/settings/sync_and_migrate_page.dart';
import 'package:debrify/screens/webdav/webdav_files_screen.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/text_brightness.dart';
import 'package:debrify/services/webdav_protocol_client.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_binding_store.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_activation.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_codec.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_engine.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_models.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_runtime.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_setup_authorization.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_setup_service.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_adapter.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _config = WebDavConfig(
  id: 'server',
  name: 'Family server',
  baseUrl: 'https://example.test/dav',
  username: 'alice',
  password: 'secret',
  connectionResourceId: 'resource',
  connectionResourceRevision: 4,
);

void main() {
  late WebDavSyncBindingStore store;
  late WebDavSyncCodec codec;
  late _FakeTransport transport;
  late WebDavSyncSetupService service;
  late _AllowAuthorization authorization;

  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    DeviceKeyProvider.debugInstallCipher(
      MemoryDeviceSecretCipher(List<int>.filled(32, 9)),
    );
    var random = 0;
    store = WebDavSyncBindingStore(
      randomBytes: (length) => Uint8List.fromList(
        List<int>.generate(length, (_) => random++ & 0xff),
      ),
    );
    codec = WebDavSyncCodec(
      randomBytes: (length) =>
          Uint8List.fromList(List<int>.generate(length, (index) => index)),
    );
    transport = _FakeTransport();
    service = WebDavSyncSetupService(
      store: store,
      codec: codec,
      runCryptoInBackground: false,
      transportFactory: ({required endpoint, required credentials}) =>
          transport,
    );
    authorization = _AllowAuthorization();
  });

  tearDown(DeviceKeyProvider.debugReset);

  Future<void> pumpPage(
    WidgetTester tester, {
    required bool enabled,
    WebDavSyncActivationController? activation,
    String folderPath = 'Family/Sync/',
    bool settle = true,
  }) async {
    final theme = AppThemes.byId('spotlight');
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeAdapter.themed(theme, TextBrightness.bright),
        builder: (context, child) => AppThemeScope(theme: theme, child: child!),
        home: SyncAndMigratePage(
          syncFeatureEnabled: enabled,
          syncService: service,
          syncAuthorization: authorization,
          syncActivation: activation,
          pickSyncFolder: (_) async =>
              WebDavPickerResult(config: _config, path: folderPath),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('M3 setup stays hidden behind its rollout gate', (tester) async {
    await pumpPage(tester, enabled: false);

    expect(find.text('Enable WebDAV Sync'), findsNothing);
    expect(find.text('Save backup to WebDAV'), findsOneWidget);
  });

  testWidgets(
    '404 warning shows exact resolved folder and Back writes nothing',
    (tester) async {
      transport.error = const WebDavException(
        kind: WebDavErrorKind.notFound,
        message: 'missing',
      );
      await pumpPage(tester, enabled: true);

      await tester.tap(find.text('Enable WebDAV Sync'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.text(
          'No existing Debrify sync was found in this folder. '
          'Continuing will create a new sync here.',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('https://example.test/dav/Family/Sync/'),
        findsOneWidget,
      );

      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect((await store.load()).bindings, isEmpty);
      expect(transport.reads, 1);
    },
  );

  testWidgets('404 continuation creates only local awaiting state', (
    tester,
  ) async {
    transport.error = const WebDavException(
      kind: WebDavErrorKind.notFound,
      message: 'missing',
    );
    await pumpPage(tester, enabled: true);

    await tester.tap(find.text('Enable WebDAV Sync'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Create sync passphrase'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'circle-secret');
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Ready to initialize this folder'), findsOneWidget);
    final binding = (await store.load()).stagedBinding!;
    expect(binding.lifecycle, WebDavSyncLifecycle.awaitingSeedCommit);
    expect(transport.reads, 1);
    expect(authorization.barriers, 3);
  });

  testWidgets('existing marker asks only for the sync passphrase', (
    tester,
  ) async {
    transport.bytes = await codec.sealRoot(
      passphrase: 'circle-secret',
      circleId: 'circle-1',
      createdAt: DateTime.utc(2026, 9, 1),
      memoryKiB: 8,
      iterations: 1,
    );
    await pumpPage(tester, enabled: true);

    await tester.tap(find.text('Enable WebDAV Sync'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Sync passphrase'), findsOneWidget);
    expect(find.textContaining('No existing Debrify sync'), findsNothing);
    await tester.enterText(find.byType(TextField), 'circle-secret');
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Folder verified'), findsOneWidget);
    final binding = (await store.load()).stagedBinding!;
    expect(binding.lifecycle, WebDavSyncLifecycle.rootVerified);
    expect(binding.circleId, 'circle-1');
    expect(authorization.barriers, 3);
  });

  testWidgets('rendered setup copy contains no protocol vocabulary', (
    tester,
  ) async {
    await pumpPage(tester, enabled: true);
    final copy = tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data ?? '')
        .join(' ')
        .toLowerCase();

    expect(copy, isNot(contains('circle')));
    expect(copy, isNot(contains('enrollment')));
    expect(copy, isNot(contains('seed')));
    expect(copy, isNot(contains('join')));
  });

  testWidgets('awaiting first sync is progress, not an error', (tester) async {
    final marker = await codec.sealRoot(
      passphrase: 'circle-secret',
      circleId: 'circle-1',
      createdAt: DateTime.utc(2026, 9, 1),
      memoryKiB: 8,
      iterations: 1,
    );
    final root = await codec.openRoot(
      marker,
      'circle-secret',
      runInBackground: false,
    );
    var waiting = await store.stageBinding(
      location: WebDavSyncFolderLocation.fromConfig(_config, 'Family/Sync/'),
      config: _config,
      syncPassphrase: 'circle-secret',
    );
    waiting = await store.markRootVerified(
      bindingId: waiting.id,
      root: root.document,
      markerBytes: marker,
    );
    await store.setLifecycle(waiting.id, WebDavSyncLifecycle.awaitingAdoption);

    await pumpPage(tester, enabled: true, settle: false);

    expect(find.text('Finishing first sync…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('terminal first-sync failure replaces progress with error', (
    tester,
  ) async {
    final marker = await codec.sealRoot(
      passphrase: 'circle-secret',
      circleId: 'circle-1',
      createdAt: DateTime.utc(2026, 9, 1),
      memoryKiB: 8,
      iterations: 1,
    );
    final root = await codec.openRoot(
      marker,
      'circle-secret',
      runInBackground: false,
    );
    var waiting = await store.stageBinding(
      location: WebDavSyncFolderLocation.fromConfig(_config, 'Family/Sync/'),
      config: _config,
      syncPassphrase: 'circle-secret',
    );
    waiting = await store.markRootVerified(
      bindingId: waiting.id,
      root: root.document,
      markerBytes: marker,
    );
    await store.setLifecycle(waiting.id, WebDavSyncLifecycle.awaitingAdoption);
    await store.markAwaitingAdoptionError(
      waiting.id,
      StateError('First sync needs a manual retry'),
    );

    await pumpPage(tester, enabled: true);

    expect(find.text('First sync needs a manual retry'), findsOneWidget);
    expect(find.text('Finishing first sync…'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('setup discloses the bounded TV database fallback', (
    tester,
  ) async {
    await pumpPage(tester, enabled: true);

    expect(
      find.text(
        'IPTV sources, favorites, history and resume state transfer. Each '
        'device rebuilds its channel and guide caches. Debrify TV channels '
        'do not transfer yet.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('low-level failures cannot leak protocol vocabulary', (
    tester,
  ) async {
    final marker = await codec.sealRoot(
      passphrase: 'circle-secret',
      circleId: 'circle-1',
      createdAt: DateTime.utc(2026, 9, 1),
      memoryKiB: 8,
      iterations: 1,
    );
    final root = await codec.openRoot(
      marker,
      'circle-secret',
      runInBackground: false,
    );
    var active = await store.stageBinding(
      location: WebDavSyncFolderLocation.fromConfig(_config, 'Family/Sync/'),
      config: _config,
      syncPassphrase: 'circle-secret',
    );
    active = await store.markRootVerified(
      bindingId: active.id,
      root: root.document,
      markerBytes: marker,
    );
    active = await store.setLifecycle(active.id, WebDavSyncLifecycle.active);
    await store.promoteStaged(active.id);
    final activation = _FakeActivation(store)
      ..syncError = StateError(
        'internal circle seed join enrollment operation failed',
      );
    await pumpPage(tester, enabled: true, activation: activation);

    await tester.tap(find.text('Sync now'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'WebDAV Sync could not complete this operation. '
        'Try again or verify the selected folder.',
      ),
      findsOneWidget,
    );
    final copy = tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data ?? '')
        .join(' ')
        .toLowerCase();
    expect(copy, isNot(contains('circle')));
    expect(copy, isNot(contains('enrollment')));
    expect(copy, isNot(contains('seed')));
    expect(copy, isNot(contains('join')));
  });

  testWidgets(
    'existing root is verified before mandatory replacement consent',
    (tester) async {
      transport.bytes = await codec.sealRoot(
        passphrase: 'circle-secret',
        circleId: 'circle-1',
        createdAt: DateTime.utc(2026, 9, 1),
        memoryKiB: 8,
        iterations: 1,
      );
      final activation = _FakeActivation(store);
      await pumpPage(tester, enabled: true, activation: activation);

      await tester.tap(find.text('Enable WebDAV Sync'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(find.byType(TextField), 'circle-secret');
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(activation.inspections, 1);
      expect(find.text('Use sync data from this folder?'), findsOneWidget);
      expect(
        find.textContaining('Existing profiles and connections'),
        findsOneWidget,
      );
      await tester.tap(find.text('Use sync data'));
      await tester.pumpAndSettle();

      expect(activation.connections, 1);
      expect(find.text('Sync is active'), findsOneWidget);
      expect(find.text('Sync now'), findsOneWidget);
    },
  );

  testWidgets('revalidating the active folder does not prompt replacement', (
    tester,
  ) async {
    final marker = await codec.sealRoot(
      passphrase: 'circle-secret',
      circleId: 'circle-1',
      createdAt: DateTime.utc(2026, 9, 1),
      memoryKiB: 8,
      iterations: 1,
    );
    transport.bytes = marker;
    final inspection = await service.inspectFolder(
      config: _config,
      folderPath: 'Family/Sync/',
    );
    var active = await service.configureExistingRoot(
      inspection: inspection as WebDavSyncFolderExisting,
      syncPassphrase: 'circle-secret',
    );
    active = await store.setLifecycle(active.id, WebDavSyncLifecycle.active);
    await store.promoteStaged(active.id);
    final activation = _FakeActivation(store);
    await pumpPage(tester, enabled: true, activation: activation);

    await tester.tap(find.text('Change sync folder'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(TextField), 'circle-secret');
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Use sync data from this folder?'), findsNothing);
    expect(activation.inspections, 0);
    expect(activation.connections, 0);
    final refreshed = await store.load();
    expect(refreshed.activeBindingId, active.id);
    expect(refreshed.activeBinding?.lifecycle, WebDavSyncLifecycle.active);
    expect(find.text('Change sync folder'), findsOneWidget);
  });

  testWidgets(
    'committed root-last candidate resumes without replacement consent',
    (tester) async {
      transport.error = const WebDavException(
        kind: WebDavErrorKind.notFound,
        message: 'missing',
      );
      final missing = await service.inspectFolder(
        config: _config,
        folderPath: 'Family/Sync/',
      );
      final candidate = await service.configureNewRoot(
        inspection: missing as WebDavSyncFolderMissing,
        syncPassphrase: 'circle-secret',
      );
      final marker = await codec.sealRoot(
        passphrase: 'circle-secret',
        circleId: 'candidate-circle',
        createdAt: DateTime.utc(2026, 9, 1),
        memoryKiB: 8,
        iterations: 1,
      );
      final opened = await codec.openRoot(
        marker,
        'circle-secret',
        runInBackground: false,
      );
      final namespace = (await store.load()).namespaceFor(candidate)!;
      await store.updateNamespaceValues(
        namespace.id,
        (values) => <String, Object?>{
          ...values,
          WebDavSyncBindingStore.seedCandidateMarkerValueKey: base64Encode(
            marker,
          ),
        },
      );
      transport
        ..error = null
        ..bytes = marker;
      final activation = _FakeActivation(
        store,
        onInitialize: (bindingId) async {
          var active = await store.markRootVerified(
            bindingId: bindingId,
            root: opened.document,
            markerBytes: marker,
          );
          active = await store.setLifecycle(
            bindingId,
            WebDavSyncLifecycle.active,
          );
          await store.promoteStaged(bindingId);
          return WebDavSyncInitialized(active);
        },
      );
      await pumpPage(tester, enabled: true, activation: activation);

      await tester.tap(find.text('Enable WebDAV Sync'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(find.byType(TextField), 'circle-secret');
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(activation.initializations, 1);
      expect(activation.inspections, 0);
      expect(activation.connections, 0);
      expect(find.text('Use sync data from this folder?'), findsNothing);
      expect(find.text('Sync is active'), findsOneWidget);
    },
  );

  testWidgets(
    'cancelling a folder replacement restores the previous active binding',
    (tester) async {
      final oldMarker = await codec.sealRoot(
        passphrase: 'circle-secret',
        circleId: 'old-circle',
        createdAt: DateTime.utc(2026, 8, 31),
        memoryKiB: 8,
        iterations: 1,
      );
      final oldRoot = await codec.openRoot(
        oldMarker,
        'circle-secret',
        runInBackground: false,
      );
      var oldBinding = await store.stageBinding(
        location: WebDavSyncFolderLocation.fromConfig(_config, 'Old'),
        config: _config,
        syncPassphrase: 'circle-secret',
      );
      oldBinding = await store.markRootVerified(
        bindingId: oldBinding.id,
        root: oldRoot.document,
        markerBytes: oldMarker,
      );
      oldBinding = await store.setLifecycle(
        oldBinding.id,
        WebDavSyncLifecycle.active,
      );
      await store.promoteStaged(oldBinding.id);
      transport.bytes = await codec.sealRoot(
        passphrase: 'circle-secret',
        circleId: 'new-circle',
        createdAt: DateTime.utc(2026, 9, 1),
        memoryKiB: 8,
        iterations: 1,
      );
      final activation = _FakeActivation(store);
      await pumpPage(
        tester,
        enabled: true,
        activation: activation,
        folderPath: 'New',
      );

      await tester.tap(find.text('Change sync folder'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(find.byType(TextField), 'circle-secret');
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      final snapshot = await store.load();
      expect(snapshot.activeBindingId, oldBinding.id);
      expect(snapshot.stagedBindingId, isNull);
      expect(snapshot.activeBinding!.lifecycle, WebDavSyncLifecycle.active);
      expect(activation.connections, 0);
      expect(activation.pauses, 1);
      expect(activation.resumes, 1);
      expect(find.text('Sync is active'), findsOneWidget);
    },
  );
}

final class _AllowAuthorization implements WebDavSyncSetupAuthorization {
  int adminChecks = 0;
  int barriers = 0;

  @override
  Future<void> requireAdmin() async => adminChecks++;

  @override
  Future<T> runForConfig<T>(
    WebDavConfig config,
    Future<T> Function(Future<void> Function()? beforeSend) body,
  ) => body(() async => barriers++);

  @override
  Future<T> runForActiveBinding<T>(
    Future<T> Function(Future<void> Function()? beforeSend) body,
  ) => body(() async => barriers++);
}

final class _FakeTransport implements WebDavSyncProbeTransport {
  int reads = 0;
  Uint8List? bytes;
  Object? error;

  @override
  Future<WebDavBytesResult> readRootMarker({
    required String path,
    Future<void> Function()? beforeSend,
  }) async {
    reads++;
    await beforeSend?.call();
    if (error case final failure?) throw failure;
    return WebDavBytesResult(
      bytes: bytes ?? Uint8List(0),
      metadata: WebDavResponseMetadata(
        statusCode: 200,
        uri: Uri.parse('https://example.test/dav/$path'),
        headers: const <String, String>{},
      ),
    );
  }

  @override
  void close() {}
}

final class _FakeActivation
    implements
        WebDavSyncActivationController,
        WebDavSyncReconfigurationController {
  _FakeActivation(this.store, {this.onInitialize});

  final WebDavSyncBindingStore store;
  final Future<WebDavSyncInitializationOutcome> Function(String bindingId)?
  onInitialize;
  int inspections = 0;
  int connections = 0;
  int initializations = 0;
  int pauses = 0;
  int resumes = 0;
  Object? syncError;

  @override
  void pauseForReconfiguration() => pauses++;

  @override
  Future<void> resumeAfterReconfiguration() async => resumes++;

  @override
  Future<void> inspectExisting(String bindingId) async {
    inspections++;
    await store.setLifecycle(bindingId, WebDavSyncLifecycle.awaitingAdoption);
  }

  @override
  Future<WebDavSyncBinding> connectExisting(
    String bindingId, {
    required bool replacementConfirmed,
  }) async {
    expect(replacementConfirmed, isTrue);
    connections++;
    await store.setLifecycle(bindingId, WebDavSyncLifecycle.active);
    await store.promoteStaged(bindingId);
    return (await store.load()).activeBinding!;
  }

  @override
  Future<WebDavSyncInitializationOutcome> initializeNew(
    String bindingId,
  ) async {
    initializations++;
    final initialize = onInitialize;
    if (initialize == null) throw UnimplementedError();
    return initialize(bindingId);
  }

  @override
  Future<WebDavSyncCycleReport> syncNow() async {
    if (syncError case final error?) throw error;
    return const WebDavSyncCycleReport(
      disposition: WebDavSyncCycleDisposition.completed,
    );
  }
}
