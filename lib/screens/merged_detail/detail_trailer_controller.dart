import 'package:flutter/material.dart';

import '../../models/playlist_view_mode.dart';
import '../../models/stremio_addon.dart';
import '../../services/imdb_trailer_service.dart';
import '../../services/storage/ambient_trailer_prefs.dart'
    show AmbientTrailerPrefs, AmbientTrailerSurface;
import '../../services/storage_service.dart';
import '../../services/video_player_launcher.dart';
import '../../services/youtube_service.dart';
import '../../widgets/detail/detail_style.dart';
import '../../widgets/hero_trailer_backdrop.dart';

/// Everything the trailer lifecycle reads off its host, re-read on every access
/// so an enriched title or a rebuilt host is seen exactly as the State's own
/// `widget.`/`_item` reads used to see it.
class DetailTrailerInputs {
  const DetailTrailerInputs({
    required this.routeItem,
    required this.item,
    required this.isTelevision,
    required this.leftEntryFocusNode,
    this.metaEnricher,
  });

  /// The item the route was opened with. The trailer id and the enrichment
  /// lookup deliberately read this rather than the enriched copy.
  final StremioMeta routeItem;

  /// The live item — enriched when enrichment has landed.
  final StremioMeta item;

  final bool isTelevision;

  /// The stable LEFT-crossing target, re-anchored when a fullscreen trailer
  /// closes on TV.
  final FocusNode leftEntryFocusNode;

  final Future<StremioMeta?> Function(String imdbId, String type)? metaEnricher;
}

/// The merged detail page's trailer lifecycle: resolving the YouTube id, the
/// OTT ambient-autoplay pipeline behind the backdrop, promoting that same
/// player to fullscreen, and the standalone fallback launch.
///
/// A [ChangeNotifier] rather than a widget because the state is read from three
/// places at once (the backdrop, the Trailer ghost button, and the "Trailer
/// playing" chip); the host listens once and rebuilds, exactly as its
/// `setState` calls used to.
class DetailTrailerController extends ChangeNotifier {
  DetailTrailerController({required this.read});

  /// Live view of the host's configuration. Called at every use rather than
  /// captured, so it behaves like the `widget.…` reads it replaces.
  final DetailTrailerInputs Function() read;

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Trailer YouTube ID, resolved from Cinemeta meta. Null until loaded / when
  /// the title has no trailer — the Trailer button only shows once this is set.
  String? _ytId;
  String? get ytId => _ytId;

  /// Guards against a double-launch while a trailer's streams resolve.
  bool _loading = false;
  bool get loading => _loading;

  /// Whether OTT-style trailer autoplay behind the backdrop is on (settings).
  /// Always false on Android TV — the Home hero owns ambient trailers there.
  bool _autoplayEnabled = false;
  bool get autoplayEnabled => _autoplayEnabled;

  /// Ambient loop volume (0–100) from settings; 0 when the sound toggle is off.
  /// Read alongside [autoplayEnabled] and applied when the backdrop opens its
  /// engine (which can't happen before the streams resolve), so it's always in
  /// place by then. Promoting to fullscreen still plays at full volume — the
  /// backdrop handles that, muted ambient or not.
  double _ambientVolume = 70;
  double get ambientVolume => _ambientVolume;

  /// Resolved trailer streams, pre-fetched for the ambient backdrop.
  YoutubeResolvedStreams? _streams;
  YoutubeResolvedStreams? get streams => _streams;

  /// Handle to the backdrop so the Trailer button can promote the *same* player
  /// to fullscreen in place (seamless — no second decoder, no re-buffer).
  final GlobalKey<HeroTrailerBackdropState> backdropKey = GlobalKey();

  /// Whether the trailer is currently brought forward to fullscreen.
  bool _foreground = false;
  bool get foreground => _foreground;

  /// The ambient backdrop trailer is live with frames on screen — the Trailer
  /// button reads "Watch Trailer" to say "it's playing, tap to view".
  bool _ambientPlaying = false;
  bool get ambientPlaying => _ambientPlaying;

  /// Autoplay pipeline in flight (stream resolve → buffer → first frame) — the
  /// Trailer button shows a spinner.
  bool _resolving = false;
  bool get resolving => _resolving;

  /// The backdrop's own report. First frames clear the spinner; a stop clears
  /// the "Watch Trailer" affordance.
  void setAmbientPlaying(bool playing) {
    if (_disposed) return;
    _ambientPlaying = playing;
    _resolving = false;
    notifyListeners();
  }

  /// Resolve the trailer's YouTube ID from Cinemeta. Runs independently of the
  /// host's meta enrichment (which short-circuits for already-rich items and so
  /// can't be relied on to carry the trailer). The `fetchMetaDetails` result is
  /// cached in `StremioService`, so this shares that fetch rather than doubling
  /// network. Silent on failure — the button simply never appears.
  Future<void> load(BuildContext context) async {
    // Resolve the trailer id: prefer what the item arrived with, else ask the
    // metadata addon (Cinemeta).
    final inputs = read();
    String? ytId = inputs.routeItem.trailerYtId;
    if (ytId == null || ytId.isEmpty) {
      final enrich = inputs.metaEnricher;
      final imdbId = inputs.routeItem.effectiveImdbId;
      if (enrich != null && imdbId != null) {
        try {
          final full = await enrich(imdbId, inputs.routeItem.type);
          ytId = full?.trailerYtId;
        } catch (_) {}
      }
    }
    if (ytId == null || ytId.isEmpty || _disposed) return;
    _ytId = ytId;
    notifyListeners();

    // OTT autoplay: honour the setting, then pre-resolve the stream (also reused
    // by the Trailer button). Silent on failure — the poster simply stays.
    final autoplay = await StorageService.getDetailTrailerAutoplayEnabled();
    // The ambient sound pair is shared with the TV hero (one live surface per
    // platform), so off-TV it governs this backdrop. Read unconditionally so
    // all three land in the one notification below — [autoplay] is false on TV
    // anyway, and these are two prefs reads.
    final soundOn = await AmbientTrailerPrefs.getAmbientTrailerAudioEnabled(
      AmbientTrailerSurface.detail,
    );
    final volume = await AmbientTrailerPrefs.getAmbientTrailerVolume(
      AmbientTrailerSurface.detail,
    );
    if (_disposed || !context.mounted) return;
    // The backdrop refuses to autoplay under OS reduced-motion — skip the whole
    // pipeline (no resolve, no spinner) rather than spin forever waiting for a
    // player that will never start.
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final willAutoplay = autoplay && !reduceMotion;
    _autoplayEnabled = autoplay;
    _ambientVolume = soundOn ? volume.toDouble() : 0;
    // Spinner from here until the backdrop reports first frames (or fails).
    _resolving = willAutoplay;
    notifyListeners();
    if (!willAutoplay) return;
    YoutubeResolvedStreams? streams;
    try {
      streams = await YoutubeService.resolveStreams(ytId);
    } catch (_) {
      streams = null;
    }
    // Backup source: IMDb's own trailer MP4s, for when YouTube resolution is
    // blocked (regional client kills) — the backdrop still gets to move.
    if (streams == null || !(streams.playUrl?.isNotEmpty ?? false)) {
      final imdbId = read().item.effectiveImdbId;
      if (imdbId != null) {
        streams = await ImdbTrailerService.resolveTrailer(imdbId);
      }
    }
    if (_disposed) return;
    final playable = streams?.playUrl?.isNotEmpty ?? false;
    _streams = streams;
    // No playable stream → the backdrop never starts, so stop the spinner
    // here; on success the backdrop's onPlayingChanged(true) clears it once
    // frames actually flow.
    if (!playable) _resolving = false;
    notifyListeners();
    if (!playable) return;
    // Safety net: a stream that opens but never renders a first frame would
    // otherwise leave the spinner up forever.
    Future.delayed(const Duration(seconds: 25), () {
      if (!_disposed && _resolving) {
        _resolving = false;
        notifyListeners();
      }
    });
  }

  void exitForeground(BuildContext context) {
    if (!_foreground) return;
    _foreground = false;
    notifyListeners();
    // TV: the page content was focus-excluded while the trailer was fullscreen,
    // so nothing holds focus now — re-anchor the remote on the primary action.
    if (read().isTelevision) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_disposed || !context.mounted) return;
        // The left-entry node only has a holder when Play or the source pill is
        // present; if neither is (edge config), fall back to traversal so the
        // remote isn't stranded rather than no-op on an unattached node.
        final leftEntry = read().leftEntryFocusNode;
        if (detailNodeMounted(leftEntry)) {
          leftEntry.requestFocus();
        } else {
          FocusScope.of(context).nextFocus();
        }
      });
    }
  }

  /// Trailer button. Seamless path: if the ambient backdrop trailer is already
  /// playing, bring that *same* player forward (unmute + controls) in place — no
  /// second decoder, no re-buffer. Fallback path (autoplay off / not resolved /
  /// reduced motion): resolve fresh and launch the standalone player as before.
  Future<void> play(BuildContext context) async {
    if (backdropKey.currentState?.canPromote ?? false) {
      _foreground = true;
      notifyListeners();
      return;
    }

    final ytId = _ytId;
    if (ytId == null || _loading) return;

    // Always resolve fresh on tap. The autoplay-prefetched [streams] is
    // deliberately NOT reused here: googlevideo URLs carry an `expire` param and
    // go dead after a few hours, so a page left open would hand the player a
    // stale URL. Re-resolving costs one request and keeps playback reliable.
    _loading = true;
    notifyListeners();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
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
    if (streams == null || !(streams.playUrl?.isNotEmpty ?? false)) {
      final imdbId = read().item.effectiveImdbId;
      if (imdbId != null) {
        streams = await ImdbTrailerService.resolveTrailer(imdbId);
      }
    }

    if (_disposed || !context.mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    _loading = false;
    notifyListeners();

    final playUrl = streams?.playUrl;
    if (playUrl == null || playUrl.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Couldn\'t load trailer')));
      return;
    }

    await VideoPlayerLauncher.push(
      context,
      VideoPlayerLaunchArgs(
        videoUrl: playUrl,
        audioUrl: streams?.audioUrl,
        fallbackUrl: streams?.muxedPlaybackFallback,
        title: '${read().item.name} — Trailer',
        viewMode: PlaylistViewMode.sorted,
      ),
      // Watching the trailer must not suppress the ambient trailer backdrop.
      isTrailer: true,
    );
  }
}
