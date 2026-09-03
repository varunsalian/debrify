import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/home_collection.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_theme_scope.dart';

/// The folder's backdrop and title logo above its lists. Files without a
/// dedicated backdrop fall back to the cover art; without a logo the title
/// is set in text. Renders nothing for a folder with no art at all.
class FolderHeroBand extends StatelessWidget {
  final HomeCollectionFolder folder;
  final bool isTelevision;

  const FolderHeroBand({
    super.key,
    required this.folder,
    this.isTelevision = false,
  });

  @override
  Widget build(BuildContext context) {
    final backdrop = folder.heroBackdropUrl ?? folder.coverImageUrl;
    final logo = folder.titleLogoUrl;
    if (backdrop == null && logo == null) return const SizedBox.shrink();
    final app = AppThemeScope.of(context);
    final bg = app.seeAll.bg;
    final height = isTelevision ? 150.0 : 110.0;
    final logoHeight = isTelevision ? 56.0 : 44.0;

    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (backdrop != null)
            CachedNetworkImage(
              imageUrl: backdrop,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              memCacheWidth: 1280,
              errorWidget: (_, __, ___) => const SizedBox.shrink(),
            ),
          // Fade the still into the page ground so the filter line below
          // reads on a settled surface, and keep the logo's corner legible.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [bg.withValues(alpha: 0.25), bg],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [bg.withValues(alpha: 0.7), bg.withValues(alpha: 0)],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Align(
              alignment: Alignment.bottomLeft,
              child: logo != null
                  ? CachedNetworkImage(
                      imageUrl: logo,
                      height: logoHeight,
                      fit: BoxFit.contain,
                      alignment: Alignment.bottomLeft,
                      errorWidget: (_, __, ___) => _title(app),
                    )
                  : _title(app),
            ),
          ),
        ],
      ),
    );
  }

  Widget _title(AppTheme app) => Text(
    folder.title,
    style: TextStyle(
      color: app.core.tx,
      fontSize: isTelevision ? 26 : 22,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.3,
    ),
  );
}
