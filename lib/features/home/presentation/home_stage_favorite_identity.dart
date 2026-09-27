import 'package:flutter/material.dart';
import '../../../theme/app_theme_scope.dart';
import 'home_favorite_focus.dart';

/// The identity block a stage shows while a FAVOURITES cell has focus.
/// Favourites aren't StremioMeta, so the logo/meta/synopsis pipeline has
/// nothing true to say about them — this is the favourite's own name and
/// source line, in the same type as the catalog identity above it.
class HomeStageFavoriteIdentity extends StatelessWidget {
  final HomeFavoriteFocus fav;
  final bool centered;

  const HomeStageFavoriteIdentity({
    super.key,
    required this.fav,
    this.centered = false,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return Column(
      crossAxisAlignment: centered
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          fav.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: centered ? TextAlign.center : TextAlign.start,
          style: TextStyle(
            color: app.core.tx,
            fontSize: 26,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.4,
            height: 1.1,
            shadows: const [Shadow(color: Colors.black54, blurRadius: 14)],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          fav.subtitle,
          textAlign: centered ? TextAlign.center : TextAlign.start,
          style: TextStyle(
            color: app.fade(app.core.tx, 0.6),
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
      ],
    );
  }
}
