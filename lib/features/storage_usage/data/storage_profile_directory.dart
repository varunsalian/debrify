// Names the profiles whose folders the storage scan found.
import 'package:debrify/features/storage_usage/models/storage_usage_models.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';

/// Every profile the registry knows, disabled and half-imported ones
/// included, so their folders are not reported as leftovers. Null before
/// profiles are committed: folders left by an interrupted migration are
/// then unknown, not a deleted profile's.
Future<List<StorageProfileInfo>?> readStorageProfiles() async {
  if (!ProfileRuntime.isProfileCommitted) return null;
  final profiles = await ProfileBootstrap.registry.listProfiles(
    includeDisabled: true,
    includeStaging: true,
  );
  return [
    for (final profile in profiles)
      StorageProfileInfo(
        id: profile.id,
        name: profile.name,
        visibleGeneration: profile.visibleDataGeneration,
      ),
  ];
}
