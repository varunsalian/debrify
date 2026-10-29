// The folders that hold Debrify's data on this platform.
//
// The one place the storage report decides per platform what to walk:
// a sandboxed app owns its whole container, while on Windows and Linux the
// Documents and temp folders are shared with everything else on the machine,
// so only Debrify's own entries in them are counted.
import 'dart:io';

import 'package:debrify/features/storage_usage/models/storage_usage_models.dart';
import 'package:debrify/services/cache_scratch_cleanup.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// What Debrify writes at the top of the shared Documents folder, besides
/// one folder per profile under `profiles/`. `Debrify` holds recordings
/// when the machine has no Downloads folder.
const _documentsEntries = <String>[
  'engines',
  'downloads',
  'subtitle_fonts',
  'Debrify',
  'iptv_catalog.db*',
  'debrify_tv.db*',
];

/// The image caches' folders at the top of the temp folder; the other
/// entries Debrify writes there are named by [CacheScratchCleanup].
const _tempCacheEntries = <String>[
  'debrifyImageCache*',
  'debrifyIptvLogoCache*',
  'libCachedImageData*',
];

Future<List<StorageRoot>> resolveStorageRoots() async {
  final documents = await AppStorage.documents();
  final support = await AppStorage.support();
  final cache = await AppStorage.cache();
  final temp = await getTemporaryDirectory();

  if (Platform.isAndroid) {
    // The app's data folder holds app_flutter (documents), files (support),
    // cache, databases and shared_prefs: everything Android reports as Data
    // and Cache. The external app folder is counted under Data as well.
    final external = await _externalAppFolder();
    return [
      StorageRoot(label: 'App data', path: documents.parent.path),
      if (external != null)
        StorageRoot(label: 'App files', path: external.path),
    ];
  }

  if (Platform.isIOS || Platform.isMacOS || PlatformUtil.isTvOS) {
    // Sandboxed: the whole container is the app's own, Library/Preferences
    // and the web caches included. Its links to the user's folders (macOS
    // Desktop, Downloads, …) are not followed. AppStorage maps documents
    // onto Caches on tvOS, so the container comes from the real Documents.
    final container = await _containerFolder();
    if (container != null) {
      return [StorageRoot(label: 'App data', path: container.path)];
    }
    return [
      StorageRoot(label: 'Documents', path: documents.path),
      StorageRoot(label: 'Support', path: support.path),
      StorageRoot(label: 'Cache', path: cache.path),
      StorageRoot(label: 'Temp', path: temp.path),
    ];
  }

  return [
    StorageRoot(
      label: 'Documents',
      path: documents.path,
      onlyEntries: [
        ..._documentsEntries,
        for (final id in await _profileFolders(documents)) 'profiles/$id',
      ],
    ),
    StorageRoot(label: 'Support', path: support.path),
    StorageRoot(label: 'Cache', path: cache.path),
    StorageRoot(
      label: 'Temp',
      path: temp.path,
      onlyEntries: [..._tempCacheEntries, ...await _scratchEntries(temp)],
    ),
  ];
}

/// The app container, or null when the app may not be sandboxed. iOS and
/// tvOS apps always are; a macOS app is when the system set its container
/// id, and an unsandboxed build's documents parent is the user's home.
Future<Directory?> _containerFolder() async {
  if (Platform.isMacOS &&
      !Platform.environment.containsKey('APP_SANDBOX_CONTAINER_ID')) {
    return null;
  }
  try {
    return (await getApplicationDocumentsDirectory()).parent;
  } catch (_) {
    return null;
  }
}

/// Profile folders by their names, so another app's `profiles` folder in
/// the shared Documents folder is never counted.
Future<List<String>> _profileFolders(Directory documents) => _entriesWhere(
  Directory(p.join(documents.path, 'profiles')),
  (entry) =>
      entry is Directory &&
      ProfileScope.isValidProfileId(p.basename(entry.path)),
);

Future<List<String>> _scratchEntries(Directory temp) => _entriesWhere(
  temp,
  (entry) => CacheScratchCleanup.isScratchName(p.basename(entry.path)),
);

/// Names of the entries in [folder] that pass [test]; none if unreadable.
Future<List<String>> _entriesWhere(
  Directory folder,
  bool Function(FileSystemEntity entry) test,
) async {
  final names = <String>[];
  try {
    await for (final entry in folder.list(followLinks: false)) {
      if (test(entry)) names.add(p.basename(entry.path));
    }
  } on FileSystemException {
    // A folder that does not exist holds nothing of ours.
  }
  return names;
}

Future<Directory?> _externalAppFolder() async {
  try {
    return await getExternalStorageDirectory();
  } catch (_) {
    // No shared storage mounted: nothing to count there.
    return null;
  }
}
