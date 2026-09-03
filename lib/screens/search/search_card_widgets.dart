part of '../search_screen.dart';

class _StremioCard extends StatefulWidget {
  final StremioMeta item;
  final bool isTelevision;
  final FocusNode focusNode;
  final bool hasBoundSource;
  final bool showWatchedBadge;

  /// Focus ring override (Canvas cells pass white). Null keeps the classic
  /// violet-on-TV grammar.
  final Color? ringColor;

  /// 0..1 watched fraction — draws a bottom progress bar when non-null.
  final double? progress;

  /// Subtle 'S2 · E5' badge for a Continue Watching series card, or null.
  final String? episodeLabel;

  /// Long-press quick-play (mobile/desktop). Null hides the shortcut.
  final VoidCallback? onQuickPlay;

  /// Long-press — and hold-OK on TV — opens a menu instead of playing. Wins
  /// over [onQuickPlay] when both are set (Continue Watching cards).
  final VoidCallback? onLongPress;
  final VoidCallback onOpen;

  /// Shared-element tag: when set, the poster flies into the detail page's
  /// backdrop on open (and back on pop). Unique per CELL, so a title showing
  /// on two rows never trips Hero's duplicate-tag assert.
  final String? heroTag;

  /// Cell shape. 2:3 everywhere except Promenade's wide strip (16/9) — only
  /// the box changes; focus feel, hold-OK, progress and badges are identical.
  final double aspectRatio;

  /// Art override. Null uses [item].poster (the row default); the wide cells
  /// pass a derived 16:9 still so a landscape box isn't filled with a
  /// centre-cropped poster.
  final String? artUrl;

  /// Animated art shown over [artUrl] only while the card is focused or
  /// hovered (collection folder tiles). At most one card is active, so at
  /// most one GIF decodes at a time.
  final String? focusArtUrl;

  /// Whether the card may paint local title text, either on a landscape
  /// artwork overlay or inside a loading/missing-art placeholder. Home can
  /// suppress this while Search and Discover retain their defaults.
  final bool showTitleOverlay;

  /// Dim while unfocused — see [CardFocusRise.restVeil].
  final Color? restVeil;

  const _StremioCard({
    required this.item,
    required this.isTelevision,
    required this.focusNode,
    required this.hasBoundSource,
    this.showWatchedBadge = true,
    this.ringColor,
    this.progress,
    this.episodeLabel,
    this.onQuickPlay,
    this.onLongPress,
    required this.onOpen,
    this.heroTag,
    this.aspectRatio = 2 / 3,
    this.artUrl,
    this.focusArtUrl,
    this.showTitleOverlay = true,
    this.restVeil,
  });

  @override
  State<_StremioCard> createState() => _StremioCardState();
}

class _StremioCardState extends State<_StremioCard>
    with SingleTickerProviderStateMixin {
  bool _focused = false;
  bool _hovered = false;
  bool _keyDown = false;
  bool get _active => _focused || _hovered;

  /// Hold-OK on TV (same 500ms as the IPTV channel row's hold-to-favourite) —
  /// only armed on cards that have an [_StremioCard.onLongPress] menu. A short
  /// press still opens the title. Driven by a controller so the focused card
  /// can show the hold filling, making an otherwise-invisible gesture
  /// discoverable.
  static const _holdDuration = Duration(milliseconds: 500);
  late final AnimationController _holdController = AnimationController(
    vsync: this,
    duration: _holdDuration,
  );
  bool _holdFired = false;
  bool _holding = false;

  bool get _holdEnabled => widget.isTelevision && widget.onLongPress != null;

  @override
  void initState() {
    super.initState();
    _holdController.addStatusListener((status) {
      if (status != AnimationStatus.completed) return;
      _holdFired = true;
      if (mounted) setState(() => _holding = false);
      _holdController.reset();
      widget.onLongPress?.call();
    });
  }

  @override
  void dispose() {
    _holdController.dispose();
    super.dispose();
  }

  /// Abandon an in-flight hold (focus left, or the key came back up).
  void _cancelHold() {
    _holdController.reset();
    if (_holding && mounted) setState(() => _holding = false);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final item = widget.item;
    final wide = widget.aspectRatio > 1;
    final poster = widget.artUrl ?? item.poster;
    final isMovie = item.type.toLowerCase() == 'movie';
    final supportsWatched = isMovie || item.type.toLowerCase() == 'series';
    final movieId = item.effectiveImdbId ?? item.id;
    // Focus visuals (scale + shadow + ring on one curve) live in the shared
    // [CardFocusRise] so tuning lands once for every board card.
    final List<Widget> layers = [
      if (poster != null && poster.isNotEmpty)
        CachedNetworkImage(
          imageUrl: poster,
          fit: BoxFit.cover,
          // Decode board posters at a capped width — tiles are small,
          // full-res posters are the main memory churn while scrolling.
          // A wide cell is ~2.7x the width of a poster at the same height,
          // so it gets a proportionally larger cap rather than a blur.
          memCacheWidth: widget.isTelevision
              ? (wide ? 640 : 320)
              : (wide ? 860 : 480),
          // Short fade on TV (see HomeTheme.imageFadeIn): posters arriving
          // as hard-snapping rectangles was the last cheap tell at the card
          // level; memory-cached loads still land settled with no fade.
          fadeInDuration: HomeTheme.imageFadeIn(widget.isTelevision),
          fadeOutDuration: HomeTheme.imageFadeOut(widget.isTelevision),
          placeholder: (_, __) => _placeholder(item.name),
          // A derived wide still (MetaHub) can 404 where the poster exists —
          // cover-crop the poster into the wide cell before giving up on art.
          errorWidget: (_, __, ___) =>
              poster != item.poster &&
                  item.poster != null &&
                  item.poster!.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: item.poster!,
                  fit: BoxFit.cover,
                  memCacheWidth: widget.isTelevision ? 320 : 480,
                  fadeInDuration: HomeTheme.imageFadeIn(widget.isTelevision),
                  fadeOutDuration: HomeTheme.imageFadeOut(widget.isTelevision),
                  placeholder: (_, __) => _placeholder(item.name),
                  errorWidget: (_, __, ___) => _placeholder(item.name),
                )
              : _placeholder(item.name),
        )
      else
        _placeholder(item.name),
      if (widget.focusArtUrl != null && _active)
        Positioned.fill(
          child: CachedNetworkImage(
            imageUrl: widget.focusArtUrl!,
            fit: BoxFit.cover,
            fadeInDuration: HomeTheme.imageFadeIn(widget.isTelevision),
            fadeOutDuration: Duration.zero,
            errorWidget: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
      // A landscape still rarely carries its title the way poster art does,
      // and off TV there is no hero identity revealing the focused card —
      // so a wide TOUCH card labels itself. TV keeps clean cards: browsing
      // there puts every focused title's name in the hero (Promenade
      // grammar). Sits under the badges; the scrim keeps them readable too.
      if (wide && !widget.isTelevision && widget.showTitleOverlay) ...[
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: IgnorePointer(
            child: Container(
              height: 52,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00000000), Color(0xB8000000)],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 8,
          right: 8,
          // Clear the CW episode badge and progress bar, which own the
          // bottom edge when present.
          bottom:
              (widget.episodeLabel != null ? 22.0 : 0.0) +
              (widget.progress != null ? 11.0 : 8.0),
          child: Text(
            item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: app.onGlass,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.1,
              shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
            ),
          ),
        ),
      ],
      if (supportsWatched && widget.showWatchedBadge)
        Positioned(
          top: 7,
          right: 7,
          child: MovieWatchedBadge(
            imdbId: movieId,
            contentType: item.type,
            compact: true,
            tickPolicyScoped: true,
          ),
        ),
      if (widget.hasBoundSource)
        Positioned(
          top: 8,
          left: supportsWatched && widget.showWatchedBadge ? 8 : null,
          right: supportsWatched && widget.showWatchedBadge ? null : 8,
          child: Icon(
            Icons.bookmark_rounded,
            size: 18,
            color: app.core.tx,
            shadows: const [Shadow(color: Colors.black, blurRadius: 6)],
          ),
        ),
      // Subtle season/episode badge for a Continue Watching series
      // card — sits just above the progress bar, bottom-left.
      if (widget.episodeLabel != null)
        Positioned(
          left: 6,
          bottom: widget.progress != null ? 11 : 6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.66),
              borderRadius: app.shape.br(5),
            ),
            child: Text(
              widget.episodeLabel!,
              style: TextStyle(
                // On the glass, not the page — see AppTheme.onGlass.
                color: app.onGlass,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ),
      // Continue Watching progress — a red bar pinned to the bottom of
      // the poster (Stremio-style, clipped to the rounded corners). A
      // faint dark track keeps it readable on bright posters.
      if (widget.progress != null)
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            height: 5,
            color: Colors.black.withValues(alpha: 0.45),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: widget.progress!.clamp(0.0, 1.0),
              heightFactor: 1,
              child: const ColoredBox(color: _kCwProgressRed),
            ),
          ),
        ),
      // Hold-OK feedback: a dim scrim with a filling ring, shown only
      // while OK is actually held down (so it costs nothing at rest).
      if (_holding) _holdLayer(),
    ];

    final posterCard = CardFocusRise(
      active: _active,
      isTelevision: widget.isTelevision,
      ringColor: widget.ringColor,
      aspectRatio: widget.aspectRatio,
      restVeil: widget.restVeil,
      children: layers,
    );

    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (!f) {
          // Focus left mid-press — disarm, so a stray key-up can't open a card
          // the user never pressed and a half-filled hold can't fire.
          _keyDown = false;
          _holdFired = false;
          _cancelHold();
        }
        if (f) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Scrollable.ensureVisible(
              context,
              alignment: 0.5,
              alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
              // TV glides too (was a hard Duration.zero jump — the single
              // biggest "not native" tell). Kept SHORT (140ms): each held-DPAD
              // repeat retargets the in-flight scroll from the CURRENT offset,
              // and a short glide converges on the focused card fast enough
              // that motion never reads as trailing the keypress (200ms felt
              // laggy on-device).
              duration: widget.isTelevision
                  ? const Duration(milliseconds: 140)
                  : const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
            );
          });
        }
      },
      onKeyEvent: (node, event) {
        if (isActivateKey(event.logicalKey) ||
            event.logicalKey == LogicalKeyboardKey.space) {
          // Cards with a long-press menu (Continue Watching) tell a tap from a
          // hold; every other card keeps the plain press-to-open path.
          if (_holdEnabled) {
            if (event is KeyDownEvent) {
              _keyDown = true;
              _holdFired = false;
              setState(() => _holding = true);
              _holdController.forward(from: 0);
            } else if (event is KeyUpEvent) {
              // A press this card actually started, released before the hold
              // completed → open. A key-up with no matching key-down (focus
              // arrived mid-press) is swallowed.
              final wasPress = _keyDown && !_holdFired;
              _keyDown = false;
              _holdFired = false;
              _cancelHold();
              if (wasPress) widget.onOpen();
            }
            // Swallow auto-repeat while the key is held.
            return KeyEventResult.handled;
          }
          if (event is KeyDownEvent) {
            _keyDown = true;
            return KeyEventResult.handled;
          } else if (event is KeyUpEvent) {
            if (_keyDown) widget.onOpen();
            _keyDown = false;
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        onEnter: (_) {
          if (mounted) setState(() => _hovered = true);
        },
        onExit: (_) {
          if (mounted) setState(() => _hovered = false);
        },
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          // Guarded because this card now sits UNDER a dialog: on TV remotes
          // where Select also emits a tap, picking a row in the long-press menu
          // pops it and lets that tap through to the card — which would open
          // the detail page on top of the play/removal the user actually asked
          // for. The dialog rows mark the key action; this drops its echo.
          onTap: () {
            if (DialogTapGuard.shouldIgnoreTap()) return;
            widget.onOpen();
          },
          // Touch/desktop counterpart of TV's hold-OK: the menu when there is
          // one, else the old long-press-to-play.
          onLongPress: widget.onLongPress ?? widget.onQuickPlay,
          behavior: HitTestBehavior.opaque,
          // No title beneath the poster — Stremio lets the artwork carry the
          // rail; the title lives on the hero (focused) and the detail page.
          //
          // RepaintBoundary so the focus pop (scale tween + shadow flip)
          // repaints only this card's layer, not the whole row viewport.
          child: RepaintBoundary(
            child: widget.heroTag == null
                ? posterCard
                : Hero(
                    tag: widget.heroTag!,
                    // Card-side shuttle covers BOTH directions (the backdrop hero
                    // defines none): the flight always shows the poster, growing
                    // into the detail backdrop on push and shrinking home on pop.
                    flightShuttleBuilder: _posterFlightShuttle,
                    child: posterCard,
                  ),
          ),
        ),
      ),
    );
  }

  /// Hold-OK feedback layer — a dim scrim with a filling ring, shown only
  /// while OK is actually held down (so it costs nothing at rest). Shared by
  /// the poster and wide layer sets.
  Widget _holdLayer() {
    return Positioned.fill(
      child: IgnorePointer(
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.42),
          child: Center(
            child: SizedBox(
              width: 34,
              height: 34,
              child: AnimatedBuilder(
                animation: _holdController,
                builder: (_, __) => CircularProgressIndicator(
                  value: _holdController.value,
                  strokeWidth: 3,
                  backgroundColor: Colors.white.withValues(alpha: 0.22),
                  valueColor: const AlwaysStoppedAnimation(kStremioFocusRing),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _placeholder(String title) {
    final app = AppThemeScope.of(context);
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
      child: widget.showTitleOverlay
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

/// The "See All ›" affordance in a rail header — a mouse/tap entry to the
/// full-screen See-All screen, shown on desktop only. Kept understated (quiet
/// grey that brightens on hover, no accent fill) so it doesn't compete with the
/// posters. TV rails are chrome-free and paginate on scroll instead.
class _SeeAllLink extends StatefulWidget {
  final VoidCallback onTap;
  final bool compact;
  const _SeeAllLink({required this.onTap, this.compact = false});

  @override
  State<_SeeAllLink> createState() => _SeeAllLinkState();
}

class _SeeAllLinkState extends State<_SeeAllLink> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final color = _hover ? app.core.tx : app.fade(app.core.tx, 0.5);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: _hover ? app.fade(app.core.tx, 0.08) : Colors.transparent,
            borderRadius: app.shape.br(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.compact ? 'All' : 'See All',
                style: TextStyle(
                  color: color,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, size: 17, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

/// The kinds of leading saved-content rows. Render order (Watchlist Movies,
/// Watchlist Series, Playlist, Debrify TV, Stremio TV, IPTV) is defined by
/// [_SearchScreenState._favRowKinds], the single source of truth for rendering
/// and the index-based DPAD focus wiring.
enum _FavKind {
  watchlistMovies,
  watchlistSeries,
  iptv,
  debrify,
  stremio,
  playlist,
}

/// One visible favourites-family row: a singleton [kind] row ([list] == -1),
/// or — for `kind == _FavKind.iptv` with [list] >= 0 — the IPTV custom-list
/// row at that index of [_SearchScreenState._iptvListRows]. Value-equal so
/// rebuilt ref lists compare cleanly.
class _FavRowRef {
  final _FavKind kind;
  final int list;
  const _FavRowRef(this.kind, [this.list = -1]);

  bool get isIptvList => list >= 0;

  @override
  bool operator ==(Object other) =>
      other is _FavRowRef && other.kind == kind && other.list == list;

  @override
  int get hashCode => Object.hash(kind, list);
}

/// One opted-in IPTV custom list shown as a Home row. [channels] are rebuilt
/// from the stored list metadata alone (no provider fetch) with their full
/// presentation fields — a list can hold VOD alongside live channels, and the
/// content type drives both the play routing and whether focus retunes the
/// hero live preview. [nodes] are owned here and reconciled by [listId]
/// across reloads (see [_SearchScreenState._loadIptvListRows]).
class _IptvListRow {
  final String listId;
  String title;
  List<IptvChannel> channels;
  final List<FocusNode> nodes = [];
  _IptvListRow(this.listId, this.title) : channels = const [];
}

/// Generic DPAD arrow-handling wrapper for a favourites-row card — the arrow
/// counterpart to [_BoardCell] for the IPTV / Debrify TV / Stremio TV rows.
/// Holds no focus itself — the inner [_ArtPoster] does; this only routes
/// left/right within the row and up/down out of it, matching the catalog
/// cards' navigation exactly.
class _FavArtCell extends StatelessWidget {
  final bool isTelevision;
  final int column;
  final List<FocusNode> rowNodes;
  final VoidCallback onUp;
  final VoidCallback onDown;

  /// Horizontal overrides — see [_BoardCell.onLeft]. Null keeps the row
  /// grammar.
  final VoidCallback? onLeft;
  final VoidCallback? onRight;

  /// Held up/down — see [_BoardCell.onUpHold].
  final VoidCallback? onUpHold;
  final VoidCallback? onDownHold;
  final Widget child;

  const _FavArtCell({
    required this.isTelevision,
    required this.column,
    required this.rowNodes,
    required this.onUp,
    required this.onDown,
    this.onLeft,
    this.onRight,
    this.onUpHold,
    this.onDownHold,
    required this.child,
  });

  KeyEventResult _handleArrows(FocusNode node, KeyEvent event) {
    // Act on key-down AND key-repeat (held DPAD). If we let a repeat fall
    // through as `ignored`, Flutter's default geometric traversal fires and
    // jumps focus into an adjacent row — so only key-ups are passed on.
    if (!isTelevision || event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (onLeft != null) {
        onLeft!();
      } else if (column > 0) {
        rowNodes[column - 1].requestFocus();
      } else {
        MainPageBridge.focusTvSidebar?.call();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      if (onRight != null) {
        onRight!();
      } else if (column < rowNodes.length - 1) {
        rowNodes[column + 1].requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      if (event is KeyRepeatEvent && onUpHold != null) {
        onUpHold!();
      } else {
        onUp();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (event is KeyRepeatEvent && onDownHold != null) {
        onDownHold!();
      } else {
        onDown();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _handleArrows,
      child: child,
    );
  }
}

/// Stremio-shaped artwork card for a favourite that has a real image (a Stremio
/// TV channel's now-playing poster, or an IPTV channel's logo). Shows the image
/// over a purple gradient — with a live-TV glyph fallback when it's missing or
/// fails to load — and the title below, matching [_StremioCard]'s size, corner
/// radius, hover/focus lift and selection ring so the row reads as one board.
class _ArtPoster extends StatefulWidget {
  final String? imageUrl;
  final String title;
  final bool showTitle;

  /// How the image fills the 2:3 tile — cover for posters, contain for logos.
  final BoxFit imageFit;

  /// Optional top-left badge text (e.g. a channel number) drawn over the tile.
  final String? badge;

  /// When true, a red "LIVE" pill is drawn top-right — signalling that this is a
  /// channel and the artwork is what's playing on it right now.
  final bool live;

  /// Optional resume-progress fraction (0..1). When set, a thin progress bar is
  /// drawn along the bottom edge of the poster (used by the Playlist row).
  final double? progress;
  final bool isTelevision;

  /// Focus ring override (Canvas favourites cells pass white); null keeps
  /// the classic violet-on-TV grammar.
  final Color? ringColor;
  final FocusNode focusNode;
  final VoidCallback onOpen;

  /// Fired when this card gains DPAD focus (TV only — see [_ArtPosterState]'s
  /// `onFocusChange`). The IPTV favourites rows use it to retune the hero's
  /// video region (boxed on classic, full-bleed on Canvas) to the focused
  /// channel's live stream; other favourites rows pass a clearing/stage
  /// callback so a live feed never lingers when focus moves off IPTV without
  /// passing through a catalog/CW card first.
  final VoidCallback? onFocused;

  const _ArtPoster({
    required this.imageUrl,
    required this.title,
    this.showTitle = true,
    required this.isTelevision,
    required this.focusNode,
    required this.onOpen,
    this.imageFit = BoxFit.cover,
    this.badge,
    this.live = false,
    this.progress,
    this.ringColor,
    this.onFocused,
  });

  @override
  State<_ArtPoster> createState() => _ArtPosterState();
}

class _ArtPosterState extends State<_ArtPoster> {
  bool _focused = false;
  bool _hovered = false;
  bool _keyDown = false;
  bool get _active => _focused || _hovered;

  Widget _glyph() {
    final app = AppThemeScope.of(context);
    return Center(
      child: Icon(
        Icons.live_tv_rounded,
        size: 40,
        color: app.fade(app.home.chromeAccent, _active ? 1 : 0.85),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final url = widget.imageUrl;
    final hasImage = url != null && url.isNotEmpty;

    // Focus visuals (scale + shadow + ring on one curve) live in the shared
    // [CardFocusRise] so tuning lands once for every board card.
    final posterCard = CardFocusRise(
      active: _active,
      isTelevision: widget.isTelevision,
      ringColor: widget.ringColor,
      children: [
        // Base gradient — the fallback backdrop and the ground behind
        // any letterboxed (contain-fit) logo.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2A1D5C), Color(0xFF1A1440), Color(0xFF0D0B1A)],
              stops: [0.0, 0.55, 1.0],
            ),
          ),
        ),
        if (hasImage)
          Padding(
            padding: widget.imageFit == BoxFit.contain
                ? const EdgeInsets.all(12)
                : EdgeInsets.zero,
            child: CachedNetworkImage(
              imageUrl: url,
              fit: widget.imageFit,
              memCacheWidth: widget.isTelevision ? 320 : 480,
              // Short fade on TV (see HomeTheme.imageFadeIn) — cached loads
              // land settled with no fade.
              fadeInDuration: HomeTheme.imageFadeIn(widget.isTelevision),
              fadeOutDuration: HomeTheme.imageFadeOut(widget.isTelevision),
              placeholder: (_, __) => _glyph(),
              errorWidget: (_, __, ___) => _glyph(),
            ),
          )
        else
          _glyph(),
        // Optional channel-number badge, top-left.
        if (widget.badge != null)
          Positioned(
            top: 10,
            left: 10,
            child: Text(
              widget.badge!,
              style: TextStyle(
                color: app.fade(app.core.tx, 0.85),
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
          ),
        // "LIVE" pill, top-right — marks this as a channel currently
        // playing the shown artwork.
        if (widget.live)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: app.shape.br(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: _kCwProgressRed,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'LIVE',
                    style: TextStyle(
                      color: app.core.tx,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
            ),
          ),
        // Resume-progress bar along the bottom edge (Playlist row).
        if (widget.progress != null && widget.progress! > 0)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SizedBox(
              height: 4,
              child: Stack(
                children: [
                  Container(color: Colors.black.withValues(alpha: 0.4)),
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: widget.progress!,
                    child: Container(color: _kCwProgressRed),
                  ),
                ],
              ),
            ),
          ),
      ],
    );

    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (!f) _keyDown = false;
        if (f) {
          widget.onFocused?.call();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Scrollable.ensureVisible(
              context,
              alignment: 0.5,
              alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
              // TV glides too (was a hard jump) — see _StremioCard: repeated
              // DPAD moves retarget the in-flight scroll, so held browsing
              // stays one continuous motion. Short on purpose; 200ms trailed
              // the keypress on-device.
              duration: widget.isTelevision
                  ? const Duration(milliseconds: 140)
                  : const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
            );
          });
        }
      },
      onKeyEvent: (node, event) {
        if (isActivateKey(event.logicalKey) ||
            event.logicalKey == LogicalKeyboardKey.space) {
          if (event is KeyDownEvent) {
            _keyDown = true;
            return KeyEventResult.handled;
          } else if (event is KeyUpEvent) {
            if (_keyDown) widget.onOpen();
            _keyDown = false;
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        onEnter: (_) {
          if (mounted) setState(() => _hovered = true);
        },
        onExit: (_) {
          if (mounted) setState(() => _hovered = false);
        },
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onOpen,
          behavior: HitTestBehavior.opaque,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              posterCard,
              if (widget.showTitle) ...[
                const SizedBox(height: _kArtTitleGap),
                Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  maxLines: _kArtTitleMaxLines,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _active ? app.core.tx : app.fade(app.core.tx, 0.92),
                    fontSize: _kArtTitleFontSize,
                    fontWeight: FontWeight.w600,
                    height: _kArtTitleHeight,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Catalog / Keyword / Lists mode selector.
class _ModeToggle extends StatelessWidget {
  final _Mode mode;
  final bool isTelevision;
  final bool listsAvailable;

  /// When true the two segments split the full available width (used when the
  /// toggle is stacked below the search box on narrow screens).
  final bool fullWidth;
  final ValueChanged<_Mode> onChanged;

  /// TV-only DPAD focus nodes for the segments (null off-TV, where the
  /// InkWell handles pointer taps and normal Tab traversal instead).
  final FocusNode? catalogNode;
  final FocusNode? keywordNode;
  final FocusNode? listsNode;
  final FocusNode? dropdownNode;

  /// Use a single DPAD-capable dropdown when three labelled segments cannot
  /// fit without squeezing or overflowing the search header.
  final bool compact;

  /// Leave the toggle back to the search field (arrow-up, or arrow-left off the
  /// leftmost segment) / down into the board content.
  final VoidCallback? onLeaveToField;
  final VoidCallback? onLeaveToContent;

  const _ModeToggle({
    required this.mode,
    required this.isTelevision,
    required this.listsAvailable,
    required this.onChanged,
    this.fullWidth = false,
    this.catalogNode,
    this.keywordNode,
    this.listsNode,
    this.dropdownNode,
    this.compact = false,
    this.onLeaveToField,
    this.onLeaveToContent,
  });

  List<_Mode> get _modes => [
    _Mode.catalog,
    if (ProfilePolicyGuard.allowsSync(ProfileFeature.keywordSearch))
      _Mode.keyword,
    if (listsAvailable) _Mode.lists,
  ];

  FocusNode? _nodeFor(_Mode value) => switch (value) {
    _Mode.catalog => catalogNode,
    _Mode.keyword => keywordNode,
    _Mode.lists => listsNode,
  };

  String _labelFor(_Mode value) => switch (value) {
    _Mode.catalog => 'Catalog',
    _Mode.keyword => 'Keyword',
    _Mode.lists => 'Lists',
  };

  /// DPAD handling for a focused segment: select switches mode, arrows move
  /// between the segments and out to the field (up/left) or content (down).
  KeyEventResult _handleSegmentKey(_Mode value, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (isActivateKey(key) || key == LogicalKeyboardKey.space) {
      onChanged(value);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      onLeaveToField?.call();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      onLeaveToContent?.call();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      final index = _modes.indexOf(value);
      if (index > 0) {
        _nodeFor(_modes[index - 1])?.requestFocus();
      } else {
        onLeaveToField?.call();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      final index = _modes.indexOf(value);
      if (index >= 0 && index < _modes.length - 1) {
        _nodeFor(_modes[index + 1])?.requestFocus();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final modes = _modes;
    if (modes.length <= 1) {
      return const SizedBox.shrink();
    }
    if (compact) {
      return SizedBox(
        width: fullWidth ? double.infinity : 156,
        child: StremioDropdown<_Mode>(
          label: 'Search',
          value: modes.contains(mode) ? mode : modes.first,
          options: [
            for (final value in modes)
              StremioDropdownOption(value, _labelFor(value)),
          ],
          onSelected: onChanged,
          isTelevision: isTelevision,
          focusNode: dropdownNode,
          onUpArrowPressed: onLeaveToField,
          onDownArrowPressed: onLeaveToContent,
        ),
      );
    }
    final catalog = _segment(
      context,
      _Mode.catalog,
      'Catalog',
      Icons.grid_view_rounded,
    );
    final keyword = _segment(
      context,
      _Mode.keyword,
      'Keyword',
      Icons.bolt_rounded,
    );
    final lists = _segment(
      context,
      _Mode.lists,
      'Lists',
      Icons.playlist_play_rounded,
    );
    final segments = <Widget>[
      catalog,
      if (modes.contains(_Mode.keyword)) keyword,
      if (modes.contains(_Mode.lists)) lists,
    ];
    return Container(
      height: isTelevision ? 54 : 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: app.shape.br(14),
        border: Border.all(color: app.fade(app.core.tx, 0.08)),
      ),
      child: Row(
        mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
        children: fullWidth
            ? [for (final segment in segments) Expanded(child: segment)]
            : segments,
      ),
    );
  }

  Widget _segment(
    BuildContext context,
    _Mode value,
    String label,
    IconData icon,
  ) {
    final app = AppThemeScope.of(context);
    final on = mode == value;
    final node = switch (value) {
      _Mode.catalog => catalogNode,
      _Mode.keyword => keywordNode,
      _Mode.lists => listsNode,
    };

    Widget content(bool focused) => AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.symmetric(horizontal: isTelevision ? 16 : 12),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: on ? app.home.chromeAccent : Colors.transparent,
        borderRadius: app.shape.br(10),
        // A white ring shows the remote's DPAD position. Drawn whenever the
        // segment is focused — including the selected one, since focus lands
        // there first (its accent fill alone wouldn't signal focus moved).
        border: Border.all(
          color: focused ? app.fade(app.core.tx, 0.9) : Colors.transparent,
          width: 2,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            // Scored against the fill, not hardcoded white: chromeAccent IS
            // the accent, and 17 of the 18 selectable themes have one where
            // white fails — Noir's and Frost's are pure #FFFFFF, so the
            // selected segment was a white label on a white bar. inkOn
            // returns white on legacy's #7B5CFF (4.36, over the threshold),
            // so this is a no-op today.
            color: on
                ? app.inkOn(app.home.chromeAccent)
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: isTelevision ? 14 : 13,
              fontWeight: FontWeight.w700,
              color: on
                  ? app.inkOn(app.home.chromeAccent)
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );

    if (node == null) {
      return InkWell(
        onTap: () => onChanged(value),
        borderRadius: app.shape.br(10),
        child: content(false),
      );
    }

    // The wrapping Focus owns the keyboard/DPAD focus node; the InkWell stays
    // pointer-only (canRequestFocus:false) so it doesn't compete for focus.
    return Focus(
      focusNode: node,
      onKeyEvent: (n, event) => _handleSegmentKey(value, event),
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return InkWell(
            onTap: () => onChanged(value),
            borderRadius: app.shape.br(10),
            canRequestFocus: false,
            child: content(focused),
          );
        },
      ),
    );
  }
}

/// A pushable manual sources list for a catalog title/episode. Searches its own
/// torrent sources (own loading), renders them as [TorrentResultRow]s, and on
/// tap plays via the isolated service with the FULL source list + content
/// metadata (so the in-player Sources switcher + Continue Watching both work).
