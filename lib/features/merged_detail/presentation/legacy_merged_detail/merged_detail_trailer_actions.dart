import 'dart:async';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_dependencies.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_focus_state.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_trailer_state.dart';
import 'package:debrify/models/ambient_trailer_surface.dart';
import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/models/playlist_view_mode.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/imdb_trailer_service.dart';
import 'package:debrify/services/metadata_preferences_service.dart';
import 'package:debrify/services/metadata_provider_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/storage/ambient_trailer_storage.dart';
import 'package:debrify/services/video_player_launcher.dart';
import 'package:debrify/services/youtube_service.dart';
import 'package:debrify/widgets/detail/detail_style.dart';
import 'package:flutter/material.dart';

class MergedDetailTrailerActions {
  final MergedDetailDependencies _deps;
  MergedDetailTrailerActions(this._deps);
  StremioMeta get _item => _deps.presentedItem();
  String get _style => _deps.style();
  bool get mounted => _deps.mounted();
  void Function(VoidCallback) get setState => _deps.setState;
  MergedDetailFocusState get _f => _deps.parts.focusState;
  MergedDetailTrailerState get _t => _deps.parts.trailerState;

  Future<String?> currentTrailerId() async {
    String? ytId = _deps.item().trailerYtId;
    if (ytId == null || ytId.isEmpty) {
      final enrich = _deps.metaEnricher();
      final imdbId = _deps.item().effectiveImdbId;
      if (enrich != null && imdbId != null) {
        try {
          final full = await enrich(imdbId, _deps.item().type);
          ytId = full?.trailerYtId;
        } catch (_) {}
      }
    }
    return ytId;
  }

  Future<void> loadTrailer() async {
    final generation = ++_t.trailerGeneration;
    final scope = ProfileRuntime.scope.value;
    final policyRevision = MetadataPreferencesService.revision.value;
    bool current() =>
        mounted &&
        generation == _t.trailerGeneration &&
        scope == ProfileRuntime.scope.value &&
        policyRevision == MetadataPreferencesService.revision.value;
    try {
      final prefs = await MetadataPreferencesService.loadForBackground(
        isCurrent: current,
      );
      if (prefs == null) return;
      final candidates = await MetadataProviderService.instance.trailers(
        _deps.item(),
        currentTrailerId,
        preferences: prefs,
      );
      if (!mounted || !current()) return;
      _t.trailerCandidates = candidates;
      _t.allowTrailerFallback =
          prefs.provider(MetadataCategory.trailers) ==
              MetadataPreferences.current ||
          prefs.fallback;
      final ytId = candidates.firstOrNull?.key;
      if (ytId == null || ytId.isEmpty || !current()) return;
      setState(() => _t.trailerYtId = ytId);

      // OTT autoplay: honour the setting, then pre-resolve the stream (also reused
      // by the Trailer button). Silent on failure — the poster simply stays.
      final autoplay =
          await AmbientTrailerStorage.getDetailTrailerAutoplayEnabled();
      // The ambient sound pair is shared with the TV hero (one live surface per
      // platform), so off-TV it governs this backdrop. Read unconditionally so
      // all three land in the one setState below — [autoplay] is false on TV
      // anyway, and these are two prefs reads.
      final soundOn = await AmbientTrailerStorage.getAmbientTrailerAudioEnabled(
        AmbientTrailerSurface.detail,
      );
      final volume = await AmbientTrailerStorage.getAmbientTrailerVolume(
        AmbientTrailerSurface.detail,
      );
      if (!mounted || !current()) return;
      // The backdrop refuses to autoplay under OS reduced-motion — skip the whole
      // pipeline (no resolve, no spinner) rather than spin forever waiting for a
      // player that will never start.
      final reduceMotion =
          MediaQuery.maybeOf(_deps.context())?.disableAnimations ?? false;
      final willAutoplay = autoplay && !reduceMotion;
      setState(() {
        _t.trailerAutoplayEnabled = autoplay;
        _t.trailerAmbientVolume = soundOn ? volume.toDouble() : 0;
        // Spinner from here until the backdrop reports first frames (or fails).
        _t.trailerResolving = willAutoplay;
      });
      if (!willAutoplay) return;
      YoutubeResolvedStreams? streams;
      try {
        streams = await YoutubeService.resolveStreams(ytId);
      } catch (_) {
        streams = null;
      }
      // Backup source: IMDb's own trailer MP4s, for when YouTube resolution is
      // blocked (regional client kills) — the backdrop still gets to move.
      if (_t.allowTrailerFallback &&
          (streams == null || !(streams.playUrl?.isNotEmpty ?? false))) {
        final imdbId = _item.effectiveImdbId;
        if (imdbId != null) {
          streams = await ImdbTrailerService.resolveTrailer(imdbId);
        }
      }
      if (!mounted || !current()) return;
      final playable = streams?.playUrl?.isNotEmpty ?? false;
      setState(() {
        _t.trailerStreams = streams;
        // No playable stream → the backdrop never starts, so stop the spinner
        // here; on success the backdrop's onPlayingChanged(true) clears it once
        // frames actually flow.
        if (!playable) _t.trailerResolving = false;
      });
      if (!playable) return;
      // Safety net: a stream that opens but never renders a first frame would
      // otherwise leave the spinner up forever.
      Future.delayed(const Duration(seconds: 25), () {
        if (current() && _t.trailerResolving) {
          setState(() => _t.trailerResolving = false);
        }
      });
    } catch (_) {
      if (current()) {
        setState(() {
          _t.trailerResolving = false;
          _t.trailerLoading = false;
        });
      }
    }
  }

  void exitTrailerForeground() {
    if (!_t.trailerForeground) return;
    setState(() => _t.trailerForeground = false);
    // TV: the page content was focus-excluded while the trailer was fullscreen,
    // so nothing holds focus now — re-anchor the remote on the primary action.
    if (_deps.isTelevision()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // The left-entry node only has a holder when Play or the source pill is
        // present; if neither is (edge config), fall back to traversal so the
        // remote isn't stranded rather than no-op on an unattached node.
        if (detailNodeMounted(_f.leftEntryFocusNode)) {
          _f.leftEntryFocusNode.requestFocus();
        } else {
          FocusScope.of(_deps.context()).nextFocus();
        }
      });
    }
  }

  /// Trailer button. Seamless path: if the ambient backdrop trailer is already
  /// playing, bring that *same* player forward (unmute + controls) in place — no
  /// second decoder, no re-buffer. Fallback path (autoplay off / not resolved /
  /// reduced motion): resolve fresh and launch the standalone player as before.
  Future<void> playTrailer() async {
    if (_t.trailerLoading) return;
    final generation = _t.trailerGeneration;
    final scope = ProfileRuntime.scope.value;
    final revision = MetadataPreferencesService.revision.value;
    String? chosen;
    if (_t.trailerCandidates.length > 1) {
      chosen = await showDialog<String>(
        context: _deps.context(),
        builder: (context) => SimpleDialog(
          title: const Text('Choose trailer'),
          children: [
            for (final video in _t.trailerCandidates)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, video.key),
                child: Text(
                  '${video.title}${video.language.isEmpty ? '' : ' · ${video.language}'}',
                ),
              ),
          ],
        ),
      );
      if (!mounted ||
          chosen == null ||
          generation != _t.trailerGeneration ||
          scope != ProfileRuntime.scope.value ||
          revision != MetadataPreferencesService.revision.value) {
        return;
      }
    }
    await playSelectedTrailer(chosen);
  }

  Future<void> playSelectedTrailer(String? chosen) async {
    final generation = _t.trailerGeneration;
    final scope = ProfileRuntime.scope.value;
    bool current() =>
        mounted &&
        generation == _t.trailerGeneration &&
        scope == ProfileRuntime.scope.value;
    if ((chosen == null || chosen == _t.trailerYtId) &&
        (_t.backdropKey.currentState?.canPromote ?? false)) {
      setState(() => _t.trailerForeground = true);
      return;
    }

    final ytId = chosen ?? _t.trailerYtId;
    if (ytId == null || _t.trailerLoading) return;

    // Always resolve fresh on tap. The autoplay-prefetched [_trailerStreams] is
    // deliberately NOT reused here: googlevideo URLs carry an `expire` param and
    // go dead after a few hours, so a page left open would hand the player a
    // stale URL. Re-resolving costs one request and keeps playback reliable.
    setState(() => _t.trailerLoading = true);
    if (mounted) {
      ScaffoldMessenger.of(_deps.context()).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Text('Loading trailer…'),
            ],
          ),
          duration: Duration(seconds: 4),
        ),
      );
    }

    YoutubeResolvedStreams? streams;
    try {
      streams = await YoutubeService.resolveStreams(ytId);
    } catch (_) {
      streams = null;
    }
    // Same backup as the ambient path: a blocked YouTube must not reduce the
    // Trailer button to a "Couldn't load trailer" snackbar when IMDb hosts
    // the same trailer as a plain MP4.
    if (_t.allowTrailerFallback &&
        (streams == null || !(streams.playUrl?.isNotEmpty ?? false))) {
      final imdbId = _item.effectiveImdbId;
      if (imdbId != null) {
        streams = await ImdbTrailerService.resolveTrailer(imdbId);
      }
    }

    if (!mounted || !current()) return;
    ScaffoldMessenger.of(_deps.context()).hideCurrentSnackBar();
    setState(() => _t.trailerLoading = false);

    final playUrl = streams?.playUrl;
    if (playUrl == null || playUrl.isEmpty) {
      ScaffoldMessenger.of(
        _deps.context(),
      ).showSnackBar(const SnackBar(content: Text('Couldn\'t load trailer')));
      return;
    }

    await VideoPlayerLauncher.push(
      _deps.context(),
      VideoPlayerLaunchArgs(
        videoUrl: playUrl,
        audioUrl: streams?.audioUrl,
        fallbackUrl: streams?.muxedPlaybackFallback,
        title: '${_item.name} — Trailer',
        viewMode: PlaylistViewMode.sorted,
      ),
      // Watching the trailer must not suppress the ambient trailer backdrop.
      isTrailer: true,
    );
  }

  /// The reference plays its detail-page preview CRYSTAL CLEAR — no wash, no
  /// glow, no blur. True while the Showcase ambient trailer is actually
  /// rolling off-TV with the page at its hero; every shell-level veil over
  /// the video gates on this. TV is untouched (its washes were tuned on the
  /// panel and nobody has complained at ten feet).
  bool get trailerClearView =>
      _style == 'showcase' &&
      !_deps.isTelevision() &&
      _t.trailerAmbientPlaying &&
      !_f.bodyDeep;
}
