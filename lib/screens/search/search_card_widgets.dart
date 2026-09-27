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

  /// Collection GIF shown over [artUrl] according to the device playback
  /// preference. Videos continue to require focus or hover.
  final String? focusArtUrl;
  final String? focusVideoUrl;
  final bool focusGlowEnabled;

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
    this.focusVideoUrl,
    this.focusGlowEnabled = false,
    this.showTitleOverlay = true,
    this.restVeil,
  });

  @override
  State<_StremioCard> createState() => _StremioCardState();
}

class _StremioCardState extends State<_StremioCard>
    with SingleTickerProviderStateMixin, MetadataPresentationMixin<_StremioCard> {
  @override
  StremioMeta get originalMetadata => widget.item;
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
    final item = presentedMetadata!;
    final folder = item is CollectionFolderMeta ? item.folder : null;
    final aspect = folder?.tileShape.aspectRatio ?? widget.aspectRatio;
    final wide = aspect > 1;
    final artwork = metadataCardArtwork(
      presented: item, preferences: metadataPreferences, wide: wide,
      overrideUrl: widget.artUrl,
      collection: folder != null,
    );
    final poster = metadataArtworkPending(wide ? MetadataCategory.backgrounds : MetadataCategory.posters)
        ? null : artwork.primary;
    final fallbackPoster = artwork.fallback;
    final isMovie = item.type.toLowerCase() == 'movie';
    final supportsWatched = isMovie || item.type.toLowerCase() == 'series';
    final movieId = item.effectiveImdbId ?? item.id;
    // Focus visuals (scale + shadow + ring on one curve) live in the shared
    // [CardFocusRise] so tuning lands once for every board card.
    final List<Widget> layers = [
      if (poster != null && poster.isNotEmpty)
        RecoverableNetworkImage(
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
              poster != fallbackPoster &&
                  fallbackPoster != null && fallbackPoster.isNotEmpty
              ? RecoverableNetworkImage(
                  imageUrl: fallbackPoster,
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
      if (widget.focusArtUrl != null || widget.focusVideoUrl != null)
        Positioned.fill(
          child: CollectionFocusArt(
            focused: _active,
            applyGifPreference: true,
            gifUrl: widget.focusArtUrl,
            videoUrl: widget.focusVideoUrl,
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
              child: const ColoredBox(color: homeCardProgressRed),
            ),
          ),
        ),
      // Hold-OK feedback: a dim scrim with a filling ring, shown only
      // while OK is actually held down (so it costs nothing at rest).
      if (_holding) _holdLayer(),
    ];

    final artCard = CollectionFocusGlow(
      active: _active,
      enabled: widget.focusGlowEnabled,
      imageUrl: poster,
      child: CardFocusRise(
        active: _active,
        isTelevision: widget.isTelevision,
        ringColor: widget.ringColor,
        aspectRatio: aspect,
        restVeil: widget.restVeil,
        children: layers,
      ),
    );

    final posterCard = folder == null
        ? artCard
        : Center(
            child: AspectRatio(aspectRatio: aspect, child: artCard),
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
    final item = presentedMetadata!;
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
          : widget.showTitleOverlay
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

/// Generic DPAD arrow-handling wrapper for a favourites-row card — the arrow
/// counterpart to [_BoardCell] for the IPTV / Debrify TV / Stremio TV rows.
/// Holds no focus itself — the inner [HomeArtPoster] does; this only routes
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
