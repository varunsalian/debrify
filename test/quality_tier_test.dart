import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/models/torrent_filter_state.dart';
import 'package:debrify/utils/torrent_filter_matcher.dart';
import 'package:debrify/widgets/torrent_result_row.dart';

void main() {
  Torrent named(String name) => Torrent(
    rowid: 1,
    infohash: 'h',
    name: name,
    sizeBytes: 1,
    createdUnix: 0,
    seeders: 1,
    leechers: 0,
    completed: 0,
    scrapedDate: 0,
  );

  group('TorrentQualityExtension.qualityTier — pixel tokens win', () {
    test('"UHD BluRay 1080p" is 1080p, not 4K', () {
      expect(named('Poltergeist 1982 UHD BluRay 1080p DD5.1').qualityTier,
          QualityTier.fullHd);
    });

    test('"RM4k WB 1080p" is 1080p, not 4K', () {
      expect(named('Poltergeist 1982 RM4k WB 1080p BluRay x264').qualityTier,
          QualityTier.fullHd);
    });

    test('explicit 2160p is 4K', () {
      expect(named('Movie.2160p.UHD.BluRay.x265').qualityTier,
          QualityTier.ultraHd);
    });

    test('bare UHD/4K keyword (no pixel token) falls back to 4K', () {
      expect(named('Movie.UHD.WEB-DL.HEVC').qualityTier, QualityTier.ultraHd);
      expect(named('Movie.4K.WEB-DL').qualityTier, QualityTier.ultraHd);
    });

    test('720p and SD still classify', () {
      expect(named('Show.720p.HDTV.x264').qualityTier, QualityTier.hd);
      expect(named('Show.480p.DVDRip').qualityTier, QualityTier.sd);
    });

    test('the quality filter now agrees with the badge for UHD-1080p', () {
      final t = named('Poltergeist 1982 UHD BluRay 1080p');
      // Filtering to 1080p keeps it; filtering to 4K drops it.
      final only1080 = TorrentFilterState(qualities: {QualityTier.fullHd});
      final only4k = TorrentFilterState(qualities: {QualityTier.ultraHd});
      expect(TorrentFilterMatcher.apply([t], only1080), [t]);
      expect(TorrentFilterMatcher.apply([t], only4k), isEmpty);
    });
  });
}
