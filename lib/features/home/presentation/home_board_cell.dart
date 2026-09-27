import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../models/stremio_addon.dart';
import 'home_catalog_card.dart';

/// [HomeCatalogCard] plus DPAD arrow navigation. The card owns SELECT, its
/// focus visuals and ensureVisible; this ancestor [Focus] catches the arrows
/// the card ignores (left/right within the row, up/down to adjacent rows or
/// the search field) and reports focus to drive the hero.
class HomeBoardCell extends StatelessWidget {
  final StremioMeta item;
  final bool isTelevision;
  final FocusNode focusNode;
  final int column;
  final List<FocusNode> rowNodes;
  final bool hasBoundSource;
  final bool showWatchedBadge;

  /// 0..1 watched fraction — draws a bottom progress bar when non-null (used by
  /// the Continue Watching row). Null on regular catalog rows.
  final double? progress;

  /// Subtle 'S2 · E5' badge for a Continue Watching series card, or null.
  final String? episodeLabel;

  /// Long-press quick-play (mobile/desktop). Null hides the shortcut — used to
  /// mirror the catalog tiles' long-press-to-play when quick-play is available.
  final VoidCallback? onQuickPlay;

  /// Long-press (and hold-OK on TV) opens a menu instead of playing. Set on
  /// Continue Watching cards, where the press has to offer removal too; takes
  /// precedence over [onQuickPlay] when both are given.
  final VoidCallback? onLongPress;

  /// Leaves the first column using the current route's sidebar action.
  final VoidCallback onLeftEdge;
  final VoidCallback onFocused;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final VoidCallback onOpen;

  /// Called when DPAD-right focus nears this row's last card, so the next page
  /// can be prefetched before the user runs out of cards. Null on rows that
  /// don't paginate (e.g. Continue Watching).
  final VoidCallback? onNearEnd;

  /// Shared-element tag forwarded to the card (see [HomeCatalogCard.heroTag]).
  final String? heroTag;

  /// Forwarded to [HomeCatalogCard.ringColor] (Canvas cells use white).
  final Color? ringColor;

  /// Cell shape + the art that fills it. Defaults are the 2:3 poster every
  /// row uses; Promenade's strip passes 16/9 with a derived wide still.
  final double aspectRatio;
  final String? artUrl;

  final String? focusArtUrl;
  final String? focusVideoUrl;
  final bool focusGlowEnabled;
  final bool showTitleOverlay;

  /// Dim applied to this cell while it is NOT focused (Promenade's strip).
  final Color? restVeil;

  /// HELD up/down — fired on the first key REPEAT instead of [onUp]/[onDown].
  /// Tonight uses it to escape a long Continue queue in one gesture rather
  /// than one row at a time. Null keeps a held key doing what a tapped one
  /// does (the fast-scroll every rail relies on).
  final VoidCallback? onUpHold;
  final VoidCallback? onDownHold;

  /// Horizontal overrides. Null keeps the row grammar (LEFT walks back along
  /// [rowNodes] and hands off to the sidebar at column 0; RIGHT walks forward
  /// and prefetches). Mosaic's GRID must override both — its leftmost cell is
  /// not column 0, so without this the sidebar would be unreachable from
  /// every row but the first — and Tonight's queue overrides them too.
  final VoidCallback? onLeft;
  final VoidCallback? onRight;

  const HomeBoardCell({
    super.key,
    required this.item,
    required this.isTelevision,
    required this.focusNode,
    required this.column,
    required this.rowNodes,
    required this.hasBoundSource,
    this.showWatchedBadge = true,
    this.progress,
    this.episodeLabel,
    this.onQuickPlay,
    this.onLongPress,
    required this.onFocused,
    required this.onLeftEdge,
    required this.onUp,
    required this.onDown,
    required this.onOpen,
    this.onNearEnd,
    this.heroTag,
    this.ringColor,
    this.onLeft,
    this.onRight,
    this.aspectRatio = 2 / 3,
    this.artUrl,
    this.focusArtUrl,
    this.focusVideoUrl,
    this.focusGlowEnabled = false,
    this.showTitleOverlay = true,
    this.restVeil,
    this.onUpHold,
    this.onDownHold,
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
        // First card in the row — leave to the sidebar (no leading tile now).
        onLeftEdge();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      // Prefetch the next page a few cards before the end so DPAD users never
      // hit a wall on a catalog that still has more.
      if (column >= rowNodes.length - 6) onNearEnd?.call();
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
      onFocusChange: (has) {
        if (has) onFocused();
      },
      onKeyEvent: _handleArrows,
      child: HomeCatalogCard(
        item: item,
        isTelevision: isTelevision,
        focusNode: focusNode,
        hasBoundSource: hasBoundSource,
        showWatchedBadge: showWatchedBadge,
        ringColor: ringColor,
        progress: progress,
        episodeLabel: episodeLabel,
        onQuickPlay: onQuickPlay,
        onLongPress: onLongPress,
        onOpen: onOpen,
        heroTag: heroTag,
        aspectRatio: aspectRatio,
        artUrl: artUrl,
        focusArtUrl: focusArtUrl,
        focusVideoUrl: focusVideoUrl,
        focusGlowEnabled: focusGlowEnabled,
        showTitleOverlay: showTitleOverlay,
        restVeil: restVeil,
      ),
    );
  }
}
