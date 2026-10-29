// Composition and state for the storage report.
//
// Storage is device-wide, so the report has no profile key: it lists every
// profile's folders whichever profile opens it. It lives as long as the page
// (auto-dispose) and scans once per open plus once per explicit rescan.
// The sources declare no `dependencies`: they are app-wide, which is what
// lets the notifier read them.
import 'package:debrify/features/storage_usage/data/storage_profile_directory.dart';
import 'package:debrify/features/storage_usage/data/storage_roots.dart';
import 'package:debrify/features/storage_usage/data/storage_scanner.dart';
import 'package:debrify/features/storage_usage/models/storage_usage_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'storage_usage_report.dart';

/// Walks this platform's folders off the UI isolate; the cancellation
/// stops the walk.
final storageScanSourceProvider =
    Provider<Future<StorageScan> Function(StorageScanCancellation cancel)>(
      (ref) =>
          (cancel) async => scanStorageInBackground(
            await resolveStorageRoots(),
            cancellation: cancel,
          ),
    );

/// The profiles that own private folders; null when they are unknown.
final storageProfilesSourceProvider =
    Provider<Future<List<StorageProfileInfo>?> Function()>(
      (ref) => readStorageProfiles,
    );

final storageClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

final storageUsageProvider =
    AsyncNotifierProvider.autoDispose<StorageUsageNotifier, StorageUsageReport>(
      StorageUsageNotifier.new,
    );

final class StorageUsageNotifier extends AsyncNotifier<StorageUsageReport> {
  @override
  Future<StorageUsageReport> build() async {
    final scan = ref.read(storageScanSourceProvider);
    final readProfiles = ref.read(storageProfilesSourceProvider);
    final clock = ref.read(storageClockProvider);
    // A rescan or a closed page disposes this build: stop its walk.
    final cancellation = StorageScanCancellation();
    ref.onDispose(cancellation.cancel);
    final profiles = _profilesOrNull(readProfiles());
    final result = await scan(cancellation);
    return buildStorageUsageReport(result, await profiles, clock());
  }

  /// Scans again. A scan still running is superseded: it is cancelled and
  /// its result dropped.
  void rescan() => ref.invalidateSelf();

  /// Names are a nicety: without them the sizes still show.
  static Future<List<StorageProfileInfo>?> _profilesOrNull(
    Future<List<StorageProfileInfo>?> read,
  ) async {
    try {
      return await read;
    } catch (_) {
      return null;
    }
  }
}
