import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/trakt/trakt_episode_model.dart';
import '../theme/widgets/themed_artwork.dart';
import '../utils/tv_keys.dart';
import 'detail/theme/detail_theme.dart';
import 'trakt/trakt_menu_helpers.dart';
import 'home/home_theme.dart';

/// OTT episode card. A big 16:9 still (play / resume bar / badge live on the
/// image), with the title/meta/synopsis on the solid card — below the still
/// on phones, beside it on wide screens so it fills the width. One shared
/// widget for the Trakt and Catalog episode lists. Tap / SELECT triggers the
/// primary action (Play, or Sources when quick-play is hidden).
class EpisodeTile extends StatefulWidget {
  final TraktEpisode episode;
  final String? showImageUrl;
  final bool isTelevision;
  final bool showQuickPlay;
  final double? watchProgress; // 0..100
  final bool isNext;
  final FocusNode? focusNode;
  final VoidCallback onPlay;
  final VoidCallback onSources;

  /// Trakt-only: mark watched/unwatched + rate. Null on the catalog path.
  final void Function(TraktEpisodeMenuAction action)? onMenuAction;

  const EpisodeTile({
    super.key,
    required this.episode,
    required this.isTelevision,
    required this.onPlay,
    required this.onSources,
    this.showImageUrl,
    this.showQuickPlay = true,
    this.watchProgress,
    this.isNext = false,
    this.focusNode,
    this.onMenuAction,
  });

  @override
  State<EpisodeTile> createState() => _EpisodeTileState();
}

class _EpisodeTileState extends State<EpisodeTile> {
  bool _focused = false;
  bool _hovered = false;
  bool get _active => _focused || _hovered;

  /// Resolved once per dependency change, never inside the LayoutBuilder below
  /// — `_still` and `_actionRow` run inside that callback, and a long episode
  /// list on a TV box cannot afford a lookup per row per layout pass.
  ///
  /// Signal today: no caller wraps this tile in a [DetailThemeScope], so the
  /// fallback IS the shipped gold.
  late DetailTheme _t;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _t = DetailThemeScope.maybeOf(context);
  }

  /// D-pad selection within the action row while the card holds focus.
  int _sel = 0;

  void _primary() =>
      widget.showQuickPlay ? widget.onPlay() : widget.onSources();

  /// Action row contents (left → right). Index 0 is the primary.
  List<_EpAction> _epActions() {
    final watched = (widget.watchProgress ?? 0) >= 100;
    return [
      _EpAction(
        icon: widget.showQuickPlay
            ? Icons.play_arrow_rounded
            : Icons.layers_rounded,
        label: widget.showQuickPlay ? 'Play' : 'Sources',
        primary: true,
        onTap: _primary,
      ),
      _EpAction(
        icon: Icons.layers_rounded,
        label: 'Sources',
        onTap: widget.onSources,
      ),
      if (widget.onMenuAction != null) ...[
        _EpAction(
          icon: watched
              ? Icons.visibility_off_rounded
              : Icons.check_circle_rounded,
          label: watched ? 'Unwatch' : 'Watched',
          iconOnly: true,
          onTap: () => widget.onMenuAction!(
            watched
                ? TraktEpisodeMenuAction.markUnwatched
                : TraktEpisodeMenuAction.markWatched,
          ),
        ),
        _EpAction(
          icon: Icons.star_rounded,
          label: 'Rate',
          iconOnly: true,
          onTap: () => widget.onMenuAction!(TraktEpisodeMenuAction.rate),
        ),
      ],
    ];
  }

  Duration get _fx => widget.isTelevision
      ? Duration.zero
      : const Duration(milliseconds: 170);

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (f) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Scrollable.ensureVisible(
              context,
              alignment: 0.5,
              alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
              duration: widget.isTelevision
                  ? Duration.zero
                  : const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
            );
          });
        }
      },
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final acts = _epActions();
        final k = event.logicalKey;
        if (k == LogicalKeyboardKey.arrowRight) {
          if (_sel < acts.length - 1) setState(() => _sel++);
          return KeyEventResult.handled; // stay within the card
        }
        if (k == LogicalKeyboardKey.arrowLeft) {
          if (_sel > 0) setState(() => _sel--);
          return KeyEventResult.handled;
        }
        if (isActivateKey(k) || k == LogicalKeyboardKey.space) {
          acts[_sel.clamp(0, acts.length - 1)].onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored; // ↑/↓ → move between episodes
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: _primary,
          behavior: HitTestBehavior.opaque,
          child: AnimatedScale(
            duration: _fx,
            curve: Curves.easeOutCubic,
            scale: _active ? 1.012 : 1.0,
            child: AnimatedContainer(
              duration: _fx,
              decoration: BoxDecoration(
                color: const Color(0xFF14141C),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _active
                      ? _t.focus
                      : Colors.white.withValues(alpha: 0.06),
                  width: _active ? 2.5 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: _active ? 0.55 : 0.3),
                    blurRadius: _active ? 28 : 12,
                    offset: const Offset(0, 10),
                  ),
                  if (_active)
                    BoxShadow(
                      color: _t.fade(_t.focus, 0.38),
                      blurRadius: 32,
                      spreadRadius: 1,
                    ),
                ],
              ),
              child: LayoutBuilder(
                builder: (context, c) {
                  final wide = c.maxWidth >= 560;
                  return wide ? _horizontal() : _vertical();
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Layouts ───────────────────────────────────────────────────────────────

  Widget _vertical() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ThemedArtwork(
              role: ArtRole.still,
              // Zero, because zero is what this layout gives the still today:
              // the card's own clip above rounds the two TOP corners and the
              // info block covers the bottom two, so the image itself has
              // never carried a radius of its own here.
              radius: 0,
              inList: true,
              builder: (context, blend) => _still(blend),
              overlay: _stillChrome(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: _info(synopsisLines: 2),
          ),
        ],
      ),
    );
  }

  Widget _horizontal() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 300,
            child: AspectRatio(
              aspectRatio: 16 / 9,
              // The still's own clip, handed to [ThemedArtwork] so the frame
              // is the theme's rather than this file's.
              child: ThemedArtwork(
                role: ArtRole.still,
                radius: 12,
                inList: true,
                builder: (context, blend) => _still(blend),
                overlay: _stillChrome(),
              ),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: _info(synopsisLines: 3),
            ),
          ),
        ],
      ),
    );
  }

  // ── Pieces ────────────────────────────────────────────────────────────────

  /// The still and everything drawn over it. [blend] is the theme's grade,
  /// which has to reach the image constructor itself — a filter layer per row
  /// is the cost this widget's whole build is written to avoid.
  /// The still ITSELF — nothing painted on it.
  ///
  /// Split from [_stillChrome] because `ThemedArtwork`'s frame is a treatment
  /// of the image: handing it the whole stack made a `faded` look dissolve the
  /// progress bar along the bottom edge, which is where progress bars live.
  Widget _still((Color, BlendMode)? blend) {
    final e = widget.episode;
    final img = (e.thumbnailUrl != null && e.thumbnailUrl!.isNotEmpty)
        ? e.thumbnailUrl!
        : (widget.showImageUrl ?? '');
    if (img.isEmpty) return _imgFallback(e);
    return CachedNetworkImage(
      imageUrl: img,
      fit: BoxFit.cover,
      color: blend?.$1,
      colorBlendMode: blend?.$2,
      placeholder: (_, __) => _imgFallback(e),
      errorWidget: (_, __, ___) => _imgFallback(e),
    );
  }

  /// Everything painted ON the still: the legibility vignette, the play glyph,
  /// the watched tick and the progress bar.
  Widget _stillChrome() {
    final e = widget.episode;
    final progress = (widget.watchProgress ?? 0).clamp(0.0, 100.0);
    final watched = progress >= 100;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Light vignette so the play glyph + badge read on any still.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              radius: 0.9,
              colors: [Color(0x00000000), Color(0x59000000)],
            ),
          ),
        ),

        Center(
          child: AnimatedContainer(
            duration: _fx,
            width: _active ? 58 : 50,
            height: _active ? 58 : 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withValues(alpha: 0.42),
              border: Border.all(
                color: _active
                    ? _t.focus
                    : Colors.white.withValues(alpha: 0.85),
                width: 2,
              ),
            ),
            child: Icon(
              widget.showQuickPlay
                  ? Icons.play_arrow_rounded
                  : Icons.layers_rounded,
              color: Colors.white,
              size: _active ? 30 : 26,
            ),
          ),
        ),

        if (widget.isNext)
          const Positioned(
            top: 8,
            left: 8,
            child: _Chip(label: 'UP NEXT', color: Color(0xFFFBBF24),
                filled: true),
          )
        else if (watched)
          const Positioned(
            top: 8,
            left: 8,
            child: _Chip(label: 'WATCHED', color: Color(0xFF34D399)),
          ),

        if (e.rating != null && e.rating! > 0)
          Positioned(
            top: 8,
            right: 8,
            child: _RatingPill(value: e.rating!),
          ),

        if (progress > 0 && progress < 100)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SizedBox(
              height: 4,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: Colors.white.withValues(alpha: 0.22)),
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: progress / 100.0,
                    child: const ColoredBox(color: Color(0xFFE50914)),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _info({required int synopsisLines}) {
    final e = widget.episode;
    final title = (e.title.isNotEmpty && e.title != 'Episode ${e.number}')
        ? e.title
        : 'Episode ${e.number}';
    final meta = <String>[
      'S${e.season} · E${e.number}',
      if (e.runtime != null && e.runtime! > 0) '${e.runtime}m',
      if (e.formattedAirDate != null) e.formattedAirDate!,
    ].join('  ·  ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          meta,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          // Deliberately NOT the theme's focus: this is gold INK, and the card
          // it sits on is pinned to a dark literal (see `build`). A light
          // theme's focus colour here would be dark-on-dark. Migrate the two
          // together, or not at all.
          style: TextStyle(
            color: HomeTheme.focusGold.withValues(alpha: 0.95),
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
            height: 1.15,
          ),
        ),
        if (e.overview != null && e.overview!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            e.overview!,
            maxLines: synopsisLines,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.62),
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
        const SizedBox(height: 12),
        _actionRow(),
      ],
    );
  }

  Widget _actionRow() {
    final acts = _epActions();
    final sel = _sel.clamp(0, acts.length - 1);
    // One row, labels kept. When narrow, the pills shrink (smaller
    // padding/font/gap); the labelled ones are Flexible so they ellipsize
    // as a last resort instead of clipping.
    return LayoutBuilder(
      builder: (context, c) {
        final compact = c.maxWidth < 380;
        final gap = compact ? 6.0 : 8.0;
        final children = <Widget>[];
        for (var i = 0; i < acts.length; i++) {
          if (i > 0) children.add(SizedBox(width: gap));
          final chip = _ActionChip(
            action: acts[i],
            selected: _focused && i == sel,
            compact: compact,
            theme: _t,
            onTap: acts[i].onTap,
          );
          children.add(acts[i].iconOnly ? chip : Flexible(child: chip));
        }
        return Row(children: children);
      },
    );
  }

  Widget _imgFallback(TraktEpisode e) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1B1B24), Color(0xFF101017)],
        ),
      ),
      child: Center(
        child: Text(
          'E${e.number}',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.16),
            fontSize: 52,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

/// IMDb-style rating pill (top-right of the still).
class _RatingPill extends StatelessWidget {
  final double value;
  const _RatingPill({required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.18),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, size: 11, color: Color(0xFFFACC15)),
          const SizedBox(width: 3),
          Text(
            value.toStringAsFixed(1),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  final bool filled;
  const _Chip({required this.label, required this.color, this.filled = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? color : Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color, width: filled ? 0 : 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: filled ? Colors.black : color,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}
/// One action-row entry (Play / Sources / Watched / Rate).
class _EpAction {
  final IconData icon;
  final String label;
  final bool primary;
  final bool iconOnly;
  final VoidCallback onTap;
  const _EpAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.iconOnly = false,
  });
}

/// Display-only action chip. The parent card owns focus and drives the
/// [selected] highlight via D-pad; this stays tappable for mouse/touch.
class _ActionChip extends StatelessWidget {
  final _EpAction action;
  final bool selected;
  final bool compact;

  /// Passed down rather than looked up: the parent already resolved it, and
  /// this chip is rebuilt for every action of every visible episode row.
  final DetailTheme theme;
  final VoidCallback onTap;

  const _ActionChip({
    required this.action,
    required this.selected,
    required this.theme,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final gold = theme.focus;
    final border = selected
        ? gold
        : (action.primary
            ? Colors.transparent
            : Colors.white.withValues(alpha: 0.16));
    final glow = selected
        ? [
            BoxShadow(
              color: theme.fade(gold, 0.4),
              blurRadius: 16,
              spreadRadius: 1,
            ),
          ]
        : null;

    final iconMode = action.iconOnly;
    final Widget child;
    if (iconMode) {
      final d = compact ? 32.0 : 38.0;
      child = Container(
        width: d,
        height: d,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: action.primary
              ? const Color(0xFFE50914)
              : Colors.white.withValues(alpha: selected ? 0.16 : 0.08),
          border: Border.all(color: border, width: selected ? 2 : 1),
          boxShadow: glow,
        ),
        child: Icon(
          action.icon,
          size: compact ? 15 : 17,
          color: Colors.white.withValues(
            alpha: (selected || action.primary) ? 1.0 : 0.9,
          ),
        ),
      );
    } else {
      child = Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 14,
          vertical: compact ? 7 : 9,
        ),
        decoration: BoxDecoration(
          color: action.primary
              ? const Color(0xFFE50914)
              : Colors.white.withValues(alpha: selected ? 0.16 : 0.10),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: border, width: selected ? 2 : 1),
          boxShadow: glow,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(action.icon, size: compact ? 14 : 16, color: Colors.white),
            SizedBox(width: compact ? 5 : 6),
            Flexible(
              child: Text(
                action.label,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compact ? 12 : 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Tooltip(
          message: iconMode ? action.label : '',
          child: child,
        ),
      ),
    );
  }
}
