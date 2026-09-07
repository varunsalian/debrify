import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/stremio_addon.dart';
import '../../theme/app_theme_scope.dart';

/// Passive Home takeover identity. Signals are borrowed, never disposed here.
class HeroTakeoverInfo extends StatelessWidget {
  const HeroTakeoverInfo({
    super.key,
    required this.heroItem,
    required this.heroEnriched,
    required this.takeoverSignal,
  });

  final ValueListenable<StremioMeta?> heroItem;
  final ValueListenable<StremioMeta?> heroEnriched;
  final ValueListenable<double> takeoverSignal;

  /// The takeover's kinetic lower-third: while the film owns the board its
  /// identity sits bottom-left — a growing accent bar, then a whispered kicker,
  /// a big uppercase title, a `year · runtime · ★rating` line and the genres,
  /// each rising in a staggered cascade timed to the mask-open. Purely
  /// informational (IgnorePointer, no focus nodes); every field degrades to
  /// nothing when absent. The text subtrees are built only when the hero item /
  /// enrichment changes and captured as locals — the per-frame builder just
  /// wraps them in cheap Opacity/Transform, never a full-screen save layer.
  @override
  Widget build(BuildContext context) {
    final themeContext = context;
    final app = AppThemeScope.of(context);
    const accentLight = Color(0xFFC4B5FD);
    return ValueListenableBuilder<StremioMeta?>(
      valueListenable: heroItem,
      builder: (context, item, __) {
        if (item == null) return const SizedBox.shrink();
        return ValueListenableBuilder<StremioMeta?>(
          valueListenable: heroEnriched,
          builder: (context, enriched, ___) {
            final rating = item.imdbRating ?? enriched?.imdbRating;
            final runtime = item.runtimeDisplay ?? enriched?.runtimeDisplay;
            final genres = item.genres?.isNotEmpty == true
                ? item.genres
                : enriched?.genres;

            // year · runtime · ★rating — assembled once per item change.
            final meta = <Widget>[];
            void sep() {
              if (meta.isNotEmpty) meta.add(_metaDot(themeContext));
            }

            if (item.year != null && item.year!.isNotEmpty) {
              meta.add(_metaText(themeContext, item.year!));
            }
            if (runtime != null && runtime.isNotEmpty) {
              sep();
              meta.add(_metaText(themeContext, runtime));
            }
            if (rating != null) {
              sep();
              meta.add(
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.star_rounded, size: 17, color: app.home.focus),
                    const SizedBox(width: 4),
                    _metaText(themeContext, rating.toStringAsFixed(1)),
                  ],
                ),
              );
            }

            final kicker = Text(
              'NOW PLAYING  ·  OFFICIAL TRAILER',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 4,
                color: accentLight,
                shadows: [Shadow(color: Colors.black87, blurRadius: 8)],
              ),
            );
            final title = Text(
              item.name.toUpperCase(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                fontSize: 46,
                fontWeight: FontWeight.w800,
                height: 0.98,
                letterSpacing: -0.5,
                color: app.core.tx,
                shadows: const [
                  Shadow(
                    color: Colors.black87,
                    blurRadius: 18,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
            );
            final metaRow = Row(mainAxisSize: MainAxisSize.min, children: meta);
            final genresLine = (genres == null || genres.isEmpty)
                ? const SizedBox.shrink()
                : Text(
                    genres.take(3).join('   •   ').toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 3,
                      color: app.fade(app.core.tx, 0.6),
                      shadows: const [
                        Shadow(color: Colors.black87, blurRadius: 8),
                      ],
                    ),
                  );

            return ValueListenableBuilder<double>(
              valueListenable: takeoverSignal,
              builder: (context, takeover, ____) {
                if (takeover <= 0.001) return const SizedBox.shrink();
                double seg(double a, double b) =>
                    ((takeover - a) / (b - a)).clamp(0.0, 1.0);
                double eo(double x) {
                  final u = 1 - x;
                  return 1 - u * u * u;
                }

                // Each element rises + fades over its own window of the arc.
                Widget rise(Widget w, double a, double b, {double dist = 14}) {
                  final p = seg(a, b);
                  return Opacity(
                    opacity: p,
                    child: Transform.translate(
                      offset: Offset(0, (1 - eo(p)) * dist),
                      child: w,
                    ),
                  );
                }

                final accentP = eo(seg(0.42, 0.72));
                final slideP = eo(seg(0.42, 0.78));

                return IgnorePointer(
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(52, 0, 48, 54),
                      child: IntrinsicHeight(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Accent bar grows up from the foot of the block.
                            Transform(
                              alignment: Alignment.bottomCenter,
                              transform: Matrix4.diagonal3Values(1, accentP, 1),
                              child: Container(
                                width: 5,
                                decoration: BoxDecoration(
                                  borderRadius: app.shape.br(4),
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      app.home.chromeAccent,
                                      accentLight,
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 20),
                            // The whole text block slides in from the left.
                            Transform.translate(
                              offset: Offset(-46 * (1 - slideP), 0),
                              child: Opacity(
                                opacity: seg(0.42, 0.6),
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 720,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      rise(kicker, 0.44, 0.6, dist: 8),
                                      const SizedBox(height: 12),
                                      rise(title, 0.5, 0.8),
                                      if (meta.isNotEmpty) ...[
                                        const SizedBox(height: 14),
                                        rise(metaRow, 0.66, 0.9, dist: 12),
                                      ],
                                      if (genres != null &&
                                          genres.isNotEmpty) ...[
                                        const SizedBox(height: 10),
                                        rise(genresLine, 0.76, 1.0, dist: 10),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  /// A metadata token in the takeover's lower-third meta line.
  Widget _metaText(BuildContext context, String s) {
    final app = AppThemeScope.of(context);
    return Text(
      s,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: app.fade(app.core.tx, 0.9),
        shadows: const [Shadow(color: Colors.black87, blurRadius: 8)],
      ),
    );
  }

  /// The dot separator between takeover meta tokens.
  Widget _metaDot(BuildContext context) {
    final app = AppThemeScope.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Container(
        width: 4,
        height: 4,
        decoration: BoxDecoration(
          color: app.fade(app.core.tx, 0.45),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
