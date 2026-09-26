import 'dart:io';

import 'package:debrify/features/sources/data/local_source_file_rules.dart';
import 'package:debrify/features/sources/models/local_source_file.dart';
import 'package:flutter_test/flutter_test.dart';

LocalVideoCandidate candidate(String name, int size) => LocalVideoCandidate(
  file: File('/fixture/$name'),
  fileName: name,
  sizeBytes: size,
  modifiedAt: 1,
);

void main() {
  test('movie matching prefers a valid year then largest matching file', () {
    final newer = candidate('Arrival.2017.mkv', 100);
    final small = candidate('Arrival.2016.mp4', 10);
    final large = candidate('Arrival.2016.mkv', 20);
    final input = [small, newer, large];
    expect(
      matchLocalMovieFiles(input, title: 'Arrival', year: ' 2016 '),
      same(large),
    );
    expect(input, [small, newer, large]);
    expect(
      matchLocalMovieFiles(input, title: 'Arrival', year: '1900'),
      same(newer),
    );
    expect(
      matchLocalMovieFiles(input, title: 'Arrival', year: '2016-01'),
      same(newer),
    );
  });

  test(
    'movie matching ignores stop words and requires every remaining token',
    () {
      final partial = candidate('Lord.of.the.Files.mkv', 100);
      final matching = candidate('Lord.Of.The.Rings.2001.mkv', 10);
      expect(
        matchLocalMovieFiles([
          partial,
          matching,
        ], title: 'The Lord of the Rings'),
        same(matching),
      );
      expect(
        matchLocalMovieFiles([partial], title: 'The Lord of the Rings'),
        isNull,
      );
      expect(
        matchLocalMovieFiles([matching], title: 'the a an of and'),
        isNull,
      );
      expect(matchLocalMovieFiles([], title: 'Movie'), isNull);
    },
  );

  test('movie matching retains its existing substring rule', () {
    final file = candidate('Super.mkv', 10);
    expect(matchLocalMovieFiles([file], title: 'Up'), same(file));
  });

  for (final (folder, title, score) in [
    ('The Office', 'The Office', 130),
    ('Office', 'The Office', 120),
    ('The Office US', 'The Office', 90),
    ('Office US', 'The Office', 80),
    ('My Office Collection', 'The Office', 0),
    ('Breaking Bad', 'Breaking Bad', 140),
    ('Breaking Bad (2008)', 'Breaking Bad', 100),
    ('Bad Breaking Extras', 'Breaking Bad', 19),
    ('Breaking Something', 'Breaking Bad', 0),
    ('Any folder', 'the of a', 0),
  ]) {
    test('series folder matching preserves score for $folder / $title', () {
      expect(localSeriesFolderMatchScore(folder, title), score);
    });
  }

  test('path labels retain separator and trailing slash handling', () {
    expect(localPathName('/shows/Season 1/'), 'Season 1');
    expect(localPathName(r' C:\Shows\Season 1\ '), 'Season 1');
    expect(localPathName('movie.mkv'), 'movie.mkv');
    expect(localPathName('/shows//'), '');
    expect(
      localRelativePath('/shows/', '/shows/Season 1/video.mkv'),
      'Season 1/video.mkv',
    );
    expect(
      localRelativePath(r'C:\Shows', r'C:\Shows\Season 1\video.mkv'),
      'Season 1/video.mkv',
    );
    expect(localRelativePath('/shows', '/shows'), 'shows');
    expect(localRelativePath('/shows', '/shows-other/video.mkv'), 'video.mkv');
  });
}
