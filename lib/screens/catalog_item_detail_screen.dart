import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/stremio_addon.dart';
import '../widgets/home/home_theme.dart';
import '../widgets/trakt/trakt_menu_helpers.dart';

/// Cinematic detail screen for a catalog item.
///
/// Shows the backdrop hero with a dark scrim, title and metadata, the full
/// description, and primary/secondary actions (Play + Browse Sources).
/// Designed to look premium on phone, tablet, and TV with D-pad support.
class CatalogItemDetailScreen extends StatefulWidget {
  final StremioMeta item;
  final bool isTelevision;
  final bool showQuickPlay;
  final bool hasBoundSource;

  /// Triggers the primary play action.
  final VoidCallback onPlay;

  /// Opens the sources/episodes flow (was "Sources" / "Episodes" in the list).
  final VoidCallback onBrowse;

  /// Pre-built Trakt menu items. When non-empty a "More" button appears
  /// next to Play/Browse.
  final List<PopupMenuEntry<TraktItemMenuAction>> traktMenuItems;

  /// Invoked when the user picks a Trakt action from the "More" menu.
  final void Function(TraktItemMenuAction action)? onTraktAction;

  const CatalogItemDetailScreen({
    super.key,
    required this.item,
    required this.onPlay,
    required this.onBrowse,
    this.isTelevision = false,
    this.showQuickPlay = true,
    this.hasBoundSource = false,
    this.traktMenuItems = const [],
    this.onTraktAction,
  });

  @override
  State<CatalogItemDetailScreen> createState() =>
      _CatalogItemDetailScreenState();
}

class _CatalogItemDetailScreenState extends State<CatalogItemDetailScreen> {
  final FocusNode _playFocus = FocusNode(debugLabel: 'detail-play');
  final FocusNode _browseFocus = FocusNode(debugLabel: 'detail-browse');
  final FocusNode _moreFocus = FocusNode(debugLabel: 'detail-more');

  bool _descriptionExpanded = false;

  @override
  void initState() {
    super.initState();
    if (widget.isTelevision) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          (widget.showQuickPlay ? _playFocus : _browseFocus).requestFocus();
        }
      });
    }
  }

  @override
  void dispose() {
    _playFocus.dispose();
    _browseFocus.dispose();
    _moreFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isWide = size.width >= 900;
    final backdropUrl = widget.item.background ?? widget.item.poster;

    return Scaffold(
      backgroundColor: const Color(0xFF050507),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Backdrop ─────────────────────────────────────────────────────
          // Wide screens: full-bleed. Narrow: top half only.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: isWide ? size.height : size.height * 0.55,
            child: _Backdrop(url: backdropUrl, isWide: isWide),
          ),

          // ── Content ──────────────────────────────────────────────────────
          // On wide layouts, content gravitates to the bottom-left third
          // (Apple-TV/Netflix style). On narrow it scrolls under the
          // backdrop normally.
          SafeArea(
            child: isWide
                ? _buildWideContent(size)
                : _buildNarrowContent(size),
          ),

          // ── Back button ──────────────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: _GlassIconButton(
                  icon: Icons.arrow_back_rounded,
                  onTap: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNarrowContent(Size size) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.only(top: size.height * 0.42, bottom: 32),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: _buildContentColumn(),
      ),
    );
  }

  Widget _buildWideContent(Size size) {
    // Content sheet: bottom-left, max ~52% width, vertically aligned to
    // the lower third so the artwork breathes above it.
    final maxWidth = (size.width * 0.55).clamp(420.0, 720.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(48, 0, 24, 40),
      child: Align(
        alignment: Alignment.bottomLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: _buildContentColumn(),
          ),
        ),
      ),
    );
  }

  Widget _buildContentColumn() {
    final item = widget.item;
    final rating = item.imdbRating;
    final genres = item.genres ?? const [];
    final typeLabel = item.type == 'series' ? 'SERIES' : 'MOVIE';
    final description = item.description ?? '';
    final wide = MediaQuery.of(context).size.width >= 900;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Small uppercase eyebrow above the title.
        Text(
          typeLabel,
          style: TextStyle(
            color: HomeTheme.accent.withValues(alpha: 0.95),
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.4,
          ),
        ),
        SizedBox(height: wide ? 10 : 8),
        // Title — large and condensed
        Text(
          item.name,
          style: TextStyle(
            color: Colors.white,
            fontSize: wide ? 44 : 30,
            fontWeight: FontWeight.w900,
            letterSpacing: -1.0,
            height: 1.0,
          ),
        ),
        SizedBox(height: wide ? 14 : 10),

        // Meta row: YEAR · ⭐ 8.4
        DefaultTextStyle(
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.75),
            fontSize: wide ? 14 : 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
          child: Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (item.year != null && item.year!.isNotEmpty)
                Text(item.year!),
              if (rating != null) ...[
                if (item.year != null && item.year!.isNotEmpty) _dot(),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.star_rounded,
                      size: 16,
                      color: Color(0xFFFACC15),
                    ),
                    const SizedBox(width: 4),
                    Text(rating.toStringAsFixed(1)),
                  ],
                ),
              ],
            ],
          ),
        ),

        if (genres.isNotEmpty) ...[
          SizedBox(height: wide ? 18 : 14),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final g in genres.take(5)) _GenreChip(label: g),
            ],
          ),
        ],

        if (description.isNotEmpty) ...[
          SizedBox(height: wide ? 22 : 18),
          _Description(
            text: description,
            wide: wide,
            expanded: _descriptionExpanded,
            onToggle: () => setState(
              () => _descriptionExpanded = !_descriptionExpanded,
            ),
          ),
        ],

        SizedBox(height: wide ? 30 : 22),

        // Actions
        _ActionRow(
          compact: !wide,
          showQuickPlay: widget.showQuickPlay,
          isSeries: item.type == 'series',
          hasBoundSource: widget.hasBoundSource,
          playFocus: _playFocus,
          browseFocus: _browseFocus,
          moreFocus: _moreFocus,
          traktMenuItems: widget.traktMenuItems,
          onTraktAction: widget.onTraktAction,
          onPlay: () {
            Navigator.of(context).pop();
            widget.onPlay();
          },
          onBrowse: () {
            Navigator.of(context).pop();
            widget.onBrowse();
          },
        ),
      ],
    );
  }

  Widget _dot() => Text(
        '·',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.4),
          fontSize: 14,
        ),
      );
}

// ── Backdrop ────────────────────────────────────────────────────────────────

class _Backdrop extends StatelessWidget {
  final String? url;
  final bool isWide;
  const _Backdrop({required this.url, required this.isWide});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (url != null && url!.isNotEmpty)
          Image.network(
            url!,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            errorBuilder: (_, __, ___) => Container(color: Colors.black),
          )
        else
          Container(color: Colors.black),

        // Vertical scrim
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: isWide
                  ? const [
                      Color(0x33000000),
                      Color(0x66000000),
                      Color(0xCC050507),
                      Color(0xFF050507),
                    ]
                  : const [
                      Color(0x33000000),
                      Color(0x66000000),
                      Color(0xCC050507),
                      Color(0xFF050507),
                    ],
              stops: isWide
                  ? const [0.0, 0.4, 0.78, 1.0]
                  : const [0.0, 0.45, 0.85, 1.0],
            ),
          ),
        ),

        // Side scrim on wide layouts — darken the left where content sits,
        // fade to clear art on the right.
        if (isWide)
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Color(0xDD050507),
                  Color(0x88050507),
                  Color(0x22000000),
                  Color(0x00000000),
                ],
                stops: [0.0, 0.35, 0.65, 1.0],
              ),
            ),
          ),
      ],
    );
  }
}

// ── Genre chip ──────────────────────────────────────────────────────────────

class _GenreChip extends StatelessWidget {
  final String label;
  const _GenreChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
          width: 0.5,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.85),
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

// ── Description with "Read more" ───────────────────────────────────────────

class _Description extends StatelessWidget {
  final String text;
  final bool wide;
  final bool expanded;
  final VoidCallback onToggle;
  const _Description({
    required this.text,
    required this.wide,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: Colors.white.withValues(alpha: 0.82),
      fontSize: wide ? 17 : 15,
      height: 1.5,
      letterSpacing: 0.1,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final tp = TextPainter(
          text: TextSpan(text: text, style: style),
          maxLines: 4,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: constraints.maxWidth);
        final overflows = tp.didExceedMaxLines;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text,
              style: style,
              maxLines: expanded ? null : 4,
              overflow: expanded ? TextOverflow.visible : TextOverflow.fade,
            ),
            if (overflows) ...[
              const SizedBox(height: 6),
              GestureDetector(
                onTap: onToggle,
                child: Text(
                  expanded ? 'Show less' : 'Read more',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.95),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

// ── Action row (PLAY + BROWSE) ──────────────────────────────────────────────

class _ActionRow extends StatelessWidget {
  final bool compact;
  final bool showQuickPlay;
  final bool isSeries;
  final bool hasBoundSource;
  final FocusNode playFocus;
  final FocusNode browseFocus;
  final FocusNode moreFocus;
  final List<PopupMenuEntry<TraktItemMenuAction>> traktMenuItems;
  final void Function(TraktItemMenuAction action)? onTraktAction;
  final VoidCallback onPlay;
  final VoidCallback onBrowse;

  const _ActionRow({
    required this.compact,
    required this.showQuickPlay,
    required this.isSeries,
    required this.hasBoundSource,
    required this.playFocus,
    required this.browseFocus,
    required this.moreFocus,
    required this.traktMenuItems,
    required this.onTraktAction,
    required this.onPlay,
    required this.onBrowse,
  });

  @override
  Widget build(BuildContext context) {
    final browseLabel = isSeries ? 'Episodes' : 'Sources';
    final browseIcon = isSeries ? Icons.list_alt_rounded : Icons.layers_rounded;
    final hasMore = traktMenuItems.isNotEmpty && onTraktAction != null;
    final gap = compact ? 8.0 : 10.0;
    final moreWidth = compact ? 48.0 : 56.0;

    final browse = _PrimaryButton(
      focusNode: browseFocus,
      icon: browseIcon,
      label: browseLabel,
      filled: !showQuickPlay,
      compact: compact,
      onTap: onBrowse,
      tinted: hasBoundSource,
    );

    final more = hasMore
        ? _MoreButton(
            focusNode: moreFocus,
            compact: compact,
            items: traktMenuItems,
            onSelected: onTraktAction!,
          )
        : null;

    if (!showQuickPlay) {
      if (more == null) return browse;
      return Row(
        children: [
          Expanded(child: browse),
          SizedBox(width: gap),
          SizedBox(width: moreWidth, child: more),
        ],
      );
    }

    final play = _PrimaryButton(
      focusNode: playFocus,
      icon: Icons.play_arrow_rounded,
      label: 'Play',
      filled: true,
      compact: compact,
      accent: _kNetflixRed,
      onTap: onPlay,
    );

    // Narrow screens: stack a full-width Play on top of the secondary
    // actions so every label has room and never gets clipped.
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          play,
          SizedBox(height: gap),
          if (more == null)
            browse
          else
            Row(
              children: [
                Expanded(child: browse),
                SizedBox(width: gap),
                SizedBox(width: moreWidth, child: more),
              ],
            ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(flex: 3, child: play),
        SizedBox(width: gap),
        Expanded(flex: 2, child: browse),
        if (more != null) ...[
          SizedBox(width: gap),
          SizedBox(width: moreWidth, child: more),
        ],
      ],
    );
  }
}

const Color _kNetflixRed = Color(0xFFE50914);

/// Icon-only "More" button. Matches the visual height of [_PrimaryButton]
/// and opens a popup menu with the supplied Trakt items.
class _MoreButton extends StatefulWidget {
  final FocusNode focusNode;
  final bool compact;
  final List<PopupMenuEntry<TraktItemMenuAction>> items;
  final void Function(TraktItemMenuAction) onSelected;

  const _MoreButton({
    required this.focusNode,
    required this.compact,
    required this.items,
    required this.onSelected,
  });

  @override
  State<_MoreButton> createState() => _MoreButtonState();
}

class _MoreButtonState extends State<_MoreButton> {
  bool _focused = false;
  final GlobalKey<PopupMenuButtonState<TraktItemMenuAction>> _menuKey =
      GlobalKey();

  void _open() => _menuKey.currentState?.showButtonMenu();

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space)) {
          _open();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: widget.compact ? 48 : 54,
        decoration: BoxDecoration(
          color: _focused
              ? Colors.white.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _focused
                ? Colors.white
                : Colors.white.withValues(alpha: 0.18),
            width: 1.2,
          ),
          boxShadow: _focused
              ? [
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.35),
                    blurRadius: 22,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: PopupMenuButton<TraktItemMenuAction>(
          key: _menuKey,
          tooltip: 'More',
          padding: EdgeInsets.zero,
          color: const Color(0xFF111118),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: Colors.white.withValues(alpha: 0.08),
              width: 0.5,
            ),
          ),
          onSelected: widget.onSelected,
          itemBuilder: (_) => widget.items,
          child: Center(
            child: Icon(
              Icons.more_horiz_rounded,
              color: Colors.white,
              size: widget.compact ? 20 : 22,
            ),
          ),
        ),
      ),
    );
  }
}

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

  /// Optional brand accent for a filled button. Falls back to white.
  final Color? accent;
  final VoidCallback onTap;

  const _PrimaryButton({
    required this.focusNode,
    required this.icon,
    required this.label,
    required this.filled,
    required this.onTap,
    this.compact = false,
    this.tinted = false,
    this.accent,
  });

  @override
  State<_PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<_PrimaryButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final filled = widget.filled;
    final accent = widget.accent;

    final filledBg = accent ?? Colors.white;
    final filledFg = accent == null ? Colors.black : Colors.white;
    final outlineAccent = widget.tinted ? HomeTheme.accent : Colors.white;

    final bg = filled
        ? (_focused
            ? Color.lerp(filledBg, Colors.white, 0.12)!
            : filledBg)
        : (_focused
            ? Colors.white.withValues(alpha: 0.18)
            : Colors.white.withValues(alpha: 0.06));

    final fg = filled ? filledFg : Colors.white;
    final borderColor = filled
        ? Colors.transparent
        : (_focused ? outlineAccent : Colors.white.withValues(alpha: 0.18));

    final glowColor =
        filled ? (accent ?? Colors.white) : Colors.white;

    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: widget.compact ? 48 : 54,
          padding: EdgeInsets.symmetric(horizontal: widget.compact ? 10 : 14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor, width: filled ? 0 : 1.2),
            boxShadow: _focused
                ? [
                    BoxShadow(
                      color: glowColor.withValues(alpha: 0.45),
                      blurRadius: 26,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, color: fg, size: widget.compact ? 20 : 24),
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
    );
  }
}

// ── Glass icon button (back) ────────────────────────────────────────────────

class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _GlassIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.18),
              width: 0.5,
            ),
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

