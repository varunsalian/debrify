import 'package:debrify/services/storage/subtitle_settings_storage.dart';
import 'package:debrify/services/storage/playback_state_store.dart';
import 'package:debrify/services/storage/iptv_audio_storage.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/models/subtitle_source_priority.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/track_preferences_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;

import 'support/fake_player.dart';
import 'support/subtitle_apply_driver.dart';
import 'video_player_subtitle_sources_payload_test.dart' show removeFixture;

const languageTracks = [
  mk.SubtitleTrack('auto', null, null),
  mk.SubtitleTrack('no', null, null),
  mk.SubtitleTrack('1', 'Français', 'fra'),
  mk.SubtitleTrack('2', 'English captions', 'eng'),
  mk.SubtitleTrack('3', 'Spanish captions', 'spa'),
  mk.SubtitleTrack('4', 'Brazilian Portuguese', 'pt-BR'),
  mk.SubtitleTrack('5', 'Portuguese captions', 'por'),
  mk.SubtitleTrack('6', 'German', null),
  mk.SubtitleTrack('7', 'French alternate', 'fre'),
];
void seedLanguagePlayer(FakePlayer p, {String sid = 'no'}) {
  p.publishTracks(
    const mk.Tracks(
      audio: [
        mk.AudioTrack('auto', null, null),
        mk.AudioTrack('no', null, null),
        mk.AudioTrack('1', 'English audio', 'eng'),
        mk.AudioTrack('2', 'French audio', 'fra'),
        mk.AudioTrack('3', 'German', null),
      ],
      subtitle: languageTracks,
    ),
    selected: mk.Track(
      audio: const mk.AudioTrack('2', 'French audio', 'fra'),
      subtitle: sid == 'no'
          ? mk.SubtitleTrack.no()
          : languageTracks.firstWhere((s) => s.id == sid),
    ),
  );
  (p.platform as FakeNativePlayer).properties['sid'] = sid;
}

void main() {
  for (final c in [
    (language: null, sid: '3', result: '3'),
    (language: null, sid: 'no', result: '2'),
    (language: 'off', sid: '3', result: 'no'),
    (language: 'en', sid: 'no', result: '2'),
    (language: 'eng', sid: 'no', result: '2'),
    (language: 'es', sid: 'no', result: '3'),
    (language: 'spa', sid: 'no', result: '3'),
    (language: 'fr', sid: 'no', result: '1'),
    (language: 'fre', sid: 'no', result: '1'),
    (language: 'fra', sid: 'no', result: '1'),
    (language: 'de', sid: 'no', result: '6'),
    (language: 'pt-BR', sid: 'no', result: '4'),
    (language: 'por', sid: 'no', result: '4'),
    (language: 'ja', sid: 'no', result: 'no'),
  ]) {
    testWidgets(
      'subtitle original language ${c.language} native ${c.sid} selects ${c.result}',
      (t) async {
        final d = SubtitleApplyDriver(
          t,
          configurePlayer: (p) {
            seedLanguagePlayer(p);
            (p.platform as FakeNativePlayer).properties['sid'] = c.sid;
          },
        );
        await d.initialize();
        await d.f.finish(
          t,
          SubtitleSettingsStorage.setDefaultSubtitleLanguage(c.language),
        );
        try {
          await d.mount(publishTracks: false);
          await d.f.actions.settle(t);
          expect(d.player.state.track.subtitle.id, c.result);
          expect(d.errors, isEmpty);
          expect(d.logs.any((v) => v.contains('restore done')), isTrue);
          expect(
            d.logs,
            contains(
              'SubAuto: restore done — embeddedSubtitleApplied=${c.language != 'ja'} → running addon auto-select',
            ),
          );
          if (c.language == 'ja') {
            expect(
              d.logs,
              contains(
                'SubAuto: no ja embedded track → returning false (addon auto-select may run)',
              ),
            );
          } else if (c.language != null && c.language != 'off') {
            final track = languageTracks.firstWhere((s) => s.id == c.result);
            expect(
              d.logs,
              contains(
                'SubAuto: matched EMBEDDED track id=${track.id} lang=${track.language} title=${track.title} — applying',
              ),
            );
          }
          expect(
            d.logs,
            contains('SubAuto: _restoreTrackPreferences entered (token=0)'),
          );
        } finally {
          await removeFixture(d);
        }
      },
    );
  }
  for (final c in [
    (language: null, native: '', result: '2'),
    (language: 'en', native: 'eng', result: '2'),
    (language: 'en', native: 'fra', result: '1'),
    (language: 'de', native: '', result: '3'),
    (language: 'ja', native: '', result: '2'),
  ]) {
    testWidgets(
      'subtitle original audio ${c.language} native ${c.native} selects ${c.result}',
      (t) async {
        final d = SubtitleApplyDriver(
          t,
          configurePlayer: (p) {
            seedLanguagePlayer(p);
            (p.platform as FakeNativePlayer)
                    .properties['current-tracks/audio/lang'] =
                c.native;
          },
        );
        await d.initialize();
        await d.f.finish(
          t,
          SubtitleSettingsStorage.setDefaultAudioLanguage(c.language),
        );
        try {
          await d.mount(publishTracks: false);
          await d.f.actions.settle(t);
          expect(d.player.state.track.audio.id, c.result);
          if (c.language == null) {
            expect(
              d.native.calls.where(
                (c) =>
                    c.$1 == 'getProperty' &&
                    c.$2 == 'current-tracks/audio/lang',
              ),
              isEmpty,
            );
          }
          expect(d.errors, isEmpty);
        } finally {
          await removeFixture(d);
        }
      },
    );
  }
  for (final stored in ['auto', 'no', '1', '2', 'missing']) {
    testWidgets(
      'subtitle stored $stored restoration keeps default conflict and off semantics',
      (t) async {
        final d = SubtitleApplyDriver(t, configurePlayer: seedLanguagePlayer);
        await d.initialize();
        await d.f.finish(
          t,
          SubtitleSettingsStorage.setDefaultSubtitleLanguage('en'),
        );
        await d.f.finish(
          t,
          TrackPreferencesStorage.saveVideoTrackPreferences(
            videoTitle: applyScreen.title,
            audioTrackId: 'missing',
            subtitleTrackId: stored,
          ),
        );
        try {
          await d.mount(publishTracks: false);
          await d.f.actions.settle(t);
          expect(
            d.player.state.track.subtitle.id,
            stored == 'no' ? 'no' : '2',
            reason: d.logs.join('\n'),
          );
          expect(d.player.state.track.audio.id, '2');
          final diagnostic = switch (stored) {
            'auto' =>
              'SubAuto: stored subtitle id=auto treated as no-choice → default-language path',
            'no' =>
              'SubAuto: applying STORED subtitle track id=no (lang=null/null) — blocks addon auto-select',
            '1' =>
              'SubAuto: stored track id=1 (lang=fra/Français) conflicts with default=en → default-language path',
            '2' =>
              'SubAuto: applying STORED subtitle track id=2 (lang=eng/English captions) — blocks addon auto-select',
            _ =>
              'SubAuto: stored subtitle id=missing not in this file → default-language path',
          };
          expect(d.logs, contains(diagnostic));
          expect(
            d.logs,
            contains(
              'SubAuto: restore done — embeddedSubtitleApplied=true → running addon auto-select',
            ),
          );
          expect(d.errors, isEmpty);
        } finally {
          await removeFixture(d);
        }
      },
    );
  }
  for (final c in [
    (language: null, forced: true, result: '2'),
    (language: 'off', forced: true, result: 'no'),
    (language: 'en', forced: false, result: 'no'),
  ]) {
    testWidgets(
      'subtitle forced ${c.forced} preference ${c.language} never selects a full track',
      (t) async {
        final d = SubtitleApplyDriver(
          t,
          configurePlayer: (p) {
            seedLanguagePlayer(p);
            (p.platform as FakeNativePlayer).properties.addAll({
              'track-list/count': '1',
              'track-list/0/type': 'sub',
              'track-list/0/forced': c.forced ? 'yes' : 'no',
              'track-list/0/external': 'no',
              'track-list/0/lang': 'eng',
              'track-list/0/id': '2',
            });
          },
        );
        await d.initialize();
        await d.f.finish(
          t,
          SubtitleSettingsStorage.setDefaultSubtitleLanguage(c.language),
        );
        await d.f.finish(
          t,
          SubtitleSettingsStorage.setSubtitleForcedOnly(true),
        );
        try {
          await d.mount(publishTracks: false);
          await d.f.actions.settle(t);
          expect(d.player.state.track.subtitle.id, c.result);
          expect(
            d.native.calls.where(
              (v) =>
                  v.$1 == 'getProperty' && v.$2 == 'current-tracks/audio/lang',
            ),
            isEmpty,
          );
          expect(d.errors, isEmpty);
        } finally {
          await removeFixture(d);
        }
      },
    );
  }
  for (final variant in [
    'audio property failure',
    'sid property failure',
    'nonnative',
    'first real',
    'empty',
  ]) {
    testWidgets('subtitle original no preference fallback $variant', (t) async {
      final d = SubtitleApplyDriver(
        t,
        native: variant != 'nonnative',
        configurePlayer: (p) {
          if (variant == 'nonnative') {
            p.state = p.state.copyWith(
              tracks: const mk.Tracks(subtitle: languageTracks),
            );
          } else {
            seedLanguagePlayer(p);
            if (variant == 'first real' || variant == 'empty') {
              p.state = p.state.copyWith(
                tracks: mk.Tracks(
                  subtitle: variant == 'empty'
                      ? const []
                      : const [
                          mk.SubtitleTrack('11', 'Spanish', 'spa'),
                          mk.SubtitleTrack('12', 'French', 'fra'),
                        ],
                ),
              );
            }
            final native = p.platform as FakeNativePlayer;
            native.properties['current-tracks/audio/lang'] = 'fra';
            if (variant == 'audio property failure') {
              native.beforeOperation = (name, value) {
                if (name == 'getProperty' &&
                    value == 'current-tracks/audio/lang') {
                  throw StateError('audio metadata missing');
                }
              };
            }
            if (variant == 'sid property failure') {
              native.beforeOperation = (name, value) {
                if (name == 'getProperty' && value == 'sid') {
                  throw StateError('sid missing');
                }
              };
            }
          }
        },
      );
      await d.initialize();
      if (variant == 'audio property failure') {
        await d.f.finish(
          t,
          SubtitleSettingsStorage.setDefaultAudioLanguage('eng'),
        );
      }
      try {
        await d.mount(
          publishTracks: false,
          settleInitialization: variant != 'empty',
        );
        if (variant == 'empty') {
          await d.f.advance(t, const Duration(seconds: 3));
          await d.f.until(
            t,
            () => d.logs.any((s) => s.contains('restore done')),
          );
        }
        await d.f.actions.settle(t);
        expect(
          d.player.state.track.subtitle.id,
          variant == 'first real'
              ? '11'
              : variant == 'empty'
              ? 'no'
              : '2',
        );
        if (variant == 'audio property failure') {
          expect(d.player.state.track.audio.id, '1');
        }
        expect(
          d.logs,
          contains(
            'SubAuto: restore done — embeddedSubtitleApplied=${variant != 'empty'} → running addon auto-select',
          ),
        );
        expect(d.errors, isEmpty);
      } finally {
        await removeFixture(d);
      }
    });
  }
  testWidgets(
    'subtitle default audio with no tracks avoids the native language property read',
    (t) async {
      final d = SubtitleApplyDriver(
        t,
        configurePlayer: (p) {
          seedLanguagePlayer(p);
          p.state = p.state.copyWith(
            tracks: const mk.Tracks(audio: [], subtitle: languageTracks),
          );
        },
      );
      await d.initialize();
      await d.f.finish(
        t,
        SubtitleSettingsStorage.setDefaultAudioLanguage('eng'),
      );
      try {
        await d.mount(publishTracks: false);
        expect(
          d.native.calls.where(
            (c) => c.$1 == 'getProperty' && c.$2 == 'current-tracks/audio/lang',
          ),
          isEmpty,
        );
        expect(d.player.calls.where((c) => c.$1 == 'audio'), isEmpty);
        expect(d.player.state.track.subtitle.id, '2');
        expect(d.errors, isEmpty);
      } finally {
        await removeFixture(d);
      }
    },
  );
  for (final stored in [false, true]) {
    testWidgets(
      'subtitle ${stored ? 'stored' : 'default'} language excludes the first app-managed addon ordinal',
      (t) async {
        final d = SubtitleApplyDriver(
          t,
          configurePlayer: (p) {
            seedLanguagePlayer(p);
            p.state = p.state.copyWith(
              tracks: const mk.Tracks(
                audio: [mk.AudioTrack('1', 'English', 'eng')],
                subtitle: [
                  mk.SubtitleTrack(
                    '8',
                    'Old addon',
                    'eng',
                    external: true,
                    externalFilename: '/fixture/stremio_sub_old.srt',
                  ),
                  ...languageTracks,
                ],
              ),
            );
          },
        );
        await d.initialize();
        await d.f.finish(
          t,
          SubtitleSettingsStorage.setDefaultSubtitleLanguage('eng'),
        );
        if (stored) {
          await d.f.finish(
            t,
            TrackPreferencesStorage.saveVideoTrackPreferences(
              videoTitle: applyScreen.title,
              audioTrackId: '1',
              subtitleTrackId: '8',
            ),
          );
        }
        try {
          await d.mount(publishTracks: false);
          await d.f.actions.settle(t);
          expect(d.player.state.track.subtitle.id, '2');
          expect(
            d.player.calls
                .where((c) => c.$1 == 'subtitle')
                .map((c) => (c.$2 as mk.SubtitleTrack).id),
            ['2'],
          );
          if (stored) {
            expect(
              d.logs,
              contains(
                'SubAuto: stored subtitle id=8 not in this file → default-language path',
              ),
            );
          }
          expect(d.errors, isEmpty);
        } finally {
          await removeFixture(d);
        }
      },
    );
  }
  for (final audio in <String?>[null, '', 'auto', 'missing', '1', '2']) {
    for (final preferred in <String?>[null, 'eng']) {
      testWidgets(
        'subtitle stored audio "$audio" with global "$preferred" restores its original precedence',
        (t) async {
          final d = SubtitleApplyDriver(
            t,
            configurePlayer: (p) {
              seedLanguagePlayer(p);
              (p.platform as FakeNativePlayer)
                      .properties['current-tracks/audio/lang'] =
                  'fra';
            },
          );
          await d.initialize();
          await d.f.finish(
            t,
            SubtitleSettingsStorage.setDefaultAudioLanguage(preferred),
          );
          await d.f.finish(
            t,
            PlaybackStateStore.savePlaybackStateMap({
              'video_subtitle_apply_original': {
                'type': 'video',
                'title': applyScreen.title,
                'trackPreferences': {
                  'audioTrackId': audio,
                  'subtitleTrackId': 'no',
                },
              },
            }),
          );
          try {
            await d.mount(publishTracks: false);
            await d.f.actions.settle(t);
            final expected = audio == '1' || audio == '2'
                ? audio
                : preferred == null
                ? '2'
                : '1';
            expect(d.player.state.track.audio.id, expected);
            expect(d.player.state.track.subtitle.id, 'no');
            expect(
              d.player.calls
                  .where((c) => c.$1 == 'audio')
                  .map((c) => (c.$2 as mk.AudioTrack).id),
              audio == '1' || audio == '2' || preferred != null
                  ? [expected]
                  : isEmpty,
            );
            expect(
              d.logs,
              contains(
                'SubAuto: applying STORED subtitle track id=no (lang=null/null) — blocks addon auto-select',
              ),
            );
            expect(d.errors, isEmpty);
          } finally {
            await removeFixture(d);
          }
        },
      );
    }
  }
  for (final stored in [false, true]) {
    testWidgets(
      'subtitle IPTV series audio override follows ${stored ? 'stored tracks' : 'global default'} before final restoration',
      (t) async {
        final d = SubtitleApplyDriver(
          t,
          configurePlayer: (p) {
            seedLanguagePlayer(p);
            (p.platform as FakeNativePlayer)
                    .properties['current-tracks/audio/lang'] =
                'fra';
          },
        );
        await d.initialize();
        await d.f.finish(
          t,
          SubtitleSettingsStorage.setDefaultAudioLanguage('eng'),
        );
        await d.f.finish(
          t,
          IptvAudioStorage.setIptvSeriesAudioLanguage('fixture::series', 'fra'),
        );
        if (stored) {
          await d.f.finish(
            t,
            TrackPreferencesStorage.saveVideoTrackPreferences(
              videoTitle: 'IPTV language original',
              audioTrackId: '1',
              subtitleTrackId: 'no',
            ),
          );
        }
        try {
          await d.mount(
            screen: VideoPlayerScreen(
              videoUrl: 'https://player.test/iptv-series.mp4',
              title: 'IPTV language original',
              iptvChannels: [
                IptvChannel(
                  name: 'Series episode',
                  url: 'https://player.test/iptv-series.mp4',
                  contentType: 'vod',
                  attributes: const {
                    'series_id': 'series',
                    'series_playlist_id': 'fixture',
                  },
                ),
              ],
            ),
            publishTracks: false,
          );
          await d.f.actions.settle(t);
          expect(d.player.state.track.audio.id, '2');
          expect(
            d.player.calls
                .where((c) => c.$1 == 'audio')
                .map((c) => (c.$2 as mk.AudioTrack).id),
            ['1', '2'],
          );
          expect(d.player.state.track.subtitle.id, stored ? 'no' : '2');
          expect(d.errors, isEmpty);
        } finally {
          await removeFixture(d);
        }
      },
    );
  }
  testWidgets(
    'subtitle global off overrides a stored embedded track literally labelled Off',
    (t) async {
      final d = SubtitleApplyDriver(
        t,
        configurePlayer: (p) {
          seedLanguagePlayer(p);
          p.state = p.state.copyWith(
            tracks: const mk.Tracks(
              audio: [mk.AudioTrack('1', 'English', 'eng')],
              subtitle: [
                mk.SubtitleTrack('no', null, null),
                mk.SubtitleTrack('2', 'Off', null),
              ],
            ),
          );
        },
      );
      await d.initialize();
      await d.f.finish(
        t,
        SubtitleSettingsStorage.setDefaultSubtitleLanguage('off'),
      );
      await d.f.finish(
        t,
        TrackPreferencesStorage.saveVideoTrackPreferences(
          videoTitle: applyScreen.title,
          audioTrackId: '1',
          subtitleTrackId: '2',
        ),
      );
      try {
        await d.mount(publishTracks: false);
        await d.f.actions.settle(t);
        expect(d.player.state.track.subtitle.id, 'no');
        expect(
          d.player.calls
              .where((c) => c.$1 == 'subtitle')
              .map((c) => (c.$2 as mk.SubtitleTrack).id),
          ['no'],
        );
        expect(
          d.logs,
          contains(
            'SubAuto: stored track id=2 (lang=null/Off) conflicts with default=off → default-language path',
          ),
        );
        expect(d.errors, isEmpty);
      } finally {
        await removeFixture(d);
      }
    },
  );
  testWidgets(
    'subtitle explicit off disables an existing track before unavailable source priority is consulted',
    (t) async {
      final d = SubtitleApplyDriver(
        t,
        configurePlayer: (p) => seedLanguagePlayer(p, sid: '3'),
      );
      await d.initialize();
      await d.f.finish(
        t,
        SubtitleSettingsStorage.setDefaultSubtitleLanguage('off'),
      );
      await d.f.finish(
        t,
        SubtitleSettingsStorage.setSubtitleSourcePriority([
          'addon:unavailable',
          SubtitleSourcePriority.embedded,
        ]),
      );
      try {
        await d.mount(publishTracks: false);
        await d.f.actions.settle(t);
        expect(d.player.state.track.subtitle.id, 'no');
        expect(
          d.player.calls
              .where((c) => c.$1 == 'subtitle')
              .map((c) => (c.$2 as mk.SubtitleTrack).id),
          ['no'],
        );
        expect(
          d.logs,
          contains(
            'SubAuto: restore done — embeddedSubtitleApplied=true → running addon auto-select',
          ),
        );
        expect(d.errors, isEmpty);
      } finally {
        await removeFixture(d);
      }
    },
  );
}
