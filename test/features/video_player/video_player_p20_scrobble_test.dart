import 'package:debrify/services/player_display_controls.dart';
import 'package:debrify/models/tracking_source.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/player_actions.dart';
import 'support/secondary_tracker_driver.dart';
import 'support/trakt_transport.dart';
import 'support/video_player_environment.dart';

const _pack = [
  PlaylistEntry(
    url: 'https://scrobble.test/S02E03.mkv',
    title: 'Show.S02E03.mkv',
  ),
  PlaylistEntry(
    url: 'https://scrobble.test/S02E04.mkv',
    title: 'Show.S02E04.mkv',
  ),
];

/// The play listener's tracker matrix, observed at the trackers' HTTP edge.
Future<void> _run(
  WidgetTester t,
  Future<void> Function(SecondaryTrackerDriver d, VideoPlayerEnvironment f)
  body,
) async {
  final f = VideoPlayerEnvironment();
  final d = SecondaryTrackerDriver(t, f);
  await d.initialize(
    targets: {
      TrackingSource.trakt,
      TrackingSource.simkl,
      TrackingSource.mdblist,
    },
  );
  try {
    await d.mount(secondaryScreen(trakt: true, playlist: _pack));
    await d.drain();
    await body(d, f);
  } finally {
    await f.close(t);
    // Leave the shared wakelock queue cursor in the real zone (as
    // EngineDriver.close does) so later cases in this isolate do not stall.
    await t.runAsync(
      () => PlayerDisplayControls.instance.setWakelockOwner(_wakeDrain, false),
    );
  }
}

Map<String, List<String>> _actions(SecondaryTrackerDriver d) => {
  for (final tracker in ['trakt', 'simkl', 'mdblist'])
    tracker: d.trackerActions(tracker),
};

int _beats(SecondaryTrackerDriver d) =>
    d.heartbeats.where((h) => h.isActive).length;

final _wakeDrain = Object();

void main() {
  // Before any tracker singleton binds a client in this isolate.
  TraktTestTransport.install();
  testWidgets(
    'P20 a user pause sends one pause per tracker and stops every heartbeat; resuming restarts Trakt and the heartbeats',
    (t) async {
      await _run(t, (d, f) async {
        expect(_actions(d), {
          'trakt': ['start'],
          'simkl': <String>[],
          'mdblist': ['pause'],
        });
        expect(_beats(d), 3);
        await d.position(300000);
        await d.playing(false);
        expect(_actions(d), {
          'trakt': ['start', 'pause'],
          'simkl': ['pause'],
          'mdblist': ['pause', 'pause'],
        });
        expect(_beats(d), 0);
        await d.playing(true);
        expect(_actions(d), {
          'trakt': ['start', 'pause', 'start'],
          'simkl': ['pause'],
          'mdblist': ['pause', 'pause'],
        });
        expect(_beats(d), 3);
      });
    },
  );

  testWidgets(
    'P20 an episode switch stops the outgoing trackers without any pause scrobble',
    (t) async {
      await _run(t, (d, f) async {
        await d.position(300000);
        final dynamic next = playerControls(t).onNext!;
        await f.finish<dynamic>(
          t,
          d.observe<dynamic>(() => next()) as Future<dynamic>,
        );
        await f.advance(t, const Duration(seconds: 4));
        await d.drain();
        expect(_actions(d), {
          'trakt': ['start', 'stop', 'start'],
          'simkl': ['stop'],
          // The outgoing checkpoint, then the incoming episode's startup one.
          'mdblist': ['pause', 'pause', 'pause'],
        });
      });
    },
  );
}
