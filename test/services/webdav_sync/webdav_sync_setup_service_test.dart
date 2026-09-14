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
  late List<String> diagnostics;

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
    diagnostics = <String>[];
    service = WebDavSyncSetupService(
      store: store,
      codec: codec,
      diagnostic: (message, _) => diagnostics.add(message),
      transportFactory: ({required endpoint, required credentials}) {
        transport.endpoint = endpoint;
        transport.credentials = credentials;
        return transport;
      },
    );
  });

  tearDown(DeviceKeyProvider.debugReset);

  Future<({WebDavSyncBinding binding, Uint8List marker})>
  installActiveBinding() async {
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
      context: WebDavSyncFolderInspectionContext.setup,
    );
    var binding = await service.configureExistingRoot(
      inspection: inspection as WebDavSyncFolderExisting,
    );
    binding = await store.setLifecycle(binding.id, WebDavSyncLifecycle.active);
    await store.promoteStaged(binding.id);
    return (binding: binding, marker: marker);
  }

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
        context: WebDavSyncFolderInspectionContext.setup,
        beforeSend: () async => barrierCalls++,
      );

      expect(inspection, isA<WebDavSyncFolderMissing>());
      expect(transport.paths, <String>[
        'Family/debrify-sync/circle.json.enc',
        'Family/debrify-sync/circle.key',
      ]);
      expect(transport.endpoint, Uri.parse('https://example.test/dav/'));
      expect(transport.credentials!.username, 'alice');
      expect(barrierCalls, 2);
      expect((await store.load()).bindings, isEmpty);

      final binding = await service.configureNewRoot(
        inspection: inspection as WebDavSyncFolderMissing,
        syncPassphrase: 'circle-secret',
      );
      expect(binding.lifecycle, WebDavSyncLifecycle.awaitingSeedCommit);
      expect(transport.paths, hasLength(2));
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
          context: WebDavSyncFolderInspectionContext.setup,
        );

        expect(inspection, isA<WebDavSyncFolderMissing>());
        expect(methods, <String>['GET', 'GET', 'GET']);
        expect(paths, <String>[
          '/dav/Family/debrify-sync/circle.authority',
          '/dav/Family/debrify-sync/circle.json.enc',
          '/dav/Family/debrify-sync/circle.key',
        ]);
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
        context: WebDavSyncFolderInspectionContext.setup,
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

  test('marker and keyfile state matrix is fail-closed', () async {
    final marker = await codec.sealRoot(
      passphrase: 'circle-secret',
      circleId: 'circle-1',
      createdAt: DateTime.utc(2026, 9, 1),
      memoryKiB: 8,
      iterations: 1,
    );

    transport
      ..bytes = marker
      ..keyBytes = null;
    await expectLater(
      service.inspectFolder(
        config: _config,
        folderPath: 'Family',
        context: WebDavSyncFolderInspectionContext.setup,
      ),
      throwsA(isA<WebDavSyncLegacyRootException>()),
    );

    transport
      ..error = const WebDavException(
        kind: WebDavErrorKind.notFound,
        message: 'missing',
      )
      ..keyBytes = const WebDavSyncRootKeyFile(
        syncPassphrase: 'orphan-secret',
      ).encode();
    final orphan = await service.inspectFolder(
      config: _config,
      folderPath: 'Other',
      context: WebDavSyncFolderInspectionContext.setup,
    );
    expect(orphan, isA<WebDavSyncFolderMissing>());

    transport
      ..error = null
      ..bytes = marker
      ..keyBytes = Uint8List.fromList(utf8.encode('{"version":1}'));
    await expectLater(
      service.inspectFolder(
        config: _config,
        folderPath: 'Damaged',
        context: WebDavSyncFolderInspectionContext.setup,
      ),
      throwsA(isA<WebDavSyncRootKeyFileException>()),
    );
    expect((await store.load()).bindings, isEmpty);
  });

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
      context: WebDavSyncFolderInspectionContext.setup,
    );
    final binding = await service.configureExistingRoot(
      inspection: inspection as WebDavSyncFolderExisting,
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
      context: WebDavSyncFolderInspectionContext.setup,
    );
    final verified = await service.configureExistingRoot(
      inspection: firstInspection as WebDavSyncFolderExisting,
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
      context: WebDavSyncFolderInspectionContext.repair,
      repairBindingId: verified.id,
    );
    final repaired = await service.configureExistingRoot(
      inspection: repairInspection as WebDavSyncFolderExisting,
    );

    expect(repaired.lifecycle, WebDavSyncLifecycle.active);
    expect((await store.load()).stagedBindingId, isNull);
    expect((await store.readSecrets(repaired)).password, 'rotated-secret');
  });

  test(
    'active same-circle marker replacement leaves pin and secrets untouched',
    () async {
      final installed = await installActiveBinding();
      final replacementMarker = await codec.sealRoot(
        passphrase: 'circle-secret',
        circleId: 'circle-1',
        createdAt: DateTime.utc(2026, 9, 2),
        memoryKiB: 8,
        iterations: 1,
      );
      const rotated = WebDavConfig(
        id: 'server-1',
        name: 'Server',
        baseUrl: 'https://example.test/dav',
        username: 'alice',
        password: 'replacement-password',
      );
      transport.bytes = replacementMarker;
      final inspection = await service.inspectFolder(
        config: rotated,
        folderPath: 'Family',
        context: WebDavSyncFolderInspectionContext.setup,
      );

      await expectLater(
        service.configureExistingRoot(
          inspection: inspection as WebDavSyncFolderExisting,
        ),
        throwsA(isA<WebDavSyncRootChangedException>()),
      );

      final snapshot = await store.load();
      final unchanged = snapshot.bindings[installed.binding.id]!;
      expect(unchanged.lifecycle, WebDavSyncLifecycle.active);
      expect(
        snapshot.namespaceFor(unchanged)!.markerBytes,
        orderedEquals(installed.marker),
      );
      final secrets = await store.readSecrets(unchanged);
      expect(secrets.password, 'secret');
      expect(secrets.syncPassphrase, 'circle-secret');
    },
  );

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
        context: WebDavSyncFolderInspectionContext.setup,
      );
      final verified = await service.configureExistingRoot(
        inspection: firstInspection as WebDavSyncFolderExisting,
      );
      await store.setLifecycle(verified.id, WebDavSyncLifecycle.active);
      await store.promoteStaged(verified.id);

      final reconnectInspection = await service.inspectFolder(
        config: _config,
        folderPath: 'Family',
        context: WebDavSyncFolderInspectionContext.repair,
        repairBindingId: verified.id,
      );
      final reconnecting = await service.configureExistingRoot(
        inspection: reconnectInspection as WebDavSyncFolderExisting,
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
      context: WebDavSyncFolderInspectionContext.setup,
    );
    final resumed = await service.configureExistingRoot(
      inspection: existing as WebDavSyncFolderExisting,
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
      service.inspectFolder(
        config: _config,
        folderPath: 'Family',
        context: WebDavSyncFolderInspectionContext.setup,
      ),
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
      context: WebDavSyncFolderInspectionContext.setup,
    );
    final binding = await service.configureExistingRoot(
      inspection: inspection as WebDavSyncFolderExisting,
    );

    transport
      ..bytes = null
      ..error = const WebDavException(
        kind: WebDavErrorKind.notFound,
        message: 'missing',
      );
    await expectLater(
      service.inspectFolder(
        config: _config,
        folderPath: 'Family',
        context: WebDavSyncFolderInspectionContext.repair,
        repairBindingId: binding.id,
      ),
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
      service.inspectFolder(
        config: _config,
        folderPath: 'Family',
        context: WebDavSyncFolderInspectionContext.repair,
        repairBindingId: binding.id,
      ),
      throwsA(isA<WebDavSyncRootChangedException>()),
    );
  });

  test(
    'merged authority pins only ciphertext and hash; runtime uses sealed secret',
    () async {
      final marker = await codec.sealRoot(
        passphrase: 'authority-secret',
        circleId: 'authority-circle',
        createdAt: DateTime.utc(2026, 9, 1),
        memoryKiB: 8,
        iterations: 1,
      );
      final authorityBytes = WebDavSyncAuthorityFile(
        markerBytes: marker,
        syncPassphrase: 'authority-secret',
      ).encode();
      final authorityTransport = _AuthorityProbeTransport()
        ..authorityBytes = authorityBytes;
      final authorityService = WebDavSyncSetupService(
        store: store,
        codec: codec,
        transportFactory: ({required endpoint, required credentials}) {
          authorityTransport
            ..endpoint = endpoint
            ..credentials = credentials;
          return authorityTransport;
        },
      );

      final inspection =
          await authorityService.inspectFolder(
                config: _config,
                folderPath: 'Family',
                context: WebDavSyncFolderInspectionContext.setup,
              )
              as WebDavSyncFolderExisting;
      expect(inspection.markerBytes, orderedEquals(marker));
      expect(inspection.authorityBytes, orderedEquals(authorityBytes));
      expect(inspection.syncPassphrase, 'authority-secret');

      final binding = await authorityService.configureExistingRoot(
        inspection: inspection,
      );
      final snapshot = await store.load();
      expect(binding.circleId, 'authority-circle');
      expect(
        snapshot.namespaceFor(binding)!.markerBytes,
        orderedEquals(marker),
      );
      final namespace = snapshot.namespaceFor(binding)!;
      expect(
        namespace.authorityContentHash,
        webDavSyncAuthorityHash(authorityBytes),
      );
      final serialized = jsonEncode(namespace.toJson());
      final prefs = await SharedPreferences.getInstance();
      final preferenceContents = prefs.getKeys().map(prefs.get).join();
      for (final value in [serialized, preferenceContents]) {
        expect(value, isNot(contains('authority-secret')));
        expect(value, isNot(contains(base64Encode(authorityBytes))));
        expect(value, isNot(contains(utf8.decode(authorityBytes))));
      }
      final secrets = await store.readSecrets(binding);
      final runtimeRoot = await codec.openPinnedAuthority(
        namespace.markerBytes!,
        secrets.syncPassphrase,
      );
      expect(runtimeRoot.document.circleId, 'authority-circle');
      final oldPin = WebDavSyncNamespace.fromJson({
        ...namespace.toJson(),
        'markerBytes': base64Encode(authorityBytes),
        'authorityContentHash': null,
      });
      expect(oldPin.markerBytes, orderedEquals(marker));
      expect(oldPin.matchesAuthority(authorityBytes), isTrue);
      expect(
        jsonEncode(oldPin.toJson()),
        isNot(contains(base64Encode(authorityBytes))),
      );
      expect(authorityTransport.writeAuthorityCalls, 0);
      await store.setLifecycle(binding.id, WebDavSyncLifecycle.active);
      await store.promoteStaged(binding.id);
      final changedBytes = Uint8List.fromList([...authorityBytes, 32]);
      final changedInspection = WebDavSyncFolderExisting(
        location: inspection.location,
        config: inspection.config,
        markerBytes: marker,
        authorityBytes: changedBytes,
        metadata: inspection.metadata,
        syncPassphrase: inspection.syncPassphrase,
      );
      // Even a whitespace-only outer change with identical inner ciphertext
      // must not bypass the resealing guard as a legacy upgrade.
      await expectLater(
        authorityService.configureExistingRoot(inspection: changedInspection),
        throwsA(isA<WebDavSyncRootChangedException>()),
      );
      authorityTransport.authorityBytes = changedBytes;
      await expectLater(
        authorityService.revalidate(binding.id),
        throwsA(isA<WebDavSyncRootChangedException>()),
      );
    },
  );

  test(
    'malformed merged authority fails closed without a legacy overwrite',
    () async {
      final malformed = <Uint8List>[
        Uint8List.fromList(utf8.encode('not-json')),
        WebDavSyncAuthorityFile(
          markerBytes: Uint8List.fromList(
            utf8.encode('{malformed-inner-secret'),
          ),
          syncPassphrase: 'malformed-inner-secret',
        ).encode(),
        Uint8List.fromList(
          utf8.encode('{"version":2,"marker":"AA==","syncPassphrase":"x"}'),
        ),
        Uint8List.fromList(utf8.encode('{"version":1,"marker":"AA=="}')),
        Uint8List.fromList(
          List<int>.filled(WebDavSyncAuthorityFile.maxBytes + 1, 0),
        ),
      ];
      for (final bytes in malformed) {
        final authorityTransport = _AuthorityProbeTransport()
          ..authorityBytes = bytes;
        final authorityService = WebDavSyncSetupService(
          store: store,
          codec: codec,
          transportFactory: ({required endpoint, required credentials}) {
            authorityTransport.endpoint = endpoint;
            return authorityTransport;
          },
        );

        await expectLater(
          authorityService.inspectFolder(
            config: _config,
            folderPath: 'Family',
            context: WebDavSyncFolderInspectionContext.setup,
          ),
          throwsA(
            isA<WebDavSyncAuthorityFileException>().having(
              (error) => error.toString(),
              'sanitized message',
              isNot(contains('malformed-inner-secret')),
            ),
          ),
        );
        expect(authorityTransport.writeAuthorityCalls, 0);
        expect(authorityTransport.legacyMarkerReads, 0);
      }
    },
  );

  test('legacy marker-only repair provisions merged authority', () async {
    final installed = await installActiveBinding();
    await store.markError(installed.binding.id, StateError('expired'));
    final authorityTransport = _AuthorityProbeTransport()
      ..bytes = installed.marker
      ..keyBytes = null;
    final authorityService = WebDavSyncSetupService(
      store: store,
      codec: codec,
      transportFactory: ({required endpoint, required credentials}) {
        authorityTransport
          ..endpoint = endpoint
          ..credentials = credentials;
        return authorityTransport;
      },
    );

    final inspection =
        await authorityService.inspectFolder(
              config: _config,
              folderPath: 'Family',
              context: WebDavSyncFolderInspectionContext.repair,
              repairBindingId: installed.binding.id,
            )
            as WebDavSyncFolderExisting;
    final repaired = await authorityService.configureExistingRoot(
      inspection: inspection,
    );

    expect(authorityTransport.writeAuthorityCalls, 1);
    final authority = WebDavSyncAuthorityFile.parse(
      authorityTransport.authorityBytes!,
    );
    expect(authority.markerBytes, orderedEquals(installed.marker));
    expect(authority.syncPassphrase, 'circle-secret');
    expect(repaired.lifecycle, WebDavSyncLifecycle.active);
    expect(
      (await store.load()).namespaceFor(repaired)!.markerBytes,
      orderedEquals(installed.marker),
    );
  });

  test('legacy upgrade adopts a different valid read-back authority', () async {
    final legacyMarker = await codec.sealRoot(
      passphrase: 'legacy-secret',
      circleId: 'legacy-circle',
      createdAt: DateTime.utc(2026, 9, 1),
      memoryKiB: 8,
      iterations: 1,
    );
    final winnerMarker = await codec.sealRoot(
      passphrase: 'winner-secret',
      circleId: 'winner-circle',
      createdAt: DateTime.utc(2026, 9, 2),
      memoryKiB: 8,
      iterations: 1,
    );
    final winnerAuthority = WebDavSyncAuthorityFile(
      markerBytes: winnerMarker,
      syncPassphrase: 'winner-secret',
    ).encode();
    final authorityTransport = _AuthorityProbeTransport()
      ..bytes = legacyMarker
      ..keyBytes = const WebDavSyncRootKeyFile(
        syncPassphrase: 'legacy-secret',
      ).encode()
      ..authorityAfterWrite = winnerAuthority;
    final authorityService = WebDavSyncSetupService(
      store: store,
      codec: codec,
      transportFactory: ({required endpoint, required credentials}) {
        authorityTransport
          ..endpoint = endpoint
          ..credentials = credentials;
        return authorityTransport;
      },
    );

    final inspection =
        await authorityService.inspectFolder(
              config: _config,
              folderPath: 'Family',
              context: WebDavSyncFolderInspectionContext.setup,
            )
            as WebDavSyncFolderExisting;

    expect(authorityTransport.writeAuthorityCalls, 1);
    expect(inspection.authorityBytes, orderedEquals(winnerAuthority));
    expect(inspection.markerBytes, orderedEquals(winnerMarker));
    expect(inspection.syncPassphrase, 'winner-secret');
  });

  test(
    'legacy upgrade adopts authority appearing before PUT without writing',
    () async {
      final legacyMarker = await codec.sealRoot(
        passphrase: 'legacy-secret',
        circleId: 'legacy-circle',
        createdAt: DateTime.utc(2026, 9, 1),
        memoryKiB: 8,
        iterations: 1,
      );
      final winnerMarker = await codec.sealRoot(
        passphrase: 'winner-secret',
        circleId: 'winner-circle',
        createdAt: DateTime.utc(2026, 9, 2),
        memoryKiB: 8,
        iterations: 1,
      );
      final winnerAuthority = WebDavSyncAuthorityFile(
        markerBytes: winnerMarker,
        syncPassphrase: 'winner-secret',
      ).encode();
      final authorityTransport = _AuthorityProbeTransport()
        ..bytes = legacyMarker
        ..keyBytes = const WebDavSyncRootKeyFile(
          syncPassphrase: 'legacy-secret',
        ).encode()
        ..authorityOnSecondRead = winnerAuthority;
      final authorityService = WebDavSyncSetupService(
        store: store,
        codec: codec,
        transportFactory: ({required endpoint, required credentials}) {
          authorityTransport
            ..endpoint = endpoint
            ..credentials = credentials;
          return authorityTransport;
        },
      );

      final inspection =
          await authorityService.inspectFolder(
                config: _config,
                folderPath: 'Family',
                context: WebDavSyncFolderInspectionContext.setup,
              )
              as WebDavSyncFolderExisting;

      expect(authorityTransport.writeAuthorityCalls, 0);
      expect(inspection.authorityBytes, orderedEquals(winnerAuthority));
      expect(inspection.markerBytes, orderedEquals(winnerMarker));
      expect(inspection.syncPassphrase, 'winner-secret');
    },
  );

  test(
    'a detected authority replacement re-enters authenticated adoption',
    () async {
      final firstMarker = await codec.sealRoot(
        passphrase: 'first-circle-secret',
        circleId: 'circle-first',
        createdAt: DateTime.utc(2026, 9, 1),
        memoryKiB: 8,
        iterations: 1,
      );
      final firstAuthority = WebDavSyncAuthorityFile(
        markerBytes: firstMarker,
        syncPassphrase: 'first-circle-secret',
      ).encode();
      final authorityTransport = _AuthorityProbeTransport()
        ..authorityBytes = firstAuthority;
      final authorityService = WebDavSyncSetupService(
        store: store,
        codec: codec,
        transportFactory: ({required endpoint, required credentials}) {
          authorityTransport
            ..endpoint = endpoint
            ..credentials = credentials;
          return authorityTransport;
        },
      );
      final firstInspection =
          await authorityService.inspectFolder(
                config: _config,
                folderPath: 'Family',
                context: WebDavSyncFolderInspectionContext.setup,
              )
              as WebDavSyncFolderExisting;
      var active = await authorityService.configureExistingRoot(
        inspection: firstInspection,
      );
      active = await store.setLifecycle(active.id, WebDavSyncLifecycle.active);
      await store.promoteStaged(active.id);
      final firstNamespace = (await store.load()).namespaceFor(active)!;

      final replacementMarker = await codec.sealRoot(
        passphrase: 'replacement-secret',
        circleId: 'circle-replacement',
        createdAt: DateTime.utc(2026, 9, 2),
        memoryKiB: 8,
        iterations: 1,
      );
      final replacementAuthority = WebDavSyncAuthorityFile(
        markerBytes: replacementMarker,
        syncPassphrase: 'replacement-secret',
      ).encode();
      authorityTransport.authorityBytes = replacementAuthority;

      await expectLater(
        authorityService.revalidate(active.id),
        throwsA(isA<WebDavSyncRootChangedException>()),
      );
      final repairInspection =
          await authorityService.inspectFolder(
                config: _config,
                folderPath: 'Family',
                context: WebDavSyncFolderInspectionContext.repair,
                repairBindingId: active.id,
              )
              as WebDavSyncFolderExisting;
      final reconnecting = await authorityService.configureExistingRoot(
        inspection: repairInspection,
        reconnectActive: true,
      );
      final snapshot = await store.load();
      final replacementNamespace = snapshot.namespaceFor(reconnecting)!;

      expect(reconnecting.lifecycle, WebDavSyncLifecycle.rootVerified);
      expect(reconnecting.circleId, 'circle-replacement');
      expect(
        replacementNamespace.markerBytes,
        orderedEquals(replacementMarker),
      );
      expect(replacementNamespace.deviceId, isNot(firstNamespace.deviceId));
      expect(
        (await store.readSecrets(reconnecting)).syncPassphrase,
        'replacement-secret',
      );
    },
  );
}

class _FakeProbeTransport implements WebDavSyncProbeTransport {
  Uri? endpoint;
  WebDavCredentials? credentials;
  Uint8List? _bytes;
  Uint8List? keyBytes;
  Object? error;
  Object? keyError;
  final List<String> paths = <String>[];

  Uint8List? get bytes => _bytes;

  set bytes(Uint8List? value) {
    _bytes = value;
    if (value != null) {
      keyBytes ??= const WebDavSyncRootKeyFile(
        syncPassphrase: 'circle-secret',
      ).encode();
    }
  }

  @override
  Future<WebDavBytesResult> readRootMarker({
    required String path,
    Future<void> Function()? beforeSend,
  }) async {
    paths.add(path);
    await beforeSend?.call();
    final failure = error;
    if (failure != null) throw failure;
    final body = _bytes ?? Uint8List(0);
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
  Future<WebDavBytesResult> readRootKey({
    required String path,
    Future<void> Function()? beforeSend,
  }) async {
    paths.add(path);
    await beforeSend?.call();
    if (keyError case final failure?) throw failure;
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
        uri: endpoint!.resolve(path),
        headers: const <String, String>{},
      ),
    );
  }

  @override
  void close() {}
}

final class _AuthorityProbeTransport extends _FakeProbeTransport
    implements
        WebDavSyncAuthorityProbeTransport,
        WebDavSyncAuthorityProvisionTransport {
  Uint8List? authorityBytes;
  Object? authorityError;
  Uint8List? authorityAfterWrite;
  Uint8List? authorityOnSecondRead;
  int authorityReads = 0;
  int writeAuthorityCalls = 0;
  int legacyMarkerReads = 0;

  @override
  Future<WebDavBytesResult> readRootMarker({
    required String path,
    Future<void> Function()? beforeSend,
  }) {
    legacyMarkerReads++;
    return super.readRootMarker(path: path, beforeSend: beforeSend);
  }

  @override
  Future<WebDavBytesResult> readRootAuthority({
    required String path,
    Future<void> Function()? beforeSend,
  }) async {
    paths.add(path);
    await beforeSend?.call();
    if (authorityError case final failure?) throw failure;
    authorityReads++;
    if (authorityReads == 2 && authorityOnSecondRead != null) {
      authorityBytes = authorityOnSecondRead;
    }
    final body = authorityBytes;
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
        uri: endpoint!.resolve(path),
        headers: const <String, String>{},
      ),
    );
  }

  @override
  Future<WebDavResponseMetadata> writeRootAuthority({
    required String path,
    required Uint8List bytes,
    Future<void> Function()? beforeSend,
  }) async {
    writeAuthorityCalls++;
    paths.add(path);
    await beforeSend?.call();
    authorityBytes = Uint8List.fromList(authorityAfterWrite ?? bytes);
    return WebDavResponseMetadata(
      statusCode: 201,
      uri: endpoint!.resolve(path),
      headers: const <String, String>{},
    );
  }
}
