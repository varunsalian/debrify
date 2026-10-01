import 'package:flutter/material.dart';
import '../../../models/home_collection_rows.dart';
import '../../../models/stremio_addon.dart';
import '../../../theme/app_theme_scope.dart';
import '../../../widgets/home/card_focus_rise.dart' show kCardFocusRing;

/// Hold-OK feedback layer — a dim scrim with a filling ring, shown only
/// while OK is actually held down (so it costs nothing at rest). Shared by
/// the poster and wide layer sets.
class HomeCardHoldLayer extends StatelessWidget {
  const HomeCardHoldLayer({super.key, required this.progress});
  final Animation<double> progress;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.42),
          child: Center(
            child: SizedBox(
              width: 34,
              height: 34,
              child: AnimatedBuilder(
                animation: progress,
                builder: (_, __) => CircularProgressIndicator(
                  value: progress.value,
                  strokeWidth: 3,
                  backgroundColor: Colors.white.withValues(alpha: 0.22),
                  valueColor: const AlwaysStoppedAnimation(kCardFocusRing),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The card surface shown while artwork loads or is missing: a static
/// gradient with the collection emoji or, when titles are shown, the name.
class HomeCardPlaceholder extends StatelessWidget {
  const HomeCardPlaceholder({
    super.key,
    required this.item,
    required this.showTitle,
  });
  final StremioMeta item;
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final item = this.item; // local, so the folder check below promotes
    final title = item.name;
    final emoji = item is CollectionFolderMeta ? item.folder.coverEmoji : null;
    return Container(
      // Subtle vertical gradient instead of a flat fill: while art loads the
      // tile reads as a designed surface, not a dead rectangle. Static —
      // no shimmer, so a board full of placeholders costs nothing per frame.
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1D1B2E), Color(0xFF15141F), Color(0xFF100E18)],
          stops: [0.0, 0.55, 1.0],
        ),
      ),
      alignment: Alignment.center,
      child: emoji != null
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: FittedBox(
                child: Text(emoji, style: const TextStyle(fontSize: 64)),
              ),
            )
          : showTitle
          ? Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: app.fade(app.core.tx, 0.5),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          : null,
    );
  }
}
