import 'package:debrify/features/catalog_detail/presentation/catalog_cert_badge.dart';
import 'package:debrify/features/catalog_detail/presentation/catalog_genre_chip.dart';
import 'package:debrify/features/catalog_detail/presentation/catalog_metacritic_badge.dart';
import 'package:debrify/features/catalog_detail/presentation/catalog_reveal.dart';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_action_layout.dart';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_dependencies.dart';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_metadata.dart';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_root_layout.dart';
import 'package:debrify/services/metadata_details_service.dart';
import 'package:debrify/widgets/detail/theme/detail_theme.dart';
import 'package:debrify/widgets/shimmer.dart';
import 'package:flutter/material.dart';

class CatalogDetailHeroSections {
  final CatalogDetailDependencies _deps;

  CatalogDetailHeroSections(this._deps);

  CatalogDetailMetadata get _m => _deps.parts.metadata;

  CatalogDetailRootLayout get _ro => _deps.parts.rootLayout;

  CatalogDetailActionLayout get _a => _deps.parts.actionLayout;

  // ── Sections ──────────────────────────────────────────────────────────────
  Widget secEyebrow(double start) => CatalogReveal(
    parent: _deps.revealCtrl,
    start: start,
    child: Text(
      _deps.item().type == 'series' ? 'SERIES' : 'MOVIE',
      style: TextStyle(
        color: DetailThemeScope.maybeOf(_deps.context()).focus,
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 2.4,
        shadows: const [
          Shadow(color: Color(0x993B2A00), blurRadius: 12),
          Shadow(color: Color(0x66000000), blurRadius: 6),
        ],
      ),
    ),
  );

  Widget secTitle(double start) => CatalogReveal(
    parent: _deps.revealCtrl,
    start: start,
    child: Text(
      _deps.presentedItem().name,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: _ro.wide ? (_ro.tight ? 30 : 44) : 28,
        fontWeight: FontWeight.w900,
        letterSpacing: -1.0,
        height: 1.05,
        shadows: const [
          Shadow(
            color: Color(0xDD000000),
            blurRadius: 24,
            offset: Offset(0, 4),
          ),
          Shadow(color: Color(0x66000000), blurRadius: 8),
        ],
      ),
    ),
  );

  Widget secMeta(double start) {
    final item = _deps.presentedItem();
    final extra = _m.imdbExtra;
    final rating = extra?.rating ?? item.imdbRating;
    final year = item.year ?? extra?.year;
    final hasYear = year != null && year.isNotEmpty;
    final cert = extra?.certificate;
    final runtime = MetadataDetailsService.informationRuntime(
      item,
      extra,
      _deps.metadataPreferences(),
    );
    final voteCount = extra?.voteCountFormatted;
    final hasVotes = voteCount != null && voteCount.isNotEmpty;
    final showMetaShimmer = !_m.imdbLoaded && extra == null;
    return CatalogReveal(
      parent: _deps.revealCtrl,
      start: start,
      child: DefaultTextStyle(
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.78),
          fontSize: _ro.wide && !_ro.tight ? 14 : 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          shadows: const [
            Shadow(color: Color(0xBB000000), blurRadius: 10),
            Shadow(color: Color(0x55000000), blurRadius: 4),
          ],
        ),
        child: Wrap(
          spacing: 10,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (hasYear) Text(year),
            if (cert != null) ...[
              if (hasYear) _a.dot(),
              CatalogCertBadge(label: cert),
            ],
            if (runtime != null) ...[
              if (hasYear || cert != null) _a.dot(),
              Text(runtime),
            ],
            if (showMetaShimmer && cert == null && runtime == null) ...[
              if (hasYear) _a.dot(),
              Shimmer(
                width: 28,
                height: 16,
                borderRadius: BorderRadius.circular(4),
              ),
              _a.dot(),
              Shimmer(
                width: 48,
                height: 14,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
            if (rating != null) ...[
              if (hasYear || cert != null || runtime != null) _a.dot(),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.star_rounded, size: 16, color: Color(0xFFFACC15)),
                  const SizedBox(width: 4),
                  Text(rating.toStringAsFixed(1)),
                  if (hasVotes) ...[
                    const SizedBox(width: 3),
                    Text(
                      '($voteCount)',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: _ro.wide && !_ro.tight ? 12 : 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ] else if (showMetaShimmer) ...[
              if (hasYear || cert != null || runtime != null) _a.dot(),
              Shimmer(
                width: 60,
                height: 14,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
            if (extra?.metacriticScore != null) ...[
              _a.dot(),
              CatalogMetacriticBadge(score: extra!.metacriticScore!),
            ],
          ],
        ),
      ),
    );
  }

  Widget? secGenres(double start) {
    final genres = MetadataDetailsService.informationGenres(
      _deps.presentedItem(),
      _m.imdbExtra,
      _deps.metadataPreferences(),
    );
    if (genres.isEmpty) {
      if (_m.imdbLoaded) return null;
      return CatalogReveal(
        parent: _deps.revealCtrl,
        start: start,
        child: Wrap(
          spacing: 7,
          runSpacing: 7,
          children: const [
            Shimmer(
              width: 64,
              height: 28,
              borderRadius: BorderRadius.all(Radius.circular(14)),
            ),
            Shimmer(
              width: 52,
              height: 28,
              borderRadius: BorderRadius.all(Radius.circular(14)),
            ),
            Shimmer(
              width: 72,
              height: 28,
              borderRadius: BorderRadius.all(Radius.circular(14)),
            ),
          ],
        ),
      );
    }
    return CatalogReveal(
      parent: _deps.revealCtrl,
      start: start,
      child: Wrap(
        spacing: 7,
        runSpacing: 7,
        children: [for (final g in genres.take(5)) CatalogGenreChip(label: g)],
      ),
    );
  }

  Widget? secAwards(double start) {
    final extra = _m.imdbExtra;
    if (extra == null || !extra.hasAwards) return null;
    return CatalogReveal(
      parent: _deps.revealCtrl,
      start: start,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: _ro.tight ? 10 : 12,
          vertical: _ro.tight ? 6 : 8,
        ),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0x22FBBF24), Color(0x0AFBBF24)],
          ),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0x33FBBF24), width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.emoji_events_rounded,
              size: 16,
              color: Color(0xFFFBBF24),
            ),
            const SizedBox(width: 8),
            Text(
              extra.awardsLine!,
              style: TextStyle(
                color: const Color(0xFFFBBF24).withValues(alpha: 0.9),
                fontSize: _ro.tight ? 11 : 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
