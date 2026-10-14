import 'dart:async';

import 'package:debrify/services/storage/track_preferences_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;

import 'support/subtitle_apply_driver.dart';
import 'support/player_actions.dart';
import 'support/vp_fixture_actions.dart';
import 'video_player_subtitle_apply_boundaries_test.dart' show boundaryScreen;

class TrackPoll {
  bool armed = true;
  int scheduled = 0;
  final pending = <void Function()>[];
  T run<T>(T Function() action) => runZoned(
    action,
    zoneSpecification: ZoneSpecification(
      createTimer: (self, parent, zone, duration, callback) {
        if (armed &&
            duration == const Duration(milliseconds: 100) &&
            StackTrace.current.toString().contains('waitForSubtitleTracks')) {
          scheduled++;
          return parent.createTimer(
            zone,
            duration,
            () => pending.add(
              VpFixtureActions.heldCallback('subtitle track poll', callback),
            ),
          );
        }
        return parent.createTimer(zone, duration, callback);
      },
    ),
  );
  void release() {
    final callbacks = List<void Function()>.of(pending);
    pending.clear();
    for (final callback in callbacks) {
      callback();
    }
  }
}

void main() {
  for (final arrival in [false, true]) {
    testWidgets(
      'subtitle track polling ${arrival ? 'accepts a real arrival' : 'times out at exactly fifty polls'} while ignoring placeholders',
      (t) async {
        final d = SubtitleApplyDriver(
          t,
          configurePlayer: (p) {
            p.state = p.state.copyWith(
              tracks: mk.Tracks(
                subtitle: [
                  mk.SubtitleTrack.auto(),
                  mk.SubtitleTrack.no(),
                  const mk.SubtitleTrack('', 'Empty', 'eng'),
                ],
              ),
            );
          },
        );
        await d.initialize();
        final held = TrackPoll();
        try {
          await d.f.finish(
            t,
            TrackPreferencesStorage.saveVideoTrackPreferences(
              videoTitle: applyScreen.title,
              audioTrackId: '1',
              subtitleTrackId: '2',
            ),
          );
          await held.run(
            () => d.mount(publishTracks: false, settleInitialization: false),
          );
          await d.f.until(t, () => held.pending.isNotEmpty);
          expect(held.scheduled, 1);
          expect(d.logs.where((v) => v.contains('restore start')), isEmpty);
          expect(d.player.calls.where((v) => v.$1 == 'subtitle'), isEmpty);
          if (arrival) {
            d.publish();
            held.release();
            await d.f.until(t, () => d.player.state.track.subtitle.id == '2');
            await d.f.actions.settle(t);
            expect(held.scheduled, 1);
            expect(
              d.logs.where(
                (v) => v.contains('applying STORED subtitle track id=2'),
              ),
              hasLength(1),
            );
          } else {
            for (var poll = 1; poll <= 50; poll++) {
              expect(held.scheduled, poll);
              expect(d.logs.where((v) => v.contains('restore start')), isEmpty);
              held.release();
              if (poll < 50) await d.f.until(t, () => held.pending.isNotEmpty);
            }
            await d.f.until(
              t,
              () => d.logs.any((v) => v.contains('restore start')),
            );
            expect(held.scheduled, 50);
            expect(
              d.player.calls.where(
                (v) =>
                    v.$1 == 'subtitle' && (v.$2 as mk.SubtitleTrack).id == '2',
              ),
              isEmpty,
            );
            expect(
              d.logs.where(
                (v) => v.contains('stored subtitle id=2 not in this file'),
              ),
              hasLength(1),
            );
          }
          expect(d.errors, isEmpty);
        } finally {
          held.armed = false;
          held.release();
          await d.close();
        }
      },
    );
  }
  testWidgets(
    'subtitle old track poll stops on content token change before touching incoming preferences',
    (t) async {
      final d = SubtitleApplyDriver(
        t,
        configurePlayer: (p) {
          p.state = p.state.copyWith(
            tracks: mk.Tracks(
              subtitle: [mk.SubtitleTrack.auto(), mk.SubtitleTrack.no()],
            ),
          );
        },
      );
      await d.initialize();
      final held = TrackPoll();
      try {
        await held.run(
          () => d.mount(
            screen: boundaryScreen,
            publishTracks: false,
            settleInitialization: false,
          ),
        );
        await d.f.until(t, () => held.pending.isNotEmpty);
        expect(held.scheduled, 1);
        final dynamic next = playerControls(t).onNext;
        final Future<dynamic> switched = d.observe<dynamic>(() => next());
        await d.f.until(
          t,
          () => d.player.calls.where((v) => v.$1 == 'open').length == 2,
        );
        expect(held.pending, hasLength(1));
        held.armed = false;
        held.release();
        d.publish();
        await d.f.finish(t, switched);
        await d.f.until(
          t,
          () =>
              d.logs.any((v) => v.contains('restore aborted after track wait')),
        );
        expect(held.scheduled, 1);
        expect(d.errors, isEmpty);
      } finally {
        held.armed = false;
        held.release();
        await d.close();
      }
    },
  );
}
