import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/play_loader_art.dart';
import '../theme/app_theme_scope.dart';
import '../utils/tv_keys.dart';
import 'recoverable_network_image.dart';

/// Use the available pane size, rather than the physical display: a tablet in
/// split view and a landscape phone still need a usable single-column list.
bool useCinemaSourcesLayout(
  BoxConstraints size, {
  required bool isTelevision,
}) =>
    size.hasBoundedWidth &&
    size.hasBoundedHeight &&
    size.maxWidth >= (isTelevision ? 600 : 720) &&
    (isTelevision || size.maxHeight >= 420);

class CinemaSourceProvider {
  const CinemaSourceProvider({
    required this.id,
    required this.label,
    required this.count,
    this.failed = false,
    this.loading = false,
  });

  /// Null is the all-sources group. Other ids retain the search's own identity.
  final String? id;
  final String label;
  final int count;
  final bool failed;
  final bool loading;
}

/// A presentation shell for the existing source list. Matching, filtering,
/// playback, and badge layout remain owned by the search and its source rows.
class CinemaSourcesLayout extends StatefulWidget {
  const CinemaSourcesLayout({
    super.key,
    required this.contextTitle,
    required this.title,
    required this.providers,
    required this.selectedProvider,
    required this.onProviderSelected,
    required this.onFocusResults,
    required this.isSourceFocused,
    required this.resultCount,
    required this.isTelevision,
    required this.child,
    this.art,
    this.subtitle,
    this.contextLabel,
    this.onBack,
    this.backLabel = 'Details',
    this.onFocusAbove,
    this.headerAction,
    this.searching = false,
    this.failed = false,
    this.providersEnabled = true,
  });

  final String contextTitle;
  final String title;
  final String? subtitle;
  final String? contextLabel;
  final PlayLoaderArt? art;
  final List<CinemaSourceProvider> providers;
  final String? selectedProvider;
  final ValueChanged<String?> onProviderSelected;
  final VoidCallback onFocusResults;
  final bool Function() isSourceFocused;
  final VoidCallback? onFocusAbove;
  final VoidCallback? onBack;
  final String backLabel;
  final Widget? headerAction;
  final int resultCount;
  final bool searching;
  final bool failed;
  final bool isTelevision;
  final bool providersEnabled;
  final Widget child;

  @override
  State<CinemaSourcesLayout> createState() => CinemaSourcesLayoutState();
}

class CinemaSourcesLayoutState extends State<CinemaSourcesLayout> {
  final Map<String?, FocusNode> _providerNodes = {};
  final FocusNode _backNode = FocusNode(debugLabel: 'cinema-sources-back');
  final ScrollController _railScroll = ScrollController();

  /// Search autofocus must respect navigation in either part of the rail.
  bool get hasRailFocus =>
      _backNode.hasFocus || _providerNodes.values.any((node) => node.hasFocus);

  FocusNode _node(String? id) => _providerNodes.putIfAbsent(
    id,
    () => FocusNode(debugLabel: 'cinema-provider-${id ?? 'all'}'),
  );

  void focusSelectedProvider() {
    if (!widget.providersEnabled) return;
    final id = widget.providers.any((p) => p.id == widget.selectedProvider)
        ? widget.selectedProvider
        : null;
    _focusProvider(id);
  }

  void _focusProvider(String? id) {
    final node = _providerNodes[id];
    if (node?.context == null) return;
    node!.requestFocus();
    Scrollable.ensureVisible(
      node.context!,
      alignment: .5,
      alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
      duration: Duration.zero,
    );
  }

  @override
  void didUpdateWidget(CinemaSourcesLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    final ids = widget.providers.map((p) => p.id).toSet();
    final removed = _providerNodes.keys
        .where((id) => !ids.contains(id))
        .toList();
    final lostFocus = removed.any((id) => _providerNodes[id]!.hasFocus);
    final retired = [for (final id in removed) _providerNodes.remove(id)!];
    if (retired.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && lostFocus) focusSelectedProvider();
        for (final node in retired) {
          node.dispose();
        }
      });
    }
  }

  @override
  void dispose() {
    for (final node in _providerNodes.values) {
      node.dispose();
    }
    _railScroll.dispose();
    _backNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final surface = app.isLegacy ? const Color(0xFF101014) : app.home.bg;
    final rail = app.isLegacy
        ? const Color(0xFF141218)
        : Color.alphaBlend(app.fade(app.core.tx, .025), surface);
    return LayoutBuilder(
      builder: (context, size) {
        final railWidth = (size.maxWidth * .29).clamp(216.0, 340.0);
        final compact = size.maxHeight < 540;
        final inset = size.maxWidth < 900 ? 18.0 : 28.0;
        return ColoredBox(
          color: surface,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                key: const ValueKey('cinema-sources-rail'),
                width: railWidth,
                child: ColoredBox(
                  color: rail,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _context(rail, compact, size.maxHeight),
                      Padding(
                        padding: EdgeInsets.fromLTRB(inset, 8, inset, 9),
                        child: Text(
                          'SOURCES',
                          style: TextStyle(
                            color: app.fade(app.core.tx, .48),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          controller: _railScroll,
                          padding: EdgeInsets.symmetric(horizontal: inset - 6),
                          child: Column(
                            children: [
                              for (var i = 0; i < widget.providers.length; i++)
                                _provider(widget.providers[i], i),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          inset,
                          12,
                          inset,
                          compact ? 12 : 22,
                        ),
                        child: Row(
                          children: [
                            if (widget.searching)
                              const SizedBox.square(
                                dimension: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                ),
                              )
                            else
                              Icon(
                                widget.failed
                                    ? Icons.error_outline
                                    : Icons.check_rounded,
                                size: 14,
                                color: app.fade(app.core.tx, .45),
                              ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                widget.searching
                                    ? 'Searching sources…'
                                    : widget.failed
                                    ? 'Search failed'
                                    : 'Search complete',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: app.fade(app.core.tx, .5),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: app.fade(app.core.tx, .08),
              ),
              Expanded(
                child: Focus(
                  canRequestFocus: false,
                  skipTraversal: true,
                  onKeyEvent: (_, event) {
                    if ((event is KeyDownEvent || event is KeyRepeatEvent) &&
                        event.logicalKey == LogicalKeyboardKey.arrowLeft &&
                        widget.providersEnabled &&
                        widget.isSourceFocused()) {
                      focusSelectedProvider();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: Padding(
                    key: const ValueKey('cinema-sources-results'),
                    padding: EdgeInsets.fromLTRB(
                      inset,
                      compact ? 18 : 28,
                      inset,
                      0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                widget.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: app.core.tx,
                                  fontSize: compact ? 23 : 28,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -.7,
                                  height: 1.2,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              '${widget.resultCount} sources',
                              style: TextStyle(
                                fontSize: 12,
                                color: app.fade(app.core.tx, .5),
                              ),
                            ),
                            if (widget.headerAction != null)
                              widget.headerAction!,
                          ],
                        ),
                        if (widget.subtitle?.isNotEmpty == true)
                          Padding(
                            padding: const EdgeInsets.only(top: 7),
                            child: Text(
                              widget.subtitle!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: app.fade(app.core.tx, .52),
                              ),
                            ),
                          ),
                        SizedBox(height: compact ? 12 : 20),
                        Expanded(child: widget.child),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _context(Color surface, bool compact, double height) {
    final app = AppThemeScope.of(context);
    final art = widget.art;
    final backdrop = _clean(art?.backdropUrl) ?? _clean(art?.posterUrl);
    final logo = _clean(art?.logoUrl);
    final hasArt = backdrop != null || logo != null;
    final metadata = [
      art?.yearLabel,
      art?.runtimeLabel,
      art?.certificate,
    ].whereType<String>().where((s) => s.trim().isNotEmpty).join(' · ');
    Widget title() => Text(
      widget.contextTitle,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: app.core.tx,
        fontSize: compact ? 21 : 26,
        fontWeight: FontWeight.w700,
        letterSpacing: -.6,
        height: 1.15,
      ),
    );
    return SizedBox(
      height: hasArt
          ? (height * .46).clamp(174.0, 310.0)
          : metadata.isNotEmpty || widget.contextLabel != null
          ? (compact ? 184 : 224)
          : (compact ? 115 : 164),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (backdrop != null)
            RecoverableNetworkImage(
              imageUrl: backdrop,
              memCacheWidth: 720,
              fit: BoxFit.cover,
              placeholder: (_, _) => const SizedBox.shrink(),
              errorWidget: (_, _, _) => const SizedBox.shrink(),
            ),
          if (hasArt)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    surface.withValues(alpha: .18),
                    surface.withValues(alpha: .28),
                    surface.withValues(alpha: .92),
                    surface,
                  ],
                  stops: const [0, .35, .83, 1],
                ),
              ),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(24, compact ? 12 : 20, 24, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.onBack != null)
                  TextButton.icon(
                    focusNode: _backNode,
                    onPressed: widget.onBack,
                    style: TextButton.styleFrom(
                      foregroundColor: app.core.tx,
                      padding: const EdgeInsets.symmetric(horizontal: 7),
                      minimumSize: const Size(0, 36),
                    ),
                    icon: const Icon(Icons.arrow_back_rounded, size: 17),
                    label: Text(
                      widget.backLabel,
                      style: const TextStyle(fontSize: 13),
                    ),
                  )
                else
                  Row(
                    children: [
                      Icon(
                        Icons.search_rounded,
                        size: 18,
                        color: app.fade(app.core.tx, .5),
                      ),
                      const SizedBox(width: 9),
                      Text(
                        'Keyword search',
                        style: TextStyle(
                          fontSize: 12,
                          color: app.fade(app.core.tx, .5),
                        ),
                      ),
                    ],
                  ),
                const Spacer(),
                Flexible(
                  flex: 3,
                  child: logo == null
                      ? title()
                      : Semantics(
                          label: widget.contextTitle,
                          image: true,
                          child: RecoverableNetworkImage(
                            imageUrl: logo,
                            memCacheWidth: 640,
                            fit: BoxFit.contain,
                            placeholder: (_, _) => title(),
                            errorWidget: (_, _, _) => title(),
                          ),
                        ),
                ),
                if (metadata.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      metadata,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: app.fade(app.core.tx, .66),
                        fontSize: 12,
                      ),
                    ),
                  ),
                if (!compact && _clean(art?.genreLabel) != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text(
                      art!.genreLabel!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: app.fade(app.core.tx, .5),
                        fontSize: 11,
                      ),
                    ),
                  ),
                if (_clean(widget.contextLabel) != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      widget.contextLabel!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: app.core.tx,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _provider(CinemaSourceProvider provider, int index) {
    final app = AppThemeScope.of(context);
    final selected = provider.id == widget.selectedProvider;
    final node = _node(provider.id);
    return Focus(
      key: ValueKey(('cinema-provider', provider.id)),
      focusNode: node,
      canRequestFocus: widget.providersEnabled,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.arrowRight) {
          widget.onFocusResults();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowUp) {
          if (index > 0) {
            _focusProvider(widget.providers[index - 1].id);
          } else if (widget.onBack != null) {
            _backNode.requestFocus();
          } else {
            widget.onFocusAbove?.call();
          }
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowDown) {
          if (index + 1 < widget.providers.length) {
            _focusProvider(widget.providers[index + 1].id);
          }
          return KeyEventResult.handled;
        }
        if (isActivateKey(key)) {
          if (event is KeyDownEvent) widget.onProviderSelected(provider.id);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          final fill = focused
              ? app.core.tx
              : selected
              ? app.fade(app.home.chromeAccent, .16)
              : Colors.transparent;
          final ink = focused
              ? app.inkOn(fill)
              : app.fade(app.core.tx, selected ? .95 : .64);
          return Opacity(
            opacity: widget.providersEnabled ? 1 : .4,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Material(
                color: fill,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  canRequestFocus: false,
                  borderRadius: BorderRadius.circular(10),
                  onTap: widget.providersEnabled
                      ? () => widget.onProviderSelected(provider.id)
                      : null,
                  child: Semantics(
                    selected: selected,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: ink.withValues(alpha: .08),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: provider.id == null
                                ? Icon(
                                    Icons.grid_view_rounded,
                                    size: 14,
                                    color: ink,
                                  )
                                : Text(
                                    provider.label.characters.first
                                        .toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: ink,
                                    ),
                                  ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              provider.label,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: ink,
                                fontSize: widget.isTelevision ? 15 : 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (provider.loading)
                            SizedBox.square(
                              dimension: 13,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: ink,
                              ),
                            )
                          else if (provider.failed)
                            Icon(
                              Icons.refresh_rounded,
                              size: 17,
                              color: focused
                                  ? ink
                                  : Theme.of(context).colorScheme.error,
                            )
                          else
                            Text(
                              '${provider.count}',
                              style: TextStyle(
                                fontSize: 12,
                                color: ink.withValues(alpha: .7),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  static String? _clean(String? value) =>
      value == null || value.trim().isEmpty ? null : value.trim();
}
