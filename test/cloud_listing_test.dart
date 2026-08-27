import 'package:debrify/core/cloud/listing.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stands in for any provider's file model — the point of CloudListing is that
/// it never names one.
class _Entry {
  final String name;
  final int size;
  final bool folder;
  final bool video;
  const _Entry(this.name, {this.size = 0, this.folder = false, this.video = false});
  @override
  String toString() => name;
}

const listing = CloudListing<_Entry>(
  isFolder: _isFolder,
  isVideo: _isVideo,
  sizeOf: _sizeOf,
  nameOf: _nameOf,
);

bool _isFolder(_Entry e) => e.folder;
bool _isVideo(_Entry e) => e.video;
int _sizeOf(_Entry e) => e.size;
String _nameOf(_Entry e) => e.name;

const mb = 1024 * 1024;

void main() {
  group('filter', () {
    final items = [
      const _Entry('Season 1', folder: true),
      const _Entry('episode.mkv', video: true, size: 700 * mb),
      const _Entry('sample.mkv', video: true, size: 12 * mb),
      const _Entry('readme.txt', size: 2000),
    ];

    test('no filters returns the list untouched', () {
      expect(listing.filter(items), same(items));
    });

    test('videosOnly keeps videos and drops other files', () {
      final kept = listing.filter(items, videosOnly: true).map(_nameOf);

      expect(kept, ['Season 1', 'episode.mkv', 'sample.mkv']);
    });

    test('a size floor drops small videos only', () {
      final kept = listing
          .filter(items, minVideoBytes: 100 * mb)
          .map(_nameOf);

      expect(kept, ['Season 1', 'episode.mkv', 'readme.txt']);
    });

    test('folders survive both filters — hiding one strands its contents', () {
      final kept = listing
          .filter(items, videosOnly: true, minVideoBytes: 100 * mb)
          .map(_nameOf);

      expect(kept, ['Season 1', 'episode.mkv']);
    });

    test('a zero-size video is not dropped when no floor is set', () {
      final kept = listing.filter(
        [const _Entry('live.ts', video: true)],
        videosOnly: true,
      );

      expect(kept, hasLength(1));
    });
  });

  group('sorted', () {
    test('folders come before files', () {
      final out = listing.sorted([
        const _Entry('b.mkv', video: true),
        const _Entry('a-folder', folder: true),
      ]).map(_nameOf);

      expect(out, ['a-folder', 'b.mkv']);
    });

    test('numbers read as numbers, so 2 precedes 10', () {
      final out = listing.sorted([
        const _Entry('Season 10', folder: true),
        const _Entry('Season 2', folder: true),
        const _Entry('Season 1', folder: true),
      ]).map(_nameOf);

      expect(out, ['Season 1', 'Season 2', 'Season 10']);
    });

    test('numbered entries lead unnumbered ones', () {
      final out = listing.sorted([
        const _Entry('Appendix', folder: true),
        const _Entry('1. Intro', folder: true),
      ]).map(_nameOf);

      expect(out, ['1. Intro', 'Appendix']);
    });

    test('files sort on a leading number, not one buried in the title', () {
      final out = listing.sorted([
        const _Entry('10. Finale 1080p.mkv'),
        const _Entry('2. Pilot 2019.mkv'),
      ]).map(_nameOf);

      expect(out, ['2. Pilot 2019.mkv', '10. Finale 1080p.mkv']);
    });

    test('same number falls back to alphabetical', () {
      final out = listing.sorted([
        const _Entry('Season 1 Extras', folder: true),
        const _Entry('Season 1 Anthology', folder: true),
      ]).map(_nameOf);

      expect(out, ['Season 1 Anthology', 'Season 1 Extras']);
    });
  });

  group('partition', () {
    test('splits folders, videos and everything else', () {
      final parts = listing.partition([
        const _Entry('Season 1', folder: true),
        const _Entry('ep.mkv', video: true),
        const _Entry('notes.txt'),
      ]);

      expect(parts.folders.map(_nameOf), ['Season 1']);
      expect(parts.videos.map(_nameOf), ['ep.mkv']);
      expect(parts.others.map(_nameOf), ['notes.txt']);
    });
  });

  group('search', () {
    final items = [
      const _Entry('The Wire S01E01.mkv'),
      const _Entry('Notes.txt'),
    ];

    test('matches case-insensitively on a substring', () {
      expect(listing.search(items, 'wire').map(_nameOf), ['The Wire S01E01.mkv']);
      expect(listing.search(items, 'NOTES').map(_nameOf), ['Notes.txt']);
    });

    test('a blank query is not a filter', () {
      expect(listing.search(items, '   '), same(items));
    });
  });

  group('number extraction', () {
    test('reads the season out of the shapes these browsers actually see', () {
      expect(seasonNumberIn('Season 3'), 3);
      expect(seasonNumberIn('season_12'), 12);
      expect(seasonNumberIn('Chapter-4'), 4);
      expect(seasonNumberIn('Part 2'), 2);
      expect(seasonNumberIn('Module-3'), 3);
      expect(seasonNumberIn('1. Pilot'), 1);
    });

    test('a specific keyword wins over the generic word-then-number rule', () {
      expect(seasonNumberIn('show season 7'), 7);
    });

    test('null when there is no number to find', () {
      expect(seasonNumberIn('Extras'), isNull);
      expect(seasonNumberIn(''), isNull);
    });

    test('leading numbers only — a year in the title cannot hijack the order', () {
      expect(leadingNumberIn('10. Finale.mkv'), 10);
      expect(leadingNumberIn('05_Episode.mp4'), 5);
      expect(leadingNumberIn('Blade Runner 2049.mkv'), isNull);
    });
  });
}
