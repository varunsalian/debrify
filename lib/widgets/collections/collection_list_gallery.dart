import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/metadata_preferences.dart';
import '../../models/stremio_addon.dart';
import '../../services/debrify_image_cache.dart';
import '../../theme/app_theme_scope.dart';
import '../../utils/tv_keys.dart';
import '../metadata_presentation_mixin.dart';

class CollectionListPreview {
  const CollectionListPreview({
    required this.id,
    required this.title,
    required this.source,
    required this.items,
    this.loading = false,
    this.failed = false,
  });
  final String id, title, source;
  final List<StremioMeta> items;
  final bool loading, failed;
}

/// Lists are the navigation targets; artwork arriving later never changes the
/// card order or focus nodes. The grid owns its scroll and return position.
class CollectionListGallery extends StatefulWidget {
  const CollectionListGallery({
    super.key,
    required this.lists,
    required this.onOpen,
    required this.onExitTop,
  });
  final List<CollectionListPreview> lists;
  final ValueChanged<int> onOpen;
  final VoidCallback onExitTop;
  @override
  State<CollectionListGallery> createState() => CollectionListGalleryState();
}

class CollectionListGalleryState extends State<CollectionListGallery> {
  final _scroll = ScrollController();
  final _nodes = <String, FocusNode>{};
  int _focused = 0, _generation = 0;
  int _columns = 1;
  double _rowHeight = 240, _viewport = 0;
  FocusNode _node(int index) => _nodes.putIfAbsent(
    widget.lists[index].id,
    () => FocusNode(debugLabel: 'collection_list_${widget.lists[index].id}'),
  );

  @override
  void dispose() {
    ++_generation;
    _scroll.dispose();
    for (final node in _nodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> focusFirst() => focusIndex(_focused);
  Future<void> focusIndex(int index) async {
    if (widget.lists.isEmpty) return;
    final generation = ++_generation;
    index = index.clamp(0, widget.lists.length - 1);
    final id = widget.lists[index].id;
    if (_scroll.hasClients) {
      final top = 8 + (index ~/ _columns) * _rowHeight;
      final bottom = top + _rowHeight;
      final offset = top < _scroll.offset
          ? top
          : bottom > _scroll.offset + _viewport
          ? bottom - _viewport
          : _scroll.offset;
      _scroll.jumpTo(offset.clamp(0, _scroll.position.maxScrollExtent));
    }
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted ||
        generation != _generation ||
        ModalRoute.of(context)?.isCurrent != true ||
        index >= widget.lists.length ||
        widget.lists[index].id != id) {
      return;
    }
    _focused = index;
    final node = _node(index);
    if (node.context != null) node.requestFocus();
  }

  KeyEventResult _key(int index, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (isActivateOrSpaceKey(key)) {
      if (event is KeyDownEvent) widget.onOpen(index);
      return KeyEventResult.handled;
    }
    int? next;
    if (key == LogicalKeyboardKey.arrowLeft) {
      next = index % _columns == 0 ? index : index - 1;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      next = index % _columns == _columns - 1 ? index : index + 1;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      if (index < _columns) {
        widget.onExitTop();
        return KeyEventResult.handled;
      }
      next = index - _columns;
    }
    if (key == LogicalKeyboardKey.arrowDown) next = index + _columns;
    if (next == null) return KeyEventResult.ignored;
    if (next < widget.lists.length) focusIndex(next);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      _viewport = box.maxHeight;
      final narrow = box.maxWidth < 600;
      final pad = narrow ? 20.0 : 32.0;
      _columns = box.maxWidth < 600
          ? 1
          : box.maxWidth < 900
          ? 2
          : 3;
      final width = (box.maxWidth - pad * 2 - (_columns - 1) * 20) / _columns;
      final height =
          (width / 1.85).clamp(170.0, 300.0) +
          (MediaQuery.textScalerOf(context).scale(20) - 20).clamp(0.0, 80.0);
      _rowHeight = height + 20;
      return GridView.builder(
        controller: _scroll,
        padding: EdgeInsets.fromLTRB(pad, 8, pad, 24),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: _columns,
          mainAxisExtent: height,
          crossAxisSpacing: 20,
          mainAxisSpacing: 20,
        ),
        itemCount: widget.lists.length,
        itemBuilder: (context, i) => _GalleryCard(
          key: ValueKey(widget.lists[i].id),
          preview: widget.lists[i],
          node: _node(i),
          onFocused: () => _focused = i,
          onKey: (_, event) => _key(i, event),
          onOpen: () => widget.onOpen(i),
        ),
      );
    },
  );
}

class _GalleryCard extends StatefulWidget {
  const _GalleryCard({
    super.key,
    required this.preview,
    required this.node,
    required this.onFocused,
    required this.onKey,
    required this.onOpen,
  });
  final CollectionListPreview preview;
  final FocusNode node;
  final VoidCallback onFocused, onOpen;
  final FocusOnKeyEventCallback onKey;
  @override
  State<_GalleryCard> createState() => _GalleryCardState();
}

class _GalleryCardState extends State<_GalleryCard> {
  bool _focused = false, _hovered = false;
  @override
  Widget build(BuildContext context) {
    final p = widget.preview;
    final active = _focused || _hovered;
    final app = AppThemeScope.of(context);
    return Focus(
      focusNode: widget.node,
      onKeyEvent: widget.onKey,
      onFocusChange: (value) {
        setState(() => _focused = value);
        if (value) widget.onFocused();
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Semantics(
          button: true,
          label: 'Open ${p.title}, ${p.source}',
          child: GestureDetector(
            onTap: widget.onOpen,
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              transform: Matrix4.translationValues(0, active ? -3 : 0, 0),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                color: app.core.tx.withValues(alpha: .06),
                border: Border.all(
                  color: app.core.tx.withValues(alpha: active ? .8 : .10),
                  width: active ? 2 : 1,
                ),
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: app.core.tx.withValues(alpha: .16),
                          blurRadius: 18,
                        ),
                      ]
                    : [],
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Row(
                    children: [
                      for (final item in p.items.take(3))
                        Expanded(
                          child: CollectionPreviewArt(
                            key: ValueKey('${item.type}:${item.id}'),
                            item: item,
                          ),
                        ),
                    ],
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          app.seeAll.bg.withValues(alpha: .3),
                          app.seeAll.bg,
                        ],
                        stops: const [0, .35, 1],
                      ),
                    ),
                  ),
                  if (p.items.isEmpty)
                    Center(
                      child: Icon(
                        p.failed
                            ? Icons.cloud_off_outlined
                            : Icons.collections_outlined,
                        size: 40,
                        color: app.core.tx.withValues(alpha: .25),
                      ),
                    ),
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 18,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                p.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: app.core.tx,
                                  fontSize: 21,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                p.failed
                                    ? '${p.source} · Tap to retry'
                                    : p.loading
                                    ? '${p.source} · Loading'
                                    : p.source,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: app.core.tx.withValues(alpha: .65),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Icon(Icons.chevron_right, color: app.core.tx),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Title-derived mosaic art follows the selected poster/backdrop provider.
class CollectionPreviewArt extends StatefulWidget {
  const CollectionPreviewArt({
    super.key,
    required this.item,
    this.wide = false,
  });
  final StremioMeta item;
  final bool wide;
  @override
  State<CollectionPreviewArt> createState() => _CollectionPreviewArtState();
}

class _CollectionPreviewArtState extends State<CollectionPreviewArt>
    with MetadataPresentationMixin<CollectionPreviewArt> {
  @override
  StremioMeta get originalMetadata => widget.item;
  @override
  Widget build(BuildContext context) {
    final category = widget.wide
        ? MetadataCategory.backgrounds
        : MetadataCategory.posters;
    final item = presentedMetadata!;
    final fallback =
        !usesMetadataProvider(category) || metadataPreferences.fallback
        ? item.poster
        : null;
    final url = metadataArtworkPending(category)
        ? null
        : widget.wide
        ? item.background ?? fallback
        : item.poster;
    Widget image(String value, {bool retry = true}) => CachedNetworkImage(
      imageUrl: value,
      cacheManager: DebrifyImageCache.manager,
      memCacheWidth: widget.wide ? 1280 : 342,
      fit: BoxFit.cover,
      fadeInDuration: const Duration(milliseconds: 120),
      placeholder: (_, _) => const SizedBox.shrink(),
      errorWidget: (_, _, _) => retry && fallback != null && fallback != value
          ? image(fallback, retry: false)
          : const SizedBox.shrink(),
    );
    return url == null || url.isEmpty ? const SizedBox.shrink() : image(url);
  }
}
