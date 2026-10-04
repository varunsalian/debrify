import 'package:debrify/features/catalog_detail/presentation/catalog_quick_actions.dart';
import 'package:debrify/features/catalog_detail/presentation/catalog_rec_card.dart';
import 'package:debrify/features/catalog_detail/presentation/catalog_reveal.dart';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_dependencies.dart';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_metadata.dart';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_root_layout.dart';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_mdblist_quick_actions.dart';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_simkl_quick_actions.dart';
import 'package:debrify/widgets/parents_guide_section.dart';
import 'package:debrify/widgets/shimmer.dart';
import 'package:flutter/material.dart';

class CatalogDetailRailSections {
  final CatalogDetailDependencies _deps;

  CatalogDetailRailSections(this._deps);

  CatalogDetailMetadata get _m => _deps.parts.metadata;

  CatalogDetailRootLayout get _ro => _deps.parts.rootLayout;

  Widget? secParentsGuide(double start) {
    final guide = _m.parentsGuide;
    if (guide == null) {
      if (_m.parentsGuideLoaded) return null;
      final rowH = _ro.tight ? 38.0 : 44.0;
      return CatalogReveal(
        parent: _deps.revealCtrl,
        start: start,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Shimmer(
              width: 130,
              height: 14,
              borderRadius: BorderRadius.circular(4),
            ),
            SizedBox(height: _ro.tight ? 8 : 10),
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) SizedBox(height: _ro.tight ? 6 : 8),
              Shimmer(
                width: double.infinity,
                height: rowH,
                borderRadius: BorderRadius.circular(10),
              ),
            ],
          ],
        ),
      );
    }
    if (guide.isEmpty) return null;
    return CatalogReveal(
      parent: _deps.revealCtrl,
      start: start,
      child: ParentsGuideSection(
        guide: guide,
        tv: _deps.isTelevision(),
        dense: _ro.tight,
      ),
    );
  }

  Widget? secSimklQuickActions(double start) {
    if (_deps.simklMenuOptions().isEmpty || _deps.onSimklAction() == null) {
      return null;
    }
    return CatalogReveal(
      parent: _deps.revealCtrl,
      start: start,
      child: CatalogSimklQuickActions(
        options: _deps.simklMenuOptions(),
        tv: _deps.isTelevision(),
        phone: !_ro.wide,
        onSelected: _deps.onSimklAction()!,
      ),
    );
  }

  Widget? secMdblistQuickActions(double start) {
    if (_deps.mdblistMenuOptions().isEmpty || _deps.onMdblistAction() == null) {
      return null;
    }
    return CatalogReveal(
      parent: _deps.revealCtrl,
      start: start,
      child: CatalogMdblistQuickActions(
        options: _deps.mdblistMenuOptions(),
        onSelected: _deps.onMdblistAction()!,
      ),
    );
  }

  Widget? secQuickActions(double start) {
    if (_deps.traktMenuOptions().isEmpty || _deps.onTraktAction() == null) {
      return null;
    }
    return CatalogReveal(
      parent: _deps.revealCtrl,
      start: start,
      child: CatalogQuickActions(
        options: _deps.traktMenuOptions(),
        tv: _deps.isTelevision(),
        // Phone (narrow layout): force a tidy 3-up grid. Wide/TV keeps
        // its free-flowing wrap.
        phone: !_ro.wide,
        onSelected: _deps.onTraktAction()!,
      ),
    );
  }

  Widget? secRecommendations(double start) {
    final recs = _m.recommendations;
    final onTap = _deps.onRecommendationTap() == null
        ? null
        : _m.openMetadataRecommendation;
    final tight = _ro.tight;
    final cardW = _ro.wide ? (tight ? 104.0 : 120.0) : 112.0;
    final posterH = cardW * 1.5;
    final loading =
        recs == null &&
        !_m.recommendationsLoaded &&
        _deps.recommendationsLoader() != null;

    if (!loading && (recs == null || recs.isEmpty || onTap == null)) {
      return null;
    }

    return CatalogReveal(
      parent: _deps.revealCtrl,
      start: start,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          loading
              ? Shimmer(
                  width: 130,
                  height: 16,
                  borderRadius: BorderRadius.circular(4),
                )
              : Text(
                  'More Like This',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontSize: _ro.wide && !tight ? 18 : 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                    shadows: const [
                      Shadow(color: Color(0x99000000), blurRadius: 8),
                    ],
                  ),
                ),
          SizedBox(height: tight ? 8 : 12),
          SizedBox(
            height: posterH + 44,
            child: loading
                ? Row(
                    children: [
                      for (var i = 0; i < 4; i++) ...[
                        if (i > 0) const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Shimmer(
                              width: cardW,
                              height: posterH,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            const SizedBox(height: 6),
                            Shimmer(
                              width: cardW * 0.8,
                              height: 12,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ],
                        ),
                      ],
                    ],
                  )
                : FocusTraversalGroup(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      clipBehavior: Clip.none,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < recs!.length; i++) ...[
                            if (i > 0) const SizedBox(width: 12),
                            CatalogRecCard(
                              item: recs[i],
                              width: cardW,
                              posterHeight: posterH,
                              tv: _deps.isTelevision(),
                              onTap: () => onTap!(recs[i]),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
