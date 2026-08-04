import 'package:flutter/material.dart';

import '../utils/format_tag_detector.dart';

/// Renders a single release [FormatTag] as a small, consistent "chip" for the
/// redesigned Sources page (Concept F) — 4K, HDR, Dolby Vision, HEVC, DTS-HD,
/// BluRay, and so on.
///
/// Every tag uses ONE chip shape (same height, padding, radius, vertical
/// centering) so a row of them lines up cleanly — only the label text and a
/// subtle brand tint change. This is deliberately uniform: mixed bordered
/// boxes / tall glyphs / bare text read as ragged. Rendered as widgets, not
/// images (the marks are stylized text; the trademarked artwork isn't
/// reproduced), which also matches the mock and renders crisply on TV.
class FormatBadge extends StatelessWidget {
  const FormatBadge(this.tag, {super.key, this.scale = 1.0});

  final FormatTag tag;

  /// Multiplies every dimension — bump to ~1.15 on TV for 10-foot legibility.
  final double scale;

  // Brand-appropriate accents. Quality signals (4K/HDR) gold, codec green,
  // BluRay blue, "premium" marks bright white, everything else muted white —
  // colour lives in the TEXT, the chip shape stays identical.
  static const _gold = Color(0xFFE9C877);
  static const _green = Color(0xFF4ADE80);
  static const _blue = Color(0xFF6FB4F0);
  static const _white = Color(0xFFF1F1F6);
  static final _muted = const Color(0xFFF1F1F6).withValues(alpha: 0.70);

  @override
  Widget build(BuildContext context) {
    final (label, fg) = _spec();
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 7 * scale, vertical: 3 * scale),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(5 * scale),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 10.5 * scale,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          height: 1.1,
        ),
      ),
    );
  }

  (String, Color) _spec() => switch (tag) {
    // source
    FormatTag.remux => ('REMUX', _muted),
    FormatTag.bluRay => ('BluRay', _blue),
    FormatTag.web => ('WEB-DL', _muted),
    FormatTag.hdRip => ('HDRip', _muted),
    FormatTag.dvdRip => ('DVDRip', _muted),
    FormatTag.cam => ('CAM', _muted),
    // resolution — only 4K gets the premium gold; the rest stay quiet
    FormatTag.uhd4k => ('4K', _gold),
    FormatTag.fullHd => ('1080p', _muted),
    FormatTag.hd720 => ('720p', _muted),
    FormatTag.sd => ('SD', _muted),
    // HDR family — gold
    FormatTag.dolbyVision => ('Dolby Vision', _gold),
    FormatTag.hdr10Plus => ('HDR10+', _gold),
    FormatTag.hdr10 => ('HDR10', _gold),
    FormatTag.hlg => ('HLG', _gold),
    FormatTag.hdr => ('HDR', _gold),
    // spec
    FormatTag.imax => ('IMAX', _white),
    // codec — green
    FormatTag.hevc => ('HEVC', _green),
    FormatTag.avc => ('AVC', _muted),
    FormatTag.av1 => ('AV1', _muted),
    // audio
    FormatTag.atmos => ('Atmos', _white),
    FormatTag.trueHd => ('TrueHD', _muted),
    FormatTag.dtsHdMa => ('DTS-HD MA', _white),
    FormatTag.dtsHd => ('DTS-HD', _white),
    FormatTag.dts => ('DTS', _white),
    FormatTag.ddPlus => ('DD+', _white),
    FormatTag.dd => ('DD', _muted),
    FormatTag.aac => ('AAC', _muted),
  };
}

/// A wrap of [FormatBadge]s for a source row — [FormatTagDetector.detect]'s
/// output laid out with consistent spacing. Empty tags → zero-size.
class FormatBadgeRow extends StatelessWidget {
  const FormatBadgeRow(this.tags, {super.key, this.scale = 1.0, this.spacing = 7, this.runSpacing = 6});

  final List<FormatTag> tags;
  final double scale;
  final double spacing;
  final double runSpacing;

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: spacing,
      runSpacing: runSpacing,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [for (final t in tags) FormatBadge(t, scale: scale)],
    );
  }
}
