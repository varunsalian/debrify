// Physical playback-state access for the video-player characterization suites.
//
// The storage-boundary guard (dev/tool/check_storage_references.py) exempts
// exactly this file and exactly these three storage-internal members, so the
// suites can seed and assert the persisted resume map without an inspection
// seam in lib/. Every other test calls these forwarders instead.
import 'package:debrify/services/storage/playback_identity_storage.dart';
import 'package:debrify/services/storage/playback_state_store.dart';

abstract final class PhysicalResumeStore {
  static Future<Map<String, dynamic>> getPlaybackStateMap() =>
      PlaybackStateStore.getPlaybackStateMap();

  static Future<void> savePlaybackStateMap(
    Map<String, dynamic> map, {
    bool recordDeletions = false,
  }) => PlaybackStateStore.savePlaybackStateMap(
    map,
    recordDeletions: recordDeletions,
  );

  static String seriesProgressKey(String title, String? id) =>
      PlaybackIdentityStorage.seriesProgressKey(title, id);
}
