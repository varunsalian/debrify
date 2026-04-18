import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/stremio_tv/stremio_tv_channel.dart';
import '../../../models/stremio_tv/stremio_tv_now_playing.dart';

enum _ChannelRowMenuAction { favorite, export }

/// A single channel row in the Stremio TV guide.
///
/// Premium TV-style card with backdrop poster, channel badge, metadata overlay.
/// Tap to play, favorite via overflow menu or long press.
/// DPAD: left/right moves across Play, Guide, and More actions.
class StremioTvChannelRow extends StatefulWidget {
  final StremioTvChannel channel;
  final StremioTvNowPlaying? nowPlaying;
  final bool isLoading;
  final bool isFocused;
  final FocusNode focusNode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onFavoritePressed;
  final VoidCallback? onExportPressed;
  final VoidCallback? onGuidePressed;
  final VoidCallback? onLeftPress;
  final VoidCallback? onUpPress;
  final double? displayProgress;
  final bool hideNowPlaying;

  const StremioTvChannelRow({
    super.key,
    required this.channel,
    required this.nowPlaying,
    this.isLoading = false,
    required this.isFocused,
    required this.focusNode,
    required this.onTap,
    required this.onLongPress,
    required this.onFavoritePressed,
    this.onExportPressed,
    this.onGuidePressed,
    this.onLeftPress,
    this.onUpPress,
    this.displayProgress,
    this.hideNowPlaying = false,
  });

  @override
  State<StremioTvChannelRow> createState() => _StremioTvChannelRowState();
}

class _StremioTvChannelRowState extends State<StremioTvChannelRow> {
  int _selectedActionIndex = 0;
  final GlobalKey<PopupMenuButtonState<_ChannelRowMenuAction>> _menuKey =
      GlobalKey<PopupMenuButtonState<_ChannelRowMenuAction>>();

  int get _guideActionIndex => 1;

  int get _menuActionIndex => widget.onGuidePressed != null ? 2 : 1;

  int get _maxActionIndex => _menuActionIndex;

  @override
  void didUpdateWidget(StremioTvChannelRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isFocused && oldWidget.isFocused) {
      _selectedActionIndex = 0;
    }
    if (_selectedActionIndex > _maxActionIndex) {
      _selectedActionIndex = _maxActionIndex;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasGuide = widget.onGuidePressed != null;

    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;

        if (event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter) {
          if (_selectedActionIndex == _menuActionIndex) {
            _menuKey.currentState?.showButtonMenu();
          } else if (widget.onGuidePressed != null &&
              _selectedActionIndex == _guideActionIndex) {
            widget.onGuidePressed?.call();
          } else {
            widget.onTap();
          }
          return KeyEventResult.handled;
        }

        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          if (_selectedActionIndex < _maxActionIndex) {
            setState(() => _selectedActionIndex += 1);
          }
          return KeyEventResult.handled;
        }

        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          if (_selectedActionIndex > 0) {
            setState(() => _selectedActionIndex -= 1);
            return KeyEventResult.handled;
          }
          widget.onLeftPress?.call();
          return KeyEventResult.handled;
        }

        if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
            widget.onUpPress != null) {
          widget.onUpPress!();
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 500;
          if (isCompact) {
            return _buildCompactCard(hasGuide);
          }
          return _buildWideCard(hasGuide);
        },
      ),
    );
  }

  /// Wide layout — cinematic card with backdrop
  Widget _buildWideCard(bool hasGuide) {
    final nowPlaying = widget.nowPlaying;
    final posterUrl = nowPlaying?.item.poster;
    final progress = widget.displayProgress ?? nowPlaying?.progress;

    return Container(
      height: 190,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: widget.isFocused
              ? const Color(0xFF6366F1).withValues(alpha: 0.6)
              : Colors.white.withValues(alpha: 0.06),
          width: widget.isFocused ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          child: Stack(
            children: [
              // Backdrop poster (blurred, fills card)
              if (posterUrl != null)
                Positioned.fill(
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                    child: CachedNetworkImage(
                      imageUrl: posterUrl,
                      memCacheWidth: 400,
                      fit: BoxFit.cover,
                      color: Colors.black.withValues(alpha: 0.5),
                      colorBlendMode: BlendMode.darken,
                      errorWidget: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              // Dark gradient overlay
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        const Color(0xFF0A0A14).withValues(alpha: 0.95),
                        const Color(0xFF0A0A14).withValues(alpha: 0.7),
                        const Color(0xFF0A0A14).withValues(alpha: 0.85),
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                ),
              ),
              // Content
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    // Poster thumbnail (sharp)
                    if (nowPlaying != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          width: 85,
                          height: 128,
                          child: Builder(
                            builder: (context) {
                              final image = posterUrl != null
                                  ? CachedNetworkImage(
                                      imageUrl: posterUrl,
                                      memCacheWidth: 300,
                                      fit: BoxFit.cover,
                                      placeholder: (_, __) =>
                                          _posterPlaceholder(),
                                      errorWidget: (_, __, ___) =>
                                          _posterPlaceholder(),
                                    )
                                  : _posterPlaceholder();
                              if (!widget.hideNowPlaying) return image;
                              return ImageFiltered(
                                imageFilter: ImageFilter.blur(
                                  sigmaX: 20,
                                  sigmaY: 20,
                                ),
                                child: image,
                              );
                            },
                          ),
                        ),
                      )
                    else if (widget.isLoading)
                      _buildPosterLoading()
                    else
                      _buildPosterEmpty(),
                    const SizedBox(width: 16),
                    // Info column
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Channel badge row
                          Row(
                            children: [
                              _buildChannelPill(),
                              const SizedBox(width: 8),
                              _buildTypePill(),
                              if (widget.channel.isFavorite) ...[
                                const SizedBox(width: 6),
                                Icon(
                                  Icons.star_rounded,
                                  size: 14,
                                  color: Colors.amber.shade600,
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          // Channel name
                          Text(
                            widget.channel.genre != null
                                ? '${widget.channel.catalog.name} \u2014 ${widget.channel.genre}'
                                : widget.channel.catalog.name,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withValues(alpha: 0.4),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          // Now playing title
                          Text(
                            widget.hideNowPlaying
                                ? _buildTeaserTitle(
                                    nowPlaying?.item.type ?? 'movie',
                                  )
                                : nowPlaying?.item.name ?? 'No content',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              height: 1.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          // Meta row (year, rating, genre)
                          if (nowPlaying != null && !widget.hideNowPlaying)
                            _buildMetaRow(nowPlaying.item)
                          else if (widget.hideNowPlaying)
                            Text(
                              'Press play to find out!',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.4),
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          // Description
                          if (nowPlaying != null &&
                              !widget.hideNowPlaying &&
                              nowPlaying.item.description != null &&
                              nowPlaying.item.description!.isNotEmpty)
                            Flexible(
                              child: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  nowPlaying.item.description!,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.white.withValues(alpha: 0.35),
                                    height: 1.3,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          const Spacer(),
                          // Progress bar
                          if (progress != null && nowPlaying != null)
                            _buildProgressBar(
                              progress,
                              nowPlaying.progressText,
                            ),
                        ],
                      ),
                    ),
                    // Action buttons
                    const SizedBox(width: 12),
                    _buildActionBtn(
                      icon: Icons.play_arrow_rounded,
                      label: 'Play',
                      baseColor: const Color(0xFFDC2626),
                      dpadSelected:
                          widget.isFocused && _selectedActionIndex == 0,
                      onTap: widget.onTap,
                    ),
                    if (hasGuide) ...[
                      const SizedBox(width: 8),
                      _buildActionBtn(
                        icon: Icons.list_rounded,
                        label: 'Guide',
                        baseColor: const Color(0xFF818CF8),
                        dpadSelected:
                            widget.isFocused &&
                            _selectedActionIndex == _guideActionIndex,
                        onTap: widget.onGuidePressed,
                      ),
                    ],
                    const SizedBox(width: 8),
                    _buildOverflowActionBtn(
                      dpadSelected:
                          widget.isFocused &&
                          _selectedActionIndex == _menuActionIndex,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Compact layout for small screens
  Widget _buildCompactCard(bool hasGuide) {
    final nowPlaying = widget.nowPlaying;
    final posterUrl = nowPlaying?.item.poster;
    final progress = widget.displayProgress ?? nowPlaying?.progress;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: widget.isFocused
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: 0.03),
        border: Border.all(
          color: widget.isFocused
              ? const Color(0xFF6366F1).withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.06),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Row(
                  children: [
                    _buildChannelPill(),
                    const SizedBox(width: 8),
                    _buildTypePill(),
                    if (widget.channel.isFavorite) ...[
                      const SizedBox(width: 6),
                      Icon(
                        Icons.star_rounded,
                        size: 14,
                        color: Colors.amber.shade600,
                      ),
                    ],
                    const Spacer(),
                    // Channel info
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            widget.channel.addon.name,
                            style: TextStyle(
                              fontSize: 9,
                              color: Colors.white.withValues(alpha: 0.3),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            widget.channel.genre != null
                                ? '${widget.channel.catalog.name} \u2014 ${widget.channel.genre}'
                                : widget.channel.catalog.name,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Divider(
                  height: 16,
                  thickness: 0.5,
                  color: Colors.white.withValues(alpha: 0.06),
                ),
                // Now playing content
                if (nowPlaying != null) ...[
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 50,
                          height: 72,
                          child: Builder(
                            builder: (context) {
                              final image = posterUrl != null
                                  ? CachedNetworkImage(
                                      imageUrl: posterUrl,
                                      memCacheWidth: 150,
                                      fit: BoxFit.cover,
                                      errorWidget: (_, __, ___) =>
                                          _posterPlaceholder(),
                                    )
                                  : _posterPlaceholder();
                              if (!widget.hideNowPlaying) return image;
                              return ImageFiltered(
                                imageFilter: ImageFilter.blur(
                                  sigmaX: 20,
                                  sigmaY: 20,
                                ),
                                child: image,
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.hideNowPlaying
                                  ? _buildTeaserTitle(nowPlaying.item.type)
                                  : nowPlaying.item.name,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            if (!widget.hideNowPlaying)
                              _buildMetaRow(nowPlaying.item),
                            if (!widget.hideNowPlaying &&
                                nowPlaying.item.description != null &&
                                nowPlaying.item.description!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  nowPlaying.item.description!,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.white.withValues(alpha: 0.35),
                                    height: 1.3,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            const SizedBox(height: 6),
                            if (progress != null)
                              _buildProgressBar(
                                progress,
                                nowPlaying.progressText,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildActionBtn(
                        icon: Icons.play_arrow_rounded,
                        label: 'Play',
                        baseColor: const Color(0xFFDC2626),
                        dpadSelected:
                            widget.isFocused && _selectedActionIndex == 0,
                        onTap: widget.onTap,
                      ),
                      if (hasGuide) ...[
                        const SizedBox(width: 8),
                        _buildActionBtn(
                          icon: Icons.list_rounded,
                          label: 'Guide',
                          baseColor: const Color(0xFF818CF8),
                          dpadSelected:
                              widget.isFocused &&
                              _selectedActionIndex == _guideActionIndex,
                          onTap: widget.onGuidePressed,
                        ),
                      ],
                      const SizedBox(width: 8),
                      _buildOverflowActionBtn(
                        dpadSelected:
                            widget.isFocused &&
                            _selectedActionIndex == _menuActionIndex,
                      ),
                    ],
                  ),
                ] else if (widget.isLoading)
                  Row(
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: Colors.white.withValues(alpha: 0.3),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Loading...',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.3),
                        ),
                      ),
                    ],
                  )
                else
                  Text(
                    'No items available',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.25),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Shared widgets ─────────────────────────────────────────────────────

  Widget _buildChannelPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: const Color(0xFF6366F1).withValues(alpha: 0.15),
        border: Border.all(
          color: const Color(0xFF6366F1).withValues(alpha: 0.25),
          width: 0.5,
        ),
      ),
      child: Text(
        'CH ${widget.channel.channelNumber.toString().padLeft(2, '0')}',
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Color(0xFF818CF8),
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildTypePill() {
    final color = _typeColor(widget.channel.type);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        color: color.withValues(alpha: 0.12),
      ),
      child: Text(
        widget.channel.type.toUpperCase(),
        style: TextStyle(
          fontSize: 9,
          color: color,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildMetaRow(dynamic item) {
    final metaStyle = TextStyle(
      fontSize: 11,
      color: Colors.white.withValues(alpha: 0.5),
    );
    final divider = Text(' | ', style: metaStyle);
    return Row(
      children: [
        if (item.year != null) Text(item.year!, style: metaStyle),
        if (item.year != null && item.imdbRating != null) divider,
        if (item.imdbRating != null) ...[
          Icon(Icons.star_rounded, size: 12, color: Colors.amber.shade600),
          const SizedBox(width: 2),
          Text('${item.imdbRating}', style: metaStyle),
        ],
        if (item.genres != null && item.genres!.isNotEmpty) ...[
          Text(' \u00B7 ', style: metaStyle),
          Flexible(
            child: Text(
              item.genres!.first,
              style: metaStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildProgressBar(double progress, String text) {
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 3,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF6366F1),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(
            fontSize: 10,
            color: Colors.white.withValues(alpha: 0.4),
          ),
        ),
      ],
    );
  }

  Widget _buildActionBtn({
    required IconData icon,
    required String label,
    required Color baseColor,
    required bool dpadSelected,
    VoidCallback? onTap,
  }) {
    return ExcludeFocus(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: dpadSelected
                  ? baseColor
                  : Color.alphaBlend(
                      Colors.white.withValues(alpha: 0.06),
                      baseColor.withValues(alpha: 0.78),
                    ),
              border: dpadSelected
                  ? Border.all(color: Colors.white, width: 2)
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: Colors.white),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
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

  Widget _buildOverflowActionBtn({required bool dpadSelected}) {
    return Tooltip(
      message: 'More options',
      child: ExcludeFocus(
        child: PopupMenuButton<_ChannelRowMenuAction>(
          key: _menuKey,
          tooltip: 'More options',
          color: const Color(0xFF111827),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          onSelected: (action) {
            switch (action) {
              case _ChannelRowMenuAction.favorite:
                widget.onFavoritePressed();
                break;
              case _ChannelRowMenuAction.export:
                widget.onExportPressed?.call();
                break;
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem<_ChannelRowMenuAction>(
              value: _ChannelRowMenuAction.favorite,
              child: Row(
                children: [
                  Icon(
                    widget.channel.isFavorite
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    size: 18,
                    color: const Color(0xFFF59E0B),
                  ),
                  const SizedBox(width: 12),
                  Text(widget.channel.isFavorite ? 'Unfavorite' : 'Favorite'),
                ],
              ),
            ),
            if (widget.channel.isLocal && widget.onExportPressed != null)
              const PopupMenuDivider(),
            if (widget.channel.isLocal && widget.onExportPressed != null)
              const PopupMenuItem<_ChannelRowMenuAction>(
                value: _ChannelRowMenuAction.export,
                child: Row(
                  children: [
                    Icon(
                      Icons.copy_rounded,
                      size: 18,
                      color: Color(0xFF60A5FA),
                    ),
                    SizedBox(width: 12),
                    Text('Copy JSON'),
                  ],
                ),
              ),
          ],
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: dpadSelected
                    ? const Color(0xFF6366F1)
                    : Colors.white.withValues(alpha: 0.08),
                border: Border.all(
                  color: dpadSelected
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.16),
                  width: dpadSelected ? 2 : 1,
                ),
              ),
              child: Icon(
                Icons.more_vert_rounded,
                size: 18,
                color: dpadSelected
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.78),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _posterPlaceholder() {
    return Container(
      color: Colors.white.withValues(alpha: 0.05),
      child: Center(
        child: Icon(
          Icons.movie_rounded,
          size: 24,
          color: Colors.white.withValues(alpha: 0.15),
        ),
      ),
    );
  }

  Widget _buildPosterLoading() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 85,
        height: 128,
        color: Colors.white.withValues(alpha: 0.03),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: Colors.white.withValues(alpha: 0.2),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPosterEmpty() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 85,
        height: 128,
        color: Colors.white.withValues(alpha: 0.03),
        child: Center(
          child: Icon(
            Icons.tv_off_rounded,
            size: 28,
            color: Colors.white.withValues(alpha: 0.1),
          ),
        ),
      ),
    );
  }

  String _buildTeaserTitle(String type) {
    final genre = widget.channel.genre;
    if (genre != null && genre.isNotEmpty) {
      final article = 'aeiouAEIOU'.contains(genre[0]) ? 'An' : 'A';
      final kind = type == 'series' ? 'series' : 'film';
      return '$article $genre $kind awaits...';
    }
    return type == 'series' ? 'A Series awaits...' : 'A Movie awaits...';
  }

  Color _typeColor(String type) {
    switch (type.toLowerCase()) {
      case 'movie':
        return const Color(0xFF60A5FA);
      case 'series':
        return const Color(0xFF34D399);
      case 'anime':
        return const Color(0xFFC084FC);
      default:
        return const Color(0xFF818CF8);
    }
  }
}
