import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/video_resume_storage.dart';
import 'package:debrify/services/storage/video_progress_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/video_player_environment.dart';

void main() {
  const identities = {
    'Plain.Movie.mkv': 'Plain.Movie',
    'Plain.Movie.MP4': 'Plain.Movie',
    '': 'Fallback title',
    'No extension': 'No extension',
    'Trailing.': 'Trailing',
    '.hidden': '',
  };
  for (final entryTitle in identities.keys) {
    testWidgets(
      'fallback resume identity restores bookmark for "$entryTitle"',
      (tester) async {
        final fixture = VideoPlayerEnvironment();
        await tester.runAsync(fixture.initialize);
        const title = 'Fallback title.ts';
        final key = identities[entryTitle]!.hashCode.toString();
        await tester.runAsync(
          () => VideoResumeStorage.upsertVideoResume(key, {
            'positionMs': 180000,
            'speed': 1.0,
            'aspect': 'contain',
          }),
        );
        try {
          await fixture.mount(
            tester,
            VideoPlayerScreen(
              videoUrl: 'https://player.test/plain.mp4',
              title: title,
              playlist: [
                PlaylistEntry(
                  url: 'https://player.test/plain.mp4',
                  title: entryTitle,
                ),
              ],
            ),
          );
          expect(
            fixture.player.calls
                .where((call) => call.$1 == 'seek')
                .map((call) => call.$2),
            contains(const Duration(minutes: 3)),
          );
          expect(fixture.player.state.position, const Duration(minutes: 3));
        } finally {
          await fixture.close(
            tester,
            inspectStorage: () async {
              final bookmark = await VideoResumeStorage.getVideoResume(key);
              expect(bookmark?['positionMs'], 180000);
              final enhanced = await VideoProgressStorage.getVideoPlaybackState(
                videoTitle: key,
              );
              expect(enhanced?['positionMs'], 180000);
              expect(enhanced?['url'], 'https://player.test/plain.mp4');
              expect(
                await VideoResumeStorage.getVideoResume(
                  'https://player.test/plain.mp4',
                ),
                isNull,
              );
            },
          );
        }
      },
    );
  }
}
