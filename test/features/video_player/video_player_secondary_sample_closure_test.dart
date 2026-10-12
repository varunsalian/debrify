import 'package:debrify/screens/video_player_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/secondary_tracker_driver.dart';
import 'support/trakt_transport.dart';
import 'support/video_player_environment.dart';

void main() {
  TraktTestTransport.install();

  testWidgets(
    'Simkl authentication delivered during playback preserves the next user pause checkpoint',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = SecondaryTrackerDriver(t, f);
      await d.initialize();
      try {
        d.cipher.hold = true;
        await d.mountHeld(secondaryScreen(mdblist: false));
        await f.until(t, () => d.cipher.held.isNotEmpty);
        expect(f.player.state.playing, isTrue);
        expect(f.player.state.duration, const Duration(minutes: 20));
        expect(d.forTracker('simkl'), isEmpty);
        expect(d.heartbeats, isEmpty);

        // No playing edge follows authentication: this is the init continuation,
        // rather than a later stream callback stamping a local action marker.
        d.cipher.releaseAll();
        await d.drain();
        expect(d.heartbeats.where((timer) => timer.isActive), hasLength(1));
        expect(d.forTracker('simkl'), isEmpty);
        await d.position(300000);
        await d.playing(false);
        await d.waitCheckpoint('simkl', 1);
        d.expectCheckpoint('simkl', 0, 'pause', 25);
        expect(d.trackerActions('simkl'), ['pause']);
        expect(d.heartbeats.where((timer) => timer.isActive), isEmpty);
        await d.retired();
        await d.waitCheckpoint('simkl', 2);
        d.expectCheckpoint('simkl', 1, 'stop', 25);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'Simkl incomplete season-only launch rejects pause heartbeat seek EOF and disposal checkpoints',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = SecondaryTrackerDriver(t, f);
      await d.initialize();
      try {
        await d.mount(
          const VideoPlayerScreen(
            videoUrl: 'https://player.test/season-only.mp4',
            title: 'Fixture S02.mkv',
            contentImdbId: 'tt5100000',
            contentType: 'series',
            contentSeason: 2,
            simklScrobble: true,
          ),
        );
        expect(d.heartbeats.where((timer) => timer.isActive), hasLength(1));
        await d.position(300000);
        await d.playing(false);
        expect(d.forTracker('simkl'), isEmpty);
        await d.playing(true);
        await d.tick(const Duration(minutes: 2));
        expect(d.forTracker('simkl'), isEmpty);
        await d.seekBeforeLanding(.81);
        expect(d.forTracker('simkl'), isEmpty);
        f.player.emit('completed', true);
        await d.drain();
        expect(d.forTracker('simkl'), isEmpty);
        expect(d.heartbeats.where((timer) => timer.isActive), isEmpty);
        await d.retired();
        expect(d.forTracker('simkl'), isEmpty);
      } finally {
        await d.close();
      }
    },
  );
}
