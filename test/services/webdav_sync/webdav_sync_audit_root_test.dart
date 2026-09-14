import 'dart:io';
import 'dart:typed_data';

import 'package:debrify/services/webdav_sync/webdav_sync_codec.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/src/webdav_sync_audit_root.dart';

void main() {
  late Directory directory;
  late Uint8List marker;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('audit-root-test');
    marker = await WebDavSyncCodec().sealRoot(
      passphrase: 'authority-secret',
      circleId: 'audit-circle',
      createdAt: DateTime.utc(2026),
      memoryKiB: 8,
      iterations: 1,
    );
  });
  tearDown(() => directory.delete(recursive: true));
  test(
    'current authority supplies its marker and key, ignoring legacy bytes',
    () async {
      await File('${directory.path}/circle.authority').writeAsBytes(
        WebDavSyncAuthorityFile(
          markerBytes: marker,
          syncPassphrase: 'authority-secret',
        ).encode(),
      );
      await File('${directory.path}/circle.json.enc').writeAsString('obsolete');
      final result = await readAuditRoot(directory, 'old-key');
      final opened = await WebDavSyncCodec().openRoot(
        result.markerBytes,
        result.passphrase,
      );
      expect(opened.document.circleId, 'audit-circle');
    },
  );
  test(
    'missing authority falls back to legacy root with supplied key',
    () async {
      await File('${directory.path}/circle.json.enc').writeAsBytes(marker);
      final result = await readAuditRoot(directory, 'authority-secret');
      expect(result.markerBytes, marker);
      expect(result.passphrase, 'authority-secret');
    },
  );
  test(
    'malformed current authority cannot fall back to valid legacy root',
    () async {
      await File('${directory.path}/circle.authority').writeAsString('broken');
      await File('${directory.path}/circle.json.enc').writeAsBytes(marker);
      await expectLater(
        readAuditRoot(directory, 'authority-secret'),
        throwsA(anything),
      );
    },
  );
  test(
    'authority read failure cannot fall back to valid legacy root',
    () async {
      await Directory('${directory.path}/circle.authority').create();
      await File('${directory.path}/circle.json.enc').writeAsBytes(marker);
      await expectLater(
        readAuditRoot(directory, 'authority-secret'),
        throwsA(isA<FileSystemException>()),
      );
    },
  );
}
