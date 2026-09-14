import 'dart:io';

import 'package:debrify/models/webdav_item.dart';
import 'package:debrify/services/webdav_backup_transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;
  late Directory scratch;
  late File source;
  late Future<void> Function(HttpRequest request) handler;
  late WebDavConfig config;

  setUp(() async {
    scratch = await Directory.systemTemp.createTemp(
      'debrify_webdav_backup_transport_',
    );
    source = File('${scratch.path}/source.json');
    await source.writeAsString('{"backup":true}', flush: true);
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
    config = WebDavConfig(
      id: 'test',
      name: 'Test DAV',
      baseUrl: 'http://${server.address.address}:${server.port}/dav',
      username: 'alice',
      password: 'secret',
    );
  });

  tearDown(() async {
    await server.close(force: true);
    if (await scratch.exists()) await scratch.delete(recursive: true);
  });

  test(
    'retries a create-only collision and verifies streamed read-back',
    () async {
      final suffixes = <String>['collision', 'created', 'readback'];
      final seenPaths = <String>[];
      var puts = 0;
      var beforeSendCount = 0;
      List<int> stored = const <int>[];
      handler = (request) async {
        seenPaths.add('${request.method} ${request.uri.path}');
        if (request.method == 'PUT') {
          puts++;
          expect(request.headers.value(HttpHeaders.ifNoneMatchHeader), '*');
          final bytes = await request.fold<List<int>>(
            <int>[],
            (value, chunk) => value..addAll(chunk),
          );
          if (puts == 1) {
            request.response.statusCode = HttpStatus.preconditionFailed;
          } else {
            stored = bytes;
            request.response.statusCode = HttpStatus.created;
          }
        } else if (request.method == 'GET') {
          request.response
            ..statusCode = HttpStatus.ok
            ..contentLength = stored.length
            ..add(stored);
        }
        await request.response.close();
      };

      final result =
          await WebDavBackupTransport(
            now: () => DateTime.utc(2026, 9, 1, 12),
            randomSuffix: () => suffixes.removeAt(0),
          ).uploadVerified(
            config: config,
            directoryPath: 'backups/',
            stagedFile: source,
            scratchDirectory: scratch,
            fileNamePrefix: 'debrify-profile',
            beforeSend: () async => beforeSendCount++,
          );

      expect(puts, 2);
      expect(result.fileName, contains('2026-09-01T12-00-00-000Z-created'));
      expect(result.remotePath, 'backups/${result.fileName}');
      expect(beforeSendCount, 3);
      expect(seenPaths.last, 'GET /dav/${result.remotePath}');
      expect(
        await scratch
            .list()
            .where((entry) => entry.path.contains('webdav-readback'))
            .isEmpty,
        isTrue,
      );
    },
  );

  test('verification mismatch deletes a proven creation', () async {
    var deleteCount = 0;
    handler = (request) async {
      if (request.method == 'PUT') {
        await request.drain<void>();
        request.response.statusCode = HttpStatus.created;
      } else if (request.method == 'GET') {
        final corrupt = '{"backup":false}'.codeUnits;
        request.response
          ..statusCode = HttpStatus.ok
          ..contentLength = corrupt.length
          ..add(corrupt);
      } else if (request.method == 'DELETE') {
        deleteCount++;
        request.response.statusCode = HttpStatus.noContent;
      }
      await request.response.close();
    };

    await expectLater(
      WebDavBackupTransport(
        now: () => DateTime.utc(2026, 9, 1),
        randomSuffix: () => 'fixed',
      ).uploadVerified(
        config: config,
        directoryPath: '',
        stagedFile: source,
        scratchDirectory: scratch,
        fileNamePrefix: 'debrify-profile',
      ),
      throwsA(isA<WebDavBackupVerificationException>()),
    );
    expect(deleteCount, 1);
    expect(
      await scratch
          .list()
          .where((entry) => entry.path.contains('webdav-readback'))
          .isEmpty,
      isTrue,
    );
  });

  test('transient read-back failure leaves a proven creation intact', () async {
    var deleteCount = 0;
    handler = (request) async {
      if (request.method == 'PUT') {
        await request.drain<void>();
        request.response.statusCode = HttpStatus.created;
      } else if (request.method == 'GET') {
        request.response.statusCode = HttpStatus.serviceUnavailable;
      } else if (request.method == 'DELETE') {
        deleteCount++;
        request.response.statusCode = HttpStatus.noContent;
      }
      await request.response.close();
    };

    await expectLater(
      WebDavBackupTransport(
        now: () => DateTime.utc(2026, 9, 1),
        randomSuffix: () => 'fixed',
      ).uploadVerified(
        config: config,
        directoryPath: '',
        stagedFile: source,
        scratchDirectory: scratch,
        fileNamePrefix: 'debrify-profile',
      ),
      throwsA(
        isA<WebDavBackupVerificationException>().having(
          (error) => error.message,
          'message',
          allOf(contains('was uploaded'), contains('delete it manually')),
        ),
      ),
    );
    expect(deleteCount, 0);
  });

  test('204 never passes as a create-only upload or deletes data', () async {
    var getCount = 0;
    var deleteCount = 0;
    handler = (request) async {
      if (request.method == 'PUT') {
        await request.drain<void>();
        request.response.statusCode = HttpStatus.noContent;
      } else if (request.method == 'GET') {
        getCount++;
        request.response
          ..statusCode = HttpStatus.ok
          ..add(await source.readAsBytes());
      } else if (request.method == 'DELETE') {
        deleteCount++;
        request.response.statusCode = HttpStatus.noContent;
      }
      await request.response.close();
    };

    await expectLater(
      WebDavBackupTransport(
        now: () => DateTime.utc(2026, 9, 1),
        randomSuffix: () => 'fixed',
      ).uploadVerified(
        config: config,
        directoryPath: '',
        stagedFile: source,
        scratchDirectory: scratch,
        fileNamePrefix: 'debrify-profile',
      ),
      throwsA(isA<WebDavBackupVerificationException>()),
    );
    expect(getCount, 0);
    expect(deleteCount, 0);
  });
}
