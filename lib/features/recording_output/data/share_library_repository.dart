// Lists and deletes the recordings on the active profile's SMB share. One
// short session per call: the Recordings page asks rarely, and a long-lived
// connection would outlive profile switches and network changes.

import 'package:flutter/foundation.dart';

import '../application/smb_contracts.dart';
import '../models/share_recording.dart';
import '../models/smb_target.dart';
import '../models/smb_upload_models.dart';
import 'dart_smb2_connector.dart';
import 'smb_settings_store.dart';

/// Video files a recording can be saved as.
const _videoExtensions = {'.ts', '.m2ts', '.mp4', '.mkv'};

final class ShareLibraryRepository {
  ShareLibraryRepository({
    SmbConnector connector = const DartSmb2Connector(),
    SmbUploadSettings? store,
  }) : _connector = connector,
       _store = store ?? SmbSettingsStore();

  final SmbConnector _connector;
  final SmbUploadSettings _store;

  /// The share's recordings, or null when no share is set up. A share that
  /// cannot be reached comes back with [ShareLibrary.error] set.
  Future<ShareLibrary?> load() async {
    final target = await _store.readTarget();
    if (!target.enabled || !target.isComplete) return null;
    final base = ShareLibrary(
      address: target.displayAddress,
      recordsDirect: target.recordDirect,
    );
    try {
      final recordings = await _session(target, (connection) async {
        final folder = target.folderSegments.join('/');
        try {
          return _recordingsIn(folder, await connection.list(folder));
        } on SmbException catch (e) {
          // No recording has created the folder yet.
          if (e.kind == SmbFailureKind.notFound) {
            return const <ShareRecording>[];
          }
          rethrow;
        }
      });
      return ShareLibrary(
        address: base.address,
        recordsDirect: base.recordsDirect,
        recordings: recordings,
      );
    } catch (error) {
      debugPrint('Share library: listing failed (${_kindOf(error)})');
      return ShareLibrary(
        address: base.address,
        recordsDirect: base.recordsDirect,
        error: _messageFor(error),
      );
    }
  }

  /// Removes [recording] from the share. Throws [SmbException] on failure.
  Future<void> delete(ShareRecording recording) async {
    final target = await _store.readTarget();
    if (!target.enabled || !target.isComplete) {
      throw const SmbException(SmbFailureKind.other, 'no share is set up');
    }
    await _session(target, (c) => c.delete(recording.path));
  }

  Future<T> _session<T>(
    SmbTarget target,
    Future<T> Function(SmbConnection connection) body,
  ) async {
    final connection = await _connector.connect(
      target,
      await _store.readPassword(),
    );
    try {
      return await body(connection);
    } finally {
      try {
        await connection.close();
      } catch (_) {
        // Logging off never decides the result.
      }
    }
  }

  static List<ShareRecording> _recordingsIn(
    String folder,
    List<SmbEntry> entries,
  ) {
    final recordings = <ShareRecording>[
      for (final entry in entries)
        if (entry.isFile && _isRecording(entry.name))
          ShareRecording(
            name: entry.name,
            path: folder.isEmpty ? entry.name : '$folder/${entry.name}',
            bytes: entry.bytes,
            modified: entry.modified,
          ),
    ]..sort((a, b) => b.modified.compareTo(a.modified));
    return recordings;
  }

  /// Video files only: never the upload's `.part` files or hidden probes.
  static bool _isRecording(String name) {
    if (name.startsWith('.')) return false;
    final dot = name.lastIndexOf('.');
    if (dot <= 0) return false;
    return _videoExtensions.contains(name.substring(dot).toLowerCase());
  }

  static String _kindOf(Object error) =>
      error is SmbException ? error.kind.name : error.runtimeType.toString();

  static String _messageFor(Object error) {
    if (error is! SmbException) return 'The share could not be read';
    return switch (error.kind) {
      SmbFailureKind.auth => 'The share refused the user name or password',
      SmbFailureKind.network => 'The share cannot be reached right now',
      SmbFailureKind.accessDenied => 'This user may not read the folder',
      SmbFailureKind.notFound => 'The share or folder does not exist',
      _ => 'The share could not be read',
    };
  }
}
