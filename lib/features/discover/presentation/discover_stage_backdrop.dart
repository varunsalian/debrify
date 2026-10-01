import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../models/stremio_addon.dart';
import '../../../utils/platform_util.dart';
import '../../../widgets/home/home_theme.dart';

/// The Discover glass stage's still backdrop: the focused (rail-shown) title's
/// backdrop drawn full-frame behind both panes, veiled by the tint veils
/// above it. Adoption is dwell-debounced (~380ms) so rapid DPAD arrowing never
/// decodes a full-bleed image per step — the first artwork after an empty stage
/// paints immediately. Only real `background` art is used (never a blown-up
/// poster); titles without it browse on the plain ink wash.
class DiscoverStageBackdrop extends StatefulWidget {
  final ValueListenable<StremioMeta?> shown;

  /// How long the DPAD must rest before this adopts a new backdrop. The STAGE
  /// layout passes ZERO: its feed is already settled upstream (the identity
  /// block's own settle), so a second dwell here would only make the art trail
  /// the title it belongs to.
  final Duration dwell;

  /// Crossfade swaps instead of snapping them. The two-pane keeps the snap —
  /// a full-screen crossfade is a saveLayer on weak TV GPUs, and behind a
  /// grid it buys little. The STAGE turns it on: the art IS the layout there,
  /// and its swaps are already rate-limited by the settle, so this matches the
  /// Home board's own full-bleed art, which crossfades on the same cadence.
  final bool crossfade;

  const DiscoverStageBackdrop({
    super.key,
    required this.shown,
    this.dwell = const Duration(milliseconds: 380),
    this.crossfade = false,
  });

  @override
  State<DiscoverStageBackdrop> createState() => _DiscoverStageBackdropState();
}

class _DiscoverStageBackdropState extends State<DiscoverStageBackdrop> {
  String? _url;
  Timer? _dwell;

  static String? _bgOf(StremioMeta? m) {
    final bg = m?.background;
    return (bg != null && bg.isNotEmpty) ? bg : null;
  }

  @override
  void initState() {
    super.initState();
    widget.shown.addListener(_onShown);
    _url = _bgOf(widget.shown.value);
  }

  @override
  void dispose() {
    _dwell?.cancel();
    widget.shown.removeListener(_onShown);
    super.dispose();
  }

  void _onShown() {
    final next = _bgOf(widget.shown.value);
    if (next == _url) return;
    _dwell?.cancel();
    // Cleared (source swap) or the focused title has no backdrop: drop to ink
    // now — holding another title's art behind the wrong detail reads wrong.
    if (next == null) {
      setState(() => _url = null);
      return;
    }
    // First art onto an empty stage: no dwell, the page should dress itself
    // promptly. Subsequent moves debounce.
    if (_url == null) {
      setState(() => _url = next);
      return;
    }
    if (widget.dwell == Duration.zero) {
      setState(() => _url = next);
      return;
    }
    _dwell = Timer(widget.dwell, () {
      if (!mounted) return;
      final cur = _bgOf(widget.shown.value);
      if (cur != null && cur != _url) setState(() => _url = cur);
    });
  }

  @override
  Widget build(BuildContext context) {
    final url = _url;
    // Per-IMAGE fades stay off in both modes (a CachedNetworkImage crossfade
    // runs on every arrival, including cache hits). Slight upward bias keeps
    // faces/titles in the art's clear zone.
    final art = url == null
        ? const SizedBox.shrink()
        : CachedNetworkImage(
            key: ValueKey(url),
            imageUrl: url,
            fit: BoxFit.cover,
            alignment: const Alignment(0, -0.4),
            memCacheWidth: HomeTheme.heroBackdropCacheWidthTv,
            fadeInDuration: Duration.zero,
            fadeOutDuration: Duration.zero,
            placeholder: (_, __) => const SizedBox.shrink(),
            errorWidget: (_, __, ___) => const SizedBox.shrink(),
          );
    if (!widget.crossfade) return art;
    // Android TV keeps the two-pane's SNAP even on the stage: the switcher's
    // crossfade is a full-screen saveLayer on that GLES2 pipeline — the exact
    // cost the two-pane documented when it declined the fade — and a rest can
    // pay it twice (the raw list art, then the /meta-enriched background a
    // moment later). On an Amlogic box those frames land right when the user
    // is about to move again, which reads as navigation lag.
    if (PlatformUtil.isAndroidTvCached) return art;
    // Between two SETTLED titles — at most one swap per rest — so the
    // saveLayer this costs is bounded, exactly as on the Home board's stage.
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      // LOSING the art snaps instead of fading. Catalog list items usually
      // arrive with no `background` at all — it comes with the /meta
      // enrichment a moment later — so a symmetric crossfade would dip the
      // whole frame to ink and back on nearly every rest. Only the arrival is
      // worth animating.
      reverseDuration: url == null
          ? Duration.zero
          : const Duration(milliseconds: 240),
      // EXPAND, not the default centre-and-shrink-wrap: a switcher's stock
      // layout hands its children loose constraints, which would let each
      // backdrop paint at its own intrinsic size instead of covering the
      // frame — outgoing and incoming art must both be the same full-bleed
      // crop, or the swap reads as a jump in zoom.
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.expand,
        children: [...previous, if (current != null) current],
      ),
      child: art,
    );
  }
}
