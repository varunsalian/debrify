// Immutable results of a storage scan: where Debrify's on-disk bytes are,
// grouped by what they hold and by the profile that owns them.

/// What a file holds, as far as its path tells.
enum StorageCategory {
  iptvCatalogs,
  debrifyTv,
  imageCache,
  guideDownloads,
  guideCache,
  recordings,
  downloads,
  logs,
  preferences,
  otherDatabases,
  other,
}

/// One folder the scanner walks.
///
/// With [onlyEntries] set, only the top-level entries it names are walked:
/// the folder is shared with other apps (a desktop Documents or temp
/// folder), so everything else in it belongs to someone else. An entry
/// ending in `*` matches by prefix.
final class StorageRoot {
  const StorageRoot({
    required this.label,
    required this.path,
    this.onlyEntries,
  });

  final String label;
  final String path;
  final List<String>? onlyEntries;
}

/// One file the scan found, kept for the largest-files list.
final class StorageFile {
  const StorageFile({
    required this.displayPath,
    required this.bytes,
    required this.category,
    this.profileId,
    this.generation,
  });

  /// Root label plus the path below the root.
  final String displayPath;
  final int bytes;
  final StorageCategory category;

  /// The profile whose private folder holds the file, if any.
  final String? profileId;

  /// The profile data generation folder holding the file, if any.
  final int? generation;
}

/// Bytes one profile's private folders hold, split by generation.
final class StorageProfileBytes {
  const StorageProfileBytes(this.profileId, this.byGeneration);

  final String profileId;

  /// Generation → bytes; the null key holds files outside a generation
  /// folder (avatars).
  final Map<int?, int> byGeneration;

  int get total => byGeneration.values.fold(0, (sum, bytes) => sum + bytes);
}

/// The raw result of walking every root.
final class StorageScan {
  const StorageScan({
    required this.totalBytes,
    required this.fileCount,
    required this.byCategory,
    required this.byProfile,
    required this.largest,
    required this.unreadableFolders,
  });

  final int totalBytes;
  final int fileCount;
  final Map<StorageCategory, int> byCategory;
  final List<StorageProfileBytes> byProfile;

  /// Largest files first.
  final List<StorageFile> largest;

  /// Folders the scan could not list (permissions, a file deleted mid-walk).
  final int unreadableFolders;
}

/// A profile as the report names it.
final class StorageProfileInfo {
  const StorageProfileInfo({
    required this.id,
    required this.name,
    required this.visibleGeneration,
  });

  final String id;
  final String name;
  final int visibleGeneration;
}

/// One profile row of the report.
final class StorageProfileUsage {
  const StorageProfileUsage({
    required this.profileId,
    required this.name,
    required this.currentBytes,
    required this.olderCopyBytes,
  });

  final String profileId;

  /// Null when the profile no longer exists: its folders are leftovers.
  final String? name;

  /// The visible generation plus files outside any generation folder.
  final int currentBytes;

  /// Generations other than the visible one: copies kept from a restore,
  /// a reset or an import until they are cleaned up.
  final int olderCopyBytes;

  int get total => currentBytes + olderCopyBytes;
}

/// What the page shows.
final class StorageUsageReport {
  const StorageUsageReport({
    required this.scan,
    required this.profiles,
    required this.scannedAt,
    required this.profilesKnown,
  });

  final StorageScan scan;

  /// Largest first.
  final List<StorageProfileUsage> profiles;
  final DateTime scannedAt;

  /// False when the profile list could not be read: a profile without a
  /// name is then unknown rather than deleted.
  final bool profilesKnown;
}
