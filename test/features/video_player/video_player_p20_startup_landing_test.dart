import 'package:debrify/services/player_display_controls.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/video_resume_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/resume_driver.dart';
import 'support/video_player_environment.dart';

const _direct = 'https://landing.test/p20-direct.mp4';
const _cold = 'https://dl.mypikpak.com/p20-landing.mp4';

/// Every startup seek branch that promises a position verifies its landing.
final _wakeDrain = Object();

void main() {
  for (final url in [_direct, _cold]) {
    final branch = url == _cold ? 'PikPak' : 'direct';
    for (final (label, screen, stored) in [
      (
        'stored resume',
        VideoPlayerScreen(videoUrl: url, title: 'P20 landing resume'),
        true,
      ),
      (
        'random start without a share',
        VideoPlayerScreen(
          videoUrl: url,
          title: 'P20 landing random',
          startFromRandom: true,
          randomStartMaxPercent: 0,
        ),
        true,
      ),
      (
        'Stremio TV deferred percent start',
        VideoPlayerScreen(
          videoUrl: url,
          title: 'P20 landing slot',
          startAtPercent: .25,
          stremioTvChannels: const [
            {'id': 'slot', 'name': 'P20 slot'},
          ],
          stremioTvCurrentChannelId: 'slot',
        ),
        false,
      ),
      (
        'percent start',
        VideoPlayerScreen(
          videoUrl: url,
          title: 'P20 landing percent',
          startAtPercent: .25,
        ),
        false,
      ),
    ]) {
      testWidgets('P20 the $branch $label seek is landing-verified', (t) async {
        final f = VideoPlayerEnvironment();
        await t.runAsync(f.initialize);
        final d = ResumeVerifierDriver(t, f);
        try {
          if (stored) {
            await f.finish(
              t,
              VideoResumeStorage.upsertVideoResume(url, {
                'positionMs': 300000,
                'speed': 1.0,
                'aspect': 'contain',
              }),
            );
          }
          await d.observe(() => f.mount(t, screen));
          await f.until(t, () => f.player.calls.any((c) => c.$1 == 'seek'));
          for (var i = 0; i < 20 && d.awaits.isEmpty; i++) {
            await f.advance(t, const Duration(milliseconds: 10));
          }
          expect(d.awaits, isNotEmpty, reason: 'verification started');
          await d.drain();
        } finally {
          await f.actions.settle(t);
          await f.close(t);
          // Leave the shared wakelock queue cursor in the real zone (as
          // EngineDriver.close does) so later cases in this isolate do not stall.
          await t.runAsync(
            () => PlayerDisplayControls.instance.setWakelockOwner(
              _wakeDrain,
              false,
            ),
          );
        }
      });
    }
  }
}
