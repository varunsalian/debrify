import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/models/torrent.dart';

void main() {
  group('Season Filtering Logic', () {
    // Helper function to create a torrent with specific coverage type
    Torrent createTorrent({
      required String name,
      required String? coverageType,
      int? seasonNumber,
      int? startSeason,
      int? endSeason,
    }) {
      return Torrent(
        rowid: 1,
        infohash: 'hash',
        name: name,
        sizeBytes: 1000000,
        createdUnix: 1234567890,
        seeders: 100,
        leechers: 10,
        completed: 50,
        scrapedDate: 1234567890,
        coverageType: coverageType,
        seasonNumber: seasonNumber,
        startSeason: startSeason,
        endSeason: endSeason,
      );
    }

    // Function to simulate the filtering logic
    bool shouldIncludeTorrent(Torrent torrent, int requestedSeason) {
      switch (torrent.coverageType) {
        case 'completeSeries':
          // Always include complete series (they include all seasons)
          return true;

        case 'multiSeasonPack':
          // Include if the requested season is within the range
          if (torrent.startSeason != null && torrent.endSeason != null) {
            return torrent.startSeason! <= requestedSeason &&
                   torrent.endSeason! >= requestedSeason;
          }
          // If season range data is missing, exclude to be safe
          return false;

        case 'seasonPack':
          // Include only if it matches the requested season exactly
          return torrent.seasonNumber == requestedSeason;

        case 'singleEpisode':
          // For single episodes, check if they belong to the requested season
          final name = torrent.name.toUpperCase();

          // Check various season formats: S04, Season 4, etc.
          final seasonPadded = requestedSeason.toString().padLeft(2, '0');
          final seasonPatterns = [
            'S$seasonPadded',  // S04
            'S$requestedSeason', // S4
            'SEASON $requestedSeason', // Season 4
            'SEASON$requestedSeason',  // Season4
            '${requestedSeason}X', // 4x (for 4x01 format)
          ];

          // Check if any pattern matches
          for (final pattern in seasonPatterns) {
            if (name.contains(pattern)) {
              return true;
            }
          }

          // If we can't determine the season, exclude the single episode
          return false;

        default:
          // Unknown coverage type - keep it to avoid over-filtering
          return true;
      }
    }

    test('Complete series should always be included', () {
      final torrent = createTorrent(
        name: 'Stranger Things Complete Series',
        coverageType: 'completeSeries',
      );

      expect(shouldIncludeTorrent(torrent, 4), isTrue);
      expect(shouldIncludeTorrent(torrent, 1), isTrue);
      expect(shouldIncludeTorrent(torrent, 5), isTrue);
    });

    test('Season pack should only match requested season', () {
      final season1 = createTorrent(
        name: 'Stranger Things Season 1',
        coverageType: 'seasonPack',
        seasonNumber: 1,
      );

      final season4 = createTorrent(
        name: 'Stranger Things Season 4',
        coverageType: 'seasonPack',
        seasonNumber: 4,
      );

      // When searching for Season 4
      expect(shouldIncludeTorrent(season1, 4), isFalse);
      expect(shouldIncludeTorrent(season4, 4), isTrue);

      // When searching for Season 1
      expect(shouldIncludeTorrent(season1, 1), isTrue);
      expect(shouldIncludeTorrent(season4, 1), isFalse);
    });

    test('Multi-season pack should include if requested season is in range', () {
      final seasons1to3 = createTorrent(
        name: 'Stranger Things Seasons 1-3',
        coverageType: 'multiSeasonPack',
        startSeason: 1,
        endSeason: 3,
      );

      final seasons3to5 = createTorrent(
        name: 'Stranger Things Seasons 3-5',
        coverageType: 'multiSeasonPack',
        startSeason: 3,
        endSeason: 5,
      );

      // When searching for Season 4
      expect(shouldIncludeTorrent(seasons1to3, 4), isFalse); // 1-3 doesn't include 4
      expect(shouldIncludeTorrent(seasons3to5, 4), isTrue);  // 3-5 includes 4

      // When searching for Season 3
      expect(shouldIncludeTorrent(seasons1to3, 3), isTrue);  // 1-3 includes 3
      expect(shouldIncludeTorrent(seasons3to5, 3), isTrue);  // 3-5 includes 3

      // When searching for Season 1
      expect(shouldIncludeTorrent(seasons1to3, 1), isTrue);  // 1-3 includes 1
      expect(shouldIncludeTorrent(seasons3to5, 1), isFalse); // 3-5 doesn't include 1
    });

    test('Multi-season pack with missing data should be excluded', () {
      final missingStart = createTorrent(
        name: 'Stranger Things Multi Season',
        coverageType: 'multiSeasonPack',
        startSeason: null,
        endSeason: 5,
      );

      final missingEnd = createTorrent(
        name: 'Stranger Things Multi Season',
        coverageType: 'multiSeasonPack',
        startSeason: 1,
        endSeason: null,
      );

      expect(shouldIncludeTorrent(missingStart, 4), isFalse);
      expect(shouldIncludeTorrent(missingEnd, 4), isFalse);
    });

    test('Single episodes should match their season', () {
      final s04e01_format1 = createTorrent(
        name: 'Stranger Things S04E01',
        coverageType: 'singleEpisode',
      );

      final s04e01_format2 = createTorrent(
        name: 'Stranger Things S4E01',
        coverageType: 'singleEpisode',
      );

      final s04e01_format3 = createTorrent(
        name: 'Stranger Things 4x01',
        coverageType: 'singleEpisode',
      );

      final s04e01_format4 = createTorrent(
        name: 'Stranger Things Season 4 Episode 1',
        coverageType: 'singleEpisode',
      );

      final s01e01 = createTorrent(
        name: 'Stranger Things S01E01',
        coverageType: 'singleEpisode',
      );

      // When searching for Season 4
      expect(shouldIncludeTorrent(s04e01_format1, 4), isTrue);
      expect(shouldIncludeTorrent(s04e01_format2, 4), isTrue);
      expect(shouldIncludeTorrent(s04e01_format3, 4), isTrue);
      expect(shouldIncludeTorrent(s04e01_format4, 4), isTrue);
      expect(shouldIncludeTorrent(s01e01, 4), isFalse);

      // When searching for Season 1
      expect(shouldIncludeTorrent(s01e01, 1), isTrue);
      expect(shouldIncludeTorrent(s04e01_format1, 1), isFalse);
    });

    test('Unknown coverage type should be kept', () {
      final unknown = createTorrent(
        name: 'Stranger Things Unknown',
        coverageType: null,
      );

      final weirdType = createTorrent(
        name: 'Stranger Things Weird',
        coverageType: 'someWeirdType',
      );

      expect(shouldIncludeTorrent(unknown, 4), isTrue);
      expect(shouldIncludeTorrent(weirdType, 4), isTrue);
    });
  });
}