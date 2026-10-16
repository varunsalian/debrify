import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/video_resume_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/video_player_environment.dart';

void main() {
  for (final pikpak in [false, true]) {
    for (final randomFallback in [false, true]) {
      testWidgets(
        'Resume P14 startup ${pikpak ? 'PikPak' : 'ranked'} ${randomFallback ? 'random fallback' : 'percent seek'} reaches the original guarded caller',
        (t) async {
          final f = VideoPlayerEnvironment();
          await t.runAsync(f.initialize);
          const url = 'https://player.test/p14-start.mp4';
          final key = pikpak ? 'pikpak_p14-start' : url;
          try {
            await f.finish(
              t,
              VideoResumeStorage.upsertVideoResume(key, {
                'positionMs': 180000,
                'speed': 1.0,
                'aspect': 'contain',
              }),
            );
            await f.mount(
              t,
              VideoPlayerScreen(
                videoUrl: url,
                title: 'P14 start',
                playlist: pikpak
                    ? const [
                        PlaylistEntry(
                          url: url,
                          title: 'P14 start',
                          provider: 'pikpak',
                          pikpakFileId: 'p14-start',
                        ),
                      ]
                    : null,
                startFromRandom: randomFallback,
                randomStartMaxPercent: 0,
                startAtPercent: randomFallback ? null : 0.25,
              ),
            );
            await f.until(t, () => f.player.calls.any((c) => c.$1 == 'seek'));
            expect(
              f.player.calls.where((c) => c.$1 == 'seek').map((c) => c.$2),
              contains(
                Duration(milliseconds: randomFallback ? 180000 : 300000),
              ),
            );
          } finally {
            await f.close(t);
          }
        },
      );
    }
  }
}
