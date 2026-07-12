import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/utils/format_tag_detector.dart';

void main() {
  group('FormatTagDetector.detect', () {
    test('empty / unremarkable names yield no tags', () {
      expect(FormatTagDetector.detect(''), isEmpty);
      expect(FormatTagDetector.detect('Some Random Release Name'), isEmpty);
    });

    test('rich 4K REMUX release keeps display order', () {
      final tags = FormatTagDetector.detect(
        'The.Wire.S01E01.2160p.REMUX.IMAX.HDR.DV.HEVC.DTS-HD.MA-NTb',
      );
      expect(tags, [
        FormatTag.remux, // source
        FormatTag.uhd4k, // resolution
        FormatTag.dolbyVision, // DV additive
        FormatTag.hdr, // brightness
        FormatTag.imax, // spec
        FormatTag.hevc, // codec
        FormatTag.dtsHdMa, // audio (most specific)
      ]);
    });

    test('picks a single source, resolution, codec and audio', () {
      final tags = FormatTagDetector.detect(
        'Movie.2019.1080p.BluRay.x264.DD5.1-GROUP',
      );
      expect(tags, [FormatTag.bluRay, FormatTag.fullHd, FormatTag.avc, FormatTag.dd]);
    });

    test('4K/UHD normalize to the 4K tag; WEB-DL is a source', () {
      expect(FormatTagDetector.detect('Film.4K.WEB-DL.HDR10.x265'), [
        FormatTag.web,
        FormatTag.uhd4k,
        FormatTag.hdr10,
        FormatTag.hevc,
      ]);
    });

    test('HDR10+ wins over HDR10/HDR; Atmos wins over DD+', () {
      final tags = FormatTagDetector.detect('S01.2160p.WEB.HDR10Plus.DDP.Atmos.HEVC');
      expect(tags, contains(FormatTag.hdr10Plus));
      expect(tags, isNot(contains(FormatTag.hdr10)));
      expect(tags, isNot(contains(FormatTag.hdr)));
      expect(tags, contains(FormatTag.atmos));
      expect(tags, isNot(contains(FormatTag.ddPlus)));
    });

    test('DTS-HD MA does not also emit plain DTS or DTS-HD', () {
      final tags = FormatTagDetector.detect('X.1080p.BluRay.DTS-HD.MA.5.1.x264');
      expect(tags, contains(FormatTag.dtsHdMa));
      expect(tags, isNot(contains(FormatTag.dts)));
      expect(tags, isNot(contains(FormatTag.dtsHd)));
    });

    test('only the release line is parsed, not an appended filename', () {
      final tags = FormatTagDetector.detect(
        'Show.S01E01.720p.WEB.x264-GRP\nsome.other.2160p.file.mkv',
      );
      expect(tags, [FormatTag.web, FormatTag.hd720, FormatTag.avc]);
    });

    test('"UHD BluRay 1080p" is 1080p, not 4K (UHD names the source)', () {
      final tags = FormatTagDetector.detect(
        'Poltergeist 1982 REPACK UHD BluRay 1080p Dolby Vision HEVC',
      );
      expect(tags, contains(FormatTag.fullHd));
      expect(tags, isNot(contains(FormatTag.uhd4k)));
    });

    test('explicit 2160p is still 4K; bare 4K/UHD keyword falls back to 4K', () {
      expect(
        FormatTagDetector.detect('Movie.2160p.UHD.BluRay.x265'),
        contains(FormatTag.uhd4k),
      );
      expect(
        FormatTagDetector.detect('Movie.UHD.WEB-DL.HEVC'), // no pixel token
        contains(FormatTag.uhd4k),
      );
    });

    test('space-separated addon titles classify like dot-separated names', () {
      // Stremio/addon stream titles use spaces, not dots.
      expect(
        FormatTagDetector.detect('The Batman 2022 2160p WEB-DL Dolby Vision DTS-HD MA HEVC'),
        [
          FormatTag.web,
          FormatTag.uhd4k,
          FormatTag.dolbyVision,
          FormatTag.hevc,
          FormatTag.dtsHdMa,
        ],
      );
    });

    test('DTS-HD MA with a space is not downgraded to plain DTS-HD', () {
      final spaced = FormatTagDetector.detect('X 1080p BluRay DTS-HD MA 5.1 x264');
      expect(spaced, contains(FormatTag.dtsHdMa));
      expect(spaced, isNot(contains(FormatTag.dtsHd)));
    });

    test('"Dolby Digital Plus" spaced resolves to ddPlus, not dd', () {
      final tags = FormatTagDetector.detect('Show S01 1080p WEB DDP5.1 x265');
      expect(tags, contains(FormatTag.ddPlus));
      expect(tags, isNot(contains(FormatTag.dd)));
    });

    test('DV is not falsely matched inside DVDRip', () {
      final tags = FormatTagDetector.detect('Old.Movie.1999.DVDRip.XviD-GRP');
      expect(tags, contains(FormatTag.dvdRip));
      expect(tags, isNot(contains(FormatTag.dolbyVision)));
    });

    test('label and asset metadata resolve', () {
      expect(FormatTag.uhd4k.label, '4K Ultra HD');
      expect(FormatTag.dolbyVision.svgAsset, 'assets/format/dolbyVision.svg');
    });
  });
}
