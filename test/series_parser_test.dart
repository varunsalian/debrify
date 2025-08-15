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
      expect(result.title, 'Stranger Things');
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
  });
} 