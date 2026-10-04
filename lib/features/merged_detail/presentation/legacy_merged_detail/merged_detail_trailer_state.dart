import 'package:debrify/services/metadata_details_service.dart';
import 'package:debrify/services/youtube_service.dart';
import 'package:debrify/widgets/hero_trailer_backdrop.dart';
import 'package:flutter/material.dart';

class MergedDetailTrailerState {
  /// Trailer YouTube ID, resolved from Cinemeta meta. Null until loaded / when
  /// the title has no trailer — the Trailer button only shows once this is set.
  String? trailerYtId;

  /// Guards against a double-launch while a trailer's streams resolve.
  bool trailerLoading = false;

  /// Whether OTT-style trailer autoplay behind the backdrop is on (settings).
  /// Always false on Android TV — the Home hero owns ambient trailers there.
  bool trailerAutoplayEnabled = false;

  /// Ambient loop volume (0–100) from settings; 0 when the sound toggle is off.
  /// Read alongside [_trailerAutoplayEnabled] and applied when the backdrop
  /// opens its engine (which can't happen before the streams resolve), so it's
  /// always in place by then. Promoting to fullscreen still plays at full
  /// volume — the backdrop handles that, muted ambient or not.
  double trailerAmbientVolume = 70;

  /// Resolved trailer streams, pre-fetched for the ambient backdrop.
  YoutubeResolvedStreams? trailerStreams;

  /// Handle to the backdrop so the Trailer button can promote the *same* player
  /// to fullscreen in place (seamless — no second decoder, no re-buffer).
  final GlobalKey<HeroTrailerBackdropState> backdropKey = GlobalKey();

  /// Whether the trailer is currently brought forward to fullscreen.
  bool trailerForeground = false;

  /// The ambient backdrop trailer is live with frames on screen — the Trailer
  /// button reads "Watch Trailer" to say "it's playing, tap to view".
  bool trailerAmbientPlaying = false;

  /// Autoplay pipeline in flight (stream resolve → buffer → first frame) — the
  /// Trailer button shows a spinner.
  bool trailerResolving = false;

  /// Resolve the trailer's YouTube ID from Cinemeta. Runs independently of
  /// [_loadEnrichedMeta] (which short-circuits for already-rich items and so
  /// can't be relied on to carry the trailer). The `fetchMetaDetails` result is
  /// cached in [StremioService], so this shares that fetch rather than doubling
  /// network. Silent on failure — the button simply never appears.
  int trailerGeneration = 0;
  List<MetadataTrailer> trailerCandidates = [];
  bool allowTrailerFallback = true;
}
