import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';

/// A row heading that leads somewhere: the title with the reference's chevron
/// set immediately after the words, the pair acting as one tap target.
///
/// The placement is the whole point. Our other boards park a "See All" pill
/// out at the row's trailing edge, where it reads as a button laid across the
/// row; Apple hangs a chevron off the last word, so the heading itself becomes
/// the door. It is also quieter than the words it follows — the heading is
/// already held at 0.84 of the ink, and this sits under that again — so it
/// points somewhere without competing with the posters beneath it.
///
/// Sized off the heading rather than fixed: the icon box has to run larger
/// than the type for the drawn chevron to match its cap height, since the
/// glyph fills a little over half its box.
///
/// Pointer surfaces only. TV never builds this (see [SpotlightBoard.dpad]),
/// and a shelf with no See-All draws a plain heading — the reference leaves
/// its own dead-end rows bare too.
class SpotlightShelfTitleLink extends StatefulWidget {
  final String title;
  final TextStyle style;
  final double fontSize;
  final VoidCallback onTap;

  const SpotlightShelfTitleLink({
    required this.title,
    required this.style,
    required this.fontSize,
    required this.onTap,
  });

  @override
  State<SpotlightShelfTitleLink> createState() =>
      SpotlightShelfTitleLinkState();
}

class SpotlightShelfTitleLinkState extends State<SpotlightShelfTitleLink> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    // Rests under the heading and comes up to meet it on hover — the whole
    // hover story, since a fill or an underline here would put chrome back
    // on a heading whose point is that it has none.
    final chevron = app.core.tx.withValues(alpha: _hover ? 0.84 : 0.5);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Flexible + one line: a long row title ellipsizes instead of
            // wrapping under itself or shoving the chevron off the gutter.
            Flexible(
              child: Text(
                widget.title,
                style: widget.style,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(width: widget.fontSize * 0.18),
            Icon(
              Icons.chevron_right_rounded,
              size: widget.fontSize * 1.25,
              color: chevron,
            ),
          ],
        ),
      ),
    );
  }
}
