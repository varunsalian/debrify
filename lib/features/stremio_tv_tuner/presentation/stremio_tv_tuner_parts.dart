import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';

/// Stage synopsis with "Read more" sheet for mobile.
class StremioTvTunerStageDescription extends StatelessWidget {
  final String text;
  final String title;
  final Color ident;
  final bool interactive;

  const StremioTvTunerStageDescription({
    required this.text,
    required this.title,
    required this.ident,
    required this.interactive,
  });

  TextStyle _styleOf(AppTheme app) => TextStyle(
    color: app.core.tx.withAlpha(0xC8),
    fontSize: 17,
    height: 1.5,
    shadows: const [Shadow(blurRadius: 8, color: Colors.black)],
  );

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final style = _styleOf(app);
    if (!interactive) {
      return Text(
        text,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    return LayoutBuilder(
      builder: (context, c) {
        final tp = TextPainter(
          text: TextSpan(text: text, style: style),
          maxLines: 3,
          textDirection: Directionality.of(context),
        )..layout(maxWidth: c.maxWidth);
        final overflows = tp.didExceedMaxLines;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
            if (overflows) ...[
              const SizedBox(height: 6),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _showFull(context),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Read more',
                      style: TextStyle(
                        color: app.core.tx.withValues(alpha: 0.95),
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Icon(
                      Icons.expand_more_rounded,
                      size: 18,
                      color: app.core.tx.withValues(alpha: 0.95),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  void _showFull(BuildContext context) {
    // Captured from the calling context — the sheet route is not under this
    // surface's theme boundary.
    final app = AppThemeScope.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: app.stremioTv.sheetBg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.35,
        maxChildSize: 0.92,
        expand: false,
        builder: (ctx, scrollCtrl) => Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: app.core.tx.withAlpha(0x3D),
                borderRadius: app.shape.br(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 26,
                    decoration: BoxDecoration(
                      color: ident,
                      borderRadius: app.shape.br(2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: app.core.tx,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: Text(
                  text,
                  style: TextStyle(
                    color: app.core.tx.withValues(alpha: 0.82),
                    fontSize: 15,
                    height: 1.45,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class StremioTvTunerLivePip extends StatelessWidget {
  final Color color;
  const StremioTvTunerLivePip({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: const BoxDecoration(
        color: Color(0xFFFF3B5C),
        shape: BoxShape.circle,
      ),
    );
  }
}

// =========================================================================
// Marquee — auto-scrolling text for overflowing labels.
// =========================================================================

class StremioTvTunerMarquee extends StatelessWidget {
  final String text;
  final TextStyle style;

  const StremioTvTunerMarquee({required this.text, required this.style});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: style,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Small glassy affordance shown on the active dial card telling the user how
/// to open the quick-actions sheet (DOWN on TV, right-click on desktop).
class StremioTvTunerDialHintChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const StremioTvTunerDialHintChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: app.shape.br(6),
        border: Border.all(
          color: app.onGlass.withValues(alpha: 0.16),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: app.onGlass.withValues(alpha: 0.85)),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              color: app.onGlass.withValues(alpha: 0.85),
              fontSize: 8,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
