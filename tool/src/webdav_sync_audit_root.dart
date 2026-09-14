import 'dart:io';
import 'dart:typed_data';

import 'package:debrify/services/webdav_sync/webdav_sync_models.dart';

/// Current authority wins. Only a missing file permits legacy fallback;
/// corrupt authority and access failures must remain visible to the auditor.
Future<({Uint8List markerBytes, String passphrase})> readAuditRoot(
  Directory directory,
  String legacyPassphrase,
) async {
  Uint8List bytes;
  try {
    bytes = await File('${directory.path}/circle.authority').readAsBytes();
  } on FileSystemException catch (error) {
    if (error.osError?.errorCode != 2) rethrow;
    return (
      markerBytes: await File(
        '${directory.path}/circle.json.enc',
      ).readAsBytes(),
      passphrase: legacyPassphrase,
    );
  }
  final authority = WebDavSyncAuthorityFile.parse(bytes);
  return (
    markerBytes: authority.markerBytes,
    passphrase: authority.syncPassphrase,
  );
}
