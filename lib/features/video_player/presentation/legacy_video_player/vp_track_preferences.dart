import 'dart:async';
import 'package:debrify/features/video_player/application/vp_subtitle_identity.dart';
import 'package:debrify/features/video_player/models/vp_subtitle_apply_attempt.dart';
import 'package:debrify/models/series_playlist.dart';
import 'package:debrify/services/storage/track_preferences_storage.dart';
import 'package:debrify/services/storage/subtitle_settings_storage.dart';
import 'package:debrify/screens/video_player/services/subtitle_track_utils.dart';
import 'package:debrify/screens/video_player/utils/language_mapping.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' as mk;

abstract interface class VpTrackPreferencesHost {
  VpSubtitleApplyAttempt? get activeSubtitleApplyAttempt;
  int get addonSubtitleFetchToken;
  Future<void> applyDefaultAudioLanguage();
  Future<bool> applyDefaultSubtitleLanguage({
    bool ignoreSourcePriority = false,
  });
  Future<void> applyIptvAudioPreference(int ticket);
  set embeddedSubtitleApplied(bool v);
  Future<void> fetchAndMaybeAutoSelectAddonSubtitle();
  bool get hasSubtitlePolicy;
  int get iptvSwitchTicket;
  bool get isIptvSeriesContext;
  mk.Player get player;
  Future<void> refreshSubtitleAudioPolicy({bool reselect = true});
  SeriesPlaylist? get seriesPlaylist;
  set trackPreferencesReadyForAddonSubtitles(bool v);
  set userManuallySelectedSubtitle(bool v);
  String get title;
  Future<void> waitForSubtitleTracks({required int token});
  Future<bool> setSubtitleTrackWithDiagnostics(
    mk.SubtitleTrack track, {
    required String source,
    bool Function()? isCurrent,
  });
}

class VpTrackPreferences {
  VpTrackPreferences(this._host);
  final VpTrackPreferencesHost _host;

  /// Restore audio and subtitle track preferences
  Future<void> restoreTrackPreferences() async {
    // Capture token to detect if content changes during async operations
    final restoreToken = _host.addonSubtitleFetchToken;

    try {
      debugPrint(
        'SubAuto: _restoreTrackPreferences entered (token=$restoreToken)',
      );
      // Wait for subtitle tracks to be parsed from the media file
      // media_kit initially only has 'auto' and 'no' placeholder tracks
      await _host.waitForSubtitleTracks(token: restoreToken);

      if (restoreToken != _host.addonSubtitleFetchToken) {
        debugPrint(
          'SubAuto: restore aborted after track wait (content changed)',
        );
        return;
      }

      final seriesPlaylist = _host.seriesPlaylist;
      Map<String, dynamic>? trackPreferences;

      if (seriesPlaylist != null && seriesPlaylist.isSeries) {
        // For series content, get preferences for the entire series
        trackPreferences =
            await TrackPreferencesStorage.getSeriesTrackPreferences(
              seriesTitle: seriesPlaylist.seriesTitle ?? 'Unknown Series',
            );
      } else {
        // For non-series content, get preferences for this specific video
        final videoTitle = _host.title.isNotEmpty
            ? _host.title
            : 'Unknown Video';
        trackPreferences =
            await TrackPreferencesStorage.getVideoTrackPreferences(
              videoTitle: videoTitle,
            );
      }

      // Bail out if content changed during preferences fetch
      if (restoreToken != _host.addonSubtitleFetchToken) {
        debugPrint(
          'SubAuto: restore aborted (content changed during prefs fetch)',
        );
        return;
      }

      final subTracksNow = _host.player.state.tracks.subtitle
          .map((t) => '${t.id}/${t.language}/${t.title}')
          .toList();
      debugPrint(
        'SubAuto: restore start — prefs=${trackPreferences == null ? 'NONE' : trackPreferences.toString()} '
        'subtitleTracks=$subTracksNow currentSub=${_host.player.state.track.subtitle.id}',
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
          final audioTrack = _host.player.state.tracks.audio
              .where((track) => track.id == audioTrackId)
              .firstOrNull;
          if (audioTrack != null) {
            await _host.player.setAudioTrack(audioTrack);
          } else {
            await _host.applyDefaultAudioLanguage();
          }
        } else {
          // No stored audio preference - apply default audio language setting
          await _host.applyDefaultAudioLanguage();
        }

        if (_host.isIptvSeriesContext) {
          await _host.applyIptvAudioPreference(_host.iptvSwitchTicket);
        }
        await _host.refreshSubtitleAudioPolicy(reselect: false);

        // Bail out if content changed during audio track application
        if (restoreToken != _host.addonSubtitleFetchToken) return;

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
          final tracks = _host.player.state.tracks;
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
                await SubtitleSettingsStorage.getDefaultSubtitleLanguage();
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
              subtitleApplied = await _host.applyDefaultSubtitleLanguage();
            } else {
              debugPrint(
                'SubAuto: applying STORED subtitle track id=$subtitleTrackId '
                '(lang=${subtitleTrack.language}/${subtitleTrack.title}) — blocks addon auto-select',
              );
              subtitleApplied = await _host.setSubtitleTrackWithDiagnostics(
                subtitleTrack,
                source: 'restore-stored-embedded',
              );
              if (_host.hasSubtitlePolicy && subtitleApplied) {
                _host.userManuallySelectedSubtitle = true;
              }
            }
          } else {
            // Stored track doesn't exist in this video - fall through to default
            debugPrint(
              'SubAuto: stored subtitle id=$subtitleTrackId not in this file → default-language path',
            );
            subtitleApplied = await _host.applyDefaultSubtitleLanguage();
          }
        } else {
          // No stored subtitle preference - apply default subtitle language setting
          debugPrint(
            'SubAuto: stored subtitle id=$subtitleTrackId treated as no-choice → default-language path',
          );
          subtitleApplied = await _host.applyDefaultSubtitleLanguage();
        }
      } else {
        // No track preferences at all - apply default language settings
        debugPrint('SubAuto: no stored prefs → default-language path');
        await _host.applyDefaultAudioLanguage();
        if (_host.isIptvSeriesContext) {
          await _host.applyIptvAudioPreference(_host.iptvSwitchTicket);
        }
        await _host.refreshSubtitleAudioPolicy(reselect: false);
        subtitleApplied = await _host.applyDefaultSubtitleLanguage();
      }

      // Final check before applying state
      if (restoreToken != _host.addonSubtitleFetchToken) {
        debugPrint('SubAuto: restore aborted post-apply (content changed)');
        return;
      }

      // Track if embedded subtitle was applied for addon fallback
      _host.embeddedSubtitleApplied = subtitleApplied;
      _host.trackPreferencesReadyForAddonSubtitles = true;
      await _host.refreshSubtitleAudioPolicy();
      debugPrint(
        'SubAuto: restore done — embeddedSubtitleApplied=$subtitleApplied → running addon auto-select',
      );

      // Always fetch Stremio addon subtitles proactively (like Android TV)
      // Auto-selection will only happen if no embedded subtitle was applied
      _host.fetchAndMaybeAutoSelectAddonSubtitle();
    } catch (e) {
      debugPrint('SubAuto: restore FAILED with exception: $e');
    }
  }

  Future<void> persistTrackChoice(String audio, String subtitle) async {
    final attempt = _host.activeSubtitleApplyAttempt;
    Completer<void>? persistenceDone;
    if (attempt != null &&
        attempt.successReturned &&
        vpSubtitlePreferenceMatchesAttempt(subtitle, attempt)) {
      attempt.persisted = true;
      attempt.persistedAudioId = audio;
      persistenceDone = Completer<void>();
      attempt.persistenceDone = persistenceDone;
    }
    try {
      final seriesPlaylist = _host.seriesPlaylist;
      if (seriesPlaylist != null && seriesPlaylist.isSeries) {
        // For series content, save preferences for the entire series
        await TrackPreferencesStorage.saveSeriesTrackPreferences(
          seriesTitle: seriesPlaylist.seriesTitle ?? 'Unknown Series',
          audioTrackId: audio,
          subtitleTrackId: subtitle,
        );
      } else {
        // For non-series content, save preferences for this specific video
        final videoTitle = _host.title.isNotEmpty
            ? _host.title
            : 'Unknown Video';
        await TrackPreferencesStorage.saveVideoTrackPreferences(
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
}
