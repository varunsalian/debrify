import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Startup-only recovery for disposable Android cache artifacts. User media,
/// resumable remote transfers, databases and backup destinations are excluded.
class CacheScratchCleanup {
  static Future<void> run() async {
    if (!Platform.isAndroid) return;
    try {
      await clean(await getTemporaryDirectory());
    } catch (_) {
      // Storage may be unavailable. Cleanup must never block app startup.
    }
  }

  /// Call before starting imports/playback, never as a live cache sweeper.
  static Future<void> clean(Directory root, {DateTime? now}) async {
    if (!await root.exists()) return;
    final cutoff = (now ?? DateTime.now()).subtract(const Duration(days: 1));
    // Do not traverse a redirected cache root.
    if (p.normalize(await root.resolveSymbolicLinks()) !=
        p.normalize(root.absolute.path)) {
      return;
    }
    await for (final entry in root.list(followLinks: false)) {
      final name = p.basename(entry.path);
      if (entry is Directory &&
          (name == 'file_picker' || name == 'generated_downloads')) {
        await for (final copy in entry.list(followLinks: false)) {
          await _deleteOld(copy, cutoff);
        }
      } else if (_scratchName.hasMatch(name)) {
        await _deleteOld(entry, cutoff);
      }
    }
  }

  static final _scratchName = RegExp(
    r'^(?:xmltv_\d+\.tmp|torrent_payload_\d+\.json|'
    r'episode_(?:metadata|guide)_\d+\.json|'
    r'stremio_sub_[\w.-]+|update-inspection-[\w.-]+\.apk|'
    r'debrify-iptv-[\w-]+|xtream-[\w-]+|'
    r'webdav-sync-section-[\w-]+|debrify-migrate-[\w-]+|'
    r'debrify-(?:channel-)?send-[\w-]+)$',
  );

  static Future<void> _deleteOld(
    FileSystemEntity entry,
    DateTime cutoff,
  ) async {
    if (entry is Link) return;
    try {
      if (!(await entry.stat()).modified.isBefore(cutoff)) return;
      if (entry is Directory) {
        await for (final child in entry.list(
          recursive: true,
          followLinks: false,
        )) {
          if (child is Link ||
              !(await child.stat()).modified.isBefore(cutoff)) {
            return;
          }
        }
      }
      await entry.delete(recursive: entry is Directory);
    } on FileSystemException {
      // An artifact can disappear or become unavailable during inspection.
    }
  }

  /// Release only a plugin-created copy, never the user's original selection.
  static Future<void> releasePickerCopy(String? selectedPath) async {
    if (!Platform.isAndroid || selectedPath == null) return;
    try {
      await deletePickerCopy(await getTemporaryDirectory(), selectedPath);
    } catch (_) {
      // The startup sweep will retry abandoned copies. A picker-cleanup error
      // must not turn a successful import into a failed operation.
    }
  }

  static Future<void> deletePickerCopy(
    Directory root,
    String selectedPath,
  ) async {
    final picker = p.join(await root.resolveSymbolicLinks(), 'file_picker');
    final selected = File(selectedPath);
    if (await FileSystemEntity.type(selectedPath, followLinks: false) !=
        FileSystemEntityType.file) {
      return;
    }
    final resolved = await selected.resolveSymbolicLinks();
    if (!p.isWithin(picker, resolved) ||
        p.normalize(selected.absolute.path) != p.normalize(resolved)) {
      return;
    }
    await selected.delete();
  }
}
