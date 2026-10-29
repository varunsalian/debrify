// One tile of the multi-view grid: the video slot (loading, video, or the
// "can't play" message), the channel-name overlay, and the focus/remote
// plumbing. All playback state lives in the page-owned engine; this widget
// only renders it and forwards activation/long-press gestures.
import 'dart:async';

import 'package:debrify/widgets/trailer_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A single multi-view tile. Tap/Select makes it the tile with sound;
/// long-press or the context-menu key opens its actions.
class MultiViewTile extends StatefulWidget {
  const MultiViewTile({
    super.key,
    required this.channelName,
    required this.engine,
    required this.failed,
    required this.hasAudio,
    this.autofocus = false,
    required this.onSelected,
    required this.onLongPressed,
  });

  final String channelName;

  /// The engine for this tile, or null while one is still being created (or
  /// after the tile was retired) — the loading placeholder shows either way.
  final TrailerEngine? engine;

  /// True when `open` threw or the engine's error stream fired.
  final bool failed;
  final bool hasAudio;
  final bool autofocus;
  final VoidCallback onSelected;
  final VoidCallback onLongPressed;

  @override
  State<MultiViewTile> createState() => _MultiViewTileState();
}

class _MultiViewTileState extends State<MultiViewTile> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'multi-view tile');
  bool _ready = false;
  bool _localFailed = false;
  StreamSubscription<void>? _errorSub;

  @override
  void initState() {
    super.initState();
    _watchEngine();
  }

  @override
  void didUpdateWidget(covariant MultiViewTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.engine != widget.engine) {
      _errorSub?.cancel();
      _ready = false;
      _localFailed = false;
      _watchEngine();
    }
  }

  void _watchEngine() {
    final engine = widget.engine;
    if (engine == null) return;
    engine.firstFrameRendered
        .then<void>((_) {
          if (mounted) setState(() => _ready = true);
        })
        .catchError((Object _) {
          if (mounted) setState(() => _localFailed = true);
        });
    _errorSub = engine.errorStream.listen((_) {
      if (mounted) setState(() => _localFailed = true);
    });
  }

  @override
  void dispose() {
    _errorSub?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  void _activate() {
    if (!_focusNode.hasPrimaryFocus) _focusNode.requestFocus();
    widget.onSelected();
  }

  void _openActions() {
    if (!_focusNode.hasPrimaryFocus) _focusNode.requestFocus();
    widget.onLongPressed();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    final isMenuKey =
        event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.contextMenu;
    if (!isMenuKey) return KeyEventResult.ignored;
    _openActions();
    return KeyEventResult.handled;
  }

  Widget _buildContent() {
    final engine = widget.engine;
    if (widget.failed || _localFailed) {
      return const Center(
        child: Text(
          "Can't play this channel",
          style: TextStyle(color: Colors.white70),
        ),
      );
    }
    if (engine != null && _ready) {
      return engine.buildVideo(fit: BoxFit.contain);
    }
    return Center(
      child: Column(
        key: const ValueKey('tile-loading'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.channelName,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 8),
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      canRequestFocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Actions(
        // Shadows the InkResponse's own activate handling so a remote
        // Select/Enter lands exactly once on this tile.
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (intent) {
              _activate();
              return null;
            },
          ),
          ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
            onInvoke: (intent) {
              _activate();
              return null;
            },
          ),
        },
        child: InkWell(
          onTap: _activate,
          onLongPress: _openActions,
          excludeFromSemantics: true,
          child: AnimatedBuilder(
            animation: _focusNode,
            builder: (context, _) {
              final hasFocus = _focusNode.hasFocus;
              return DecoratedBox(
                key: ValueKey('tile-frame-${widget.channelName}'),
                decoration: BoxDecoration(
                  color: Colors.black,
                  border: Border.all(
                    color: hasFocus ? Colors.white : Colors.transparent,
                    width: 3,
                  ),
                ),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildContent(),
                      Positioned(
                        left: 8,
                        bottom: 8,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.hasAudio) ...[
                              const Icon(
                                Icons.volume_up_rounded,
                                size: 14,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 4),
                            ],
                            Flexible(
                              child: Text(
                                widget.channelName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
