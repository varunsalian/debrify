import 'dart:async';

import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/screens/video_player/widgets/source_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/player_actions.dart';
import 'support/secondary_tracker_driver.dart';
import 'support/trakt_transport.dart';
import 'support/video_player_environment.dart';
import 'video_player_source_test.dart' show source;
import 'video_player_trakt_snapshots_test.dart'
    show traktPlaylist, traktBrowser;

void main() {
  TraktTestTransport.install();
  for (final held in ['pause', 'open']) {
    testWidgets(
      'Simkl live heartbeat during a suspended source $held rejects the paused or validation-gated renderer',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = SecondaryTrackerDriver(t, f);
        await d.initialize();
        final gate = Completer<void>();
        final a = source('Original', 'https://player.test/suspended-a.mp4');
        final b = source('Incoming', 'https://player.test/suspended-b.mp4');
        try {
          await d.mount(
            VideoPlayerScreen(
              videoUrl: a.directUrl!,
              title: 'Suspended source tracker fixture',
              contentImdbId: 'tt5100000',
              contentType: 'series',
              contentSeason: 2,
              contentEpisode: 3,
              simklScrobble: true,
              stremioSources: [a, b],
              resolveStremioSource: (s) async => s.directUrl,
            ),
          );
          await d.position(300000);
          f.player.delays[held] = gate;
          final callsBefore = f.player.calls.where((c) => c.$1 == held).length;
          playerControls(t).onShowStremioSources!();
          await f.advance(t, const Duration(milliseconds: 300));
          t
              .widget<SourceSheet>(find.byType(SourceSheet))
              .onSourceSelected(1, b.directUrl!);
          await f.until(
            t,
            () =>
                f.player.calls.where((c) => c.$1 == held).length > callsBefore,
          );
          // Native state events and command acknowledgements are independent.
          // The transition suppresses normal pause cancellation. In the open
          // case the untrusted renderer can already report playing=true.
          f.player.emit('playing', held == 'open');
          await d.drain();
          expect(d.heartbeats.where((timer) => timer.isActive), hasLength(1));
          expect(d.forTracker('simkl'), isEmpty);
          await d.tick(const Duration(minutes: 2));
          expect(d.forTracker('simkl'), isEmpty);
          expect(d.heartbeats.where((timer) => timer.isActive), hasLength(1));
          if (held == 'open') {
            f.player.emit('position', const Duration(milliseconds: 959000));
            await d.drain();
            await f.key(t, LogicalKeyboardKey.mediaFastForward);
            await d.drain();
            expect(d.seeks.last, const Duration(milliseconds: 969000));
            expect(d.forTracker('simkl'), isEmpty);
          }
          gate.complete();
          f.player.delays.remove(held);
          await d.drain();
          await d.retired();
          expect(d.heartbeats.where((timer) => timer.isActive), isEmpty);
        } finally {
          if (!gate.isCompleted) gate.complete();
          f.player.delays.remove(held);
          await d.close();
        }
      },
    );
  }

  testWidgets(
    'MDBList episode selection with newly invalid live identity exits then continues its outgoing target',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = SecondaryTrackerDriver(t, f);
      await d.initialize();
      try {
        await d.mount(
          secondaryScreen(
            simkl: false,
            playlist: traktPlaylist,
            season: 1,
            episode: 1,
          ),
        );
        await d.waitCheckpoint('mdblist', 1);
        final browser = await traktBrowser(t, f);
        await t.pumpWidget(
          MaterialApp(
            navigatorKey: f.navigator,
            home: secondaryScreen(
              simkl: false,
              id: '',
              playlist: traktPlaylist,
              season: 1,
              episode: 1,
            ),
          ),
        );
        await d.position(300000);
        Object? selectionError;
        try {
          await f.finish(t, browser.onEpisodeSelected(1, 2));
        } catch (error) {
          selectionError = error;
        }
        expect(
          selectionError,
          isNull,
          reason: 'Invalid metadata originally returns without throwing',
        );
        await d.drain();
        await d.waitCheckpoint('mdblist', 2);
        d.expectCheckpoint('mdblist', 1, 'pause', 25, season: 1, episode: 1);
        expect(f.player.calls.where((c) => c.$1 == 'open'), hasLength(2));
        expect(d.heartbeats.where((timer) => timer.isActive), hasLength(1));
        await d.tick(const Duration(minutes: 2));
        await d.waitCheckpoint('mdblist', 3);
        d.expectCheckpoint('mdblist', 2, 'pause', 0.01, season: 1, episode: 1);
      } finally {
        await d.close();
      }
    },
  );
}
