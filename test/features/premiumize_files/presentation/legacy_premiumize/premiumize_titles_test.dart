import 'package:debrify/utils/series_parser.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../../support/premiumize_files_fixture.dart';

void main() {
  testWidgets(
    'real title helpers preserve episode labels and collection fallbacks',
    (t) => premiumizeCase(t, (f) async {
      await f.mount(t);
      const episode = SeriesInfo(
        title: ' Show ',
        season: 1,
        episode: 2,
        episodeTitle: ' Label ',
        isSeries: true,
      );
      expect(
        f.member('formatPlaylistTitle')(
          info: episode,
          fallback: 'original.mkv',
          isSeriesCollection: true,
        ),
        'S01E02 · Label',
      );
      expect(
        f.member('formatPlaylistTitle')(
          info: episode,
          fallback: 'original.mkv',
          isSeriesCollection: false,
        ),
        'original.mkv',
      );
      expect(
        f.member('formatPlaylistTitle')(
          info: const SeriesInfo(
            title: 'Title',
            season: 2,
            episode: 3,
            isSeries: true,
          ),
          fallback: 'original.mkv',
          isSeriesCollection: true,
        ),
        'S02E03 · Title',
      );
      expect(
        f.member('formatPlaylistTitle')(
          info: const SeriesInfo(isSeries: false),
          fallback: 'original.mkv',
          isSeriesCollection: true,
        ),
        'original.mkv',
      );
      expect(
        f.member('composeEntryTitle')(
          seriesTitle: ' Show._-',
          episodeLabel: 'S01E02 · Label',
          isSeriesCollection: true,
          fallback: 'original.mkv',
        ),
        'Show S01E02 · Label',
      );
      expect(
        f.member('composeEntryTitle')(
          seriesTitle: null,
          episodeLabel: 'Label',
          isSeriesCollection: true,
          fallback: 'original.mkv',
        ),
        'original.mkv',
      );
      expect(
        f.member('composeEntryTitle')(
          seriesTitle: 'Show',
          episodeLabel: 'Label',
          isSeriesCollection: false,
          fallback: 'original.mkv',
        ),
        'original.mkv',
      );
    }),
  );
  testWidgets(
    'real first episode helper chooses season then episode not filename index',
    (t) => premiumizeCase(t, (f) async {
      await f.mount(t);
      final infos = [
        const SeriesInfo(season: 2, episode: 1, isSeries: true),
        const SeriesInfo(season: 1, episode: 3, isSeries: true),
        const SeriesInfo(season: 1, episode: 1, isSeries: true),
        const SeriesInfo(season: 0, episode: 1, isSeries: false),
      ];
      expect(f.member('findFirstEpisodeIndex')(infos), 2);
      expect(f.member('findFirstEpisodeIndex')(<SeriesInfo>[]), 0);
      expect(
        f.member('findFirstEpisodeIndex')([const SeriesInfo(isSeries: false)]),
        0,
      );
    }),
  );
}
