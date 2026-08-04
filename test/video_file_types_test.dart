import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/utils/file_utils.dart';

/// [FileUtils.isVideoFile] is the single gate every cloud browser asks before
/// offering Play instead of download-only, so a container missing from it is
/// not "unsupported" — it is invisible. These pin the set.
void main() {
  group('isVideoFile', () {
    test('recognises the MPEG program-stream family', () {
      // Both players read this container: libmpv decodes it in software on
      // phone/desktop, and the TV player's PsExtractor + bundled ffmpeg audio
      // decoders cover it there.
      for (final name in const [
        'Movie.mpg',
        'Movie.mpeg',
        'Movie.m2p',
        'VTS_01_1.VOB',
      ]) {
        expect(FileUtils.isVideoFile(name), isTrue, reason: name);
      }
    });

    test('still recognises the formats it always did', () {
      for (final name in const [
        'a.mp4',
        'a.mkv',
        'a.avi',
        'a.mov',
        'a.wmv',
        'a.flv',
        'a.webm',
        'a.m4v',
        'a.3gp',
        'a.ts',
        'a.mts',
        'a.m2ts',
      ]) {
        expect(FileUtils.isVideoFile(name), isTrue, reason: name);
      }
    });

    test('is case-insensitive and path-tolerant', () {
      expect(FileUtils.isVideoFile('Season 1/Episode 1.MPG'), isTrue);
      expect(FileUtils.isVideoFile('SHOW.MPEG'), isTrue);
    });

    test('does not swallow non-video files', () {
      for (final name in const [
        'subs.srt',
        'notes.txt',
        'archive.rar',
        'cover.jpg',
        'audio.mp3',
        'nfo',
        'trailer.mpg.txt',
      ]) {
        expect(FileUtils.isVideoFile(name), isFalse, reason: name);
      }
    });
  });
}
