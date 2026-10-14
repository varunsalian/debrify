import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/storage/playback_state_store.dart';
import 'package:debrify/services/storage/track_preferences_storage.dart';
import 'video_player_subtitle_sources_language_test.dart'
    show seedLanguagePlayer;
import 'package:flutter_test/flutter_test.dart';

import 'support/local_completion_driver.dart' show CompletionDelivery;
import 'support/subtitle_apply_driver.dart';
import 'video_player_skip_races_test.dart' show incomingProfile;
import 'video_player_subtitle_apply_persistence_test.dart' show ApplyWrites;
import 'video_player_subtitle_sources_payload_test.dart' show removeFixture;
import 'video_player_trakt_snapshots_test.dart'
    show traktPlaylist, traktBrowser;

void main() {
  for (final handoff in [false, true]) {
    testWidgets(
      'subtitle series preference map read ${handoff ? 'crosses profile handoff' : 'keeps original scope'} and preserves physical contents',
      (t) async {
        final d = SubtitleApplyDriver(t);
        await d.initialize();
        final store = await t.runAsync(ApplyWrites.install);
        final outgoing = ProfileRuntime.capture();
        final held = CompletionDelivery(
          'saveSeriesTrackPreferences',
          (v) => v is Map<String, dynamic>,
        );
        try {
          await d.mount(
            screen: const VideoPlayerScreen(
              videoUrl: 'https://player.test/trakt-one.mp4',
              title: 'Trakt.Show.S01E01.mkv',
              playlist: traktPlaylist,
            ),
          );
          final b = await traktBrowser(t, d.f);
          final title = b.seriesPlaylist.seriesTitle!;
          expect(title, 'trakt show');
          d.f.navigator.currentState!.pop();
          await d.f.advance(t);
          await d.f.finish(
            t,
            PlaybackStateStore.savePlaybackStateMap({
              'unrelated-A': {'owner': 'A'},
            }),
          );
          final panel = await d.menu();
          final pending = held.run(
            () => d.observe(() => panel.onEmbeddedSubtitleSelected('2', '1')),
          );
          var completed = false;
          pending.then((_) => completed = true);
          await d.f.until(t, () => held.pending.isNotEmpty);
          expect(completed, isFalse);
          expect((await store!.map(outgoing))['series_trakt_show'], isNull);
          if (handoff) {
            await incomingProfile(t, d.f);
            await d.f.finish(
              t,
              PlaybackStateStore.savePlaybackStateMap({
                'unrelated-B': {'owner': 'B'},
              }),
            );
          }
          final incoming = ProfileRuntime.capture();
          held.release();
          expect(await d.f.finish(t, pending), isTrue);
          final a = await store.map(outgoing);
          final bmap = await store.map(incoming);
          expect(a['unrelated-A'], {'owner': 'A'});
          expect(bmap['unrelated-A'], {'owner': 'A'});
          expect(bmap['unrelated-B'], isNull);
          final record = bmap['series_trakt_show'] as Map;
          expect(record['type'], 'series');
          expect(record['title'], title);
          expect(
            record['trackPreferences'],
            allOf(
              containsPair('audioTrackId', '1'),
              containsPair('subtitleTrackId', '2'),
            ),
          );
          expect(record['trackPreferences']['updatedAt'], isA<int>());
          expect(record['seasons'], isEmpty);
          if (handoff) {
            expect(a['series_trakt_show'], isNull);
          }
          expect(d.errors, isEmpty);
        } finally {
          held.release();
          store!.releaseAll();
          await removeFixture(d);
        }
      },
    );
  }
  for (final title in ['', 'A Film / β!']) {
    testWidgets(
      'subtitle video title "$title" persists its original sanitized fallback key',
      (t) async {
        final d = SubtitleApplyDriver(t, configurePlayer: seedLanguagePlayer);
        await d.initialize();
        final store = await t.runAsync(ApplyWrites.install);
        final scope = ProfileRuntime.capture();
        try {
          await d.f.finish(
            t,
            TrackPreferencesStorage.saveVideoTrackPreferences(
              videoTitle: title.isEmpty ? 'Unknown Video' : title,
              audioTrackId: '1',
              subtitleTrackId: '3',
            ),
          );
          await d.mount(
            screen: VideoPlayerScreen(
              videoUrl: 'https://player.test/title.mp4',
              title: title,
            ),
            publishTracks: false,
          );
          expect(d.player.state.track.subtitle.id, '3');
          await d.f.finish(
            t,
            PlaybackStateStore.savePlaybackStateMap({
              'unrelated': {'keep': true},
            }),
          );
          expect(await d.select('2'), isTrue);
          final physical = await store!.map(scope);
          expect(physical['unrelated'], {'keep': true});
          final key = title.isEmpty
              ? 'video_unknown_video'
              : 'video_a_film_____';
          expect(physical[key], isA<Map>());
          final record = physical[key] as Map;
          expect(record['type'], 'video');
          expect(record['title'], title.isEmpty ? 'Unknown Video' : title);
          expect(record['trackPreferences']['audioTrackId'], '1');
          expect(record['trackPreferences']['subtitleTrackId'], '2');
          expect(record['trackPreferences']['updatedAt'], isA<int>());
          expect(physical.keys, unorderedEquals(['unrelated', key]));
        } finally {
          store!.releaseAll();
          await removeFixture(d);
        }
      },
    );
  }
  for (final missing in [false, true]) {
    testWidgets(
      'subtitle series restore reads ${missing ? 'Unknown Series fallback' : 'parsed series'} preferences through original initialization',
      (t) async {
        final d = SubtitleApplyDriver(t, configurePlayer: seedLanguagePlayer);
        await d.initialize();
        final title = missing ? 'Unknown Series' : 'trakt show';
        await d.f.finish(
          t,
          TrackPreferencesStorage.saveSeriesTrackPreferences(
            seriesTitle: title,
            audioTrackId: '1',
            subtitleTrackId: '3',
          ),
        );
        try {
          await d.mount(
            screen: VideoPlayerScreen(
              videoUrl: 'https://player.test/trakt-one.mp4',
              title: missing ? '' : 'Trakt.Show.S01E01.mkv',
              contentType: 'series',
              playlist: missing
                  ? const [
                      PlaylistEntry(
                        url: 'https://player.test/trakt-one.mp4',
                        title: '',
                      ),
                      PlaylistEntry(
                        url: 'https://player.test/trakt-two.mp4',
                        title: '',
                      ),
                    ]
                  : traktPlaylist,
            ),
            publishTracks: false,
          );
          expect(d.player.state.track.subtitle.id, '3');
          expect(
            d.logs.where(
              (s) => s.contains('applying STORED subtitle track id=3'),
            ),
            isNotEmpty,
          );
          final b = await traktBrowser(t, d.f);
          expect(b.seriesPlaylist.seriesTitle, missing ? null : 'trakt show');
          d.f.navigator.currentState!.pop();
          await d.f.advance(t);
          expect(await d.select('2'), isTrue);
          expect(
            (await d.f.finish(
              t,
              TrackPreferencesStorage.getSeriesTrackPreferences(
                seriesTitle: title,
              ),
            ))?['subtitleTrackId'],
            '2',
          );
          expect(d.errors, isEmpty);
        } finally {
          await removeFixture(d);
        }
      },
    );
  }
}
