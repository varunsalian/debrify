import 'package:debrify/screens/video_player_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/secondary_policy_reads.dart';
import 'support/secondary_tracker_driver.dart';
import 'support/trakt_transport.dart';
import 'support/video_player_environment.dart';

void main() {
  TraktTestTransport.install();
  testWidgets(
    'Simkl disabled policy delivered after playing and duration cannot arm a silent heartbeat',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = SecondaryTrackerDriver(t, f);
      await d.initialize(target: false);
      final reads = MdblistPolicyReads(awaitName: 'initSimklScrobble');
      try {
        await d.observe(
          () => reads.run(() => f.mount(t, secondaryScreen(mdblist: false))),
        );
        await f.until(t, () => reads.pending.isNotEmpty);
        expect(f.player.state.playing, isTrue);
        expect(f.player.state.duration, const Duration(minutes: 20));
        reads.release();
        await d.drain();
        expect(d.heartbeats, isEmpty);
        expect(d.forTracker('simkl'), isEmpty);
      } finally {
        reads.release();
        await d.close();
      }
    },
  );
  testWidgets(
    'Simkl parsed episode-only identity rejects heartbeat and pause with a missing season',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = SecondaryTrackerDriver(t, f);
      await d.initialize();
      try {
        await d.mount(
          const VideoPlayerScreen(
            videoUrl: 'https://player.test/episode-only.mp4',
            title: 'Fixture Episode 3.mkv',
            contentImdbId: 'tt5100000',
            contentType: 'series',
            simklScrobble: true,
          ),
        );
        await d.position(972000);
        await d.tick(const Duration(minutes: 2));
        expect(d.forTracker('simkl'), isEmpty);
        expect(d.heartbeats.where((timer) => timer.isActive), hasLength(1));
        await d.playing(false);
        expect(d.forTracker('simkl'), isEmpty);
      } finally {
        await d.close();
      }
    },
  );
}
