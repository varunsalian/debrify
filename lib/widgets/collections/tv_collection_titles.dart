import 'dart:async';
import '../../utils/tv_keys.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../services/debrify_image_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/stremio_addon.dart';
import '../../services/storage_service.dart';
import '../../services/main_page_bridge.dart';
import '../../services/app_route_observer.dart';
import '../../utils/platform_util.dart';
import '../home/spotlight_card_trailer.dart';

/// Large-screen presentations of a collection's titles. The parent owns
/// paging, sorting and title actions; focus remains here while details push.
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

class TvCollectionTitlesState extends State<TvCollectionTitles>
    with RouteAware, WidgetsBindingObserver {
  static const _red = Color(0xffe50914);
  static const _ground = Color(0xff09090b);
  static const _surface = Color(0xff17171b);
  static const _muted = Color(0xffb3b3bd);
  Timer? _trailerDwell;
  String? _previewIdentity;
  bool _trailersEnabled = false;
  double _trailerVolume = 0;
  bool _covered = false;
  bool _paused = false;
  int _prefsRequest = 0;
  PageRoute<dynamic>? _route;

  String _identity(StremioMeta item) => '${item.type}:${item.id}';
  bool get _previewEligible =>
      !_covered &&
      !_paused &&
      _trailersEnabled &&
      (widget.style == 'gallery' ||
          widget.style == 'filmstrip' ||
          widget.style == 'journal') &&
      _index < widget.items.length &&
      _index < _nodes.length &&
      _nodes[_index].hasFocus &&
      (widget.items[_index].type == 'movie' ||
          widget.items[_index].type == 'series') &&
      !MediaQuery.disableAnimationsOf(context);

  Future<void> _loadTrailerSettings() async {
    final request = ++_prefsRequest;
    final surface = PlatformUtil.isTelevision
        ? AmbientTrailerSurface.homeHero
        : AmbientTrailerSurface.detail;
    final values = await Future.wait([
      StorageService.getHomeHeroTrailerEnabled(),
      StorageService.getAmbientTrailerAudioEnabled(surface),
      StorageService.getAmbientTrailerVolume(surface),
    ]);
    if (!mounted || request != _prefsRequest) return;
    final enabled = values[0] as bool;
    final changed = enabled != _trailersEnabled;
    setState(() {
      _trailersEnabled = enabled;
      _trailerVolume = (values[1] as bool) ? (values[2] as int).toDouble() : 0;
    });
    if (changed) _armPreview();
  }

  void _armPreview() {
    _trailerDwell?.cancel();
    if (_previewIdentity != null && mounted)
      setState(() => _previewIdentity = null);
    if (!mounted || !_previewEligible) return;
    final identity = _identity(widget.items[_index]);
    _trailerDwell = Timer(const Duration(seconds: 4), () {
      if (!mounted ||
          !_previewEligible ||
          ModalRoute.of(context)?.isCurrent == false ||
          identity != _identity(widget.items[_index]))
        return;
      setState(() => _previewIdentity = identity);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<dynamic> && route != _route) {
      appRouteObserver.unsubscribe(this);
      _route = route;
      appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didPushNext() {
    _covered = true;
    _armPreview();
  }

  @override
  void didPopNext() {
    _covered = false;
    _armPreview();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _paused = state != AppLifecycleState.resumed;
    _armPreview();
  }

  final _nodes = <FocusNode>[];
  int _index = 0;
  int? _hoverFocusIndex;
  int? _scrollLoadRequestedForLength;
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
    WidgetsBinding.instance.addObserver(this);
    MainPageBridge.addHomeSettingsListener(_loadTrailerSettings);
    unawaited(_loadTrailerSettings());
    _scroll.addListener(_maybeLoadMoreFromScroll);
    _resize();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeLoadMoreFromScroll();
    });
  }

  void _maybeLoadMoreFromScroll() {
    if (!_scroll.hasClients ||
        widget.items.isEmpty ||
        widget.loadingMore ||
        widget.exhausted ||
        _scrollLoadRequestedForLength == widget.items.length) {
      return;
    }
    // Two rows gives touch users enough headroom for the next page to arrive
    // before they hit the end, while the length guard prevents one swipe from
    // scheduling the same page more than once.
    if (_scroll.position.extentAfter > _rowExtent * 2) return;
    _scrollLoadRequestedForLength = widget.items.length;
    widget.onLoadMore();
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
    if (oldWidget.items.length != widget.items.length ||
        (oldWidget.loadingMore && !widget.loadingMore) ||
        (oldWidget.exhausted && !widget.exhausted)) {
      _scrollLoadRequestedForLength = null;
    }
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
    final selected = _index < widget.items.length ? widget.items[_index] : null;
    if (oldWidget.style != widget.style ||
        previous == null ||
        selected == null ||
        _identity(previous) != _identity(selected)) {
      _armPreview();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeLoadMoreFromScroll();
    });
  }

  @override
  void dispose() {
    _trailerDwell?.cancel();
    MainPageBridge.removeHomeSettingsListener(_loadTrailerSettings);
    WidgetsBinding.instance.removeObserver(this);
    appRouteObserver.unsubscribe(this);
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
    _hoverFocusIndex = null;
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
    final fromHover = _hoverFocusIndex == index;
    _hoverFocusIndex = null;
    setState(() => _index = index);
    _armPreview();
    widget.onItemFocused?.call(widget.items[index]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || fromHover || index >= widget.items.length) return;
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
      color: _surface,
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
          if (_index == index) _armPreview();
          if (_pressedIndex == index) _cancelPress();
          if (mounted) setState(() {});
        }
      },
      onKeyEvent: (_, event) => _key(index, event),
      child: Material(
        color: journal && focused ? const Color(0xff281114) : _surface,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          canRequestFocus: false,
          onHover: (hovering) {
            if (hovering && !_nodes[index].hasFocus) {
              _hoverFocusIndex = index;
              _nodes[index].requestFocus();
            }
          },
          onTap: () => widget.onOpen(item),
          onLongPress: widget.onQuickPlay == null
              ? null
              : () => widget.onQuickPlay!(item),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: focused ? _red : const Color(0xff27272e),
                width: 3,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: journal
                ? Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    child: Row(
                      children: [
                        Text(
                          '${index + 1}'.padLeft(2, '0'),
                          style: TextStyle(
                            color: focused ? _red : const Color(0xff666670),
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -1,
                          ),
                        ),
                        const SizedBox(width: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: SizedBox(
                            width: 32,
                            height: 44,
                            child: _art(item.poster, width: 100),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            item.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: focused
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          item.year ?? '',
                          style: TextStyle(color: _muted, fontSize: 11),
                        ),
                      ],
                    ),
                  )
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(7),
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
                          padding: const EdgeInsets.fromLTRB(10, 28, 10, 10),
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Color(0xf209090b)],
                            ),
                          ),
                          child: Text(
                            item.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                            ),
                          ),
                        ),
                      ),
                      if (focused)
                        const Positioned(
                          left: 10,
                          top: 10,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: _red,
                              borderRadius: BorderRadius.all(
                                Radius.circular(2),
                              ),
                            ),
                            child: SizedBox(width: 20, height: 3),
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
        Row(
          children: [
            Container(width: 3, height: 11, color: _red),
            const SizedBox(width: 8),
            Text(
              item.type == 'series' ? 'SERIES' : 'FILM',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 2.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          item.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            fontSize: journal ? 30 : 34,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.8,
            height: 1.05,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          [
            if (item.imdbRating != null)
              '★ ${item.imdbRating!.toStringAsFixed(1)}',
            if (item.year != null) item.year!,
            if (item.genres?.isNotEmpty == true) item.genres!.first,
          ].join('   ·   '),
          style: const TextStyle(
            color: Color(0xffd4d4da),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          item.description ?? 'Select this title to view details.',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: _muted, fontSize: 13, height: 1.45),
        ),
      ],
    );
    final artwork = Stack(
      fit: StackFit.expand,
      children: [
        _art(item.background ?? item.poster),
        if (_previewIdentity == _identity(item) && _previewEligible)
          SpotlightCardTrailer(
            key: ValueKey('collection-trailer:$_previewIdentity'),
            item: item,
            volume: _trailerVolume,
            onPlayingChanged: (_) {},
          ),
      ],
    );
    final preview = LayoutBuilder(
      builder: (context, constraints) => journal
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: artwork,
                  ),
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: details,
                ),
              ],
            )
          : ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  artwork,
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0.15, 0.55, 1],
                        colors: [
                          Colors.transparent,
                          Color(0x5509090b),
                          Color(0xff09090b),
                        ],
                      ),
                    ),
                  ),
                  Positioned(left: 24, right: 24, bottom: 28, child: details),
                ],
              ),
            ),
    );
    final list = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          child: Row(
            children: [
              Container(width: 3, height: 17, color: _red),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  journal ? 'The collection' : 'Browse titles',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${_index + 1} / ${widget.items.length}${widget.exhausted ? '' : '+'}',
                style: const TextStyle(color: _muted, fontSize: 11),
              ),
              if (widget.loadingMore)
                const Padding(
                  padding: EdgeInsets.only(left: 10),
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _red,
                    ),
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
      color: _ground,
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
