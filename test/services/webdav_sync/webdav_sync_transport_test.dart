import 'dart:typed_data';

import 'package:debrify/services/webdav_protocol_client.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_hot_models.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_models.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  WebDavSyncFolderLocation location() => WebDavSyncFolderLocation(
    endpoint: 'https://example.test/dav',
    folderPath: 'Family',
    serverName: 'Test',
  );

  test('section PUT metadata accepts absence and non-empty validators', () {
    validateWebDavSyncSectionWriteMetadata(
      WebDavResponseMetadata(
        statusCode: 201,
        uri: Uri.parse('https://example.test/dav/section.enc'),
        headers: const <String, String>{},
      ),
      expectedBytes: 42,
    );
    validateWebDavSyncSectionWriteMetadata(
      WebDavResponseMetadata(
        statusCode: 201,
        uri: Uri.parse('https://example.test/dav/section.enc'),
        headers: const <String, String>{
          'ETag': '"section-1"',
          'X-Stored-Content-Length': '42',
        },
      ),
      expectedBytes: 42,
    );
  });

  test(
    'section PUT metadata rejects empty ETag and stored-size contradictions',
    () {
      final uri = Uri.parse('https://example.test/dav/section.enc');

      expect(
        () => validateWebDavSyncSectionWriteMetadata(
          WebDavResponseMetadata(
            statusCode: 201,
            uri: uri,
            headers: const <String, String>{'etag': ''},
          ),
          expectedBytes: 42,
        ),
        throwsStateError,
      );
      expect(
        () => validateWebDavSyncSectionWriteMetadata(
          WebDavResponseMetadata(
            statusCode: 201,
            uri: uri,
            headers: const <String, String>{'content-range': 'bytes 0-40/41'},
          ),
          expectedBytes: 42,
        ),
        throwsStateError,
      );
    },
  );

  test(
    'large section PUT accepts a 201 text body with Content-Length 2',
    () async {
      final bytes = Uint8List(64 * 1024);
      final transport = ProtocolWebDavSyncTransport(
        location: location(),
        credentials: const WebDavCredentials(username: '', password: ''),
        client: MockClient((request) async {
          expect(request.method, 'PUT');
          expect(request.bodyBytes, hasLength(bytes.length));
          return http.Response(
            'OK',
            201,
            headers: const <String, String>{'content-length': '2'},
          );
        }),
      );

      final metadata = await transport.writeSection(
        'device-a',
        'a' * 64,
        bytes,
        maxBytes: WebDavSyncLimits.maxGraphDocumentBytes,
      );
      validateWebDavSyncSectionWriteMetadata(
        metadata,
        expectedBytes: bytes.length,
      );

      transport.close();
    },
  );

  test('peer discovery returns only bounded safe collection IDs', () async {
    final client = MockClient((request) async {
      expect(request.method, 'PROPFIND');
      return http.Response(
        _listing(<String>['device-b', '../bad', 'device-a']),
        207,
        headers: const <String, String>{
          'date': 'Tue, 01 Sep 2026 00:00:00 GMT',
        },
      );
    });
    final transport = ProtocolWebDavSyncTransport(
      location: location(),
      credentials: const WebDavCredentials(username: '', password: ''),
      client: client,
    );

    final result = await transport.listDeviceIds();

    expect(result.deviceIds, <String>['device-a', 'device-b']);
    expect(result.metadata.serverDate, DateTime.utc(2026, 9, 1));
    transport.close();
  });

  test('peer discovery rejects a listing beyond the peer cap', () async {
    final ids = List<String>.generate(
      WebDavSyncLimits.maxPeers + 1,
      (index) => 'device-$index',
    );
    final transport = ProtocolWebDavSyncTransport(
      location: location(),
      credentials: const WebDavCredentials(username: '', password: ''),
      client: MockClient((_) async => http.Response(_listing(ids), 207)),
    );

    await expectLater(
      transport.listDeviceIds(),
      throwsA(
        isA<WebDavException>().having(
          (error) => error.kind,
          'kind',
          WebDavErrorKind.malformedResponse,
        ),
      ),
    );
    transport.close();
  });

  test('manifest probe uses HEAD and prefers ETag', () async {
    final transport = ProtocolWebDavSyncTransport(
      location: location(),
      credentials: const WebDavCredentials(username: '', password: ''),
      client: MockClient((request) async {
        expect(request.method, 'HEAD');
        expect(
          request.url.path,
          '/dav/Family/debrify-sync/devices/device-b/manifest.enc',
        );
        return http.Response(
          '',
          200,
          headers: const <String, String>{
            'etag': '"revision-2"',
            'last-modified': 'Tue, 01 Sep 2026 00:00:00 GMT',
            'content-length': '42',
          },
        );
      }),
    );

    final result = await transport.probeManifest('device-b');

    expect(result.exists, isTrue);
    expect(
      result.validator,
      const WebDavSyncManifestValidator.etag('"revision-2"'),
    );
    transport.close();
  });

  test(
    'manifest probe falls back to modified time and content length',
    () async {
      final transport = ProtocolWebDavSyncTransport(
        location: location(),
        credentials: const WebDavCredentials(username: '', password: ''),
        client: MockClient(
          (_) async => http.Response(
            '',
            200,
            headers: const <String, String>{
              'last-modified': 'Tue, 01 Sep 2026 00:00:00 GMT',
              'content-length': '42',
            },
          ),
        ),
      );

      final result = await transport.probeManifest('device-b');

      expect(
        result.validator,
        const WebDavSyncManifestValidator.metadata(
          lastModified: 'Tue, 01 Sep 2026 00:00:00 GMT',
          contentLength: 42,
        ),
      );
      transport.close();
    },
  );

  test('405 HEAD probe reads the target DAV property validator', () async {
    var requests = 0;
    final transport = ProtocolWebDavSyncTransport(
      location: location(),
      credentials: const WebDavCredentials(username: '', password: ''),
      client: MockClient((request) async {
        requests++;
        if (request.method == 'HEAD') return http.Response('', 405);
        expect(request.method, 'PROPFIND');
        expect(request.headers['depth'], '0');
        expect(request.body, contains('<D:getetag/>'));
        expect(request.body, contains('<D:getlastmodified/>'));
        expect(request.body, contains('<D:getcontentlength/>'));
        return http.Response('''<?xml version="1.0" encoding="utf-8"?>
          <D:multistatus xmlns:D="DAV:">
            <D:response>
              <D:href>/dav/Family/debrify-sync/devices/device-b/manifest.enc</D:href>
              <D:propstat>
                <D:prop>
                  <D:getetag>"dav-revision-3"</D:getetag>
                  <D:getlastmodified>Tue, 01 Sep 2026 00:00:00 GMT</D:getlastmodified>
                  <D:getcontentlength>42</D:getcontentlength>
                </D:prop>
                <D:status>HTTP/1.1 200 OK</D:status>
              </D:propstat>
            </D:response>
          </D:multistatus>''', 207);
      }),
    );

    final result = await transport.probeManifest('device-b');

    expect(requests, 2);
    expect(result.exists, isTrue);
    expect(
      result.validator,
      const WebDavSyncManifestValidator.etag('"dav-revision-3"'),
    );
    transport.close();
  });

  test(
    'missing manifest probe is a change hint rather than an error',
    () async {
      final transport = ProtocolWebDavSyncTransport(
        location: location(),
        credentials: const WebDavCredentials(username: '', password: ''),
        client: MockClient((_) async => http.Response('', 404)),
      );

      final result = await transport.probeManifest('device-b');

      expect(result.exists, isFalse);
      expect(result.validator, isNull);
      transport.close();
    },
  );

  test('root commit keeps create-only header and accepts any 2xx', () async {
    final transport = ProtocolWebDavSyncTransport(
      location: location(),
      credentials: const WebDavCredentials(username: '', password: ''),
      client: MockClient((request) async {
        expect(request.method, 'PUT');
        expect(request.url.path, '/dav/Family/debrify-sync/circle.json.enc');
        expect(request.headers['if-none-match'], '*');
        return http.Response('', 204);
      }),
    );

    final metadata = await transport.createRootMarker(
      Uint8List.fromList(<int>[1, 2, 3]),
    );

    expect(metadata.statusCode, 204);
    transport.close();
  });

  for (final conflictStatus in <int>[403, 405, 409, 412]) {
    test(
      'conditional-create probe accepts HTTP $conflictStatus conflict dialect',
      () async {
        final methods = <String>[];
        Uri? sentinel;
        Uint8List? firstBody;
        Uint8List? secondBody;
        var putCount = 0;
        final transport = ProtocolWebDavSyncTransport(
          location: location(),
          credentials: const WebDavCredentials(username: '', password: ''),
          client: MockClient((request) async {
            methods.add(request.method);
            sentinel ??= request.url;
            expect(request.url, sentinel);
            expect(
              request.url.path,
              matches(
                RegExp(r'^/dav/Family/debrify-sync/\.cond-probe-[0-9a-f]{32}$'),
              ),
            );
            if (request.method == 'PUT') {
              expect(request.headers['if-none-match'], '*');
              putCount++;
              if (putCount == 1) {
                firstBody = Uint8List.fromList(request.bodyBytes);
                return http.Response('', 200);
              }
              secondBody = Uint8List.fromList(request.bodyBytes);
              return http.Response('', conflictStatus);
            }
            if (request.method == 'GET') {
              return http.Response.bytes(firstBody!, 200);
            }
            if (request.method == 'DELETE') return http.Response('', 204);
            return http.Response('', 500);
          }),
        );

        await transport.verifyConditionalCreate(
          syncRootPath: 'Family/debrify-sync',
        );

        expect(methods, <String>['PUT', 'GET', 'PUT', 'GET', 'DELETE']);
        expect(firstBody, hasLength(16));
        expect(secondBody, hasLength(16));
        expect(secondBody, isNot(orderedEquals(firstBody!)));
        transport.close();
      },
    );
  }

  test(
    'conditional-create probe refuses an overwrite lie and cleans up',
    () async {
      final methods = <String>[];
      final diagnostics = <String>[];
      Uint8List? stored;
      final transport = ProtocolWebDavSyncTransport(
        location: location(),
        credentials: const WebDavCredentials(username: '', password: ''),
        diagnostic: (message, _) => diagnostics.add(message),
        client: MockClient((request) async {
          methods.add(request.method);
          if (request.method == 'PUT') {
            stored = Uint8List.fromList(request.bodyBytes);
            return http.Response('', 201);
          }
          if (request.method == 'GET') {
            return http.Response.bytes(stored!, 200);
          }
          if (request.method == 'DELETE') return http.Response('', 204);
          return http.Response('', 500);
        }),
      );

      await expectLater(
        transport.verifyConditionalCreate(syncRootPath: 'Family/debrify-sync'),
        throwsA(
          isA<WebDavSyncProviderUnsupportedException>()
              .having(
                (error) => error.toString(),
                'message',
                contains('(probe step 2: HTTP 201)'),
              )
              .having((error) => error.probeStep, 'step', 2)
              .having((error) => error.statusCode, 'status', 201),
        ),
      );

      expect(methods, <String>['PUT', 'GET', 'PUT', 'GET', 'DELETE']);
      expect(diagnostics, <String>[
        'WebDAV sync authority failure: probe-conflict, HTTP 201',
      ]);
      transport.close();
    },
  );

  test(
    'conditional-create probe refuses an absent conflict read-back',
    () async {
      final diagnostics = <String>[];
      var putCount = 0;
      var getCount = 0;
      Uint8List? stored;
      final transport = ProtocolWebDavSyncTransport(
        location: location(),
        credentials: const WebDavCredentials(username: '', password: ''),
        diagnostic: (message, _) => diagnostics.add(message),
        client: MockClient((request) async {
          if (request.method == 'PUT') {
            putCount++;
            if (putCount == 1) {
              stored = Uint8List.fromList(request.bodyBytes);
              return http.Response('', 201);
            }
            return http.Response('', 409);
          }
          if (request.method == 'GET') {
            getCount++;
            return getCount == 1
                ? http.Response.bytes(stored!, 200)
                : http.Response('', 404);
          }
          if (request.method == 'DELETE') return http.Response('', 204);
          return http.Response('', 500);
        }),
      );

      await expectLater(
        transport.verifyConditionalCreate(syncRootPath: 'Family/debrify-sync'),
        throwsA(
          isA<WebDavSyncProviderUnsupportedException>()
              .having((error) => error.probeStep, 'step', 2)
              .having((error) => error.statusCode, 'status', 404),
        ),
      );

      expect(diagnostics, <String>[
        'WebDAV sync authority failure: probe-readback, HTTP 404',
      ]);
      transport.close();
    },
  );

  test('root key claim keeps create-only header and accepts any 2xx', () async {
    final transport = ProtocolWebDavSyncTransport(
      location: location(),
      credentials: const WebDavCredentials(username: '', password: ''),
      client: MockClient((request) async {
        expect(request.method, 'PUT');
        expect(request.url.path, '/dav/Family/debrify-sync/circle.key');
        expect(request.headers['if-none-match'], '*');
        return http.Response('', 200);
      }),
    );

    final metadata = await transport.createRootKey(
      const WebDavSyncRootKeyFile(syncPassphrase: 'machine-secret').encode(),
    );

    expect(metadata.statusCode, 200);
    transport.close();
  });

  test(
    'root key claim returns 204 for caller read-back verification',
    () async {
      final transport = ProtocolWebDavSyncTransport(
        location: location(),
        credentials: const WebDavCredentials(username: '', password: ''),
        client: MockClient((_) async => http.Response('', 204)),
      );

      final metadata = await transport.createRootKey(
        const WebDavSyncRootKeyFile(syncPassphrase: 'machine-secret').encode(),
      );
      expect(metadata.statusCode, 204);
      transport.close();
    },
  );

  test('root key reads enforce the 4 KiB cap', () async {
    final transport = ProtocolWebDavSyncTransport(
      location: location(),
      credentials: const WebDavCredentials(username: '', password: ''),
      client: MockClient(
        (request) async => http.Response.bytes(
          Uint8List(WebDavSyncRootKeyFile.maxBytes + 1),
          200,
        ),
      ),
    );

    await expectLater(
      transport.readRootKey(),
      throwsA(
        isA<WebDavException>().having(
          (error) => error.kind,
          'kind',
          WebDavErrorKind.invalidRequest,
        ),
      ),
    );
    transport.close();
  });

  test(
    'activation verifies the root collection after ambiguous MKCOL 405',
    () async {
      final requests = <String>[];
      final transport = ProtocolWebDavSyncTransport(
        location: location(),
        credentials: const WebDavCredentials(username: '', password: ''),
        client: MockClient((request) async {
          requests.add('${request.method} ${request.url.path}');
          if (request.method == 'MKCOL') return http.Response('', 405);
          if (request.method == 'PROPFIND') return http.Response('', 404);
          return http.Response('', 500);
        }),
      );

      await expectLater(
        transport.ensureActivationLayout(),
        throwsA(isA<WebDavSyncRootKeyClaimException>()),
      );

      expect(requests.first, startsWith('MKCOL '));
      expect(requests, contains('PROPFIND /dav/Family/debrify-sync/'));
      transport.close();
    },
  );

  test('live-shape runtime binding reads no keyfile', () async {
    final requests = <String>[];
    final WebDavSyncTransport transport = ProtocolWebDavSyncTransport(
      location: WebDavSyncFolderLocation(
        endpoint: 'https://app.koofr.net/dav/',
        folderPath: 'Koofr/Koofr sync',
        serverName: 'Koofr',
      ),
      credentials: const WebDavCredentials(
        username: 'live-user',
        password: 'live-password',
      ),
      client: MockClient((request) async {
        requests.add('${request.method} ${request.url.path}');
        return http.Response.bytes(Uint8List.fromList(<int>[1, 2, 3]), 200);
      }),
    );

    await transport.readRootMarker();

    expect(requests, <String>[
      'GET /dav/Koofr/Koofr%20sync/debrify-sync/circle.json.enc',
    ]);
    expect(requests.single, isNot(contains('circle.key')));
    transport.close();
  });

  test('root commit returns 204 for caller read-back verification', () async {
    final transport = ProtocolWebDavSyncTransport(
      location: location(),
      credentials: const WebDavCredentials(username: '', password: ''),
      client: MockClient((_) async => http.Response('', 204)),
    );

    final metadata = await transport.createRootMarker(
      Uint8List.fromList(<int>[1, 2, 3]),
    );
    expect(metadata.statusCode, 204);
    transport.close();
  });

  test(
    'own-section listing keeps only bounded hash files with known age',
    () async {
      final oldHash = 'a' * 64;
      final client = MockClient((request) async {
        expect(request.method, 'PROPFIND');
        expect(
          request.url.path,
          '/dav/Family/debrify-sync/devices/device-a/sections/',
        );
        expect(request.headers['depth'], '1');
        return http.Response(
          _sectionListing(oldHash),
          207,
          headers: const <String, String>{
            'date': 'Tue, 01 Sep 2026 00:00:00 GMT',
          },
        );
      });
      final transport = ProtocolWebDavSyncTransport(
        location: location(),
        credentials: const WebDavCredentials(username: '', password: ''),
        client: client,
      );

      final result = await transport.listOwnSections('device-a');

      expect(result, hasLength(1));
      expect(result.single.contentHash, oldHash);
      expect(
        result.single.lastModifiedMs,
        DateTime.utc(2026, 8, 20).millisecondsSinceEpoch,
      );
      transport.close();
    },
  );

  test('over-cap section listing returns an oldest bounded GC batch', () async {
    final hashes = List<String>.generate(
      WebDavSyncLimits.maxStoredSectionsPerDevice + 2,
      (index) => index.toRadixString(16).padLeft(64, '0'),
    );
    final transport = ProtocolWebDavSyncTransport(
      location: location(),
      credentials: const WebDavCredentials(username: '', password: ''),
      client: MockClient(
        (_) async => http.Response(_sectionListingBatch(hashes), 207),
      ),
    );

    final result = await transport.listOwnSections('device-a');

    expect(result, hasLength(WebDavSyncLimits.maxStoredSectionsPerDevice));
    expect(result.first.contentHash, hashes.first);
    expect(
      result.map((section) => section.contentHash),
      isNot(contains(hashes.last)),
    );
    transport.close();
  });
}

String _listing(List<String> ids) =>
    '<?xml version="1.0"?><D:multistatus xmlns:D="DAV:">'
    '<D:response><D:href>/dav/Family/debrify-sync/devices/</D:href>'
    '<D:propstat><D:prop><D:resourcetype><D:collection/>'
    '</D:resourcetype></D:prop></D:propstat></D:response>'
    '${ids.map((id) => '<D:response><D:href>/dav/Family/debrify-sync/'
        'devices/$id/</D:href><D:propstat><D:prop><D:resourcetype>'
        '<D:collection/></D:resourcetype></D:prop></D:propstat>'
        '</D:response>').join()}'
    '</D:multistatus>';

String _sectionListing(String hash) =>
    '<?xml version="1.0"?><D:multistatus xmlns:D="DAV:">'
    '<D:response><D:href>/dav/Family/debrify-sync/devices/device-a/'
    'sections/</D:href><D:propstat><D:prop><D:resourcetype>'
    '<D:collection/></D:resourcetype></D:prop></D:propstat></D:response>'
    '<D:response><D:href>/dav/Family/debrify-sync/devices/device-a/'
    'sections/$hash.enc</D:href><D:propstat><D:prop><D:resourcetype/>'
    '<D:getlastmodified>Thu, 20 Aug 2026 00:00:00 GMT</D:getlastmodified>'
    '</D:prop></D:propstat></D:response>'
    '<D:response><D:href>/dav/Family/debrify-sync/devices/device-a/'
    'sections/not-a-hash.enc</D:href><D:propstat><D:prop>'
    '<D:resourcetype/><D:getlastmodified>Thu, 20 Aug 2026 00:00:00 GMT'
    '</D:getlastmodified></D:prop></D:propstat></D:response>'
    '<D:response><D:href>/dav/Family/debrify-sync/devices/device-a/'
    'sections/${List<String>.filled(64, 'b').join()}.enc</D:href>'
    '<D:propstat><D:prop>'
    '<D:resourcetype/><D:getlastmodified>unknown</D:getlastmodified>'
    '</D:prop></D:propstat></D:response>'
    '</D:multistatus>';

String _sectionListingBatch(List<String> hashes) =>
    '<?xml version="1.0"?><D:multistatus xmlns:D="DAV:">'
    '<D:response><D:href>/dav/Family/debrify-sync/devices/device-a/'
    'sections/</D:href><D:propstat><D:prop><D:resourcetype>'
    '<D:collection/></D:resourcetype></D:prop></D:propstat></D:response>'
    '${hashes.map((hash) => '<D:response><D:href>/dav/Family/debrify-sync/'
        'devices/device-a/sections/$hash.enc</D:href><D:propstat><D:prop>'
        '<D:resourcetype/><D:getlastmodified>'
        'Thu, 20 Aug 2026 00:00:00 GMT</D:getlastmodified>'
        '</D:prop></D:propstat></D:response>').join()}'
    '</D:multistatus>';
