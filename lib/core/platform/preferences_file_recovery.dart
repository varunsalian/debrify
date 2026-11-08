import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// What [recoverPreferencesFile] found.
enum PreferencesFileRecovery {
  /// No preferences file yet (first launch or cleared data).
  missing,

  /// The file parses; a backup of it was refreshed.
  valid,

  /// The file was unreadable and the last good backup replaced it.
  restored,

  /// The file was unreadable and no good backup existed; it was set aside so
  /// the app starts with fresh preferences.
  reset,

  /// The file was unreadable, no good backup existed, and starting fresh is
  /// not safe here (Linux keeps its device key in preferences), so the file
  /// is left as it was: the startup failure screen shows, unless it is one the
  /// plugin itself tolerates as empty.
  kept,

  /// Another Debrify process owns the file; it was not touched.
  busy,

  /// The check itself failed; startup continues as without it.
  failed,
}

/// The files this recovery writes beside `shared_preferences.json`, for a
/// device reset to remove with it.
const preferencesRecoveryFileNames = <String>[
  'shared_preferences.json.bak',
  'shared_preferences.json.bak.tmp',
  'shared_preferences.json.corrupt',
];

/// Linux keeps its device key in preferences under this plugin key. A backup
/// taken before the key existed would make the app mint a new one and strand
/// every sealed credential, so on Linux a backup only counts when it holds it.
const linuxDeviceKeyPreference = 'flutter.profiles_linux_wrapped_key_v1';

/// Windows and Linux keep shared_preferences in one JSON file that the plugin
/// rewrites in place and parses with no guard. A crash or power cut during a
/// write can leave it empty or zero-filled, and every later launch then fails
/// with `FormatException: Unexpected character (at character 1)` before any
/// UI appears. Reinstalling doesn't help: the file lives in app data.
///
/// Runs before the first preferences read. A good file is copied to `.bak`;
/// an unreadable one is moved to `.corrupt` (kept for support) and replaced by
/// the backup when it is good. Without a good backup, [allowReset] decides
/// between starting fresh and leaving the file as it is.
Future<PreferencesFileRecovery> recoverPreferencesFile(
  Directory dir, {
  required bool allowReset,
  String? backupMustHold,
}) async {
  final file = File(_join(dir, 'shared_preferences.json'));
  final backup = File(_join(dir, preferencesRecoveryFileNames[0]));
  final temp = File(_join(dir, preferencesRecoveryFileNames[1]));
  final corrupt = File(_join(dir, preferencesRecoveryFileNames[2]));
  if (!await file.exists()) {
    // A restore interrupted between its two renames: finish it, or the next
    // good launch would back up fresh preferences over the good backup.
    if (await corrupt.exists() &&
        await temp.exists() &&
        _parses(await temp.readAsBytes(), backupMustHold)) {
      await temp.rename(file.path);
      return PreferencesFileRecovery.restored;
    }
    return PreferencesFileRecovery.missing;
  }
  final bytes = await file.readAsBytes();
  if (_parses(bytes)) {
    await temp.writeAsBytes(bytes, flush: true);
    await _replace(temp, backup);
    return PreferencesFileRecovery.valid;
  }
  final restorable =
      await backup.exists() &&
      _parses(await backup.readAsBytes(), backupMustHold);
  if (!restorable && !allowReset) return PreferencesFileRecovery.kept;
  // Stage the backup first: if anything below fails, the good backup and the
  // unreadable file are both still on disk for the next launch.
  if (restorable) {
    await temp.writeAsBytes(await backup.readAsBytes(), flush: true);
  }
  await _replace(file, corrupt);
  if (!restorable) return PreferencesFileRecovery.reset;
  await temp.rename(file.path);
  return PreferencesFileRecovery.restored;
}

String _join(Directory dir, String name) =>
    '${dir.path}${Platform.pathSeparator}$name';

/// Renames over [to], which keeps [to] if the rename fails for any reason.
/// Only a rename refused because [to] exists (Windows errors 80 and 183)
/// deletes it and tries again.
Future<void> _replace(File from, File to) async {
  try {
    await from.rename(to.path);
  } on FileSystemException catch (error) {
    if (!const {80, 183}.contains(error.osError?.errorCode)) rethrow;
    await to.delete();
    await from.rename(to.path);
  }
}

/// The plugin never writes an empty file (an empty map is `{}`), so empty is
/// a truncated write too. It reads the file as UTF-8, so bytes that aren't
/// valid UTF-8 would fail there as well. [mustHold] is a key the map must
/// carry to count.
bool _parses(List<int> bytes, [String? mustHold]) {
  if (bytes.isEmpty) return false;
  try {
    final data = jsonDecode(utf8.decode(bytes));
    return data is Map && (mustHold == null || data.containsKey(mustHold));
  } on FormatException {
    return false;
  }
}

/// The startup entry point: Windows and Linux only, and never fatal.
///
/// It runs before the desktop single-instance lock is taken for the app's
/// lifetime, so it holds that same lock itself while it works: a second
/// process (a magnet or stremio link opened while the app runs) finds the
/// lock held and leaves the running app's file alone. [error] names the
/// exception type when the check itself failed.
Future<({PreferencesFileRecovery outcome, String? error})>
recoverDesktopPreferencesFile() async {
  if (!Platform.isWindows && !Platform.isLinux) {
    return (outcome: PreferencesFileRecovery.missing, error: null);
  }
  RandomAccessFile? lock;
  try {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    lock = await File(
      _join(dir, '.debrify-primary.lock'),
    ).open(mode: FileMode.append);
    try {
      await lock.lock(FileLock.exclusive);
    } on FileSystemException {
      return (outcome: PreferencesFileRecovery.busy, error: null);
    }
    final outcome = await recoverPreferencesFile(
      dir,
      allowReset: Platform.isWindows,
      backupMustHold: Platform.isLinux ? linuxDeviceKeyPreference : null,
    );
    return (outcome: outcome, error: null);
  } catch (error) {
    return (
      outcome: PreferencesFileRecovery.failed,
      error: error.runtimeType.toString(),
    );
  } finally {
    // Closing releases the lock; the app takes it again for its lifetime.
    // Unlock explicitly: Windows releases a lock on close only "depending on
    // available system resources", and a lock left behind would make this
    // process look like a second instance to itself.
    try {
      await lock?.unlock();
    } catch (_) {}
    try {
      await lock?.close();
    } catch (_) {}
  }
}
