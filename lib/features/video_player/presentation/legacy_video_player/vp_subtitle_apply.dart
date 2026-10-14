import 'package:debrify/features/video_player/application/vp_subtitle_identity.dart';
import 'package:debrify/features/video_player/models/vp_subtitle_apply_attempt.dart';
import 'package:debrify/models/android_video_renderer_mode.dart';
import 'package:debrify/screens/video_player/services/subtitle_track_utils.dart';
import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' as mk;

abstract interface class VpSubtitleApplyHost {
  bool get mounted;
  BuildContext get context;
  void setState(VoidCallback fn);
  mk.Player get player;
  int get addonSubtitleFetchToken;
  bool get isIOS;
  bool get isAndroid;
  bool get isPipActive;
  bool get iosPipStarting;
  AndroidVideoRendererMode get androidVideoRendererMode;
  String? get selectedStremioSubtitleId;
  set selectedStremioSubtitleId(String? v);
  String? get activeExternalSubtitlePath;
  ValueNotifier<String?> get subtitleSelectionCorrection;
  GlobalKey<PlayerMenuPanelState> get playerMenuKey;
  void setActiveExternalSubtitlePath(String? path);
  Future<void> persistTrackChoice(String audio, String subtitle);
  int get subtitleDiagnosticGeneration;
  set subtitleDiagnosticGeneration(int v);
  VpSubtitleApplyAttempt? get activeSubtitleApplyAttempt;
  set activeSubtitleApplyAttempt(VpSubtitleApplyAttempt? v);
}

class VpSubtitleApply {
  VpSubtitleApply(this._host);
  final VpSubtitleApplyHost _host;

  // Wait for subtitle tracks to be parsed from the media file
  // media_kit initially only has 'auto' and 'no' tracks, real tracks come later
  Future<void> waitForSubtitleTracks({required int token}) async {
    // Wait up to 5 seconds for subtitle tracks to be available
    for (int i = 0; i < 50; i++) {
      if (token != _host.addonSubtitleFetchToken) return;
      final tracks = _host.player.state.tracks.subtitle;
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

  Future<void> setNativeSubtitleVisibilityForTrack(
    mk.SubtitleTrack track,
  ) async {
    final platform = _host.player.platform;
    if (platform is! mk.NativePlayer) return;
    final nativeRendering =
        requiresNativeSubtitleRendering(track) ||
        (_host.isIOS && (_host.isPipActive || _host.iosPipStarting));
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
    bool Function()? isCurrent,
  }) async {
    if (isCurrent != null && !isCurrent()) return false;
    if (_host.isAndroid &&
        !PlatformUtil.isAndroidTvCached &&
        requiresNativeSubtitleRendering(track) &&
        _host.androidVideoRendererMode !=
            AndroidVideoRendererMode.directMediaCodec) {
      showSubtitleFailureMessage(
        'Bitmap subtitles require MediaCodec + GPU. Change Video renderer in Settings and restart playback.',
      );
      debugPrint(
        '[SubtitleDiag] apply rejected source=$source '
        'reason=android_renderer_incompatible',
      );
      return false;
    }
    final diagnosticGeneration = ++_host.subtitleDiagnosticGeneration;
    final attempt = VpSubtitleApplyAttempt(
      generation: diagnosticGeneration,
      requested: track,
      previous: _host.player.state.track.subtitle,
      source: source,
      previousStremioId: _host.selectedStremioSubtitleId,
      previousExternalPath: _host.activeExternalSubtitlePath,
    );
    _host.activeSubtitleApplyAttempt = attempt;
    // Null arms the next correction even when two failures restore the same
    // selection consecutively.
    _host.subtitleSelectionCorrection.value = null;

    try {
      await setNativeSubtitleVisibilityForTrack(track);
      if (isCurrent != null && !isCurrent()) return false;
      await _host.player.setSubtitleTrack(track);
    } catch (error, stackTrace) {
      debugPrint(
        '[SubtitleDiag] set FAILED source=$source '
        'requestedId=${vpDiagnosticSubtitleId(track)} '
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
    VpSubtitleApplyAttempt attempt,
    String reason,
  ) async {
    if (attempt.handled ||
        _host.activeSubtitleApplyAttempt != attempt ||
        attempt.generation != _host.subtitleDiagnosticGeneration) {
      return;
    }
    attempt.failed = true;
    attempt.handled = true;
    _host.activeSubtitleApplyAttempt = null;

    final previous = attempt.previous;
    final sameTrack = previous.id == attempt.requested.id;
    final fallback = previous.id == 'auto' || sameTrack
        ? mk.SubtitleTrack.no()
        : previous;
    var restoredOriginalSelection = fallback.id == previous.id;
    try {
      await setNativeSubtitleVisibilityForTrack(fallback);
      await _host.player.setSubtitleTrack(fallback);
    } catch (error) {
      restoredOriginalSelection = false;
      debugPrint(
        '[SubtitleDiag] rollback FAILED source=${attempt.source} error=$error',
      );
      try {
        final noTrack = mk.SubtitleTrack.no();
        await setNativeSubtitleVisibilityForTrack(noTrack);
        await _host.player.setSubtitleTrack(noTrack);
      } catch (_) {
        // The original actionable error is surfaced below. A second snackbar
        // for rollback failure would obscure it without giving the user a
        // useful recovery action.
      }
    }

    _host.selectedStremioSubtitleId = restoredOriginalSelection
        ? attempt.previousStremioId
        : null;
    _host.setActiveExternalSubtitlePath(
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
      await _host.persistTrackChoice(
        attempt.persistedAudioId ?? _host.player.state.track.audio.id,
        restoredSelection,
      );
    }
    if (!_host.mounted) return;
    _host.setState(() {});
    _host.playerMenuKey.currentState?.reconcileSubtitleSelection(
      restoredSelection,
    );
    _host.subtitleSelectionCorrection.value = restoredSelection;

    final codec = attempt.requested.codec;
    final message = codec == null || codec.isEmpty
        ? 'Couldn’t apply subtitles. Try another embedded or online track.'
        : 'Couldn’t decode $codec subtitles. Try another embedded or online track.';
    showSubtitleFailureMessage(message);
    debugPrint(
      '[SubtitleDiag] user notified source=${attempt.source} reason=$reason',
    );
  }

  void showSubtitleFailureMessage(String message) {
    if (!_host.mounted) return;
    final messenger = ScaffoldMessenger.of(_host.context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }
}
