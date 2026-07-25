import '../models/torrent_filter_state.dart';
import '../services/storage_service.dart';
import '../widgets/torrent_result_row.dart' show qualityTierForName;

/// Debrify TV's playback filters, split by the level each one can actually be
/// evaluated at:
///
/// * **Quality** is a release-NAME signal, so it's applied at the torrent
///   level — when a channel's cache is read for playback, and on each
///   quick-play queue rebuild. Cheap, and it narrows the pool before any
///   debrid call is made.
/// * **Size** is only meaningful per FILE. A season pack's torrent size is the
///   whole pack, so filtering it at the torrent level would be comparing
///   against a number the user never meant. Applied after the provider returns
///   its file list, per-file sizes ARE per-episode sizes — which is why this
///   needs no series-vs-movie detection at all, and why it doubles as the
///   trailer/sample guard.
///
/// Both facets are plain narrowing (not the Search tab's tiered ranking), so
/// callers can shuffle results freely afterwards — membership is what matters,
/// not order. Empty facets match everything, keeping Debrify TV byte-identical
/// for users who never set a filter.
class DebrifyTvFilters {
  final Set<QualityTier> qualities;
  final Set<SizeBucket> sizes;

  const DebrifyTvFilters({
    this.qualities = const <QualityTier>{},
    this.sizes = const <SizeBucket>{},
  });

  const DebrifyTvFilters.empty()
      : qualities = const <QualityTier>{},
        sizes = const <SizeBucket>{};

  bool get hasQuality => qualities.isNotEmpty;
  bool get hasSize => sizes.isNotEmpty;
  bool get isActive => hasQuality || hasSize;

  /// Reads the Debrify TV-scoped filters (Debrify TV → Settings), NOT the
  /// Search tab's default filters.
  static Future<DebrifyTvFilters> load() async {
    final results = await Future.wait([
      StorageService.getDebrifyTvFilterQualities(),
      StorageService.getDebrifyTvFilterSizes(),
    ]);
    return DebrifyTvFilters(
      qualities: <QualityTier>{
        for (final q in results[0])
          ...QualityTier.values.where((e) => e.name == q),
      },
      sizes: <SizeBucket>{
        for (final s in results[1])
          ...SizeBucket.values.where((e) => e.name == s),
      },
    );
  }

  /// Whether a torrent's release name carries an accepted quality. Uses the
  /// same classifier as the search result badges, so a filter can never reject
  /// something the UI labels as that quality.
  bool qualityMatchesName(String name) {
    if (qualities.isEmpty) return true;
    return qualities.contains(qualityTierForName(name));
  }

  /// Whether a real file byte count falls in an accepted bucket. Unknown or
  /// zero sizes (providers that don't report one) are ACCEPTED rather than
  /// hidden — Debrify TV would otherwise silently drop a whole provider's
  /// files, and an unplayable channel is worse than a slightly-off size.
  bool sizeMatchesBytes(int bytes) {
    if (sizes.isEmpty) return true;
    if (bytes <= 0) return true;
    final bucket = sizeBucketForBytes(bytes);
    return bucket != null && sizes.contains(bucket);
  }

  /// Short summary for snackbars ("1080p · 2.5–4GB"), empty when inactive.
  String summary() {
    final parts = <String>[
      ...qualities.map(qualityLabel),
      ...sizes.map(sizeLabel),
    ];
    return parts.join(' · ');
  }

  static String qualityLabel(QualityTier q) => switch (q) {
        QualityTier.ultraHd => '4K',
        QualityTier.fullHd => '1080p',
        QualityTier.hd => '720p',
        QualityTier.sd => 'SD',
      };

  static String sizeLabel(SizeBucket s) => switch (s) {
        SizeBucket.under500mb => '<500MB',
        SizeBucket.mb500to1gb => '500MB–1GB',
        SizeBucket.gb1to1p5 => '1–1.5GB',
        SizeBucket.gb1p5to2p5 => '1.5–2.5GB',
        SizeBucket.gb2p5to4 => '2.5–4GB',
        SizeBucket.gb4to6 => '4–6GB',
        SizeBucket.gb6to10 => '6–10GB',
        SizeBucket.gb10to20 => '10–20GB',
        SizeBucket.gb20to40 => '20–40GB',
        SizeBucket.over40gb => '>40GB',
      };
}
