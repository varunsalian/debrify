import 'dart:math' show min;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../models/stremio_addon.dart';
import '../../../models/hero_metadata_presentation.dart';
import '../../../theme/app_theme_scope.dart';
import '../application/home_stage_metadata.dart';

/// Shared with the Mosaic band so its reserved height matches this view.
const double homeStageHeadlineLogoHeight = 52;

/// The headline text fallback is smaller than a stage title: a caption over
/// the wall. Shared with the band's height calculation so it cannot drift.
const double homeStageHeadlineTitleSize = 24;

/// How a stage sets its identity block.
enum HomeStageIdentityVariant {
  /// Canvas / Deck / Tonight: bottom-left, one meta line, three-line synopsis.
  stage,

  /// Atrium: a narrow ink column — the meta breaks onto two lines (facts, then
  /// genres) so it can never overrun the column, and the synopsis gets a
  /// fourth line because there is room for it.
  narrow,

  /// Promenade: centred, no synopsis — the composition is the point.
  centered,

  /// Mosaic: a fixed-height band above the wall — logo and one meta line,
  /// left-aligned, no synopsis (the grid is the content; this is a caption).
  headline,
}

/// The height a [HomeStageIdentityVariant.narrow] block needs before its synopsis
/// is worth reserving: logo, two meta lines, the slot itself and the air
/// between them, at the current text scale. Below this the caller asks for
/// [HomeStageIdentityVariant.headline] instead of clipping.
double homeStageNarrowIdentityHeight(BuildContext context) {
  final t = MediaQuery.textScalerOf(context);
  return 56 + 10 + t.scale(23) * 1.3 * 2 + 6 + 10 + 78;
}

/// Canvas identity block: logo title-art (held EMPTY while loading, text only
/// when there's no URL or it 404s — the C5 "no text→logo flash" rule) over a
/// quiet meta line with the gold IMDb mark and a three-line synopsis. While
/// the ambient trailer plays, meta + synopsis fade away and the LOGO HOLDS
/// THE STAGE (the classic hero's premium move); any DPAD move brings them
/// back with the lights.
class HomeStageIdentity extends StatelessWidget {
  final ValueListenable<StremioMeta?> item;
  final ValueListenable<StremioMeta?> enriched;

  /// True while ambient video owns the stage — drives the meta/synopsis fade.
  final ValueListenable<bool> trailerShowing;

  final HomeStageIdentityVariant variant;

  /// Width the block may occupy — the text column's real width, so the logo
  /// and synopsis are capped by geometry rather than by a guess.
  final double maxWidth;

  const HomeStageIdentity({
    super.key,
    required this.item,
    required this.enriched,
    required this.trailerShowing,
    this.variant = HomeStageIdentityVariant.stage,
    this.maxWidth = 430,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final centered = variant == HomeStageIdentityVariant.centered;
    final narrow = variant == HomeStageIdentityVariant.narrow;
    final headline = variant == HomeStageIdentityVariant.headline;
    final noSynopsis = centered || headline;
    // The stage variant is Canvas's, and Canvas never capped its title or
    // meta line — only the synopsis. Keep that exactly, or long logo-less
    // titles start ellipsising where they never used to.
    final capWidth = variant != HomeStageIdentityVariant.stage;
    Widget capped(Widget child) => capWidth
        ? ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: child,
          )
        : child;
    final cross = centered
        ? CrossAxisAlignment.center
        : CrossAxisAlignment.start;
    final align = centered ? TextAlign.center : TextAlign.start;
    final double logoMaxW = centered
        ? 380
        : min(maxWidth, narrow ? 340 : (headline ? 360 : 300));
    final double logoMaxH = centered
        ? 66
        : (headline ? homeStageHeadlineLogoHeight : 56);
    // Fixed synopsis slot (see below) — 3 lines on a stage, 4 in a column.
    final int synLines = narrow ? 4 : 3;
    final double synSlot = narrow ? 78 : 58;

    return ValueListenableBuilder<StremioMeta?>(
      valueListenable: item,
      builder: (context, it, _) => ValueListenableBuilder<StremioMeta?>(
        valueListenable: enriched,
        builder: (context, en, _) {
          final it0 = it;
          if (it0 == null) return const SizedBox.shrink();
          // Enrichment merged over the catalog item FIELD BY FIELD: matched
          // by canonical IMDb identity (catalog ids can be tmdb:… while the
          // /meta record is tt…), and a sparse /meta response — it may carry
          // only a rating — can never erase what the catalog already knew.
          final enr = (en != null && sameHomeStageTitle(it0, en)) ? en : null;
          final fields = HeroMetadataFields(it0, enr);
          final logo =
              fields.logo ??
              (fields.allowArtworkFallback ? homeStageLogoUrl(it0) : null);
          final rating = enr?.imdbRating ?? it0.imdbRating;
          final year = homeStageFirstNonEmpty(enr?.year, it0.year);
          final runtime = fields.runtime;
          final genres = fields.genres;
          final description = fields.description;
          final titleText = Text(
            fields.name,
            maxLines: narrow ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            textAlign: align,
            style: TextStyle(
              color: app.core.tx,
              fontSize: headline ? homeStageHeadlineTitleSize : 30,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
              height: 1.05,
              shadows: const [Shadow(color: Colors.black54, blurRadius: 14)],
            ),
          );
          final genreText = (genres != null && genres.isNotEmpty)
              ? genres.take(2).join(' · ')
              : null;
          // The narrow column splits the line rather than ellipsising it.
          final metaParts = <String>[
            it0.type == 'series' ? 'SERIES' : 'MOVIE',
            if (year != null) year,
            if (runtime != null) runtime,
            if (!narrow && !headline && genreText != null) genreText,
          ];
          // Headline stands in for narrow on short columns, so it wraps the
          // genres the same way — in the facts row they would just be the
          // first thing ellipsised away.
          final wrapGenres = narrow || headline;
          final metaStyle = TextStyle(
            color: app.fade(app.core.tx, 0.7),
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          );
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            // AnimatedSwitcher's DEFAULT layout centers its child — which
            // floated the whole identity block to mid-screen, off the left
            // scrim column it was designed to stand on. Pin it to the edge
            // the variant is anchored to.
            layoutBuilder: (currentChild, previousChildren) => Stack(
              alignment: centered
                  ? Alignment.bottomCenter
                  : Alignment.bottomLeft,
              children: [
                ...previousChildren,
                if (currentChild != null) currentChild,
              ],
            ),
            child: Column(
              key: ValueKey('canvas-id-${it0.id}'),
              crossAxisAlignment: cross,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (logo != null)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: logoMaxW,
                      maxHeight: logoMaxH,
                    ),
                    child: CachedNetworkImage(
                      imageUrl: logo,
                      fit: BoxFit.contain,
                      alignment: centered
                          ? Alignment.bottomCenter
                          : Alignment.bottomLeft,
                      memCacheWidth: 480,
                      fadeInDuration: Duration.zero,
                      fadeOutDuration: Duration.zero,
                      placeholder: (_, __) => SizedBox(height: logoMaxH),
                      errorWidget: (_, __, ___) => capped(titleText),
                    ),
                  )
                else
                  capped(titleText),
                const SizedBox(height: 10),
                // Meta + synopsis fade while the ambient trailer plays; the
                // logo above stays. Sibling-above-the-hole opacity — the
                // on-device-proven overlay pattern (region feathers/chip).
                ValueListenableBuilder<bool>(
                  valueListenable: trailerShowing,
                  builder: (context, showing, kid) => AnimatedOpacity(
                    opacity: showing ? 0.0 : 1.0,
                    duration: const Duration(milliseconds: 480),
                    curve: Curves.easeOut,
                    child: kid,
                  ),
                  child: Column(
                    crossAxisAlignment: cross,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      capped(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: centered
                              ? MainAxisAlignment.center
                              : MainAxisAlignment.start,
                          children: [
                            if (rating != null) ...[
                              const Text(
                                'IMDb',
                                style: TextStyle(
                                  color: Color(0xFFF5C518),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                rating.toStringAsFixed(1),
                                style: TextStyle(
                                  color: app.fade(app.core.tx, 0.9),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                child: Text(
                                  '·',
                                  style: TextStyle(
                                    color: app.fade(app.core.tx, 0.3),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                            Flexible(
                              child: Text(
                                metaParts.join('  ·  '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: metaStyle,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Narrow columns carry genres on their own line rather
                      // than ellipsising the facts away.
                      if (wrapGenres && genreText != null) ...[
                        const SizedBox(height: 6),
                        capped(
                          Text(
                            genreText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: metaStyle.copyWith(
                              color: app.fade(app.core.tx, 0.46),
                            ),
                          ),
                        ),
                      ],
                      // Fixed-height synopsis slot: the description usually
                      // lands ~300ms after the settle (/meta enrichment), and
                      // this block is BOTTOM-anchored — reserving the lines
                      // keeps the logo from jumping when the text arrives.
                      // Promenade has no synopsis at all, so it reserves
                      // nothing.
                      if (!noSynopsis) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          height: synSlot,
                          child: description != null
                              ? ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: maxWidth,
                                  ),
                                  child: Text(
                                    description,
                                    maxLines: synLines,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: app.fade(app.core.tx, 0.78),
                                      fontSize: 12.5,
                                      height: 1.5,
                                      fontWeight: FontWeight.w500,
                                      // Crisp, tight shadow — a seasoning under
                                      // the scrim, never a smear (big radii
                                      // read as muddy text on TV panels).
                                      shadows: const [
                                        Shadow(
                                          color: Color(0xBF000000),
                                          blurRadius: 3,
                                          offset: Offset(0, 1),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
