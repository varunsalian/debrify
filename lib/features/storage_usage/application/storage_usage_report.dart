// Turns a raw scan and the profile list into the report the page shows, and
// renders it as plain text for bug reports.
import 'package:debrify/features/storage_usage/models/storage_category_text.dart';
import 'package:debrify/features/storage_usage/models/storage_usage_models.dart';
import 'package:path/path.dart' as p;

/// Combines [scan] with [profiles]. A null [profiles] means the names could
/// not be read: every profile then counts as current, never as a leftover.
StorageUsageReport buildStorageUsageReport(
  StorageScan scan,
  List<StorageProfileInfo>? profiles,
  DateTime scannedAt,
) {
  final known = {
    for (final profile in profiles ?? const []) profile.id: profile,
  };
  final rows = <StorageProfileUsage>[];
  for (final usage in scan.byProfile) {
    final profile = known[usage.profileId];
    var current = 0;
    var older = 0;
    usage.byGeneration.forEach((generation, bytes) {
      final isOlder =
          profile != null &&
          generation != null &&
          generation != profile.visibleGeneration;
      if (isOlder) {
        older += bytes;
      } else {
        current += bytes;
      }
    });
    rows.add(
      StorageProfileUsage(
        profileId: usage.profileId,
        name: profile?.name,
        currentBytes: current,
        olderCopyBytes: older,
      ),
    );
  }
  rows.sort((a, b) => b.total.compareTo(a.total));
  return StorageUsageReport(
    scan: scan,
    profiles: List.unmodifiable(rows),
    scannedAt: scannedAt,
    profilesKnown: profiles != null,
  );
}

/// Plain-text summary to paste into a bug report. Profile names and ids
/// are replaced by numbered labels, and recordings, downloads and
/// unrecognised files lose their names (they can say what the user watches),
/// so neither leaves the device.
String storageUsageReportText(StorageUsageReport report) {
  final scan = report.scan;
  final labels = <String, String>{
    for (final (index, profile) in report.profiles.indexed)
      profile.profileId: _profileLabel(report, profile, index),
  };
  final lines = <String>[
    'Debrify storage: ${formatStorageBytes(scan.totalBytes)} in '
        '${scan.fileCount} files (${_stamp(report.scannedAt)})',
    '',
    'By kind:',
    for (final entry in sortedStorageCategories(scan))
      '  ${entry.key.label}: ${formatStorageBytes(entry.value)}',
  ];
  if (report.profiles.isNotEmpty) {
    lines
      ..add('')
      ..add('By profile:');
    for (final profile in report.profiles) {
      final older = profile.olderCopyBytes > 0
          ? ', older copies ${formatStorageBytes(profile.olderCopyBytes)}'
          : '';
      lines.add(
        '  ${labels[profile.profileId]}: '
        '${formatStorageBytes(profile.currentBytes)}$older',
      );
    }
  }
  if (scan.largest.isNotEmpty) {
    lines
      ..add('')
      ..add('Largest files:');
    for (final file in scan.largest) {
      lines.add(
        '  ${formatStorageBytes(file.bytes)}  '
        '${_sharedPath(file, labels[file.profileId])}',
      );
    }
  }
  if (scan.unreadableFolders > 0) {
    lines
      ..add('')
      ..add('Folders that could not be read: ${scan.unreadableFolders}');
  }
  return lines.join('\n');
}

/// Categories that hold anything, largest first.
List<MapEntry<StorageCategory, int>> sortedStorageCategories(
  StorageScan scan,
) =>
    scan.byCategory.entries.where((entry) => entry.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

String _profileLabel(
  StorageUsageReport report,
  StorageProfileUsage profile,
  int index,
) {
  if (profile.name != null || !report.profilesKnown) {
    return 'Profile ${index + 1}';
  }
  return 'Deleted profile ${index + 1}';
}

String _stamp(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${time.year}-${two(time.month)}-${two(time.day)} '
      '${two(time.hour)}:${two(time.minute)}';
}

/// [file]'s path for the copied report: the profile folder named by its
/// label, and a recording, a download or an unrecognised file reduced to its
/// kind (an older Android saves downloads loose in the app's own folder, so
/// an unrecognised name may be a title).
String _sharedPath(StorageFile file, String? profileLabel) {
  final segments = p.split(file.displayPath);
  final profiles = segments.indexOf('profiles');
  if (profileLabel != null && profiles >= 0 && profiles + 1 < segments.length) {
    segments[profiles + 1] = '<$profileLabel>';
  }
  final kind = switch (file.category) {
    StorageCategory.recordings => 'recording',
    StorageCategory.downloads => 'download',
    StorageCategory.other => 'file',
    _ => null,
  };
  if (kind == null) return p.joinAll(segments);
  return p.join(segments.first, '…', '<$kind>${p.extension(file.displayPath)}');
}
