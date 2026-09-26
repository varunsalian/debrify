import 'package:flutter/material.dart';
import '../../../models/torrent_filter_state.dart';
import '../../../theme/app_theme_scope.dart';

/// Ordered filter labels and clear affordance; filtering stays in application state.
class SourceActiveFilters extends StatelessWidget {
  const SourceActiveFilters({
    super.key,
    required this.filters,
    required this.accent,
    required this.dim,
    required this.onClear,
  });

  final TorrentFilterState filters;
  final Color accent;
  final Color dim;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final labels = <String>[
      for (final q in filters.qualities) 'Quality · ${_qualityFilterLabel(q)}',
      for (final r in filters.ripSources) 'Source · ${_ripFilterLabel(r)}',
      for (final l in filters.languages) 'Lang · ${_langFilterLabel(l)}',
      for (final s in filters.sizes) 'Size · ${_sizeFilterLabel(s)}',
      for (final d in filters.dynamicRanges) 'Range · ${_rangeFilterLabel(d)}',
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Wrap(
        spacing: 7,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final l in labels)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: app.fade(app.core.tx, 0.06),
                border: Border.all(color: app.fade(app.core.tx, 0.08)),
                borderRadius: app.shape.brPill,
              ),
              child: Text(
                l,
                style: TextStyle(
                  color: dim,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          InkWell(
            onTap: onClear,
            child: Text(
              'Clear',
              style: TextStyle(
                color: accent,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _qualityFilterLabel(QualityTier q) => switch (q) {
    QualityTier.ultraHd => '4K',
    QualityTier.fullHd => '1080p',
    QualityTier.hd => '720p',
    QualityTier.sd => '480p',
  };

  static String _ripFilterLabel(RipSourceCategory r) => switch (r) {
    RipSourceCategory.web => 'WEB',
    RipSourceCategory.bluRay => 'BluRay',
    RipSourceCategory.hdrip => 'HDRip',
    RipSourceCategory.dvdrip => 'DVDRip',
    RipSourceCategory.cam => 'CAM',
    RipSourceCategory.other => 'Other',
  };

  static String _langFilterLabel(AudioLanguage l) =>
      l.name[0].toUpperCase() + l.name.substring(1);

  static String _sizeFilterLabel(SizeBucket s) => switch (s) {
    SizeBucket.under500mb => '< 500 MB',
    SizeBucket.mb500to1gb => '500 MB – 1 GB',
    SizeBucket.gb1to1p5 => '1 – 1.5 GB',
    SizeBucket.gb1p5to2p5 => '1.5 – 2.5 GB',
    SizeBucket.gb2p5to4 => '2.5 – 4 GB',
    SizeBucket.gb4to6 => '4 – 6 GB',
    SizeBucket.gb6to10 => '6 – 10 GB',
    SizeBucket.gb10to20 => '10 – 20 GB',
    SizeBucket.gb20to40 => '20 – 40 GB',
    SizeBucket.over40gb => '> 40 GB',
  };

  static String _rangeFilterLabel(DynamicRange d) => switch (d) {
    DynamicRange.sdr => 'SDR',
    DynamicRange.hdr => 'HDR',
  };
}
