import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/home_collection.dart';
import '../../models/stremio_addon.dart';
import '../../services/debrify_image_cache.dart';
import '../../theme/app_theme_scope.dart';
import 'collection_list_gallery.dart';
import 'collection_focus_art.dart';

/// Compact cinematic header; short landscape screens keep room for browsing.
class CollectionBrowserHero extends StatelessWidget {
  const CollectionBrowserHero({
    super.key,
    required this.collectionTitle,
    required this.folder,
    required this.listCount,
    required this.backNode,
    required this.onDown,
    this.listTitle,
    this.source,
    this.backdrop,
    this.item,
    this.action,
    this.onRight,
  });
  final String collectionTitle;
  final HomeCollectionFolder? folder;
  final String? listTitle, source, backdrop;
  final int listCount;
  final StremioMeta? item;
  final FocusNode backNode;
  final VoidCallback onDown;
  final Widget? action;
  final VoidCallback? onRight;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.height < 480;
    final narrow = size.width < 600;
    final app = AppThemeScope.of(context);
    final bg = app.seeAll.bg;
    final image = folder?.heroBackdropUrl ?? backdrop ?? folder?.coverImageUrl;
    final logo = folder?.titleLogoUrl;
    final video = Uri.tryParse(folder?.heroVideoUrl ?? '');
    final hasVideo =
        video != null &&
        video.host.isNotEmpty &&
        (video.scheme == 'https' || video.scheme == 'http');
    final title = listTitle ?? folder?.title ?? collectionTitle;
    final textGrowth = (MediaQuery.textScalerOf(context).scale(34) - 34).clamp(
      0.0,
      68.0,
    );
    final height = compact
        ? 110.0 + textGrowth
        : (size.height * .26).clamp(170.0, 240.0) +
              textGrowth * 2 +
              (logo != null ? 24 : 0);
    Widget network(String url, {BoxFit fit = BoxFit.cover, Widget? fallback}) =>
        CachedNetworkImage(
          imageUrl: url,
          cacheManager: DebrifyImageCache.manager,
          fit: fit,
          memCacheWidth: fit == BoxFit.cover ? 1280 : 400,
          placeholder: (_, _) => const SizedBox.shrink(),
          errorWidget: (_, _, _) => fallback ?? const SizedBox.shrink(),
        );
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (item != null)
            CollectionPreviewArt(item: item!, wide: true)
          else if (image != null)
            network(image),
          if (item == null && hasVideo)
            CollectionFocusArt(videoUrl: folder!.heroVideoUrl!),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [bg, bg.withValues(alpha: .28)],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [bg.withValues(alpha: .15), bg],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: narrow ? 20 : 32,
              vertical: compact ? 6 : 12,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Focus(
                      canRequestFocus: false,
                      onKeyEvent: (_, event) {
                        if (event is KeyDownEvent &&
                            event.logicalKey == LogicalKeyboardKey.arrowDown) {
                          onDown();
                          return KeyEventResult.handled;
                        }
                        if (event is KeyDownEvent &&
                            event.logicalKey == LogicalKeyboardKey.arrowRight &&
                            onRight != null) {
                          onRight!();
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                      child: IconButton(
                        focusNode: backNode,
                        tooltip: 'Back',
                        onPressed: () => Navigator.maybePop(context),
                        icon: Icon(Icons.arrow_back, color: app.core.tx),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        listTitle == null
                            ? collectionTitle
                            : '$collectionTitle / ${folder?.title ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: app.core.tx.withValues(alpha: .65),
                          fontSize: narrow ? 12 : 14,
                        ),
                      ),
                    ),
                    if (action != null) action!,
                  ],
                ),
                const Spacer(),
                if (!compact && logo != null) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: narrow ? 100 : 140,
                      height: 30,
                      child: network(logo, fit: BoxFit.contain),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: app.core.tx,
                    fontSize: compact
                        ? 22
                        : narrow
                        ? 28
                        : 34,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(height: 6),
                  Text(
                    listTitle == null
                        ? '$listCount lists · Choose a list to explore'
                        : source ?? 'List',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: app.core.tx.withValues(alpha: .6),
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
