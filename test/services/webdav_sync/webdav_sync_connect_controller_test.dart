import 'dart:typed_data';

import 'package:debrify/models/webdav_item.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/webdav_protocol_client.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_activation.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_binding_store.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_connect_controller.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_engine.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_models.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_runtime.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_setup_authorization.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_setup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late WebDavSyncBindingStore store;
  late _ProbeTransport transport;
  late _Authorization authorization;
  late WebDavSyncSetupService setup;

  final credentials = WebDavSyncLoginCredentials(
    endpoint: Uri(scheme: 'https', host: 'example.test', path: '/dav/'),
    username: 'alice',
    password: 'server-secret',
    serverName: 'Custom',
  );

  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    DeviceKeyProvider.debugInstallCipher(
      MemoryDeviceSecretCipher(List<int>.filled(32, 5)),
    );
    store = WebDavSyncBindingStore(
      randomBytes: (length) => Uint8List.fromList(
        List<int>.generate(length, (index) => index & 0xff),
      ),
    );
    transport = _ProbeTransport();
    authorization = _Authorization();
    setup = WebDavSyncSetupService(
      store: store,
      transportFactory: ({required endpoint, required credentials}) =>
          transport,
    );
  });

  tearDown(DeviceKeyProvider.debugReset);

  WebDavSyncConnectController controller({
    WebDavSyncActivationController? activation,
  }) => WebDavSyncConnectController(
    setupService: setup,
    authorization: authorization,
    activation: activation,
  );

  test('cancelled login has no durable side effects', () async {
    final outcome = await controller().connect(
      credentials: null,
      confirmExistingReplacement: () async => true,
    );

    expect(outcome, isA<WebDavSyncConnectCancelled>());
    expect((await store.load()).bindings, isEmpty);
    expect(authorization.calls, 0);
  });

  test('onboarding cancellation discards only the staged candidate', () async {
    await store.stageBinding(
      location: WebDavSyncFolderLocation(
        endpoint: 'https://other.test/dav',
        folderPath: 'Debrify',
        serverName: 'Other',
      ),
      config: const WebDavConfig(
        id: 'other',
        name: 'Other',
        baseUrl: 'https://other.test/dav',
        username: 'alice',
        password: 'secret',
      ),
      syncPassphrase: 'circle-secret',
      completeOnboarding: true,
    );

    final outcome = await controller().connect(
      credentials: null,
      completeOnboarding: true,
      confirmExistingReplacement: () async => true,
    );

    expect(outcome, isA<WebDavSyncConnectCancelled>());
    expect((await store.load()).stagedBinding, isNull);
    expect((await store.load()).bindings, isEmpty);
  });

  test(
    'new login uses the fixed folder and reports adoption finishing',
    () async {
      final outcome = await controller().connect(
        credentials: credentials,
        completeOnboarding: true,
        confirmExistingReplacement: () async => true,
      );

      final finishing = outcome as WebDavSyncConnectAdoptedFinishing;
      expect(finishing.binding.location.folderPath, 'Debrify');
      expect(transport.paths, <String>[
        'Debrify/debrify-sync/circle.json.enc',
        'Debrify/debrify-sync/circle.key',
      ]);
      expect(
        (await store.readSecrets(finishing.binding)).syncPassphrase,
        hasLength(43),
      );
      expect((await store.load()).stagedBinding?.completeOnboarding, isTrue);
    },
  );

  test('pre-handoff failure removes the onboarding candidate', () async {
    var saves = 0;
    authorization.beforeCommit = () async {
      saves++;
      if (saves == 2) throw StateError('commit fence changed');
    };

    final outcome = await controller().connect(
      credentials: credentials,
      completeOnboarding: true,
      confirmExistingReplacement: () async => true,
    );

    expect(outcome, isA<WebDavSyncConnectPreHandoffFailure>());
    expect((await store.load()).stagedBinding, isNull);
    expect((await store.load()).bindings, isEmpty);
  });

  test('inspection errors are pre-handoff failures', () async {
    authorization.error = StateError('authorization changed');

    final outcome = await controller().connect(
      credentials: credentials,
      confirmExistingReplacement: () async => true,
    );

    expect(outcome, isA<WebDavSyncConnectPreHandoffFailure>());
    expect((await store.load()).bindings, isEmpty);
  });

  test('activation errors are post-handoff failures', () async {
    final outcome = await controller(activation: _FailingActivation()).connect(
      credentials: credentials,
      confirmExistingReplacement: () async => true,
    );

    expect(outcome, isA<WebDavSyncConnectPostHandoffFailure>());
    expect(
      (await store.load()).stagedBinding?.lifecycle,
      WebDavSyncLifecycle.awaitingSeedCommit,
    );
  });
}

final class _Authorization implements WebDavSyncSetupAuthorization {
  Object? error;
  int calls = 0;
  Future<void> Function()? beforeCommit;

  @override
  Future<void> requireAdmin() async {}

  @override
  Future<T> runForAdminSession<T>(
    Future<T> Function(Future<void> Function()? beforeSend) body,
  ) async {
    calls++;
    if (error case final failure?) throw failure;
    return body(beforeCommit);
  }

  @override
  Future<T> runForActiveBinding<T>(
    Future<T> Function(Future<void> Function()? beforeSend) body,
  ) => runForAdminSession(body);
}

final class _ProbeTransport implements WebDavSyncProbeTransport {
  final List<String> paths = <String>[];

  @override
  Future<WebDavBytesResult> readRootMarker({
    required String path,
    Future<void> Function()? beforeSend,
  }) async {
    paths.add(path);
    throw const WebDavException(
      kind: WebDavErrorKind.notFound,
      message: 'missing',
    );
  }

  @override
  Future<WebDavBytesResult> readRootKey({
    required String path,
    Future<void> Function()? beforeSend,
  }) async {
    paths.add(path);
    throw const WebDavException(
      kind: WebDavErrorKind.notFound,
      message: 'missing',
    );
  }

  @override
  void close() {}
}

final class _FailingActivation implements WebDavSyncActivationController {
  @override
  Future<WebDavSyncBinding> connectExisting(
    String bindingId, {
    required bool replacementConfirmed,
  }) => throw UnimplementedError();

  @override
  Future<WebDavSyncInitializationOutcome> initializeNew(String bindingId) =>
      throw StateError('activation failed');

  @override
  Future<void> inspectExisting(String bindingId) => throw UnimplementedError();

  @override
  Future<WebDavSyncCycleReport> syncNow() => throw UnimplementedError();
}
