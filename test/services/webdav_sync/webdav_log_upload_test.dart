import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:debrify/services/diagnostic_log.dart';
import 'package:debrify/services/webdav_protocol_client.dart';
import 'package:debrify/services/webdav_sync/webdav_log_upload.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_models.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';

DiagnosticLogExport snapshot([String contents = '{"event":"test"}\n']) =>
    DiagnosticLogExport(
      fileName: 'unused.jsonl',
      bytes: Uint8List.fromList(utf8.encode(contents)),
      entryCount: 1,
      windowStart: DateTime.utc(2026),
      windowEnd: DateTime.utc(2026, 1, 2),
    );
WebDavLogTarget target(String device) => WebDavLogTarget(
  key: 'binding:$device',
  deviceId: device,
  revision: 'credentials-v1',
  location: WebDavSyncFolderLocation(
    endpoint: 'https://example.invalid/dav',
    folderPath: 'Debrify',
    serverName: 'Test',
  ),
  credentials: const WebDavCredentials(username: 'user', password: 'private'),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late WebDavLogTarget? current;
  late String? optIn;
  late List<http.Request> requests;
  late Future<DiagnosticLogExport> Function() exporter;
  late WebDavLogUpload service;
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Debrify',
      packageName: 'test',
      version: '1.0',
      buildNumber: '2',
      buildSignature: '',
    );
    current = target('phone');
    optIn = current!.key;
    requests = [];
    exporter = () async => snapshot();
    service = WebDavLogUpload(
      target: () async => current,
      readOptIn: () async => optIn,
      writeOptIn: (key) async {
        optIn = key;
      },
      export: () => exporter(),
      clientFactory: (target) => WebDavProtocolClient(
        endpoint: target.location.endpoint,
        credentials: target.credentials,
        client: MockClient((request) async {
          requests.add(request);
          return http.Response('', request.method == 'MKCOL' ? 201 : 204);
        }),
      ),
    );
    addTearDown(service.dispose);
  });

  test('off by default means no export and no remote requests', () async {
    optIn = null;
    exporter = () => throw StateError('Must not export');
    expect(await service.upload(), WebDavLogUploadResult.unavailable);
    expect(requests, isEmpty);
  });

  test('success replaces one device file beside the sync folder', () async {
    expect(await service.upload(), WebDavLogUploadResult.uploaded);
    expect(await service.upload(), WebDavLogUploadResult.uploaded);
    final puts = requests.where((request) => request.method == 'PUT').toList();
    expect(puts, hasLength(2));
    expect(puts.map((request) => request.url.path).toSet(), {
      '/dav/Debrify/logs/device-phone.jsonl',
    });
    expect(puts.first.body, contains('"appVersion":"1.0+2"'));
    expect(puts.first.body, isNot(contains('private')));
    expect(service.lastUploaded, isNotNull);
  });

  test('other device/account never inherits consent', () async {
    current = target('mac');
    expect(await service.isEnabled(), isFalse);
    expect(await service.upload(), WebDavLogUploadResult.unavailable);
    expect(requests, isEmpty);
  });

  test('account changes during export prevent all network writes', () async {
    final pending = Completer<DiagnosticLogExport>();
    final entered = Completer<void>();
    exporter = () {
      entered.complete();
      return pending.future;
    };
    final uploading = service.upload();
    await entered.future;
    current = target('mac');
    pending.complete(snapshot());
    expect(await uploading, WebDavLogUploadResult.failed);
    expect(requests, isEmpty);
  });

  test('disable cancels an export and concurrent uploads coalesce', () async {
    final pending = Completer<DiagnosticLogExport>();
    final entered = Completer<void>();
    exporter = () {
      entered.complete();
      return pending.future;
    };
    final uploading = service.upload();
    await entered.future;
    expect(await service.upload(), WebDavLogUploadResult.busy);
    await service.setEnabled(false);
    pending.complete(snapshot());
    expect(await uploading, WebDavLogUploadResult.failed);
    expect(await service.isEnabled(), isFalse);
    expect(requests, isEmpty);
  });

  test(
    'backgrounding prevents late writes and resumes on next attempt',
    () async {
      service.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(await service.upload(), WebDavLogUploadResult.unavailable);
      service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(await service.upload(), WebDavLogUploadResult.uploaded);
    },
  );

  test('deadline cancels late exports and permits a later retry', () async {
    final pending = Completer<DiagnosticLogExport>();
    final entered = Completer<void>();
    exporter = () {
      entered.complete();
      return pending.future;
    };
    final timed = WebDavLogUpload(
      target: service.target,
      readOptIn: service.readOptIn,
      writeOptIn: service.writeOptIn,
      export: () => exporter(),
      clientFactory: service.clientFactory,
      deadline: const Duration(milliseconds: 50),
    );
    addTearDown(timed.dispose);
    final uploading = timed.upload();
    await entered.future;
    expect(await uploading, WebDavLogUploadResult.failed);
    pending.complete(snapshot());
    await Future<void>.delayed(Duration.zero);
    expect(requests, isEmpty);
    exporter = () async => snapshot();
    expect(await timed.upload(), WebDavLogUploadResult.uploaded);
  });

  test('bounded snapshot keeps complete newest JSONL records', () {
    final lines = List.generate(
      30000,
      (i) => jsonEncode({'index': i, 'data': 'x' * 100}),
    );
    final bytes = WebDavLogUpload.snapshotBytes(
      snapshot('${lines.join('\n')}\n'),
      'phone',
    );
    expect(bytes.length, lessThanOrEqualTo(WebDavLogUpload.maxUploadBytes));
    final records = const LineSplitter()
        .convert(utf8.decode(bytes))
        .map(jsonDecode)
        .toList();
    expect(records.first['truncated'], isTrue);
    expect(records.last['index'], 29999);
    expect(records[1]['index'], greaterThan(0));
  });
}
