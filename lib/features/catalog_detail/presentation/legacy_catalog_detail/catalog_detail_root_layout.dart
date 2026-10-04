import 'package:debrify/features/catalog_detail/presentation/catalog_backdrop.dart';
import 'package:debrify/features/catalog_detail/presentation/catalog_glass_icon_button.dart';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_content_columns.dart';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_dependencies.dart';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_metadata.dart';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_resources.dart';
import 'package:debrify/screens/metadata_explore_page.dart';
import 'package:debrify/services/metadata_details_service.dart';
import 'package:debrify/theme/artwork_accent.dart';
import 'package:debrify/utils/artwork_url.dart';
import 'package:flutter/material.dart';

class CatalogDetailRootLayout {
  final CatalogDetailDependencies _deps;

  CatalogDetailRootLayout(this._deps);

  CatalogDetailResources get _f => _deps.parts.resources;

  CatalogDetailMetadata get _m => _deps.parts.metadata;

  CatalogDetailContentColumns get _co => _deps.parts.contentColumns;

  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isWide = wide;
    // The detail backdrop is a display-sized hero, not a shelf card. Upgrade
    // MetaHub's catalog-sized art here without changing the item's shared
    // poster URL (recommendation shelves continue to use their medium source).
    final backdropUrl = highQualityArtworkUrl(
      MetadataDetailsService.backdrop(
        _deps.presentedItem(),
        _deps.metadataPreferences(),
      ),
    );

    return ArtworkAccentScope(
      accent: _m.artworkAccent,
      child: buildBody(context, size, isWide, backdropUrl),
    );
  }

  Widget buildBody(
    BuildContext context,
    Size size,
    bool isWide,
    String? backdropUrl,
  ) {
    return Scaffold(
      floatingActionButton: MetadataExploreButton(
        item: _deps.presentedItem(),
        onOpen: _deps.onRecommendationTap(),
        isTelevision: _deps.isTelevision(),
      ),
      backgroundColor: const Color(0xFF050507),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Backdrop ─────────────────────────────────────────────────────
          // Wide screens: full-bleed. Narrow: top half only.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: isWide ? size.height : size.height * 0.62,
            child: CatalogBackdrop(
              url: backdropUrl,
              isWide: isWide,
              animate: !_deps.isTelevision(),
            ),
          ),

          // ── Content ──────────────────────────────────────────────────────
          // On wide layouts, content gravitates to the bottom-left third
          // (Apple-TV/Netflix style). On narrow it scrolls under the
          // backdrop normally.
          SafeArea(
            child: isWide ? buildWideContent(size) : buildNarrowContent(size),
          ),

          // ── Back button ──────────────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.all(_deps.isTelevision() ? 28 : 8),
                child: CatalogGlassIconButton(
                  icon: Icons.arrow_back_rounded,
                  onTap: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildNarrowContent(Size size) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.only(top: size.height * 0.30, bottom: 48),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: _co.buildNarrowColumn(),
      ),
    );
  }

  Widget buildWideContent(Size size) {
    // Content sheet bottom-left over the full-bleed art. TVs overscan, so
    // keep it well off the physical bezel — including the top: when the
    // content is tall enough to fill the sheet (expanded synopsis + quick
    // actions + recs) the eyebrow/title reach the top edge and the TV
    // overscan clips them, so mirror the bottom inset there.
    final tv = _deps.isTelevision();
    final maxWidth = (size.width * 0.56).clamp(440.0, 760.0);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        tv ? 64 : 48,
        tv ? 44 : 0,
        tv ? 48 : 24,
        tv ? 44 : 40,
      ),
      child: Align(
        alignment: Alignment.bottomLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(
              _deps.context(),
            ).copyWith(scrollbars: false),
            child: SingleChildScrollView(
              controller: _f.wideScroll,
              physics: const BouncingScrollPhysics(),
              // Don't clip the focus glow on Play/Sources/quick actions.
              clipBehavior: Clip.none,
              child: _co.buildContentColumn(),
            ),
          ),
        ),
      ),
    );
  }

  /// The cinematic bottom-left sheet is the premium look for landscape
  /// screens (incl. TV). Portrait/narrow windows use the single-scroll
  /// phone layout instead.
  bool get wide {
    if (_deps.isTelevision()) return true;
    final s = MediaQuery.of(_deps.context()).size;
    return s.width >= 900 && s.width > s.height;
  }

  /// Limited vertical space (Android TV is only ~540 logical px tall at
  /// DPR 2.0) — shrink typography/spacing so the cinematic layout still
  /// fits on one screen instead of overflowing.
  bool get tight => MediaQuery.of(_deps.context()).size.height < 620;

  Widget divider() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Container(
      height: 0.5,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0x00FFFFFF),
            Color(0x18FFFFFF),
            Color(0x18FFFFFF),
            Color(0x00FFFFFF),
          ],
          stops: [0.0, 0.2, 0.8, 1.0],
        ),
      ),
    ),
  );
}
