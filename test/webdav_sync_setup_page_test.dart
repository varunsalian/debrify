import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:debrify/models/webdav_item.dart';
import 'package:debrify/screens/settings/sync_and_migrate_page.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/text_brightness.dart';
import 'package:debrify/services/webdav_protocol_client.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_binding_store.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_activation.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_codec.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_connect_controller.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_engine.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_graph_tier.dart';
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
);

void main() {
  final lastSyncLabel = RegExp(r'^Last synced 9/10/2026 5:30\sAM$');
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
    bool settle = true,
    Size size = const Size(1280, 720),
  }) async {
    final theme = AppThemes.byId('spotlight');
    await tester.binding.setSurfaceSize(size);
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
          launchSyncLogin: (_, controller) async {
            final credentials = WebDavSyncLoginCredentials(
              endpoint: Uri.parse(_config.baseUrl),
              username: _config.username,
              password: _config.password,
              serverName: _config.name,
            );
            await controller.inspect(credentials);
            return credentials;
          },
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

  Future<void> installActiveBinding() async {
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
      location: WebDavSyncFolderLocation.fromConfig(_config, 'Debrify'),
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
  }

  for (final size in [const Size(390, 844), const Size(800, 360)]) {
    testWidgets('sync settings and logout remain usable at $size', (
      tester,
    ) async {
      await installActiveBinding();
      await pumpPage(
        tester,
        enabled: true,
        activation: _FakeActivation(store),
        size: size,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Manual backups'), findsNothing);
      expect(find.text('Save backup to WebDAV'), findsNothing);
      expect(find.text('Restore backup from WebDAV'), findsNothing);
      for (final label in [
        'Sync now',
        'Connected devices',
        'Log out',
        'Sync channels now',
      ]) {
        await tester.ensureVisible(find.text(label));
        await tester.pumpAndSettle();
        expect(find.text(label).hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await tester.ensureVisible(find.text('Log out'));
      await tester.tap(find.text('Log out'));
      await tester.pumpAndSettle();
      expect(find.text('Cancel').hitTestable(), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Log out').hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  }

  testWidgets('reopening waits for saved sync history before showing status', (
    tester,
  ) async {
    await installActiveBinding();
    final activation = _FakeActivation(store)
      ..lastSuccessfulSyncMs = DateTime(
        2026,
        9,
        10,
        5,
        30,
      ).millisecondsSinceEpoch;
    await pumpPage(tester, enabled: true, activation: activation);
    expect(find.textContaining(lastSyncLabel), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    final release = Completer<void>();
    activation.statusRelease = release;
    await pumpPage(tester, enabled: true, activation: activation);
    await tester.pump(const Duration(seconds: 6));

    expect(find.text('Connected to Family server'), findsOneWidget);
    expect(find.text('Loading sync status…'), findsOneWidget);
    expect(find.text('Waiting for the first completed sync'), findsNothing);

    release.complete();
    await tester.pumpAndSettle();
    expect(find.textContaining(lastSyncLabel), findsOneWidget);
    expect(find.text('Loading sync status…'), findsNothing);
    expect(find.text('Waiting for the first completed sync'), findsNothing);
  });

  testWidgets('first-sync message requires successfully loaded empty history', (
    tester,
  ) async {
    await installActiveBinding();
    final release = Completer<void>();
    final activation = _FakeActivation(store)..statusRelease = release;
    await pumpPage(tester, enabled: true, activation: activation);

    expect(find.text('Loading sync status…'), findsOneWidget);
    expect(find.text('Waiting for the first completed sync'), findsNothing);

    release.complete();
    await tester.pumpAndSettle();
    expect(find.text('Loading sync status…'), findsNothing);
    expect(find.text('Waiting for the first completed sync'), findsOneWidget);
  });

  testWidgets('failed status read is unavailable until a refresh succeeds', (
    tester,
  ) async {
    await installActiveBinding();
    final activation = _FakeActivation(store)
      ..lastSuccessfulSyncMs = DateTime(
        2026,
        9,
        10,
        5,
        30,
      ).millisecondsSinceEpoch
      ..statusError = StateError('status temporarily unavailable');
    await pumpPage(tester, enabled: true, activation: activation);

    expect(find.text('Sync status unavailable'), findsOneWidget);
    expect(find.text('Loading sync status…'), findsNothing);
    expect(find.text('Waiting for the first completed sync'), findsNothing);

    activation.statusError = null;
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.textContaining(lastSyncLabel), findsOneWidget);
    expect(find.text('Sync status unavailable'), findsNothing);
  });

  testWidgets('status refresh keeps the last known sync time during failure', (
    tester,
  ) async {
    await installActiveBinding();
    final activation = _FakeActivation(store)
      ..lastSuccessfulSyncMs = DateTime(
        2026,
        9,
        10,
        5,
        30,
      ).millisecondsSinceEpoch;
    await pumpPage(tester, enabled: true, activation: activation);
    expect(find.textContaining(lastSyncLabel), findsOneWidget);

    final release = Completer<void>();
    activation
      ..statusRelease = release
      ..statusError = StateError('status temporarily unavailable');
    await tester.pump(const Duration(seconds: 2));
    expect(find.textContaining(lastSyncLabel), findsOneWidget);
    expect(find.text('Loading sync status…'), findsNothing);

    release.complete();
    await tester.pumpAndSettle();
    expect(find.textContaining(lastSyncLabel), findsOneWidget);
    expect(find.text('Sync status unavailable'), findsNothing);
    expect(find.text('Waiting for the first completed sync'), findsNothing);
  });

  testWidgets('logout requires confirmation and returns to connect', (
    tester,
  ) async {
    await installActiveBinding();
    final activation = _FakeActivation(store);
    await pumpPage(tester, enabled: true, activation: activation);
    await tester.ensureVisible(find.text('Log out'));
    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();
    expect(activation.logouts, 0);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(activation.logouts, 0);
    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Log out'));
    await tester.pumpAndSettle();
    expect(activation.logouts, 1);
    expect(find.text('Connect WebDAV'), findsOneWidget);
    expect(find.text('Log out'), findsNothing);
    expect((await store.load()).bindings, isEmpty);
  });

  for (final action in [
    'Forget connection',
    'Change account',
    'Connect WebDAV',
  ]) {
    testWidgets('$action recovers pending logout with confirmation', (
      tester,
    ) async {
      await installActiveBinding();
      if (action == 'Connect WebDAV') {
        await store.markError(
          (await store.load()).activeBindingId!,
          StateError('missing root'),
        );
      }
      await store.beginLogout();
      final activation = _FakeActivation(store)..failLogout = true;
      await pumpPage(tester, enabled: true, activation: activation);
      await tester.ensureVisible(find.text(action));
      await tester.tap(find.text(action));
      await tester.pumpAndSettle();
      expect(find.text('Forget WebDAV connection?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect((await store.load()).bindings, isNotEmpty);
      await tester.tap(find.text(action));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Forget connection'));
      await tester.pumpAndSettle();
      expect((await store.load()).bindings, isEmpty);
      expect(activation.logouts, 1);
    });
  }

  testWidgets('failed logout presents a retry and disables sync', (
    tester,
  ) async {
    await installActiveBinding();
    final activation = _FakeActivation(store)..failLogout = true;
    await pumpPage(tester, enabled: true, activation: activation);
    await tester.ensureVisible(find.text('Log out'));
    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Log out'));
    await tester.pumpAndSettle();
    expect(find.text('Retry logout'), findsOneWidget);
    expect(WebDavSyncBindingStore.logoutPending(await store.load()), isTrue);
    expect(
      tester
          .widget<SettingsTile>(
            find
                .ancestor(
                  of: find.text('Sync now'),
                  matching: find.byType(SettingsTile),
                )
                .first,
          )
          .enabled,
      isFalse,
    );
    activation.failLogout = false;
    await tester.ensureVisible(find.text('Retry logout'));
    await tester.tap(find.text('Retry logout'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Log out'));
    await tester.pumpAndSettle();
    expect(find.text('Connect WebDAV'), findsOneWidget);
  });

  testWidgets('M3 setup stays hidden behind its rollout gate', (tester) async {
    await pumpPage(tester, enabled: false);

    expect(find.text('Connect WebDAV'), findsNothing);
    expect(find.text('Manual backups'), findsNothing);
    expect(find.text('Save backup to WebDAV'), findsNothing);
    expect(find.text('Restore backup from WebDAV'), findsNothing);
  });

  testWidgets('failed Admin check does not resume an unpaused runtime', (
    tester,
  ) async {
    final activation = _FakeActivation(store);
    authorization.adminError = StateError('Admin required');
    await pumpPage(tester, enabled: true, activation: activation);

    await tester.tap(find.text('Connect WebDAV'));
    await tester.pumpAndSettle();

    expect(activation.pauses, 0);
    expect(activation.resumes, 0);
  });

  testWidgets('login launcher creates fixed-folder pending state', (
    tester,
  ) async {
    transport.error = const WebDavException(
      kind: WebDavErrorKind.notFound,
      message: 'missing',
    );
    await pumpPage(tester, enabled: true);

    await tester.tap(find.text('Connect WebDAV'));
    await tester.pumpAndSettle();

    expect(find.text('Ready to initialize WebDAV Sync'), findsOneWidget);
    expect(find.text('Create sync passphrase'), findsNothing);
    expect(find.text('Sync passphrase'), findsNothing);
    final binding = (await store.load()).stagedBinding!;
    expect(binding.lifecycle, WebDavSyncLifecycle.awaitingSeedCommit);
    expect(binding.location.folderPath, 'Debrify');
    expect(transport.reads, 2);
    expect(authorization.barriers, 4);
  });

  testWidgets('existing marker uses its keyfile without a passphrase dialog', (
    tester,
  ) async {
    transport.bytes = await codec.sealRoot(
      passphrase: 'circle-secret',
      circleId: 'circle-1',
      createdAt: DateTime.utc(2026, 9, 1),
      memoryKiB: 8,
      iterations: 1,
    );
    transport.keyBytes = const WebDavSyncRootKeyFile(
      syncPassphrase: 'circle-secret',
    ).encode();
    await pumpPage(tester, enabled: true);

    await tester.tap(find.text('Connect WebDAV'));
    await tester.pumpAndSettle();

    expect(find.text('WebDAV account verified'), findsOneWidget);
    expect(find.text('Sync passphrase'), findsNothing);
    final binding = (await store.load()).stagedBinding!;
    expect(binding.lifecycle, WebDavSyncLifecycle.rootVerified);
    expect(binding.circleId, 'circle-1');
    expect(authorization.barriers, 4);
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

  testWidgets('credential repair asks only for the WebDAV password', (
    tester,
  ) async {
    await installActiveBinding();
    final active = (await store.load()).activeBinding!;
    final namespace = (await store.load()).namespaceFor(active)!;
    transport
      ..bytes = Uint8List.fromList(namespace.markerBytes!)
      ..keyBytes = const WebDavSyncRootKeyFile(
        syncPassphrase: 'circle-secret',
      ).encode();
    await store.markError(active.id, StateError('credentials expired'));
    await pumpPage(tester, enabled: true);

    await tester.tap(find.text('Update password'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Sync passphrase'), findsNothing);
    expect(find.byType(TextField), findsNWidgets(2));
    await tester.enterText(find.byType(TextField).last, 'rotated-password');
    await tester.pump();
    await tester.tap(find.text('Verify'));
    await tester.pumpAndSettle();

    expect(find.text('WebDAV Sync credentials verified.'), findsOneWidget);
    expect(
      (await store.readSecrets((await store.load()).activeBinding!)).password,
      'rotated-password',
    );
  });

  testWidgets('pending logout exposes a staged binding for credential repair', (
    tester,
  ) async {
    await installActiveBinding();
    final old = (await store.load()).activeBinding!;
    final namespace = (await store.load()).namespaceFor(old)!;
    final staged = await store.stageBinding(
      location: WebDavSyncFolderLocation.fromConfig(
        const WebDavConfig(
          id: 'next',
          name: 'Second server',
          baseUrl: 'https://second.test/dav',
          username: 'alice',
          password: 'old-password',
        ),
        'Next',
      ),
      config: const WebDavConfig(
        id: 'next',
        name: 'Second server',
        baseUrl: 'https://second.test/dav',
        username: 'alice',
        password: 'old-password',
      ),
      syncPassphrase: 'circle-secret',
    );
    final root = await WebDavSyncCodec().openRoot(
      Uint8List.fromList(namespace.markerBytes!),
      'circle-secret',
    );
    await store.markRootVerified(
      bindingId: staged.id,
      root: root.document,
      markerBytes: namespace.markerBytes!,
    );
    transport
      ..bytes = Uint8List.fromList(namespace.markerBytes!)
      ..keyBytes = const WebDavSyncRootKeyFile(
        syncPassphrase: 'circle-secret',
      ).encode();
    await store.beginLogout();
    final before = await store.load();
    await pumpPage(tester, enabled: true);
    await tester.tap(find.text('Update password'));
    await tester.pumpAndSettle();
    expect(find.text('Choose account to repair'), findsOneWidget);
    await tester.tap(find.textContaining('Second server').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'new-password');
    await tester.pump();
    await tester.tap(find.text('Verify'));
    await tester.pumpAndSettle();
    final after = await store.load();
    expect(after.activeBindingId, before.activeBindingId);
    expect(after.stagedBindingId, staged.id);
    expect(
      after.bindings[staged.id]!.lifecycle,
      before.bindings[staged.id]!.lifecycle,
    );
    expect(
      (await store.readSecrets(after.bindings[staged.id]!)).password,
      'new-password',
    );
    expect(WebDavSyncBindingStore.logoutPending(after), isTrue);
  });

  testWidgets('failed repair Admin check does not resume an unpaused runtime', (
    tester,
  ) async {
    await installActiveBinding();
    final active = (await store.load()).activeBinding!;
    await store.markError(active.id, StateError('credentials expired'));
    final activation = _FakeActivation(store);
    authorization.adminError = StateError('Admin required');
    await pumpPage(tester, enabled: true, activation: activation);

    await tester.tap(find.text('Update password'));
    await tester.pumpAndSettle();

    expect(activation.pauses, 0);
    expect(activation.resumes, 0);
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
      location: WebDavSyncFolderLocation.fromConfig(_config, 'Debrify'),
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

    expect(
      find.text('Setting up sync. Keep the app open while this finishes.'),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('foreground status refresh observes first-sync promotion', (
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
      location: WebDavSyncFolderLocation.fromConfig(_config, 'Debrify'),
      config: _config,
      syncPassphrase: 'circle-secret',
    );
    waiting = await store.markRootVerified(
      bindingId: waiting.id,
      root: root.document,
      markerBytes: marker,
    );
    await store.setLifecycle(waiting.id, WebDavSyncLifecycle.awaitingAdoption);
    final activation = _FakeActivation(store)
      ..tvAvailability = WebDavSyncTvManualAvailability.firstJoinPending;
    // The finishing spinner animates indefinitely, so a settling pump would
    // never complete; use the helper's bounded pumps until promotion lands.
    await pumpPage(
      tester,
      enabled: true,
      activation: activation,
      settle: false,
    );
    expect(
      find.text('Setting up sync. Keep the app open while this finishes.'),
      findsOneWidget,
    );
    expect(
      find.text('Finish the first sync before syncing Debrify TV'),
      findsOneWidget,
    );

    await store.activateAndPromoteStaged(waiting.id);
    activation.tvAvailability = WebDavSyncTvManualAvailability.available;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(activation.statusReads, greaterThanOrEqualTo(2));
    expect(
      find.text('Setting up sync. Keep the app open while this finishes.'),
      findsNothing,
    );
    expect(find.text('Connected to Family server'), findsOneWidget);
    expect(find.text('Change account'), findsOneWidget);
  });

  testWidgets(
    'open page observes first-sync promotion without a lifecycle event',
    (tester) async {
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
        location: WebDavSyncFolderLocation.fromConfig(_config, 'Debrify'),
        config: _config,
        syncPassphrase: 'circle-secret',
      );
      waiting = await store.markRootVerified(
        bindingId: waiting.id,
        root: root.document,
        markerBytes: marker,
      );
      await store.setLifecycle(
        waiting.id,
        WebDavSyncLifecycle.awaitingAdoption,
      );
      final activation = _FakeActivation(store)
        ..tvAvailability = WebDavSyncTvManualAvailability.firstJoinPending;
      // The finishing spinner animates indefinitely, so a settling pump would
      // never complete; use the helper's bounded pumps until promotion lands.
      await pumpPage(
        tester,
        enabled: true,
        activation: activation,
        settle: false,
      );
      expect(
        find.text('Setting up sync. Keep the app open while this finishes.'),
        findsOneWidget,
      );
      expect(
        find.text('Finish the first sync before syncing Debrify TV'),
        findsOneWidget,
      );

      await store.activateAndPromoteStaged(waiting.id);
      activation.tvAvailability = WebDavSyncTvManualAvailability.available;
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      expect(activation.statusReads, greaterThanOrEqualTo(2));
      expect(
        find.text('Setting up sync. Keep the app open while this finishes.'),
        findsNothing,
      );
      expect(find.text('Connected to Family server'), findsOneWidget);
      expect(find.text('Change account'), findsOneWidget);
    },
  );

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
      location: WebDavSyncFolderLocation.fromConfig(_config, 'Debrify'),
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
    expect(
      find.text('Setting up sync. Keep the app open while this finishes.'),
      findsNothing,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('setup discloses manual-only Debrify TV sync', (tester) async {
    await pumpPage(tester, enabled: true);

    expect(
      find.text(
        'Channels and saved torrent pools transfer only when you sync them here. Run this on both devices after changing channels.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('manual Debrify TV block shows pending status and Stop works', (
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
      location: WebDavSyncFolderLocation.fromConfig(_config, 'Debrify'),
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
    final release = Completer<void>();
    final activation = _FakeActivation(store)
      ..tvChangesPending = true
      ..lastTvSyncMs = DateTime.utc(2026, 9, 3).millisecondsSinceEpoch
      ..tvStageRelease = release;
    await pumpPage(tester, enabled: true, activation: activation);

    expect(find.text('DEBRIFY TV CHANNELS'), findsOneWidget);
    expect(find.text('Sync channels now'), findsOneWidget);
    expect(find.text('Changes are waiting for a manual sync'), findsOneWidget);
    expect(find.textContaining('Channels last synced'), findsOneWidget);

    await tester.ensureVisible(find.text('Sync channels now'));
    await tester.tap(find.text('Sync channels now'));
    await tester.pump();
    expect(find.text('Syncing Debrify TV'), findsOneWidget);
    expect(find.text('Reading'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);
    await tester.tap(find.text('Stop'));
    await tester.pump();
    expect(find.text('Stopping after this stage…'), findsOneWidget);
    release.complete();
    await tester.pumpAndSettle();

    expect(activation.tvSyncs, 1);
    expect(find.text('Debrify TV sync stopped safely.'), findsOneWidget);
  });

  testWidgets('manual TV platform gates show actionable disabled reasons', (
    tester,
  ) async {
    await installActiveBinding();
    final activation = _FakeActivation(store)
      ..tvAvailability = WebDavSyncTvManualAvailability.televisionPlayback;
    await pumpPage(tester, enabled: true, activation: activation);

    expect(find.text('Stop TV playback, then try again'), findsOneWidget);
    expect(
      tester
          .widget<SettingsTile>(
            find.ancestor(
              of: find.text('Sync channels now'),
              matching: find.byType(SettingsTile),
            ),
          )
          .enabled,
      isFalse,
    );

    activation.tvAvailability = WebDavSyncTvManualAvailability.tvOsLowMemory;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Apple TV is low on memory; wait a few minutes, then try again',
      ),
      findsOneWidget,
    );
  });

  testWidgets('ambient capacity status is visible with recovery action', (
    tester,
  ) async {
    await installActiveBinding();
    final activation = _FakeActivation(store)
      ..statusHint =
          'Sync paused because saved IPTV and playback activity exceeds '
          '20,000 items. Remove older history or lists, then press Sync now.';
    await pumpPage(tester, enabled: true, activation: activation);

    expect(find.text(activation.statusHint!), findsOneWidget);
  });

  testWidgets('disposing the TV dialog cancels at the read-stage boundary', (
    tester,
  ) async {
    await installActiveBinding();
    final readRelease = Completer<void>();
    final terminal = Completer<void>();
    final activation = _FakeActivation(store)
      ..tvStageRelease = readRelease
      ..tvTerminal = terminal;
    await pumpPage(tester, enabled: true, activation: activation);

    await tester.ensureVisible(find.text('Sync channels now'));
    await tester.tap(find.text('Sync channels now'));
    await tester.pump();
    expect(find.text('Reading'), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    readRelease.complete();
    await terminal.future;
    await tester.pump();

    expect(activation.tvCancellationObserved, isTrue);
    expect(activation.tvStages, <WebDavSyncTvManualStage>[
      WebDavSyncTvManualStage.reading,
    ]);
  });

  testWidgets('two immediate TV sync presses launch one dialog and operation', (
    tester,
  ) async {
    await installActiveBinding();
    final availabilityRelease = Completer<void>();
    final readRelease = Completer<void>();
    final activation = _FakeActivation(store)..tvStageRelease = readRelease;
    await pumpPage(tester, enabled: true, activation: activation);
    activation.tvAvailabilityReads = 0;
    activation.tvAvailabilityRelease = availabilityRelease;

    await tester.ensureVisible(find.text('Sync channels now'));
    await tester.tap(find.text('Sync channels now'));
    await tester.tap(find.text('Sync channels now'));
    availabilityRelease.complete();
    await tester.pump();

    expect(activation.tvAvailabilityReads, 1);
    expect(activation.tvSyncs, 1);
    expect(find.text('Syncing Debrify TV'), findsOneWidget);
    readRelease.complete();
    await tester.pumpAndSettle();
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
      location: WebDavSyncFolderLocation.fromConfig(_config, 'Debrify'),
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
        'Try again or verify the WebDAV account.',
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

      await tester.tap(find.text('Connect WebDAV'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(activation.inspections, 1);
      expect(find.text('Use sync data from this account?'), findsOneWidget);
      expect(
        find.textContaining('Existing profiles and connections'),
        findsOneWidget,
      );
      await tester.tap(find.text('Use sync data'));
      await tester.pumpAndSettle();

      expect(activation.connections, 1);
      expect(find.text('Connected to Family server'), findsOneWidget);
      expect(find.text('Sync now'), findsOneWidget);
      final tvTile = tester.widget<SettingsTile>(
        find.ancestor(
          of: find.text('Sync channels now'),
          matching: find.byType(SettingsTile),
        ),
      );
      expect(tvTile.enabled, isTrue);
      expect(activation.statusReads, greaterThanOrEqualTo(1));
    },
  );

  testWidgets('revalidating the active account does not prompt replacement', (
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
      folderPath: 'Debrify',
      context: WebDavSyncFolderInspectionContext.setup,
    );
    var active = await service.configureExistingRoot(
      inspection: inspection as WebDavSyncFolderExisting,
    );
    active = await store.setLifecycle(active.id, WebDavSyncLifecycle.active);
    await store.promoteStaged(active.id);
    final activation = _FakeActivation(store);
    await pumpPage(tester, enabled: true, activation: activation);

    await tester.tap(find.text('Change account'));
    await tester.pumpAndSettle();

    expect(find.text('Use sync data from this account?'), findsNothing);
    expect(activation.inspections, 0);
    expect(activation.connections, 0);
    final refreshed = await store.load();
    expect(refreshed.activeBindingId, active.id);
    expect(refreshed.activeBinding?.lifecycle, WebDavSyncLifecycle.active);
    expect(find.text('Change account'), findsOneWidget);
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
        folderPath: 'Debrify',
        context: WebDavSyncFolderInspectionContext.setup,
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

      await tester.tap(find.text('Connect WebDAV'));
      await tester.pumpAndSettle();

      expect(activation.initializations, 1);
      expect(activation.inspections, 0);
      expect(activation.connections, 0);
      expect(find.text('Use sync data from this account?'), findsNothing);
      expect(find.text('Connected to Family server'), findsOneWidget);
    },
  );

  testWidgets(
    'cancelling an account replacement restores the previous active binding',
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
      const oldConfig = WebDavConfig(
        id: 'old-server',
        name: 'Old server',
        baseUrl: 'https://old.example.test/dav',
        username: 'alice',
        password: 'secret',
      );
      var oldBinding = await store.stageBinding(
        location: WebDavSyncFolderLocation.fromConfig(oldConfig, 'Debrify'),
        config: oldConfig,
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
      await pumpPage(tester, enabled: true, activation: activation);

      await tester.tap(find.text('Change account'));
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
      expect(find.text('Connected to Old server'), findsOneWidget);
    },
  );
}

final class _AllowAuthorization implements WebDavSyncSetupAuthorization {
  int adminChecks = 0;
  int barriers = 0;
  Object? adminError;

  @override
  Future<void> requireAdmin() async {
    adminChecks++;
    if (adminError case final failure?) throw failure;
  }

  @override
  Future<T> runForAdminSession<T>(
    Future<T> Function(Future<void> Function()? beforeSend) body,
  ) => body(() async => barriers++);

  @override
  Future<T> runForActiveBinding<T>(
    Future<T> Function(Future<void> Function()? beforeSend) body,
  ) => body(() async => barriers++);
}

final class _FakeTransport implements WebDavSyncProbeTransport {
  int reads = 0;
  Uint8List? _bytes;
  Uint8List? keyBytes;
  Object? error;

  Uint8List? get bytes => _bytes;

  set bytes(Uint8List? value) {
    _bytes = value;
    if (value != null) {
      keyBytes = const WebDavSyncRootKeyFile(
        syncPassphrase: 'circle-secret',
      ).encode();
    }
  }

  @override
  Future<WebDavBytesResult> readRootMarker({
    required String path,
    Future<void> Function()? beforeSend,
  }) async {
    reads++;
    await beforeSend?.call();
    if (error case final failure?) throw failure;
    return WebDavBytesResult(
      bytes: _bytes ?? Uint8List(0),
      metadata: WebDavResponseMetadata(
        statusCode: 200,
        uri: Uri.parse('https://example.test/dav/$path'),
        headers: const <String, String>{},
      ),
    );
  }

  @override
  Future<WebDavBytesResult> readRootKey({
    required String path,
    Future<void> Function()? beforeSend,
  }) async {
    reads++;
    await beforeSend?.call();
    if (error case final failure?) throw failure;
    final body = keyBytes;
    if (body == null) {
      throw const WebDavException(
        kind: WebDavErrorKind.notFound,
        message: 'missing',
      );
    }
    return WebDavBytesResult(
      bytes: body,
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
        WebDavSyncManagementController,
        WebDavSyncLogoutController,
        WebDavSyncTvManualController,
        WebDavSyncReconfigurationController {
  _FakeActivation(this.store, {this.onInitialize});

  final WebDavSyncBindingStore store;
  final Future<WebDavSyncInitializationOutcome> Function(String bindingId)?
  onInitialize;
  int logouts = 0;
  bool failLogout = false;

  @override
  Future<void> logout({bool localOnly = false}) async {
    logouts++;
    await store.beginLogout();
    if (failLogout && !localOnly) throw StateError('offline');
    await store.finishLogout();
  }

  int inspections = 0;
  int connections = 0;
  int initializations = 0;
  int pauses = 0;
  int resumes = 0;
  int statusReads = 0;
  Completer<void>? statusRelease;
  Object? statusError;
  int? lastSuccessfulSyncMs;
  Object? syncError;
  String? statusHint;
  bool tvChangesPending = false;
  int? lastTvSyncMs;
  int tvSyncs = 0;
  int tvAvailabilityReads = 0;
  bool tvCancellationObserved = false;
  final List<WebDavSyncTvManualStage> tvStages = <WebDavSyncTvManualStage>[];
  WebDavSyncTvManualAvailability tvAvailability =
      WebDavSyncTvManualAvailability.available;
  Completer<void>? tvAvailabilityRelease;
  Completer<void>? tvStageRelease;
  Completer<void>? tvTerminal;

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

  @override
  Future<WebDavSyncRuntimeStatus> status() async {
    statusReads++;
    await statusRelease?.future;
    if (statusError case final error?) throw error;
    return WebDavSyncRuntimeStatus(
      lastSuccessfulSyncMs: lastSuccessfulSyncMs,
      peerCount: 0,
      adminPruneBlocked: false,
      deviceClockWarning: false,
      clockPauseReason: null,
      statusHint: statusHint,
      tvChangesPending: tvChangesPending,
      lastTvSyncMs: lastTvSyncMs,
    );
  }

  @override
  Future<WebDavSyncTvManualAvailability> tvManualAvailability() async {
    tvAvailabilityReads++;
    await tvAvailabilityRelease?.future;
    return tvAvailability;
  }

  @override
  Future<WebDavSyncTvManualReport> syncDebrifyTv({
    required WebDavSyncTvCancellationToken cancellationToken,
    WebDavSyncTvStageCallback? onStage,
  }) async {
    tvSyncs++;
    try {
      tvStages.add(WebDavSyncTvManualStage.reading);
      onStage?.call(WebDavSyncTvManualStage.reading);
      await tvStageRelease?.future;
      if (cancellationToken.isCancelled) {
        tvCancellationObserved = true;
        return const WebDavSyncTvManualReport(
          disposition: WebDavSyncTvManualDisposition.cancelled,
        );
      }
      tvStages.add(WebDavSyncTvManualStage.merging);
      onStage?.call(WebDavSyncTvManualStage.merging);
      tvStages.add(WebDavSyncTvManualStage.applying);
      onStage?.call(WebDavSyncTvManualStage.applying);
      tvStages.add(WebDavSyncTvManualStage.publishing);
      onStage?.call(WebDavSyncTvManualStage.publishing);
      return const WebDavSyncTvManualReport(
        disposition: WebDavSyncTvManualDisposition.completed,
      );
    } finally {
      final terminal = tvTerminal;
      if (terminal != null && !terminal.isCompleted) terminal.complete();
    }
  }

  @override
  Future<List<WebDavSyncDeviceSummary>> listDevices() async => const [];

  @override
  Future<void> forgetDevice(String deviceId) async {}
}
