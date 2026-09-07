/// The Play / Browse / My Watchlist action row on `CatalogItemDetailScreen`.
library;

import 'package:flutter/material.dart';

import '../../theme/app_theme_scope.dart';
import '../../theme/artwork_accent.dart';
import 'catalog_detail_primary_button.dart';

// ── Action row (PLAY + BROWSE) ──────────────────────────────────────────────

class CatalogDetailActionRow extends StatelessWidget {
  final bool compact;
  final bool showQuickPlay;
  final bool isSeries;
  final bool hasBoundSource;
  final FocusNode playFocus;
  final FocusNode browseFocus;
  final FocusNode watchlistFocus;
  final bool tv;

  /// The primary button's label — progress-aware ("Start Watching" /
  /// "Resume · S3E4"), computed by the host.
  final String playLabel;

  /// Resume state still resolving — Play shows a spinner instead of a label.
  final bool playBusy;
  final VoidCallback onPlay;
  final VoidCallback? onPlayLongPress;
  final VoidCallback onBrowse;
  final bool inMyWatchlist;
  final VoidCallback? onToggleMyWatchlist;

  /// D-pad "up" handler — the row is the top focusable, so this scrolls the
  /// sheet back to the header rather than letting focus dead-end. Null off TV.
  final VoidCallback? onArrowUp;

  const CatalogDetailActionRow({
    super.key,
    required this.compact,
    required this.showQuickPlay,
    required this.isSeries,
    required this.hasBoundSource,
    required this.playFocus,
    required this.browseFocus,
    required this.watchlistFocus,
    required this.tv,
    required this.playLabel,
    this.playBusy = false,
    required this.onPlay,
    this.onPlayLongPress,
    required this.onBrowse,
    required this.inMyWatchlist,
    required this.onToggleMyWatchlist,
    this.onArrowUp,
  });

  @override
  Widget build(BuildContext context) {
    final browseLabel = isSeries ? 'Episodes' : 'Sources';
    final browseIcon = isSeries ? Icons.list_alt_rounded : Icons.layers_rounded;
    final gap = compact ? 8.0 : 10.0;

    final browse = CatalogDetailPrimaryButton(
      focusNode: browseFocus,
      icon: browseIcon,
      label: browseLabel,
      filled: !showQuickPlay,
      compact: compact,
      tv: tv,
      onTap: onBrowse,
      onArrowUp: onArrowUp,
      tinted: hasBoundSource,
    );

    final watchlist = onToggleMyWatchlist == null
        ? null
        : CatalogDetailPrimaryButton(
            focusNode: watchlistFocus,
            icon: inMyWatchlist
                ? Icons.bookmark_rounded
                : Icons.bookmark_add_outlined,
            label: inMyWatchlist ? 'In My Watchlist' : 'My Watchlist',
            filled: false,
            compact: compact,
            tv: tv,
            onTap: onToggleMyWatchlist!,
            onArrowUp: onArrowUp,
            tinted: inMyWatchlist,
          );

    if (!showQuickPlay) {
      if (compact) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            browse,
            if (watchlist != null) ...[SizedBox(height: gap), watchlist],
          ],
        );
      }
      return Row(
        children: [
          Expanded(child: browse),
          if (watchlist != null) ...[
            SizedBox(width: gap),
            Expanded(child: watchlist),
          ],
        ],
      );
    }

    // Play is the page's IDENTITY control, so it is where this title's own
    // colour belongs — the one role `ArtworkAccentScope` exists to serve.
    //
    // Gated on `!isLegacy` deliberately. Signal declares `useArtworkAccent`,
    // so `resolve` would hand the poster colour to legacy too, and legacy's
    // Play button has always been this red. New behaviour goes to the themes
    // a user opted into, not to the default look.
    final app = AppThemeScope.of(context);
    final playAccent = app.isLegacy
        ? _kNetflixRed
        : ArtworkAccentScope.resolve(context, app, fallback: _kNetflixRed);
    final play = CatalogDetailPrimaryButton(
      focusNode: playFocus,
      icon: Icons.play_arrow_rounded,
      label: playLabel,
      busy: playBusy,
      filled: true,
      compact: compact,
      tv: tv,
      accent: playAccent,
      // An arbitrary poster colour is an arbitrary fill, so the label is
      // SCORED against it rather than assumed white — the whole reason
      // `inkOn` exists. Legacy keeps its shipped white on the red.
      accentInk: app.isLegacy ? null : app.inkOn(playAccent),
      onTap: onPlay,
      onLongPress: onPlayLongPress,
      onArrowUp: onArrowUp,
    );

    // Narrow screens: stack a full-width Play on top of Sources so every
    // label has room and never gets clipped.
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          play,
          SizedBox(height: gap),
          browse,
          if (watchlist != null) ...[SizedBox(height: gap), watchlist],
        ],
      );
    }

    return Row(
      children: [
        Expanded(flex: 3, child: play),
        SizedBox(width: gap),
        Expanded(flex: 2, child: browse),
        if (watchlist != null) ...[
          SizedBox(width: gap),
          Expanded(flex: 2, child: watchlist),
        ],
      ],
    );
  }
}

const Color _kNetflixRed = Color(0xFFE50914);
