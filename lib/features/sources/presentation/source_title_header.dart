import 'package:flutter/material.dart';
import '../../../theme/app_theme_scope.dart';

/// Title and dimmed poster for non-keyword Sources; visibility stays with the view.
class SourceTitleHeader extends StatelessWidget {
  const SourceTitleHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.poster,
  });

  final String title;
  final String subtitle;
  final String? poster;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final bg = app.home.bg;
    final poster = this.poster;
    return SizedBox(
      height: 128,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (poster != null && poster.isNotEmpty)
            Image.network(
              poster,
              fit: BoxFit.cover,
              // Decode at a capped width — the hero is only a ~128px strip, so a
              // full-res poster is wasted memory (and OOMs 2GB TV boxes).
              cacheWidth: 640,
              filterQuality: FilterQuality.low,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                // Byte-exact fades of the page ink: 0x59 and 0x8C of 0xFF.
                colors: [
                  app.fade(bg, 0x59 / 0xFF),
                  app.fade(bg, 0x8C / 0xFF),
                  bg,
                ],
                stops: const [0.0, 0.55, 1.0],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: app.core.tx,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: app.fade(app.core.tx, 0.62),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
