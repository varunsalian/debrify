import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_cast_tile.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_dependencies.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_focus_state.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_metadata_state.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_pane_layout.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_root_layout.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_rec_card.dart';
import 'package:debrify/features/merged_detail/presentation/merged_detail_palette.dart';
import 'package:debrify/features/merged_detail/presentation/merged_rail_edge_trap.dart';
import 'package:debrify/features/merged_detail/presentation/merged_round_icon_button.dart';
import 'package:debrify/features/merged_detail/presentation/merged_scroll_anchor.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/imdb_enrichment_service.dart';
import 'package:debrify/widgets/detail/theme/detail_theme.dart';
import 'package:debrify/widgets/horizontal_mouse_wheel.dart';
import 'package:debrify/widgets/metadata_franchise_rail.dart';
import 'package:debrify/widgets/parents_guide_section.dart';
import 'package:flutter/material.dart';

class MergedDetailRailLayout {
  final MergedDetailDependencies _deps;
  MergedDetailRailLayout(this._deps);
  StremioMeta get _item => _deps.presentedItem();
  MergedDetailFocusState get _f => _deps.parts.focusState;
  MergedDetailMetadataState get _m => _deps.parts.metadataState;
  MergedDetailPaneLayout get _pa => _deps.parts.paneLayout;
  MergedDetailRootLayout get _ro => _deps.parts.rootLayout;

  // ── Side-rail sections (shared by wide rail + narrow details sheet) ─────────

  /// The reference sections that live inline in the TV info column (awards,
  /// credits, cast, details, parents guide, more like this) — no quick actions,
  /// no summary (both already shown above in the info pane).
  List<Widget> referenceSections() {
    return [
      const SizedBox(height: 20),
      ...sideRailSections(includeSummary: false),
    ];
  }

  List<Widget> sideRailSections({bool includeSummary = true}) {
    final item = _item;
    final extra = _m.imdbExtra;
    final sections = <Widget>[];

    final summary = (item.description?.isNotEmpty ?? false)
        ? item.description
        : extra?.plot;
    if (includeSummary && summary != null && summary.isNotEmpty) {
      sections
        ..add(sectionLabel('Summary'))
        ..add(const SizedBox(height: 8))
        ..add(
          Text(
            summary,
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13.5,
              height: 1.55,
            ),
          ),
        )
        ..add(const SizedBox(height: 22));
    }

    // Awards (gold pill) — parity with the detail screen.
    final awardsLine = extra?.hasAwards == true ? extra!.awardsLine : null;
    if (awardsLine != null && awardsLine.isNotEmpty) {
      sections
        ..add(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              color: MergedDetailPalette.gold.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: MergedDetailPalette.gold.withValues(alpha: 0.24),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.emoji_events_rounded,
                  size: 15,
                  color: MergedDetailPalette.gold,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    awardsLine,
                    style: const TextStyle(
                      color: MergedDetailPalette.gold,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        )
        ..add(const SizedBox(height: 22));
    }

    // Credits (director / stars) — parity with the detail screen.
    final creditRows = <(String, String)>[];
    if (extra != null) {
      if (extra.director != null && extra.director!.isNotEmpty) {
        creditRows.add(('Director', extra.director!));
      }
      if (extra.stars.isNotEmpty) {
        creditRows.add(('Stars', extra.stars.take(4).join(', ')));
      }
    }
    if (creditRows.isNotEmpty) {
      sections
        ..add(sectionLabel('Credits'))
        ..add(const SizedBox(height: 8))
        ..add(kvBlock(creditRows))
        ..add(const SizedBox(height: 22));
    }

    // Details (country / language / studio / box office) — grouped with the
    // other non-focusable text ABOVE the focusable Cast/Recs/Parents-Guide, so
    // on TV it's revealed while scrolling down to those (never stranded below
    // the last focusable when e.g. Parents Guide is absent).
    final detailRows = <(String, String)>[];
    if (extra != null) {
      if (extra.countries.isNotEmpty) {
        detailRows.add(('Country', extra.countries.take(2).join(', ')));
      }
      if (extra.languages.isNotEmpty) {
        detailRows.add(('Language', extra.languages.take(3).join(', ')));
      }
      if (extra.productionCompany != null) {
        detailRows.add(('Studio', extra.productionCompany!));
      }
      if (extra.boxOffice != null) {
        detailRows.add(('Box Office', extra.boxOffice!));
      }
    }
    if (detailRows.isNotEmpty) {
      sections
        ..add(sectionLabel('Details'))
        ..add(const SizedBox(height: 8))
        ..add(kvBlock(detailRows))
        ..add(const SizedBox(height: 22));
    }

    // Cast / More Like This are capped so the rails can build EVERY card up
    // front (see [_focusRail]) without a wall of image fetches — DPAD needs
    // real widgets to walk onto, and a dozen tiny thumbs is plenty of content.
    final cast = (extra?.cast ?? const []).take(12).toList();
    if (cast.isNotEmpty) {
      sections
        ..add(sectionLabel('Cast'))
        ..add(const SizedBox(height: 12))
        ..add(
          MergedScrollAnchor(
            active: _deps.isTelevision(),
            alignment: 0.35,
            child: SizedBox(
              height: 92,
              child: focusRail(
                controller: _f.castRailScroll,
                gap: 14,
                cards: [for (final m in cast) castTile(m)],
              ),
            ),
          ),
        )
        ..add(const SizedBox(height: 22));
    }

    sections.add(
      MetadataFranchiseRail(
        item: _item,
        onOpen: _deps.onRecommendationTap() == null
            ? null
            : _m.openMetadataRecommendation,
        isTelevision: _deps.isTelevision(),
      ),
    );

    // More Like This — placed high (right after Cast) so it's an easy DPAD-down
    // reach, ahead of the long focusable Parents-Guide list.
    final recs = (_m.recommendations ?? const <StremioMeta>[])
        .take(10)
        .toList();
    if (recs.isNotEmpty && _deps.onRecommendationTap() != null) {
      sections
        ..add(sectionLabel('More Like This'))
        ..add(const SizedBox(height: 12))
        ..add(
          MergedScrollAnchor(
            active: _deps.isTelevision(),
            alignment: 0.5,
            child: SizedBox(
              height: 168,
              child: focusRail(
                controller: _f.recommendationRailScroll,
                gap: 11,
                cards: [for (final r in recs) recCard(r)],
              ),
            ),
          ),
        )
        ..add(const SizedBox(height: 22));
    }

    final guide = _m.parentsGuide;
    if (guide != null && !guide.isEmpty) {
      sections
        ..add(sectionLabel('Parents Guide'))
        ..add(const SizedBox(height: 12))
        ..add(
          ParentsGuideSection(
            guide: guide,
            tv: _deps.isTelevision(),
            dense: true,
            accent: _m.accent,
          ),
        );
    }

    return sections;
  }

  /// Horizontal DPAD rail (Cast / More Like This). Builds ALL cards in a plain
  /// scrollable Row — a lazy ListView only builds what's near the viewport, so
  /// DPAD-right at the build edge found no next card and the focus jumped clean
  /// out of the rail (into the episodes pane) mid-browse. With every card real,
  /// traversal walks the whole rail and the framework auto-scrolls each focused
  /// card into view. The first card traps LEFT as a dead stop; the last card's
  /// RIGHT crosses deterministically into the episodes pane in the series
  /// two-pane layout (dead stop otherwise) — RIGHT is the sanctioned pane
  /// crossing, so it should work from a rail end too.
  Widget focusRail({
    required ScrollController controller,
    required List<Widget> cards,
    required double gap,
  }) {
    final crossRight = (!_ro.isMovie && _ro.wide)
        ? _pa.focusEpisodesPane
        : null;
    return HorizontalMouseWheel(
      controller: controller,
      child: SingleChildScrollView(
        controller: controller,
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              if (i > 0) SizedBox(width: gap),
              MergedRailEdgeTrap(
                trapLeft: i == 0,
                trapRight: i == cards.length - 1,
                onTrapRight: crossRight,
                child: cards[i],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget castTile(CastMember m) =>
      MergedCastTile(member: m, fallback: MergedDetailPalette.glass2);

  Widget recCard(StremioMeta rec) => MergedRecCard(
    rec: rec,
    fallback: MergedDetailPalette.glass2,
    onTap: () => _m.openMetadataRecommendation(rec),
  );

  Widget sectionLabel(String s) => Text(
    s.toUpperCase(),
    style: TextStyle(
      color: Colors.white38,
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.6,
    ),
  );

  /// Label→value rows (Credits / Details), matching the detail screen's layout.
  Widget kvBlock(List<(String, String)> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 70,
                child: Text(
                  rows[i].$1,
                  style: const TextStyle(color: Colors.white38, fontSize: 13),
                ),
              ),
              Expanded(
                child: Text(
                  rows[i].$2,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget pill(String s) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    decoration: BoxDecoration(
      color: MergedDetailPalette.glass2,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: MergedDetailPalette.hair),
    ),
    child: Text(s, style: const TextStyle(fontSize: 12)),
  );

  Widget circleButton(
    IconData icon,
    VoidCallback onTap, {
    String? tooltip,
    FocusNode? focusNode,
    DetailTheme? theme,
  }) {
    return MergedRoundIconButton(
      icon: icon,
      onTap: onTap,
      tooltip: tooltip,
      focusNode: focusNode,
      background: theme == null
          ? Colors.black.withValues(alpha: 0.35)
          : theme.ground.withValues(alpha: 0.55),
      theme: theme,
    );
  }
}
