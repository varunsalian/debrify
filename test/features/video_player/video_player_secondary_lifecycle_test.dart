import 'dart:async';

import 'package:debrify/models/tracking_source.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/screens/video_player/widgets/source_sheet.dart';
import 'package:debrify/services/storage/tracking_source_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/player_actions.dart';
import 'support/secondary_tracker_driver.dart';
import 'support/trakt_transport.dart';
import 'support/video_player_environment.dart';
import 'video_player_source_test.dart' show source;

void main() {
  TraktTestTransport.install();
  testWidgets(
    'Secondary held resume pins MDBList raw initialization then persistable pause and stop diagnostics',
    (t) async {
      final f = VideoPlayerEnvironment(
        configurePlayer: (p) {
          p.failures['seek'] = StateError('synthetic unlanded resume');
        },
      );
      final d = SecondaryTrackerDriver(t, f);
      await d.initialize();
      final oldPrint = debugPrint;
      final logs = <String>[];
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };
      try {
        await d.mount(secondaryScreen(mdblistPercent: 50));
        await d.waitCheckpoint('mdblist', 1);
        expect(d.seeks, [const Duration(seconds: 600)]);
        expect(f.player.state.position, const Duration(milliseconds: 80));
        d.expectCheckpoint('mdblist', 0, 'pause', 0.01);
        expect(
          logs,
          contains(
            '[MDBListDiag] player session ready imdb=tt5100000 episode=true playing=true positionMs=80 durationMs=1200000',
          ),
        );
        await d.playing(false);
        await d.waitCheckpoint('simkl', 1);
        await d.waitCheckpoint('mdblist', 2);
        d.expectCheckpoint('simkl', 0, 'pause', 50);
        d.expectCheckpoint('mdblist', 1, 'pause', 50);
        await d.retired();
        await d.waitCheckpoint('simkl', 2);
        d.expectCheckpoint('simkl', 1, 'stop', 50);
        expect(
          logs,
          contains(
            '[MDBListDiag] player stop complete=false session=true positionMs=80 durationMs=1200000',
          ),
        );
        expect(d.trackerActions('mdblist'), ['pause', 'pause']);
      } finally {
        debugPrint = oldPrint;
        await d.close();
      }
    },
  );

  testWidgets(
    'Secondary gated disposal still closes MDBList at its outgoing position with no Trakt or Simkl stop',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = SecondaryTrackerDriver(t, f);
      await d.initialize(
        targets: {
          TrackingSource.trakt,
          TrackingSource.simkl,
          TrackingSource.mdblist,
        },
      );
      final opening = Completer<void>();
      final a = source('Original', 'https://player.test/secondary-a.mp4');
      final b = source('Pending', 'https://player.test/secondary-b.mp4');
      try {
        await d.mount(
          VideoPlayerScreen(
            videoUrl: a.directUrl!,
            title: 'Secondary validation',
            contentImdbId: 'tt5100000',
            contentType: 'series',
            contentSeason: 2,
            contentEpisode: 3,
            traktScrobble: true,
            simklScrobble: true,
            mdblistScrobble: true,
            stremioSources: [a, b],
            resolveStremioSource: (s) async => s.directUrl,
          ),
        );
        await d.waitCheckpoint('trakt', 1);
        await d.waitCheckpoint('mdblist', 1);
        await d.position(300000);
        f.player.delays['open'] = opening;
        playerControls(t).onShowStremioSources!();
        await f.advance(t, const Duration(milliseconds: 300));
        t
            .widget<SourceSheet>(find.byType(SourceSheet))
            .onSourceSelected(1, b.directUrl!);
        await f.until(
          t,
          () => f.player.calls.where((c) => c.$1 == 'open').length == 2,
        );
        f.player.emit('position', const Duration(seconds: 600));
        f.player.emit('duration', const Duration(minutes: 20));
        await d.drain();
        final traktBefore = d.requests.length;
        final simklBefore = d.forTracker('simkl').length;
        await d.retired();
        await d.waitCheckpoint('mdblist', 2);
        d.expectCheckpoint('mdblist', 1, 'pause', 25);
        expect(d.requests, hasLength(traktBefore));
        expect(d.forTracker('simkl'), hasLength(simklBefore));
        expect(d.heartbeats.where((timer) => timer.isActive), isEmpty);
        opening.complete();
        await d.drain();
        await d.tick(const Duration(minutes: 4));
        expect(d.forTracker('mdblist'), hasLength(2));
      } finally {
        if (!opening.isCompleted) opening.complete();
        await d.close();
      }
    },
  );

  testWidgets(
    'Secondary legacy policy storage type error propagates from MDBList initialization while player failure stays caught',
    (t) async {
      final f = VideoPlayerEnvironment(committed: false);
      final d = SecondaryTrackerDriver(t, f);
      await d.initialize();
      final errors = <Object>[];
      final oldPrint = debugPrint;
      final logs = <String>[];
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };
      try {
        await t.runAsync(() async {
          final prefs = await ProfilePreferences.instance();
          await prefs.setInt(TrackingSourceStorage.watchProgressSourceKey, 7);
        });
        await d.mountHeld(secondaryScreen(simkl: false), errors: errors);
        await d.drain();
        expect(errors, [isA<TypeError>(), isA<TypeError>()]);
        expect(
          logs.where(
            (s) =>
                s.startsWith('VideoPlayer: initial open failed:') &&
                s.contains('String?'),
          ),
          hasLength(1),
        );
        expect(
          logs.where((s) => s.startsWith('[MDBListDiag] player session ready')),
          isEmpty,
        );
        expect(d.forTracker('mdblist'), isEmpty);
        expect(d.heartbeats, isEmpty);
        await t.runAsync(
          () => TrackingSourceStorage.setWatchProgressSource(
            WatchProgressSource.smart,
          ),
        );
      } finally {
        await t.runAsync(
          () => TrackingSourceStorage.setWatchProgressSource(
            WatchProgressSource.smart,
          ),
        );
        debugPrint = oldPrint;
        await d.close();
      }
    },
  );
}
