import 'package:debrify/models/torrent.dart';
import 'package:debrify/models/torrent_filter_state.dart';
import 'package:debrify/utils/stremio_tv_audio_policy.dart';
import 'package:flutter_test/flutter_test.dart';

Torrent source(
  String name, {
  List<String>? audioLanguages,
  String? streamDescription,
}) {
  return Torrent(
    rowid: 0,
    infohash: name.hashCode.toUnsigned(32).toRadixString(16),
    name: name,
    sizeBytes: 2 * 1024 * 1024 * 1024,
    createdUnix: 0,
    seeders: 10,
    leechers: 0,
    completed: 0,
    scrapedDate: 0,
    audioLanguages: audioLanguages,
    streamDescription: streamDescription,
  );
}

void main() {
  group('StremioTvAudioPolicy blocking', () {
    test('blocks a Russian-only release when Russian is blocked', () {
      final item = source('Show.S01E01.1080p.RUS.WEB-DL');

      expect(
        StremioTvAudioPolicy.shouldBlock(
          item,
          {AudioLanguage.russian},
        ),
        isTrue,
      );
    });

    test('does not hardcode Russian', () {
      final item = source('Movie.1080p.SPANISH.WEB-DL');

      expect(
        StremioTvAudioPolicy.shouldBlock(
          item,
          {AudioLanguage.spanish},
        ),
        isTrue,
      );
    });

    test('keeps ENG + RUS when only Russian is blocked', () {
      final item = source('Show.S01E01.ENG.RUS.1080p');

      expect(
        StremioTvAudioPolicy.shouldBlock(
          item,
          {AudioLanguage.russian},
        ),
        isFalse,
      );
    });

    test('blocks ENG + RUS when both are blocked', () {
      final item = source('Show.S01E01.ENG.RUS.1080p');

      expect(
        StremioTvAudioPolicy.shouldBlock(
          item,
          {
            AudioLanguage.english,
            AudioLanguage.russian,
          },
        ),
        isTrue,
      );
    });

    test('keeps unknown-language releases', () {
      final item = source('Show.S01E01.1080p.WEB-DL');

      expect(
        StremioTvAudioPolicy.shouldBlock(
          item,
          {AudioLanguage.russian},
        ),
        isFalse,
      );
    });

    test('keeps ambiguous Multi-Audio release', () {
      final item = source('Show.S01E01.RUS.Multi-Audio.1080p');

      expect(
        StremioTvAudioPolicy.shouldBlock(
          item,
          {AudioLanguage.russian},
        ),
        isFalse,
      );
    });

    test('uses authoritative track metadata', () {
      final item = source(
        'Show.S01E01.1080p.WEB-DL',
        audioLanguages: ['ru'],
      );

      expect(
        StremioTvAudioPolicy.shouldBlock(
          item,
          {AudioLanguage.russian},
        ),
        isTrue,
      );
    });

    test('keeps mixed authoritative track metadata', () {
      final item = source(
        'Show.S01E01.1080p.WEB-DL',
        audioLanguages: ['ru', 'en'],
      );

      expect(
        StremioTvAudioPolicy.shouldBlock(
          item,
          {AudioLanguage.russian},
        ),
        isFalse,
      );
    });
  });

  group('StremioTvAudioPolicy preference', () {
    test('preferred Spanish outranks English', () {
      final spanish = source('Movie.1080p.LATINO.WEB-DL');
      final english = source('Movie.2160p.ENG.WEB-DL');

      expect(
        StremioTvAudioPolicy.preferenceRank(
          spanish,
          AudioLanguage.spanish,
        ),
        lessThan(
          StremioTvAudioPolicy.preferenceRank(
            english,
            AudioLanguage.spanish,
          ),
        ),
      );
    });

    test('multi-audio is a safer fallback than explicit wrong language', () {
      final multi = source('Movie.1080p.MULTI-AUDIO');
      final russian = source('Movie.1080p.RUS');

      expect(
        StremioTvAudioPolicy.preferenceRank(
          multi,
          AudioLanguage.english,
        ),
        lessThan(
          StremioTvAudioPolicy.preferenceRank(
            russian,
            AudioLanguage.english,
          ),
        ),
      );
    });
  });
}
