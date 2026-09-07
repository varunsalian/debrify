import 'package:debrify/services/storage/playback_progress_store.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart' as mk;
import 'package:path_provider/path_provider.dart';

import '../../models/android_video_renderer_mode.dart';
import '../../models/series_playlist.dart';
import '../../models/stremio_addon.dart';
import '../../models/stremio_subtitle.dart';
import '../../services/storage_service.dart';
import '../../services/stremio_subtitle_service.dart';
import '../../utils/platform_util.dart';
import '../../widgets/player/identify_title_sheet.dart';
import 'services/external_subtitle_payload.dart';
import 'services/subtitle_track_utils.dart';
import 'utils/language_mapping.dart';
import 'widgets/tracks_sheet.dart';

/// Origin `_SubtitleApplyAttempt`.
class SubtitleApplyAttempt {
  final int generation;
  final mk.SubtitleTrack requested;
  final mk.SubtitleTrack previous;
  final String source;
  final String? previousStremioId;
  final String? previousExternalPath;
  bool failed = false;
  bool handled = false;
  bool successReturned = false;
  bool persisted = false;
  String? persistedAudioId;
  Completer<void>? persistenceDone;

  SubtitleApplyAttempt({
    required this.generation,
    required this.requested,
    required this.previous,
    required this.source,
    required this.previousStremioId,
    required this.previousExternalPath,
  });
}

/// Live player state the moved subtitle/track functions read and write.
///
/// Implemented by the player State. Named without host `_` prefixes so this
/// file compiles with those members removed (gate g).
abstract class SubtitleTrackSession {
  mk.Player get player;
  bool get isMounted;
  BuildContext get hostContext;

  /// Origin `widget.title` (empty → `'Unknown Video'`).
  String get videoTitle;

  SeriesPlaylist? get seriesPlaylist;
  String? get effectiveContentImdbId;
  String? get effectiveContentType;
  int? get effectiveContentSeason;
  int? get effectiveContentEpisode;
  String? get singleFileImdbId;
  int? get currentStremioTvContentSeason;
  int? get currentStremioTvContentEpisode;
  int? get launchContentSeason;
  int? get launchContentEpisode;

  AndroidVideoRendererMode get androidVideoRendererMode;
  bool get isIptvSeriesContext;
  int get iptvSwitchTicket;

  int get addonSubtitleFetchToken;
  set addonSubtitleFetchToken(int value);
  int get subtitleDiagnosticGeneration;
  set subtitleDiagnosticGeneration(int value);
  SubtitleApplyAttempt? get activeSubtitleApplyAttempt;
  set activeSubtitleApplyAttempt(SubtitleApplyAttempt? value);
  ValueNotifier<String?> get subtitleSelectionCorrection;

  List<StremioSubtitle>? get cachedStremioSubtitles;
  set cachedStremioSubtitles(List<StremioSubtitle>? value);
  List<AddonSubtitleSlot>? get cachedAddonSlots;
  set cachedAddonSlots(List<AddonSubtitleSlot>? value);
  String? get cachedSubtitleKey;
  set cachedSubtitleKey(String? value);
  String? get selectedStremioSubtitleId;
  set selectedStremioSubtitleId(String? value);
  bool get embeddedSubtitleApplied;
  set embeddedSubtitleApplied(bool value);
  bool get userManuallySelectedSubtitle;
  set userManuallySelectedSubtitle(bool value);
  bool get trackPreferencesReadyForAddonSubtitles;
  set trackPreferencesReadyForAddonSubtitles(bool value);
  Set<String> get tempSubtitleFiles;
  String? get activeExternalSubtitlePath;

  String? get manualContentImdbId;
  set manualContentImdbId(String? value);
  String? get manualContentType;
  set manualContentType(String? value);
  int? get manualContentSeason;
  set manualContentSeason(int? value);
  int? get manualContentEpisode;
  set manualContentEpisode(int? value);
  String? get manualSubtitleDisplayLabel;
  set manualSubtitleDisplayLabel(String? value);

  void runSetState(VoidCallback updates);
  void showSubtitleFailureMessage(String message);
  void showSnackBar(String message);
  void setActiveExternalSubtitlePath(String? path);
  void captureIptvAudioLanguage(String audioId);
  void resetSubtitleSyncOffset();
  void hidePlayerMenuOnContentChange();
  void reconcileMenuSubtitleSelection(String restoredSelection);
  Future<void> applyIptvAudioPreference(int ticket);
  SeriesEpisode? findSeriesEpisodeForCurrentIndex(
    SeriesPlaylist seriesPlaylist,
  );
  String currentPlaybackTitleForIdentity();
  SeasonEpisodeSelection? currentSeasonEpisodeForIdentity();
}

/// Origin `_normalisedContentType`.
String normalisedSubtitleContentType(String type) =>
    type.toLowerCase() == 'series' ? 'series' : 'movie';

/// Origin `_subtitleSearchDisplayLabel`.
String subtitleSearchDisplayLabel(
  StremioMeta meta, {
  required String contentType,
  int? season,
  int? episode,
}) {
  final year = meta.year?.trim();
  final title = year != null && year.isNotEmpty
      ? '${meta.name} ($year)'
      : meta.name;
  if (contentType == 'series' && season != null && episode != null) {
    return '$title S${season}E$episode';
  }
  return title;
}

/// Origin `_subtitlePreferenceMatchesAttempt`.
bool subtitlePreferenceMatchesAttempt(
  String subtitle,
  SubtitleApplyAttempt attempt,
) {
  if (attempt.requested.id == 'no') return subtitle == 'no';
  if (attempt.requested.uri || attempt.requested.data) {
    return subtitle.startsWith('stremio:');
  }
  return subtitle == attempt.requested.id;
}

/// Player subtitle/track restore, persist, diagnostics, and addon fetch.
///
/// Bodies moved from `_VideoPlayerScreenState`. Mutations go through
/// [SubtitleTrackSession]. Temp-file cleanup is invoked from host `dispose`.
class SubtitleTrackController {
  SubtitleTrackController(this.session);

  final SubtitleTrackSession session;

  // Wait for subtitle tracks to be parsed from the media file
  // media_kit initially only has 'auto' and 'no' tracks, real tracks come later
  Future<void> waitForSubtitleTracks({required int token}) async {
    // Wait up to 5 seconds for subtitle tracks to be available
    for (int i = 0; i < 50; i++) {
      if (token != session.addonSubtitleFetchToken) return;
      final tracks = session.player.state.tracks.subtitle;
      // Check if we have any real tracks (not just 'auto' and 'no')
      final hasRealTracks = tracks.any(
        (t) => t.id != 'auto' && t.id != 'no' && t.id.isNotEmpty,
      );
      if (hasRealTracks) {
        return;
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }
    // Timeout reached - video may not have embedded subtitles
  }

  static String diagnosticSubtitleId(mk.SubtitleTrack track) =>
      track.uri || track.data ? '<external>' : track.id;

  Future<void> setNativeSubtitleVisibilityForTrack(
    mk.SubtitleTrack track,
  ) async {
    final platform = session.player.platform;
    if (platform is! mk.NativePlayer) return;
    final nativeRendering = requiresNativeSubtitleRendering(track);
    await platform.setProperty(
      'sub-visibility',
      nativeRendering ? 'yes' : 'no',
    );
  }

  /// Records both media_kit's optimistic Dart state and libmpv's authoritative
  /// properties. This distinction matters for subtitle selection: media_kit
  /// updates `state.track.subtitle` after the property-set request completes,
  /// while mpv may still retain a different `sid` or fail to decode the track.
  Future<bool> setSubtitleTrackWithDiagnostics(
    mk.SubtitleTrack track, {
    required String source,
  }) async {
    if (Platform.isAndroid &&
        !PlatformUtil.isAndroidTvCached &&
        requiresNativeSubtitleRendering(track) &&
        session.androidVideoRendererMode !=
            AndroidVideoRendererMode.directMediaCodec) {
      session.showSubtitleFailureMessage(
        'Bitmap subtitles require MediaCodec + GPU. Change Video renderer in Settings and restart playback.',
      );
      debugPrint(
        '[SubtitleDiag] apply rejected source=$source '
        'reason=android_renderer_incompatible',
      );
      return false;
    }
    final diagnosticGeneration = ++session.subtitleDiagnosticGeneration;
    final attempt = SubtitleApplyAttempt(
      generation: diagnosticGeneration,
      requested: track,
      previous: session.player.state.track.subtitle,
      source: source,
      previousStremioId: session.selectedStremioSubtitleId,
      previousExternalPath: session.activeExternalSubtitlePath,
    );
    session.activeSubtitleApplyAttempt = attempt;
    // Null arms the next correction even when two failures restore the same
    // selection consecutively.
    session.subtitleSelectionCorrection.value = null;

    try {
      await setNativeSubtitleVisibilityForTrack(track);
      await session.player.setSubtitleTrack(track);
    } catch (error, stackTrace) {
      debugPrint(
        '[SubtitleDiag] set FAILED source=$source '
        'requestedId=${diagnosticSubtitleId(track)} '
        'error=$error\n$stackTrace',
      );
      await handleSubtitleApplyFailure(attempt, error.toString());
      return false;
    }
    // mpv posts decoder failures through its log stream immediately after the
    // property reply. Give that event one run-loop turn before reporting
    // success to optimistic menu UI; late failures are still handled by the
    // active attempt above and roll the selection back centrally.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (attempt.failed) return false;

    attempt.successReturned = true;
    return true;
  }

  Future<void> handleSubtitleApplyFailure(
    SubtitleApplyAttempt attempt,
    String reason,
  ) async {
    if (attempt.handled ||
        session.activeSubtitleApplyAttempt != attempt ||
        attempt.generation != session.subtitleDiagnosticGeneration) {
      return;
    }
    attempt.failed = true;
    attempt.handled = true;
    session.activeSubtitleApplyAttempt = null;

    final previous = attempt.previous;
    final sameTrack = previous.id == attempt.requested.id;
    final fallback = previous.id == 'auto' || sameTrack
        ? mk.SubtitleTrack.no()
        : previous;
    var restoredOriginalSelection = fallback.id == previous.id;
    try {
      await setNativeSubtitleVisibilityForTrack(fallback);
      await session.player.setSubtitleTrack(fallback);
    } catch (error) {
      restoredOriginalSelection = false;
      debugPrint(
        '[SubtitleDiag] rollback FAILED source=${attempt.source} error=$error',
      );
      try {
        final noTrack = mk.SubtitleTrack.no();
        await setNativeSubtitleVisibilityForTrack(noTrack);
        await session.player.setSubtitleTrack(noTrack);
      } catch (_) {
        // The original actionable error is surfaced below. A second snackbar
        // for rollback failure would obscure it without giving the user a
        // useful recovery action.
      }
    }

    session.selectedStremioSubtitleId = restoredOriginalSelection
        ? attempt.previousStremioId
        : null;
    session.setActiveExternalSubtitlePath(
      restoredOriginalSelection ? attempt.previousExternalPath : null,
    );
    final String restoredSelection;
    if (restoredOriginalSelection && attempt.previousStremioId != null) {
      restoredSelection = 'stremio:${attempt.previousStremioId}';
    } else {
      restoredSelection = restoredOriginalSelection ? fallback.id : 'no';
    }

    // A decoder error can arrive after the property reply and after a picker
    // has persisted its optimistic selection. Undo that commit as part of the
    // same rollback, while leaving automatic (never-persisted) attempts alone.
    if (attempt.successReturned && attempt.persisted) {
      await attempt.persistenceDone?.future;
      await persistTrackChoice(
        attempt.persistedAudioId ?? session.player.state.track.audio.id,
        restoredSelection,
      );
    }
    if (!session.isMounted) return;
    session.runSetState(() {});
    session.reconcileMenuSubtitleSelection(restoredSelection);
    session.subtitleSelectionCorrection.value = restoredSelection;

    final codec = attempt.requested.codec;
    final message = codec == null || codec.isEmpty
        ? 'Couldn’t apply subtitles. Try another embedded or online track.'
        : 'Couldn’t decode $codec subtitles. Try another embedded or online track.';
    session.showSubtitleFailureMessage(message);
    debugPrint(
      '[SubtitleDiag] user notified source=${attempt.source} reason=$reason',
    );
  }

  String? subtitleIdentityLabelForSheet() {
    final manualLabel = session.manualSubtitleDisplayLabel?.trim();
    if (manualLabel != null && manualLabel.isNotEmpty) {
      return 'Subtitles for $manualLabel';
    }

    // Inlined origin `_identitySearchInitialQuery` 3-line forwarder.
    final detectedTitle = identifyTitleSearchInitialQuery(
      session.currentPlaybackTitleForIdentity(),
    );
    if (detectedTitle.isEmpty) return null;
    return 'Detected: $detectedTitle';
  }

  Future<TracksSheetSubtitleSearchResult?>
  identifyTitleAndFetchSubtitles() async {
    final identifyToken = session.addonSubtitleFetchToken;
    final selected = await showIdentifyTitleSearchSheet(
      context: session.hostContext,
      initialQuery: identifyTitleSearchInitialQuery(
        session.currentPlaybackTitleForIdentity(),
      ),
    );
    if (!session.isMounted ||
        selected == null ||
        identifyToken != session.addonSubtitleFetchToken) {
      return null;
    }

    final imdbId = selected.effectiveImdbId;
    if (imdbId == null || !imdbId.startsWith('tt')) {
      session.showSnackBar('Selected title has no IMDb ID');
      return null;
    }

    final contentType = normalisedSubtitleContentType(selected.type);
    int? season;
    int? episode;

    if (contentType == 'series') {
      final currentEpisode = session.currentSeasonEpisodeForIdentity();
      season = currentEpisode?.season;
      episode = currentEpisode?.episode;

      if (season == null || episode == null) {
        final entered = await requestSeasonEpisodeForIdentity(
          // Origin used host context after the sheet await (same gap).
          // ignore: use_build_context_synchronously
          session.hostContext,
          selected.name,
        );
        if (!session.isMounted ||
            entered == null ||
            identifyToken != session.addonSubtitleFetchToken) {
          return null;
        }
        season = entered.season;
        episode = entered.episode;
      }
    }

    final displayLabel = subtitleSearchDisplayLabel(
      selected,
      contentType: contentType,
      season: season,
      episode: episode,
    );

    final fetchToken = session.addonSubtitleFetchToken + 1;
    session.runSetState(() {
      session.addonSubtitleFetchToken = fetchToken;
      session.manualContentImdbId = imdbId;
      session.manualContentType = contentType;
      session.manualContentSeason = contentType == 'series' ? season : null;
      session.manualContentEpisode = contentType == 'series' ? episode : null;
      session.manualSubtitleDisplayLabel = displayLabel;
      session.selectedStremioSubtitleId = null;
      session.embeddedSubtitleApplied = false;
      session.userManuallySelectedSubtitle = false;
      session.cachedStremioSubtitles = null;
      session.cachedAddonSlots = null;
      session.cachedSubtitleKey = null;
    });

    try {
      final slots = await StremioSubtitleService.instance.fetchSubtitleSlots(
        type: contentType,
        imdbId: imdbId,
        season: contentType == 'series' ? season : null,
        episode: contentType == 'series' ? episode : null,
      );
      final subtitles = AddonSubtitleSlot.flatten(slots);

      if (!session.isMounted || fetchToken != session.addonSubtitleFetchToken) {
        return null;
      }

      final cacheKey =
          contentType == 'series' && season != null && episode != null
          ? '$imdbId:$season:$episode'
          : imdbId;

      session.cachedStremioSubtitles = subtitles;
      session.cachedAddonSlots = slots;
      session.cachedSubtitleKey = cacheKey;

      await fetchAndMaybeAutoSelectAddonSubtitle();

      if (subtitles.isEmpty && session.isMounted) {
        session.showSnackBar('No online subtitles found for this title');
      }

      return TracksSheetSubtitleSearchResult(
        subtitles: subtitles,
        slots: slots,
        selectedSubtitleId: session.selectedStremioSubtitleId,
        identityLabel: 'Subtitles for $displayLabel',
        imdbId: imdbId,
        contentType: contentType,
        season: contentType == 'series' ? season : null,
        episode: contentType == 'series' ? episode : null,
      );
    } catch (e) {
      debugPrint('VideoPlayer: Search subtitle fetch failed: $e');
      if (session.isMounted) {
        session.showSnackBar('Subtitle search failed');
      }
      return null;
    }
  }

  /// Reset subtitle-related state when switching content.
  void resetSubtitleState() {
    session.cachedStremioSubtitles = null;
    session.cachedAddonSlots = null;
    session.cachedSubtitleKey = null;
    session.selectedStremioSubtitleId = null;
    session.manualContentImdbId = null;
    session.manualContentType = null;
    session.manualContentSeason = null;
    session.manualContentEpisode = null;
    session.manualSubtitleDisplayLabel = null;
    session.embeddedSubtitleApplied = false;
    session.userManuallySelectedSubtitle = false;
    session.trackPreferencesReadyForAddonSubtitles = false;
    session.addonSubtitleFetchToken++;
    session.subtitleDiagnosticGeneration++;
    session.activeSubtitleApplyAttempt = null;
    cleanupTempSubtitleFilesSync();
    session.setActiveExternalSubtitlePath(null);
    session.hidePlayerMenuOnContentChange();
    // Content changed: the previous item's sync offset no longer applies.
    session.resetSubtitleSyncOffset();
  }

  /// Restore audio and subtitle track preferences
  Future<void> restoreTrackPreferences() async {
    // Capture token to detect if content changes during async operations
    final restoreToken = session.addonSubtitleFetchToken;

    try {
      debugPrint(
        'SubAuto: _restoreTrackPreferences entered (token=$restoreToken)',
      );
      // Wait for subtitle tracks to be parsed from the media file
      // media_kit initially only has 'auto' and 'no' placeholder tracks
      await waitForSubtitleTracks(token: restoreToken);

      if (restoreToken != session.addonSubtitleFetchToken) {
        debugPrint(
          'SubAuto: restore aborted after track wait (content changed)',
        );
        return;
      }

      final seriesPlaylist = session.seriesPlaylist;
      Map<String, dynamic>? trackPreferences;

      if (seriesPlaylist != null && seriesPlaylist.isSeries) {
        // For series content, get preferences for the entire series
        trackPreferences = await PlaybackProgressStore.getSeriesTrackPreferences(
          seriesTitle: seriesPlaylist.seriesTitle ?? 'Unknown Series',
        );
      } else {
        // For non-series content, get preferences for this specific video
        // Origin: widget.title.isNotEmpty (session.videoTitle).
        final videoTitle = session.videoTitle.isNotEmpty
            ? session.videoTitle
            : 'Unknown Video';
        trackPreferences = await PlaybackProgressStore.getVideoTrackPreferences(
          videoTitle: videoTitle,
        );
      }

      // Bail out if content changed during preferences fetch
      if (restoreToken != session.addonSubtitleFetchToken) {
        debugPrint(
          'SubAuto: restore aborted (content changed during prefs fetch)',
        );
        return;
      }

      final subTracksNow = session.player.state.tracks.subtitle
          .map((t) => '${t.id}/${t.language}/${t.title}')
          .toList();
      debugPrint(
        'SubAuto: restore start — prefs=${trackPreferences == null ? 'NONE' : trackPreferences.toString()} '
        'subtitleTracks=$subTracksNow currentSub=${session.player.state.track.subtitle.id}',
      );

      bool subtitleApplied = false;

      if (trackPreferences != null) {
        final audioTrackId = trackPreferences['audioTrackId'] as String?;
        final subtitleTrackId = trackPreferences['subtitleTrackId'] as String?;

        // Apply audio track preference — only if the stored id exists in
        // THIS file (mirrors the subtitle branch). Prefs are keyed by title
        // and store bare mpv ordinals, so a different release of the same
        // title can carry the ordinal elsewhere; the old fallback landed on
        // tracks.audio.first, which is the 'auto' pseudo-track.
        if (audioTrackId != null &&
            audioTrackId.isNotEmpty &&
            audioTrackId != 'auto') {
          final audioTrack = session.player.state.tracks.audio
              .where((track) => track.id == audioTrackId)
              .firstOrNull;
          if (audioTrack != null) {
            await session.player.setAudioTrack(audioTrack);
          } else {
            await applyDefaultAudioLanguage();
          }
        } else {
          // No stored audio preference - apply default audio language setting
          await applyDefaultAudioLanguage();
        }

        // Bail out if content changed during audio track application
        if (restoreToken != session.addonSubtitleFetchToken) return;

        // Apply subtitle track preference. A stored 'auto' is mpv's default
        // placeholder — persisted whenever the user changed AUDIO without
        // ever picking a subtitle — not an explicit subtitle choice. Honoring
        // it would mark an embedded subtitle as applied (mpv 'auto' shows the
        // file's default track, often English) and block addon auto-select of
        // the preferred language. Mirror the audio branch's 'auto' guard and
        // fall through to the default-language path instead.
        if (subtitleTrackId != null &&
            subtitleTrackId.isNotEmpty &&
            subtitleTrackId != 'auto') {
          final tracks = session.player.state.tracks;
          // Check if the stored track actually exists in this video
          final trackExists = tracks.subtitle.any(
            (t) =>
                t.id == subtitleTrackId && !isAppManagedAddonSubtitleTrack(t),
          );
          if (trackExists) {
            final subtitleTrack = tracks.subtitle.firstWhere(
              (track) =>
                  track.id == subtitleTrackId &&
                  !isAppManagedAddonSubtitleTrack(track),
            );
            // A stored pick that CONFLICTS with the current global default
            // language is stale — it predates the user changing the setting
            // (the ids are bare mpv ordinals, so it can't be trusted across
            // setting changes). Let the default-language path win instead:
            // embedded match first, else addon auto-select. Stored 'no'
            // (explicit off for this series) is always honored.
            final defaultLang =
                await StorageService.getDefaultSubtitleLanguage();
            final conflictsWithDefault =
                subtitleTrackId != 'no' &&
                defaultLang != null &&
                (defaultLang == 'off' ||
                    !(LanguageMapper.matchesLanguage(
                          defaultLang,
                          subtitleTrack.language,
                        ) ||
                        LanguageMapper.matchesLanguage(
                          defaultLang,
                          subtitleTrack.title,
                        )));
            if (conflictsWithDefault) {
              debugPrint(
                'SubAuto: stored track id=$subtitleTrackId '
                '(lang=${subtitleTrack.language}/${subtitleTrack.title}) '
                'conflicts with default=$defaultLang → default-language path',
              );
              subtitleApplied = await applyDefaultSubtitleLanguage();
            } else {
              debugPrint(
                'SubAuto: applying STORED subtitle track id=$subtitleTrackId '
                '(lang=${subtitleTrack.language}/${subtitleTrack.title}) — blocks addon auto-select',
              );
              subtitleApplied = await setSubtitleTrackWithDiagnostics(
                subtitleTrack,
                source: 'restore-stored-embedded',
              );
            }
          } else {
            // Stored track doesn't exist in this video - fall through to default
            debugPrint(
              'SubAuto: stored subtitle id=$subtitleTrackId not in this file → default-language path',
            );
            subtitleApplied = await applyDefaultSubtitleLanguage();
          }
        } else {
          // No stored subtitle preference - apply default subtitle language setting
          debugPrint(
            'SubAuto: stored subtitle id=$subtitleTrackId treated as no-choice → default-language path',
          );
          subtitleApplied = await applyDefaultSubtitleLanguage();
        }
      } else {
        // No track preferences at all - apply default language settings
        debugPrint('SubAuto: no stored prefs → default-language path');
        await applyDefaultAudioLanguage();
        subtitleApplied = await applyDefaultSubtitleLanguage();
      }

      // IPTV series: the language-based memory wins over the per-title ordinal
      // / global default applied above (episodes are separate files whose track
      // orderings differ, so only language carries). No-op off a series episode.
      // No switch is in flight on the initial open, so the current ticket is a
      // valid generation for the staleness guard.
      if (session.isIptvSeriesContext) {
        await session.applyIptvAudioPreference(session.iptvSwitchTicket);
      }

      // Final check before applying state
      if (restoreToken != session.addonSubtitleFetchToken) {
        debugPrint('SubAuto: restore aborted post-apply (content changed)');
        return;
      }

      // Track if embedded subtitle was applied for addon fallback
      session.embeddedSubtitleApplied = subtitleApplied;
      session.trackPreferencesReadyForAddonSubtitles = true;
      debugPrint(
        'SubAuto: restore done — embeddedSubtitleApplied=$subtitleApplied → running addon auto-select',
      );

      // Always fetch Stremio addon subtitles proactively (like Android TV)
      // Auto-selection will only happen if no embedded subtitle was applied
      fetchAndMaybeAutoSelectAddonSubtitle();
    } catch (e) {
      debugPrint('SubAuto: restore FAILED with exception: $e');
    }
  }

  /// Apply default audio language from settings (when no stored preference exists)
  Future<void> applyDefaultAudioLanguage() async {
    try {
      final defaultLang = await StorageService.getDefaultAudioLanguage();
      if (defaultLang == null) {
        // No preference set - do nothing, let player use its default
        return;
      }

      final tracks = session.player.state.tracks;
      if (tracks.audio.isEmpty) return;

      // If mpv's own selection (via the `alang` set at configure time)
      // already matches the preference, keep it: mpv's matcher weighs the
      // default/forced dispositions, so on a file with a normal and a
      // commentary track in the same language it lands on the right one —
      // the first-match loop below would overwrite that with whichever
      // matching track enumerates first.
      final platform = session.player.platform;
      if (platform is mk.NativePlayer) {
        try {
          final currentLang = await platform.getProperty(
            'current-tracks/audio/lang',
          );
          if (LanguageMapper.matchesLanguage(defaultLang, currentLang)) {
            return;
          }
        } catch (_) {
          // Property unanswered — fall through to the metadata matcher.
        }
      }

      // Find an audio track matching the preferred language using robust matching
      mk.AudioTrack? matchingTrack;
      for (final track in tracks.audio) {
        if (LanguageMapper.matchesLanguage(defaultLang, track.language)) {
          matchingTrack = track;
          break;
        }
        // Also check title field as some tracks store language there
        if (LanguageMapper.matchesLanguage(defaultLang, track.title)) {
          matchingTrack = track;
          break;
        }
      }

      if (matchingTrack != null) {
        await session.player.setAudioTrack(matchingTrack);
      }
    } catch (e) {
      // Silently fail - audio preference is non-critical
    }
  }

  /// Apply default subtitle language from settings (when no stored preference exists)
  /// Returns true if an embedded subtitle was found and applied, false otherwise.
  Future<bool> applyDefaultSubtitleLanguage() async {
    try {
      final defaultLang = await StorageService.getDefaultSubtitleLanguage();
      debugPrint('SubAuto: defaultSubtitleLanguage setting = $defaultLang');
      if (defaultLang == null) {
        // No preference set - do nothing, let player use its default
        return false;
      }

      final tracks = session.player.state.tracks;

      if (defaultLang == 'off') {
        // Explicitly disable subtitles
        final applied = await setSubtitleTrackWithDiagnostics(
          mk.SubtitleTrack.no(),
          source: 'default-language-off',
        );
        return applied; // User explicitly disabled, don't try addon
      }

      // Find a subtitle track matching the preferred language using robust matching
      // This handles ISO 639-1, ISO 639-2, regional variants, and language names
      mk.SubtitleTrack? matchingTrack;
      for (final track in tracks.subtitle) {
        if (isAppManagedAddonSubtitleTrack(track)) continue;
        if (LanguageMapper.matchesLanguage(defaultLang, track.language)) {
          matchingTrack = track;
          break;
        }
        // Also check title field as some tracks store language there
        if (LanguageMapper.matchesLanguage(defaultLang, track.title)) {
          matchingTrack = track;
          break;
        }
      }

      if (matchingTrack != null) {
        debugPrint(
          'SubAuto: matched EMBEDDED track id=${matchingTrack.id} lang=${matchingTrack.language} title=${matchingTrack.title} — applying',
        );
        return await setSubtitleTrackWithDiagnostics(
          matchingTrack,
          source: 'default-language-embedded',
        );
      }
      debugPrint(
        'SubAuto: no $defaultLang embedded track → returning false (addon auto-select may run)',
      );
      return false;
    } catch (e) {
      // Silently fail - subtitle preference is non-critical
      debugPrint('SubAuto: _applyDefaultSubtitleLanguage FAILED: $e');
      return false;
    }
  }

  /// Download an addon subtitle's raw bytes and write them to a temp file.
  ///
  /// Returning a file path (rather than a pre-decoded string) lets libmpv
  /// auto-detect the character encoding via its `sub-codepage=auto` default,
  /// which correctly handles GBK, Big5, EUC-KR, Windows-125x, etc. Pre-decoding
  /// via `http.Response.body` would silently corrupt non-UTF-8 subtitle files.
  Future<String?> downloadStremioSubtitleToTempFile(StremioSubtitle sub) async {
    try {
      final uri = Uri.parse(sub.url);
      final dir = await getTemporaryDirectory();
      final stem = externalSubtitleCacheStem(sub.url);
      for (final ext in const [
        'srt',
        'vtt',
        'ass',
        'ssa',
        'ttml',
        'xml',
        'sub',
      ]) {
        final cached = File('${dir.path}/stremio_sub_$stem.$ext');
        if (cached.existsSync()) {
          final cachedLength = cached.lengthSync();
          if (cachedLength > 0 && cachedLength <= maxDecodedSubtitleBytes) {
            session.tempSubtitleFiles.add(cached.path);
            return cached.path;
          }
          cached.deleteSync();
        }
      }

      final client = http.Client();
      late http.StreamedResponse response;
      try {
        response = await client
            .send(http.Request('GET', uri))
            .timeout(const Duration(seconds: 15));
        final declaredLength = response.contentLength;
        if (declaredLength != null &&
            declaredLength > maxSubtitleResponseBytes) {
          debugPrint(
            'VideoPlayer: Subtitle download rejected: '
            '$declaredLength bytes exceeds limit',
          );
          return null;
        }
        if (response.statusCode != 200) {
          debugPrint(
            'VideoPlayer: Subtitle download failed: HTTP ${response.statusCode}',
          );
          return null;
        }

        final responseBytes = await readBoundedSubtitleResponse(
          response.stream,
        ).timeout(const Duration(seconds: 15));
        final payload = prepareExternalSubtitlePayload(responseBytes, uri);
        final file = File('${dir.path}/stremio_sub_$stem.${payload.extension}');
        final partial = File('${file.path}.part');
        await partial.writeAsBytes(payload.bytes, flush: true);
        if (file.existsSync()) file.deleteSync();
        await partial.rename(file.path);
        session.tempSubtitleFiles.add(file.path);
        debugPrint(
          'VideoPlayer: Subtitle written to temp file: ${file.path} '
          '(${payload.bytes.length} bytes)',
        );
        return file.path;
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('VideoPlayer: Subtitle download/write failed: $e');
      return null;
    }
  }

  /// Load a replacement first, then unload older addon tracks. A malformed
  /// replacement therefore leaves the currently working subtitle untouched.
  Future<bool> applyExternalSubtitleTrack(mk.SubtitleTrack track) async {
    // Track IDs are small mpv ordinals and may be reused by the next media.
    // Keep the content generation with this operation so a delayed apply can
    // never remove a same-numbered subtitle from newly opened content.
    final contentToken = session.addonSubtitleFetchToken;
    final oldExternalIds = session.player.state.tracks.subtitle
        .where(isAppManagedAddonSubtitleTrack)
        .map((subtitle) => subtitle.id)
        .toList(growable: false);

    final applied = await setSubtitleTrackWithDiagnostics(
      track,
      source: 'addon-external',
    );
    if (!applied) return false;

    final platform = session.player.platform;
    if (platform is mk.NativePlayer) {
      for (final id in oldExternalIds) {
        if (!session.isMounted ||
            contentToken != session.addonSubtitleFetchToken) {
          debugPrint(
            'VideoPlayer: Content changed during addon subtitle cleanup; '
            'stopping before track $id',
          );
          return false;
        }
        try {
          await platform.command(['sub-remove', id]);
        } catch (e) {
          debugPrint('VideoPlayer: Failed to unload external subtitle $id: $e');
        }
      }
    }
    return true;
  }

  /// Delete any temp subtitle files we've written. Called from dispose.
  /// Origin _cleanupTempSubtitleFilesSync.
  void cleanupTempSubtitleFilesSync() {
    for (final path in session.tempSubtitleFiles) {
      try {
        File(path).deleteSync();
      } catch (e) {
        debugPrint('VideoPlayer: Failed to delete temp subtitle $path: $e');
      }
    }
    session.tempSubtitleFiles.clear();
  }

  /// Fetch Stremio addon subtitles proactively and auto-select if no embedded subtitle was applied.
  /// This mirrors the Android TV behavior where subtitles are always fetched on playback start.
  Future<void> fetchAndMaybeAutoSelectAddonSubtitle() async {
    // Capture token at start to detect if content changes during async operations
    final fetchToken = session.addonSubtitleFetchToken;

    try {
      // Get content info for Stremio subtitle fetch
      final seriesPlaylist = session.seriesPlaylist;
      String? imdbId;
      String contentType;
      int? season;
      int? episode;

      if (session.manualContentImdbId != null &&
          session.manualContentImdbId!.isNotEmpty) {
        imdbId = session.manualContentImdbId;
        contentType = session.manualContentType == 'series'
            ? 'series'
            : 'movie';
        if (contentType == 'series') {
          season = session.manualContentSeason;
          episode = session.manualContentEpisode;
          if ((season == null || episode == null) &&
              seriesPlaylist != null &&
              seriesPlaylist.isSeries) {
            final currentEp = session.findSeriesEpisodeForCurrentIndex(
              seriesPlaylist,
            );
            season ??= currentEp?.seriesInfo.season;
            episode ??= currentEp?.seriesInfo.episode;
          }
          season ??=
              session.currentStremioTvContentSeason ??
              session.launchContentSeason;
          episode ??=
              session.currentStremioTvContentEpisode ??
              session.launchContentEpisode;
        }
      } else if (seriesPlaylist != null && seriesPlaylist.isSeries) {
        imdbId = seriesPlaylist.imdbId ?? session.effectiveContentImdbId;
        contentType = 'series';
        // Get current episode info from playlist using current index
        final currentEp = session.findSeriesEpisodeForCurrentIndex(
          seriesPlaylist,
        );
        if (currentEp != null) {
          season = currentEp.seriesInfo.season;
          episode = currentEp.seriesInfo.episode;
        }
      } else {
        // Use widget's content IMDB ID or single file IMDB ID
        imdbId = session.effectiveContentImdbId ?? session.singleFileImdbId;
        // Single-file series playback: use widget params for S/E
        if (session.effectiveContentType == 'series' &&
            session.effectiveContentSeason != null &&
            session.effectiveContentEpisode != null) {
          contentType = 'series';
          season = session.effectiveContentSeason;
          episode = session.effectiveContentEpisode;
        } else {
          contentType = 'movie';
        }
      }

      // Need IMDB ID to fetch Stremio subtitles
      if (imdbId == null || imdbId.isEmpty) {
        debugPrint('SubAuto: ABORT — no IMDB ID for addon subtitle fetch');
        return;
      }
      debugPrint(
        'SubAuto: addon auto-select start — imdb=$imdbId type=$contentType s=$season e=$episode',
      );

      // Build cache key
      final cacheKey = season != null && episode != null
          ? '$imdbId:$season:$episode'
          : imdbId;

      // Check if we have cached subtitles
      List<StremioSubtitle> subtitles;
      if (session.cachedSubtitleKey == cacheKey &&
          session.cachedStremioSubtitles != null) {
        subtitles = session.cachedStremioSubtitles!;
        debugPrint(
          'VideoPlayer: Using ${subtitles.length} cached addon subtitles',
        );
      } else {
        // Fetch Stremio subtitles proactively (per-addon slots, so the
        // sheet's addon groups are warm when opened)
        debugPrint('VideoPlayer: Fetching addon subtitles (IMDB: $imdbId)');
        final slots = await StremioSubtitleService.instance.fetchSubtitleSlots(
          type: contentType,
          imdbId: imdbId,
          season: season,
          episode: episode,
        );
        subtitles = AddonSubtitleSlot.flatten(slots);

        // Check if content changed during fetch
        if (fetchToken != session.addonSubtitleFetchToken) {
          debugPrint(
            'VideoPlayer: Content changed during addon subtitle fetch, discarding results',
          );
          return;
        }

        // Cache the results
        session.cachedStremioSubtitles = subtitles;
        session.cachedAddonSlots = slots;
        session.cachedSubtitleKey = cacheKey;
        debugPrint(
          'VideoPlayer: Fetched and cached ${subtitles.length} addon subtitles',
        );
      }

      // Only auto-select if no embedded subtitle was applied and user hasn't manually selected
      if (session.embeddedSubtitleApplied) {
        debugPrint(
          'SubAuto: SKIP — embedded subtitle already applied (_embeddedSubtitleApplied=true)',
        );
        return;
      }

      if (session.userManuallySelectedSubtitle) {
        debugPrint(
          'SubAuto: SKIP — user manually selected a subtitle this session',
        );
        return;
      }

      if (subtitles.isEmpty) {
        debugPrint('SubAuto: SKIP — zero addon subtitles fetched');
        return;
      }

      // Get user's default subtitle language preference
      final defaultLang = await StorageService.getDefaultSubtitleLanguage();

      // If subtitles are explicitly disabled, don't auto-select
      if (defaultLang == 'off') {
        debugPrint('SubAuto: SKIP — subtitles set to off');
        return;
      }

      // If no preference set, default to English
      final targetLang = defaultLang ?? 'en';
      final availableLangs = subtitles.map((s) => s.lang).toSet();
      debugPrint(
        'SubAuto: matching targetLang=$targetLang (setting=$defaultLang) '
        'against ${subtitles.length} addon subs, langs=$availableLangs',
      );

      // Find matching subtitle by language
      StremioSubtitle? matchingSub;
      for (final sub in subtitles) {
        if (LanguageMapper.matchesLanguage(targetLang, sub.lang)) {
          matchingSub = sub;
          break;
        }
      }

      if (matchingSub == null) {
        debugPrint('SubAuto: NO MATCH — no $targetLang among $availableLangs');
        return;
      }

      debugPrint(
        'VideoPlayer: Auto-selecting addon subtitle: ${matchingSub.displayName} (${matchingSub.lang})',
      );

      // Download to a temp file so libmpv can detect the encoding itself.
      final filePath = await downloadStremioSubtitleToTempFile(matchingSub);

      // Check if content changed or user manually selected during download
      if (fetchToken != session.addonSubtitleFetchToken) {
        debugPrint(
          'VideoPlayer: Content changed during addon subtitle download, discarding',
        );
        return;
      }
      if (session.userManuallySelectedSubtitle) {
        debugPrint(
          'VideoPlayer: User manually selected subtitle during addon download, discarding',
        );
        return;
      }
      if (filePath == null) {
        debugPrint(
          'SubAuto: FAILED to download addon subtitle ${matchingSub.url}',
        );
        session.showSubtitleFailureMessage(
          'Couldn’t load the preferred subtitles. Choose another subtitle track.',
        );
        return;
      }

      final track = mk.SubtitleTrack.uri(
        filePath,
        title: matchingSub.displayName,
        language: matchingSub.lang,
      );
      final applied = await applyExternalSubtitleTrack(track);
      if (!applied) return;
      session.selectedStremioSubtitleId = matchingSub.id;
      session.setActiveExternalSubtitlePath(filePath);

      debugPrint(
        'SubAuto: APPLIED addon subtitle "${matchingSub.displayName}" lang=${matchingSub.lang} source=${matchingSub.source}',
      );
    } catch (e) {
      debugPrint('SubAuto: auto-select FAILED with exception: $e');
    }
  }

  Future<void> persistTrackChoice(String audio, String subtitle) async {
    final attempt = session.activeSubtitleApplyAttempt;
    Completer<void>? persistenceDone;
    if (attempt != null &&
        attempt.successReturned &&
        subtitlePreferenceMatchesAttempt(subtitle, attempt)) {
      attempt.persisted = true;
      attempt.persistedAudioId = audio;
      persistenceDone = Completer<void>();
      attempt.persistenceDone = persistenceDone;
    }
    try {
      final seriesPlaylist = session.seriesPlaylist;
      if (seriesPlaylist != null && seriesPlaylist.isSeries) {
        // For series content, save preferences for the entire series
        await PlaybackProgressStore.saveSeriesTrackPreferences(
          seriesTitle: seriesPlaylist.seriesTitle ?? 'Unknown Series',
          audioTrackId: audio,
          subtitleTrackId: subtitle,
        );
      } else {
        // For non-series content, save preferences for this specific video
        // Origin: widget.title.isNotEmpty (session.videoTitle).
        final videoTitle = session.videoTitle.isNotEmpty
            ? session.videoTitle
            : 'Unknown Video';
        await PlaybackProgressStore.saveVideoTrackPreferences(
          videoTitle: videoTitle,
          audioTrackId: audio,
          subtitleTrackId: subtitle,
        );
      }
    } catch (e) {
      // Track persistence is best-effort; playback selection still succeeds.
    } finally {
      if (persistenceDone != null && !persistenceDone.isCompleted) {
        persistenceDone.complete();
      }
    }
  }

  /// The old tracks-sheet `onTrackChanged` closure, verbatim: shared tail of
  /// every track selection made from the menu.
  Future<void> menuApplyTrackChange(String audioId, String subtitleId) async {
    session.userManuallySelectedSubtitle = true;
    if (!subtitleId.startsWith('stremio:')) {
      session.setActiveExternalSubtitlePath(null);
    }
    session.captureIptvAudioLanguage(audioId);
    await persistTrackChoice(audioId, subtitleId);
  }

  Future<void> menuSelectAudio(String audioId, String currentSubId) async {
    final track = session.player.state.tracks.audio
        .where((a) => a.id == audioId)
        .firstOrNull;
    if (track == null) return;
    await session.player.setAudioTrack(track);
    await menuApplyTrackChange(audioId, currentSubId);
  }

  Future<bool> menuSubtitlesOff(String audioId) async {
    final applied = await setSubtitleTrackWithDiagnostics(
      mk.SubtitleTrack.no(),
      source: 'player-menu-off',
    );
    if (!applied) return false;
    session.selectedStremioSubtitleId = null;
    await menuApplyTrackChange(audioId, 'no');
    return true;
  }

  Future<bool> menuSelectEmbeddedSubtitle(String subId, String audioId) async {
    final track = session.player.state.tracks.subtitle
        .where((s) => s.id == subId)
        .firstOrNull;
    if (track == null) {
      session.showSubtitleFailureMessage(
        'That subtitle track is no longer available. Try another track.',
      );
      return false;
    }
    final applied = await setSubtitleTrackWithDiagnostics(
      track,
      source: 'player-menu-embedded',
    );
    if (!applied) return false;
    session.selectedStremioSubtitleId = null;
    await menuApplyTrackChange(audioId, subId);
    return true;
  }

  /// Returns false when the download/apply failed — the panel keeps the
  /// previous selection (and its sync offset) in that case.
  Future<bool> menuSelectAddonSubtitle(
    StremioSubtitle sub,
    String audioId,
  ) async {
    // Playback continues behind the menu: if the content switches while the
    // download is in flight (auto-advance, zap), applying the stale subtitle
    // would attach it — and persist its ids — against the NEW item.
    final token = session.addonSubtitleFetchToken;
    try {
      final filePath = await downloadStremioSubtitleToTempFile(sub);
      if (filePath == null) {
        session.showSubtitleFailureMessage(
          'Couldn’t load subtitles. Check your connection or try another track.',
        );
        return false;
      }
      if (token != session.addonSubtitleFetchToken || !session.isMounted) {
        return false;
      }
      final track = mk.SubtitleTrack.uri(
        filePath,
        title: sub.displayName,
        language: sub.lang,
      );
      final applied = await applyExternalSubtitleTrack(track);
      if (!applied) return false;
      if (token != session.addonSubtitleFetchToken || !session.isMounted) return false;
      session.selectedStremioSubtitleId = sub.id;
      session.setActiveExternalSubtitlePath(filePath);
      await menuApplyTrackChange(audioId, 'stremio:${sub.id}');
      return true;
    } catch (e) {
      debugPrint('PlayerMenu: subtitle apply failed - $e');
      session.showSubtitleFailureMessage(
        'Couldn’t apply subtitles. Try another embedded or online track.',
      );
      return false;
    }
  }

  Future<bool> applyStremioSubtitleFromTracksSheet(StremioSubtitle sub) async {
    final token = session.addonSubtitleFetchToken;
    try {
      final filePath = await downloadStremioSubtitleToTempFile(sub);
      if (filePath == null) {
        session.showSubtitleFailureMessage(
          'Couldn’t load subtitles. Check your connection or try another track.',
        );
        return false;
      }
      if (token != session.addonSubtitleFetchToken || !session.isMounted) {
        return false;
      }
      final applied = await applyExternalSubtitleTrack(
        mk.SubtitleTrack.uri(
          filePath,
          title: sub.displayName,
          language: sub.lang,
        ),
      );
      if (!applied) return false;
      if (token != session.addonSubtitleFetchToken || !session.isMounted) return false;
      session.setActiveExternalSubtitlePath(filePath);
      return true;
    } catch (e) {
      debugPrint('TracksSheet: subtitle apply failed - $e');
      session.showSubtitleFailureMessage(
        'Couldn’t apply subtitles. Try another embedded or online track.',
      );
      return false;
    }
  }
}
