import 'package:debrify/features/video_player/application/vp_format.dart';
import 'package:debrify/models/playlist_entry.dart';
import 'package:debrify/models/playlist_view_mode.dart';
import 'package:debrify/models/series_playlist.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/video_player/widgets/playlist_sheet.dart';
import 'package:debrify/utils/episode_playback_request.dart';
import 'package:debrify/utils/series_parser.dart';
import 'package:flutter/material.dart';

abstract interface class VpEpisodeGuideHost {
  List<PlaylistEntry>? get activePlaylist;
  bool get canFetchEpisodes;
  int get currentIndex;
  String? get currentSeriesImdbId;
  Future<void>? get episodeMetadataReady;
  set episodeMetadataReady(Future<void>? v);
  bool get seriesImdbKnownAtLaunch;
  SeriesPlaylist? get seriesPlaylist;
  SeriesPlaylist? get syntheticGuidePlaylist;
  set syntheticGuidePlaylist(SeriesPlaylist? v);
  void setManualSelectionMode({bool allowResume = false});
  ({int? season, int? episode}) traktSeasonEpisode();
  Future<void> preloadEpisodeInfo();
  Map<String, dynamic>? constructPlaylistItemData();
  Future<bool> loadPlaylistIndex(
    int index, {
    bool autoplay = false,
    EpisodePlaybackRequest? request,
    bool skipInitialSave = false,
    bool preferLocalResume = false,
    bool suppressResume = false,
    Torrent? manualValidationSource,
    int? manualValidationSourceIndex,
  });
  Future<EpisodePlaybackOutcome> fetchAndPlayEpisode(
    int season,
    int episode, {
    int? shuffleGeneration,
    bool autoAdvance = false,
    EpisodePlaybackRequest? request,
  });
  String get title;
  String get videoUrl;
  String? get contentTitle;
  PlaylistViewMode? get viewMode;
}

class VpEpisodeGuide {
  VpEpisodeGuide(this._host);
  final VpEpisodeGuideHost _host;

  List<PlaylistEntry>? syntheticGuideEntries;

  (SeriesPlaylist, List<PlaylistEntry>)? buildSyntheticGuide() {
    final existingSp = _host.syntheticGuidePlaylist;
    final existingEntries = syntheticGuideEntries;
    if (existingSp != null && existingEntries != null) {
      return (existingSp, existingEntries);
    }
    final se = _host.traktSeasonEpisode();
    if (se.season == null || se.episode == null) return null;
    var title = _host.title;
    final info = SeriesParser.parseFilename(title);
    if (info.season == null || info.episode == null) {
      // Stamp the playing episode's identity so the guide groups it right.
      title = 'S${vpPad2(se.season!)}E${vpPad2(se.episode!)} $title';
    }
    final entries = [PlaylistEntry(url: _host.videoUrl, title: title)];
    final sp = SeriesPlaylist.fromPlaylistEntries(
      entries,
      collectionTitle: _host.contentTitle ?? _host.title,
      forceSeries: true,
    );
    sp.imdbId = _host.currentSeriesImdbId;
    _host.syntheticGuidePlaylist = sp;
    syntheticGuideEntries = entries;
    return (sp, entries);
  }

  Future<void> showPlaylistSheet(BuildContext context) async {
    var playlist = _host.activePlaylist ?? const <PlaylistEntry>[];
    var seriesPlaylist = _host.seriesPlaylist;
    var currentIndex = _host.currentIndex;
    final canFetch = _host.canFetchEpisodes;
    if (playlist.isEmpty && canFetch) {
      // Single stream without a playlist: back the guide with a synthetic
      // 1-entry playlist so the full episode list can render.
      final synthetic = buildSyntheticGuide();
      if (synthetic == null) return;
      seriesPlaylist = synthetic.$1;
      playlist = synthetic.$2;
      currentIndex = 0;
    }
    if (seriesPlaylist != null && seriesPlaylist.isSeries) {
      _host.episodeMetadataReady ??= _host.preloadEpisodeInfo();
    }
    await PlaylistSheet.show(
      context,
      playlist: playlist,
      currentIndex: currentIndex,
      seriesPlaylist: seriesPlaylist,
      playlistItemData: _host.constructPlaylistItemData(),
      imdbId: seriesPlaylist?.imdbId ?? _host.currentSeriesImdbId,
      imdbKnownAtLaunch: _host.seriesImdbKnownAtLaunch,
      metadataReady: _host.episodeMetadataReady,
      viewMode: _host.viewMode,
      onSelect: (index, {bool allowResume = false}) async {
        // Synthetic guide: its only playlist row IS the playing stream.
        if (_host.activePlaylist == null || _host.activePlaylist!.isEmpty)
          return;
        _host.setManualSelectionMode(allowResume: allowResume);
        await _host.loadPlaylistIndex(index, autoplay: true);
      },
      onFetchEpisode: canFetch ? _host.fetchAndPlayEpisode : null,
    );
  }
}
