import 'package:debrify/models/playlist_view_mode.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/storage/local_completion_storage.dart';
import 'package:flutter_test/flutter_test.dart';
// Existing resolved transport; application dependencies stay frozen.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'support/local_completion_driver.dart';
import 'support/trakt_transport.dart';
import 'support/video_player_environment.dart';
import 'video_player_completion_playlist_test.dart' show completionPlaylist;
import 'video_player_trakt_snapshots_test.dart' show traktBrowser;

void main() {
  TraktTestTransport.install();
  testWidgets(
    'Completion parsed series playlist supplies completion when catalog type is absent',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = LocalCompletionDriver(t, f);
      await d.initialize();
      try {
        await d.mount(
          completionScreen(type: null, playlist: completionPlaylist),
        );
        final browser = await traktBrowser(t, f);
        expect(browser.seriesPlaylist.isSeries, isTrue);
        await d.percent(80);
        await d.drain();
        expect(
          await d.finishedEpisode(
            title: browser.seriesPlaylist.seriesTitle!,
            season: 1,
            episode: 1,
          ),
          isNotNull,
        );
      } finally {
        await d.close();
      }
    },
  );
  testWidgets(
    'Completion nameless forced series playlist remains unmarked on positions and repeated EOF',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = LocalCompletionDriver(t, f);
      await d.initialize();
      try {
        await d.mount(
          completionScreen(
            type: 'series',
            title: '',
            contentTitle: null,
            viewMode: PlaylistViewMode.series,
            playlist: const [
              PlaylistEntry(
                url: 'https://player.test/nameless-1.mp4',
                title: '',
              ),
              PlaylistEntry(
                url: 'https://player.test/nameless-2.mp4',
                title: '',
              ),
            ],
          ),
        );
        final browser = await traktBrowser(t, f);
        expect(browser.seriesPlaylist.isSeries, isTrue);
        expect(browser.seriesPlaylist.seriesTitle, isNull);
        final revision = LocalCompletionStorage.localCompletionRevision.value;
        await d.percent(85);
        await d.drain();
        await d.percent(90);
        await d.eof();
        await d.eof();
        await d.drain();
        expect(
          (await d.stateMap()).values.where(
            (value) => value is Map && value['finishedEpisodes'] != null,
          ),
          isEmpty,
        );
        expect(LocalCompletionStorage.localCompletionRevision.value, revision);
        expect(d.uncaught, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'Completion caught playlist write failure spends the position guard and EOF retries after storage recovers',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = LocalCompletionDriver(t, f);
      await d.initialize();
      final previous = SharedPreferencesStorePlatform.instance;
      CompletionWrites? writes;
      try {
        await d.mount(
          completionScreen(type: 'series', playlist: completionPlaylist),
        );
        final browser = await traktBrowser(t, f);
        final title = browser.seriesPlaylist.seriesTitle!;
        writes = await t.runAsync(CompletionWrites.install);
        writes!.reject = (key) => key.endsWith('playback_state_v1');
        await d.percent(85);
        await d.drain();
        expect(d.uncaught, isEmpty);
        expect(
          writes.writes.where(
            (write) => write.$1.endsWith('playback_state_v1'),
          ),
          hasLength(1),
        );
        expect(
          await d.finishedEpisode(title: title, season: 1, episode: 1),
          isNotNull,
          reason: 'The rejected write already changed the preference cache',
        );
        expect(
          decodeCompletionPhysical(
            await writes.physical(
              ProfileRuntime.capture(),
              'playback_state_v1',
            ),
          ),
          isEmpty,
        );
        writes.reject = null;
        await d.percent(90);
        await d.drain();
        expect(
          writes.writes.where(
            (write) => write.$1.endsWith('playback_state_v1'),
          ),
          hasLength(1),
        );
        await d.eof();
        await d.drain();
        expect(
          await d.finishedEpisode(title: title, season: 1, episode: 1),
          isNotNull,
        );
        expect(
          decodeCompletionPhysical(
            await writes.physical(
              ProfileRuntime.capture(),
              'playback_state_v1',
            ),
          ).keys,
          contains(d.episodeKey(title: title)),
        );
      } finally {
        writes?.reject = null;
        await d.close();
        SharedPreferencesStorePlatform.instance = previous;
      }
    },
  );
}
