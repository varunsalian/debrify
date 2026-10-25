import 'dart:async';
import 'package:debrify/models/series_playlist.dart';
import 'package:debrify/models/stremio_subtitle.dart';
import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/utils/series_parser.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' as mk;

abstract interface class VpPlayerMenuHost {
  void setState(VoidCallback fn);
  bool get mounted;
  int get addonSubtitleFetchToken;
  List<AddonSubtitleSlot>? get cachedAddonSlots;
  String? get cachedSubtitleKey;
  void captureIptvAudioLanguage(String audioId);
  ValueNotifier<bool> get controlsVisible;
  int get currentIndex;
  int? get effectiveContentEpisode;
  String? get effectiveContentImdbId;
  int? get effectiveContentSeason;
  String? get effectiveContentType;
  bool get hasSubtitlePolicy;
  void hideIptvZapBanner({bool immediate = false});
  Timer? get hideTimer;
  List<AddonSubtitleSlot>? get injectedSubtitleSlots;
  int? get manualContentEpisode;
  String? get manualContentImdbId;
  int? get manualContentSeason;
  String? get manualContentType;
  set menuCacheKey(String? v);
  set menuCachedSlots(List<AddonSubtitleSlot>? v);
  set menuContentType(String? v);
  set menuEpisode(int? v);
  set menuImdbId(String? v);
  set menuSeason(int? v);
  mk.Player get player;
  set playerMenuInitialSection(PlayerMenuSection v);
  set selectedStremioSubtitleId(String? v);
  SeriesPlaylist? get seriesPlaylist;
  bool get showPlayerMenu;
  set showPlayerMenu(bool v);
  String? get singleFileImdbId;
  int get subtitleAudioRevision;
  set subtitleAudioRevision(int v);
  void tvReleaseFocusForOverlay();
  FocusNode get tvRootFocus;
  bool get userManuallySelectedSubtitle;
  set userManuallySelectedSubtitle(bool v);
  String currentPlaybackTitleForIdentity();
  void setActiveExternalSubtitlePath(String? path);
  Future<void> persistTrackChoice(String audioId, String subtitleId);
  Future<bool> setSubtitleTrackWithDiagnostics(
    mk.SubtitleTrack track, {
    required String source,
    bool Function()? isCurrent,
  });
  void showSubtitleFailureMessage(String message);
  Future<void> refreshSubtitleAudioPolicy({bool reselect = true});
  Future<String?> downloadStremioSubtitleToTempFile(StremioSubtitle sub);
  Future<bool> applyExternalSubtitleTrack(mk.SubtitleTrack track);
}

class VpPlayerMenu {
  VpPlayerMenu(this._host);
  final VpPlayerMenuHost _host;

  // ── Unified player menu (Spotlight panel) ─────────────────────────────

  /// Opens the menu with the subtitle-identity context already resolved
  /// (the tracks-button path, which may await a metadata fetch first).
  void openPlayerMenuAt(
    PlayerMenuSection section, {
    String? imdbId,
    String? contentType,
    int? season,
    int? episode,
    List<AddonSubtitleSlot>? cachedSlots,
    String? cacheKey,
  }) {
    _host.hideIptvZapBanner();
    _host.hideTimer?.cancel();
    _host.tvReleaseFocusForOverlay();
    _host.setState(() {
      _host.playerMenuInitialSection = section;
      _host.menuImdbId = imdbId;
      _host.menuContentType = contentType;
      _host.menuSeason = season;
      _host.menuEpisode = episode;
      _host.menuCachedSlots = cachedSlots;
      _host.menuCacheKey = cacheKey;
      _host.showPlayerMenu = true;
      _host.controlsVisible.value = false;
    });
  }

  /// Opens the menu from a non-subtitle entry (speed, sleep, aspect,
  /// shuffle) without awaiting anything: identity comes from caches only.
  /// If the IMDb id was never fetched, the Subtitles pane still offers the
  /// "Fix the title" recovery, so nothing is lost — just not pre-fetched.
  void openPlayerMenuQuick(PlayerMenuSection section) {
    final currentTitle = _host.currentPlaybackTitleForIdentity();
    final seriesInfo = SeriesParser.parseFilename(currentTitle);
    final season =
        seriesInfo.season ??
        _host.manualContentSeason ??
        _host.effectiveContentSeason;
    final episode =
        seriesInfo.episode ??
        _host.manualContentEpisode ??
        _host.effectiveContentEpisode;

    String? imdbId;
    final seriesPlaylist = _host.seriesPlaylist;
    if (_host.manualContentImdbId != null &&
        _host.manualContentImdbId!.isNotEmpty) {
      imdbId = _host.manualContentImdbId;
    } else if (seriesPlaylist != null) {
      imdbId = seriesPlaylist.isSeries
          ? (seriesPlaylist.imdbId ?? _host.effectiveContentImdbId)
          : (seriesPlaylist.getImdbIdForIndex(_host.currentIndex) ??
                _host.effectiveContentImdbId);
    } else {
      imdbId = _host.singleFileImdbId ?? _host.effectiveContentImdbId;
    }

    String? contentType = _host.manualContentType ?? _host.effectiveContentType;
    if (contentType == null) {
      if (seriesPlaylist?.isSeries == true) {
        contentType = 'series';
      } else if (imdbId != null) {
        contentType = 'movie';
      }
    }

    final subtitleSeason = contentType == 'series' ? season : null;
    final subtitleEpisode = contentType == 'series' ? episode : null;
    final String? cacheKey = imdbId != null
        ? (subtitleSeason != null && subtitleEpisode != null
              ? '$imdbId:$subtitleSeason:$subtitleEpisode'
              : imdbId)
        : null;
    final baseSlots = (cacheKey != null && _host.cachedSubtitleKey == cacheKey)
        ? _host.cachedAddonSlots
        : null;
    final cachedSlots = _host.injectedSubtitleSlots != null
        ? [...?baseSlots, ..._host.injectedSubtitleSlots!]
        : baseSlots;

    openPlayerMenuAt(
      section,
      imdbId: imdbId,
      contentType: contentType,
      season: subtitleSeason,
      episode: subtitleEpisode,
      cachedSlots: cachedSlots,
      cacheKey: cacheKey,
    );
  }

  void hidePlayerMenu() {
    if (!_host.showPlayerMenu) return;
    _host.setState(() => _host.showPlayerMenu = false);
    if (PlatformUtil.isTelevision) _host.tvRootFocus.requestFocus();
  }

  /// Persist an explicit subtitle choice made from the menu.
  Future<void> menuApplyTrackChange(String audioId, String subtitleId) async {
    _host.userManuallySelectedSubtitle = true;
    if (!subtitleId.startsWith('stremio:')) {
      _host.setActiveExternalSubtitlePath(null);
    }
    _host.captureIptvAudioLanguage(audioId);
    await _host.persistTrackChoice(audioId, subtitleId);
  }

  Future<void> audioTrackChoiceChanged(
    String audioId,
    String currentSubId,
  ) async {
    _host.captureIptvAudioLanguage(audioId);
    await _host.persistTrackChoice(
      audioId,
      _host.hasSubtitlePolicy && !_host.userManuallySelectedSubtitle
          ? 'auto'
          : currentSubId,
    );
    await _host.refreshSubtitleAudioPolicy();
  }

  Future<void> menuSelectAudio(String audioId, String currentSubId) async {
    final track = _host.player.state.tracks.audio
        .where((a) => a.id == audioId)
        .firstOrNull;
    if (track == null) return;
    await _host.player.setAudioTrack(track);
    await audioTrackChoiceChanged(audioId, currentSubId);
  }

  Future<bool> withManualSubtitleChoice(Future<bool> Function() apply) async {
    if (!_host.hasSubtitlePolicy) return apply();
    final previouslyManual = _host.userManuallySelectedSubtitle;
    final token = _host.addonSubtitleFetchToken;
    final revision = ++_host.subtitleAudioRevision;
    _host.userManuallySelectedSubtitle = true;
    var applied = false;
    try {
      applied = await apply();
      return applied;
    } finally {
      if (!applied &&
          _host.mounted &&
          token == _host.addonSubtitleFetchToken &&
          revision == _host.subtitleAudioRevision) {
        _host.userManuallySelectedSubtitle = previouslyManual;
        unawaited(_host.refreshSubtitleAudioPolicy());
      }
    }
  }

  Future<bool> menuSubtitlesOff(String audioId) =>
      withManualSubtitleChoice(() async {
        final applied = await _host.setSubtitleTrackWithDiagnostics(
          mk.SubtitleTrack.no(),
          source: 'player-menu-off',
        );
        if (!applied) return false;
        _host.selectedStremioSubtitleId = null;
        await menuApplyTrackChange(audioId, 'no');
        return true;
      });

  Future<bool> menuSelectEmbeddedSubtitle(String subId, String audioId) =>
      withManualSubtitleChoice(() async {
        final track = _host.player.state.tracks.subtitle
            .where((s) => s.id == subId)
            .firstOrNull;
        if (track == null) {
          _host.showSubtitleFailureMessage(
            'That subtitle track is no longer available. Try another track.',
          );
          return false;
        }
        final applied = await _host.setSubtitleTrackWithDiagnostics(
          track,
          source: 'player-menu-embedded',
        );
        if (!applied) return false;
        _host.selectedStremioSubtitleId = null;
        await menuApplyTrackChange(audioId, subId);
        return true;
      });

  /// Returns false when the download/apply failed — the panel keeps the
  /// previous selection (and its sync offset) in that case.
  Future<bool> menuSelectAddonSubtitle(
    StremioSubtitle sub,
    String audioId,
  ) => withManualSubtitleChoice(() async {
    // Playback continues behind the menu: if the content switches while the
    // download is in flight (auto-advance, zap), applying the stale subtitle
    // would attach it — and persist its ids — against the NEW item.
    final token = _host.addonSubtitleFetchToken;
    try {
      final filePath = await _host.downloadStremioSubtitleToTempFile(sub);
      if (filePath == null) {
        _host.showSubtitleFailureMessage(
          'Couldn’t load subtitles. Check your connection or try another track.',
        );
        return false;
      }
      if (token != _host.addonSubtitleFetchToken || !_host.mounted) {
        return false;
      }
      final track = mk.SubtitleTrack.uri(
        filePath,
        title: sub.displayName,
        language: sub.lang,
      );
      final applied = await _host.applyExternalSubtitleTrack(track);
      if (!applied) return false;
      if (token != _host.addonSubtitleFetchToken || !_host.mounted) {
        return false;
      }
      _host.selectedStremioSubtitleId = sub.id;
      _host.setActiveExternalSubtitlePath(filePath);
      await menuApplyTrackChange(audioId, 'stremio:${sub.id}');
      return true;
    } catch (e) {
      debugPrint('PlayerMenu: subtitle apply failed - $e');
      _host.showSubtitleFailureMessage(
        'Couldn’t apply subtitles. Try another embedded or online track.',
      );
      return false;
    }
  });

  Future<bool> applyStremioSubtitleFromTracksSheet(
    StremioSubtitle sub,
  ) => withManualSubtitleChoice(() async {
    final token = _host.addonSubtitleFetchToken;
    try {
      final filePath = await _host.downloadStremioSubtitleToTempFile(sub);
      if (filePath == null) {
        _host.showSubtitleFailureMessage(
          'Couldn’t load subtitles. Check your connection or try another track.',
        );
        return false;
      }
      if (token != _host.addonSubtitleFetchToken || !_host.mounted) {
        return false;
      }
      final applied = await _host.applyExternalSubtitleTrack(
        mk.SubtitleTrack.uri(
          filePath,
          title: sub.displayName,
          language: sub.lang,
        ),
      );
      if (!applied) return false;
      if (token != _host.addonSubtitleFetchToken || !_host.mounted) {
        return false;
      }
      _host.setActiveExternalSubtitlePath(filePath);
      return true;
    } catch (e) {
      debugPrint('TracksSheet: subtitle apply failed - $e');
      _host.showSubtitleFailureMessage(
        'Couldn’t apply subtitles. Try another embedded or online track.',
      );
      return false;
    }
  });
}
