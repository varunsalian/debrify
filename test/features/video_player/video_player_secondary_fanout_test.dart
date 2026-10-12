import 'dart:async';

import 'package:debrify/models/tracking_source.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/secondary_tracker_driver.dart';
import 'support/trakt_transport.dart';
import 'support/video_player_environment.dart';

void main() {
  TraktTestTransport.install();
  for (final event in ['pause', 'seek', 'EOF', 'dispose']) {
    testWidgets(
      'Secondary all-tracker $event fanout preserves ordered timer ownership and tracker-specific payloads',
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
        final tagged = <(String, int)>[];
        final oldPrint = debugPrint;
        try {
          await d.mount(secondaryScreen(trakt: true));
          await d.waitCheckpoint('trakt', 1);
          await d.waitCheckpoint('mdblist', 1);
          await d.playing(false);
          await d.position(300000);
          final first = d.heartbeats.length;
          await d.playing(true);
          await d.waitCheckpoint('mdblist', 2);
          expect(d.heartbeats.length, first + 3);
          expect(d.heartbeats.skip(first).every((t) => t.isActive), isTrue);
          debugPrint = (String? message, {int? wrapWidth}) {
            final tag = Zone.current[SecondaryTrackerDriver.timerTag];
            if (tag is int && message != null) {
              if (message.startsWith('Trakt: Heartbeat')) {
                tagged.add(('api.trakt.tv', tag));
              }
              if (message.startsWith('Simkl: Heartbeat')) {
                tagged.add(('api.simkl.com', tag));
              }
              if (message.startsWith('[MDBListDiag] scrobble queued')) {
                tagged.add(('api.mdblist.com', tag));
              }
            }
            oldPrint(message, wrapWidth: wrapWidth);
          };
          await d.position(600000);
          await d.tick(const Duration(seconds: 119));
          expect(tagged, isEmpty);
          await d.tick(const Duration(seconds: 1));
          await f.until(t, () => tagged.length == 3);
          await d.waitCheckpoint('trakt', 4);
          await d.waitCheckpoint('simkl', 2);
          await d.waitCheckpoint('mdblist', 3);
          tagged.sort((a, b) => a.$2.compareTo(b.$2));
          expect(tagged, [
            ('api.trakt.tv', first),
            ('api.simkl.com', first + 1),
            ('api.mdblist.com', first + 2),
          ]);
          d.expectRequest(d.requests.length - 1, 'start', 50);
          d.expectCheckpoint(
            'simkl',
            d.forTracker('simkl').length - 1,
            'pause',
            50,
          );
          d.expectCheckpoint(
            'mdblist',
            d.forTracker('mdblist').length - 1,
            'pause',
            50,
          );
          d.cancellations.clear();
          final traktBefore = d.requests.length;
          final simklBefore = d.forTracker('simkl').length;
          final mdblistBefore = d.forTracker('mdblist').length;
          await d.position(720000);
          if (event == 'pause') await d.playing(false);
          if (event == 'seek') await d.seekBeforeLanding(.81);
          if (event == 'EOF') {
            f.player.emit('completed', true);
            await d.drain();
          }
          if (event == 'dispose') await d.retired();
          await d.waitCheckpoint('trakt', traktBefore + 1);
          await d.waitCheckpoint('simkl', simklBefore + 1);
          await d.waitCheckpoint('mdblist', mdblistBefore + 1);
          expect(d.cancellations, [first, first + 1, first + 2]);
          expect(d.heartbeats.where((t) => t.isActive), isEmpty);
          final percent = event == 'seek' ? 81.0 : 60.0;
          d.expectRequest(
            traktBefore,
            event == 'pause' ? 'pause' : 'stop',
            percent,
          );
          d.expectCheckpoint(
            'simkl',
            simklBefore,
            event == 'pause' ? 'pause' : 'stop',
            percent,
          );
          d.expectCheckpoint(
            'mdblist',
            mdblistBefore,
            ['seek', 'EOF'].contains(event) ? 'stop' : 'pause',
            event == 'EOF' ? 100 : percent,
          );
          await d.tick(const Duration(minutes: 4));
          expect(d.requests, hasLength(traktBefore + 1));
          expect(d.forTracker('simkl'), hasLength(simklBefore + 1));
          expect(d.forTracker('mdblist'), hasLength(mdblistBefore + 1));
        } finally {
          debugPrint = oldPrint;
          await d.close();
        }
      },
    );
  }
}
