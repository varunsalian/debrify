import '../../models/iptv_playlist.dart';
import '../../models/playlist_entry.dart';
import '../../models/series_playlist.dart';

/// The fourteen host reads behind the player's episode display projection
/// (dock title, subtitle and OTT metadata), captured by the host State as one
/// immutable snapshot at the call site.
///
/// Field order is the order the origin functions first read them.
/// [seriesPlaylist] comes from a lazy host getter with a cache side effect,
/// so the host evaluates it while building this object — at the call, exactly
/// where the origin evaluated it first. Nothing here is derived; every value
/// is the host read, unchanged.
class EpisodeDisplayInputs {
  const EpisodeDisplayInputs({
    required this.seriesPlaylist,
    required this.activePlaylist,
    required this.currentIndex,
    required this.effectiveContentTitle,
    required this.effectiveStremioTvChannels,
    required this.hasStremioTvGuide,
    required this.dynamicTitle,
    required this.hasMagicNext,
    required this.effectiveIptvChannels,
    required this.title,
    required this.currentIptvIndex,
    required this.effectiveContentSeason,
    required this.effectiveContentEpisode,
    required this.subtitle,
  });

  /// Host `_seriesPlaylist` (lazy, cached parse of [activePlaylist]).
  final SeriesPlaylist? seriesPlaylist;

  /// Host `_activePlaylist`.
  final List<PlaylistEntry>? activePlaylist;

  /// Host `_currentIndex`.
  final int currentIndex;

  /// Host `_effectiveContentTitle` (Stremio TV override or launch
  /// `contentTitle`).
  final String? effectiveContentTitle;

  /// Host `_effectiveStremioTvChannels`.
  final List<Map<String, dynamic>>? effectiveStremioTvChannels;

  /// Host `_hasStremioTvGuide`.
  final bool hasStremioTvGuide;

  /// Host `_dynamicTitle`.
  final String dynamicTitle;

  /// Host `widget.requestMagicNext != null` (Debrify TV provider present).
  final bool hasMagicNext;

  /// Host `_effectiveIptvChannels`.
  final List<IptvChannel>? effectiveIptvChannels;

  /// Host `widget.title`.
  final String title;

  /// Host `_currentIptvIndex`.
  final int currentIptvIndex;

  /// Host `_effectiveContentSeason`.
  final int? effectiveContentSeason;

  /// Host `_effectiveContentEpisode`.
  final int? effectiveContentEpisode;

  /// Host `widget.subtitle`.
  final String? subtitle;
}
