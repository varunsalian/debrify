import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/secondary_tracker_driver.dart';
import 'support/trakt_transport.dart';
import 'support/video_player_environment.dart';

void main() {
  TraktTestTransport.install();
  for (final movie in [false, true]) {
    testWidgets(
      'Secondary protocol ${movie ? 'movie' : 'episode'} play pause exit bodies and dedup',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = SecondaryTrackerDriver(t, f);
        await d.initialize();
        try {
          await d.mount(secondaryScreen(type: movie ? 'movie' : 'series'));
          await d.waitCheckpoint('mdblist', 1);
          expect(d.trackerActions('simkl'), isEmpty);
          d.expectCheckpoint('mdblist', 0, 'pause', 0.01, movie: movie);
          await d.position(300000);
          await d.playing(false);
          await d.waitCheckpoint('simkl', 1);
          await d.waitCheckpoint('mdblist', 2);
          d.expectCheckpoint('simkl', 0, 'pause', 25, movie: movie);
          d.expectCheckpoint('mdblist', 1, 'pause', 25, movie: movie);
          f.player.emit('playing', false);
          await d.drain();
          expect(d.trackerActions('simkl'), ['pause']);
          expect(d.trackerActions('mdblist'), ['pause', 'pause']);
          await d.position(600000);
          await d.retired();
          await d.waitCheckpoint('simkl', 2);
          await d.waitCheckpoint('mdblist', 3);
          expect(d.trackerActions('simkl'), ['pause', 'stop']);
          expect(d.trackerActions('mdblist'), ['pause', 'pause', 'pause']);
          d.expectCheckpoint('simkl', 1, 'stop', 50, movie: movie);
          d.expectCheckpoint('mdblist', 2, 'pause', 50, movie: movie);
          expect(d.heartbeats.where((timer) => timer.isActive), isEmpty);
          await d.tick(const Duration(minutes: 4));
          expect(d.forTracker('simkl'), hasLength(2));
          expect(d.forTracker('mdblist'), hasLength(3));
        } finally {
          await d.close();
        }
      },
    );
  }

  for (final percent in [80, 81]) {
    testWidgets(
      'Secondary pause at $percent preserves Simkl strict and MDBList inclusive completion thresholds',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = SecondaryTrackerDriver(t, f);
        await d.initialize();
        try {
          await d.mount(secondaryScreen());
          await d.waitCheckpoint('mdblist', 1);
          await d.position(percent * 12000);
          await d.playing(false);
          await d.waitCheckpoint('simkl', 1);
          expect(d.trackerActions('simkl'), [percent == 80 ? 'pause' : 'stop']);
          d.expectCheckpoint(
            'simkl',
            0,
            percent == 80 ? 'pause' : 'stop',
            percent.toDouble(),
          );
          // pause itself checkpoints only below 80; exit finalizes exactly 80.
          expect(d.trackerActions('mdblist'), ['pause']);
          await d.retired();
          await d.waitCheckpoint('mdblist', 2);
          expect(d.trackerActions('mdblist'), ['pause', 'stop']);
          d.expectCheckpoint('mdblist', 1, 'stop', percent.toDouble());
          expect(d.heartbeats.where((timer) => timer.isActive), isEmpty);
        } finally {
          await d.close();
        }
      },
    );
    testWidgets(
      'Secondary seek at $percent crosses tracker thresholds and seeking back rearms checkpoints',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = SecondaryTrackerDriver(t, f);
        await d.initialize();
        try {
          await d.mount(secondaryScreen());
          await d.waitCheckpoint('mdblist', 1);
          final landing = Completer<void>();
          f.player.delays['seek'] = landing;
          await d.seek(percent / 100);
          landing.complete();
          f.player.delays.remove('seek');
          await d.drain();
          if (percent == 81) await d.waitCheckpoint('simkl', 1);
          await d.waitCheckpoint('mdblist', 2);
          expect(d.trackerActions('simkl'), percent == 80 ? isEmpty : ['stop']);
          expect(d.trackerActions('mdblist'), ['pause', 'stop']);
          d.expectCheckpoint('mdblist', 1, 'stop', percent.toDouble());
          if (percent == 81) d.expectCheckpoint('simkl', 0, 'stop', 81);
          final before = d.forTracker('simkl').length;
          final reverseLanding = Completer<void>();
          f.player.delays['seek'] = reverseLanding;
          await d.seek(.25);
          reverseLanding.complete();
          f.player.delays.remove('seek');
          await d.drain();
          await d.waitCheckpoint('mdblist', 3);
          expect(d.trackerActions('mdblist'), ['pause', 'stop', 'pause']);
          d.expectCheckpoint('mdblist', 2, 'pause', 25);
          if (percent == 81) {
            await d.waitCheckpoint('simkl', before + 1);
            expect(d.trackerActions('simkl'), ['stop', 'pause']);
            d.expectCheckpoint('simkl', 1, 'pause', 25);
          } else {
            expect(d.trackerActions('simkl'), isEmpty);
          }
          await d.seek(.3);
          expect(d.forTracker('simkl'), hasLength(percent == 81 ? 2 : 0));
          expect(d.forTracker('mdblist'), hasLength(3));
          await d.playing(false);
          await d.playing(true);
          await d.position(600000);
          final simklBefore = d.forTracker('simkl').length;
          final mdblistBefore = d.forTracker('mdblist').length;
          await d.tick(const Duration(seconds: 119));
          expect(d.forTracker('simkl'), hasLength(simklBefore));
          expect(d.forTracker('mdblist'), hasLength(mdblistBefore));
          await d.tick(const Duration(seconds: 1));
          await d.waitCheckpoint('simkl', simklBefore + 1);
          await d.waitCheckpoint('mdblist', mdblistBefore + 1);
          d.expectCheckpoint('simkl', simklBefore, 'pause', 50);
          d.expectCheckpoint('mdblist', mdblistBefore, 'pause', 50);
          await d.position(720000);
          await d.playing(false);
          await d.waitCheckpoint('simkl', simklBefore + 2);
          d.expectCheckpoint('simkl', simklBefore + 1, 'pause', 60);
          expect(d.heartbeats.where((timer) => timer.isActive), isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }

  for (final percent in [80, 81]) {
    testWidgets(
      'Secondary landed slider $percent keeps original MDBList crossing silence until exit',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = SecondaryTrackerDriver(t, f);
        await d.initialize();
        try {
          await d.mount(secondaryScreen());
          await d.waitCheckpoint('mdblist', 1);
          await d.seek(percent / 100);
          expect(d.trackerActions('mdblist'), ['pause']);
          expect(d.trackerActions('simkl'), percent == 80 ? isEmpty : ['stop']);
          await d.retired();
          await d.waitCheckpoint('mdblist', 2);
          d.expectCheckpoint('mdblist', 1, 'stop', percent.toDouble());
        } finally {
          await d.close();
        }
      },
    );
  }

  for (final failure in ['status', 'throw', 'held']) {
    testWidgets(
      'Secondary failed $failure checkpoint retains original tracker dedup before and after reply',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = SecondaryTrackerDriver(t, f);
        await d.initialize();
        final reply = Completer<http.Response>();
        try {
          await d.mount(secondaryScreen());
          await d.waitCheckpoint('mdblist', 1);
          f.network.handler = (r) {
            if (!r.url.path.startsWith('/scrobble/')) return secondaryReply(r);
            if (failure == 'held') return reply.future;
            if (failure == 'throw') {
              throw http.ClientException('synthetic failure');
            }
            return http.Response('{}', 503);
          };
          await d.position(300000);
          await d.playing(false);
          await d.waitCheckpoint('simkl', 1);
          await d.waitCheckpoint('mdblist', 2);
          f.player.emit('playing', false);
          await d.drain();
          expect(d.trackerActions('simkl'), ['pause']);
          expect(d.trackerActions('mdblist'), ['pause', 'pause']);
          if (!reply.isCompleted) reply.complete(http.Response('{}', 503));
          await d.drain();
          await d.playing(true);
          await d.playing(false);
          await d.waitCheckpoint('simkl', 2);
          expect(d.trackerActions('simkl'), ['pause', 'pause']);
          // The failed MDBList checkpoint still spent its rounded-position dedup.
          expect(d.trackerActions('mdblist'), ['pause', 'pause']);
        } finally {
          if (!reply.isCompleted) reply.complete(http.Response('{}', 503));
          await d.close();
        }
      },
    );
  }
}
