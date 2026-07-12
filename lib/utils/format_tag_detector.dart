/// Detects the "format badges" shown on a source row in the redesigned Sources
/// page (Concept F) — the recognizable release attributes a torrent/stream name
/// encodes: rip source, resolution, HDR, IMAX, video codec, and audio format.
///
/// Pure name-heuristic parsing, mirroring the token style already used by
/// `TorrentCoverageDetector._extractHdr` / `_extractCodec`. No widget state, so
/// the row widget and any tests stay in sync. Detection is intentionally
/// forgiving — a name that encodes nothing simply yields an empty list.
library;

/// One recognizable release attribute. Grouped by kind; [FormatTagDetector]
/// emits at most a few per row, in a fixed display order (source → resolution →
/// HDR → IMAX → codec → audio) so rows line up visually.
enum FormatTag {
  // Rip source (at most one)
  remux,
  bluRay,
  web,
  hdRip,
  dvdRip,
  cam,
  // Resolution (at most one)
  uhd4k,
  fullHd,
  hd720,
  sd,
  // HDR (Dolby Vision may co-exist with one brightness tag)
  dolbyVision,
  hdr10Plus,
  hdr10,
  hdr,
  // Spec
  imax,
  // Video codec (at most one)
  hevc,
  avc,
  av1,
  // Audio (at most one, most-specific wins)
  atmos,
  trueHd,
  dtsHdMa,
  dtsHd,
  dts,
  ddPlus,
  dd,
  aac,
}

/// Presentation metadata for a [FormatTag] — the short label and the SVG asset
/// the [FormatBadge] widget (Phase 2) renders. Asset files live under
/// `assets/format/`. Kept beside the enum so callers never hard-code strings.
extension FormatTagInfo on FormatTag {
  String get label => switch (this) {
    FormatTag.remux => 'REMUX',
    FormatTag.bluRay => 'BluRay',
    FormatTag.web => 'WEB-DL',
    FormatTag.hdRip => 'HDRip',
    FormatTag.dvdRip => 'DVDRip',
    FormatTag.cam => 'CAM',
    FormatTag.uhd4k => '4K Ultra HD',
    FormatTag.fullHd => '1080p',
    FormatTag.hd720 => '720p',
    FormatTag.sd => 'SD',
    FormatTag.dolbyVision => 'Dolby Vision',
    FormatTag.hdr10Plus => 'HDR10+',
    FormatTag.hdr10 => 'HDR10',
    FormatTag.hdr => 'HDR',
    FormatTag.imax => 'IMAX',
    FormatTag.hevc => 'HEVC',
    FormatTag.avc => 'AVC',
    FormatTag.av1 => 'AV1',
    FormatTag.atmos => 'Dolby Atmos',
    FormatTag.trueHd => 'Dolby TrueHD',
    FormatTag.dtsHdMa => 'DTS-HD MA',
    FormatTag.dtsHd => 'DTS-HD',
    FormatTag.dts => 'DTS',
    FormatTag.ddPlus => 'Dolby Digital Plus',
    FormatTag.dd => 'Dolby Digital',
    FormatTag.aac => 'AAC',
  };

  /// SVG asset path (created in Phase 2). Files are named after the enum.
  String get svgAsset => 'assets/format/$name.svg';
}

/// Extracts the ordered [FormatTag]s a release name encodes.
class FormatTagDetector {
  const FormatTagDetector._();

  /// One match test per pattern: a leading word boundary, then the token, then
  /// a non-letter (so a channel-suffixed token like `DD5.1` or `HDR10` still
  /// matches, while a longer word like `HDRip` does not match `HDR`).
  static bool _has(String text, String pattern) =>
      RegExp(r'\b(?:' + pattern + r')(?![A-Za-z])', caseSensitive: false)
          .hasMatch(text);

  /// Returns the format tags for [name] in display order (source → resolution →
  /// HDR → IMAX → codec → audio). At most one tag per "pick-one" group; Dolby
  /// Vision is additive to a brightness (HDR) tag. Empty when nothing matches.
  static List<FormatTag> detect(String name) {
    if (name.isEmpty) return const [];
    // Only the release line is meaningful; some sources append a filename.
    final text = name.split('\n').first;
    final tags = <FormatTag>[];

    // Source — most specific first, pick one.
    if (_has(text, r'REMUX')) {
      tags.add(FormatTag.remux);
    } else if (_has(text, r'BluRay|Blu-Ray|BDRip|BRRip|BD')) {
      tags.add(FormatTag.bluRay);
    } else if (_has(text, r'WEB[ .-]?DL|WEBRip|WEBHD|WEB')) {
      tags.add(FormatTag.web);
    } else if (_has(text, r'HDRip|HDTV')) {
      tags.add(FormatTag.hdRip);
    } else if (_has(text, r'DVDRip|DVD-?Rip|DVDScr|DVD')) {
      tags.add(FormatTag.dvdRip);
    } else if (_has(text, r'HDCAM|CAMRip|CAM|TELESYNC|TS|TC')) {
      tags.add(FormatTag.cam);
    }

    // Resolution — explicit pixel tokens WIN. "UHD"/"4K" keywords frequently
    // name the SOURCE, not the encode ("UHD BluRay 1080p" is a 1080p file), so
    // they only decide the tag when no pixel resolution is present.
    if (_has(text, r'2160p')) {
      tags.add(FormatTag.uhd4k);
    } else if (_has(text, r'1080p|1080i|FHD')) {
      tags.add(FormatTag.fullHd);
    } else if (_has(text, r'720p|720i')) {
      tags.add(FormatTag.hd720);
    } else if (_has(text, r'480p|360p|576p')) {
      tags.add(FormatTag.sd);
    } else if (_has(text, r'4K|UHD')) {
      tags.add(FormatTag.uhd4k);
    }

    // HDR — Dolby Vision is additive; then one brightness tag, most specific.
    if (_has(text, r'DV|Dolby[ .]?Vision|DoVi')) tags.add(FormatTag.dolbyVision);
    if (_has(text, r'HDR10\+|HDR10Plus')) {
      tags.add(FormatTag.hdr10Plus);
    } else if (_has(text, r'HDR10')) {
      tags.add(FormatTag.hdr10);
    } else if (_has(text, r'HDR')) {
      tags.add(FormatTag.hdr);
    }

    // Spec.
    if (_has(text, r'IMAX')) tags.add(FormatTag.imax);

    // Video codec — pick one.
    if (_has(text, r'x265|HEVC|H\.?265')) {
      tags.add(FormatTag.hevc);
    } else if (_has(text, r'x264|AVC|H\.?264')) {
      tags.add(FormatTag.avc);
    } else if (_has(text, r'AV1')) {
      tags.add(FormatTag.av1);
    }

    // Audio — pick one, most specific wins (checked before its parent).
    if (_has(text, r'Atmos')) {
      tags.add(FormatTag.atmos);
    } else if (_has(text, r'True[ .-]?HD')) {
      tags.add(FormatTag.trueHd);
    } else if (_has(text, r'DTS[ .-]?HD[ .]?MA|DTS[ .-]?HD[ .]?Master')) {
      tags.add(FormatTag.dtsHdMa);
    } else if (_has(text, r'DTS[ .-]?HD')) {
      tags.add(FormatTag.dtsHd);
    } else if (_has(text, r'DTS')) {
      tags.add(FormatTag.dts);
    } else if (_has(text, r'DD\+|DDP|E-?AC-?3|EAC3')) {
      tags.add(FormatTag.ddPlus);
    } else if (_has(text, r'DD|AC-?3|Dolby[ .]?Digital')) {
      tags.add(FormatTag.dd);
    } else if (_has(text, r'AAC')) {
      tags.add(FormatTag.aac);
    }

    return tags;
  }
}
