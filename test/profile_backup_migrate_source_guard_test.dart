import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File(
    'lib/screens/settings/profile_backup_flows.dart',
  ).readAsStringSync();

  test(
    'local backup and restore retain their original transport entry points',
    () {
      // Both transports use file-backed archives; WebDAV wraps its archive
      // in authenticated binary encryption before uploading.
      expect(source, contains('await _createLocalArchiveBackup();'));
      expect(source, contains('_createWebDavProfileBackupUnchecked()'));
      expect(source, contains('saveBackupFile('));
      expect(source, contains('DownloadService.instance.saveGeneratedFile('));
      expect(
        source,
        contains('DownloadService.instance.saveGeneratedFileFromPath('),
      );
      expect(source, contains('source: _ProfileBackupSource.localFile'));
      expect(source, contains('FilePicker.platform.pickFiles('));
      expect(source, contains('LocalBackupZip.looksLikeArchive(File(path))'));
      expect(source, contains('return await _restoreLocalArchive(path);'));
      expect(
        source,
        contains('return await _restoreProfileBackupFromPath(path);'),
      );
    },
  );

  test(
    'local and WebDAV restore converge before package validation/commit',
    () {
      expect(
        RegExp(r'_restoreLocalArchive\(').allMatches(source).length,
        greaterThanOrEqualTo(3),
      );
      expect(source, contains('PortableProfilePackage.probeFile(path)'));
      expect(source, contains('coordinator.restoreDeviceGraph('));
      expect(source, contains('coordinator.restore('));
    },
  );

  test('remote staging is always private, bounded, and finally-cleaned', () {
    expect(source, contains('getTemporaryDirectory()'));
    expect(source, contains("root.createTemp('debrify-migrate-\$purpose-')"));
    expect(
      RegExp(r'_deletePrivateStagingDirectory\(').allMatches(source).length,
      greaterThanOrEqualTo(2),
    );
    expect(source, contains('TransferIo.maxFileBytes'));
    expect(source, contains('StreamingEncryptedFile.looksLike'));
    expect(source, contains('WebDavBackupArchive.decrypt'));
    expect(source, contains('LocalBackupScratch.delete(staging)'));
  });

  test('WebDAV migration binds backup permission and resource authority', () {
    expect(
      RegExp(
        r'feature: ProfileFeature\.backupRestore',
      ).allMatches(source).length,
      greaterThanOrEqualTo(3),
    );
    expect(source, contains('_captureWebDavAuthorization('));
    expect(source, contains('resourceAuthorizationRevision:'));
    expect(source, contains('runIfCurrentAsOutbound'));
    expect(source, contains('currentOutboundBarrier'));
  });
}
