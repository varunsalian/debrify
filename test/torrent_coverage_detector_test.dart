import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/utils/torrent_coverage_detector.dart';

CoverageType detect(String name) =>
    TorrentCoverageDetector.detectCoverage(title: name).coverageType;

void main() {
  group('single season packs are NOT complete series', () {
    // The Rick and Morty bug: dotted scene names hid the "Season.3" token
    // from the single-season check, so standalone "Complete" won.
    test('dotted "Season.N.Complete"', () {
      expect(
        detect('Rick.and.Morty.Season.3.Complete.1080p.UNCENSORED.WEB-DL'),
        CoverageType.seasonPack,
      );
    });

    test('dotted "Complete.Season.N"', () {
      expect(
        detect('Rick.and.Morty.Complete.Season.3.1080p.WEB-DL'),
        CoverageType.seasonPack,
      );
    });

    test('spaced "Season N Complete"', () {
      expect(
        detect('Rick and Morty Season 3 Complete 1080p WEB-DL'),
        CoverageType.seasonPack,
      );
    });

    test('dotted "SNN.Complete"', () {
      expect(
        detect('Rick.and.Morty.S03.Complete.1080p'),
        CoverageType.seasonPack,
      );
    });

    test('underscored "Season_N_Complete"', () {
      expect(
        detect('Rick_and_Morty_Season_3_Complete_1080p'),
        CoverageType.seasonPack,
      );
    });

    test('bare "Season N" with no complete keyword is a pack', () {
      expect(
        detect('Rick.and.Morty.Season.3.1080p.WEB-DL.x264'),
        CoverageType.seasonPack,
      );
      expect(
        detect('Better Call Saul Season 2 720p'),
        CoverageType.seasonPack,
      );
    });

    test('season number is extracted from dotted names', () {
      final info = TorrentCoverageDetector.detectCoverage(
        title: 'Rick.and.Morty.Season.3.Complete.1080p',
      );
      expect(info.seasonNumber, 3);
    });
  });

  group('complete series stays complete series', () {
    test('explicit keyword', () {
      expect(
        detect('Game.of.Thrones.Complete.Series.2160p'),
        CoverageType.completeSeries,
      );
      expect(
        detect('Rik Mayall Believe Nothing Entire Series DVDRip'),
        CoverageType.completeSeries,
      );
    });

    test('wide S-ranges', () {
      expect(
        detect('Rick and Morty.2013.S01-08.1080p.WEB-DL'),
        CoverageType.completeSeries,
      );
      expect(
        detect('Rick and Morty (2013-2025) [S01-S08] [MULTI]'),
        CoverageType.completeSeries,
      );
      expect(
        detect('Рик и Морти / Rick and Morty [S01-08] (2013)'),
        CoverageType.completeSeries,
      );
    });

    test('standalone complete with no season token', () {
      expect(
        detect('Game of Thrones (2011) COMPLETE 2160p'),
        CoverageType.completeSeries,
      );
      expect(
        detect('Breaking.Bad.COMPLETE.1080p.BluRay'),
        CoverageType.completeSeries,
      );
    });

    test('dotted season range', () {
      expect(
        detect('The.Wire.Season.1-5.Complete.720p'),
        CoverageType.completeSeries,
      );
    });
  });

  group('multi-season packs', () {
    test('two-season range without complete keyword', () {
      expect(detect('Severance S01-S02 2160p'), CoverageType.multiSeasonPack);
      expect(
        detect('Severance.Seasons.1.&.2.1080p'),
        CoverageType.multiSeasonPack,
      );
    });
  });

  group('single episodes stay single episodes', () {
    test('standard S/E forms', () {
      expect(
        detect('Rick.and.Morty.S03E05.1080p.WEB-DL'),
        CoverageType.singleEpisode,
      );
      expect(
        detect('Rick and Morty S03E05 720p'),
        CoverageType.singleEpisode,
      );
    });

    test('dotted S.E form', () {
      // "S01.E01" — the dot previously hid the episode marker from the
      // season-pack lookahead, misclassifying the episode as a pack.
      expect(
        detect('Show.Name.S01.E01.1080p'),
        CoverageType.singleEpisode,
      );
    });

    test('"Season N Episode M" wording', () {
      expect(
        detect('Rick and Morty Season 3 Episode 5 HDTV'),
        CoverageType.singleEpisode,
      );
    });

    test('"Season N" separated from the episode marker', () {
      expect(
        detect('Rick and Morty Season 3 - Episode 5 HDTV'),
        CoverageType.singleEpisode,
      );
      expect(
        detect('Rick and Morty Season 3, Episode 5 HDTV'),
        CoverageType.singleEpisode,
      );
      expect(
        detect('Rick and Morty Season 3 - Ep. 5 HDTV'),
        CoverageType.singleEpisode,
      );
    });
  });

  group('years are not season ranges', () {
    test('"Season N - YYYY" stays a season pack', () {
      // The year's first two digits must not be read as the range end
      // ({start: 3, end: 20} → bogus Complete Series).
      expect(
        detect('True Detective Season 3 - 2019 1080p WEB-DL'),
        CoverageType.seasonPack,
      );
      expect(
        detect('True.Detective.Season.3.-.2019.1080p'),
        CoverageType.seasonPack,
      );
    });

    test('real ranges still work next to years', () {
      expect(
        detect('Rick and Morty (2013-2025) S01-S08 1080p'),
        CoverageType.completeSeries,
      );
    });
  });
}
