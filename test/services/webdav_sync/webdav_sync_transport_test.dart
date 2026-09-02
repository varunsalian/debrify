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

  test('root commit is create-only and accepts exactly 201', () async {
    final transport = ProtocolWebDavSyncTransport(
      location: location(),
      credentials: const WebDavCredentials(username: '', password: ''),
      client: MockClient((request) async {
        expect(request.method, 'PUT');
        expect(request.url.path, '/dav/Family/debrify-sync/circle.json.enc');
        expect(request.headers['if-none-match'], '*');
        return http.Response('', 201);
      }),
    );

    final metadata = await transport.createRootMarker(
      Uint8List.fromList(<int>[1, 2, 3]),
    );

    expect(metadata.statusCode, 201);
    transport.close();
  });

  test('root commit rejects ambiguous 204 success', () async {
    final transport = ProtocolWebDavSyncTransport(
      location: location(),
      credentials: const WebDavCredentials(username: '', password: ''),
      client: MockClient((_) async => http.Response('', 204)),
    );

    await expectLater(
      transport.createRootMarker(Uint8List.fromList(<int>[1, 2, 3])),
      throwsA(
        isA<WebDavException>()
            .having(
              (error) => error.kind,
              'kind',
              WebDavErrorKind.unexpectedStatus,
            )
            .having((error) => error.statusCode, 'status', 204),
      ),
    );
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
