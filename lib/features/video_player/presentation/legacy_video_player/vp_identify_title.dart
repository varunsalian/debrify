import 'package:debrify/features/video_player/application/vp_identity_text.dart';
import 'package:debrify/features/video_player/models/vp_season_episode_selection.dart';
import 'package:debrify/models/playlist_entry.dart';
import 'package:debrify/models/series_playlist.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/models/stremio_subtitle.dart';
import 'package:debrify/screens/video_player/widgets/tracks_sheet.dart';
import 'package:debrify/services/stremio_subtitle_service.dart';
import 'package:debrify/utils/movie_parser.dart';
import 'package:debrify/utils/series_parser.dart';
import 'package:flutter/material.dart';

abstract interface class VpIdentifyTitleHost {
  void setState(VoidCallback fn);
  BuildContext get context;
  bool get mounted;
  List<PlaylistEntry>? get activePlaylist;
  int get addonSubtitleFetchToken;
  set addonSubtitleFetchToken(int v);
  set cachedAddonSlots(List<AddonSubtitleSlot>? v);
  set cachedStremioSubtitles(List<StremioSubtitle>? v);
  set cachedSubtitleKey(String? v);
  int get currentIndex;
  int? get currentStremioTvContentEpisode;
  int? get currentStremioTvContentSeason;
  String? get currentStremioTvContentTitle;
  String get dynamicTitle;
  set embeddedSubtitleApplied(bool v);
  SeriesEpisode? findSeriesEpisodeForCurrentIndex(
    SeriesPlaylist seriesPlaylist,
  );
  int? get manualContentEpisode;
  set manualContentEpisode(int? v);
  set manualContentImdbId(String? v);
  int? get manualContentSeason;
  set manualContentSeason(int? v);
  set manualContentType(String? v);
  String? get manualSubtitleDisplayLabel;
  set manualSubtitleDisplayLabel(String? v);
  Future<VpSeasonEpisodeSelection?> requestSeasonEpisodeForIdentity(
    String title,
  );
  String? get selectedStremioSubtitleId;
  set selectedStremioSubtitleId(String? v);
  SeriesPlaylist? get seriesPlaylist;
  Future<StremioMeta?> showIdentifyTitleSearchSheet({
    required String initialQuery,
  });
  set userManuallySelectedSubtitle(bool v);
  String get title;
  String? get contentTitle;
  int? get contentSeason;
  int? get contentEpisode;
  Future<void> fetchAndMaybeAutoSelectAddonSubtitle();
}

class VpIdentifyTitle {
  VpIdentifyTitle(this._host);
  final VpIdentifyTitleHost _host;

  String currentPlaybackTitleForIdentity() {
    if (_host.activePlaylist != null &&
        _host.currentIndex >= 0 &&
        _host.currentIndex < _host.activePlaylist!.length) {
      return _host.activePlaylist![_host.currentIndex].title;
    }
    if (_host.dynamicTitle.isNotEmpty) return _host.dynamicTitle;
    final stremioTitle = _host.currentStremioTvContentTitle;
    if (stremioTitle != null && stremioTitle.trim().isNotEmpty) {
      return stremioTitle;
    }
    final contentTitle = _host.contentTitle;
    if (contentTitle != null && contentTitle.trim().isNotEmpty) {
      return contentTitle;
    }
    return _host.title;
  }

  String identitySearchInitialQuery() {
    final rawTitle = currentPlaybackTitleForIdentity();
    final seriesInfo = SeriesParser.parseFilename(rawTitle);
    final seriesTitle = seriesInfo.title?.trim();
    if (seriesInfo.isSeries && seriesTitle != null && seriesTitle.isNotEmpty) {
      return seriesTitle;
    }

    final movieInfo = MovieParser.parseFilename(rawTitle);
    final movieTitle = movieInfo.title?.trim();
    if (movieTitle != null && movieTitle.isNotEmpty) {
      return movieTitle;
    }

    return rawTitle
        .replaceAll(
          RegExp(
            r'\.(mkv|mp4|avi|mov|wmv|flv|webm|m4v|ts|mpg|mpeg)$',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(RegExp(r'[._]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String? subtitleIdentityLabelForSheet() {
    final manualLabel = _host.manualSubtitleDisplayLabel?.trim();
    if (manualLabel != null && manualLabel.isNotEmpty) {
      return 'Subtitles for $manualLabel';
    }

    final detectedTitle = identitySearchInitialQuery();
    if (detectedTitle.isEmpty) return null;
    return 'Detected: $detectedTitle';
  }

  VpSeasonEpisodeSelection? currentSeasonEpisodeForIdentity() {
    final seriesPlaylist = _host.seriesPlaylist;
    if (seriesPlaylist != null && seriesPlaylist.isSeries) {
      final currentEp = _host.findSeriesEpisodeForCurrentIndex(seriesPlaylist);
      final season = currentEp?.seriesInfo.season;
      final episode = currentEp?.seriesInfo.episode;
      if (season != null && episode != null) {
        return VpSeasonEpisodeSelection(season: season, episode: episode);
      }
    }

    final seriesInfo = SeriesParser.parseFilename(
      currentPlaybackTitleForIdentity(),
    );
    final season =
        seriesInfo.season ??
        _host.manualContentSeason ??
        _host.currentStremioTvContentSeason ??
        _host.contentSeason;
    final episode =
        seriesInfo.episode ??
        _host.manualContentEpisode ??
        _host.currentStremioTvContentEpisode ??
        _host.contentEpisode;

    if (season == null || episode == null) return null;
    return VpSeasonEpisodeSelection(season: season, episode: episode);
  }

  Future<TracksSheetSubtitleSearchResult?>
  identifyTitleAndFetchSubtitles() async {
    final identifyToken = _host.addonSubtitleFetchToken;
    final selected = await _host.showIdentifyTitleSearchSheet(
      initialQuery: identitySearchInitialQuery(),
    );
    if (!_host.mounted ||
        selected == null ||
        identifyToken != _host.addonSubtitleFetchToken) {
      return null;
    }

    final imdbId = selected.effectiveImdbId;
    if (imdbId == null || !imdbId.startsWith('tt')) {
      ScaffoldMessenger.of(_host.context).showSnackBar(
        const SnackBar(content: Text('Selected title has no IMDb ID')),
      );
      return null;
    }

    final contentType = vpNormalisedContentType(selected.type);
    int? season;
    int? episode;

    if (contentType == 'series') {
      final currentEpisode = currentSeasonEpisodeForIdentity();
      season = currentEpisode?.season;
      episode = currentEpisode?.episode;

      if (season == null || episode == null) {
        final entered = await _host.requestSeasonEpisodeForIdentity(
          selected.name,
        );
        if (!_host.mounted ||
            entered == null ||
            identifyToken != _host.addonSubtitleFetchToken) {
          return null;
        }
        season = entered.season;
        episode = entered.episode;
      }
    }

    final subtitleDisplayLabel = vpSubtitleSearchDisplayLabel(
      selected,
      contentType: contentType,
      season: season,
      episode: episode,
    );

    final fetchToken = _host.addonSubtitleFetchToken + 1;
    _host.setState(() {
      _host.addonSubtitleFetchToken = fetchToken;
      _host.manualContentImdbId = imdbId;
      _host.manualContentType = contentType;
      _host.manualContentSeason = contentType == 'series' ? season : null;
      _host.manualContentEpisode = contentType == 'series' ? episode : null;
      _host.manualSubtitleDisplayLabel = subtitleDisplayLabel;
      _host.selectedStremioSubtitleId = null;
      _host.embeddedSubtitleApplied = false;
      _host.userManuallySelectedSubtitle = false;
      _host.cachedStremioSubtitles = null;
      _host.cachedAddonSlots = null;
      _host.cachedSubtitleKey = null;
    });

    try {
      final slots = await StremioSubtitleService.instance.fetchSubtitleSlots(
        type: contentType,
        imdbId: imdbId,
        season: contentType == 'series' ? season : null,
        episode: contentType == 'series' ? episode : null,
      );
      final subtitles = AddonSubtitleSlot.flatten(slots);

      if (!_host.mounted || fetchToken != _host.addonSubtitleFetchToken) {
        return null;
      }

      final cacheKey =
          contentType == 'series' && season != null && episode != null
          ? '$imdbId:$season:$episode'
          : imdbId;

      _host.cachedStremioSubtitles = subtitles;
      _host.cachedAddonSlots = slots;
      _host.cachedSubtitleKey = cacheKey;

      await _host.fetchAndMaybeAutoSelectAddonSubtitle();

      if (subtitles.isEmpty && _host.mounted) {
        ScaffoldMessenger.of(_host.context).showSnackBar(
          const SnackBar(
            content: Text('No online subtitles found for this title'),
          ),
        );
      }

      return TracksSheetSubtitleSearchResult(
        subtitles: subtitles,
        slots: slots,
        selectedSubtitleId: _host.selectedStremioSubtitleId,
        identityLabel: 'Subtitles for $subtitleDisplayLabel',
        imdbId: imdbId,
        contentType: contentType,
        season: contentType == 'series' ? season : null,
        episode: contentType == 'series' ? episode : null,
      );
    } catch (e) {
      debugPrint('VideoPlayer: Search subtitle fetch failed: $e');
      if (_host.mounted) {
        ScaffoldMessenger.of(
          _host.context,
        ).showSnackBar(const SnackBar(content: Text('Subtitle search failed')));
      }
      return null;
    }
  }
}
