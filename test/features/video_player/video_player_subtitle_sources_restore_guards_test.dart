import 'package:debrify/services/storage/track_preferences_storage.dart';
import 'package:debrify/services/storage/subtitle_settings_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;

import 'support/local_completion_driver.dart' show CompletionDelivery;
import 'support/player_actions.dart';
import 'support/subtitle_apply_driver.dart';
import 'video_player_subtitle_apply_boundaries_test.dart'
    show boundaryScreen, crossBoundary;
import 'video_player_subtitle_apply_wait_test.dart' show TrackPoll;
import 'video_player_subtitle_sources_language_test.dart'
    show seedLanguagePlayer;
import 'video_player_subtitle_sources_payload_test.dart' show removeFixture;
import 'support/physical_resume_store.dart';

void main() {
  testWidgets(
    'subtitle restoration rejects old content immediately after the held preference map read',
    (t) async {
      final d = SubtitleApplyDriver(t, configurePlayer: seedLanguagePlayer);
      await d.initialize();
      await d.f.finish(
        t,
        TrackPreferencesStorage.saveVideoTrackPreferences(
          videoTitle: boundaryScreen.title,
          audioTrackId: '1',
          subtitleTrackId: '3',
        ),
      );
      final held = CompletionDelivery(
        'restoreTrackPreferences',
        (v) => v is Map && v['subtitleTrackId'] == '3',
      );
      try {
        await held.run(
          () => d.mount(
            screen: boundaryScreen,
            publishTracks: false,
            settleInitialization: false,
          ),
        );
        await d.f.until(t, () => held.pending.isNotEmpty);
        expect(d.player.calls.where((c) => c.$1 == 'subtitle'), isEmpty);
        await crossBoundary(d, 'reset');
        await d.f.until(t, () => d.logs.any((s) => s.contains('restore done')));
        final audio = d.player.calls.where((c) => c.$1 == 'audio').length;
        final subtitles = d.player.calls
            .where((c) => c.$1 == 'subtitle')
            .length;
        expect(held.pending, hasLength(1));
        held.release();
        await d.f.actions.settle(t);
        expect(d.player.calls.where((c) => c.$1 == 'audio'), hasLength(audio));
        expect(
          d.player.calls.where((c) => c.$1 == 'subtitle'),
          hasLength(subtitles),
        );
        expect(
          d.logs,
          contains(
            'SubAuto: restore aborted (content changed during prefs fetch)',
          ),
        );
        expect(d.errors, isEmpty);
      } finally {
        held.release();
        await removeFixture(d);
      }
    },
  );
  testWidgets(
    'subtitle restoration rejects old content immediately after the held track poll',
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
        expect(d.logs.where((s) => s.contains('restore start')), isEmpty);
        final dynamic next = playerControls(t).onNext;
        final Future<dynamic> switched = d.observe<dynamic>(() => next());
        await d.f.until(
          t,
          () => d.player.calls.where((c) => c.$1 == 'open').length == 2,
        );
        held.armed = false;
        held.release();
        d.publish();
        await d.f.finish<dynamic>(t, switched);
        await d.f.until(
          t,
          () => d.logs.contains(
            'SubAuto: restore aborted after track wait (content changed)',
          ),
        );
        expect(
          d.logs.where((s) => s.startsWith('SubAuto: restore start')),
          hasLength(1),
        );
        await d.f.actions.settle(t);
        await d.f.advance(t, const Duration(milliseconds: 100));
        expect(
          d.logs.where((s) => s.contains('content changed during prefs fetch')),
          isEmpty,
        );
        expect(held.scheduled, 1);
        expect(d.errors, isEmpty);
      } finally {
        held.armed = false;
        held.release();
        await removeFixture(d);
      }
    },
  );
  testWidgets(
    'subtitle restoration diagnostic preserves the track snapshot and chosen fallback',
    (t) async {
      final d = SubtitleApplyDriver(t, configurePlayer: seedLanguagePlayer);
      await d.initialize();
      await d.f.finish(
        t,
        SubtitleSettingsStorage.setDefaultSubtitleLanguage('eng'),
      );
      try {
        await d.mount(publishTracks: false);
        await d.f.actions.settle(t);
        expect(d.player.state.track.subtitle.id, '2');
        expect(d.logs.where((s) => s.startsWith('SubAuto:')), [
          'SubAuto: _restoreTrackPreferences entered (token=0)',
          'SubAuto: restore start — prefs=NONE subtitleTracks=[auto/null/null, no/null/null, 1/fra/Français, 2/eng/English captions, 3/spa/Spanish captions, 4/pt-BR/Brazilian Portuguese, 5/por/Portuguese captions, 6/null/German, 7/fre/French alternate] currentSub=no',
          'SubAuto: no stored prefs → default-language path',
          'SubAuto: defaultSubtitleLanguage setting = eng',
          'SubAuto: matched EMBEDDED track id=2 lang=eng title=English captions — applying',
          'SubAuto: restore done — embeddedSubtitleApplied=true → running addon auto-select',
        ], reason: d.logs.join('\n'));
        expect(d.errors, isEmpty);
      } finally {
        await removeFixture(d);
      }
    },
  );
  testWidgets(
    'subtitle malformed stored track identity is caught before restoration publishes selection',
    (t) async {
      final d = SubtitleApplyDriver(t, configurePlayer: seedLanguagePlayer);
      await d.initialize();
      await d.f.finish(
        t,
        PhysicalResumeStore.savePlaybackStateMap({
          'video_subtitle_apply_original': {
            'type': 'video',
            'title': applyScreen.title,
            'trackPreferences': {'audioTrackId': 42, 'subtitleTrackId': 'no'},
          },
        }),
      );
      try {
        await d.mount(publishTracks: false);
        await d.f.actions.settle(t);
        expect(d.player.state.track.subtitle.id, 'no');
        expect(d.player.state.track.audio.id, '2');
        expect(
          d.player.calls.where((c) => c.$1 == 'audio' || c.$1 == 'subtitle'),
          isEmpty,
        );
        expect(
          d.logs.where(
            (s) => s.startsWith('SubAuto: restore FAILED with exception:'),
          ),
          hasLength(1),
        );
        expect(d.logs.where((s) => s.contains('restore done')), isEmpty);
        expect(d.errors, isEmpty);
      } finally {
        await removeFixture(d);
      }
    },
  );
}
