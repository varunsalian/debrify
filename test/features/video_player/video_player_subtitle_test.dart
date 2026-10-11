import 'package:debrify/models/stremio_subtitle.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/track_preferences_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart' as mk;

import 'support/fake_player.dart';
import 'support/player_actions.dart';
import 'support/video_player_environment.dart';

const subtitleScreen = VideoPlayerScreen(
  videoUrl: 'https://player.test/subs.mp4',
  title: 'Subtitle original',
);
const selectedTrack = mk.SubtitleTrack('2', 'Spanish', 'spa');

Future<void> prepare(
  WidgetTester tester,
  VideoPlayerEnvironment fixture,
) async {
  await tester.runAsync(fixture.initialize);
  await fixture.mount(tester, subtitleScreen);
  fixture.player.publishTracks(
    const mk.Tracks(
      audio: [
        mk.AudioTrack('1', 'English', 'eng'),
        mk.AudioTrack('2', 'Spanish audio', 'spa'),
      ],
      subtitle: [mk.SubtitleTrack('1', 'English', 'eng'), selectedTrack],
    ),
    selected: const mk.Track(
      audio: mk.AudioTrack('1', 'English', 'eng'),
      subtitle: mk.SubtitleTrack('1', 'English', 'eng'),
    ),
  );
  await fixture.advance(tester);
}

Future<Map<String, dynamic>?> preferences(WidgetTester tester) =>
    tester.runAsync<Map<String, dynamic>?>(
      () => TrackPreferencesStorage.getVideoTrackPreferences(
        videoTitle: subtitleScreen.title,
      ),
    );

void main() {
  testWidgets(
    'subtitle success then late failure restores selection with the persisted audio identity',
    (tester) async {
      final fixture = VideoPlayerEnvironment(native: true);
      await prepare(tester, fixture);
      try {
        final menu = await openPlayerMenu(tester, fixture);
        expect(
          await fixture.finish(
            tester,
            menu.onEmbeddedSubtitleSelected('2', '1'),
          ),
          isTrue,
        );
        expect(fixture.player.state.track.subtitle.id, '2');
        expect((await preferences(tester))?['subtitleTrackId'], '2');
        // An independent audio event after persistence must not overwrite the
        // audio identity captured by the accepted subtitle apply attempt.
        await fixture.player.setAudioTrack(
          const mk.AudioTrack('2', 'Spanish audio', 'spa'),
        );
        fixture.player.emit(
          'log',
          const mk.PlayerLog(
            prefix: 'sub',
            level: 'error',
            text: 'subtitle decoder failed',
          ),
        );
        await fixture.until(
          tester,
          () => fixture.player.state.track.subtitle.id == '1',
        );
        for (var i = 0; i < 10; i++) {
          await fixture.advance(tester, const Duration(milliseconds: 50));
        }
        final saved = await preferences(tester);
        expect(saved?['subtitleTrackId'], '1');
        expect(saved?['audioTrackId'], '1');
        expect(fixture.player.state.track.audio.id, '2');
        expect(find.textContaining('Couldn’t apply subtitles'), findsOneWidget);
        expect(
          (fixture.player.platform as FakeNativePlayer)
              .properties['sub-visibility'],
          'no',
        );
      } finally {
        await fixture.close(tester);
      }
    },
  );

  testWidgets(
    'subtitle rejected apply rolls back once and reports the original diagnostic id',
    (tester) async {
      final fixture = VideoPlayerEnvironment(native: true);
      await prepare(tester, fixture);
      final logs = <String>[];
      final previousPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };
      try {
        final menu = await openPlayerMenu(tester, fixture);
        fixture.player.calls.clear();
        fixture.player.failures['subtitle'] = StateError('fixture rejection');
        expect(
          await fixture.finish(
            tester,
            menu.onEmbeddedSubtitleSelected('2', '1'),
          ),
          isFalse,
        );
        expect(fixture.player.state.track.subtitle.id, '1');
        expect(
          fixture.player.calls
              .where((call) => call.$1 == 'subtitle')
              .map((call) => (call.$2 as mk.SubtitleTrack).id),
          ['2', '1'],
        );
        expect(await preferences(tester), isNull);
        expect(logs.join('\n'), contains('requestedId=2'));
        expect(logs.join('\n'), contains('source=player-menu-embedded'));
        expect(find.textContaining('Couldn’t apply subtitles'), findsOneWidget);
      } finally {
        debugPrint = previousPrint;
        await fixture.close(tester);
      }
    },
  );

  testWidgets(
    'external subtitle apply persists its addon identity and rolls back after a decoder error',
    (tester) async {
      final fixture = VideoPlayerEnvironment(native: true);
      await prepare(tester, fixture);
      const subtitle = StremioSubtitle(
        id: 'online-1',
        url: 'https://player.test/captions.srt',
        lang: 'eng',
        source: 'Fixture captions',
      );
      fixture.network.replies[subtitle.url] = http.Response(
        '1\n00:00:01,000 --> 00:00:02,000\nOriginal caption\n',
        200,
      );
      try {
        final menu = await openPlayerMenu(tester, fixture);
        expect(
          await fixture.finish(
            tester,
            menu.onAddonSubtitleSelected(subtitle, '1'),
          ),
          isTrue,
        );
        expect(fixture.player.state.track.subtitle.uri, isTrue);
        expect(
          (await preferences(tester))?['subtitleTrackId'],
          'stremio:online-1',
        );
        fixture.player.emit(
          'log',
          const mk.PlayerLog(
            prefix: 'sub',
            level: 'error',
            text: 'subtitle decoder failed',
          ),
        );
        await fixture.until(
          tester,
          () => fixture.player.state.track.subtitle.id == '1',
        );
        for (var i = 0; i < 10; i++) {
          await fixture.advance(tester, const Duration(milliseconds: 50));
        }
        expect((await preferences(tester))?['subtitleTrackId'], '1');
        expect(
          fixture.network.requests.where(
            (r) => r.url.toString() == subtitle.url,
          ),
          hasLength(1),
        );
      } finally {
        await fixture.close(tester);
      }
    },
  );
}
