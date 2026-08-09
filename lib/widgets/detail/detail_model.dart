import 'package:flutter/material.dart';

import '../../models/stremio_addon.dart';
import '../../services/imdb_enrichment_service.dart';
import '../../services/imdb_parents_guide_service.dart';
import 'detail_style.dart';

/// Screen-owned focus anchors, handed to whichever body is drawing.
///
/// The shell owns the back button and the trailer's focus restoration, but only
/// the body knows where its primary action lives — so the body mounts
/// [primaryEntry] and the shell drives it through this.
class DetailFocusCoordinator {
  /// The shell's back button. Always mounted, in every layout.
  final FocusNode backNode;

  /// The body's primary action — Play/Resume, else the source pill when Play is
  /// hidden (PikPak-only), else the body's first focusable. Mounted exactly
  /// once by the active layout.
  final FocusNode primaryEntry;

  const DetailFocusCoordinator({
    required this.backNode,
    required this.primaryEntry,
  });

  /// Deterministic, synchronous. Used by the episode list's LEFT crossing.
  ///
  /// Never falls through to bare traversal: a geometric search happily picks a
  /// cast tile or a recommendation sitting below-left of the list, which is
  /// what "LEFT lands somewhere random" was.
  void focusEntry() {
    if (detailNodeMounted(primaryEntry)) {
      primaryEntry.requestFocus();
    } else {
      backNode.requestFocus();
    }
  }

  /// Post-frame variant, for use after the body has just re-mounted (leaving
  /// the fullscreen trailer), when neither node has a context yet.
  void restoreAfterTrailer() {
    WidgetsBinding.instance.addPostFrameCallback((_) => focusEntry());
  }
}

/// What the body asks the shell to paint behind it.
class DetailBodySpec {
  /// Flat ink instead of the artwork — Broadsheet's editorial ground.
  ///
  /// The shell paints this INSIDE its content layer (above the tint, below the
  /// accent wash), never as an ancestor of the trailer backdrop, so the
  /// punch-through and the promote/dismiss fade both keep working.
  final bool inkGround;

  /// The body paints its own scrim, so the shell must skip Classic's tint.
  ///
  /// Classic's tint is a flat 0.60→0.88 wash designed to make text readable
  /// over any poster on a page that isn't *about* the poster. Stacking a
  /// layout's own gradient on top of it darkens the artwork to near-black —
  /// which erases the entire point of a full-bleed layout.
  final bool ownScrim;

  const DetailBodySpec({this.inkGround = false, this.ownScrim = false});
}

/// Everything a layout renders, owned and kept fresh by `MergedDetailScreen`.
///
/// Layouts are stateless with respect to data — they hold only focus, scroll
/// and tab state — so every load, refresh and tracker round-trip keeps working
/// exactly as it does for Classic.
class DetailModel {
  final StremioMeta item;
  final bool isMovie;
  final bool isTelevision;

  /// Per-title accent, extracted from the poster.
  final Color accent;

  final ImdbEnrichment? imdbExtra;
  final ParentsGuideResult? parentsGuide;
  final List<StremioMeta> recommendations;

  /// Primary button caption — "Resume · S5E9", "Start Watching", "Rewatch", …
  final String primaryLabel;

  /// Bound-source count for the pill; 0 renders "Bind source".
  final int sourceCount;

  // ── Trailer ──────────────────────────────────────────────────────────────
  final bool hasTrailer;
  final bool trailerBusy;
  final bool trailerPlaying;

  // ── Tracker pills ────────────────────────────────────────────────────────
  final bool hasTrakt;
  final bool traktTracked;
  final String traktLabel;
  final int? traktRating;
  final bool hasSimkl;
  final bool simklTracked;
  final String simklLabel;
  final int? simklRating;

  // ── Actions ──────────────────────────────────────────────────────────────
  final bool showPrimary;
  final VoidCallback onPrimary;
  final VoidCallback? onBrowse; // movie Sources
  final VoidCallback onTrailer;
  final VoidCallback? onSelectSource;
  final VoidCallback? onAppMenu;
  final VoidCallback? onTraktMenu;
  final VoidCallback? onSimklMenu;
  final void Function(StremioMeta)? onRecommendationTap;

  /// Filmstrip pushes the focused episode's still here; the shell paints it as
  /// an ambient layer. Null clears it.
  final void Function(String?) onAmbientStill;

  final DetailFocusCoordinator focus;

  const DetailModel({
    required this.item,
    required this.isMovie,
    required this.isTelevision,
    required this.accent,
    required this.imdbExtra,
    required this.parentsGuide,
    required this.recommendations,
    required this.primaryLabel,
    required this.sourceCount,
    required this.hasTrailer,
    required this.trailerBusy,
    required this.trailerPlaying,
    required this.hasTrakt,
    required this.traktTracked,
    required this.traktLabel,
    required this.traktRating,
    required this.hasSimkl,
    required this.simklTracked,
    required this.simklLabel,
    required this.simklRating,
    required this.showPrimary,
    required this.onPrimary,
    required this.onBrowse,
    required this.onTrailer,
    required this.onSelectSource,
    required this.onAppMenu,
    required this.onTraktMenu,
    required this.onSimklMenu,
    required this.onRecommendationTap,
    required this.onAmbientStill,
    required this.focus,
  });

  String get name => item.name;
  String? get year => item.year ?? imdbExtra?.year;
  double? get rating => imdbExtra?.rating ?? item.imdbRating;
  String? get certificate => imdbExtra?.certificate;
  String? get runtime => imdbExtra?.runtime;
  String? get logo => item.logo;
  String? get poster => item.poster;
  String? get backdrop => item.background ?? item.poster;

  List<String> get genres {
    final own = item.genres;
    if (own != null && own.isNotEmpty) return own;
    return imdbExtra?.genres ?? const [];
  }

  String? get synopsis {
    final own = item.description;
    if (own != null && own.isNotEmpty) return own;
    return imdbExtra?.plot;
  }

  String? get awards =>
      imdbExtra?.hasAwards == true ? imdbExtra!.awardsLine : null;

  List<CastMember> get cast => imdbExtra?.cast ?? const [];

  /// Label→value pairs for the Details block. Empty when nothing is known —
  /// callers must omit the whole section rather than render an empty one.
  List<(String, String)> get detailRows {
    final e = imdbExtra;
    if (e == null) return const [];
    return [
      if (e.director != null && e.director!.isNotEmpty)
        (isMovie ? 'Director' : 'Creator', e.director!),
      if (e.countries.isNotEmpty) ('Country', e.countries.take(2).join(', ')),
      if (e.languages.isNotEmpty) ('Language', e.languages.take(3).join(', ')),
      if (e.productionCompany != null) ('Studio', e.productionCompany!),
      if (e.boxOffice != null) ('Box Office', e.boxOffice!),
    ];
  }
}
