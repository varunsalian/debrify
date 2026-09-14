import 'dart:io';

const _passphraseVariable = 'WEBDAV_SYNC_AUDIT_PASSPHRASE';
const _backupVariable = 'WEBDAV_SYNC_AUDIT_BACKUP';
const _syncRootVariable = 'WEBDAV_SYNC_AUDIT_ROOT';

/// Launches the Flutter-bound production profile-package decoder without ever
/// placing the passphrase on the process command line.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln(
      'Usage: $_passphraseVariable=<redacted> dart run '
      'tool/webdav_sync_completeness_audit.dart <backup.json> <sync-folder>',
    );
    exitCode = 64;
    return;
  }
  final passphrase = Platform.environment[_passphraseVariable];
  if (passphrase == null || passphrase.isEmpty) {
    stderr.writeln(
      'Missing $_passphraseVariable (its value is never printed).',
    );
    exitCode = 64;
    return;
  }

  final toolDirectory = File.fromUri(Platform.script).parent;
  final repositoryRoot = toolDirectory.parent;
  final runner = File(
    '${toolDirectory.path}/src/webdav_sync_completeness_audit_runner.dart',
  );
  if (!await runner.exists()) {
    stderr.writeln('Completeness audit runner is missing.');
    exitCode = 1;
    return;
  }

  try {
    final process = await Process.start(
      'flutter',
      <String>['test', '--no-pub', '--reporter=expanded', runner.path],
      workingDirectory: repositoryRoot.path,
      environment: <String, String>{
        ...Platform.environment,
        _backupVariable: File(arguments[0]).absolute.path,
        _syncRootVariable: Directory(arguments[1]).absolute.path,
      },
      mode: ProcessStartMode.inheritStdio,
    );
    exitCode = await process.exitCode;
  } catch (error) {
    // Avoid interpolating arbitrary process errors. The passphrase is only in
    // the child environment, but keeping failures type-only is safer.
    stderr.writeln('AUDIT LAUNCH FAILED (${error.runtimeType}).');
    exitCode = 1;
  }
}
