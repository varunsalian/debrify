import '../../../models/torrent.dart';
import '../application/keyword_providers.dart';

/// Prefer a provider's display name from the fullest available result set.
String keywordSourceLabel(List<Torrent> full, String source) {
  for (final torrent in full) {
    if (keywordSourceOf(torrent) != source) continue;
    final label = torrent.addonDisplayName?.trim();
    if (label != null && label.isNotEmpty) return label;
  }
  final value = source.startsWith('stremio:') ? source.substring(8) : source;
  return value.isEmpty ? source : value[0].toUpperCase() + value.substring(1);
}
