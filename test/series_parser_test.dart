import 'package:flutter_test/flutter_test.dart';
import '../lib/utils/series_parser.dart';

void main() {
  group('SeriesParser Tests', () {
    test('should parse S01E02 format', () {
      final result = SeriesParser.parseFilename('Breaking Bad S01E02.mkv');
      expect(result.isSeries, true);
      expect(result.title, 'Breaking Bad');
      expect(result.season, 1);
      expect(result.episode, 2);
    });

    test('should parse S1E2 format', () {
      final result = SeriesParser.parseFilename('Game of Thrones S1E2.mp4');
      expect(result.isSeries, true);
      expect(result.title, 'Game of Thrones');
      expect(result.season, 1);
      expect(result.episode, 2);
    });

    test('should parse 1x02 format', () {
      final result = SeriesParser.parseFilename('The Office 1x02.avi');
      expect(result.isSeries, true);
      expect(result.title, 'The Office');
      expect(result.season, 1);
      expect(result.episode, 2);
    });

    test('should parse 01.02 format', () {
      final result = SeriesParser.parseFilename('Friends 01.02.mkv');
      expect(result.isSeries, true);
      expect(result.title, 'Friends');
      expect(result.season, 1);
      expect(result.episode, 2);
    });

    test('should parse Season 1 Episode 2 format', () {
      final result = SeriesParser.parseFilename('Stranger Things Season 1 Episode 2.mp4');
      expect(result.isSeries, true);
      expect(result.title, null); // Now returns null, will use collection title
      expect(result.season, 1);
      expect(result.episode, 2);
    });

    test('should parse Episode 2 format', () {
      final result = SeriesParser.parseFilename('The Mandalorian Episode 2.mkv');
      expect(result.isSeries, true);
      expect(result.episode, 2);
    });

    test('should parse E02 format', () {
      final result = SeriesParser.parseFilename('The Witcher E02.mp4');
      expect(result.isSeries, true);
      expect(result.episode, 2);
    });

    test('should extract quality information', () {
      final result = SeriesParser.parseFilename('Breaking Bad S01E02 1080p.mkv');
      expect(result.isSeries, true);
      expect(result.quality, '1080p');
    });

    test('should extract year information', () {
      final result = SeriesParser.parseFilename('Breaking Bad (2008) S01E02.mkv');
      expect(result.isSeries, true);
      expect(result.year, 2008);
    });

    test('should identify non-series files', () {
      final result = SeriesParser.parseFilename('The Matrix (1999).mkv');
      expect(result.isSeries, false);
      expect(result.title, 'The Matrix');
      expect(result.year, 1999);
    });

    test('should detect series playlist', () {
      final filenames = [
        'Breaking Bad S01E01.mkv',
        'Breaking Bad S01E02.mkv',
        'Breaking Bad S01E03.mkv',
      ];
      expect(SeriesParser.isSeriesPlaylist(filenames), true);
    });

    test('should detect non-series playlist', () {
      final filenames = [
        'The Matrix (1999).mkv',
        'Inception (2010).mkv',
        'Interstellar (2014).mkv',
      ];
      expect(SeriesParser.isSeriesPlaylist(filenames), false);
    });

    // Bracket notation format tests
    test('should parse bracket notation [S.E] format', () {
      final result = SeriesParser.parseFilename('[7.22] Goodbye, Michael.avi');
      expect(result.isSeries, true);
      expect(result.season, 7);
      expect(result.episode, 22);
      expect(result.episodeTitle, 'Goodbye, Michael');
      expect(result.title, null); // No series title in filename, will use collection title
    });

    test('should parse bracket notation [S.E.E] multi-episode format', () {
      final result = SeriesParser.parseFilename('[9.24.25] Finale.mp4');
      expect(result.isSeries, true);
      expect(result.season, 9);
      expect(result.episode, 24);
      expect(result.episodeTitle, 'Finale (Episodes 24-25)');
    });

    test('should parse bracket notation with leading zeros', () {
      final result = SeriesParser.parseFilename('[5.01.02] Weight Loss.avi');
      expect(result.isSeries, true);
      expect(result.season, 5);
      expect(result.episode, 1);
      expect(result.episodeTitle, 'Weight Loss (Episodes 1-2)');
    });

    test('should parse bracket notation single episode', () {
      final result = SeriesParser.parseFilename('[8.14] Special Project.avi');
      expect(result.isSeries, true);
      expect(result.season, 8);
      expect(result.episode, 14);
      expect(result.episodeTitle, 'Special Project');
    });

    test('should validate series titles correctly', () {
      expect(SeriesParser.isValidSeriesTitle('The Office'), true);
      expect(SeriesParser.isValidSeriesTitle('Game of Thrones'), true);
      expect(SeriesParser.isValidSeriesTitle('['), false);
      expect(SeriesParser.isValidSeriesTitle(']'), false);
      expect(SeriesParser.isValidSeriesTitle(''), false);
      expect(SeriesParser.isValidSeriesTitle(null), false);
      expect(SeriesParser.isValidSeriesTitle('A'), false);
      expect(SeriesParser.isValidSeriesTitle('   '), false);
      expect(SeriesParser.isValidSeriesTitle('...'), false);
      expect(SeriesParser.isValidSeriesTitle('_-_'), false);
    });

    test('should detect bracket notation playlist as series', () {
      final filenames = [
        '[9.24.25] Finale.mp4',
        '[7.22] Goodbye, Michael.avi',
        '[5.01.02] Weight Loss.avi',
        '[8.14] Special Project.avi',
      ];
      expect(SeriesParser.isSeriesPlaylist(filenames), true);
    });
  });

  group('cleanCollectionTitle Tests', () {
    test('should clean collection title with season range and release group', () {
      final result = SeriesParser.cleanCollectionTitle('The Office - Complete Season 1-9 [F4S7]');
      expect(result, 'The Office');
    });

    test('should clean complete series with S##-S## format', () {
      final result = SeriesParser.cleanCollectionTitle('Breaking Bad S01-S05 COMPLETE [x265]');
      expect(result, 'Breaking Bad');
    });

    test('should clean with year range and quality tags', () {
      final result = SeriesParser.cleanCollectionTitle('Game of Thrones - Complete Series (2011-2019) [1080p] [BluRay]');
      expect(result, 'Game of Thrones');
    });

    test('should normalize country codes and clean metadata', () {
      final result = SeriesParser.cleanCollectionTitle('The Office [US] - Complete Series');
      expect(result, 'The Office US');
    });

    test('should normalize country codes in parentheses', () {
      final result = SeriesParser.cleanCollectionTitle('Shameless (US) (2011-2021)');
      expect(result, 'Shameless US');
    });

    test('should preserve numbers in show title like Beverly Hills 90210', () {
      final result = SeriesParser.cleanCollectionTitle('Beverly Hills 90210');
      expect(result, 'Beverly Hills 90210');
    });

    test('should preserve That 70s Show with year range removed', () {
      final result = SeriesParser.cleanCollectionTitle('That \'70s Show (1998-2006)');
      expect(result, 'That \'70s Show');
    });

    test('should clean The 100 with quality tags', () {
      final result = SeriesParser.cleanCollectionTitle('The 100 - Complete Series [1080p]');
      expect(result, 'The 100');
    });

    test('should preserve 9-1-1 (not a season range)', () {
      final result = SeriesParser.cleanCollectionTitle('9-1-1 Season 1-6');
      expect(result, '9-1-1');
    });

    test('should not modify simple titles without metadata', () {
      final result = SeriesParser.cleanCollectionTitle('Breaking Bad');
      expect(result, 'Breaking Bad');
    });

    test('should clean dots and multiple tags', () {
      final result = SeriesParser.cleanCollectionTitle('Star.Wars.The.Complete.Saga.(1977-2005).[1080p]');
      expect(result, 'Star Wars The Complete Saga');
    });

    test('should return original if result would be empty', () {
      final result = SeriesParser.cleanCollectionTitle('[YIFY] [1080p]');
      expect(result, '[YIFY] [1080p]');
    });

    test('should preserve special characters in show titles', () {
      final result = SeriesParser.cleanCollectionTitle('Marvel\'s Agents of S.H.I.E.L.D. S01-S07');
      // Dots are replaced with spaces, S01-S07 is removed
      expect(result, 'Marvel\'s Agents of S H I E L D');
    });

    test('should clean multiple quality tags', () {
      final result = SeriesParser.cleanCollectionTitle('The Office - Complete Series [1080p] [BluRay] [x265] [YIFY]');
      expect(result, 'The Office');
    });

    test('should handle underscores as separators', () {
      final result = SeriesParser.cleanCollectionTitle('The_Office_S01-S09_1080p');
      expect(result, 'The Office');
    });

    test('should clean multiple bracket types', () {
      final result = SeriesParser.cleanCollectionTitle('The Office [1080p] {RARBG} (US)');
      expect(result, 'The Office US');
    });

    test('should remove trailing year but keep in-title years', () {
      final result = SeriesParser.cleanCollectionTitle('The 4400 (2004-2007)');
      expect(result, 'The 4400');
    });

    test('should preserve show title with The', () {
      final result = SeriesParser.cleanCollectionTitle('The Office');
      expect(result, 'The Office');
    });

    test('should clean season ranges in different formats', () {
      final result = SeriesParser.cleanCollectionTitle('Friends - Seasons 1-10 [720p]');
      expect(result, 'Friends');
    });

    test('should handle All Seasons keyword', () {
      final result = SeriesParser.cleanCollectionTitle('Breaking Bad - All Seasons [1080p]');
      expect(result, 'Breaking Bad');
    });

    test('should remove edition tags', () {
      final result = SeriesParser.cleanCollectionTitle('The Office - Complete Series Extended Edition [BluRay]');
      expect(result, 'The Office');
    });

    test('should clean WEB-DL and WEBRip tags', () {
      final result = SeriesParser.cleanCollectionTitle('Game of Thrones S01-S08 WEB-DL 1080p [HEVC]');
      expect(result, 'Game of Thrones');
    });

    test('should remove audio codec tags', () {
      final result = SeriesParser.cleanCollectionTitle('Breaking Bad Complete Series 1080p AAC 5.1 x265');
      expect(result, 'Breaking Bad');
    });

    test('should preserve UK country code', () {
      final result = SeriesParser.cleanCollectionTitle('The Office [UK] - Complete Series');
      expect(result, 'The Office UK');
    });

    test('should handle Complete Collection keyword', () {
      final result = SeriesParser.cleanCollectionTitle('Star Trek The Next Generation - Complete Collection');
      expect(result, 'Star Trek The Next Generation');
    });

    test('should clean multiple season patterns', () {
      final result = SeriesParser.cleanCollectionTitle('The Office Complete Season 1-9 S01-S09 [1080p]');
      expect(result, 'The Office');
    });

    test('should preserve numerical show titles like 24', () {
      final result = SeriesParser.cleanCollectionTitle('24 - Complete Series [1080p]');
      expect(result, '24');
    });

    test('should handle 4K and UHD tags', () {
      final result = SeriesParser.cleanCollectionTitle('Game of Thrones - Complete Series [4K UHD] [HDR]');
      expect(result, 'Game of Thrones');
    });

    test('should remove DTS and Atmos audio tags', () {
      final result = SeriesParser.cleanCollectionTitle('Breaking Bad S01-S05 1080p DTS Atmos');
      expect(result, 'Breaking Bad');
    });

    test('should clean multiple release groups', () {
      final result = SeriesParser.cleanCollectionTitle('The Office [RARBG] [PublicHD] [1080p]');
      expect(result, 'The Office');
    });

    test('should handle Directors Cut edition tag', () {
      final result = SeriesParser.cleanCollectionTitle('Twin Peaks - Complete Series Directors Cut [BluRay]');
      expect(result, 'Twin Peaks');
    });

    test('should preserve show title even with minimal content', () {
      final result = SeriesParser.cleanCollectionTitle('IT');
      expect(result, 'IT');
    });

    test('should clean HDRip and BRRip tags', () {
      final result = SeriesParser.cleanCollectionTitle('Breaking Bad S01-S05 BRRip 720p');
      expect(result, 'Breaking Bad');
    });

    test('should handle multiple quality indicators', () {
      final result = SeriesParser.cleanCollectionTitle('Game of Thrones 4K 2160p HEVC 10bit HDR');
      expect(result, 'Game of Thrones');
    });

    test('should clean standalone year at end', () {
      final result = SeriesParser.cleanCollectionTitle('Breaking Bad - Complete Series 2013');
      expect(result, 'Breaking Bad');
    });

    test('should handle remastered edition tag', () {
      final result = SeriesParser.cleanCollectionTitle('Star Trek TNG - Remastered Complete Series [1080p]');
      expect(result, 'Star Trek TNG');
    });

    test('should preserve and normalize Australian country code', () {
      final result = SeriesParser.cleanCollectionTitle('MasterChef [AU] - Complete Season');
      expect(result, 'MasterChef AU');
    });

    test('should clean curly brace release groups', () {
      final result = SeriesParser.cleanCollectionTitle('The Office {YIFY} - Complete Series');
      expect(result, 'The Office');
    });

    test('should handle DVDRip and HDTV tags', () {
      final result = SeriesParser.cleanCollectionTitle('Friends - Complete Series DVDRip HDTV');
      expect(result, 'Friends');
    });
  });

  group('Enhanced Title Validation Tests', () {
    test('should reject titles starting with S##E##', () {
      expect(SeriesParser.isValidSeriesTitle('S01E01 Pilot'), false);
      expect(SeriesParser.isValidSeriesTitle('S01 - E01 - Winter Is Coming'), false);
      expect(SeriesParser.isValidSeriesTitle('S1E1'), false);
    });

    test('should reject titles starting with Season/Episode', () {
      expect(SeriesParser.isValidSeriesTitle('Season 1 Episode 1'), false);
      expect(SeriesParser.isValidSeriesTitle('Episode 1 The Beginning'), false);
    });

    test('should reject titles with mostly quality tags', () {
      expect(SeriesParser.isValidSeriesTitle('1080p BluRay x264'), false);
      expect(SeriesParser.isValidSeriesTitle('720p HDTV'), false);
    });

    test('should accept valid series titles', () {
      expect(SeriesParser.isValidSeriesTitle('Game of Thrones'), true);
      expect(SeriesParser.isValidSeriesTitle('The Office'), true);
      expect(SeriesParser.isValidSeriesTitle('Breaking Bad'), true);
      expect(SeriesParser.isValidSeriesTitle('The Office US'), true);
    });
  });

  group('Common Prefix Extraction Tests', () {
    test('should extract common title when all files have same series name', () {
      final filenames = [
        'Game of Thrones S01E01.mkv',
        'Game of Thrones S01E02.mkv',
        'Game of Thrones S01E03.mkv',
      ];
      final title = SeriesParser.extractCommonSeriesTitle(filenames);
      expect(title, 'game of thrones');
    });

    test('should return null when files start with S##E##', () {
      final filenames = [
        'S01 - E01 - Winter Is Coming.mkv',
        'S01 - E02 - The Kingsroad.mkv',
        'S01 - E03 - Lord Snow.mkv',
      ];
      final title = SeriesParser.extractCommonSeriesTitle(filenames);
      expect(title, null);
    });

    test('should extract common prefix from slightly different titles', () {
      final filenames = [
        'Game.of.Thrones.S01E01.720p.mkv',
        'Game.of.Thrones.S01E02.1080p.mkv',
        'Game.of.Thrones.S01E03.BluRay.mkv',
      ];
      final title = SeriesParser.extractCommonSeriesTitle(filenames);
      expect(title, 'game of thrones');
    });

    test('should return null for bracket notation files', () {
      final filenames = [
        '[7.22] Goodbye, Michael.avi',
        '[7.23] The Inner Circle.avi',
      ];
      final title = SeriesParser.extractCommonSeriesTitle(filenames);
      expect(title, null);
    });
  });

  group('Title Extraction Bug Fix Tests', () {
    test('should return null title for S## - E## format files', () {
      final info = SeriesParser.parseFilename('S01 - E01 - Winter Is Coming.mkv');
      expect(info.season, 1);
      expect(info.episode, 1);
      expect(info.title, null); // Should be null, not episode name
    });

    test('should return null title for Season X Episode Y format', () {
      final info = SeriesParser.parseFilename('Season 1 Episode 1 Pilot.mkv');
      expect(info.season, 1);
      expect(info.episode, 1);
      expect(info.title, null);
    });
  });
} 