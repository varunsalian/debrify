import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Presentation fades with borrowed signals; owns no controllers or listeners.
class HomeHeroTransitions {
  const HomeHeroTransitions({
    required this.boxedTrailer,
    this.showing,
    this.liveTakeover,
  });
  final bool boxedTrailer;
  final ValueListenable<bool>? showing;
  final ValueListenable<bool>? liveTakeover;

  /// Legibility wrapper for the left tint SCRIM and the identity TEXT: in
  /// [boxedTrailer] mode they must STAY while the trailer plays (only the
  /// backdrop image yields — see [fadeBackdropForTrailer]), so this is a pass-
  /// through there. No-op too when the surface runs no trailers.
  Widget fadeIdentityForTrailer(Widget child) {
    final showing = this.showing;
    if (showing == null || boxedTrailer) return child;
    return ValueListenableBuilder<bool>(
      valueListenable: showing,
      builder: (context, on, kid) => AnimatedOpacity(
        opacity: on ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeOut,
        child: kid,
      ),
      child: child,
    );
  }

  /// Fades the backdrop IMAGE out while the trailer plays (boxedTrailer). The
  /// colour field beneath (the mood field) takes its place, so the left of
  /// the hero becomes a rich tint wash instead of a cropped half-poster beside
  /// the trailer. Timing mirrors the 650ms crossfade the video uses internally.
  Widget fadeBackdropForTrailer(Widget child) {
    final showing = this.showing;
    if (showing == null || !boxedTrailer) return child;
    return ValueListenableBuilder<bool>(
      valueListenable: showing,
      builder: (context, on, kid) => AnimatedOpacity(
        opacity: on ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeOut,
        child: kid,
      ),
      child: child,
    );
  }

  /// Boxed-mode counterpart of [fadeIdentityForTrailer] for the SECONDARY
  /// identity lines only (meta chips + plot): while the ambient trailer plays
  /// they fade away and the title/logo stays — the Netflix/Nuvio "logo holds
  /// the stage" move. Safe by construction: the identity block sits left of
  /// the trailer region, so this Opacity never covers the underlay's
  /// punch-through hole. Pass-through outside boxed mode (the full-block fade
  /// above already handles that layout).
  Widget fadeMetaForTrailer(Widget child) {
    final showing = this.showing;
    if (showing == null || !boxedTrailer) return child;
    return ValueListenableBuilder<bool>(
      valueListenable: showing,
      builder: (context, on, kid) => AnimatedOpacity(
        opacity: on ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 480),
        curve: Curves.easeOut,
        child: kid,
      ),
      child: child,
    );
  }

  /// An IPTV favourite has taken the boxed video region ([liveTakeover]) —
  /// unlike the catalog trailer, that video has NOTHING to do with the catalog title, so
  /// its colour field / identity text must actually disappear rather than
  /// stay put (the invariant [fadeIdentityForTrailer]/[fadeMetaForTrailer] rely
  /// on — "the text is still about what's playing" — doesn't hold here).
  /// No-op when the surface never runs IPTV favourites.
  Widget fadeForLiveTakeover(Widget child) {
    final live = liveTakeover;
    if (live == null) return child;
    return ValueListenableBuilder<bool>(
      valueListenable: live,
      builder: (context, on, kid) => AnimatedOpacity(
        opacity: on ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 340),
        curve: Curves.easeOut,
        child: kid,
      ),
      child: child,
    );
  }
}
