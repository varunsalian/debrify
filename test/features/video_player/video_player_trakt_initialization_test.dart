import 'dart:async';

import 'package:debrify/models/custom_series_identity.dart';
import 'package:debrify/services/profiles/connection_resource_service.dart';
import 'package:debrify/services/storage/trakt_storage.dart';
import 'package:debrify/services/storage/tracking_source_storage.dart';
import 'package:debrify/models/tracking_source.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/trakt_player_driver.dart';
import 'support/trakt_transport.dart';
import 'support/video_player_environment.dart';
import 'video_player_skip_races_test.dart' show incomingProfile;

void main() {
  TraktTestTransport.install();
  for (final gate in [
    'flag',
    'identity',
    'type',
    'target',
    'credential',
    'custom',
    'coordinates',
  ]) {
    testWidgets(
      'Trakt initialization $gate gate prevents play seek heartbeat and dispose sends',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = TraktPlayerDriver(t, f);
        await d.initialize(target: gate != 'target');
        final oldPrint = debugPrint;
        final diagnostics = <String>[];
        final timers = <Timer>[];
        debugPrint = (String? message, {int? wrapWidth}) {
          if (message != null) diagnostics.add(message);
        };
        try {
          if (gate == 'credential') {
            await t.runAsync(TraktStorage.clearTraktAuth);
            await t.runAsync(
              () => TrackingSourceStorage.setTrackingScrobbleTargets({
                TrackingSource.trakt,
              }),
            );
          }
          await runZoned(
            () => f.mount(
              t,
              traktScreen(
                enabled: gate != 'flag',
                id: gate == 'identity'
                    ? null
                    : gate == 'custom'
                    ? const CustomSeriesIdentity('fixture', 'trakt').id
                    : 'tt5100000',
                type: gate == 'type' ? 'channel' : 'series',
                season: gate == 'coordinates' ? null : 2,
                episode: gate == 'coordinates' ? null : 3,
              ),
            ),
            zoneSpecification: ZoneSpecification(
              createPeriodicTimer: (self, parent, zone, duration, callback) {
                final timer = parent.createPeriodicTimer(
                  zone,
                  duration,
                  callback,
                );
                if (duration == const Duration(minutes: 2)) timers.add(timer);
                return timer;
              },
            ),
          );
          await d.drain();
          await d.playing(false);
          await d.playing(true);
          await d.seek(.25);
          await f.advance(t, const Duration(minutes: 2));
          await d.drain();
          expect(d.requests, isEmpty);
          expect(timers.where((timer) => timer.isActive), isEmpty);
          expect(
            diagnostics.where(
              (s) => s.startsWith('VideoPlayer: initial open failed:'),
            ),
            isEmpty,
          );
          if (gate == 'credential') {
            await t.runAsync(
              () => TraktStorage.setTraktSession(
                accessToken: 'vplayer-synthetic-access',
                refreshToken: 'vplayer-synthetic-refresh',
                expiryMs: 4102444800000,
              ),
            );
            await d.seek(.3);
            expect(d.requests, isEmpty);
          }
          await t.pumpWidget(const SizedBox.shrink());
          await d.drain();
          expect(d.requests, isEmpty);
          if (['flag', 'identity', 'type', 'target', 'custom'].contains(gate)) {
            expect(d.cipher.opens, 0);
          }
        } finally {
          debugPrint = oldPrint;
          await d.close();
        }
      },
    );
  }

  for (final edge in ['playing', 'paused', 'duration']) {
    testWidgets(
      'Trakt held auth initialization $edge completion samples live state',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = TraktPlayerDriver(t, f);
        await d.initialize();
        final errors = <Object>[];
        try {
          d.cipher.hold = true;
          await runZonedGuarded(
            () => f.mount(t, traktScreen()),
            (e, s) => errors.add(e),
          );
          expect(d.cipher.held, isNotEmpty);
          expect(d.requests, isEmpty);
          if (edge == 'paused') await d.playing(false);
          if (edge == 'duration') {
            f.player.emit('duration', Duration.zero);
            await f.advance(t);
          }
          // This early user event must neither send nor install a heartbeat
          // while the original false enable initializer is still in force.
          await d.seek(.25);
          expect(d.cipher.held, hasLength(1));
          d.cipher.releaseAll();
          await d.drain();
          expect(errors, isEmpty);
          expect(d.actions, edge == 'playing' ? ['start'] : isEmpty);
          if (edge == 'playing') d.expectRequest(0, 'start', 25);
          await f.advance(t, const Duration(minutes: 2));
          await d.drain();
          expect(d.actions, edge == 'playing' ? ['start', 'start'] : isEmpty);
          if (edge != 'playing') {
            f.player.emit('duration', const Duration(minutes: 20));
            await f.advance(t);
            await d.playing(true);
            expect(d.actions, ['start']);
          }
        } finally {
          await d.close();
        }
      },
    );
  }

  testWidgets(
    'Trakt held auth completion above eighty sends stop without arming heartbeat',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = TraktPlayerDriver(t, f);
      await d.initialize();
      final errors = <Object>[];
      final timers = <Timer>[];
      try {
        d.cipher.hold = true;
        await runZoned(
          () => f.mount(t, traktScreen()),
          zoneSpecification: ZoneSpecification(
            handleUncaughtError: (self, parent, zone, error, stack) {
              errors.add(error);
            },
            createPeriodicTimer: (self, parent, zone, duration, callback) {
              final timer = parent.createPeriodicTimer(
                zone,
                duration,
                callback,
              );
              if (duration == const Duration(minutes: 2)) timers.add(timer);
              return timer;
            },
          ),
        );
        expect(d.cipher.held, isNotEmpty);
        await d.seek(.81);
        expect(d.requests, isEmpty);
        d.cipher.releaseAll();
        await d.drain();
        expect(errors, isEmpty);
        expect(d.actions, ['stop']);
        d.expectRequest(0, 'stop', 81);
        expect(timers, isEmpty);
        await f.advance(t, const Duration(minutes: 2));
        await d.drain();
        expect(d.actions, ['stop']);
      } finally {
        await d.close();
      }
    },
  );

  for (final retire in ['dispose', 'profile']) {
    testWidgets(
      'Trakt held initialization $retire completion has no outgoing send',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = TraktPlayerDriver(t, f);
        await d.initialize();
        final errors = <Object>[];
        try {
          d.cipher.hold = true;
          await runZonedGuarded(
            () => f.mount(t, traktScreen()),
            (e, s) => errors.add(e),
          );
          expect(d.cipher.held, isNotEmpty);
          if (retire == 'dispose') {
            await t.pumpWidget(const SizedBox.shrink());
            await d.drain();
          } else {
            await incomingProfile(t, f);
          }
          d.cipher.releaseAll();
          await d.drain();
          expect(
            errors,
            retire == 'profile'
                ? [isA<ResourceAuthorizationException>()]
                : isEmpty,
          );
          expect(d.actions, isEmpty);
          await f.advance(t, const Duration(minutes: 2));
          await d.drain();
          expect(d.actions, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }

  testWidgets(
    'Trakt auth storage failure escapes initialization without enabling sends',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = TraktPlayerDriver(t, f);
      await d.initialize();
      final errors = <Object>[];
      final failure = StateError('synthetic auth storage failure');
      try {
        d.cipher.hold = true;
        await runZonedGuarded(
          () => f.mount(t, traktScreen()),
          (e, s) => errors.add(e),
        );
        expect(d.cipher.held, isNotEmpty);
        d.cipher.failure = failure;
        d.cipher.releaseAll();
        await d.drain();
        expect(errors, contains(same(failure)));
        expect(d.requests, isEmpty);
        d.cipher.failure = null;
        await d.playing(false);
        await d.playing(true);
        expect(d.requests, isEmpty);
      } finally {
        d.cipher.failure = null;
        await d.close();
      }
    },
  );

  testWidgets(
    'Trakt seek samples target clamps progress and rejects paused or unknown duration',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = TraktPlayerDriver(t, f);
      await d.initialize();
      try {
        await d.mount(traktScreen());
        await d.seek(-.1);
        d.expectRequest(1, 'start', 0);
        await d.seek(1.2);
        d.expectRequest(2, 'stop', 100);
        await d.playing(false);
        await d.seek(.25);
        expect(d.actions, ['start', 'start', 'stop']);
        await d.playing(true);
        final before = d.requests.length;
        f.player.emit('duration', Duration.zero);
        await f.advance(t);
        await d.seek(.5);
        expect(d.requests, hasLength(before));
      } finally {
        await d.close();
      }
    },
  );
}
