import 'dart:convert';
import 'dart:math';

import 'webdav_sync_library_models.dart';
import '../profiles/profile_preferences.dart';
import '../profiles/profile_runtime.dart';

/// Process-local bridge from synchronous SQLite writers to the current sync
/// device identity and scheduler. The persisted row remains authoritative;
/// these hooks only supply a stamp origin and a post-commit wake-up.
abstract final class WebDavSyncLibraryMutation {
  static String originDeviceId = 'local-device';
  static void Function()? debugUserMutationObserver;
  static DateTime Function() debugTvClock = DateTime.now;
  static String Function() debugTvGenerationId = _newGenerationId;

  static void resetDebugTvHooks() {
    debugTvClock = DateTime.now;
    debugTvGenerationId = _newGenerationId;
  }

  static final WebDavSyncMonotonicStamp _monotonic = WebDavSyncMonotonicStamp();

  /// Stamp time for a user TV mutation: the clock, floored strictly above the
  /// previous stamp so a backwards clock step cannot mint two different
  /// mutations with one identical stamp.
  static int nextTvStampMs() => _monotonic.next(debugTvClock);

  static String mintTvGenerationId({String? differentFrom}) {
    var candidate = debugTvGenerationId();
    if (candidate == differentFrom) candidate = _newGenerationId();
    if (candidate == differentFrom ||
        !RegExp(r'^[A-Za-z0-9_-]{1,96}$').hasMatch(candidate)) {
      throw StateError('Could not mint a valid Debrify TV pool generation');
    }
    return candidate;
  }

  static String _newGenerationId() {
    final random = Random.secure();
    final bytes = List<int>.generate(18, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  static void notifyUserMutation({bool playbackCheckpoint = false}) {
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
        playbackCheckpoint
            ? ProfilePreferences.webDavSyncPlaybackLibraryLogicalKey
            : ProfilePreferences.webDavSyncLibraryLogicalKey,
      );
    } catch (_) {
      // A committed database mutation is never failed by sync scheduling.
    }
  }
}
