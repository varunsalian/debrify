import 'package:debrify/models/custom_series_identity.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/secondary_tracker_driver.dart';
import 'support/trakt_transport.dart';
import 'support/video_player_environment.dart';

void main() {
  TraktTestTransport.install();
  for (final tracker in ['simkl', 'mdblist']) {
    testWidgets(
      'Secondary $tracker custom identity policy disables otherwise enabled tracking before authentication',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = SecondaryTrackerDriver(t, f);
        await d.initialize();
        try {
          await d.mount(
            secondaryScreen(
              simkl: tracker == 'simkl',
              mdblist: tracker == 'mdblist',
              id: const CustomSeriesIdentity('fixture', 'p6-policy').id,
            ),
          );
          await d.position(972000);
          await d.playing(false);
          await d.playing(true);
          await d.seek(.9);
          await d.tick(const Duration(minutes: 2));
          expect(d.forTracker(tracker), isEmpty);
          expect(d.heartbeats, isEmpty);
          await d.retired();
          expect(d.forTracker(tracker), isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }

  testWidgets(
    'Secondary missing session stop diagnostics retain false presence before any allocation',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = SecondaryTrackerDriver(t, f);
      await d.initialize();
      final oldPrint = debugPrint;
      final logs = <String>[];
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };
      try {
        await d.mount(secondaryScreen(simkl: false, mdblist: false));
        await d.retired();
        expect(
          logs,
          contains(
            '[MDBListDiag] player stop complete=false session=false positionMs=80 durationMs=1200000',
          ),
        );
        expect(d.forTracker('mdblist'), isEmpty);
      } finally {
        debugPrint = oldPrint;
        await d.close();
      }
    },
  );

  testWidgets(
    'Simkl initialized playing owns one immediate heartbeat without a remote start',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = SecondaryTrackerDriver(t, f);
      await d.initialize();
      try {
        await d.mount(secondaryScreen(mdblist: false));
        expect(d.heartbeats.where((timer) => timer.isActive), hasLength(1));
        expect(d.forTracker('simkl'), isEmpty);
        await d.tick(const Duration(minutes: 2));
        await d.waitCheckpoint('simkl', 1);
        d.expectCheckpoint('simkl', 0, 'pause', 80 / 1200000 * 100);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'Simkl initially disabled policy cannot install even a silent heartbeat before any input',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = SecondaryTrackerDriver(t, f);
      await d.initialize(target: false);
      try {
        await d.mount(secondaryScreen(mdblist: false));
        expect(d.heartbeats, isEmpty);
        expect(d.forTracker('simkl'), isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'Simkl disposal during playing auth completion cannot create a late heartbeat',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = SecondaryTrackerDriver(t, f);
      await d.initialize();
      try {
        d.cipher.hold = true;
        await d.mountHeld(secondaryScreen(mdblist: false));
        expect(f.player.state.playing, isTrue);
        await d.retired();
        d.cipher.releaseAll();
        await d.drain();
        expect(d.heartbeats, isEmpty);
        expect(d.forTracker('simkl'), isEmpty);
        await d.tick(const Duration(minutes: 2));
        expect(d.forTracker('simkl'), isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'Simkl authentication inside startup validation keeps its timer absent until a decoded frame releases the gate',
    (t) async {
      final f = VideoPlayerEnvironment(
        configurePlayer: (p) {
          p.onOpen = () {};
        },
      );
      final d = SecondaryTrackerDriver(t, f);
      await d.initialize();
      try {
        d.cipher.hold = true;
        await d.mountHeld(secondaryScreen(mdblist: false));
        f.player.emit('duration', const Duration(minutes: 20));
        f.player.emit('playing', true);
        await d.drain();
        d.cipher.releaseAll();
        await d.drain();
        expect(d.heartbeats, isEmpty);
        expect(d.forTracker('simkl'), isEmpty);
        f.player.publishFrame();
        f.controllers.last.publishFrame();
        await f.until(t, () => d.heartbeats.isNotEmpty);
        expect(d.heartbeats.where((timer) => timer.isActive), hasLength(1));
        expect(d.forTracker('simkl'), isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'Simkl episode-only filename remains unresolved and leaves its heartbeat armed above eighty',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = SecondaryTrackerDriver(t, f);
      await d.initialize();
      try {
        await d.mount(
          const VideoPlayerScreen(
            videoUrl: 'https://player.test/partial.mp4',
            title: 'Fixture.Episode.3.mkv',
            contentImdbId: 'tt5100000',
            contentType: 'series',
            simklScrobble: true,
          ),
        );
        await d.position(972000);
        await d.tick(const Duration(minutes: 2));
        expect(d.forTracker('simkl'), isEmpty);
        expect(d.heartbeats.where((timer) => timer.isActive), hasLength(1));
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'Simkl public seek endpoints send exactly one hundred then zero and a reverse seek at eighty remains resumable',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = SecondaryTrackerDriver(t, f);
      await d.initialize();
      try {
        await d.mount(secondaryScreen(mdblist: false));
        await d.seekBeforeLanding(1);
        await d.waitCheckpoint('simkl', 1);
        d.expectCheckpoint('simkl', 0, 'stop', 100);
        expect(d.heartbeats.where((timer) => timer.isActive), isEmpty);
        await d.seekBeforeLanding(1);
        expect(d.forTracker('simkl'), hasLength(1));
        await d.seekBeforeLanding(0);
        await d.waitCheckpoint('simkl', 2);
        d.expectCheckpoint('simkl', 1, 'pause', 0);
        await d.seekBeforeLanding(.81);
        await d.waitCheckpoint('simkl', 3);
        d.expectCheckpoint('simkl', 2, 'stop', 81);
        expect(d.heartbeats.where((timer) => timer.isActive), isEmpty);
        await d.seekBeforeLanding(.8);
        await d.waitCheckpoint('simkl', 4);
        d.expectCheckpoint('simkl', 3, 'pause', 80);
        expect(d.heartbeats.where((timer) => timer.isActive), hasLength(1));
      } finally {
        await d.close();
      }
    },
  );

  for (final target in ['disabled', 'empty', 'unresolved']) {
    testWidgets(
      'MDBList startup $target preserves exact requested and rejection diagnostics',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = SecondaryTrackerDriver(t, f);
        await d.initialize();
        final oldPrint = debugPrint;
        final logs = <String>[];
        debugPrint = (String? message, {int? wrapWidth}) {
          if (message != null) logs.add(message);
        };
        try {
          final requested = target != 'disabled';
          final id = target == 'empty' ? '' : 'tt5100000';
          await d.mount(
            secondaryScreen(
              simkl: false,
              mdblist: requested,
              id: id,
              season: target == 'unresolved' ? null : 2,
            ),
          );
          expect(
            logs,
            contains(
              '[MDBListDiag] player init requested=$requested flag=true imdb=$id type=series',
            ),
          );
          expect(
            logs,
            contains(
              target == 'disabled'
                  ? '[MDBListDiag] player init skipped: tracking not requested'
                  : '[MDBListDiag] player init skipped: invalid target metadata',
            ),
          );
          expect(d.forTracker('mdblist'), isEmpty);
          expect(d.heartbeats, isEmpty);
          await d.retired();
          expect(d.forTracker('mdblist'), isEmpty);
        } finally {
          debugPrint = oldPrint;
          await d.close();
        }
      },
    );
  }

  testWidgets(
    'Simkl EOF then disposal deduplicates the already sent stop checkpoint',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = SecondaryTrackerDriver(t, f);
      await d.initialize();
      try {
        await d.mount(secondaryScreen(mdblist: false));
        await d.position(600000);
        f.player.emit('completed', true);
        await d.drain();
        await d.waitCheckpoint('simkl', 1);
        d.expectCheckpoint('simkl', 0, 'stop', 50);
        await d.retired();
        expect(d.forTracker('simkl'), hasLength(1));
        expect(d.heartbeats.where((timer) => timer.isActive), isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'Simkl repeated playing notification replaces its live heartbeat without a duplicate checkpoint',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = SecondaryTrackerDriver(t, f);
      await d.initialize();
      try {
        await d.mount(secondaryScreen(mdblist: false));
        expect(d.heartbeats.where((timer) => timer.isActive), hasLength(1));
        final before = d.heartbeats.length;
        await d.playing(true);
        expect(d.heartbeats, hasLength(before + 1));
        expect(d.heartbeats.where((timer) => timer.isActive), hasLength(1));
        expect(d.heartbeats[before - 1].isActive, isFalse);
        await d.position(600000);
        await d.tick(const Duration(minutes: 2));
        await d.waitCheckpoint('simkl', 1);
        d.expectCheckpoint('simkl', 0, 'pause', 50);
        expect(d.forTracker('simkl'), hasLength(1));
      } finally {
        await d.close();
      }
    },
  );

  for (final gate in ['paused', 'duration']) {
    testWidgets(
      'Simkl public seek while $gate remains silent despite a threshold-sized input',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = SecondaryTrackerDriver(t, f);
        await d.initialize();
        try {
          await d.mount(secondaryScreen(mdblist: false));
          await d.position(300000);
          if (gate == 'paused') {
            await d.playing(false);
            await d.waitCheckpoint('simkl', 1);
            d.expectCheckpoint('simkl', 0, 'pause', 25);
          } else {
            f.player.emit('duration', Duration.zero);
            await d.drain();
          }
          final before = d.forTracker('simkl').length;
          await d.seekBeforeLanding(.9);
          expect(d.forTracker('simkl'), hasLength(before));
          expect(
            d.heartbeats.where((timer) => timer.isActive),
            hasLength(gate == 'paused' ? 0 : 1),
          );
        } finally {
          await d.close();
        }
      },
    );
  }

  for (final event in ['play', 'dispose']) {
    testWidgets(
      'MDBList held resume $event samples its promised position before any intervening native position event',
      (t) async {
        final f = VideoPlayerEnvironment(
          configurePlayer: (player) {
            player.failures['seek'] = StateError('synthetic unlanded resume');
          },
        );
        final d = SecondaryTrackerDriver(t, f);
        await d.initialize();
        try {
          await d.mount(secondaryScreen(simkl: false, mdblistPercent: 50));
          await d.waitCheckpoint('mdblist', 1);
          expect(f.player.state.position, const Duration(milliseconds: 80));
          d.expectCheckpoint('mdblist', 0, 'pause', 0.01);
          if (event == 'play') {
            await d.playing(true);
            expect(d.forTracker('mdblist'), hasLength(1));
            await d.tick(const Duration(minutes: 2));
            expect(d.seeks, [const Duration(seconds: 600)]);
          }
          if (event == 'dispose') await d.retired();
          await d.waitCheckpoint('mdblist', 2);
          d.expectCheckpoint('mdblist', 1, 'pause', 50);
        } finally {
          await d.close();
        }
      },
    );
  }

  testWidgets(
    'MDBList ordinary disposal logs its session exit before close exactly once',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = SecondaryTrackerDriver(t, f);
      await d.initialize();
      final oldPrint = debugPrint;
      final logs = <String>[];
      try {
        await d.mount(secondaryScreen(simkl: false));
        await d.waitCheckpoint('mdblist', 1);
        await d.position(300000);
        debugPrint = (String? message, {int? wrapWidth}) {
          if (message != null) logs.add(message);
        };
        await d.retired();
        await d.waitCheckpoint('mdblist', 2);
        d.expectCheckpoint('mdblist', 1, 'pause', 25);
        expect(
          logs.where(
            (line) =>
                line.startsWith('[MDBListDiag] player stop ') ||
                line.startsWith('[MDBListDiag] session exit ') ||
                line.startsWith('[MDBListDiag] session close '),
          ),
          [
            '[MDBListDiag] player stop complete=false session=true positionMs=300000 durationMs=1200000',
            '[MDBListDiag] session exit imdb=tt5100000 progress=25.000',
            '[MDBListDiag] session close imdb=tt5100000 progress=25.000',
          ],
        );
        expect(d.heartbeats.where((timer) => timer.isActive), isEmpty);
      } finally {
        debugPrint = oldPrint;
        await d.close();
      }
    },
  );

  testWidgets(
    'MDBList positive duration replacement updates the heartbeat denominator without another position or playing event',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = SecondaryTrackerDriver(t, f);
      await d.initialize();
      try {
        await d.mount(secondaryScreen(simkl: false));
        await d.waitCheckpoint('mdblist', 1);
        await d.position(300000);
        f.player.emit('duration', const Duration(minutes: 10));
        await d.drain();
        await d.tick(const Duration(minutes: 2));
        await d.waitCheckpoint('mdblist', 2);
        d.expectCheckpoint('mdblist', 1, 'pause', 50);
      } finally {
        await d.close();
      }
    },
  );
}
