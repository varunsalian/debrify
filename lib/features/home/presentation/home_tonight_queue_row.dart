import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/stremio_addon.dart';
import '../../../theme/app_theme_scope.dart';
import '../../../utils/tv_keys.dart';
import '../../../widgets/home/home_theme.dart';
import '../application/home_stage_metadata.dart';

/// One row of Tonight's Continue queue: a 16:9 still, the title, the episode
/// and a progress bar. Carries the same focus grammar and the same hold-OK
/// menu as a Continue Watching card, so nothing is lost by laying the row out
/// horizontally instead of as a poster.
class HomeTonightQueueRow extends StatefulWidget {
  final StremioMeta item;
  final double height;

  /// Width of the still, capped by the queue layout upstream.
  final double thumbWidth;
  final FocusNode focusNode;
  final String? episode;
  final double? progress;

  /// Mirrors the board cards' bookmark mark — a title with a source already
  /// bound plays without picking one, and that is worth seeing here too.
  final bool hasBoundSource;
  final VoidCallback onFocused;
  final VoidCallback onOpen;
  final VoidCallback onLongPress;
  final VoidCallback onUp;
  final VoidCallback onDown;

  /// Held DOWN override. Null keeps a held key stepping one row at a time.
  final VoidCallback? onDownHold;
  final VoidCallback onLeft;

  const HomeTonightQueueRow({
    super.key,
    required this.item,
    required this.height,
    required this.thumbWidth,
    required this.focusNode,
    required this.episode,
    required this.progress,
    required this.hasBoundSource,
    required this.onFocused,
    required this.onOpen,
    required this.onLongPress,
    required this.onUp,
    required this.onDown,
    this.onDownHold,
    required this.onLeft,
  });

  @override
  State<HomeTonightQueueRow> createState() => _HomeTonightQueueRowState();
}

class _HomeTonightQueueRowState extends State<HomeTonightQueueRow>
    with SingleTickerProviderStateMixin {
  bool _focused = false;
  bool _keyDown = false;
  bool _holdFired = false;
  bool _holding = false;

  /// Same 500ms hold-OK the Continue Watching cards use.
  static const _holdDuration = Duration(milliseconds: 500);
  late final AnimationController _holdController = AnimationController(
    vsync: this,
    duration: _holdDuration,
  );

  @override
  void initState() {
    super.initState();
    _holdController.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        _holdFired = true;
        setState(() => _holding = false);
        _holdController.reset();
        widget.onLongPress();
      }
    });
  }

  @override
  void dispose() {
    _holdController.dispose();
    super.dispose();
  }

  void _cancelHold() {
    _holdController.reset();
    if (_holding && mounted) setState(() => _holding = false);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) {
      if (isActivateKey(event.logicalKey) ||
          event.logicalKey == LogicalKeyboardKey.space) {
        final wasPress = _keyDown && !_holdFired;
        _keyDown = false;
        _holdFired = false;
        _cancelHold();
        if (wasPress) widget.onOpen();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (isActivateKey(key) || key == LogicalKeyboardKey.space) {
      if (event is KeyDownEvent) {
        _keyDown = true;
        _holdFired = false;
        setState(() => _holding = true);
        _holdController.forward(from: 0);
      }
      // Swallow auto-repeat while held.
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      widget.onUp();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (event is KeyRepeatEvent && widget.onDownHold != null) {
        widget.onDownHold!();
      } else {
        widget.onDown();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      widget.onLeft();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      // Nothing to the right of the queue — swallow it so Flutter's geometric
      // traversal can't wander into the rail below.
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final h = widget.height;
    final thumbW = widget.thumbWidth;
    final art = homeStageWideArtwork(widget.item);
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (!f) {
          _keyDown = false;
          _holdFired = false;
          _cancelHold();
        } else {
          widget.onFocused();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Scrollable.ensureVisible(
              context,
              alignment: 0.5,
              alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOutCubic,
            );
          });
        }
      },
      onKeyEvent: _onKey,
      child: GestureDetector(
        onTap: widget.onOpen,
        onLongPress: widget.onLongPress,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          height: h,
          decoration: BoxDecoration(
            color: app.fade(app.core.tx, _focused ? 0.10 : 0.045),
            borderRadius: app.shape.br(10),
            border: Border.all(
              color: _focused ? app.core.tx : app.fade(app.core.tx, 0.06),
              width: _focused ? 2.5 : 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: app.shape.br(9),
            child: Row(
              children: [
                SizedBox(
                  width: thumbW,
                  height: h,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const ColoredBox(color: Color(0xFF171426)),
                      if (art != null && art.isNotEmpty)
                        CachedNetworkImage(
                          imageUrl: art,
                          fit: BoxFit.cover,
                          memCacheWidth: 420,
                          fadeInDuration: HomeTheme.imageFadeIn(true),
                          fadeOutDuration: HomeTheme.imageFadeOut(true),
                          errorWidget: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      if (widget.hasBoundSource)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Icon(
                            Icons.bookmark_rounded,
                            size: 15,
                            color: app.core.tx,
                            shadows: const [
                              Shadow(color: Colors.black, blurRadius: 6),
                            ],
                          ),
                        ),
                      if (_holding) const ColoredBox(color: Color(0x730A0810)),
                      if (_holding)
                        Center(
                          child: SizedBox(
                            width: 26,
                            height: 26,
                            child: AnimatedBuilder(
                              animation: _holdController,
                              builder: (context, _) =>
                                  CircularProgressIndicator(
                                    value: _holdController.value,
                                    strokeWidth: 2.5,
                                    color: app.core.tx,
                                    backgroundColor: Colors.white24,
                                  ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: app.core.tx,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.1,
                          ),
                        ),
                        if (widget.episode != null) ...[
                          const SizedBox(height: 5),
                          Text(
                            widget.episode!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: app.fade(app.core.tx, 0.56),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                        if (widget.progress != null) ...[
                          const SizedBox(height: 9),
                          ClipRRect(
                            borderRadius: app.shape.br(2),
                            child: SizedBox(
                              height: 4,
                              child: ColoredBox(
                                // 0.18 vanished against the row's own panel,
                                // so the fill read as a dash floating in
                                // space rather than a bar with a track.
                                color: app.core.tx.withValues(alpha: 0.28),
                                child: FractionallySizedBox(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: widget.progress!.clamp(0.0, 1.0),
                                  heightFactor: 1,
                                  child: const ColoredBox(color: Colors.white),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
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
