import '../profiles/profile_preferences.dart';
import '../profiles/profile_runtime.dart';

/// Process-local bridge from synchronous SQLite writers to the current sync
/// device identity and scheduler. The persisted row remains authoritative;
/// these hooks only supply a stamp origin and a post-commit wake-up.
abstract final class WebDavSyncLibraryMutation {
  static String originDeviceId = 'local-device';
  static void Function()? debugUserMutationObserver;

  static void notifyUserMutation() {
    try {
      debugUserMutationObserver?.call();
    } catch (_) {
      // Test/diagnostic observers share the same never-throw boundary.
    }
    if (!ProfileRuntime.isInitialized || !ProfileRuntime.isProfileCommitted) {
      return;
    }
    try {
      ProfilePreferences.notifyWebDavSyncLocalChange(
        ProfileRuntime.capture().profileId,
        ProfilePreferences.webDavSyncLibraryLogicalKey,
      );
    } catch (_) {
      // A committed database mutation is never failed by sync scheduling.
    }
  }
}
