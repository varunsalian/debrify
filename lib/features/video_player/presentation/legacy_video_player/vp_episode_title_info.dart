import 'dart:async';

import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/models/playlist_entry.dart';
import 'package:debrify/models/series_playlist.dart';

abstract interface class VpEpisodeTitleInfoHost {
  List<PlaylistEntry>? get activePlaylist;
  int get currentIndex;
  int get currentIptvIndex;
  String get dynamicTitle;
  int? get effectiveContentEpisode;
  int? get effectiveContentSeason;
  String? get effectiveContentTitle;
  List<IptvChannel>? get effectiveIptvChannels;
  List<Map<String, dynamic>>? get effectiveStremioTvChannels;
  bool get hasStremioTvGuide;
  SeriesPlaylist? get seriesPlaylist;
  Future<Map<String, String>?> Function()? get requestMagicNext;
  String get title;
  String? get subtitle;
}

class VpEpisodeTitleInfo {
  VpEpisodeTitleInfo(this._host);
  final VpEpisodeTitleInfoHost _host;

  /// Get the current episode title for display
  String getCurrentEpisodeTitle() => getCurrentEpisodeTitleInfo().title;

  /// The dock title plus whether it's a fetched, human name (TVMaze episode
  /// title, catalog content title, channel name) as opposed to a release
  /// filename. TvControls skips its release-noise cleaner for fetched names —
  /// the token list would truncate a real title containing e.g. "Proper".
  ({String title, bool fetched}) getCurrentEpisodeTitleInfo() {
    final seriesPlaylist = _host.seriesPlaylist;
    if (seriesPlaylist != null &&
        seriesPlaylist.isSeries &&
        _host.activePlaylist != null) {
      // Find the current episode info
      if (_host.currentIndex >= 0 &&
          _host.currentIndex < _host.activePlaylist!.length) {
        try {
          final currentEpisode = seriesPlaylist.allEpisodes.firstWhere(
            (episode) => episode.originalIndex == _host.currentIndex,
            orElse: () => seriesPlaylist.allEpisodes.first,
          );

          // Return episode title if available, otherwise use the playlist entry title
          if (currentEpisode.episodeInfo?.title != null &&
              currentEpisode.episodeInfo!.title!.isNotEmpty) {
            final episodeTitle = currentEpisode.episodeInfo!.title!;
            // "Show — Episode" when TVMaze supplied the official show name;
            // the subtitle then drops the name to avoid saying it twice.
            final show = seriesPlaylist.tvmazeShowName;
            return (
              title: show == null || show.isEmpty
                  ? episodeTitle
                  : '$show — $episodeTitle',
              fetched: true,
            );
          } else if (currentEpisode.seriesInfo.season != null &&
              currentEpisode.seriesInfo.episode != null) {
            // Catalog singleton without TVMaze data yet: the clean catalog
            // title beats a bare "Episode N".
            final contentTitle = _host.effectiveContentTitle;
            if (_host.activePlaylist!.length == 1 &&
                contentTitle != null &&
                contentTitle.isNotEmpty &&
                _host.effectiveStremioTvChannels == null) {
              return (title: contentTitle, fetched: true);
            }
            final episodeTitle = 'Episode ${currentEpisode.seriesInfo.episode}';
            final show = seriesPlaylist.tvmazeShowName;
            return (
              title: show == null || show.isEmpty
                  ? episodeTitle
                  : '$show — $episodeTitle',
              fetched: true,
            );
          }
        } catch (e) {
          // Silently fail
        }
      }
    }

    // Stremio TV: use dynamic title when a channel switch has occurred
    if (_host.hasStremioTvGuide && _host.dynamicTitle.isNotEmpty) {
      return (title: _host.dynamicTitle, fetched: true);
    }

    // Catalog single stream (Quick Play / Sources tap): prefer the clean
    // content title over the release filename. Packs are handled by the
    // series branch above; Debrify TV, IPTV and Stremio TV keep their
    // dynamic titles.
    final contentTitle = _host.effectiveContentTitle;
    if (contentTitle != null &&
        contentTitle.isNotEmpty &&
        _host.requestMagicNext == null &&
        _host.effectiveIptvChannels == null &&
        _host.effectiveStremioTvChannels == null &&
        (_host.activePlaylist == null || _host.activePlaylist!.length <= 1)) {
      return (title: contentTitle, fetched: true);
    }

    // Fallback to the current playlist entry title
    if (_host.activePlaylist != null &&
        _host.currentIndex >= 0 &&
        _host.currentIndex < _host.activePlaylist!.length) {
      return (
        title: _host.activePlaylist![_host.currentIndex].title,
        fetched: false,
      );
    }

    // If Debrify TV (no playlist) is active, use dynamic title when available
    // (a Debrify TV title can be a torrent name — keep the cleaner on it).
    if ((_host.activePlaylist == null || _host.activePlaylist!.isEmpty) &&
        _host.requestMagicNext != null) {
      return _host.dynamicTitle.isNotEmpty
          ? (title: _host.dynamicTitle, fetched: false)
          : (title: _host.title, fetched: false);
    }

    // IPTV: use current channel name
    final iptvChannels = _host.effectiveIptvChannels;
    if (iptvChannels != null &&
        _host.currentIptvIndex >= 0 &&
        _host.currentIptvIndex < iptvChannels.length) {
      return (
        title: iptvChannels[_host.currentIptvIndex].numberedName,
        fetched: true,
      );
    }

    // Final fallback
    return (title: _host.title, fetched: false);
  }

  /// Get the current episode subtitle for display
  String? getCurrentEpisodeSubtitle() {
    final seriesPlaylist = _host.seriesPlaylist;
    if (seriesPlaylist != null &&
        seriesPlaylist.isSeries &&
        _host.activePlaylist != null) {
      // Find the current episode info
      if (_host.currentIndex >= 0 &&
          _host.currentIndex < _host.activePlaylist!.length) {
        try {
          final currentEpisode = seriesPlaylist.allEpisodes.firstWhere(
            (episode) => episode.originalIndex == _host.currentIndex,
            orElse: () => seriesPlaylist.allEpisodes.first,
          );

          // Return series name and season/episode info as subtitle
          if (currentEpisode.seriesInfo.season != null &&
              currentEpisode.seriesInfo.episode != null) {
            // Catalog singleton: the filename-parsed series name can be a
            // mangled release string; the clean catalog title is authoritative.
            // While TVMaze hasn't supplied an episode title yet, the title line
            // is already showing the catalog name — don't repeat it here.
            final contentTitle = _host.effectiveContentTitle;
            final isCatalogSingleton =
                _host.activePlaylist!.length == 1 &&
                contentTitle != null &&
                contentTitle.isNotEmpty &&
                _host.effectiveStremioTvChannels == null;
            final seasonEpisode =
                'Season ${currentEpisode.seriesInfo.season}, Episode ${currentEpisode.seriesInfo.episode}';
            // When TVMaze supplied the show name, the TITLE line already
            // reads "Show — Episode", so repeating the name here would say
            // it twice. Without it, fall back to the filename-parsed series
            // name — release strings only as a last resort, same rule as the
            // native player's OTT identity row.
            final showName = seriesPlaylist.tvmazeShowName;
            if (showName != null && showName.isNotEmpty) {
              return seasonEpisode;
            }
            if (isCatalogSingleton) {
              final hasEpisodeTitle =
                  currentEpisode.episodeInfo?.title?.isNotEmpty == true;
              return hasEpisodeTitle
                  ? '$contentTitle • $seasonEpisode'
                  : seasonEpisode;
            }
            return '${seriesPlaylist.seriesTitle} • $seasonEpisode';
          }
        } catch (e) {}
      }
    }

    // IPTV: use current channel group as subtitle
    final iptvChannels = _host.effectiveIptvChannels;
    if (iptvChannels != null &&
        _host.currentIptvIndex >= 0 &&
        _host.currentIptvIndex < iptvChannels.length) {
      return iptvChannels[_host.currentIptvIndex].group ?? 'IPTV';
    }

    // Catalog single stream: when the title shows the clean content name,
    // surface the episode identity (and the release detail line) here.
    final contentTitle = _host.effectiveContentTitle;
    if (contentTitle != null &&
        contentTitle.isNotEmpty &&
        _host.requestMagicNext == null &&
        _host.effectiveStremioTvChannels == null &&
        (_host.activePlaylist == null || _host.activePlaylist!.length <= 1)) {
      final season = _host.effectiveContentSeason;
      final episode = _host.effectiveContentEpisode;
      final parts = <String>[
        if (season != null && episode != null)
          'Season $season, Episode $episode',
        if (_host.subtitle != null && _host.subtitle!.trim().isNotEmpty)
          _host.subtitle!,
      ];
      if (parts.isNotEmpty) return parts.join(' • ');
    }

    // Fallback to the current subtitle or widget subtitle
    return _host.subtitle;
  }

  /// Get enhanced metadata for OTT-style display
  Map<String, dynamic> getEnhancedMetadata() {
    final seriesPlaylist = _host.seriesPlaylist;

    if (seriesPlaylist != null &&
        seriesPlaylist.isSeries &&
        _host.activePlaylist != null) {
      // Find the current episode info
      if (_host.currentIndex >= 0 &&
          _host.currentIndex < _host.activePlaylist!.length) {
        try {
          final currentEpisode = seriesPlaylist.allEpisodes.firstWhere(
            (episode) => episode.originalIndex == _host.currentIndex,
            orElse: () => seriesPlaylist.allEpisodes.first,
          );

          if (currentEpisode.episodeInfo != null) {
            final episodeInfo = currentEpisode.episodeInfo!;

            final metadata = {
              'rating': episodeInfo.rating,
              'runtime': episodeInfo.runtime,
              'year': episodeInfo.year,
              'airDate': episodeInfo.airDate,
              'language': episodeInfo.language,
              'genres': episodeInfo.genres,
              'network': episodeInfo.network,
              'country': episodeInfo.country,
              'plot': episodeInfo.plot,
            };

            return metadata;
          }
        } catch (e) {}
      }
    }

    return {};
  }
}
