import 'package:debrify/services/iptv_media_store.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_library_models.dart';

final class VideoResumeStorage {
  const VideoResumeStorage._(); // granted|denied|never|unknown
  // Shared within lib/services/storage/.
  static const String videoResumeKey = 'video_resume_v1';

  // Video resume — one row per item in debrify_tv.db (see IptvMediaStore).
  static Future<Map<String, dynamic>?> getVideoResume(String key) {
    return IptvMediaStore.videoResume(key);
  }

  static Future<void> upsertVideoResume(
    String key,
    Map<String, dynamic> entry, {
    String? sourceId,
    WebDavSyncMutationOrigin origin = WebDavSyncMutationOrigin.user,
  }) {
    return IptvMediaStore.upsertVideoResume(
      key,
      entry,
      sourceId: sourceId,
      origin: origin,
    );
  }

  static Future<void> removeVideoResume(
    String key, {
    bool playbackCheckpoint = false,
    WebDavSyncMutationOrigin origin = WebDavSyncMutationOrigin.user,
  }) {
    return IptvMediaStore.removeVideoResume(
      key,
      origin: origin,
      playbackCheckpoint: playbackCheckpoint,
    );
  }
}
