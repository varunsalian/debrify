import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/youtube_service.dart';
import '../../theme/app_theme_scope.dart';
import '../browse/brand_accent.dart';
import '../../utils/tv_keys.dart';

/// Vertical grid card for a YouTube video: 16:9 thumbnail on top, then a
/// channel-avatar + title + meta block below. Mirrors the app's premium
/// focus language (scale + gold ring/glow) shared with the poster/IPTV grids.
class YoutubeVideoCard extends StatefulWidget {
  final YoutubeVideo video;
  final VoidCallback onTap;
  final VoidCallback? onDownload;
  final FocusNode? focusNode;
  final bool isTelevision;

  const YoutubeVideoCard({
    super.key,
    required this.video,
    required this.onTap,
    this.onDownload,
    this.focusNode,
    this.isTelevision = false,
  });

  @override
  State<YoutubeVideoCard> createState() => _YoutubeVideoCardState();
}

class _YoutubeVideoCardState extends State<YoutubeVideoCard> {
  late FocusNode _focusNode;
  bool _focused = false;
  bool _hovered = false;
  bool get _active => _focused || _hovered;

  // Press-and-hold detection for the remote OK button (TV has no pointer
  // long-press). A held OK fires [onDownload]; a quick tap fires [onTap].
  Timer? _holdTimer;
  bool _longPressFired = false;
  static const Duration _holdDuration = Duration(milliseconds: 600);

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _focusNode.removeListener(_onFocusChange);
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  void _onFocusChange() {
    if (mounted) setState(() => _focused = _focusNode.hasFocus);
  }

  String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final app = AppThemeScope.of(context);
    final video = widget.video;

    final metaParts = <String>[
      if (video.formattedViews.isNotEmpty) video.formattedViews,
      if (video.publishedLabel != null && video.publishedLabel!.isNotEmpty)
        video.publishedLabel!,
    ];

    final fx = widget.isTelevision
        ? Duration.zero
        : const Duration(milliseconds: 160);

    return Focus(
      focusNode: _focusNode,
      onFocusChange: (f) {
        if (f) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Scrollable.ensureVisible(
              context,
              alignment: 0.5,
              alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
              duration: widget.isTelevision
                  ? Duration.zero
                  : const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
            );
          });
        }
      },
      onKeyEvent: (node, event) {
        if (!isActivateKey(event.logicalKey)) return KeyEventResult.ignored;
        // Start of a press: arm the hold timer (ignore auto-repeat).
        if (event is KeyDownEvent) {
          _longPressFired = false;
          _holdTimer?.cancel();
          final onDownload = widget.onDownload;
          if (onDownload != null) {
            _holdTimer = Timer(_holdDuration, () {
              _longPressFired = true;
              onDownload();
            });
          }
          return KeyEventResult.handled;
        }
        // Swallow repeats so a held key doesn't re-fire the tap.
        if (event is KeyRepeatEvent) return KeyEventResult.handled;
        // Release: a quick tap (hold hadn't fired yet) plays the video.
        if (event is KeyUpEvent) {
          _holdTimer?.cancel();
          _holdTimer = null;
          if (!_longPressFired) widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          onLongPress: widget.onDownload,
          behavior: HitTestBehavior.opaque,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Thumbnail
              AspectRatio(
                aspectRatio: 16 / 9,
                child: AnimatedScale(
                  duration: fx,
                  curve: Curves.easeOutCubic,
                  scale: _active ? 1.03 : 1.0,
                  child: AnimatedContainer(
                    duration: fx,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black
                              .withValues(alpha: _active ? 0.55 : 0.3),
                          blurRadius: _active ? 28 : 12,
                          offset: const Offset(0, 10),
                        ),
                        if (_active)
                          BoxShadow(
                            color: app.youtube.focus.withValues(alpha: 0.5),
                            blurRadius: 30,
                            spreadRadius: 1,
                          ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Container(
                            color: colorScheme.surfaceContainerHigh,
                            child: video.thumbnailUrl != null
                                ? Image.network(
                                    video.thumbnailUrl!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        _thumbFallback(colorScheme),
                                  )
                                : _thumbFallback(colorScheme),
                          ),
                          if (video.durationSeconds != null)
                            Positioned(
                              bottom: 6,
                              right: 6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.82),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text(
                                  _formatDuration(video.durationSeconds!),
                                  style: TextStyle(
                                    // On the badge's black glass, not on the
                                    // page: page ink would vanish here.
                                    color: app.onGlass,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          if (_active)
                            const Positioned.fill(child: _PlayOverlay()),
                          if (_active)
                            Positioned.fill(
                              child: IgnorePointer(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: app.youtube.focus,
                                      width: 2.5,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 11),

              // Meta: channel avatar + title + author + stats
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ChannelAvatar(author: video.author),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            video.title,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            video.author,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (metaParts.isNotEmpty)
                            Text(
                              metaParts.join(' • '),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.85),
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
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

  Widget _thumbFallback(ColorScheme colorScheme) {
    return Center(
      child: Icon(
        Icons.play_circle_outline,
        size: 40,
        color: colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// Number of YouTube grid columns. One column on phones (full-width thumbnail
/// with meta beneath, à la mobile YouTube), scaling up on wider screens/TV.
int youtubeGridColumnsFor(double width, {bool isTelevision = false}) {
  if (isTelevision || width >= 1600) return 4;
  if (width >= 1100) return 3;
  if (width >= 680) return 2;
  return 1;
}

class _PlayOverlay extends StatelessWidget {
  const _PlayOverlay();

  @override
  Widget build(BuildContext context) {
    // The scrim and the disc are black glass over an arbitrary thumbnail and
    // stay black on every theme, so their ink is `onGlass`, not page text.
    final onGlass = AppThemeScope.of(context).onGlass;
    return IgnorePointer(
      child: Container(
        color: Colors.black.withValues(alpha: 0.28),
        alignment: Alignment.center,
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            shape: BoxShape.circle,
            border: Border.all(
              color: onGlass.withValues(alpha: 0.55),
              width: 1.5,
            ),
          ),
          child: Icon(Icons.play_arrow_rounded, size: 26, color: onGlass),
        ),
      ),
    );
  }
}

/// Circular channel monogram, tinted by a stable per-channel accent.
class _ChannelAvatar extends StatelessWidget {
  final String author;
  const _ChannelAvatar({required this.author});

  @override
  Widget build(BuildContext context) {
    final trimmed = author.trim();
    final letter = trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
    final color = brandAccentFor(author);
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, HSLColor.fromColor(color).withLightness(0.42).toColor()],
        ),
      ),
      child: Text(
        letter,
        // Deliberately literal: the disc is a RUNTIME brand accent, so no
        // token holds this value. `app.inkOn(color)` is the right role but
        // would flip the monogram to near-black on the lighter hues — a
        // visible change today — so this waits for its own pass.
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
