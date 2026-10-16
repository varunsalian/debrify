import 'package:media_kit/media_kit.dart' as mk;
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'support/iptv_storage_driver.dart';
import 'support/iptv_workflow_driver.dart';
import 'video_player_iptv_memory_test.dart' show iptvEpisode, iptvAudioTracks;

void main() {
  for (final disposed in [false, true]) {
    testWidgets(
      'P15 review2 final audio poll rejects stale storage reads disposed=$disposed',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        final delay = IptvAwaitDelivery(
          'applyIptvAudioPreference',
          (v) => v == null,
          skip: 19,
        );
        final series = IptvAwaitDelivery(
          'getIptvSeriesAudioLanguage',
          (v) => v is ProfilePreferences,
        )..armed = false;
        final defaults = IptvAwaitDelivery(
          'getDefaultAudioLanguage',
          (v) => v is ProfilePreferences,
        )..armed = false;
        try {
          await d.mount([iptvEpisode(1), iptvEpisode(2)]);
          final before = d.timed.length;
          await series.run(() => defaults.run(() => delay.run(() => d.zap(1))));
          for (var i = 0; i < 25 && delay.pending.isEmpty; i++) {
            await d.advance(const Duration(milliseconds: 100));
          }
          expect(delay.pending, hasLength(1));
          expect(
            d.timed
                .skip(before)
                .where(
                  (v) =>
                      d.timerOwners[v.$2]!.contains('applyIptvAudioPreference'),
                ),
            hasLength(20),
          );
          if (disposed) {
            await d.retire();
          } else {
            await d.pick([iptvChannel(90)], 0);
          }
          d.player.publishTracks(
            const mk.Tracks(
              audio: [
                mk.AudioTrack('1', 'English', 'eng'),
                mk.AudioTrack('2', 'French', 'fra'),
              ],
            ),
          );
          await d.settle();
          series.armed = true;
          defaults.armed = true;
          delay.release();
          await d.settle();
          expect(
            series.pending,
            isEmpty,
            reason: 'A disposed poll cannot start a per-series storage read',
          );
          expect(
            defaults.pending,
            isEmpty,
            reason:
                'A superseded poll cannot start a default-language storage read',
          );
          expect(d.errors, isEmpty);
        } finally {
          delay.release();
          series.release();
          defaults.release();
          await d.close();
        }
      },
    );
  }
  for (final last in [false, true]) {
    for (final disposed in [false, true]) {
      testWidgets(
        'P15 review2 audio wait rejects stale owner last=$last disposed=$disposed',
        (t) async {
          final d = IptvWorkflowDriver(t);
          await d.initialize();
          final delivery = IptvAwaitDelivery(
            'applyIptvAudioPreference',
            (v) => v == null,
            skip: last ? 19 : 0,
          );
          try {
            await d.mount([iptvEpisode(1), iptvEpisode(2)]);
            if (last) {
              iptvAudioTracks(d);
              await d.settle();
              final menu = await openPlayerMenu(t, d.f);
              await d.f.finish(t, menu.onAudioSelected('2', '1'));
              await d.settle();
            }
            d.player.publishTracks(mk.Tracks(audio: const []));
            await d.settle();
            await delivery.run(() => d.zap(1));
            for (var i = 0; i < 25 && delivery.pending.isEmpty; i++) {
              await d.advance(const Duration(milliseconds: 100));
            }
            expect(delivery.pending, hasLength(1));
            if (disposed) {
              await d.retire();
            } else {
              await d.pick([iptvChannel(90)], 0);
            }
            if (last) {
              d.player.publishTracks(
                mk.Tracks(
                  audio: const [
                    mk.AudioTrack('1', 'English', 'eng'),
                    mk.AudioTrack('2', 'French', 'fra'),
                  ],
                ),
              );
              await d.settle();
            }
            final beforeTimers = d.timed
                .where(
                  (v) =>
                      d.timerOwners[v.$2]!.contains('applyIptvAudioPreference'),
                )
                .length;
            final beforeAudio = d.calls('audio').length;
            delivery.release();
            await d.settle();
            expect(
              d.timed.where(
                (v) =>
                    d.timerOwners[v.$2]!.contains('applyIptvAudioPreference'),
              ),
              hasLength(beforeTimers),
              reason: 'A stale waiter cannot schedule another track poll',
            );
            expect(
              d.calls('audio'),
              hasLength(beforeAudio),
              reason:
                  'The last wait still validates ownership before selecting tracks',
            );
            expect(d.errors, isEmpty);
          } finally {
            delivery.release();
            for (final timer in d.timed) {
              if (d.timerOwners[timer.$2]!.contains(
                'applyIptvAudioPreference',
              )) {
                timer.$2.cancel();
              }
            }
            await d.close();
          }
        },
      );
    }
  }
}
