import 'package:debrify/models/torrent.dart';
import 'package:debrify/models/torrent_filter_state.dart';
import 'package:debrify/utils/filter_ladder.dart';
import 'package:debrify/utils/torrent_filter_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

// Brazilian add-ons (Brazuca and other Torrentio forks) label dubbed audio in
// Portuguese — DUBLADO, NACIONAL, "Dual Áudio", a 🇧🇷 flag — and subtitled
// releases LEGENDADO. A Portuguese filter used to keep only the subtitled
// rows, because "PT-BR" next to LEGENDADO was the one token it knew.

var _index = 0;

Torrent _stream(String name, {String? label, String? description}) => Torrent(
  rowid: 0,
  infohash: (_index++).toRadixString(16).padLeft(40, '0'),
  name: name,
  sizeBytes: 0,
  createdUnix: 0,
  seeders: 0,
  leechers: 0,
  completed: 0,
  scrapedDate: 0,
  streamType: StreamType.directUrl,
  streamLabel: label,
  streamDescription: description,
);

final _portuguese = TorrentFilterState(languages: {AudioLanguage.portuguese});
final _english = TorrentFilterState(languages: {AudioLanguage.english});

void main() {
  group('Portuguese browse filter', () {
    test('keeps dubbed releases named in Portuguese', () {
      final dubbed = [
        _stream('Filme.2024.1080p.WEB-DL.DUBLADO.mkv'),
        _stream('Filme 2024 720p Nacional.mkv'),
        _stream('Filme (2024) 1080p Dual Áudio 5.1.mkv'),
        _stream('Filme.2024.1080p.Português.mkv'),
      ];
      expect(TorrentFilterMatcher.apply(dubbed, _portuguese), dubbed);
    });

    test('drops a subtitled release even though it says PT-BR', () {
      final subtitled = _stream('Filme.2024.1080p.LEGENDADO.PT-BR.mkv');
      expect(TorrentFilterMatcher.apply([subtitled], _portuguese), isEmpty);
    });

    test('a subtitled release that also carries a Portuguese track stays', () {
      final both = _stream('Filme.2024.1080p.DUAL.Legendado.PT-BR.mkv');
      expect(TorrentFilterMatcher.apply([both], _portuguese), [both]);
    });

    test('reads the add-on description when the file name is bare', () {
      final dubbed = _stream(
        'Filme.2024.1080p.mkv',
        label: 'Brazuca\n1080p',
        description:
            'Filme 2024 1080p WEB-DL DUAL\n👤 12 💾 2.1 GB ⚙️ Comando\n🇧🇷',
      );
      final subtitled = _stream(
        'Filme.2024.1080p.mkv',
        label: 'Brazuca\n1080p',
        description:
            'Filme 2024 1080p WEB-DL LEGENDADO\n👤 4 💾 2.0 GB ⚙️ Comando\n🇧🇷',
      );
      expect(TorrentFilterMatcher.apply([subtitled, dubbed], _portuguese), [
        dubbed,
      ]);
    });

    test('"Pt" in a title is not Portuguese', () {
      final part = _stream('Dune.Pt.2.2024.1080p.WEB-DL.mkv');
      expect(TorrentFilterMatcher.apply([part], _portuguese), isEmpty);
    });
  });

  group('other languages keep working with the description read', () {
    test(
      'a multi-audio release that names English passes an English filter',
      () {
        final multi = _stream(
          'Movie.2024.1080p.ENG.mkv',
          description: 'Movie 2024 1080p\nMulti Audio / 🇮🇹',
        );
        expect(TorrentFilterMatcher.apply([multi], _english), [multi]);
      },
    );

    test('a multi-audio release that does not name English is hidden', () {
      final multi = _stream(
        'Film.2024.1080p.ITA.mkv',
        description: 'Multi Audio / 🇮🇹 / 🇫🇷',
      );
      expect(TorrentFilterMatcher.apply([multi], _english), isEmpty);
    });
  });

  group('Quick Play ladder with a Portuguese filter', () {
    test('ranks dubbed above subtitled whatever the add-on order', () {
      final subtitled = _stream(
        'Filme.2024.1080p.mkv',
        description: 'Filme 2024 1080p LEGENDADO PT-BR\n🇧🇷',
      );
      final english = _stream('Movie.2024.1080p.WEB-DL.mkv');
      final dubbed = _stream(
        'Filme.2024.1080p.mkv',
        description: 'Filme 2024 1080p DUBLADO\n🇧🇷',
      );
      final ladder = FilterLadder(_portuguese);
      expect(ladder.order([subtitled, english, dubbed]).first, dubbed);
      expect(ladder.tierOf(dubbed), 0);
      expect(ladder.tierOf(subtitled), greaterThan(0));
    });
  });
}
