import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/storage/video_resume_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/local_completion_driver.dart';
import 'support/trakt_transport.dart';
import 'support/video_player_environment.dart';

void main() {
  TraktTestTransport.install();
  testWidgets(
    'Completion resume cleanup wakes playback sync for its profile rather than ordinary library scheduling',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = LocalCompletionDriver(t, f);
      await d.initialize();
      final previous = ProfilePreferences.webDavSyncLocalChangeSink;
      try {
        final screen = completionScreen();
        await d.mount(screen);
        await f.finish(
          t,
          VideoResumeStorage.upsertVideoResume(screen.videoUrl, {
            'positionMs': 111,
            'durationMs': 1200000,
          }),
        );
        final changes = <(String, String)>[];
        ProfilePreferences.webDavSyncLocalChangeSink = (profile, key) =>
            changes.add((profile, key));
        await d.percent(80);
        await d.drain();
        final library = changes
            .where(
              (change) =>
                  change.$2 ==
                      ProfilePreferences.webDavSyncPlaybackLibraryLogicalKey ||
                  change.$2 == ProfilePreferences.webDavSyncLibraryLogicalKey,
            )
            .toList();
        expect(library, [
          (
            ProfileRuntime.capture().profileId,
            ProfilePreferences.webDavSyncPlaybackLibraryLogicalKey,
          ),
        ]);
        expect(
          await f.finish(t, VideoResumeStorage.getVideoResume(screen.videoUrl)),
          isNull,
        );
        await f.finish(
          t,
          VideoResumeStorage.upsertVideoResume(screen.videoUrl, {
            'positionMs': 123,
            'durationMs': 1200000,
          }),
        );
        changes.clear();
        await d.eof();
        await d.drain();
        expect(
          changes,
          isEmpty,
          reason: 'EOF also respects the movie one-shot',
        );
        expect(
          (await f.finish(
            t,
            VideoResumeStorage.getVideoResume(screen.videoUrl),
          ))?['positionMs'],
          123,
        );
      } finally {
        ProfilePreferences.webDavSyncLocalChangeSink = previous;
        await d.close();
      }
    },
  );
}
