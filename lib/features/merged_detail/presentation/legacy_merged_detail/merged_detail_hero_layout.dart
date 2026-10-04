import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_action_layout.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_dependencies.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_metadata_state.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_rail_layout.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_root_layout.dart';
import 'package:debrify/features/merged_detail/presentation/merged_detail_palette.dart';
import 'package:debrify/features/merged_detail/presentation/merged_stagger_reveal.dart';
import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/imdb_enrichment_service.dart';
import 'package:debrify/services/metadata_details_service.dart';
import 'package:flutter/material.dart';

class MergedDetailHeroLayout {
  final MergedDetailDependencies _deps;
  MergedDetailHeroLayout(this._deps);
  StremioMeta get _item => _deps.presentedItem();
  MetadataPreferences get metadataPreferences => _deps.metadataPreferences();
  MergedDetailActionLayout get _ac => _deps.parts.actionLayout;
  MergedDetailMetadataState get _m => _deps.parts.metadataState;
  MergedDetailRailLayout get _ri => _deps.parts.railLayout;
  MergedDetailRootLayout get _ro => _deps.parts.rootLayout;

  // Mobile-only compact hero (wide/TV uses the left info pane instead).
  Widget buildHero() {
    final item = _item;
    final extra = _m.imdbExtra;
    final rating = extra?.rating ?? item.imdbRating;
    final year = item.year ?? extra?.year;
    final genres = MetadataDetailsService.informationGenres(
      item,
      extra,
      metadataPreferences,
    );

    // No boxed hero image: the page already paints one continuous full-bleed
    // backdrop (HeroTrailerBackdrop + dark tint) behind everything — exactly
    // like the movie layout — so a second inset image here read as an ugly
    // floating card. The hero is now pure content over that shared surface,
    // sized to what it holds (the old fixed 220px box overflowed upward when
    // the action row wrapped, shoving the title under the floating back
    // button). Bonus: with autoplay on, the ambient trailer now owns the whole
    // screen behind the page instead of stopping at a card edge. Top padding
    // clears the 46px floating back button.
    final animate =
        !(MediaQuery.maybeOf(_deps.context())?.disableAnimations ?? false) &&
        !_deps.isTelevision();
    return Padding(
      padding: EdgeInsets.fromLTRB(
        _deps.isTelevision() ? 40 : 24,
        _deps.isTelevision() ? 20 : 64,
        24,
        14,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MergedStaggerReveal(
            key: const ValueKey('rev-h-eyebrow'),
            delayMs: 0,
            enabled: animate,
            child: Text(
              'SERIES',
              style: TextStyle(
                color: _m.accent,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.2,
              ),
            ),
          ),
          const SizedBox(height: 8),
          MergedStaggerReveal(
            key: const ValueKey('rev-h-title'),
            delayMs: 55,
            enabled: animate,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Text(
                item.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: _ro.wide ? 34 : 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  height: 1.02,
                  shadows: const [
                    Shadow(color: Colors.black54, blurRadius: 18),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          MergedStaggerReveal(
            key: const ValueKey('rev-h-meta'),
            delayMs: 110,
            enabled: animate,
            child: buildMetaBar(year, extra, rating),
          ),
          // Tracker state lives in the action-row pills (see the info pane).
          if (genres.isNotEmpty) ...[
            const SizedBox(height: 10),
            MergedStaggerReveal(
              key: const ValueKey('rev-h-genres'),
              delayMs: 165,
              enabled: animate,
              child: Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [for (final g in genres.take(4)) _ri.pill(g)],
              ),
            ),
          ],
          const SizedBox(height: 14),
          MergedStaggerReveal(
            key: const ValueKey('rev-h-actions'),
            delayMs: 220,
            enabled: animate,
            child: _ac.buildActionRow(),
          ),
        ],
      ),
    );
  }

  Widget buildMetaBar(String? year, ImdbEnrichment? extra, double? rating) {
    final parts = <Widget>[];
    void add(Widget w) {
      if (parts.isNotEmpty) parts.add(const SizedBox(width: 16));
      parts.add(w);
    }

    final runtime = MetadataDetailsService.informationRuntime(
      _item,
      extra,
      metadataPreferences,
    );
    if (runtime != null) add(metaText(runtime));
    if (year != null && year.isNotEmpty) add(metaText(year));
    final cert = extra?.certificate;
    if (cert != null) {
      add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: MergedDetailPalette.glass2,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: MergedDetailPalette.hair),
          ),
          child: Text(
            cert,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
      );
    }
    if (rating != null) {
      add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              rating.toStringAsFixed(1),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: MergedDetailPalette.imdb,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'IMDb',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: parts);
  }

  Widget metaText(String s) => Text(
    s,
    style: TextStyle(
      color: Colors.white70,
      fontSize: 14,
      fontWeight: FontWeight.w600,
    ),
  );
}
