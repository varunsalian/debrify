import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File(
    'lib/screens/settings/profile_backup_flows.dart',
  ).readAsStringSync();

  test(
    'local backup and restore retain their original transport entry points',
    () {
      // Local files use the streamed .debrify archive; WebDAV keeps the
      // encrypted JSON package. Neither transport borrows the other's path.
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
        RegExp(r'_restoreProfileBackupFromPath\(').allMatches(source).length,
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
      greaterThanOrEqualTo(3),
    );
    expect(source, contains('PortableProfilePackage.maxEnvelopeBytes'));
    expect(source, contains('_lowMemoryTvosRestoreLimit'));
    expect(source, contains('TvosDevice.isLowMemoryCached'));
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
