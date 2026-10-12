import 'dart:async';

import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/screens/video_player/widgets/source_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/player_actions.dart';
import 'support/secondary_tracker_driver.dart';
import 'support/trakt_transport.dart';
import 'support/video_player_environment.dart';
import 'video_player_source_test.dart' show source;

void main() {
  TraktTestTransport.install();
  testWidgets(
    'MDBList validation release while paused refreshes its session before returning without play',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = SecondaryTrackerDriver(t, f);
      await d.initialize();
      final landing = Completer<void>();
      final a = source('Original', 'https://player.test/paused-release-a.mp4');
      final b = source('Incoming', 'https://player.test/paused-release-b.mp4');
      try {
        await d.mount(
          VideoPlayerScreen(
            videoUrl: a.directUrl!,
            title: 'Paused validation release',
            contentImdbId: 'tt5100000',
            contentType: 'series',
            contentSeason: 2,
            contentEpisode: 3,
            mdblistScrobble: true,
            stremioSources: [a, b],
            resolveStremioSource: (s) async => s.directUrl,
          ),
        );
        await d.waitCheckpoint('mdblist', 1);
        await d.position(300000);
        f.player.delays['seek'] = landing;
        f.player.onOpen = () =>
            f.player.publishFrame(duration: const Duration(minutes: 40));
        playerControls(t).onShowStremioSources!();
        await f.advance(t, const Duration(milliseconds: 300));
        t
            .widget<SourceSheet>(find.byType(SourceSheet))
            .onSourceSelected(1, b.directUrl!);
        await f.until(t, () => d.seeks.isNotEmpty);
        expect(d.seeks.last, const Duration(seconds: 300));
        playerControls(t).onPlayPause();
        await d.drain();
        expect(f.player.state.playing, isFalse);
        // The backend reports the landing while its command acknowledgement
        // is held. No second position edge arrives after validation releases.
        f.player.publishPositionOnSeekAcknowledgement = false;
        f.player.emit('position', const Duration(seconds: 300));
        await d.drain();
        landing.complete();
        f.player.delays.remove('seek');
        await d.drain();
        expect(d.forTracker('mdblist'), hasLength(1));
        // The original session's playing bit survives the gated pause. Keep
        // its resulting heartbeat, including the refreshed 40-minute duration.
        await d.tick(const Duration(minutes: 2));
        await d.waitCheckpoint('mdblist', 2);
        d.expectCheckpoint('mdblist', 1, 'pause', 12.5);
      } finally {
        if (!landing.isCompleted) landing.complete();
        f.player.delays.remove('seek');
        await d.close();
      }
    },
  );

  testWidgets(
    'Simkl successful source validation resets a watched stop marker before the next real pause',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = SecondaryTrackerDriver(t, f);
      await d.initialize();
      final a = source('Original', 'https://player.test/marker-release-a.mp4');
      final b = source('Incoming', 'https://player.test/marker-release-b.mp4');
      try {
        await d.mount(
          VideoPlayerScreen(
            videoUrl: a.directUrl!,
            title: 'Watched marker validation release',
            contentImdbId: 'tt5100000',
            contentType: 'series',
            contentSeason: 2,
            contentEpisode: 3,
            simklScrobble: true,
            stremioSources: [a, b],
            resolveStremioSource: (s) async => s.directUrl,
          ),
        );
        await d.seekBeforeLanding(.81);
        await d.waitCheckpoint('simkl', 1);
        d.expectCheckpoint('simkl', 0, 'stop', 81);
        playerControls(t).onShowStremioSources!();
        await f.advance(t, const Duration(milliseconds: 300));
        t
            .widget<SourceSheet>(find.byType(SourceSheet))
            .onSourceSelected(1, b.directUrl!);
        await f.until(t, () => d.seeks.length == 2);
        expect(d.seeks.last, const Duration(seconds: 972));
        await d.drain();
        await d.playing(false);
        await d.waitCheckpoint('simkl', 2);
        d.expectCheckpoint('simkl', 1, 'stop', 81);
        expect(d.trackerActions('simkl'), ['stop', 'stop']);
      } finally {
        await d.close();
      }
    },
  );
}
