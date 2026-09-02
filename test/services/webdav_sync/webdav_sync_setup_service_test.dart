import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:debrify/models/webdav_item.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/webdav_protocol_client.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_binding_store.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_codec.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_models.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_setup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _config = WebDavConfig(
  id: 'server-1',
  name: 'Server',
  baseUrl: 'https://example.test/dav',
  username: 'alice',
  password: 'secret',
);

void main() {
  late WebDavSyncBindingStore store;
  late WebDavSyncCodec codec;
  late _FakeProbeTransport transport;
  late WebDavSyncSetupService service;

  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    DeviceKeyProvider.debugInstallCipher(
      MemoryDeviceSecretCipher(List<int>.filled(32, 7)),
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
    transport = _FakeProbeTransport();
    service = WebDavSyncSetupService(
      store: store,
      codec: codec,
      transportFactory: ({required endpoint, required credentials}) {
        transport.endpoint = endpoint;
        transport.credentials = credentials;
        return transport;
      },
    );
  });

  tearDown(DeviceKeyProvider.debugReset);

  test(
    'unbound 404 is read-only and creates only local pending state',
    () async {
      transport.error = const WebDavException(
        kind: WebDavErrorKind.notFound,
        message: 'missing',
      );
      var barrierCalls = 0;
      final inspection = await service.inspectFolder(
        config: _config,
        folderPath: '/Family/',
        beforeSend: () async => barrierCalls++,
      );

      expect(inspection, isA<WebDavSyncFolderMissing>());
      expect(transport.paths, <String>['Family/debrify-sync/circle.json.enc']);
      expect(transport.endpoint, Uri.parse('https://example.test/dav/'));
      expect(transport.credentials!.username, 'alice');
      expect(barrierCalls, 1);
      expect((await store.load()).bindings, isEmpty);

      final binding = await service.configureNewRoot(
        inspection: inspection as WebDavSyncFolderMissing,
        syncPassphrase: 'circle-secret',
      );
      expect(binding.lifecycle, WebDavSyncLifecycle.awaitingSeedCommit);
      expect(transport.paths, hasLength(1));
    },
  );

  test(
    'real protocol probe sends GET only and never mutates the server',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final methods = <String>[];
      final paths = <String>[];
      server.listen((request) async {
        methods.add(request.method);
        paths.add(request.uri.path);
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });
      try {
        final live = WebDavSyncSetupService(store: store, codec: codec);
        final inspection = await live.inspectFolder(
          config: WebDavConfig(
            id: 'local',
            name: 'Local test',
            baseUrl: 'http://${server.address.address}:${server.port}/dav',
            username: 'alice',
            password: 'secret',
          ),
          folderPath: 'Family',
        );

        expect(inspection, isA<WebDavSyncFolderMissing>());
        expect(methods, <String>['GET']);
        expect(paths, <String>['/dav/Family/debrify-sync/circle.json.enc']);
        expect((await store.load()).bindings, isEmpty);
      } finally {
        await server.close(force: true);
      }
    },
  );

  test(
    'authorization is revalidated immediately before local commit',
    () async {
      transport.error = const WebDavException(
        kind: WebDavErrorKind.notFound,
        message: 'missing',
      );
      final inspection = await service.inspectFolder(
        config: _config,
        folderPath: 'Family',
      );

      await expectLater(
        service.configureNewRoot(
          inspection: inspection as WebDavSyncFolderMissing,
          syncPassphrase: 'circle-secret',
          beforeCommit: () async => throw StateError('session changed'),
        ),
        throwsStateError,
      );
      expect((await store.load()).bindings, isEmpty);
    },
  );

  test('existing marker authenticates and pins exact bytes', () async {
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
      folderPath: 'Family',
    );
    final binding = await service.configureExistingRoot(
      inspection: inspection as WebDavSyncFolderExisting,
      syncPassphrase: 'circle-secret',
    );
    final snapshot = await store.load();

    expect(binding.lifecycle, WebDavSyncLifecycle.rootVerified);
    expect(binding.circleId, 'circle-1');
    expect(snapshot.namespaceFor(binding)!.markerBytes, orderedEquals(marker));
  });

  test('same-folder credential repair preserves Active state', () async {
    final marker = await codec.sealRoot(
      passphrase: 'circle-secret',
      circleId: 'circle-1',
      createdAt: DateTime.utc(2026, 9, 1),
      memoryKiB: 8,
      iterations: 1,
    );
    transport.bytes = marker;
    final firstInspection = await service.inspectFolder(
      config: _config,
      folderPath: 'Family',
    );
    final verified = await service.configureExistingRoot(
      inspection: firstInspection as WebDavSyncFolderExisting,
      syncPassphrase: 'circle-secret',
    );
    await store.setLifecycle(verified.id, WebDavSyncLifecycle.active);
    await store.promoteStaged(verified.id);
    await store.markError(verified.id, StateError('credentials expired'));

    const rotated = WebDavConfig(
      id: 'server-1',
      name: 'Server',
      baseUrl: 'https://example.test/dav',
      username: 'alice',
      password: 'rotated-secret',
    );
    final repairInspection = await service.inspectFolder(
      config: rotated,
      folderPath: 'Family',
    );
    final repaired = await service.configureExistingRoot(
      inspection: repairInspection as WebDavSyncFolderExisting,
      syncPassphrase: 'circle-secret',
    );

    expect(repaired.lifecycle, WebDavSyncLifecycle.active);
    expect((await store.load()).stagedBindingId, isNull);
    expect((await store.readSecrets(repaired)).password, 'rotated-secret');
  });

  test(
    'missing local state explicitly stages the pinned Active root',
    () async {
      final marker = await codec.sealRoot(
        passphrase: 'circle-secret',
        circleId: 'circle-1',
        createdAt: DateTime.utc(2026, 9, 1),
        memoryKiB: 8,
        iterations: 1,
      );
      transport.bytes = marker;
      final firstInspection = await service.inspectFolder(
        config: _config,
        folderPath: 'Family',
      );
      final verified = await service.configureExistingRoot(
        inspection: firstInspection as WebDavSyncFolderExisting,
        syncPassphrase: 'circle-secret',
      );
      await store.setLifecycle(verified.id, WebDavSyncLifecycle.active);
      await store.promoteStaged(verified.id);

      final reconnectInspection = await service.inspectFolder(
        config: _config,
        folderPath: 'Family',
      );
      final reconnecting = await service.configureExistingRoot(
        inspection: reconnectInspection as WebDavSyncFolderExisting,
        syncPassphrase: 'circle-secret',
        reconnectActive: true,
      );
      final snapshot = await store.load();

      expect(reconnecting.lifecycle, WebDavSyncLifecycle.rootVerified);
      expect(snapshot.activeBindingId, reconnecting.id);
      expect(snapshot.stagedBindingId, reconnecting.id);
    },
  );

  test('committed root-last candidate resumes its seed transaction', () async {
    transport.error = const WebDavException(
      kind: WebDavErrorKind.notFound,
      message: 'missing',
    );
    final missing = await service.inspectFolder(
      config: _config,
      folderPath: 'Family',
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
    final existing = await service.inspectFolder(
      config: _config,
      folderPath: 'Family',
    );
    final resumed = await service.configureExistingRoot(
      inspection: existing as WebDavSyncFolderExisting,
      syncPassphrase: 'circle-secret',
    );
    final snapshot = await store.load();

    expect(resumed.id, candidate.id);
    expect(resumed.lifecycle, WebDavSyncLifecycle.awaitingSeedCommit);
    expect(resumed.circleId, isNull);
    expect(snapshot.stagedBindingId, candidate.id);
    expect(snapshot.namespaceFor(resumed)!.markerBytes, isNull);
    expect(
      snapshot.namespaceFor(resumed)!.values,
      contains(WebDavSyncBindingStore.seedCandidateMarkerValueKey),
    );
  });

  test('only a real 404 means missing', () async {
    transport.error = const WebDavException(
      kind: WebDavErrorKind.authentication,
      message: 'denied',
    );

    await expectLater(
      service.inspectFolder(config: _config, folderPath: 'Family'),
      throwsA(
        isA<WebDavException>().having(
          (error) => error.kind,
          'kind',
          WebDavErrorKind.authentication,
        ),
      ),
    );
    expect((await store.load()).bindings, isEmpty);
  });

  test('pinned marker deletion and replacement are hard errors', () async {
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
      folderPath: 'Family',
    );
    final binding = await service.configureExistingRoot(
      inspection: inspection as WebDavSyncFolderExisting,
      syncPassphrase: 'circle-secret',
    );

    transport
      ..bytes = null
      ..error = const WebDavException(
        kind: WebDavErrorKind.notFound,
        message: 'missing',
      );
    await expectLater(
      service.inspectFolder(config: _config, folderPath: 'Family'),
      throwsA(isA<WebDavSyncRootMissingException>()),
    );
    expect(
      (await store.load()).bindings[binding.id]!.lifecycle,
      WebDavSyncLifecycle.error,
    );

    transport
      ..error = null
      ..bytes = Uint8List.fromList(<int>[...marker]..[0] ^= 1);
    await expectLater(
      service.inspectFolder(config: _config, folderPath: 'Family'),
      throwsA(isA<WebDavSyncRootChangedException>()),
    );
  });
}

final class _FakeProbeTransport implements WebDavSyncProbeTransport {
  Uri? endpoint;
  WebDavCredentials? credentials;
  Uint8List? bytes;
  Object? error;
  final List<String> paths = <String>[];

  @override
  Future<WebDavBytesResult> readRootMarker({
    required String path,
    Future<void> Function()? beforeSend,
  }) async {
    paths.add(path);
    await beforeSend?.call();
    final failure = error;
    if (failure != null) throw failure;
    final body = bytes ?? Uint8List(0);
    return WebDavBytesResult(
      bytes: body,
      metadata: WebDavResponseMetadata(
        statusCode: 200,
        uri: endpoint!.resolve(path),
        headers: const <String, String>{},
      ),
    );
  }

  @override
  void close() {}
}
