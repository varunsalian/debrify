import 'dart:async';

import 'package:debrify/models/series_playlist.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/storage/episode_progress_storage.dart';
import 'package:debrify/services/storage/playlist_preferences_storage.dart';
import 'package:debrify/utils/series_parser.dart';
import 'package:debrify/widgets/view_mode_dropdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/playlist_content_fixture.dart';
import '../../../../support/playlist_content_profile.dart';
import 'playlist_content_progress_test.dart' show seedSeries;

void main() {
  for (final saved in [null, 'raw', 'sortedAZ']) {
    testWidgets(
      'initial automatic Series Arrange only when no saved mode $saved',
      (t) => playlistContentCase(t, (f) async {
        seedSeries(f);
        await f.mount(t, mode: saved);
        expect(
          f.member('currentViewMode'),
          saved == null
              ? FolderViewMode.seriesArrange
              : saved == 'raw'
              ? FolderViewMode.raw
              : FolderViewMode.sortedAZ,
        );
        expect(
          await t.runAsync(
            () => PlaylistPreferencesStorage.getPlaylistItemViewMode(f.item),
          ),
          saved ?? 'seriesArrange',
        );
      }),
    );
  }
  testWidgets(
    'recursive search nested path separator and case independent matches',
    (t) => playlistContentCase(t, (f) async {
      f.files = [
        {'id': 9, 'path': '/Outer/Inner/Two.MKV', 'bytes': 1, 'selected': 1},
        {'id': 2, 'path': '/Outer/Other/readme.txt', 'bytes': 1, 'selected': 1},
      ];
      await f.mount(t);
      f.member('toggleSearch')();
      f.member('performSearch')('tWo');
      final results = f.member('searchResults') as List;
      expect(results, hasLength(1));
      expect(results.single.path, 'Outer / Inner');
      expect(results.single.node.name, 'Two.MKV');
      await t.pump();
    }),
  );
  for (final key in [
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.space,
  ]) {
    testWidgets(
      'file card host activation key ${key.keyLabel} resolves selected file',
      (t) => playlistContentCase(t, (f) async {
        await f.mount(t);
        f.member('navigateIntoFolder')(f.root.children.single);
        await t.pump();
        final card = find.byType(FocusableActionDetector).first;
        final child = t.widget<FocusableActionDetector>(card).child;
        final node = Focus.of(t.element(find.byWidget(child)));
        node.requestFocus();
        await t.pump();
        final probe = PlaylistContentProbe(f)..install();
        try {
          await t.sendKeyEvent(key);
          await f.until(t, () => probe.calls == 2);
          expect(
            f.requests
                .where((r) => r.url.path.endsWith('/unrestrict/link'))
                .single
                .body,
            'link=https%3A%2F%2Flocked.test%2F9',
          );
          expect(probe.stops, 1);
        } finally {
          probe.remove();
        }
      }),
    );
  }
  testWidgets(
    'missing season post-frame change requires next scheduled frame',
    (t) => playlistContentCase(t, (f) async {
      seedSeries(f);
      await f.mount(t);
      final seasons = f.series.seasons;
      seasons.clear();
      seasons.add(
        SeriesSeason(seasonNumber: 2, episodes: f.series.allEpisodes),
      );
      expect(f.member('selectedSeasonNumber'), 1);
      f.member('applyViewMode')(FolderViewMode.seriesArrange);
      await t.pump();
      expect(f.member('selectedSeasonNumber'), 2);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await t.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Season 2'), findsOneWidget);
    }),
  );
  testWidgets(
    'episode card keeps five progress print lines and text',
    (t) => playlistContentCase(t, (f) async {
      seedSeries(f);
      await f.mount(t);
      f.progress['1_1'] = {'positionMs': 90, 'durationMs': 100};
      final lines = <String>[];
      await runZoned(
        () async {
          f.member('applyViewMode')(FolderViewMode.seriesArrange);
          await t.pump();
        },
        zoneSpecification: ZoneSpecification(
          print: (_, __, ___, line) {
            lines.add(line);
          },
        ),
      );
      expect(lines.take(4), [
        '🔍 Looking for progress with key: 1_1 for Episode 1',
        '💾 Available keys in cache: [1_1]',
        '✅ Found progress data: {positionMs: 90, durationMs: 100}',
        '📈 Progress: 90%, Finished: true',
      ]);
      f.progress.clear();
      lines.clear();
      await runZoned(
        () async {
          f.member('applyViewMode')(FolderViewMode.seriesArrange);
          await t.pump();
        },
        zoneSpecification: ZoneSpecification(
          print: (_, __, ___, line) {
            lines.add(line);
          },
        ),
      );
      expect(lines, contains('❌ No progress data found for key: 1_1'));
    }),
  );
  testWidgets(
    'watched defaults and model imdb preferred to item persist independent key',
    (t) => playlistContentCase(t, (f) async {
      seedSeries(f);
      await f.mount(t);
      f.series.imdbId = 'custom-series:model';
      f.item['imdbId'] = 'custom-series:item';
      final episode = SeriesEpisode(
        url: '',
        title: 'No numbers',
        filename: 'Movie.mkv',
        seriesInfo: SeriesInfo(isSeries: false),
        originalIndex: 0,
      );
      await f.invoke(
        t,
        () => f.member('toggleWatchedState')(episode) as Future<void>,
      );
      expect(
        await t.runAsync(
          () => EpisodeProgressStorage.isEpisodeFinished(
            seriesTitle: 'fixture',
            season: 1,
            episode: 1,
            imdbId: 'custom-series:model',
          ),
        ),
        isTrue,
      );
      expect(
        await t.runAsync(
          () => EpisodeProgressStorage.isEpisodeFinished(
            seriesTitle: 'fixture',
            season: 1,
            episode: 1,
            imdbId: 'custom-series:item',
          ),
        ),
        isFalse,
      );
      expect(
        f.progress,
        isEmpty,
        reason: 'Legacy reload reads title while toggle writes imdb key',
      );
      expect(find.text('Episode marked as watched'), findsOneWidget);
    }),
  );
  testWidgets(
    'watched stale captured read caught and error snackbar no profile writes',
    (t) => playlistContentCase(t, (f) async {
      seedSeries(f);
      await f.mount(t);
      final p = PlaylistContentProfiles();
      await t.runAsync(p.open);
      try {
        var switched = false;
        await t.runAsync(
          () => runZoned(
            () =>
                f.member('toggleWatchedState')(f.series.allEpisodes.first)
                    as Future<void>,
            zoneSpecification: ZoneSpecification(
              registerUnaryCallback:
                  <R, T>(self, parent, zone, R Function(T) callback) =>
                      parent.registerUnaryCallback(zone, (value) {
                        if (!switched && value is ProfilePreferences) {
                          switched = true;
                          p.switchTo(p.b);
                        }
                        return callback(value);
                      }),
            ),
          ),
        );
        await t.pump();
        expect(switched, isTrue);
        expect(
          find.textContaining(
            'Error updating watched state: Bad state: A stale ProfilePreferences instance',
          ),
          findsOneWidget,
        );
        expect(
          t.widget<SnackBar>(find.byType(SnackBar)).backgroundColor,
          Colors.red,
        );
        expect(
          await t.runAsync(
            () => EpisodeProgressStorage.getEpisodeProgress(
              seriesTitle: 'fixture',
            ),
          ),
          isEmpty,
        );
        expect(await t.runAsync(() => p.tombstones(p.b.profileId)), isEmpty);
        p.switchTo(p.a);
        expect(
          await t.runAsync(
            () => EpisodeProgressStorage.getEpisodeProgress(
              seriesTitle: 'fixture',
            ),
          ),
          isEmpty,
        );
        expect(await t.runAsync(() => p.tombstones(p.a.profileId)), isEmpty);
      } finally {
        await t.runAsync(p.close);
      }
    }),
  );
}
