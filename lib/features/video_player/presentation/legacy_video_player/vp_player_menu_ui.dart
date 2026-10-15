import 'dart:async';
import 'dart:io';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/models/playlist_entry.dart';
import 'package:debrify/models/series_playlist.dart';
import 'package:debrify/models/stremio_subtitle.dart';
import 'package:debrify/screens/video_player/models/gesture_state.dart';
import 'package:debrify/screens/video_player/services/subtitle_settings_service.dart';
import 'package:debrify/screens/video_player/services/subtitle_track_utils.dart';
import 'package:debrify/screens/video_player/utils/language_mapping.dart';
import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:debrify/screens/video_player/widgets/sleep_timer_sheet.dart';
import 'package:debrify/screens/video_player/widgets/tracks_sheet.dart';
import 'package:debrify/utils/series_parser.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' as mk;

abstract interface class VpPlayerMenuUiHost {
  List<PlaylistEntry>? get activePlaylist;
  Future<bool> applyStremioSubtitleFromTracksSheet(StremioSubtitle sub);
  bool get audioPassthroughEnabled;
  Future<void> audioTrackChoiceChanged(String audioId, String currentSubId);
  List<AddonSubtitleSlot>? get cachedAddonSlots;
  set cachedAddonSlots(List<AddonSubtitleSlot>? v);
  set cachedStremioSubtitles(List<StremioSubtitle>? v);
  String? get cachedSubtitleKey;
  set cachedSubtitleKey(String? v);
  bool get canFetchEpisodes;
  void captureIptvAudioLanguage(String audioId);
  bool get continuousShuffleEnabled;
  int get currentIndex;
  IptvChannel? get currentIptvChannel;
  int? get effectiveContentEpisode;
  String? get effectiveContentImdbId;
  int? get effectiveContentSeason;
  String? get effectiveContentType;
  Future<void> fetchSingleFileMovieMetadata();
  void hidePlayerMenu();
  List<AddonSubtitleSlot>? get injectedSubtitleSlots;
  bool get iptvZapBannerOwnsIdentity;
  int? get manualContentEpisode;
  String? get manualContentImdbId;
  int? get manualContentSeason;
  String? get manualContentType;
  String? get menuCacheKey;
  List<AddonSubtitleSlot>? get menuCachedSlots;
  String? get menuContentType;
  int? get menuEpisode;
  String? get menuImdbId;
  int? get menuSeason;
  Future<bool> menuSelectAddonSubtitle(StremioSubtitle sub, String audioId);
  Future<void> menuSelectAudio(String audioId, String currentSubId);
  Future<bool> menuSelectEmbeddedSubtitle(String subId, String audioId);
  Future<bool> menuSubtitlesOff(String audioId);
  void openPlayerMenuAt(
    PlayerMenuSection section, {
    String? imdbId,
    String? contentType,
    int? season,
    int? episode,
    List<AddonSubtitleSlot>? cachedSlots,
    String? cacheKey,
  });
  Future<void> playRandomOnce({bool disableContinuousShuffle = false});
  mk.Player get player;
  PlayerMenuSection get playerMenuInitialSection;
  GlobalKey<PlayerMenuPanelState> get playerMenuKey;
  String? get selectedStremioSubtitleId;
  set selectedStremioSubtitleId(String? v);
  SeriesPlaylist? get seriesPlaylist;
  Future<void> setAudioPassthroughLive(bool enabled);
  bool get singleFileImdbFetched;
  String? get singleFileImdbId;
  ValueNotifier<String?> get subtitleSelectionCorrection;
  Future<void> toggleContinuousShuffle();
  set userManuallySelectedSubtitle(bool v);
  Future<bool> withManualSubtitleChoice(Future<bool> Function() apply);
  String currentPlaybackTitleForIdentity();
  Future<TracksSheetSubtitleSearchResult?> identifyTitleAndFetchSubtitles();
  String? subtitleIdentityLabelForSheet();
  void setActiveExternalSubtitlePath(String? path);
  void resetSubtitleSyncOffset();
  void onSubtitleStyleChanged(SubtitleSettingsData settings);
  void showSyncOverlayPanel();
  Future<void> persistTrackChoice(String audioId, String subtitleId);
  Future<bool> setSubtitleTrackWithDiagnostics(
    mk.SubtitleTrack track, {
    required String source,
    bool Function()? isCurrent,
  });
  double get playbackSpeed;
  void setPlaybackSpeed(double speed);
  AspectMode get aspectMode;
  void setAspectModeDirect(AspectMode mode);
  SleepTimerMode get sleepTimerMode;
  int get sleepTimerArmedMinutes;
  int get sleepTimerMinutesLeft;
  void applySleepTimerSelection(SleepTimerSelection picked);
}

class VpPlayerMenuUi {
  VpPlayerMenuUi(this._host);
  final VpPlayerMenuUiHost _host;

  Future<void> showTracksSheet(BuildContext context) async {
    // Dynamically parse season/episode from current video's filename
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

    // Get IMDB ID for current item
    // For series: uses shared IMDB ID (all episodes share same show ID)
    // For movies: uses per-item IMDB ID (each movie in collection has unique ID)
    String? effectiveImdbId;
    final seriesPlaylist = _host.seriesPlaylist;

    if (_host.manualContentImdbId != null &&
        _host.manualContentImdbId!.isNotEmpty) {
      effectiveImdbId = _host.manualContentImdbId;
    } else if (seriesPlaylist != null) {
      if (seriesPlaylist.isSeries) {
        // Series: use shared IMDB ID
        effectiveImdbId = seriesPlaylist.imdbId ?? _host.effectiveContentImdbId;
      } else {
        // Movie collection: try to get/fetch IMDB ID for current index
        effectiveImdbId = seriesPlaylist.getImdbIdForIndex(_host.currentIndex);

        // If not cached, try to fetch it now (async but we wait for it)
        if (effectiveImdbId == null && _host.effectiveContentImdbId == null) {
          debugPrint(
            'VideoPlayer: Fetching movie metadata for index ${_host.currentIndex} before showing tracks',
          );
          effectiveImdbId = await seriesPlaylist.fetchMovieMetadataForIndex(
            _host.currentIndex,
          );
        }

        // Fall back to widget's contentImdbId if still null
        effectiveImdbId ??= _host.effectiveContentImdbId;
      }
    } else {
      // Single-file playback (no playlist)
      // Try cached single-file IMDB ID, then widget's contentImdbId
      effectiveImdbId = _host.singleFileImdbId ?? _host.effectiveContentImdbId;

      // If not cached yet, try to fetch it now
      if (effectiveImdbId == null && !_host.singleFileImdbFetched) {
        debugPrint(
          'VideoPlayer: Fetching single-file movie metadata before showing tracks',
        );
        await _host.fetchSingleFileMovieMetadata();
        effectiveImdbId = _host.singleFileImdbId;
      }
    }

    // Determine content type
    // Priority: manual override > widget/channel metadata > playlist detection
    String? effectiveContentType =
        _host.manualContentType ?? _host.effectiveContentType;
    if (effectiveContentType == null) {
      if (seriesPlaylist?.isSeries == true) {
        effectiveContentType = 'series';
      } else if (effectiveImdbId != null) {
        // We have an IMDB ID (either from playlist or single-file lookup)
        // If not a series, it's a movie
        effectiveContentType = 'movie';
      }
    }

    debugPrint(
      'VideoPlayer: Opening TracksSheet with contentImdbId=$effectiveImdbId, '
      'contentType=$effectiveContentType, '
      'season=$season, episode=$episode (parsed from: $currentTitle)',
    );

    final subtitleSeason = effectiveContentType == 'series' ? season : null;
    final subtitleEpisode = effectiveContentType == 'series' ? episode : null;

    // Build cache key for subtitle caching (per-item like Android TV)
    final String? cacheKey = effectiveImdbId != null
        ? (subtitleSeason != null && subtitleEpisode != null
              ? '$effectiveImdbId:$subtitleSeason:$subtitleEpisode'
              : effectiveImdbId)
        : null;

    // Check if we have cached per-addon subtitle slots for this content.
    final List<AddonSubtitleSlot>? baseSlots =
        (cacheKey != null && _host.cachedSubtitleKey == cacheKey)
        ? _host.cachedAddonSlots
        : null;
    // Always include launch-supplied subtitles (e.g. YouTube captions). They
    // aren't IMDb-keyed, so they never live in the per-item cache above and
    // must be appended unconditionally — otherwise identifying the title (which
    // populates _cachedAddonSlots) would make the caption group disappear.
    final List<AddonSubtitleSlot>? cachedSlots =
        _host.injectedSubtitleSlots != null
        ? [...?baseSlots, ..._host.injectedSubtitleSlots!]
        : baseSlots;

    if (cachedSlots != null) {
      debugPrint(
        'VideoPlayer: Using ${cachedSlots.length} cached addon slots for key: $cacheKey',
      );
    }

    if (!context.mounted) return;

    if (kUnifiedPlayerMenuEnabled) {
      _host.openPlayerMenuAt(
        PlayerMenuSection.subtitles,
        imdbId: effectiveImdbId,
        contentType: effectiveContentType,
        season: subtitleSeason,
        episode: subtitleEpisode,
        cachedSlots: cachedSlots,
        cacheKey: cacheKey,
      );
      return;
    }

    await TracksSheet.show(
      context,
      _host.player,
      onAudioTrackChanged: _host.audioTrackChoiceChanged,
      onTrackChanged: (audioId, subtitleId) async {
        _host.userManuallySelectedSubtitle = true;
        if (!subtitleId.startsWith('stremio:')) {
          _host.setActiveExternalSubtitlePath(null);
        }
        // Remember the chosen audio language for this IPTV series (carries to
        // later episodes and future sessions). No-op off IPTV.
        _host.captureIptvAudioLanguage(audioId);
        await _host.persistTrackChoice(audioId, subtitleId);
      },
      // Fires only on a genuine subtitle switch (not audio, not re-select, not a
      // failed load): the sync offset was calibrated for the previous subtitle.
      onSubtitleTrackChanged: _host.resetSubtitleSyncOffset,
      // Android bitstream passthrough, applied LIVE (same stored setting as
      // the Playback Defaults row).
      audioPassthrough: !kIsWeb && Platform.isAndroid
          ? _host.audioPassthroughEnabled
          : null,
      onAudioPassthroughChanged: !kIsWeb && Platform.isAndroid
          ? _host.setAudioPassthroughLive
          : null,
      onSubtitleStyleChanged: _host.onSubtitleStyleChanged,
      onSyncOverlayRequested: _host.showSyncOverlayPanel,
      contentImdbId: effectiveImdbId,
      contentType: effectiveContentType,
      contentSeason: subtitleSeason,
      contentEpisode: subtitleEpisode,
      cachedAddonSlots: cachedSlots,
      onAddonSlotsFetched: (slots) {
        // Cache the per-addon slots (and their flat projection, which the
        // auto-select path consumes) for this content. If the identity was
        // fixed while the sheet was open, the identify flow already re-keyed
        // the cache — updates keyed to the stale open-time identity must not
        // clobber it.
        if (cacheKey == null) return;
        if (_host.cachedSubtitleKey != null &&
            _host.cachedSubtitleKey != cacheKey) {
          return;
        }
        _host.cachedAddonSlots = slots;
        _host.cachedStremioSubtitles = AddonSubtitleSlot.flatten(slots);
        _host.cachedSubtitleKey = cacheKey;
      },
      selectedStremioSubtitleId: _host.selectedStremioSubtitleId,
      subtitleSelectionCorrection: _host.subtitleSelectionCorrection,
      onStremioSubtitleSelected: (id) {
        _host.selectedStremioSubtitleId = id;
        _host.userManuallySelectedSubtitle = true;
      },
      onApplyEmbeddedSubtitle: (track) => _host.withManualSubtitleChoice(
        () => _host.setSubtitleTrackWithDiagnostics(
          track,
          source: 'tracks-sheet-embedded',
        ),
      ),
      onApplyStremioSubtitle: _host.applyStremioSubtitleFromTracksSheet,
      onIdentifyTitle: _host.identifyTitleAndFetchSubtitles,
      subtitleIdentityLabel: _host.subtitleIdentityLabelForSheet(),
    );
  }

  Widget buildPlayerMenuPanel() {
    final audios = _host.player.state.tracks.audio
        .where((a) => a.id.toLowerCase() != 'no')
        .toList(growable: false);
    final embedded = embeddedSubtitleTracks(_host.player.state.tracks.subtitle);
    final selectedSub = _host.selectedStremioSubtitleId != null
        ? 'stremio:${_host.selectedStremioSubtitleId}'
        : _host.player.state.track.subtitle.id;
    // Captured, not read live: cache write-back must be keyed to the identity
    // the menu opened with (an identity fix re-keys through its own path).
    final cacheKey = _host.menuCacheKey;

    return PlayerMenuPanel(
      key: _host.playerMenuKey,
      initialSection: _host.playerMenuInitialSection,
      onClose: _host.hidePlayerMenu,
      // mpv's `auto` pseudo-entry heads the list, labeled for what it is —
      // and kept, because persisting 'auto' is the only way to un-pin a
      // stored explicit track for this title (restore treats a stored 'auto'
      // as "use the default selection"). Real tracks are numbered without it
      // so the file's first stream still reads "Track 1".
      audioTracks: LanguageMapper.audioTrackOptions(
        audios,
        (id, label) => PlayerMenuTrackOption(id, label),
      ),
      selectedAudioId: _host.player.state.track.audio.id,
      onAudioSelected: _host.menuSelectAudio,
      audioPassthrough: !kIsWeb && Platform.isAndroid
          ? _host.audioPassthroughEnabled
          : null,
      onAudioPassthroughChanged: !kIsWeb && Platform.isAndroid
          ? _host.setAudioPassthroughLive
          : null,
      embeddedSubtitles: [
        for (final (i, s) in embedded.indexed)
          PlayerMenuTrackOption(s.id, LanguageMapper.labelForTrack(s, i)),
      ],
      selectedSubtitleId: selectedSub,
      onSubtitlesOff: _host.menuSubtitlesOff,
      onEmbeddedSubtitleSelected: _host.menuSelectEmbeddedSubtitle,
      onAddonSubtitleSelected: _host.menuSelectAddonSubtitle,
      onSubtitleTrackChanged: _host.resetSubtitleSyncOffset,
      contentImdbId: _host.menuImdbId,
      contentType: _host.menuContentType,
      contentSeason: _host.menuSeason,
      contentEpisode: _host.menuEpisode,
      cachedAddonSlots: _host.menuCachedSlots,
      onAddonSlotsFetched: (slots) {
        if (cacheKey == null) return;
        if (_host.cachedSubtitleKey != null &&
            _host.cachedSubtitleKey != cacheKey) {
          return;
        }
        _host.cachedAddonSlots = slots;
        _host.cachedStremioSubtitles = AddonSubtitleSlot.flatten(slots);
        _host.cachedSubtitleKey = cacheKey;
      },
      onIdentifyTitle: _host.identifyTitleAndFetchSubtitles,
      subtitleIdentityLabel: _host.subtitleIdentityLabelForSheet(),
      onSubtitleStyleChanged: _host.onSubtitleStyleChanged,
      onSyncRequested: _host.showSyncOverlayPanel,
      showSpeed: !_host.iptvZapBannerOwnsIdentity,
      speed: _host.playbackSpeed,
      onSpeedSelected: _host.setPlaybackSpeed,
      aspectMode: _host.aspectMode,
      onAspectSelected: _host.setAspectModeDirect,
      sleepMode: _host.sleepTimerMode,
      sleepArmedMinutes: _host.sleepTimerArmedMinutes,
      sleepMinutesLeft: _host.sleepTimerMinutesLeft,
      allowEndOfItem: _host.currentIptvChannel?.isLive != true,
      onSleepSelected: _host.applySleepTimerSelection,
      hasPlaylist:
          (_host.activePlaylist != null && _host.activePlaylist!.isNotEmpty) ||
          _host.canFetchEpisodes,
      continuousShuffle: _host.continuousShuffleEnabled,
      onShuffleOnce: () {
        _host.hidePlayerMenu();
        unawaited(_host.playRandomOnce(disableContinuousShuffle: true));
      },
      onShuffleContinuousToggle: () =>
          unawaited(_host.toggleContinuousShuffle()),
    );
  }
}
