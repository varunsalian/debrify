import 'package:debrify/features/catalog_detail/presentation/catalog_glass_card.dart';
import 'package:debrify/features/catalog_detail/presentation/catalog_reveal.dart';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_action_layout.dart';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_credits_sections.dart';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_dependencies.dart';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_hero_sections.dart';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_metadata.dart';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_rail_sections.dart';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_root_layout.dart';
import 'package:debrify/widgets/metadata_franchise_rail.dart';
import 'package:flutter/material.dart';

class CatalogDetailContentColumns {
  final CatalogDetailDependencies _deps;

  CatalogDetailContentColumns(this._deps);

  CatalogDetailMetadata get _m => _deps.parts.metadata;

  CatalogDetailRootLayout get _ro => _deps.parts.rootLayout;

  CatalogDetailHeroSections get _he => _deps.parts.heroSections;

  CatalogDetailCreditsSections get _cr => _deps.parts.creditsSections;

  CatalogDetailRailSections get _ra => _deps.parts.railSections;

  CatalogDetailActionLayout get _a => _deps.parts.actionLayout;

  /// Wide: cinematic bottom-left sheet — info first, Play/Sources at the end.
  Widget buildContentColumn() {
    final t = _ro.tight;
    final children = <Widget>[
      _he.secEyebrow(0.00),
      SizedBox(height: t ? 6 : 10),
      _he.secTitle(0.10),
      SizedBox(height: t ? 8 : 14),
      _he.secMeta(0.20),
    ];
    final g = _he.secGenres(0.28);
    if (g != null) {
      children
        ..add(SizedBox(height: t ? 10 : 18))
        ..add(g);
    }
    final aw = _he.secAwards(0.32);
    if (aw != null) {
      children
        ..add(SizedBox(height: t ? 8 : 12))
        ..add(aw);
    }
    children
      ..add(SizedBox(height: t ? 16 : 26))
      ..add(_a.buildActionRow(0.38));
    final d = _a.secDescription(0.46);
    if (d != null) {
      children
        ..add(SizedBox(height: t ? 12 : 24))
        ..add(d);
    }
    final cr = _cr.secCredits(0.50);
    if (cr != null) {
      children
        ..add(SizedBox(height: t ? 10 : 18))
        ..add(cr);
    }
    final ca = _cr.secCast(0.52);
    if (ca != null) {
      children
        ..add(SizedBox(height: t ? 14 : 24))
        ..add(ca);
    }
    final q = _ra.secQuickActions(0.54);
    if (q != null) {
      children
        ..add(SizedBox(height: t ? 14 : 26))
        ..add(q);
    }
    final sq = _ra.secSimklQuickActions(0.55);
    if (sq != null) {
      children
        ..add(SizedBox(height: t ? 14 : 26))
        ..add(sq);
    }
    final mq = _ra.secMdblistQuickActions(0.555);
    if (mq != null) {
      children
        ..add(SizedBox(height: t ? 14 : 26))
        ..add(mq);
    }
    final dt = _cr.secDetails(0.56);
    if (dt != null) {
      children
        ..add(SizedBox(height: t ? 12 : 22))
        ..add(dt);
    }
    final pg = _ra.secParentsGuide(0.58);
    if (pg != null) {
      children
        ..add(SizedBox(height: t ? 12 : 22))
        ..add(pg);
    }
    children.add(
      MetadataFranchiseRail(
        item: _deps.presentedItem(),
        onOpen: _deps.onRecommendationTap() == null
            ? null
            : _m.openMetadataRecommendation,
        isTelevision: _deps.isTelevision(),
      ),
    );
    final r = _ra.secRecommendations(0.66);
    if (r != null) {
      children
        ..add(SizedBox(height: t ? 16 : 28))
        ..add(r);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  Widget buildNarrowColumn() {
    final children = <Widget>[
      _he.secEyebrow(0.00),
      const SizedBox(height: 8),
      _he.secTitle(0.10),
      const SizedBox(height: 12),
      _he.secMeta(0.20),
    ];
    final g = _he.secGenres(0.28);
    if (g != null) {
      children
        ..add(const SizedBox(height: 14))
        ..add(g);
    }
    final aw = _he.secAwards(0.32);
    if (aw != null) {
      children
        ..add(const SizedBox(height: 12))
        ..add(aw);
    }
    children
      ..add(const SizedBox(height: 24))
      ..add(_a.buildActionRow(0.38));

    // ── Glass info card: synopsis + credits + cast ──
    // All inner sections share the card's start time so they fade in
    // together — no staggered holes inside the card.
    const infoStart = 0.46;
    final infoChildren = <Widget>[];
    final d = _a.secDescription(infoStart);
    if (d != null) infoChildren.add(d);
    final cr = _cr.secCredits(infoStart);
    if (cr != null) {
      if (infoChildren.isNotEmpty) infoChildren.add(_ro.divider());
      infoChildren.add(cr);
    }
    final ca = _cr.secCast(infoStart);
    if (ca != null) {
      if (infoChildren.isNotEmpty) infoChildren.add(_ro.divider());
      infoChildren.add(ca);
    }
    if (infoChildren.isNotEmpty) {
      children
        ..add(const SizedBox(height: 24))
        ..add(
          CatalogReveal(
            parent: _deps.revealCtrl,
            start: infoStart,
            child: CatalogGlassCard(children: infoChildren),
          ),
        );
    }

    final q = _ra.secQuickActions(0.54);
    if (q != null) {
      children
        ..add(const SizedBox(height: 24))
        ..add(q);
    }
    final sq = _ra.secSimklQuickActions(0.55);
    if (sq != null) {
      children
        ..add(const SizedBox(height: 24))
        ..add(sq);
    }
    final mq = _ra.secMdblistQuickActions(0.555);
    if (mq != null) {
      children
        ..add(const SizedBox(height: 24))
        ..add(mq);
    }

    // ── Glass details card: production details + parents guide ──
    const detailStart = 0.56;
    final detailChildren = <Widget>[];
    final dt = _cr.secDetails(detailStart);
    if (dt != null) detailChildren.add(dt);
    final pg = _ra.secParentsGuide(detailStart);
    if (pg != null) {
      if (detailChildren.isNotEmpty) detailChildren.add(_ro.divider());
      detailChildren.add(pg);
    }
    if (detailChildren.isNotEmpty) {
      children
        ..add(const SizedBox(height: 24))
        ..add(
          CatalogReveal(
            parent: _deps.revealCtrl,
            start: detailStart,
            child: CatalogGlassCard(children: detailChildren),
          ),
        );
    }

    children.add(
      MetadataFranchiseRail(
        item: _deps.presentedItem(),
        onOpen: _deps.onRecommendationTap() == null
            ? null
            : _m.openMetadataRecommendation,
        isTelevision: _deps.isTelevision(),
      ),
    );
    final r = _ra.secRecommendations(0.66);
    if (r != null) {
      children
        ..add(const SizedBox(height: 28))
        ..add(r);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }
}
