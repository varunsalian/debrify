import 'package:debrify/models/rd_file_node.dart';
import 'package:debrify/models/series_playlist.dart';
import 'package:debrify/utils/series_parser.dart';
import 'package:debrify/widgets/view_mode_dropdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/playlist_content_fixture.dart';

RDFileNode progressFile(String name, {String? path}) => RDFileNode.file(
  name: name,
  fileId: 91,
  path: path ?? name,
  bytes: 1,
  linkIndex: 0,
);
SeriesEpisode episode(int number) => SeriesEpisode(
  url: '',
  title: 'Episode $number',
  filename: 'Fixture.S02E0$number.mkv',
  seriesInfo: SeriesInfo(isSeries: true, season: 2, episode: number),
  originalIndex: number - 1,
);
void seedSeries(PlaylistContentFixture f, {int count = 4}) {
  f.item['title'] = 'Fixture';
  f.files = [
    for (var i = count; i >= 1; i--)
      {
        'id': i * 3,
        'path': '/Pack/Fixture.S01E${i.toString().padLeft(2, '0')}.mkv',
        'bytes': 200000000,
        'selected': 1,
      },
  ];
}

void main() {
  testWidgets(
    'progress parsed hit sequential null sorted index and absent-file fallback',
    (t) => playlistContentCase(t, (f) async {
      await f.mount(t);
      final hit = {'positionMs': 77, 'durationMs': 100};
      final filename = {'positionMs': 44, 'durationMs': 100};
      f.progress.addAll({'1_2': hit, '2. Two.mkv': filename});
      expect(
        identical(
          f.member('getProgressForFile')(progressFile('Fixture.S01E02.mkv')),
          hit,
        ),
        isTrue,
      );
      final two = f.root.getAllFiles()[1];
      expect(f.member('getProgressForFile')(two), isNull);
      expect(
        identical(
          f.member('getProgressForFile')(
            progressFile(two.name, path: 'absent'),
          ),
          filename,
        ),
        isTrue,
      );
      f.progress['0_2'] = hit;
      expect(identical(f.member('getProgressForFile')(two), hit), isTrue);
      f.member('applyViewMode')(FolderViewMode.sortedAZ);
      expect(f.member('getProgressForFile')(two), isNull);
      f.progress['0_1'] = filename;
      expect(identical(f.member('getProgressForFile')(two), filename), isTrue);
      await t.pump();
    }),
  );
  testWidgets(
    'progress filename fallback with absent root',
    (t) => playlistContentCase(t, (f) async {
      f.item.remove('rdTorrentId');
      await f.mount(t);
      final hit = {'positionMs': 1};
      f.progress['Absent.mkv'] = hit;
      expect(f.member('rootContent'), isNull);
      expect(
        identical(
          f.member('getProgressForFile')(progressFile('Absent.mkv')),
          hit,
        ),
        isTrue,
      );
    }),
  );
  for (final value in <Object>[
    2000000000000,
    '2000000000',
    '2000000000000',
    '2033-05-18T03:33:20Z',
  ]) {
    testWidgets(
      'latest updatedAt $value selects same season and episode',
      (t) => playlistContentCase(t, (f) async {
        await f.mount(t);
        f.progress.addAll({
          '1_1': {'updatedAt': 1900000000000},
          '2_2': {'updatedAt': value},
          '2_1': {'updatedAt': 'bad timestamp'},
        });
        expect(f.member('determineInitialSeason')(), 2);
        final season = SeriesSeason(
          seasonNumber: 2,
          episodes: [episode(1), episode(2)],
        );
        expect(f.member('determineInitialEpisodeIndex')(season), 1);
      }),
    );
  }
  testWidgets(
    'timestamp ties keep first entry invalid types and strings ignored',
    (t) => playlistContentCase(t, (f) async {
      await f.mount(t);
      f.progress.addAll({
        '2_2': {'updatedAt': 2000000000000},
        '1_1': {'updatedAt': '2000000000'},
        '2_1': {'updatedAt': '2000000000000'},
        '3_1': {'updatedAt': 9.2},
        '4_1': {'updatedAt': 'invalid'},
      });
      expect(f.member('determineInitialSeason')(), 2);
      expect(
        f.member('determineInitialEpisodeIndex')(
          SeriesSeason(seasonNumber: 2, episodes: [episode(1), episode(2)]),
        ),
        1,
      );
      f.progress.clear();
      expect(f.member('determineInitialSeason')(), 1);
      expect(
        f.member('determineInitialEpisodeIndex')(
          SeriesSeason(seasonNumber: 2, episodes: [episode(1)]),
        ),
        isNull,
      );
    }),
  );
  final boundaries = [
    (890000, 1000000, true),
    (8900000, 10000000, false),
    (9000000, 10000000, true),
    (880000, 1000000, false),
    (880001, 1000000, true),
    (0, 1, true),
  ];
  for (final (position, duration, finished) in boundaries) {
    testWidgets(
      'episode completion position=$position duration=$duration finished=$finished',
      (t) => playlistContentCase(t, (f) async {
        seedSeries(f);
        await f.mount(t, mode: 'raw', width: 500);
        f.member('applyViewMode')(FolderViewMode.seriesArrange);
        await t.pump();
        await f.until(
          t,
          () => PaintingBinding.instance.imageCache.pendingImageCount == 0,
        );
        f.progress['1_1'] = {'positionMs': position, 'durationMs': duration};
        f.member('setAndroidTv')(false);
        await t.pump();
        final watched = find.byIcon(Icons.check);
        expect(watched, finished ? findsOneWidget : findsNothing);
      }),
    );
  }
  testWidgets(
    'unattached scroll retries 100 200 300 ms replacement and disposal',
    (t) => playlistContentCase(t, (f) async {
      await f.mount(t);
      f.member('scrollToEpisode')(2);
      final first = f.member('scrollRetryTimer');
      expect(first.isActive, isTrue);
      await t.pump(const Duration(milliseconds: 99));
      expect(identical(f.member('scrollRetryTimer'), first), isTrue);
      await t.pump(const Duration(milliseconds: 1));
      final second = f.member('scrollRetryTimer');
      expect(identical(first, second), isFalse);
      expect(first.isActive, isFalse);
      await t.pump(const Duration(milliseconds: 199));
      expect(identical(f.member('scrollRetryTimer'), second), isTrue);
      await t.pump(const Duration(milliseconds: 1));
      final third = f.member('scrollRetryTimer');
      expect(identical(second, third), isFalse);
      await t.pump(const Duration(milliseconds: 299));
      expect(third.isActive, isTrue);
      await t.pump(const Duration(milliseconds: 1));
      expect(third.isActive, isFalse);
      f.member('scrollToEpisode')(2);
      final last = f.member('scrollRetryTimer');
      await t.pumpWidget(const SizedBox.shrink());
      expect(last.isActive, isFalse);
      await t.pump(const Duration(seconds: 1));
    }),
  );
  testWidgets(
    'attached scheduled scroll uses latest episode and 800 ms animation',
    (t) => playlistContentCase(t, (f) async {
      seedSeries(f, count: 20);
      await f.mount(t, mode: 'raw');
      f.progress['1_8'] = {'updatedAt': 2000000000000};
      f.member('applyViewMode')(FolderViewMode.seriesArrange);
      await t.pump();
      await t.pump();
      final controller =
          f.member('episodeListScrollController') as ScrollController;
      expect(controller.hasClients, isTrue);
      expect(f.member('targetEpisodeIndex'), 7);
      expect(controller.offset, 0);
      await t.pump(const Duration(milliseconds: 400));
      expect(controller.offset, greaterThan(0));
      expect(controller.offset, lessThan(7 * 124));
      await t.pump(const Duration(milliseconds: 400));
      expect(controller.offset, 7 * 124);
      expect(f.member('isScrollScheduled'), isFalse);
    }),
  );
}
