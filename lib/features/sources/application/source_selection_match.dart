import '../../../models/series_source.dart';
import '../../../models/torrent.dart';
import '../../../services/pinned_direct_stream_match.dart';

class SourceSelectionMatch {
  SourceSelectionMatch(this.source, [Map<String, Object?>? diagnostics])
    : diagnostics = diagnostics == null ? null : Map.unmodifiable(diagnostics);

  final Torrent? source;

  /// Null preserves the media-server branch's existing omission of match logs.
  final Map<String, Object?>? diagnostics;
}

/// Match only the primary pin, preserving row identity for focus/highlighting.
SourceSelectionMatch matchSelectedSource({
  required List<SeriesSource> saved,
  required List<Torrent> torrents,
  required String? Function(Torrent) mediaServerKeyFor,
  required bool Function(Torrent) isIptvSource,
}) {
  Torrent? selected;
  if (saved.isNotEmpty && saved.first.isMediaServer) {
    for (final candidate in torrents) {
      if (mediaServerKeyFor(candidate) == saved.first.bindingKey) {
        selected = candidate;
        break;
      }
    }
    return SourceSelectionMatch(selected);
  }
  if (saved.isNotEmpty && saved.first.isIptvDirect) {
    final pin = saved.first;
    for (final candidate in torrents) {
      if (isIptvSource(candidate) &&
          candidate.iptvPlaylistId == pin.iptvPlaylistId &&
          candidate.iptvCatalogType == pin.iptvCatalogType &&
          candidate.iptvEntryKey == pin.iptvEntryKey) {
        selected = candidate;
        break;
      }
    }
    return SourceSelectionMatch(selected, {
      'reason': selected == null ? 'iptv_entry_not_found' : 'matched',
    });
  }
  if (saved.isEmpty || !saved.first.isAddonDirect) {
    return SourceSelectionMatch(selected, {
      'reason': saved.isEmpty ? 'no_saved_source' : 'primary_not_direct',
    });
  }
  final pin = saved.first;
  final candidates =
      torrents
          .where((t) => t.isDirectStream && t.stremioAddonKey == pin.addonKey)
          .toList()
        ..sort(
          (a, b) =>
              (a.stremioStreamIndex ?? 0).compareTo(b.stremioStreamIndex ?? 0),
        );
  selected = matchPinnedDirectStream(
    candidates,
    streamKey: pin.streamKey ?? '',
    streamIndex: pin.streamIndex ?? 0,
    bingeGroup: pin.bingeGroup,
  );
  final groupMatches = candidates
      .where((t) => t.stremioBingeGroup == pin.bingeGroup)
      .length;
  final profileMatches = candidates
      .where((t) => t.stremioStreamKey == pin.streamKey)
      .length;
  return SourceSelectionMatch(selected, {
    'direct_results': torrents.where((t) => t.isDirectStream).length,
    'addon_matches': candidates.length,
    'uses_binge_group': pin.bingeGroup?.isNotEmpty == true,
    'group_matches': groupMatches,
    'profile_matches': profileMatches,
    'saved_stream_index': pin.streamIndex,
    'matched_stream_index': selected?.stremioStreamIndex,
    'reason': selected != null
        ? 'matched'
        : candidates.isEmpty
        ? 'addon_configuration_not_found'
        : pin.bingeGroup?.isNotEmpty == true
        ? 'binge_group_not_found'
        : 'stream_identity_not_found',
  });
}
