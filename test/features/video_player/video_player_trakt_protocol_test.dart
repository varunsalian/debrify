import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/trakt_player_driver.dart';
import 'support/trakt_transport.dart';
import 'support/video_player_environment.dart';

void main() {
  TraktTestTransport.install();
  testWidgets(
    'Trakt seek rearms heartbeat and restores start dedup after a watched stop',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = TraktPlayerDriver(t, f);
      await d.initialize();
      try {
        await d.mount(traktScreen());
        await d.seek(.81);
        expect(d.actions, ['start', 'stop']);
        expect(d.heartbeats.where((timer) => timer.isActive), isEmpty);
        await d.seek(.25);
        expect(d.actions, ['start', 'stop', 'start']);
        expect(d.heartbeats.where((timer) => timer.isActive), hasLength(1));
        await d.playing(true);
        expect(d.actions, ['start', 'stop', 'start']);
        await f.advance(t, const Duration(minutes: 2));
        await d.drain();
        expect(d.actions, ['start', 'stop', 'start', 'start']);
        d.expectRequest(3, 'start', 25);
      } finally {
        await d.close();
      }
    },
  );

  for (final movie in [false, true]) {
    testWidgets(
      'Trakt protocol ${movie ? 'movie' : 'episode'} start pause stop bodies and duplicate edges',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = TraktPlayerDriver(t, f);
        await d.initialize();
        try {
          await d.mount(traktScreen(type: movie ? 'movie' : 'series'));
          await d.drain();
          expect(d.actions, ['start']);
          d.expectRequest(0, 'start', 80 / 1200000 * 100, movie: movie);
          f.player.emit('playing', true);
          await d.drain();
          expect(d.actions, ['start']);
          await d.position(300000);
          await d.playing(false);
          expect(d.actions, ['start', 'pause']);
          d.expectRequest(1, 'pause', 25, movie: movie);
          f.player.emit('playing', false);
          await d.drain();
          expect(d.actions, ['start', 'pause']);
          await t.pumpWidget(const SizedBox.shrink());
          await d.drain();
          expect(d.actions, ['start', 'pause', 'stop']);
          d.expectRequest(2, 'stop', 25, movie: movie);
        } finally {
          await d.close();
        }
      },
    );
  }

  for (final percent in [80, 81]) {
    testWidgets(
      'Trakt pause transition at $percent percent keeps strict watched threshold',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = TraktPlayerDriver(t, f);
        await d.initialize();
        try {
          await d.mount(traktScreen());
          await d.position(percent * 12000);
          await d.playing(false);
          expect(d.actions, ['start', percent == 80 ? 'pause' : 'stop']);
          d.expectRequest(
            1,
            percent == 80 ? 'pause' : 'stop',
            percent.toDouble(),
          );
        } finally {
          await d.close();
        }
      },
    );
    testWidgets(
      'Trakt playing transition at $percent percent keeps strict watched threshold',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = TraktPlayerDriver(t, f);
        await d.initialize();
        try {
          await d.mount(traktScreen());
          await d.playing(false);
          await d.position(percent * 12000);
          await d.playing(true);
          expect(d.actions, [
            'start',
            'pause',
            percent == 80 ? 'start' : 'stop',
          ]);
          d.expectRequest(
            2,
            percent == 80 ? 'start' : 'stop',
            percent.toDouble(),
          );
          await d.playing(false);
          expect(
            d.actions,
            percent == 80
                ? ['start', 'pause', 'start', 'pause']
                : ['start', 'pause', 'stop'],
          );
        } finally {
          await d.close();
        }
      },
    );
    testWidgets(
      'Trakt user seek at $percent percent bypasses dedup and owns heartbeat',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = TraktPlayerDriver(t, f);
        await d.initialize();
        try {
          await d.mount(traktScreen());
          await d.seek(percent / 100);
          expect(d.actions, ['start', percent == 80 ? 'start' : 'stop']);
          d.expectRequest(
            1,
            percent == 80 ? 'start' : 'stop',
            percent.toDouble(),
          );
          await f.advance(t, const Duration(minutes: 2));
          await d.drain();
          expect(
            d.actions,
            percent == 80 ? ['start', 'start', 'start'] : ['start', 'stop'],
          );
          if (percent == 80) d.expectRequest(2, 'start', 80);
          if (percent == 81) {
            await d.playing(false);
            expect(d.actions, ['start', 'stop']);
          }
        } finally {
          await d.close();
        }
      },
    );
  }

  testWidgets(
    'Trakt heartbeat interval replaces previous timer bypasses dedup then stops above eighty',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = TraktPlayerDriver(t, f);
      await d.initialize();
      final oldPrint = debugPrint;
      final logs = <String>[];
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };
      try {
        await d.mount(traktScreen());
        await d.position(960000);
        await f.advance(t, const Duration(seconds: 110));
        f.player.emit('playing', true);
        await d.drain();
        await f.advance(t, const Duration(seconds: 119));
        await d.drain();
        expect(d.actions, ['start']);
        await f.advance(t, const Duration(seconds: 1));
        await d.drain();
        expect(d.actions, ['start', 'start']);
        d.expectRequest(1, 'start', 80);
        expect(logs, contains('Trakt: Heartbeat scrobble at 80.0%'));
        await d.position(972000);
        await f.advance(t, const Duration(minutes: 2));
        await d.drain();
        expect(d.actions, ['start', 'start', 'stop']);
        expect(d.heartbeats.where((timer) => timer.isActive), isEmpty);
        await d.playing(false);
        expect(d.actions, ['start', 'start', 'stop']);
        d.expectRequest(2, 'stop', 81);
        expect(logs, contains('Trakt: Heartbeat stop at 81.0% (>80%)'));
        await f.advance(t, const Duration(minutes: 4));
        await d.drain();
        expect(d.actions, ['start', 'start', 'stop']);
      } finally {
        debugPrint = oldPrint;
        await d.close();
      }
    },
  );

  for (final exit in ['pause', 'EOF', 'dispose']) {
    testWidgets('Trakt $exit cancels the heartbeat with exact final event', (
      t,
    ) async {
      final f = VideoPlayerEnvironment();
      final d = TraktPlayerDriver(t, f);
      await d.initialize();
      try {
        await d.mount(traktScreen());
        await d.position(600000);
        if (exit == 'pause') await d.playing(false);
        if (exit == 'EOF') {
          f.player.emit('completed', true);
          await d.drain();
        }
        if (exit == 'dispose') {
          await t.pumpWidget(const SizedBox.shrink());
          await d.drain();
        }
        expect(d.actions, ['start', exit == 'pause' ? 'pause' : 'stop']);
        expect(d.heartbeats, isNotEmpty);
        expect(d.heartbeats.where((timer) => timer.isActive), isEmpty);
        d.expectRequest(1, exit == 'pause' ? 'pause' : 'stop', 50);
        await f.advance(t, const Duration(minutes: 4));
        await d.drain();
        expect(d.actions, ['start', exit == 'pause' ? 'pause' : 'stop']);
      } finally {
        await d.close();
      }
    });
  }

  testWidgets(
    'Trakt heartbeat restores start dedup after an implicit stop with a live timer',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = TraktPlayerDriver(t, f);
      await d.initialize();
      try {
        await d.mount(traktScreen());
        await d.position(972000);
        await d.playing(true);
        expect(d.actions, ['start', 'stop']);
        await d.position(300000);
        await f.advance(t, const Duration(minutes: 2));
        await d.drain();
        expect(d.actions, ['start', 'stop', 'start']);
        d.expectRequest(2, 'start', 25);
        await d.playing(true);
        expect(d.actions, ['start', 'stop', 'start']);
      } finally {
        await d.close();
      }
    },
  );

  for (final failure in ['status', 'throw', 'held']) {
    testWidgets(
      'Trakt failed $failure send spends dedup before completion and seek retries',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = TraktPlayerDriver(t, f);
        await d.initialize();
        final reply = Completer<http.Response>();
        try {
          f.network.handler = (r) {
            if (!r.url.path.startsWith('/scrobble/')) return traktReply(r);
            if (failure == 'held') return reply.future;
            if (failure == 'throw') {
              throw http.ClientException('synthetic failure');
            }
            return http.Response('{}', 503);
          };
          await d.mount(traktScreen());
          await d.drain();
          expect(d.actions, ['start']);
          f.player.emit('playing', true);
          await d.drain();
          expect(d.actions, ['start']);
          await d.seek(.25);
          expect(d.actions, ['start', 'start']);
          d.expectRequest(1, 'start', 25);
          if (!reply.isCompleted) reply.complete(http.Response('{}', 503));
          await d.drain();
          f.player.emit('playing', true);
          await d.drain();
          expect(d.actions, ['start', 'start']);
          await d.playing(false);
          expect(d.actions, ['start', 'start', 'pause']);
        } finally {
          if (!reply.isCompleted) reply.complete(http.Response('{}', 503));
          await d.close();
        }
      },
    );
  }
}
