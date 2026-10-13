import 'dart:convert';

import 'package:debrify/models/subtitle_source_priority.dart';
import 'package:debrify/screens/video_player/widgets/auto_sync_pill.dart';
import 'package:debrify/screens/video_player/widgets/subtitle_line_picker_overlay.dart';
import 'package:debrify/screens/video_player/widgets/sync_stepper_overlay.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/services/storage/subtitle_settings_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart' as mk;

import 'support/fake_player.dart';
import 'support/player_actions.dart';
import 'support/subtitle_sync_driver.dart';
import 'support/trakt_transport.dart';

void main() {
  for (final foreign in [false, true]) {
    testWidgets(
      'subtitle automatic source priority ${foreign ? 'retires on preferred audio' : 'activates the real engine through its retained caller'}',
      (t) async {
        final d = SubtitleSyncDriver(
          configurePlayer: (p) {
            if (foreign) {
              p.state = p.state.copyWith(
                track: const mk.Track(
                  audio: mk.AudioTrack('2', 'French', 'fra'),
                ),
                tracks: const mk.Tracks(
                  audio: [mk.AudioTrack('2', 'French', 'fra')],
                  subtitle: [mk.SubtitleTrack('1', 'English', 'eng')],
                ),
              );
              (p.platform! as FakeNativePlayer)
                      .properties['current-tracks/audio/lang'] =
                  'fra';
            }
          },
        );
        await d.initialize(t);
        TraktTestTransport.instance.attach(d.fixture);
        const manifest = 'https://subtitle-provider.test/manifest.json';
        const captions = 'https://subtitle-provider.test/caption.srt';
        d.fixture.network.replies[manifest] = http.Response(
          jsonEncode({
            'id': 'p9-subtitles',
            'name': 'P9 fixture subtitles',
            'version': '1.0.0',
            'types': ['movie'],
            'resources': ['stream', 'subtitles'],
            'catalogs': [],
          }),
          200,
        );
        d
                .fixture
                .network
                .replies['https://subtitle-provider.test/subtitles/movie/tt9900001.json'] =
            http.Response(
              jsonEncode({
                'subtitles': [
                  {'id': 'priority-spa', 'url': captions, 'lang': 'spa'},
                ],
              }),
              200,
            );
        d.fixture.network.replies[captions] = http.Response(
          d.srt(d.speech()),
          200,
        );
        final addon = await d.fixture.finish(
          t,
          StremioService.instance.addAddon(manifest),
        );
        await d.fixture.finish(
          t,
          SubtitleSettingsStorage.setDefaultSubtitleLanguage('spa'),
        );
        await d.fixture.finish(
          t,
          SubtitleSettingsStorage.setSubtitleSourcePriority([
            SubtitleSourcePriority.addon(addon.id),
            SubtitleSourcePriority.embedded,
          ]),
        );
        if (foreign) {
          await d.fixture.finish(
            t,
            SubtitleSettingsStorage.setSubtitleOnlyForeignAudio(true),
          );
          await d.fixture.finish(
            t,
            SubtitleSettingsStorage.setDefaultAudioLanguage('eng'),
          );
        }
        try {
          await d.mount(
            t,
            screen: const VideoPlayerScreen(
              videoUrl: 'https://player.test/auto-subtitles.mp4',
              title: 'Automatic subtitles original',
              contentImdbId: 'tt9900001',
              contentType: 'movie',
            ),
          );
          await d.fixture.until(
            t,
            () => d.fixture.player.state.track.subtitle.uri,
          );
          await d.feed(t, durationMs: 1000);
          expect(d.pill?.phase, AutoSyncPillPhase.announce);
          expect(
            d.logs,
            contains(
              'SubtitleAutoSync: external subtitle set (controller=present)',
            ),
          );
          expect(
            d.fixture.network.requests.where(
              (r) => r.url.toString() == captions,
            ),
            hasLength(1),
          );
          if (foreign) {
            d.fixture.player.publishTracks(
              mk.Tracks(
                audio: const [
                  mk.AudioTrack('2', 'French', 'fra'),
                  mk.AudioTrack('1', 'English', 'eng'),
                ],
                subtitle: d.fixture.player.state.tracks.subtitle,
              ),
            );
            await d.fixture.advance(t);
            d.native.properties['current-tracks/audio/lang'] = 'eng';
            await d.observe(
              () => d.fixture.player.setAudioTrack(
                const mk.AudioTrack('1', 'English', 'eng'),
              ),
            );
            await d.fixture.until(
              t,
              () => d.fixture.player.state.track.subtitle.id == 'no',
            );
            await d.fixture.until(t, () => d.native.mapObservers.isEmpty);
            expect(d.pill, isNull);
            expect(
              d.logs,
              contains(
                'SubtitleAutoSync: external subtitle cleared (controller=present)',
              ),
            );
            final menu = await openPlayerMenu(t, d.fixture);
            menu.onClose();
            menu.onSyncRequested!();
            await d.fixture.advance(t);
            expect(find.byType(SyncStepperOverlay), findsOneWidget);
            expect(find.byType(SubtitleLinePickerOverlay), findsNothing);
          }
          expect(d.errors, isEmpty);
        } finally {
          await d.close(t);
        }
      },
    );
  }
}
