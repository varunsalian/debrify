import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../theme/app_theme_scope.dart';
import '../../../ui/core/see_all_link.dart';
import '../../../widgets/home/row_tag_pill.dart';

/// Shared by the rendered heading and the classic row's line-height measurement.
TextStyle homeCatalogRowTitleStyle(
  BuildContext context, {
  required double fontSize,
}) {
  final app = AppThemeScope.of(context);
  return GoogleFonts.poppins(
    fontSize: fontSize,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    color: app.fade(app.core.tx, 0.92),
  );
}

/// Shared header for a board rail: a "Popular Movies"-style title with the
/// source riding beside it as a small [RowTagPill]. The "See All" link is a
/// mouse/tap affordance shown off TV; TV paginates as the user scrolls.
Widget buildHomeCatalogRowHeader(
  BuildContext context, {
  required bool isTelevision,
  required String title,
  String? tag,
  VoidCallback? onSeeAll,
}) {
  final compact = !isTelevision && MediaQuery.sizeOf(context).width < 480;
  return Padding(
    // Tighter vertically on TV so the current row's header + a peek of the
    // next row fit under the hero on short-canvas panels.
    padding: EdgeInsets.fromLTRB(
      compact ? 16 : 24,
      isTelevision ? 14 : 22,
      compact ? 16 : 24,
      isTelevision ? 10 : 12,
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          // One shape for every tier now: title + provenance pill. The tag
          // used to render as a second line (compact) / a dot-suffix (wide)
          // back when it was the content type; as the ADDON it reads as
          // provenance, and the pill keeps it a footnote on all three tiers
          // (the same chip the Spotlight board's headings wear).
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  // Poppins for the rail titles too, so headings share one
                  // display face. TV runs them quieter (15px) — the hero
                  // carries the weight, the row title just labels the shelf
                  // (Nuvio's row grammar).
                  style: homeCatalogRowTitleStyle(
                    context,
                    fontSize: isTelevision || compact ? 15 : 17,
                  ),
                ),
              ),
              if (tag != null) ...[
                const SizedBox(width: 8),
                // Intrinsic width under a hard cap — a second Flexible here
                // would halve the title's max width and wrap it (the
                // Spotlight heading hit exactly that).
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 150),
                  child: RowTagPill(tag, fontSize: 9.5),
                ),
              ],
            ],
          ),
        ),
        if (onSeeAll != null && !isTelevision)
          SeeAllLink(onTap: onSeeAll, compact: compact),
      ],
    ),
  );
}
