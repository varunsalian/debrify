import 'package:debrify/features/catalog_detail/presentation/catalog_reveal.dart';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_cast_avatar.dart';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_dependencies.dart';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_metadata.dart';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_root_layout.dart';
import 'package:debrify/widgets/shimmer.dart';
import 'package:flutter/material.dart';

class CatalogDetailCreditsSections {
  final CatalogDetailDependencies _deps;

  CatalogDetailCreditsSections(this._deps);

  CatalogDetailMetadata get _m => _deps.parts.metadata;

  CatalogDetailRootLayout get _ro => _deps.parts.rootLayout;

  Widget? secCredits(double start) {
    final extra = _m.imdbExtra;
    if (extra == null) {
      if (_m.imdbLoaded) return null;
      final h = _ro.tight ? 10.0 : 12.0;
      return CatalogReveal(
        parent: _deps.revealCtrl,
        start: start,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Shimmer(
                  width: 60,
                  height: h,
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(width: 10),
                Shimmer(
                  width: 140,
                  height: h,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            ),
            SizedBox(height: _ro.tight ? 4 : 8),
            Row(
              children: [
                Shimmer(
                  width: 60,
                  height: h,
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(width: 10),
                Shimmer(
                  width: 200,
                  height: h,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            ),
          ],
        ),
      );
    }
    final hasDirector = extra.director != null && extra.director!.isNotEmpty;
    final hasStars = extra.stars.isNotEmpty;
    if (!hasDirector && !hasStars) return null;

    const sh = [Shadow(color: Color(0x55000000), blurRadius: 4)];
    final labelStyle = TextStyle(
      color: Colors.white.withValues(alpha: 0.45),
      fontSize: _ro.tight ? 11 : 12,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.3,
      shadows: sh,
    );
    final valueStyle = TextStyle(
      color: Colors.white.withValues(alpha: 0.85),
      fontSize: _ro.tight ? 11 : 12,
      fontWeight: FontWeight.w500,
      shadows: sh,
    );

    return CatalogReveal(
      parent: _deps.revealCtrl,
      start: start,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasDirector) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 70, child: Text('Director', style: labelStyle)),
                Expanded(child: Text(extra.director!, style: valueStyle)),
              ],
            ),
            if (hasStars) SizedBox(height: _ro.tight ? 4 : 6),
          ],
          if (hasStars)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 70, child: Text('Stars', style: labelStyle)),
                Expanded(
                  child: Text(
                    extra.stars.take(4).join(', '),
                    style: valueStyle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget? secCast(double start) {
    final cast = _m.imdbExtra?.cast ?? const [];
    if (cast.isEmpty) {
      if (_m.imdbLoaded) return null;
      return CatalogReveal(
        parent: _deps.revealCtrl,
        start: start,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            sectionHeader('CAST'),
            const SizedBox(height: 12),
            SizedBox(
              height: (_ro.tight ? 56.0 : 68.0) + 42,
              child: Row(
                children: [
                  for (var i = 0; i < 4; i++) ...[
                    if (i > 0) const SizedBox(width: 14),
                    Column(
                      children: [
                        Shimmer(
                          width: _ro.tight ? 56 : 68,
                          height: _ro.tight ? 56 : 68,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        const SizedBox(height: 6),
                        Shimmer(
                          width: 50,
                          height: 10,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }

    final avatarSize = _ro.tight ? 56.0 : 68.0;
    return CatalogReveal(
      parent: _deps.revealCtrl,
      start: start,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          sectionHeader('CAST'),
          const SizedBox(height: 12),
          SizedBox(
            height: avatarSize + 42,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              clipBehavior: Clip.none,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < cast.length; i++) ...[
                    if (i > 0) const SizedBox(width: 14),
                    CatalogCastAvatar(member: cast[i], size: avatarSize),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget? secDetails(double start) {
    final extra = _m.imdbExtra;
    if (extra == null) {
      if (_m.imdbLoaded) return null;
      return CatalogReveal(
        parent: _deps.revealCtrl,
        start: start,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            sectionHeader('DETAILS'),
            const SizedBox(height: 10),
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(height: 6),
              Row(
                children: [
                  Shimmer(
                    width: 70,
                    height: 11,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  const SizedBox(width: 10),
                  Shimmer(
                    width: 120,
                    height: 11,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ],
              ),
            ],
          ],
        ),
      );
    }

    final rows = <(String, String)>[];
    if (extra.countries.isNotEmpty) {
      rows.add(('Country', extra.countries.take(2).join(', ')));
    }
    if (extra.languages.isNotEmpty) {
      rows.add(('Language', extra.languages.take(3).join(', ')));
    }
    if (extra.productionCompany != null) {
      rows.add(('Studio', extra.productionCompany!));
    }
    if (extra.boxOffice != null) {
      rows.add(('Box Office', extra.boxOffice!));
    }
    if (rows.isEmpty) return null;

    final labelStyle = TextStyle(
      color: Colors.white.withValues(alpha: 0.40),
      fontSize: _ro.tight ? 11 : 12,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.3,
      shadows: const [Shadow(color: Color(0x55000000), blurRadius: 4)],
    );
    final valueStyle = TextStyle(
      color: Colors.white.withValues(alpha: 0.82),
      fontSize: _ro.tight ? 11 : 12,
      fontWeight: FontWeight.w500,
      shadows: const [Shadow(color: Color(0x55000000), blurRadius: 4)],
    );

    return CatalogReveal(
      parent: _deps.revealCtrl,
      start: start,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          sectionHeader('DETAILS'),
          SizedBox(height: _ro.tight ? 8 : 10),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) SizedBox(height: _ro.tight ? 4 : 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 78, child: Text(rows[i].$1, style: labelStyle)),
                Expanded(child: Text(rows[i].$2, style: valueStyle)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget sectionHeader(String label) {
    return Text(
      label,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.45),
        fontSize: _ro.tight ? 10 : 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 2.2,
        shadows: const [Shadow(color: Color(0x55000000), blurRadius: 4)],
      ),
    );
  }
}
