import 'dart:typed_data';

import 'package:debrify/models/webdav_item.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
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
      transportFactory: ({required endpoint, required credentials}) {
        transport.endpoint = endpoint;
        return transport;
      },
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

  Future<({WebDavSyncBinding binding, Uint8List marker})>
  installActiveBinding() async {
    final marker = await WebDavSyncCodec().sealRoot(
      passphrase: 'circle-secret',
      circleId: 'active-circle',
      createdAt: DateTime.utc(2026, 9, 3),
      memoryKiB: 8,
      iterations: 1,
    );
    transport
      ..marker = marker
      ..rootKey = const WebDavSyncRootKeyFile(
        syncPassphrase: 'circle-secret',
      ).encode();
    final inspection = await setup.inspectFolder(
      config: credentials.toConfig(),
      folderPath: WebDavSyncConnectController.folderPath,
      context: WebDavSyncFolderInspectionContext.setup,
    );
    var binding = await setup.configureExistingRoot(
      inspection: inspection as WebDavSyncFolderExisting,
    );
    binding = await store.setLifecycle(binding.id, WebDavSyncLifecycle.active);
    await store.promoteStaged(binding.id);
    return (binding: binding, marker: marker);
  }

  test('cancelled login has no durable side effects', () async {
    final outcome = await controller().connect(
      credentials: null,
      confirmExistingReplacement: () async => true,
    );

    expect(outcome, isA<WebDavSyncConnectCancelled>());
    expect((await store.load()).bindings, isEmpty);
    expect(authorization.calls, 0);
  });

  test(
    'onboarding cancellation preserves an earlier staged candidate',
    () async {
      final earlier = await store.stageBinding(
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
      expect((await store.load()).stagedBinding?.id, earlier.id);
      expect((await store.load()).bindings, contains(earlier.id));
    },
  );

  test('pre-staging login failure preserves an earlier candidate', () async {
    final earlier = await store.stageBinding(
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
    authorization.error = StateError('authorization changed');

    final outcome = await controller().connect(
      credentials: credentials,
      completeOnboarding: true,
      confirmExistingReplacement: () async => true,
    );

    expect(outcome, isA<WebDavSyncConnectPreHandoffFailure>());
    expect((await store.load()).stagedBinding?.id, earlier.id);
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

  test(
    'change-account setup inspection never mutates a same-id active binding',
    () async {
      final installed = await installActiveBinding();

      transport
        ..marker = null
        ..rootKey = null;
      expect(
        await controller().inspect(credentials),
        isA<WebDavSyncFolderMissing>(),
      );
      var snapshot = await store.load();
      var active = snapshot.bindings[installed.binding.id]!;
      expect(active.lifecycle, WebDavSyncLifecycle.active);
      expect(active.errorMessage, isNull);
      expect(
        snapshot.namespaceFor(active)!.markerBytes,
        orderedEquals(installed.marker),
      );

      transport
        ..marker = await WebDavSyncCodec().sealRoot(
          passphrase: 'other-secret',
          circleId: 'other-circle',
          createdAt: DateTime.utc(2026, 9, 4),
          memoryKiB: 8,
          iterations: 1,
        )
        ..rootKey = const WebDavSyncRootKeyFile(
          syncPassphrase: 'other-secret',
        ).encode();
      expect(
        await controller().inspect(credentials),
        isA<WebDavSyncFolderExisting>(),
      );
      expect(
        await controller().connect(
          credentials: null,
          confirmExistingReplacement: () async => true,
        ),
        isA<WebDavSyncConnectCancelled>(),
      );
      snapshot = await store.load();
      active = snapshot.bindings[installed.binding.id]!;
      expect(active.lifecycle, WebDavSyncLifecycle.active);
      expect(active.errorMessage, isNull);
      expect(
        snapshot.namespaceFor(active)!.markerBytes,
        orderedEquals(installed.marker),
      );
    },
  );

  test('state reconnect is pinned to the stored endpoint and folder', () async {
    final installed = await installActiveBinding();
    await store.setLifecycle(
      installed.binding.id,
      WebDavSyncLifecycle.error,
      errorMessage: webDavSyncMissingStateMessage,
    );
    final supplied = WebDavSyncLoginCredentials(
      endpoint: Uri.parse('https://different.test/elsewhere/'),
      username: 'alice',
      password: 'rotated-secret',
      serverName: 'Different',
    );

    final inspection = await controller().inspectReconnect(supplied);

    expect(inspection.location.endpoint, installed.binding.location.endpoint);
    expect(
      inspection.location.folderPath,
      installed.binding.location.folderPath,
    );
    expect(transport.endpoint, installed.binding.location.endpoint);
    expect(transport.paths.sublist(transport.paths.length - 2), <String>[
      'Debrify/debrify-sync/circle.json.enc',
      'Debrify/debrify-sync/circle.key',
    ]);
  });

  for (final scenario in <({String name, Object error})>[
    (name: 'clock validation', error: StateError('server clock unavailable')),
    (name: 'authority claim', error: const WebDavSyncAuthorityClaimException()),
    (
      name: 'non-linearizable store',
      error: const WebDavSyncStoreNotLinearizableException(),
    ),
    (
      name: 'temporarily inconclusive conditional-create capability',
      error: const WebDavSyncSetupInconclusiveException(),
    ),
    (
      name: 'seed upload',
      error: const WebDavException(
        kind: WebDavErrorKind.network,
        message: 'upload failed',
      ),
    ),
  ]) {
    test(
      '${scenario.name} failure before profile authority is pre-handoff',
      () async {
        final outcome =
            await controller(
              activation: _FailingActivation(newRootFailure: scenario.error),
            ).connect(
              credentials: credentials,
              confirmExistingReplacement: () async => true,
            );

        expect(outcome, isA<WebDavSyncConnectPreHandoffFailure>());
        if (scenario.error is WebDavSyncStoreNotLinearizableException) {
          expect(
            (outcome as WebDavSyncConnectPreHandoffFailure).error,
            isA<WebDavSyncStoreNotLinearizableException>(),
          );
        }
        if (scenario.error is WebDavSyncSetupInconclusiveException) {
          expect(
            (outcome as WebDavSyncConnectPreHandoffFailure).error,
            isA<WebDavSyncSetupInconclusiveException>(),
          );
        }
        expect(
          (await store.load()).stagedBinding?.lifecycle,
          WebDavSyncLifecycle.awaitingSeedCommit,
        );
      },
    );
  }

  test('discovery failure before profile authority is pre-handoff', () async {
    transport
      ..marker = await WebDavSyncCodec().sealRoot(
        passphrase: 'circle-secret',
        circleId: 'existing-circle',
        createdAt: DateTime.utc(2026, 9, 4),
        memoryKiB: 8,
        iterations: 1,
      )
      ..rootKey = const WebDavSyncRootKeyFile(
        syncPassphrase: 'circle-secret',
      ).encode();
    final outcome =
        await controller(
          activation: _FailingActivation(
            existingInspectionFailure: StateError('discovery failed'),
          ),
        ).connect(
          credentials: credentials,
          confirmExistingReplacement: () async => true,
        );

    expect(outcome, isA<WebDavSyncConnectPreHandoffFailure>());
  });

  test('typed authority-committed errors are post-handoff failures', () async {
    transport
      ..marker = await WebDavSyncCodec().sealRoot(
        passphrase: 'circle-secret',
        circleId: 'existing-circle',
        createdAt: DateTime.utc(2026, 9, 4),
        memoryKiB: 8,
        iterations: 1,
      )
      ..rootKey = const WebDavSyncRootKeyFile(
        syncPassphrase: 'circle-secret',
      ).encode();
    final outcome =
        await controller(
          activation: _FailingActivation(postHandoff: true),
        ).connect(
          credentials: credentials,
          confirmExistingReplacement: () async => true,
        );

    final failure = outcome as WebDavSyncConnectPostHandoffFailure;
    expect(failure.error, isA<StateError>());
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
  Uri? endpoint;
  Uint8List? marker;
  Uint8List? rootKey;

  @override
  Future<WebDavBytesResult> readRootMarker({
    required String path,
    Future<void> Function()? beforeSend,
  }) async {
    paths.add(path);
    if (marker case final bytes?) {
      return WebDavBytesResult(bytes: bytes, metadata: _metadata);
    }
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
    if (rootKey case final bytes?) {
      return WebDavBytesResult(bytes: bytes, metadata: _metadata);
    }
    throw const WebDavException(
      kind: WebDavErrorKind.notFound,
      message: 'missing',
    );
  }

  @override
  void close() {}

  static final WebDavResponseMetadata _metadata = WebDavResponseMetadata(
    statusCode: 200,
    uri: Uri.parse('https://example.test/dav'),
    headers: const <String, String>{},
  );
}

final class _FailingActivation implements WebDavSyncActivationController {
  _FailingActivation({
    this.newRootFailure,
    this.existingInspectionFailure,
    this.postHandoff = false,
  });

  final Object? newRootFailure;
  final Object? existingInspectionFailure;
  final bool postHandoff;

  @override
  Future<WebDavSyncBinding> connectExisting(
    String bindingId, {
    required bool replacementConfirmed,
  }) {
    if (postHandoff) {
      throw WebDavSyncPostHandoffException(StateError('activation failed'));
    }
    throw UnimplementedError();
  }

  @override
  Future<WebDavSyncInitializationOutcome> initializeNew(String bindingId) {
    throw newRootFailure ?? StateError('activation failed');
  }

  @override
  Future<void> inspectExisting(String bindingId) async {
    if (existingInspectionFailure case final error?) throw error;
  }

  @override
  Future<WebDavSyncCycleReport> syncNow() => throw UnimplementedError();
}
