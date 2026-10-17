import 'support/local_completion_driver.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Existing resolved preference transport.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'support/iptv_storage_driver.dart';
import 'package:debrify/services/storage/iptv_audio_storage.dart';
import 'package:debrify/services/storage/iptv_history_storage.dart';
import 'package:debrify/services/storage/iptv_last_channel_storage.dart';
import 'package:debrify/services/storage/subtitle_settings_storage.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'dart:async';
import 'support/iptv_workflow_driver.dart';

IptvChannel iptvEpisode(
  int episode, {
  String? series = 'series',
  String playlist = 'provider',
}) => iptvChannel(
  episode,
  live: false,
  attributes: {
    if (series != null) 'series_id': series,
    'series_playlist_id': playlist,
    'series_name': 'P15 show',
    'season': '2',
    'episode': '$episode',
    'has_next_episode': 'true',
  },
);
void iptvAudioTracks(IptvWorkflowDriver d) => d.player.publishTracks(
  const mk.Tracks(
    audio: [
      mk.AudioTrack('auto', null, null),
      mk.AudioTrack('no', null, null),
      mk.AudioTrack('1', 'English', 'eng'),
      mk.AudioTrack('2', 'French', 'fra'),
    ],
    subtitle: [mk.SubtitleTrack('1', 'English', 'eng')],
  ),
);

void main() {
  for (final preference in ['session', 'stored', 'default', 'none']) {
    testWidgets(
      'P15 series audio precedence $preference and history attributes',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        final a = [iptvEpisode(1), iptvEpisode(2)];
        try {
          if (preference == 'stored') {
            await d.f.finish(
              t,
              IptvAudioStorage.setIptvSeriesAudioLanguage(
                'provider::series',
                'fra',
              ),
            );
          }
          if (preference == 'default') {
            await d.f.finish(
              t,
              SubtitleSettingsStorage.setDefaultAudioLanguage('fra'),
            );
          }
          await d.mount(a);
          iptvAudioTracks(d);
          await d.settle();
          if (preference == 'session') {
            final m = await openPlayerMenu(t, d.f);
            await d.f.finish(t, m.onAudioSelected('2', '1'));
            m.onClose();
            await d.settle();
          }
          final before = d.calls('audio').length;
          await d.zap(1);
          await d.settle();
          if (preference == 'none') {
            expect(d.calls('audio').length, before);
          } else {
            expect(d.player.state.track.audio.id, '2');
          }
          final rows = await d.f.finish(
            t,
            IptvHistoryStorage.getIptvWatchHistory(),
          );
          expect(rows, contains(a[1].url));
          final row = rows[a[1].url]!;
          expect(row['playlistId'], 'provider');
          expect(row['seriesId'], 'series');
          expect(row['seriesName'], 'P15 show');
          expect(row['season'], 2);
          expect(row['episode'], 2);
          expect(row['hasNext'], true);
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
  for (final language in [null, '', 'auto', 'und', 'fra']) {
    testWidgets(
      'P15 audio capture accepts only meaningful series language $language',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        try {
          await d.mount([iptvEpisode(1)]);
          d.player.publishTracks(
            mk.Tracks(audio: [mk.AudioTrack('1', 'Chosen', language)]),
          );
          await d.settle();
          final m = await openPlayerMenu(t, d.f);
          await d.f.finish(t, m.onAudioSelected('1', 'no'));
          await d.settle();
          expect(
            await d.f.finish(
              t,
              IptvAudioStorage.getIptvSeriesAudioLanguage('provider::series'),
            ),
            language == 'fra' ? 'fra' : isNull,
          );
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
  for (final context in ['live', 'movie', 'series']) {
    testWidgets(
      'P15 audio capture is series-only context=$context and skips unchanged writes',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        final previousStore = SharedPreferencesStorePlatform.instance;
        final writes = (await t.runAsync(IptvPreferenceWrites.install))!;
        int audioWrites() => writes.writes
            .where((v) => v.$1.endsWith('iptv_series_audio_lang'))
            .length;
        final channel = context == 'series'
            ? iptvEpisode(1)
            : iptvChannel(0, live: context == 'live');
        try {
          await d.f.finish(
            t,
            SubtitleSettingsStorage.setDefaultAudioLanguage('eng'),
          );
          await d.mount([channel]);
          iptvAudioTracks(d);
          await d.settle();
          final m = await openPlayerMenu(t, d.f);
          await d.f.finish(t, m.onAudioSelected('2', '1'));
          await d.settle();
          final first = await d.f.finish(
            t,
            IptvAudioStorage.getIptvSeriesAudioLanguage('provider::series'),
          );
          expect(first, context == 'series' ? 'fra' : isNull);
          expect(audioWrites(), context == 'series' ? 1 : 0);
          await d.f.finish(t, m.onAudioSelected('2', '1'));
          await d.settle();
          expect(
            await d.f.finish(
              t,
              IptvAudioStorage.getIptvSeriesAudioLanguage('provider::series'),
            ),
            first,
          );
          expect(audioWrites(), context == 'series' ? 1 : 0);
          if (context != 'series') {
            await d.pick([iptvEpisode(2)], 0);
            await d.settle();
            expect(d.player.state.track.audio.id, '1');
          }
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
          SharedPreferencesStorePlatform.instance = previousStore;
          SharedPreferences.resetStatic();
        }
      },
    );
  }
  for (final outcome in [
    'tracks-arrive',
    'no-tracks',
    'new-ticket',
    'dispose',
    'manual',
  ]) {
    testWidgets(
      'P15 audio 20x100ms wait $outcome pins selection and abandonment',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        final audioWait = CompletionDelivery(
          'applyIptvAudioPreference',
          (v) => v == null,
        )..armed = outcome == 'manual';
        final a = [iptvEpisode(1), iptvEpisode(2), iptvEpisode(3)];
        try {
          await d.f.finish(
            t,
            IptvAudioStorage.setIptvSeriesAudioLanguage(
              'provider::series',
              'eng',
            ),
          );
          await d.mount(a);
          final before = d.calls('audio').length;
          await audioWait.run(() => d.zap(1));
          if (outcome == 'manual') {
            await d.f.until(t, () => audioWait.pending.isNotEmpty);
          }
          if (outcome == 'dispose') {
            await d.retire();
          }
          if (outcome == 'new-ticket') {
            await d.zap(1);
          }
          if (outcome == 'tracks-arrive' ||
              outcome == 'new-ticket' ||
              outcome == 'manual') {
            iptvAudioTracks(d);
            if (outcome == 'manual') {
              final m = await openPlayerMenu(t, d.f);
              await d.f.finish(t, m.onAudioSelected('2', '1'));
              audioWait.release();
            }
          }
          await d.advance(const Duration(seconds: 3));
          await d.settle();
          if (outcome == 'no-tracks' || outcome == 'dispose') {
            expect(d.calls('audio').length, before);
          } else {
            expect(
              d.player.state.track.audio.id,
              outcome == 'manual' ? '2' : '1',
            );
          }
          expect(d.errors, isEmpty);
        } finally {
          audioWait.release();
          await d.close();
        }
      },
    );
  }
  testWidgets(
    'P15 last-live same URL does not rearm the one-second settle timer',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final live = iptvChannel(0, attributes: {'source_playlist_id': 'origin'});
      try {
        await d.mount([live]);
        await d.f.finish(t, IptvLastChannelStorage.clearIptvLastLiveChannel());
        d.observe(() => d.player.emit('playing', true));
        await d.f.advance(t);
        expect(
          d.timed.where((v) => v.$1 == const Duration(seconds: 1)),
          isNotEmpty,
        );
        final timer = d.timed
            .lastWhere((v) => v.$1 == const Duration(seconds: 1))
            .$2;
        await d.advance(const Duration(milliseconds: 800));
        d.player.emit('playing', true);
        await d.f.advance(t);
        expect(timer.isActive, true);
        expect(
          await d.f.finish(t, IptvLastChannelStorage.getIptvLastLiveChannel()),
          isNull,
        );
        await d.advance(const Duration(milliseconds: 200));
        final prefs = await d.f.finish(t, ProfilePreferences.instance());
        await d.f.until(t, () => prefs.containsKey('iptv_last_live_channel'));
        final row = await d.f.finish(
          t,
          IptvLastChannelStorage.getIptvLastLiveChannel(),
        );
        expect(row, isNotNull);
        expect(row!['url'], live.url);
        expect(row['playlistId'], 'origin');
        expect(timer.isActive, false);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
  for (final finish in ['zap', 'pause', 'dispose']) {
    testWidgets(
      'P15 last-live settle $finish only records a channel that actually plays',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        var writeRegistrations = 0;
        Result observeWrites<Result>(Result Function() body) => runZoned(
          body,
          zoneSpecification: ZoneSpecification(
            registerUnaryCallback:
                <R, T>(self, parent, zone, R Function(T) callback) {
                  final frame = StackTrace.current
                      .toString()
                      .split('\n')
                      .where((s) => s.contains('package:debrify/'))
                      .firstOrNull;
                  if (frame?.contains('setIptvLastLiveChannel') ?? false) {
                    writeRegistrations++;
                  }
                  return parent.registerUnaryCallback(zone, callback);
                },
          ),
        );
        final a = [iptvChannel(0), iptvChannel(1)];
        try {
          await observeWrites(() => d.mount(a));
          final initialPrefs = await d.f.finish(
            t,
            ProfilePreferences.instance(),
          );
          await d.f.until(
            t,
            () => initialPrefs.containsKey('iptv_last_live_channel'),
          );
          expect(
            await d.f.finish(
              t,
              IptvLastChannelStorage.getIptvLastLiveChannel(),
            ),
            isNotNull,
          );
          await d.f.finish(
            t,
            IptvLastChannelStorage.clearIptvLastLiveChannel(),
          );
          final beforeWrites = writeRegistrations;
          final count = d.timed
              .where((v) => v.$1 == const Duration(seconds: 1))
              .length;
          d.observe(() => d.player.emit('playing', true));
          await d.f.advance(t);
          expect(
            d.timed.where((v) => v.$1 == const Duration(seconds: 1)).length,
            count + 1,
          );
          final settleTimer = d.timed
              .lastWhere((v) => v.$1 == const Duration(seconds: 1))
              .$2;
          if (finish == 'zap') {
            await d.zap(1);
          }
          if (finish == 'pause') {
            d.player.state = d.player.state.copyWith(playing: false);
            d.player.emit('playing', false);
            await d.f.advance(t);
          }
          if (finish == 'dispose') {
            await d.retire();
            expect(settleTimer.isActive, false);
          }
          await d.advance(const Duration(seconds: 2));
          // This observes the real writer's first executed await before its
          // playlist lookup can race a subsequent empty preference read.
          expect(
            writeRegistrations,
            finish == 'zap' ? greaterThan(beforeWrites) : beforeWrites,
          );
          if (finish == 'zap') {
            final prefs = await d.f.finish(t, ProfilePreferences.instance());
            await d.f.until(
              t,
              () => prefs.containsKey('iptv_last_live_channel'),
            );
          }
          final row = await d.f.finish(
            t,
            IptvLastChannelStorage.getIptvLastLiveChannel(),
          );
          if (finish == 'zap') {
            expect(row, isNotNull);
            expect(row!['url'], a[1].url);
            expect(row['playlistId'], 'launch-source');
          } else {
            expect(row, isNull);
          }
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
  testWidgets(
    'P15 initial series restore reaches the retained P11 audio adapter',
    (t) async {
      final d = IptvWorkflowDriver(
        t,
        configurePlayer: (p) {
          p.publishTracks(
            const mk.Tracks(
              audio: [
                mk.AudioTrack('1', 'English', 'eng'),
                mk.AudioTrack('2', 'French', 'fra'),
              ],
              subtitle: [mk.SubtitleTrack('1', 'English', 'eng')],
            ),
          );
        },
      );
      await d.initialize();
      try {
        await d.f.finish(
          t,
          IptvAudioStorage.setIptvSeriesAudioLanguage(
            'provider::series',
            'fra',
          ),
        );
        await d.mount([iptvEpisode(1)]);
        expect(d.player.state.track.audio.id, '2');
        expect(
          d
              .calls('audio')
              .where((c) => (c.$2 as mk.AudioTrack).id == '2')
              .length,
          1,
        );
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
  testWidgets(
    'P15 switch owner and pending P11 restoration keep both audio appliers in their original order',
    (t) async {
      final gate = Completer<void>();
      var entered = false;
      final d = IptvWorkflowDriver(
        t,
        native: true,
        configurePlayer: (p) {
          p.publishTracks(
            const mk.Tracks(
              audio: [
                mk.AudioTrack('1', 'English', 'eng'),
                mk.AudioTrack('2', 'French', 'fra'),
              ],
              subtitle: [mk.SubtitleTrack('1', 'English', 'eng')],
            ),
          );
          final native = p.platform as FakeNativePlayer;
          bool selected(String n, Object? v) =>
              n == 'getProperty' &&
              v == 'current-tracks/audio/lang' &&
              StackTrace.current.toString().contains(
                'applyDefaultAudioLanguage',
              );
          native.heldOperation = (n, v) => !entered && selected(n, v);
          native.beforeOperation = (n, v) async {
            if (!entered && selected(n, v)) {
              entered = true;
              await gate.future;
            }
          };
        },
      );
      await d.initialize();
      try {
        await d.f.finish(
          t,
          SubtitleSettingsStorage.setDefaultAudioLanguage('eng'),
        );
        await d.f.finish(
          t,
          IptvAudioStorage.setIptvSeriesAudioLanguage(
            'provider::series',
            'fra',
          ),
        );
        final channels = [iptvEpisode(1), iptvEpisode(2)];
        await d.observe(() => d.f.mount(t, d.screen(channels)));
        await d.f.until(t, () => entered);
        expect(gate.isCompleted, false);
        final before = d.calls('audio').length;
        final s = await d.guide();
        await d.f.finish(t, d.observe(() => s.onChannelSelected(channels, 1)));
        await d.settle();
        expect(
          d.calls('audio').skip(before).map((c) => (c.$2 as mk.AudioTrack).id),
          ['2'],
        );
        gate.complete();
        await d.f.until(
          t,
          () => d.periodic.any((v) => v.$1 == const Duration(seconds: 6)),
        );
        await d.settle();
        expect(
          d.calls('audio').skip(before).map((c) => (c.$2 as mk.AudioTrack).id),
          ['2', '1', '2'],
        );
        expect(d.errors, isEmpty);
      } finally {
        if (!gate.isCompleted) gate.complete();
        await d.settle();
        await d.close();
      }
    },
  );
}
