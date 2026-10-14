import 'package:debrify/models/stremio_subtitle.dart';
import 'package:debrify/models/subtitle_source_priority.dart';
import 'package:debrify/screens/video_player/services/subtitle_track_utils.dart';
import 'package:debrify/screens/video_player/utils/language_mapping.dart';
import 'package:debrify/screens/video_player/utils/subtitle_audio_policy.dart';
import 'package:debrify/services/storage/subtitle_settings_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' as mk;

abstract interface class VpSubtitleLanguagePolicyHost {
  bool get mounted;
  int get addonSubtitleFetchToken;
  Future<void> applySubtitleSourcePriority(
    List<AddonSubtitleSlot> slots,
    int token, {
    bool discoveryReady = true,
  });
  List<AddonSubtitleSlot>? get cachedAddonSlots;
  set embeddedSubtitleApplied(bool v);
  bool get hasSubtitlePolicy;
  mk.Player get player;
  set selectedStremioSubtitleId(String? v);
  int get subtitleAudioRevision;
  set subtitleAudioRevision(int v);
  bool get subtitleForcedOnly;
  bool get subtitleOnlyForeignAudio;
  String? get subtitlePreferredAudio;
  String? get subtitleSelectedAudio;
  set subtitleSelectedAudio(String? v);
  bool get trackPreferencesReadyForAddonSubtitles;
  bool get userManuallySelectedSubtitle;
  void setActiveExternalSubtitlePath(String? path);
  Future<bool> setSubtitleTrackWithDiagnostics(
    mk.SubtitleTrack track, {
    required String source,
    bool Function()? isCurrent,
  });
}

class VpSubtitleLanguagePolicy {
  VpSubtitleLanguagePolicy(this._host);
  final VpSubtitleLanguagePolicyHost _host;

  /// Apply default audio language from settings (when no stored preference exists)
  Future<void> applyDefaultAudioLanguage() async {
    try {
      final defaultLang =
          await SubtitleSettingsStorage.getDefaultAudioLanguage();
      if (defaultLang == null) {
        // No preference set - do nothing, let player use its default
        return;
      }

      final tracks = _host.player.state.tracks;
      if (tracks.audio.isEmpty) return;

      // If mpv's own selection (via the `alang` set at configure time)
      // already matches the preference, keep it: mpv's matcher weighs the
      // default/forced dispositions, so on a file with a normal and a
      // commentary track in the same language it lands on the right one —
      // the first-match loop below would overwrite that with whichever
      // matching track enumerates first.
      final platform = _host.player.platform;
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
        await _host.player.setAudioTrack(matchingTrack);
      }
    } catch (e) {
      // Silently fail - audio preference is non-critical
    }
  }

  bool get audioAllowsAutomaticSubtitles =>
      _host.subtitleForcedOnly ||
      allowsAutomaticSubtitles(
        onlyForeignAudio: _host.subtitleOnlyForeignAudio,
        preferredAudio: _host.subtitlePreferredAudio,
        selectedAudio: _host.subtitleSelectedAudio,
      );

  Future<void> refreshSubtitleAudioPolicy({bool reselect = true}) async {
    if (!_host.hasSubtitlePolicy || _host.userManuallySelectedSubtitle) return;
    if (_host.subtitleForcedOnly) {
      if (reselect && _host.trackPreferencesReadyForAddonSubtitles) {
        await _host.applySubtitleSourcePriority(
          const [],
          _host.addonSubtitleFetchToken,
        );
      }
      return;
    }
    final revision = ++_host.subtitleAudioRevision;
    final token = _host.addonSubtitleFetchToken;
    _host.subtitleSelectedAudio = null;
    final audio = _host.player.state.track.audio;
    String? language =
        LanguageMapper.canonicalLanguage(audio.language) ??
        LanguageMapper.canonicalLanguage(audio.title);
    final platform = _host.player.platform;
    if (platform is mk.NativePlayer) {
      try {
        // Dart may still expose the 'auto' placeholder at startup.
        final tag = await platform.getProperty('current-tracks/audio/lang');
        language = LanguageMapper.canonicalLanguage(tag) ?? language;
      } catch (_) {
        // Retain recognized track metadata if the native property is unavailable.
      }
    }
    bool current() =>
        _host.mounted &&
        token == _host.addonSubtitleFetchToken &&
        revision == _host.subtitleAudioRevision &&
        !_host.userManuallySelectedSubtitle;
    if (!current()) return;
    _host.subtitleSelectedAudio = language;
    if (!reselect || !_host.trackPreferencesReadyForAddonSubtitles) return;
    if (!audioAllowsAutomaticSubtitles) {
      _host.embeddedSubtitleApplied = false;
      _host.selectedStremioSubtitleId = null;
      _host.setActiveExternalSubtitlePath(null);
      await _host.setSubtitleTrackWithDiagnostics(
        mk.SubtitleTrack.no(),
        source: 'audio-language-off',
        isCurrent: current,
      );
    }
    if (!current()) return;
    await _host.applySubtitleSourcePriority(
      _host.cachedAddonSlots ?? const [],
      token,
      discoveryReady: _host.cachedAddonSlots != null,
    );
  }

  /// Apply default subtitle language from settings (when no stored preference exists)
  /// Returns true if an embedded subtitle was found and applied, false otherwise.
  Future<bool> applyDefaultSubtitleLanguage({
    bool ignoreSourcePriority = false,
  }) async {
    final token = _host.addonSubtitleFetchToken;
    final audioRevision = _host.subtitleAudioRevision;
    bool current() =>
        _host.mounted &&
        token == _host.addonSubtitleFetchToken &&
        audioRevision == _host.subtitleAudioRevision &&
        !_host.userManuallySelectedSubtitle;
    try {
      if (!audioAllowsAutomaticSubtitles) {
        await _host.setSubtitleTrackWithDiagnostics(
          mk.SubtitleTrack.no(),
          source: 'audio-language-default-off',
          isCurrent: current,
        );
        return false;
      }
      final defaultLang =
          await SubtitleSettingsStorage.getDefaultSubtitleLanguage();
      debugPrint('SubAuto: defaultSubtitleLanguage setting = $defaultLang');
      if (!current()) {
        return false;
      }
      if (_host.subtitleForcedOnly) {
        return applyForcedSubtitle(defaultLang, current);
      }
      if (!ignoreSourcePriority && defaultLang != 'off') {
        final order = await SubtitleSettingsStorage.getSubtitleSourcePriority();
        if (!current()) {
          return false;
        }
        if (order.first != SubtitleSourcePriority.embedded) return false;
      }
      if (defaultLang == null) {
        var selectedId = _host.player.state.track.subtitle.id;
        final platform = _host.player.platform;
        if (platform is mk.NativePlayer) {
          try {
            // Dart may still report "auto" while mpv has selected a real sid.
            selectedId = await platform.getProperty('sid');
          } catch (_) {
            // Fall back to media_kit's reported selection.
          }
        }
        if (!current()) {
          return false;
        }
        final track = subtitleWithoutLanguagePreference(
          _host.player.state.tracks.subtitle,
          selectedId: selectedId,
        );
        if (track == null) return false;
        return _host.setSubtitleTrackWithDiagnostics(
          track,
          source: 'no-preference-embedded',
          isCurrent: current,
        );
      }

      final tracks = _host.player.state.tracks;

      if (defaultLang == 'off') {
        // Explicitly disable subtitles
        final applied = await _host.setSubtitleTrackWithDiagnostics(
          mk.SubtitleTrack.no(),
          source: 'default-language-off',
          isCurrent: current,
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
        return _host.setSubtitleTrackWithDiagnostics(
          matchingTrack,
          source: 'default-language-embedded',
          isCurrent: current,
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

  Future<bool> applyForcedSubtitle(
    String? language,
    bool Function() current,
  ) async {
    String? id;
    final platform = _host.player.platform;
    try {
      if (platform is mk.NativePlayer) {
        id = await findForcedSubtitleId(
          readProperty: platform.getProperty,
          preferredSubtitle: language,
          isCurrent: current,
        );
      }
    } catch (error) {
      debugPrint('SubAuto: forced-track metadata unavailable: $error');
    }
    if (!current()) return false;
    final track = _host.player.state.tracks.subtitle
        .where(
          (track) => track.id == id && !isAppManagedAddonSubtitleTrack(track),
        )
        .firstOrNull;
    // A missing or unmarked track must never fall back to full subtitles.
    return _host.setSubtitleTrackWithDiagnostics(
      track ?? mk.SubtitleTrack.no(),
      source: track == null ? 'forced-only-off' : 'forced-only-embedded',
      isCurrent: current,
    );
  }
}
