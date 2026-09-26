import '../models/torrent.dart';
import '../models/torrent_filter_state.dart';
import 'source_quality.dart';

/// Extension to detect quality tier from torrent name
extension TorrentQualityExtension on Torrent {
  QualityTier get qualityTier => qualityTierForName(name);
}

/// Name-based quality classification, shared by the row badge (via
/// [TorrentQualityExtension]) and quick-play's FilterLadder (which ranks by
/// name). One implementation so the badge, the browse filter, and the play
/// ladder can never disagree.
QualityTier qualityTierForName(String name) {
  switch (sourceQualityForName(name)) {
    case SourceQuality.ultraHd:
      return QualityTier.ultraHd;
    case SourceQuality.fullHd:
      return QualityTier.fullHd;
    case SourceQuality.hd:
      return QualityTier.hd;
    case SourceQuality.sd:
      return QualityTier.sd;
    case null:
      final lower = name.toLowerCase();
      if (lower.contains('4096')) return QualityTier.ultraHd;
      if (lower.contains('hd ') || lower.contains('hdrip')) {
        return QualityTier.hd;
      }
      return QualityTier.sd;
  }
}
