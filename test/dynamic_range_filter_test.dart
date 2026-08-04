import 'package:debrify/models/torrent.dart';
import 'package:debrify/models/torrent_filter_state.dart';
import 'package:debrify/utils/filter_ladder.dart';
import 'package:debrify/utils/format_tag_detector.dart';
import 'package:debrify/utils/torrent_filter_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

Torrent _t(String name, {int size = 2 * 1024 * 1024 * 1024}) => Torrent(
      rowid: 0,
      infohash: 'a' * 40,
      name: name,
      sizeBytes: size,
      createdUnix: 0,
      seeders: 10,
      leechers: 0,
      completed: 0,
      scrapedDate: 0,
    );

void main() {
  group('detectDynamicRange', () {
    test('reads every HDR flavour as HDR', () {
      for (final name in const [
        'Movie.2024.2160p.WEB-DL.HDR.x265-GRP',
        'Movie.2024.2160p.WEB-DL.HDR10.x265-GRP',
        'Movie.2024.2160p.WEB-DL.HDR10+.x265-GRP',
        'Movie.2024.2160p.WEB-DL.DV.HDR10.x265-GRP',
        'Movie.2024.2160p.Dolby.Vision.x265-GRP',
        'Movie.2024.2160p.WEB-DL.HLG.x265-GRP',
      ]) {
        expect(
          TorrentFilterMatcher.detectDynamicRange(name),
          DynamicRange.hdr,
          reason: name,
        );
      }
    });

    test('HDRip is not HDR', () {
      // The whole reason detection is delegated to FormatTagDetector: its
      // word-boundary rule stops the very common HDRip token reading as HDR,
      // which would hide most SD/720p releases from an SDR-only filter.
      expect(
        TorrentFilterMatcher.detectDynamicRange('Movie.2024.720p.HDRip.x264'),
        DynamicRange.sdr,
      );
      expect(
        FormatTagDetector.detect('Movie.2024.720p.HDRip.x264'),
        isNot(contains(FormatTag.hdr)),
      );
    });

    test('an untagged release reads as SDR', () {
      expect(
        TorrentFilterMatcher.detectDynamicRange('Movie.2024.1080p.WEB-DL.x264'),
        DynamicRange.sdr,
      );
    });
  });

  group('TorrentFilterMatcher dynamic range', () {
    final sdr = _t('Movie.2024.1080p.WEB-DL.x264-GRP');
    final hdr = _t('Movie.2024.2160p.WEB-DL.HDR10.x265-GRP');
    final dv = _t('Movie.2024.2160p.WEB-DL.DV.x265-GRP');

    test('SDR alone excludes every HDR source — the requested behaviour', () {
      final out = TorrentFilterMatcher.apply(
        [sdr, hdr, dv],
        TorrentFilterState(dynamicRanges: const {DynamicRange.sdr}),
      );
      expect(out, [sdr]);
    });

    test('HDR alone keeps only HDR', () {
      final out = TorrentFilterMatcher.apply(
        [sdr, hdr, dv],
        TorrentFilterState(dynamicRanges: const {DynamicRange.hdr}),
      );
      expect(out, [hdr, dv]);
    });

    test('both selected, or neither, filters nothing', () {
      final both = TorrentFilterMatcher.apply(
        [sdr, hdr, dv],
        TorrentFilterState(
          dynamicRanges: const {DynamicRange.sdr, DynamicRange.hdr},
        ),
      );
      expect(both, [sdr, hdr, dv]);
      expect(
        TorrentFilterMatcher.apply([sdr, hdr, dv],
            const TorrentFilterState.empty()),
        [sdr, hdr, dv],
      );
    });
  });

  group('FilterLadder dynamic range', () {
    test('is honoured longer than every other facet', () {
      // The request: Quick Play must keep excluding HDR even as it relaxes
      // the other filters. So the SDR-only tier must outlive quality/size.
      final ladder = FilterLadder(TorrentFilterState(
        qualities: const {QualityTier.ultraHd},
        sizes: const {SizeBucket.gb4to6},
        dynamicRanges: const {DynamicRange.sdr},
      ));
      final sdrSmall = 'Movie.2024.1080p.WEB-DL.x264';
      final hdrExact = 'Movie.2024.2160p.WEB-DL.HDR10.x265';

      // An HDR release matching quality AND size still ranks BELOW an SDR one
      // that matches neither, because dynamic range relaxes last.
      final sdrTier = ladder.tierOfName(sdrSmall, sizeBytes: 1024);
      final hdrTier = ladder.tierOfName(
        hdrExact,
        sizeBytes: 5 * 1024 * 1024 * 1024,
      );
      expect(sdrTier, lessThan(hdrTier));
    });

    test('still ranks HDR rather than dropping it', () {
      // The floor tier is unrestricted: if every source is HDR, quick play
      // must still have something to play.
      final ladder = FilterLadder(
        TorrentFilterState(dynamicRanges: const {DynamicRange.sdr}),
      );
      final tier = ladder.tierOfName('Movie.2024.2160p.HDR10.x265');
      expect(tier, lessThanOrEqualTo(ladder.tierCount));
      expect(ladder.isActive, isTrue);
    });

    test('adds no tiers for users who never set one', () {
      // Existing ladders must be byte-identical: the size branch was rewritten
      // to relax into a tier rather than jump straight to the floor.
      final withoutRange = FilterLadder(TorrentFilterState(
        qualities: const {QualityTier.fullHd},
        sizes: const {SizeBucket.gb2p5to4},
      ));
      expect(withoutRange.tierCount, 3); // exact, size-only, unrestricted
    });
  });
}
