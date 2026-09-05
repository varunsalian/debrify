import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:debrify/models/webdav_item.dart';
import 'package:debrify/services/webdav_protocol_client.dart';
import 'package:debrify/services/webdav_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late HttpServer server;
  late Directory tempDirectory;
  late Future<void> Function(HttpRequest request) handler;
  late WebDavProtocolClient client;

  Future<Uri> endpointFor(HttpServer value, {String path = '/dav'}) async =>
      Uri.parse('http://${value.address.address}:${value.port}$path');

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'debrify_webdav_protocol_',
    );
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    handler = (request) async {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    };
    server.listen((request) async {
      try {
        await handler(request);
      } catch (error, stackTrace) {
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.write('$error\n$stackTrace');
        await request.response.close();
      }
    });
    client = WebDavProtocolClient(
      endpoint: await endpointFor(server),
      credentials: const WebDavCredentials(
        username: 'alice',
        password: 'secret',
      ),
      timeout: const Duration(seconds: 5),
    );
  });

  tearDown(() async {
    client.close();
    await server.close(force: true);
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test(
    'parses canonical endpoints and rejects unsafe schemes and userinfo',
    () {
      expect(
        WebDavProtocolClient.parseEndpoint('example.com/dav').toString(),
        'https://example.com/dav',
      );
      expect(
        WebDavProtocolClient.parseEndpoint('example.com:8443/dav').toString(),
        'https://example.com:8443/dav',
      );
      expect(WebDavProtocolClient.isInsecureUrl('http://example.com'), isTrue);
      expect(
        WebDavProtocolClient.isInsecureUrl('https://example.com'),
        isFalse,
      );
      expect(
        () => WebDavProtocolClient.parseEndpoint('ftp://example.com/dav'),
        throwsA(
          isA<WebDavException>().having(
            (error) => error.kind,
            'kind',
            WebDavErrorKind.invalidRequest,
          ),
        ),
      );
      expect(
        () => WebDavProtocolClient.parseEndpoint(
          'https://alice:secret@example.com/dav',
        ),
        throwsA(isA<WebDavException>()),
      );
      expect(
        () => WebDavProtocolClient(
          endpoint: Uri.parse('https://alice:secret@example.com/dav'),
          credentials: const WebDavCredentials(username: '', password: ''),
        ),
        throwsA(isA<WebDavException>()),
      );
    },
  );

  test('PUT creates missing parent collections and returns metadata', () async {
    final collections = <String>{'/dav/'};
    final methods = <String>[];
    handler = (request) async {
      methods.add('${request.method} ${request.uri.path}');
      expect(
        request.headers.value(HttpHeaders.authorizationHeader),
        'Basic ${base64Encode(utf8.encode('alice:secret'))}',
      );
      if (request.method == 'MKCOL') {
        final path = request.uri.path;
        final parent = path
            .substring(0, path.length - 1)
            .replaceFirst(RegExp(r'[^/]+$'), '');
        if (!collections.contains(parent)) {
          request.response.statusCode = HttpStatus.conflict;
        } else if (!collections.add(path)) {
          request.response.statusCode = HttpStatus.methodNotAllowed;
        } else {
          request.response.statusCode = HttpStatus.created;
        }
      } else if (request.method == 'PUT') {
        final parent = request.uri.path.replaceFirst(RegExp(r'[^/]+$'), '');
        if (!collections.contains(parent)) {
          request.response.statusCode = HttpStatus.conflict;
        } else {
          expect(await utf8.decoder.bind(request).join(), 'payload');
          expect(request.headers.value(HttpHeaders.ifNoneMatchHeader), '*');
          request.response
            ..statusCode = HttpStatus.created
            ..headers.set(HttpHeaders.etagHeader, '"etag-1"')
            ..headers.set(
              HttpHeaders.dateHeader,
              'Tue, 01 Sep 2026 12:00:00 GMT',
            );
        }
      }
      await request.response.close();
    };

    final result = await client.putBytes(
      path: 'alpha/beta/backup.json',
      bytes: utf8.encode('payload'),
      maxBytes: 1024,
      ifNoneMatch: '*',
    );

    expect(result.statusCode, HttpStatus.created);
    expect(result.etag, '"etag-1"');
    expect(result.serverDate, DateTime.utc(2026, 9, 1, 12));
    expect(methods, <String>[
      'PUT /dav/alpha/beta/backup.json',
      'MKCOL /dav/alpha/beta/',
      'MKCOL /dav/alpha/',
      'MKCOL /dav/alpha/beta/',
      'PUT /dav/alpha/beta/backup.json',
    ]);
  });

  test('existing collection metadata survives MKCOL 405 success', () async {
    handler = (request) async {
      expect(request.method, 'MKCOL');
      request.response
        ..statusCode = HttpStatus.methodNotAllowed
        ..headers.set(HttpHeaders.etagHeader, '"collection-etag"')
        ..headers.set(HttpHeaders.dateHeader, 'Tue, 01 Sep 2026 12:00:00 GMT');
      await request.response.close();
    };

    final result = await client.ensureCollection('already-there');

    expect(result!.statusCode, HttpStatus.methodNotAllowed);
    expect(result.etag, '"collection-etag"');
    expect(result.serverDate, DateTime.utc(2026, 9, 1, 12));
  });

  test('malformed HTTP Date metadata is treated as unavailable', () async {
    client.close();
    client = WebDavProtocolClient(
      endpoint: Uri.parse('https://example.test/dav'),
      credentials: const WebDavCredentials(username: '', password: ''),
      client: MockClient(
        (_) async => http.Response(
          'payload',
          HttpStatus.ok,
          headers: const <String, String>{'date': 'not-an-http-date'},
        ),
      ),
    );

    final result = await client.getBytes(path: 'backup.json', maxBytes: 1024);

    expect(utf8.decode(result.bytes), 'payload');
    expect(result.metadata.serverDate, isNull);
  });

  test('uploadFile streams a file and enforces its byte cap', () async {
    final source = File('${tempDirectory.path}/source.bin');
    await source.writeAsBytes(List<int>.generate(8192, (index) => index % 251));
    var received = <int>[];
    handler = (request) async {
      received = await request.fold<List<int>>(
        <int>[],
        (bytes, chunk) => bytes..addAll(chunk),
      );
      request.response.statusCode = HttpStatus.created;
      await request.response.close();
    };

    await client.uploadFile(path: 'source.bin', file: source, maxBytes: 8192);
    expect(received, await source.readAsBytes());

    await expectLater(
      client.uploadFile(path: 'too-large.bin', file: source, maxBytes: 10),
      throwsA(
        isA<WebDavException>().having(
          (error) => error.kind,
          'kind',
          WebDavErrorKind.invalidRequest,
        ),
      ),
    );
  });

  test(
    'a progressing file upload may exceed the small-request timeout',
    () async {
      final source = File('${tempDirectory.path}/slow-source.bin');
      final expected = List<int>.generate(512 * 1024, (index) => index % 251);
      await source.writeAsBytes(expected);
      var received = 0;
      client.close();
      client = WebDavProtocolClient(
        endpoint: await endpointFor(server),
        credentials: const WebDavCredentials(username: '', password: ''),
        client: _StreamingClient((request) async {
          await for (final chunk in request.finalize()) {
            received += chunk.length;
            await Future<void>.delayed(const Duration(milliseconds: 30));
          }
          return http.StreamedResponse(
            const Stream<List<int>>.empty(),
            HttpStatus.created,
            request: request,
          );
        }),
        timeout: const Duration(milliseconds: 20),
      );
      final elapsed = Stopwatch()..start();

      await client.uploadFile(
        path: 'slow-source.bin',
        file: source,
        maxBytes: expected.length,
        createParents: false,
      );

      elapsed.stop();
      expect(elapsed.elapsed, greaterThan(const Duration(milliseconds: 20)));
      expect(received, expected.length);
    },
  );

  test(
    'upload source failure observes the in-flight response future',
    () async {
      client.close();
      client = WebDavProtocolClient(
        endpoint: await endpointFor(server),
        credentials: const WebDavCredentials(username: '', password: ''),
        client: _StreamingClient((request) async {
          try {
            await request.finalize().drain<void>();
          } catch (_) {}
          await Future<void>.delayed(Duration.zero);
          throw StateError('orphaned response failure');
        }),
        timeout: const Duration(seconds: 1),
      );

      await expectLater(
        client.uploadFile(
          path: 'vanishing-source.bin',
          file: const _ThrowOnReadFile('vanishing-source.bin'),
          maxBytes: 1024,
          createParents: false,
        ),
        throwsA(isA<FileSystemException>()),
      );
      await Future<void>.delayed(Duration.zero);
    },
  );

  test('GET APIs enforce declared and streamed byte limits', () async {
    var requestCount = 0;
    handler = (request) async {
      requestCount++;
      request.response.statusCode = HttpStatus.ok;
      if (request.uri.path.endsWith('declared')) {
        request.response.contentLength = 100;
        request.response.add(List<int>.filled(100, 1));
      } else {
        request.response.headers.chunkedTransferEncoding = true;
        request.response.add(List<int>.filled(20, 2));
        request.response.add(List<int>.filled(20, 3));
      }
      await request.response.close();
    };

    await expectLater(
      client.getBytes(path: 'declared', maxBytes: 10),
      throwsA(isA<WebDavException>()),
    );
    await expectLater(
      client.getBytes(path: 'chunked', maxBytes: 30),
      throwsA(isA<WebDavException>()),
    );

    final destination = File('${tempDirectory.path}/partial.bin');
    await expectLater(
      client.downloadToFile(
        path: 'chunked',
        destination: destination,
        maxBytes: 30,
      ),
      throwsA(isA<WebDavException>()),
    );
    expect(await destination.exists(), isFalse);
    expect(requestCount, 3);
  });

  test(
    'downloadToFile writes a bounded response without buffering it',
    () async {
      final expected = List<int>.generate(16384, (index) => index % 239);
      handler = (request) async {
        request.response
          ..statusCode = HttpStatus.ok
          ..contentLength = expected.length
          ..add(expected);
        await request.response.close();
      };
      final destination = File('${tempDirectory.path}/nested/backup.json');
      final result = await client.downloadToFile(
        path: 'backup.json',
        destination: destination,
        maxBytes: expected.length,
      );
      expect(result.bytesWritten, expected.length);
      expect(await destination.readAsBytes(), expected);
    },
  );

  test('exists file fallback preserves its non-collection URI', () async {
    final seen = <String>[];
    handler = (request) async {
      seen.add(
        '${request.method} ${request.uri.path}:'
        '${request.headers.value('Depth')}',
      );
      if (request.method == 'HEAD') {
        request.response.statusCode = HttpStatus.methodNotAllowed;
      } else {
        request.response
          ..statusCode = HttpStatus.multiStatus
          ..headers.set(HttpHeaders.etagHeader, '"file-etag"')
          ..headers.set(
            HttpHeaders.dateHeader,
            'Tue, 01 Sep 2026 12:00:00 GMT',
          );
      }
      await request.drain<void>();
      await request.response.close();
    };

    final result = await client.exists(path: 'backup.json');
    expect(result.exists, isTrue);
    expect(result.metadata.statusCode, HttpStatus.multiStatus);
    expect(result.metadata.etag, '"file-etag"');
    expect(result.metadata.serverDate, DateTime.utc(2026, 9, 1, 12));
    expect(seen, <String>[
      'HEAD /dav/backup.json:null',
      'PROPFIND /dav/backup.json:0',
    ]);
  });

  test('oversized successful PROPFIND still proves existence', () async {
    client.close();
    final oversizedBody = List<int>.filled(
      WebDavProtocolClient.defaultSmallDocumentLimit + 1,
      120,
    );
    final mockClient = MockClient((request) async {
      if (request.method == 'HEAD') {
        return http.Response('', HttpStatus.methodNotAllowed, request: request);
      }
      return http.Response.bytes(
        oversizedBody,
        HttpStatus.multiStatus,
        request: request,
      );
    });
    addTearDown(mockClient.close);
    client = WebDavProtocolClient(
      endpoint: Uri.parse('https://example.test/dav'),
      credentials: const WebDavCredentials(
        username: 'alice',
        password: 'secret',
      ),
      client: mockClient,
    );

    final result = await client.exists(path: 'oversized.xml');

    expect(result.exists, isTrue);
    expect(result.metadata.statusCode, HttpStatus.multiStatus);
    expect(result.metadata.etag, isNull);
  });

  test(
    'exists is false only for 404 and preserves authorization failures',
    () async {
      handler = (request) async {
        request.response.statusCode = request.uri.path.endsWith('missing')
            ? HttpStatus.notFound
            : HttpStatus.unauthorized;
        await request.response.close();
      };
      expect((await client.exists(path: 'missing')).exists, isFalse);
      await expectLater(
        client.exists(path: 'private'),
        throwsA(
          isA<WebDavException>().having(
            (error) => error.kind,
            'kind',
            WebDavErrorKind.authentication,
          ),
        ),
      );
    },
  );

  test('same-origin 307 replays PUT once with its body intact', () async {
    var finalBody = '';
    var finalAuthorization = '';
    handler = (request) async {
      if (request.uri.path.endsWith('/start')) {
        await request.drain<void>();
        request.response
          ..statusCode = HttpStatus.temporaryRedirect
          ..headers.set(HttpHeaders.locationHeader, '/dav/final');
      } else {
        finalBody = await utf8.decoder.bind(request).join();
        finalAuthorization =
            request.headers.value(HttpHeaders.authorizationHeader) ?? '';
        request.response.statusCode = HttpStatus.created;
      }
      await request.response.close();
    };

    await client.putBytes(
      path: 'start',
      bytes: utf8.encode('redirected'),
      maxBytes: 100,
      createParents: false,
    );
    expect(finalBody, 'redirected');
    expect(finalAuthorization, startsWith('Basic '));
  });

  test('GET follows an uncommon same-origin 3xx exactly once', () async {
    var requests = 0;
    handler = (request) async {
      requests++;
      if (requests == 1) {
        request.response
          ..statusCode = HttpStatus.multipleChoices
          ..headers.set(HttpHeaders.locationHeader, '/dav/final');
      } else {
        request.response
          ..statusCode = HttpStatus.ok
          ..write('final');
      }
      await request.response.close();
    };

    final result = await client.getBytes(path: 'start', maxBytes: 100);
    expect(utf8.decode(result.bytes), 'final');
    expect(requests, 2);
  });

  test('never sends credentials across an origin redirect', () async {
    final other = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var otherRequests = 0;
    other.listen((request) async {
      otherRequests++;
      await request.drain<void>();
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
    });
    addTearDown(() => other.close(force: true));
    handler = (request) async {
      request.response
        ..statusCode = HttpStatus.temporaryRedirect
        ..headers.set(
          HttpHeaders.locationHeader,
          'http://${other.address.address}:${other.port}/stolen',
        );
      await request.response.close();
    };

    await expectLater(
      client.getBytes(path: 'redirect', maxBytes: 100),
      throwsA(
        isA<WebDavException>().having(
          (error) => error.kind,
          'kind',
          WebDavErrorKind.unsafeRedirect,
        ),
      ),
    );
    expect(otherRequests, 0);
  });

  test('rejects a second redirect hop', () async {
    var requests = 0;
    handler = (request) async {
      requests++;
      await request.drain<void>();
      request.response
        ..statusCode = HttpStatus.temporaryRedirect
        ..headers.set(
          HttpHeaders.locationHeader,
          requests == 1 ? '/dav/second' : '/dav/third',
        );
      await request.response.close();
    };

    await expectLater(
      client.getBytes(path: 'first', maxBytes: 100),
      throwsA(
        isA<WebDavException>().having(
          (error) => error.kind,
          'kind',
          WebDavErrorKind.unsafeRedirect,
        ),
      ),
    );
    expect(requests, 2);
  });

  test(
    'PROPFIND rejects 301 because its method and body are ambiguous',
    () async {
      handler = (request) async {
        await request.drain<void>();
        request.response
          ..statusCode = HttpStatus.movedPermanently
          ..headers.set(HttpHeaders.locationHeader, '/dav/canonical/');
        await request.response.close();
      };

      await expectLater(
        client.propfind(
          path: '',
          depth: 1,
          body: '<propfind/>',
          collection: true,
        ),
        throwsA(
          isA<WebDavException>().having(
            (error) => error.kind,
            'kind',
            WebDavErrorKind.unsafeRedirect,
          ),
        ),
      );
    },
  );

  test('maps important HTTP failures to typed error categories', () async {
    const expected = <int, WebDavErrorKind>{
      HttpStatus.forbidden: WebDavErrorKind.authentication,
      HttpStatus.notFound: WebDavErrorKind.notFound,
      HttpStatus.conflict: WebDavErrorKind.conflict,
      HttpStatus.preconditionFailed: WebDavErrorKind.preconditionFailed,
      HttpStatus.insufficientStorage: WebDavErrorKind.quota,
      HttpStatus.tooManyRequests: WebDavErrorKind.transient,
      HttpStatus.serviceUnavailable: WebDavErrorKind.transient,
    };
    var status = HttpStatus.ok;
    handler = (request) async {
      request.response.statusCode = status;
      await request.response.close();
    };

    for (final entry in expected.entries) {
      status = entry.key;
      await expectLater(
        client.getBytes(path: 'failure', maxBytes: 100),
        throwsA(
          isA<WebDavException>().having(
            (error) => error.kind,
            'kind for ${entry.key}',
            entry.value,
          ),
        ),
      );
    }
  });

  test('profile facade maps malformed PROPFIND XML distinctly', () async {
    handler = (request) async {
      await request.drain<void>();
      request.response
        ..statusCode = HttpStatus.multiStatus
        ..headers.contentType = ContentType('application', 'xml')
        ..write('<multistatus><broken>');
      await request.response.close();
    };
    final config = WebDavConfig(
      id: 'malformed',
      name: 'Malformed',
      baseUrl: (await endpointFor(server)).toString(),
      username: 'alice',
      password: 'secret',
    );

    await expectLater(
      WebDavService.testConnection(config),
      throwsA(
        isA<WebDavException>().having(
          (error) => error.kind,
          'kind',
          WebDavErrorKind.malformedResponse,
        ),
      ),
    );
  });

  test('profile facade preserves a valid DAV directory listing', () async {
    String? requestedPath;
    handler = (request) async {
      requestedPath = request.uri.path;
      await request.drain<void>();
      request.response
        ..statusCode = HttpStatus.multiStatus
        ..headers.contentType = ContentType('application', 'xml')
        ..write('''<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
  <D:response><D:href>/dav/</D:href><D:propstat><D:prop>
    <D:displayname>dav</D:displayname><D:resourcetype><D:collection/></D:resourcetype>
  </D:prop></D:propstat></D:response>
  <D:response><D:href>/dav/Folder%20One/</D:href><D:propstat><D:prop>
    <D:displayname>Folder One</D:displayname><D:resourcetype><D:collection/></D:resourcetype>
  </D:prop></D:propstat></D:response>
  <D:response><D:href>/dav/backup.json</D:href><D:propstat><D:prop>
    <D:displayname>backup.json</D:displayname><D:getcontentlength>14</D:getcontentlength>
    <D:getcontenttype>application/json</D:getcontenttype><D:resourcetype/>
  </D:prop></D:propstat></D:response>
</D:multistatus>''');
      await request.response.close();
    };
    final config = WebDavConfig(
      id: 'valid',
      name: 'Valid',
      baseUrl: (await endpointFor(server)).toString(),
      username: 'alice',
      password: 'secret',
    );

    final items = await WebDavService.listDirectory(config: config, path: '');
    expect(requestedPath, '/dav/');
    expect(items, hasLength(2));
    expect(items.first.name, 'Folder One');
    expect(items.first.path, 'Folder One/');
    expect(items.first.isDirectory, isTrue);
    expect(items.last.name, 'backup.json');
    expect(items.last.path, 'backup.json');
    expect(items.last.sizeBytes, 14);
  });

  for (final download in [false, true]) {
    test(
      'oversized ${download ? "file" : "bytes"} response cancels without draining',
      () async {
        client.close();
        var cancelled = false;
        final body = StreamController<List<int>>(
          onCancel: () => cancelled = true,
        );
        addTearDown(body.close);
        client = WebDavProtocolClient(
          endpoint: await endpointFor(server),
          credentials: const WebDavCredentials(username: '', password: ''),
          client: _StreamingClient(
            (request) async => http.StreamedResponse(
              body.stream,
              200,
              contentLength: 1000000000,
              request: request,
            ),
          ),
          timeout: const Duration(seconds: 5),
        );
        final future = download
            ? client.downloadToFile(
                path: 'large',
                destination: File('${tempDirectory.path}/large'),
                maxBytes: 16,
              )
            : client.getBytes(path: 'large', maxBytes: 16);
        await expectLater(
          future.timeout(const Duration(seconds: 1)),
          throwsA(
            isA<WebDavException>().having(
              (e) => e.kind,
              'kind',
              WebDavErrorKind.invalidRequest,
            ),
          ),
        );
        expect(cancelled, isTrue);
      },
    );
  }

  for (final status in [200, 503]) {
    test(
      'trickling body has a total deadline and retains status $status',
      () async {
        client.close();
        var cancelled = false;
        final body = StreamController<List<int>>(
          onCancel: () => cancelled = true,
        );
        final ticker = Timer.periodic(
          const Duration(milliseconds: 5),
          (_) => body.add([1]),
        );
        addTearDown(() async {
          ticker.cancel();
          await body.close();
        });
        client = WebDavProtocolClient(
          endpoint: await endpointFor(server),
          credentials: const WebDavCredentials(username: '', password: ''),
          client: _StreamingClient(
            (request) async =>
                http.StreamedResponse(body.stream, status, request: request),
          ),
          timeout: const Duration(milliseconds: 40),
        );
        await expectLater(
          client
              .getBytes(path: 'trickle', maxBytes: 1024)
              .timeout(const Duration(seconds: 2)),
          throwsA(
            isA<WebDavException>()
                .having((e) => e.kind, 'kind', WebDavErrorKind.timeout)
                .having((e) => e.statusCode, 'status', status),
          ),
        );
        expect(cancelled, isTrue);
      },
    );
  }

  test('metadata response drains at most its bounded allowance', () async {
    client.close();
    var cancelled = false;
    final body = StreamController<List<int>>(onCancel: () => cancelled = true);
    addTearDown(body.close);
    body.add(List<int>.filled(65537, 0));
    client = WebDavProtocolClient(
      endpoint: await endpointFor(server),
      credentials: const WebDavCredentials(username: '', password: ''),
      client: _StreamingClient(
        (request) async =>
            http.StreamedResponse(body.stream, 204, request: request),
      ),
    );
    await client.deletePath(path: 'object').timeout(const Duration(seconds: 1));
    expect(cancelled, isTrue);
  });

  test('maps a stalled response body to timeout', () async {
    client.close();
    final controller = StreamController<List<int>>();
    addTearDown(controller.close);
    controller.add(const <int>[1]);
    client = WebDavProtocolClient(
      endpoint: await endpointFor(server),
      credentials: const WebDavCredentials(username: '', password: ''),
      client: _StreamingClient(
        (request) async => http.StreamedResponse(
          controller.stream,
          HttpStatus.ok,
          request: request,
        ),
      ),
      timeout: const Duration(milliseconds: 20),
    );

    await expectLater(
      client.getBytes(path: 'stalled', maxBytes: 100),
      throwsA(
        isA<WebDavException>()
            .having((error) => error.kind, 'kind', WebDavErrorKind.timeout)
            .having((error) => error.statusCode, 'status', HttpStatus.ok),
      ),
    );
  });

  for (final scenario in <({String name, Object error, WebDavErrorKind kind})>[
    (
      name: 'timeout',
      error: TimeoutException('response timed out'),
      kind: WebDavErrorKind.timeout,
    ),
    (
      name: 'TLS handshake',
      error: const HandshakeException('response handshake failed'),
      kind: WebDavErrorKind.tls,
    ),
    (
      name: 'socket',
      error: const SocketException('response interrupted'),
      kind: WebDavErrorKind.network,
    ),
    (
      name: 'HTTP client',
      error: http.ClientException('response interrupted'),
      kind: WebDavErrorKind.network,
    ),
    (
      name: 'decoder-style format',
      error: const FormatException('invalid compressed response'),
      kind: WebDavErrorKind.network,
    ),
    (
      name: 'generic',
      error: Exception('response interrupted'),
      kind: WebDavErrorKind.network,
    ),
  ]) {
    test(
      'successful PUT preserves status for ${scenario.name} body failure',
      () async {
        client.close();
        client = WebDavProtocolClient(
          endpoint: await endpointFor(server),
          credentials: const WebDavCredentials(username: '', password: ''),
          client: _StreamingClient(
            (request) async => http.StreamedResponse(
              Stream<List<int>>.error(scenario.error),
              HttpStatus.noContent,
              request: request,
            ),
          ),
        );
        final requestUri = client.uriForPath('status-preserved');

        await expectLater(
          client.putBytes(
            path: 'status-preserved',
            bytes: const <int>[1],
            maxBytes: 1,
            createParents: false,
          ),
          throwsA(
            isA<WebDavException>()
                .having((error) => error.kind, 'kind', scenario.kind)
                .having(
                  (error) => error.statusCode,
                  'status',
                  HttpStatus.noContent,
                )
                .having((error) => error.uri, 'uri', requestUri)
                .having((error) => error.cause, 'cause', scenario.error),
          ),
        );
      },
    );
  }

  test('response body WebDavException is rethrown as-is', () async {
    const bodyError = WebDavException(
      kind: WebDavErrorKind.malformedResponse,
      message: 'invalid response body',
      statusCode: HttpStatus.partialContent,
    );
    client.close();
    client = WebDavProtocolClient(
      endpoint: await endpointFor(server),
      credentials: const WebDavCredentials(username: '', password: ''),
      client: _StreamingClient(
        (request) async => http.StreamedResponse(
          Stream<List<int>>.error(bodyError),
          HttpStatus.partialContent,
          request: request,
        ),
      ),
    );

    await expectLater(
      client.getBytes(path: 'invalid', maxBytes: 100),
      throwsA(same(bodyError)),
    );
  });

  test(
    'inner body WebDavException without a status inherits the response status',
    () async {
      const statuslessBodyError = WebDavException(
        kind: WebDavErrorKind.network,
        message: 'inner body failure without a status',
      );
      client.close();
      client = WebDavProtocolClient(
        endpoint: await endpointFor(server),
        credentials: const WebDavCredentials(username: '', password: ''),
        client: _StreamingClient(
          (request) async => http.StreamedResponse(
            Stream<List<int>>.error(statuslessBodyError),
            HttpStatus.ok,
            request: request,
          ),
        ),
      );

      await expectLater(
        client.getBytes(path: 'invalid', maxBytes: 100),
        throwsA(
          isA<WebDavException>()
              .having((error) => error.statusCode, 'status', HttpStatus.ok)
              .having((error) => error.kind, 'kind', WebDavErrorKind.network)
              .having(
                (error) => error.cause,
                'cause',
                same(statuslessBodyError),
              ),
        ),
      );
    },
  );

  test(
    'inner body WebDavException with a mismatched status is re-stamped',
    () async {
      // A 412 riding on a 201 response body must never mask the real 201:
      // the exit carries the response status so a conflicting-PUT 2xx cannot
      // be laundered into a "conflict enforced" signal.
      const mismatchedBodyError = WebDavException(
        kind: WebDavErrorKind.preconditionFailed,
        message: 'inner precondition on a created response',
        statusCode: HttpStatus.preconditionFailed,
      );
      client.close();
      client = WebDavProtocolClient(
        endpoint: await endpointFor(server),
        credentials: const WebDavCredentials(username: '', password: ''),
        client: _StreamingClient(
          (request) async => http.StreamedResponse(
            Stream<List<int>>.error(mismatchedBodyError),
            HttpStatus.created,
            request: request,
          ),
        ),
      );

      await expectLater(
        client.getBytes(path: 'invalid', maxBytes: 100),
        throwsA(
          isA<WebDavException>()
              .having((error) => error.statusCode, 'status', HttpStatus.created)
              .having(
                (error) => error.cause,
                'cause',
                same(mismatchedBodyError),
              ),
        ),
      );
    },
  );

  test(
    'maps timeout, network, and TLS transport failures distinctly',
    () async {
      Future<void> expectKind(
        Future<http.Response> Function() handler,
        WebDavErrorKind kind, {
        Duration timeout = const Duration(seconds: 1),
      }) async {
        client.close();
        client = WebDavProtocolClient(
          endpoint: await endpointFor(server),
          credentials: const WebDavCredentials(username: '', password: ''),
          client: MockClient((_) => handler()),
          timeout: timeout,
        );
        await expectLater(
          client.getBytes(path: 'failure', maxBytes: 100),
          throwsA(
            isA<WebDavException>()
                .having((error) => error.kind, 'kind', kind)
                .having((error) => error.statusCode, 'status', isNull),
          ),
        );
      }

      await expectKind(
        () => Completer<http.Response>().future,
        WebDavErrorKind.timeout,
        timeout: const Duration(milliseconds: 10),
      );
      await expectKind(
        () => Future<http.Response>.error(
          const SocketException('network unavailable'),
        ),
        WebDavErrorKind.network,
      );
      await expectKind(
        () => Future<http.Response>.error(
          const HandshakeException('certificate rejected'),
        ),
        WebDavErrorKind.tls,
      );
    },
  );
}

final class _StreamingClient extends http.BaseClient {
  _StreamingClient(this.handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request)
  handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);
}

final class _ThrowOnReadFile implements File {
  const _ThrowOnReadFile(this.path);

  @override
  final String path;

  @override
  Future<int> length() async => 1024;

  @override
  Stream<List<int>> openRead([int? start, int? end]) =>
      const _ThrowOnListenStream();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _ThrowOnListenStream extends Stream<List<int>> {
  const _ThrowOnListenStream();

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    throw const FileSystemException('staged upload became unreadable');
  }
}
