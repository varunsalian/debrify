import '../../models/torrent.dart';
import '../../utils/format_tag_detector.dart';

/// `size · ↑seeders · ↓leechers · SOURCE` meta line for a redesigned row.
String sourceRowSubtitle(Torrent t, {DateTime? now}) {
  final parts = <String>[];
  final sourceLabel = t.addonDisplayName ?? t.source;
  if (t.isDirectStream || t.isExternalStream) {
    if (t.sizeBytes > 0) parts.add(sourceSizeLabel(t.sizeBytes));
    if (sourceLabel.isNotEmpty) parts.add(sourceLabel.toUpperCase());
    return parts.join(' · ');
  }
  if (t.sizeBytes > 0) parts.add(sourceSizeLabel(t.sizeBytes));
  if (t.seeders > 0) parts.add('↑ ${t.seeders}');
  if (t.leechers > 0) parts.add('↓ ${t.leechers}');
  if (sourceLabel.isNotEmpty) parts.add(sourceLabel.toUpperCase());
  final date = sourceDateLabel(t.createdUnix, now: now);
  if (date != null) parts.add(date);
  return parts.join(' · ');
}

/// Relative upload date ("2d ago"), matching the classic row. Null when the
/// torrent carries no date.
String? sourceDateLabel(int createdUnix, {DateTime? now}) {
  if (createdUnix <= 0) return null;
  final then = DateTime.fromMillisecondsSinceEpoch(createdUnix * 1000);
  final d = (now ?? DateTime.now()).difference(then);
  if (d.inDays >= 365) return '${(d.inDays / 365).floor()}y ago';
  if (d.inDays >= 30) return '${(d.inDays / 30).floor()}mo ago';
  if (d.inDays >= 7) return '${(d.inDays / 7).floor()}w ago';
  if (d.inDays >= 1) return '${d.inDays}d ago';
  if (d.inHours >= 1) return '${d.inHours}h ago';
  return 'Today';
}

String? sourceQualityLabel(Torrent t) {
  // Use the same resolution logic as the F badges (pixel tokens win over the
  // loose UHD/4K keyword) so the compact/keyword quality pill stays consistent
  // with them — the `qualityTier` extension mislabels "UHD BluRay 1080p".
  final tags = FormatTagDetector.detect(t.name);
  if (tags.contains(FormatTag.uhd4k)) return '4K';
  if (tags.contains(FormatTag.fullHd)) return '1080p';
  if (tags.contains(FormatTag.hd720)) return '720p';
  return null; // SD / unknown — no pill
}

String? sourceCoverageLabel(Torrent t) {
  switch (t.coverageType) {
    case 'completeSeries':
      return 'Complete Series';
    case 'multiSeasonPack':
      return 'Multi-Season';
    case 'seasonPack':
      return t.seasonNumber != null
          ? 'Season ${t.seasonNumber}'
          : 'Season Pack';
    case 'singleEpisode':
      return t.episodeIdentifier;
    default:
      return null;
  }
}

String sourceSizeLabel(int bytes) {
  if (bytes <= 0) return '';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var size = bytes.toDouble();
  var u = 0;
  while (size >= 1024 && u < units.length - 1) {
    size /= 1024;
    u++;
  }
  return '${size.toStringAsFixed(size >= 100 || u == 0 ? 0 : 1)} ${units[u]}';
}
