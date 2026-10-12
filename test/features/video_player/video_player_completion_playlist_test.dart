import 'package:debrify/models/series_playlist.dart';
import 'package:debrify/models/playlist_view_mode.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/local_completion_storage.dart';
import 'package:debrify/utils/series_parser.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/local_completion_driver.dart';
import 'support/trakt_transport.dart';
import 'support/video_player_environment.dart';
import 'video_player_trakt_snapshots_test.dart'
    show traktBrowser, traktPlaylist;

const completionPlaylist = [
  ...traktPlaylist,
  PlaylistEntry(
    url: 'https://player.test/third.mp4',
    title: 'Trakt.Show.S01E03.mkv',
  ),
];

void main() {
  TraktTestTransport.install();
  for (final metadataId in [null, 'tt7123456']) {
    testWidgets(
      'Completion playlist uses parsed coordinates and ${metadataId == null ? 'launch fallback' : 'enriched'} identity',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = LocalCompletionDriver(t, f);
        await d.initialize();
        try {
          await d.mount(
            completionScreen(type: 'series', playlist: completionPlaylist),
          );
          final browser = await traktBrowser(t, f);
          browser.seriesPlaylist.imdbId = metadataId;
          final title = browser.seriesPlaylist.seriesTitle!;
          final id = metadataId ?? 'tt7100000';
          expect(browser.currentEpisodeIndex, 0);
          await d.percent(80);
          await d.drain();
          final map = await d.stateMap();
          expect(map.keys, contains(d.episodeKey(title: title, id: id)));
          final data = map[d.episodeKey(title: title, id: id)] as Map;
          expect(data['imdbId'], id);
          expect(data['finishedEpisodes']['1']['1']['finishedAt'], isA<int>());
          expect(data['finishedEpisodes']['2'], isNull);
        } finally {
          await d.close();
        }
      },
    );
  }

  testWidgets(
    'Completion missing current playlist metadata falls back to the first remaining episode and EOF later retries the restored entry',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = LocalCompletionDriver(t, f);
      await d.initialize();
      try {
        await d.mount(
          completionScreen(type: 'series', playlist: completionPlaylist),
        );
        final b = await traktBrowser(t, f);
        final title = b.seriesPlaylist.seriesTitle!;
        final removed = b.seriesPlaylist.allEpisodes.removeAt(0);
        expect(b.seriesPlaylist.allEpisodes.map((e) => e.originalIndex), [
          1,
          2,
        ]);
        await d.percent(80);
        await d.drain();
        expect(
          await d.finishedEpisode(title: title, season: 1, episode: 2),
          isNotNull,
        );
        expect(
          await d.finishedEpisode(title: title, season: 1, episode: 3),
          isNull,
        );
        final revision = LocalCompletionStorage.localCompletionRevision.value;
        b.seriesPlaylist.allEpisodes.insert(0, removed);
        await d.percent(85);
        await d.drain();
        expect(
          await d.finishedEpisode(title: title, season: 1, episode: 1),
          isNull,
        );
        expect(LocalCompletionStorage.localCompletionRevision.value, revision);
        await d.eof();
        await d.drain();
        expect(
          await d.finishedEpisode(title: title, season: 1, episode: 1),
          isNotNull,
        );
        expect(
          LocalCompletionStorage.localCompletionRevision.value,
          revision + 1,
        );
      } finally {
        await d.close();
      }
    },
  );

  for (final missing in ['season', 'episode']) {
    testWidgets(
      'Completion playlist missing $missing spends its position guard before metadata and EOF is the later retry',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = LocalCompletionDriver(t, f);
        await d.initialize();
        try {
          await d.mount(
            completionScreen(type: 'series', playlist: completionPlaylist),
          );
          final b = await traktBrowser(t, f);
          final title = b.seriesPlaylist.seriesTitle!;
          final original = b.seriesPlaylist.allEpisodes.first;
          // The guide publishes this mutable legacy model, as in P5/P6 reader
          // races. Exercise the player's normal position/EOF callers afterward.
          b.seriesPlaylist.allEpisodes[0] = SeriesEpisode(
            url: original.url,
            title: original.title,
            filename: original.filename,
            originalIndex: 0,
            seriesInfo: SeriesInfo(
              title: title,
              season: missing == 'season' ? null : 1,
              episode: missing == 'episode' ? null : 1,
              isSeries: true,
            ),
          );
          await d.percent(80);
          await d.drain();
          expect(
            await d.finishedEpisode(title: title, season: 1, episode: 1),
            isNull,
          );
          final revision = LocalCompletionStorage.localCompletionRevision.value;
          b.seriesPlaylist.allEpisodes[0] = original;
          await d.percent(85);
          await d.drain();
          expect(
            await d.finishedEpisode(title: title, season: 1, episode: 1),
            isNull,
          );
          expect(
            LocalCompletionStorage.localCompletionRevision.value,
            revision,
          );
          await d.eof();
          await d.drain();
          expect(
            await d.finishedEpisode(title: title, season: 1, episode: 1),
            isNotNull,
          );
          expect(
            LocalCompletionStorage.localCompletionRevision.value,
            revision + 1,
          );
        } finally {
          await d.close();
        }
      },
    );
  }

  for (final start in [-5, 99]) {
    testWidgets(
      'Completion public stale playlist index $start is clamped before marking',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = LocalCompletionDriver(t, f);
        await d.initialize();
        try {
          await d.mount(
            completionScreen(
              type: 'series',
              playlist: completionPlaylist,
              startIndex: start,
              disableAutoResume: true,
            ),
          );
          final b = await traktBrowser(t, f);
          final expected = start < 0 ? 0 : 2;
          expect(b.currentEpisodeIndex, expected);
          await d.percent(80);
          await d.drain();
          expect(
            await d.finishedEpisode(
              title: b.seriesPlaylist.seriesTitle!,
              season: 1,
              episode: expected + 1,
            ),
            isNotNull,
          );
        } finally {
          await d.close();
        }
      },
    );
  }

  testWidgets(
    'Completion non-series playlist still uses single-file launch coordinates when catalog type is series',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = LocalCompletionDriver(t, f);
      await d.initialize();
      try {
        await d.mount(
          completionScreen(
            type: 'series',
            playlist: completionPlaylist,
            viewMode: PlaylistViewMode.raw,
          ),
        );
        await d.percent(80);
        await d.drain();
        expect(await d.finishedEpisode(), isNotNull);
        expect(await d.finishedEpisode(season: 1, episode: 1), isNull);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'Completion playlist switch resets the position one-shot after target switching and marks the incoming episode',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = LocalCompletionDriver(t, f);
      await d.initialize();
      try {
        await d.mount(
          completionScreen(type: 'series', playlist: completionPlaylist),
        );
        final b = await traktBrowser(t, f);
        final title = b.seriesPlaylist.seriesTitle!;
        await d.percent(80);
        await d.drain();
        expect(
          await d.finishedEpisode(title: title, season: 1, episode: 1),
          isNotNull,
        );
        final revision = LocalCompletionStorage.localCompletionRevision.value;
        await f.finish(t, b.onEpisodeSelected(1, 2));
        await d.drain();
        await d.percent(80);
        await d.drain();
        expect(
          await d.finishedEpisode(title: title, season: 1, episode: 2),
          isNotNull,
        );
        expect(
          LocalCompletionStorage.localCompletionRevision.value,
          revision + 1,
        );
        expect(f.player.calls.where((c) => c.$1 == 'open'), hasLength(2));
      } finally {
        await d.close();
      }
    },
  );
}
