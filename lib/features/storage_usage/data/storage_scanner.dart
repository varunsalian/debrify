// Walks Debrify's folders and adds up file sizes by category and profile.
//
// Pure dart:io with no plugins, so the whole walk runs in a worker isolate:
// a TV box can hold tens of thousands of cached images, and a stat per file
// on the UI isolate would stall the page.
import 'dart:io';
import 'dart:isolate';

import 'package:debrify/features/storage_usage/models/storage_usage_models.dart';
import 'package:path/path.dart' as p;

/// How many files the largest-files list keeps.
const int kStorageLargestFiles = 15;

/// Folder and file names of the image caches: flutter_cache_manager stores
/// (Debrify's two plus the package default) and Glide on Android.
const _imageCacheNames = <String>{
  'debrifyImageCache',
  'debrifyIptvLogoCache',
  'libCachedImageData',
  'image_manager_disk_cache',
};

/// Stops a scan that is no longer wanted.
final class StorageScanCancellation {
  bool _cancelled = false;
  void Function()? _onCancel;

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _onCancel?.call();
  }
}

/// Thrown by a scan that was cancelled before it finished.
final class StorageScanCancelled implements Exception {
  const StorageScanCancelled();
}

/// Runs [scanStorageRoots] in a worker isolate that [cancellation] kills,
/// so a scan superseded by a rescan or a closed page stops reading the disk.
Future<StorageScan> scanStorageInBackground(
  List<StorageRoot> roots, {
  StorageScanCancellation? cancellation,
}) async {
  if (cancellation?.isCancelled ?? false) throw const StorageScanCancelled();
  final messages = ReceivePort();
  try {
    final isolate = await Isolate.spawn(
      _scanInIsolate,
      (messages.sendPort, roots),
      onError: messages.sendPort,
      onExit: messages.sendPort,
      errorsAreFatal: true,
    );
    void kill() => isolate.kill(priority: Isolate.immediate);
    cancellation?._onCancel = kill;
    if (cancellation?.isCancelled ?? false) kill();
    // The result, or the error pair, arrives before the exit message.
    final message = await messages.first;
    if (message is StorageScan) return message;
    if (message is List && message.length == 2) {
      throw RemoteError('${message[0]}', '${message[1]}');
    }
    throw const StorageScanCancelled();
  } finally {
    cancellation?._onCancel = null;
    messages.close();
  }
}

void _scanInIsolate((SendPort, List<StorageRoot>) request) =>
    Isolate.exit(request.$1, scanStorageRoots(request.$2));

/// Walks [roots] and totals what it finds. A root listed twice, or nested
/// inside another whole-folder root, is skipped, and no file is counted
/// twice.
StorageScan scanStorageRoots(List<StorageRoot> roots) {
  final whole = [
    for (final root in roots)
      if (root.onlyEntries == null) p.normalize(p.absolute(root.path)),
  ];
  final byCategory = <StorageCategory, int>{};
  final byProfile = <String, Map<int?, int>>{};
  final seen = <String>{};
  final largest = <StorageFile>[];
  var total = 0;
  var files = 0;
  var unreadable = 0;

  void addFile(StorageRoot root, String rootPath, File file) {
    final path = p.normalize(file.path);
    if (!seen.add(path)) return;
    final int bytes;
    try {
      bytes = file.statSync().size;
    } on FileSystemException {
      return;
    }
    if (bytes < 0) return;
    final segments = p.split(p.relative(path, from: rootPath));
    final category = classifyStoragePath(segments);
    final owner = profileOwnerOf(segments);
    total += bytes;
    files++;
    byCategory.update(category, (sum) => sum + bytes, ifAbsent: () => bytes);
    if (owner != null) {
      byProfile
          .putIfAbsent(owner.profileId, () => <int?, int>{})
          .update(
            owner.generation,
            (sum) => sum + bytes,
            ifAbsent: () => bytes,
          );
    }
    _keepLargest(
      largest,
      StorageFile(
        displayPath: p.joinAll([root.label, ...segments]),
        bytes: bytes,
        category: category,
        profileId: owner?.profileId,
        generation: owner?.generation,
      ),
    );
  }

  final walked = <String>{};
  for (final root in roots) {
    final rootPath = p.normalize(p.absolute(root.path));
    final only = root.onlyEntries;
    if (only == null &&
        (!walked.add(rootPath) ||
            whole.any((other) => p.isWithin(other, rootPath)))) {
      // The same folder again, or one inside a folder walked whole.
      continue;
    }
    if (!Directory(rootPath).existsSync()) continue;
    final pending = <Directory>[];
    void visit(FileSystemEntity entry) {
      if (entry is File) {
        addFile(root, rootPath, entry);
      } else if (entry is Directory) {
        pending.add(entry);
      }
    }

    if (only == null) {
      pending.add(Directory(rootPath));
    } else {
      // Nested entries ("profiles/<id>") name one path below the root.
      for (final entry in only.where((entry) => entry.contains('/'))) {
        final path = p.joinAll([rootPath, ...entry.split('/')]);
        switch (FileSystemEntity.typeSync(path, followLinks: false)) {
          case FileSystemEntityType.file:
            visit(File(path));
          case FileSystemEntityType.directory:
            visit(Directory(path));
          default:
            break;
        }
      }
      final topLevel = only.where((entry) => !entry.contains('/')).toList();
      try {
        for (final entry in Directory(rootPath).listSync(followLinks: false)) {
          if (_matchesEntry(p.basename(entry.path), topLevel)) visit(entry);
        }
      } on FileSystemException {
        unreadable++;
      }
    }
    while (pending.isNotEmpty) {
      final directory = pending.removeLast();
      try {
        directory.listSync(followLinks: false).forEach(visit);
      } on FileSystemException {
        unreadable++;
      }
    }
  }

  return StorageScan(
    totalBytes: total,
    fileCount: files,
    byCategory: Map.unmodifiable(byCategory),
    byProfile: List.unmodifiable([
      for (final entry in byProfile.entries)
        StorageProfileBytes(entry.key, Map.unmodifiable(entry.value)),
    ]),
    largest: List.unmodifiable(largest),
    unreadableFolders: unreadable,
  );
}

/// Sorts a file into a category from its path below the root.
StorageCategory classifyStoragePath(List<String> segments) {
  if (segments.isEmpty) return StorageCategory.other;
  final name = segments.last;
  final folders = segments.sublist(0, segments.length - 1);
  if (name.startsWith('xmltv_') && name.endsWith('.tmp')) {
    return StorageCategory.guideDownloads;
  }
  if (folders.contains('epg_cache')) return StorageCategory.guideCache;
  if (segments.any(
    (segment) => _imageCacheNames.any((cache) => segment.startsWith(cache)),
  )) {
    return StorageCategory.imageCache;
  }
  if (name.startsWith('iptv_catalog.db')) return StorageCategory.iptvCatalogs;
  if (name.startsWith('debrify_tv.db')) return StorageCategory.debrifyTv;
  if (folders.contains('Recordings')) return StorageCategory.recordings;
  // Android stages generated downloads under cache/generated_downloads.
  if (folders.contains('downloads') ||
      folders.contains('generated_downloads')) {
    return StorageCategory.downloads;
  }
  if (folders.contains('diagnostics')) return StorageCategory.logs;
  if (folders.contains('shared_prefs') || name == 'shared_preferences.json') {
    return StorageCategory.preferences;
  }
  if (_isDatabaseFile(name)) return StorageCategory.otherDatabases;
  return StorageCategory.other;
}

/// The profile whose private folder holds the file at [segments]:
/// `profiles/<id>/…`, with the generation from `profiles/<id>/g/<n>/…`.
({String profileId, int? generation})? profileOwnerOf(List<String> segments) {
  final at = segments.indexOf('profiles');
  // The id must name a folder, not the file itself.
  if (at < 0 || segments.length < at + 3) return null;
  final generation = segments.length > at + 4 && segments[at + 2] == 'g'
      ? int.tryParse(segments[at + 3])
      : null;
  return (profileId: segments[at + 1], generation: generation);
}

bool _isDatabaseFile(String name) =>
    name.endsWith('.db') ||
    name.endsWith('.db-wal') ||
    name.endsWith('.db-shm') ||
    name.endsWith('.db-journal') ||
    name.endsWith('.sqlite');

bool _matchesEntry(String name, List<String> only) => only.any(
  (entry) => entry.endsWith('*')
      ? name.startsWith(entry.substring(0, entry.length - 1))
      : name == entry,
);

void _keepLargest(List<StorageFile> largest, StorageFile file) {
  if (largest.length == kStorageLargestFiles &&
      file.bytes <= largest.last.bytes) {
    return;
  }
  var index = largest.indexWhere((kept) => kept.bytes < file.bytes);
  if (index < 0) index = largest.length;
  largest.insert(index, file);
  if (largest.length > kStorageLargestFiles) largest.removeLast();
}
