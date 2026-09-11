import 'dart:async';
import '../../utils/tv_keys.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../services/debrify_image_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/stremio_addon.dart';

/// TV-only presentations of a collection's titles. The parent owns paging,
/// sorting and title actions; focus remains here while details are pushed.
class TvCollectionTitles extends StatefulWidget {
  const TvCollectionTitles({
    super.key,
    required this.style,
    required this.items,
    required this.onOpen,
    required this.onLoadMore,
    required this.onExitTop,
    this.onQuickPlay,
    this.onItemFocused,
    this.isBound,
    this.loadingMore = false,
    this.exhausted = false,
  });
  final String style;
  final List<StremioMeta> items;
  final ValueChanged<StremioMeta> onOpen;
  final ValueChanged<StremioMeta>? onQuickPlay, onItemFocused;
  final bool Function(StremioMeta)? isBound;
  final VoidCallback onLoadMore, onExitTop;
  final bool loadingMore, exhausted;
  @override
  State<TvCollectionTitles> createState() => TvCollectionTitlesState();
}

class TvCollectionTitlesState extends State<TvCollectionTitles> {
  final _nodes = <FocusNode>[];
  int _index = 0;
  Timer? _holdTimer;
  int? _pressedIndex;
  LogicalKeyboardKey? _pressedKey;
  bool _holdFired = false;

  void _cancelPress() {
    _holdTimer?.cancel();
    _holdTimer = null;
    _pressedIndex = null;
    _pressedKey = null;
    _holdFired = false;
  }

  KeyEventResult _activation(int index, KeyEvent event) {
    if (event is KeyDownEvent && _pressedIndex == null) {
      _pressedIndex = index;
      _pressedKey = event.logicalKey;
      _holdFired = false;
      if (widget.onQuickPlay != null) {
        _holdTimer = Timer(const Duration(milliseconds: 800), () {
          if (!mounted ||
              _pressedIndex != index ||
              !_nodes[index].hasFocus ||
              index >= widget.items.length) {
            return;
          }
          _holdFired = true;
          widget.onQuickPlay?.call(widget.items[index]);
        });
      }
    } else if (event is KeyUpEvent && event.logicalKey == _pressedKey) {
      final open = _pressedIndex == index && !_holdFired;
      _cancelPress();
      if (open) widget.onOpen(widget.items[index]);
    }
    // Repeats and orphaned releases must never reach Material activation.
    return KeyEventResult.handled;
  }

  final _scroll = ScrollController();
  double _rowExtent = 72;
  int get _columns => widget.style == 'gallery' ? 3 : 1;
  @override
  void initState() {
    super.initState();
    _resize();
  }

  void _resize() {
    while (_nodes.length < widget.items.length) {
      _nodes.add(FocusNode());
    }
    _index = widget.items.isEmpty
        ? 0
        : _index.clamp(0, widget.items.length - 1);
  }

  @override
  void didUpdateWidget(covariant TvCollectionTitles oldWidget) {
    super.didUpdateWidget(oldWidget);
    final pressed = _pressedIndex;
    if (pressed != null &&
        (pressed >= widget.items.length ||
            pressed >= oldWidget.items.length ||
            oldWidget.items[pressed].id != widget.items[pressed].id ||
            oldWidget.items[pressed].type != widget.items[pressed].type ||
            oldWidget.style != widget.style ||
            (oldWidget.onQuickPlay == null) != (widget.onQuickPlay == null))) {
      _cancelPress();
    }
    final oldIndex = _index;
    final focused = oldIndex < _nodes.length && _nodes[oldIndex].hasFocus;
    final previous = oldIndex < oldWidget.items.length
        ? oldWidget.items[oldIndex]
        : null;
    _resize();
    if (previous != null) {
      final retained = widget.items.indexWhere(
        (item) => item.id == previous.id && item.type == previous.type,
      );
      if (retained >= 0) _index = retained;
      if (focused && _index != oldIndex && widget.items.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _move(_index);
        });
      }
    }
  }

  @override
  void dispose() {
    _cancelPress();
    for (final node in _nodes) {
      node.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  void focusFirst() {
    if (widget.items.isNotEmpty) _move(0);
  }

  void _move(int index) {
    if (_scroll.hasClients) {
      final top = 5 + (index ~/ _columns) * _rowExtent;
      final position = _scroll.position;
      if (top < position.pixels ||
          top + _rowExtent > position.pixels + position.viewportDimension) {
        _scroll.jumpTo(
          (top - (position.viewportDimension - _rowExtent) / 2).clamp(
            0.0,
            position.maxScrollExtent,
          ),
        );
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && index < widget.items.length) _nodes[index].requestFocus();
    });
    // A cached row can need focus without a scroll triggering a new frame.
    WidgetsBinding.instance.scheduleFrame();
  }

  void _focus(int index) {
    setState(() => _index = index);
    widget.onItemFocused?.call(widget.items[index]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || index >= widget.items.length) return;
      final target = _nodes[index].context;
      if (target != null) Scrollable.ensureVisible(target, alignment: .5);
    });
    if (index >= widget.items.length - _columns * 2 &&
        !widget.loadingMore &&
        !widget.exhausted) {
      widget.onLoadMore();
    }
  }

  KeyEventResult _key(int index, KeyEvent event) {
    if (widget.items.isEmpty) return KeyEventResult.ignored;
    if (isActivateOrSpaceKey(event.logicalKey)) {
      return _activation(index, event);
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp && index < _columns) {
      widget.onExitTop();
      return KeyEventResult.handled;
    }
    int? next;
    if (key == LogicalKeyboardKey.arrowDown) next = index + _columns;
    if (key == LogicalKeyboardKey.arrowUp) next = index - _columns;
    if (key == LogicalKeyboardKey.arrowLeft) {
      next = _columns == 1 ? index : index - 1;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      next = _columns == 1 ? index : index + 1;
    }
    if (next != null) {
      if (next >= widget.items.length &&
          !widget.loadingMore &&
          !widget.exhausted) {
        widget.onLoadMore();
      }
      _move(next.clamp(0, widget.items.length - 1));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _art(String? url, {BoxFit fit = BoxFit.cover, int width = 1280}) {
    final fallback = Container(
      color: const Color(0xff27332f),
      child: const Center(
        child: Icon(Icons.movie_outlined, color: Colors.white38, size: 42),
      ),
    );
    if (url == null || url.isEmpty) return fallback;
    return CachedNetworkImage(
      key: ValueKey(url),
      imageUrl: url,
      fit: fit,
      cacheManager: DebrifyImageCache.manager,
      memCacheWidth: width,
      placeholder: (_, _) => fallback,
      errorWidget: (_, _, _) => fallback,
    );
  }

  Widget _tile(int index) {
    final item = widget.items[index];
    final focused = index == _index && _nodes[index].hasFocus;
    final journal = widget.style == 'journal';
    return Focus(
      focusNode: _nodes[index],
      onFocusChange: (value) {
        if (value) {
          _focus(index);
        } else {
          if (_pressedIndex == index) _cancelPress();
          if (mounted) setState(() {});
        }
      },
      onKeyEvent: (_, event) => _key(index, event),
      child: Material(
        color: journal && focused
            ? const Color(0xffd2ddbf)
            : const Color(0xff18221e),
        borderRadius: BorderRadius.circular(journal ? 0 : 8),
        child: InkWell(
          canRequestFocus: false,
          onTap: () => widget.onOpen(item),
          onLongPress: widget.onQuickPlay == null
              ? null
              : () => widget.onQuickPlay!(item),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: focused ? const Color(0xffd2ddbf) : Colors.transparent,
                width: 3,
              ),
              borderRadius: BorderRadius.circular(journal ? 0 : 8),
            ),
            child: journal
                ? Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Text(
                          '${index + 1}'.padLeft(2, '0'),
                          style: TextStyle(
                            color: focused ? Colors.black54 : Colors.white54,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            item.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: focused ? Colors.black87 : Colors.white,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          item.year ?? '',
                          style: TextStyle(
                            color: focused ? Colors.black54 : Colors.white54,
                          ),
                        ),
                      ],
                    ),
                  )
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: _art(
                          widget.style == 'filmstrip'
                              ? item.background ?? item.poster
                              : item.poster,
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          color: Colors.black87,
                          child: Text(
                            item.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                      if (widget.isBound?.call(item) == true)
                        const Positioned(
                          top: 6,
                          right: 6,
                          child: Icon(
                            Icons.push_pin,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();
    final item = widget.items[_index];
    final journal = widget.style == 'journal';
    final gallery = widget.style == 'gallery';
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: const Color(0xffeeeade),
            fontSize: journal ? 27 : 30,
            fontFamily: journal ? 'serif' : null,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          [
            if (item.imdbRating != null)
              '★ ${item.imdbRating!.toStringAsFixed(1)}',
            if (item.year != null) item.year!,
            item.type == 'series' ? 'Series' : 'Movie',
          ].join('   ·   '),
          style: const TextStyle(color: Color(0xffc1cbae), fontSize: 13),
        ),
        const SizedBox(height: 10),
        Text(
          item.description ?? 'Select this title to view details.',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xffb6beb1),
            fontSize: 14,
            height: 1.45,
          ),
        ),
      ],
    );
    final preview = LayoutBuilder(
      builder: (context, constraints) => journal
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _art(item.background ?? item.poster)),
                const SizedBox(height: 16),
                details,
              ],
            )
          : Stack(
              fit: StackFit.expand,
              children: [
                _art(item.background ?? item.poster),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0xff111815)],
                    ),
                  ),
                ),
                Positioned(left: 24, right: 24, bottom: 24, child: details),
              ],
            ),
    );
    final list = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          child: Row(
            children: [
              Text(
                'Titles',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: journal ? 23 : 17,
                  fontFamily: journal ? 'serif' : null,
                ),
              ),
              const Spacer(),
              Text(
                '${_index + 1} / ${widget.items.length}${widget.exhausted ? '' : '+'}',
                style: const TextStyle(color: Colors.white60),
              ),
              if (widget.loadingMore)
                const Padding(
                  padding: EdgeInsets.only(left: 10),
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              _rowExtent = gallery
                  ? ((constraints.maxWidth - 34) / 3) / .67 + 12
                  : journal
                  ? 72
                  : (constraints.maxWidth - 10) / 2.4 + 8;
              return gallery
                  ? GridView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(5),
                      itemCount: widget.items.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            childAspectRatio: .67,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                      itemBuilder: (_, i) => _tile(i),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(5),
                      itemCount: widget.items.length,
                      itemExtent: _rowExtent,
                      itemBuilder: (_, i) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _tile(i),
                      ),
                    );
            },
          ),
        ),
      ],
    );
    return ColoredBox(
      color: const Color(0xff111815),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: gallery
              ? [
                  Expanded(flex: 44, child: preview),
                  const SizedBox(width: 24),
                  Expanded(flex: 56, child: list),
                ]
              : [
                  Expanded(flex: journal ? 42 : 28, child: list),
                  const SizedBox(width: 28),
                  Expanded(flex: journal ? 58 : 72, child: preview),
                ],
        ),
      ),
    );
  }
}
