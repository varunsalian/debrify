import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/theme/artwork_accent.dart';
import 'package:debrify/utils/tv_keys.dart';
import 'package:debrify/widgets/detail/theme/detail_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class _ActionRow extends StatelessWidget {
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

  const _ActionRow({
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

    final browse = _PrimaryButton(
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
        : _PrimaryButton(
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
    final play = _PrimaryButton(
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

class _PrimaryButton extends StatefulWidget {
  final FocusNode focusNode;
  final IconData icon;
  final String label;

  /// Filled buttons get a solid background ([accent] when provided, white
  /// otherwise). Outlined buttons have a glass background.
  final bool filled;
  final bool tinted;

  /// Narrow screens: shorter button, smaller icon/text, tighter spacing.
  final bool compact;

  /// TV: skip the focus tween (instant), keep the highlight.
  final bool tv;

  /// Optional brand accent for a filled button. Falls back to white.
  final Color? accent;

  /// Ink for the label ON [accent], scored by the caller.
  ///
  /// Null keeps the shipped rule (`accent == null ? black : white`), which is
  /// right for legacy's fixed red and wrong for an arbitrary poster colour —
  /// white on a pale artwork accent is unreadable.
  final Color? accentInk;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// D-pad "up" handler (TV). Set on the top action row so "up" reveals the
  /// header rather than dead-ending focus traversal.
  final VoidCallback? onArrowUp;

  /// Resume state still resolving — spinner instead of icon+label so the
  /// button never flashes a wrong status. Stays tappable.
  final bool busy;

  const _PrimaryButton({
    required this.focusNode,
    required this.icon,
    required this.label,
    required this.filled,
    required this.onTap,
    this.onLongPress,
    this.busy = false,
    this.compact = false,
    this.tv = false,
    this.tinted = false,
    this.accent,
    this.accentInk,
    this.onArrowUp,
  });

  @override
  State<_PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<_PrimaryButton> {
  bool _focused = false;
  late final TvHoldOk _hold;

  @override
  void initState() {
    super.initState();
    _hold = TvHoldOk(
      onTap: () => widget.onTap(),
      onHold: () => widget.onLongPress?.call(),
    );
  }

  @override
  void dispose() {
    _hold.reset();
    super.dispose();
  }

  void _onPointerLongPress() {
    HapticFeedback.mediumImpact();
    widget.onLongPress?.call();
  }

  @override
  Widget build(BuildContext context) {
    final filled = widget.filled;
    final accent = widget.accent;
    final t = DetailThemeScope.maybeOf(context);

    final filledBg = accent ?? Colors.white;
    final filledFg =
        widget.accentInk ?? (accent == null ? Colors.black : Colors.white);

    final bg = filled
        ? (_focused ? Color.lerp(filledBg, Colors.white, 0.12)! : filledBg)
        : (_focused
              ? Colors.white.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.06));

    final fg = filled ? filledFg : Colors.white;

    // Focus is always shown as a bright gold ring + glow (+ a slight
    // scale-up) regardless of the button's base colour, so it's obvious
    // even on the red Play button.
    final Color borderColor;
    if (_focused) {
      borderColor = t.focus;
    } else if (filled) {
      borderColor = Colors.transparent;
    } else if (widget.tinted) {
      // A bound source: hint with a soft gold resting border.
      borderColor = t.fade(t.focus, 0.5);
    } else {
      borderColor = Colors.white.withValues(alpha: 0.18);
    }
    final borderWidth = _focused ? 2.5 : (filled ? 0.0 : 1.2);

    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (!f) _hold.reset();
      },
      onKeyEvent: (node, event) {
        if (widget.onLongPress != null &&
            isActivateOrSpaceKey(event.logicalKey)) {
          return _hold.handle(event);
        }
        if (event is KeyDownEvent) {
          if (isActivateKey(event.logicalKey) ||
              event.logicalKey == LogicalKeyboardKey.space) {
            widget.onTap();
            return KeyEventResult.handled;
          }
          // Nothing focusable sits above this row, so consume "up" and use
          // it to bring the header back into view instead of no-op.
          if (widget.onArrowUp != null &&
              event.logicalKey == LogicalKeyboardKey.arrowUp) {
            widget.onArrowUp!();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress == null ? null : _onPointerLongPress,
        child: AnimatedScale(
          duration: widget.tv
              ? Duration.zero
              : const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          scale: _focused ? 1.035 : 1.0,
          child: AnimatedContainer(
            duration: widget.tv
                ? Duration.zero
                : const Duration(milliseconds: 160),
            height: widget.compact ? 48 : 54,
            padding: EdgeInsets.symmetric(horizontal: widget.compact ? 10 : 14),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: borderColor, width: borderWidth),
              boxShadow: _focused
                  ? [
                      BoxShadow(
                        color: t.fade(t.focus, 0.55),
                        blurRadius: 30,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            alignment: Alignment.center,
            child: widget.busy
                ? SizedBox(
                    width: widget.compact ? 52 : 64,
                    child: Center(
                      child: SizedBox(
                        width: widget.compact ? 16 : 18,
                        height: widget.compact ? 16 : 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: fg,
                        ),
                      ),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        widget.icon,
                        color: fg,
                        size: widget.compact ? 20 : 24,
                      ),
                      SizedBox(width: widget.compact ? 7 : 10),
                      Flexible(
                        child: Text(
                          widget.label,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: fg,
                            fontSize: widget.compact ? 14 : 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

typedef CatalogActionRow = _ActionRow;

const catalogActionRowConstructor = _ActionRow.new;
