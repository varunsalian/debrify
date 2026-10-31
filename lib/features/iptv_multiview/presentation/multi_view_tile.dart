// One tile of the multi-view grid: the video slot (loading, video, or the
// "can't play" message), the channel-name overlay, and the focus/remote
// plumbing. All playback state lives in the page-owned engine; this widget
// only renders it and forwards activation/long-press gestures.
import 'dart:async';

import 'package:debrify/widgets/trailer_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A single multi-view tile. Tap/Select makes it the tile with sound;
/// holding OK, the context-menu key, a long press or a right click opens its
/// actions.
class MultiViewTile extends StatefulWidget {
  const MultiViewTile({
    super.key,
    required this.channelName,
    required this.engine,
    required this.failed,
    this.playingName,
    this.note,
    this.noteTag,
    this.noteTop = 8,
    this.failedMessage = "Can't play this channel",
    required this.hasAudio,
    this.autofocus = false,
    required this.onSelected,
    required this.onLongPressed,
  });

  final String channelName;

  /// The engine for this tile, or null while one is still being created (or
  /// after the tile was retired) — the loading placeholder shows either way.
  final TrailerEngine? engine;

  /// True once nothing for this tile could play (the page tried every
  /// version it found); [failedMessage] says why.
  final bool failed;
  final String failedMessage;

  /// The version on screen when it is not [channelName], and [note] on why.
  /// The note shows for [noteDuration] when it appears, then only [noteTag]
  /// stays, next to the channel name ("HD version").
  final String? playingName;
  final String? note;
  final String? noteTag;

  /// Where the note starts from the tile's top edge (below anything the page
  /// lays over the tile, such as its back button).
  final double noteTop;

  static const noteDuration = Duration(seconds: 6);

  /// How long OK has to be held to open the actions instead of selecting.
  static const holdDuration = Duration(milliseconds: 500);
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

  /// Whether the fallback note is still on screen (see [MultiViewTile.note]).
  bool _noteShown = false;
  Timer? _noteTimer;

  /// Running while OK is held: firing opens the actions, a release before it
  /// fires selects the tile. [_holdDown] is the press's own timestamp, so a
  /// busy UI thread cannot turn a real hold into a short press.
  Timer? _holdTimer;
  Duration? _holdDown;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
    _watchEngine();
    _showNote();
  }

  /// A hold ends when focus leaves the tile (DPAD on, a dialog, Home): its
  /// release lands elsewhere or never, and must not open this tile's actions.
  void _onFocusChange() {
    if (!_focusNode.hasFocus) _cancelHold();
  }

  void _cancelHold() {
    _holdTimer?.cancel();
    _holdTimer = null;
    _holdDown = null;
  }

  @override
  void didUpdateWidget(covariant MultiViewTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.engine != widget.engine) {
      _ready = false;
      _watchEngine();
    }
    if (oldWidget.note != widget.note ||
        oldWidget.playingName != widget.playingName) {
      _showNote();
    }
  }

  /// Shows a new fallback note; it stays [MultiViewTile.noteDuration] once
  /// the video is up (not while the version is still loading), then only the
  /// tag remains.
  void _showNote() {
    _noteTimer?.cancel();
    _noteTimer = null;
    _noteShown = widget.note != null;
    _armNoteTimer();
  }

  void _armNoteTimer() {
    if (!_noteShown || !_ready || _noteTimer != null) return;
    _noteTimer = Timer(MultiViewTile.noteDuration, () {
      if (mounted) setState(() => _noteShown = false);
    });
  }

  /// Shows the video once its first frame is up. Failures are the page's:
  /// it switches to another version of the channel or marks [failed].
  void _watchEngine() {
    final engine = widget.engine;
    if (engine == null) return;
    engine.firstFrameRendered.then<void>((_) {
      if (mounted && identical(widget.engine, engine)) {
        setState(() => _ready = true);
        _armNoteTimer();
      }
    }, onError: (Object _) {});
  }

  @override
  void dispose() {
    _noteTimer?.cancel();
    _holdTimer?.cancel();
    _focusNode.removeListener(_onFocusChange);
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

  static final _okKeys = <LogicalKeyboardKey>{
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.gameButtonA,
  };

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.contextMenu) {
      if (event is KeyDownEvent) _openActions();
      return KeyEventResult.handled;
    }
    if (!_okKeys.contains(key)) return KeyEventResult.ignored;
    // OK selects on release; held past [holdDuration] it opens the actions
    // instead (TV remotes rarely have a Menu key). Repeats while held are
    // swallowed so a long press never selects as well.
    switch (event) {
      case KeyDownEvent():
        _cancelHold();
        _holdDown = event.timeStamp;
        _holdTimer = Timer(MultiViewTile.holdDuration, () {
          _cancelHold();
          if (mounted && _focusNode.hasFocus) _openActions();
        });
      case KeyUpEvent():
        // No press on record: the release of the OK that opened this page or
        // closed a sheet, or a hold whose actions already opened.
        final down = _holdDown;
        final pending = _holdTimer?.isActive ?? false;
        _cancelHold();
        if (down == null || !pending) break;
        if (event.timeStamp - down >= MultiViewTile.holdDuration) {
          _openActions();
        } else {
          _activate();
        }
      default:
        break;
    }
    return KeyEventResult.handled;
  }

  Widget _buildContent() {
    final engine = widget.engine;
    if (widget.failed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            widget.failedMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
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
        // OK, Enter and gamepad A are handled in [_handleKeyEvent] (short
        // press selects, a hold opens the actions); this covers the other
        // activate paths (Space, accessibility) without a second handler.
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
          onSecondaryTap: _openActions,
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
                      if (widget.note != null && _noteShown && !widget.failed)
                        Positioned(
                          left: 8,
                          top: widget.noteTop,
                          right: 8,
                          child: _FallbackNote(
                            playingName: widget.playingName,
                            note: widget.note!,
                          ),
                        ),
                      Positioned(
                        left: 8,
                        bottom: 8,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Remote users learn the hold here, on its own
                            // line so a long channel name cannot cut it off.
                            if (hasFocus &&
                                FocusManager.instance.highlightMode ==
                                    FocusHighlightMode.traditional)
                              const Padding(
                                key: ValueKey('tile-hold-hint'),
                                padding: EdgeInsets.only(bottom: 2),
                                child: Text(
                                  'Hold OK for options',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            Row(
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
                                    [
                                      widget.channelName,
                                      if (widget.noteTag != null &&
                                          !_noteShown &&
                                          !widget.failed)
                                        widget.noteTag!,
                                    ].join(' · '),
                                    key: const ValueKey('tile-label'),
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

/// Why a tile shows another version of its channel: what plays, and why.
class _FallbackNote extends StatelessWidget {
  const _FallbackNote({required this.playingName, required this.note});

  final String? playingName;
  final String note;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: Container(
        key: const ValueKey('tile-fallback-note'),
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.fromLTRB(10, 7, 10, 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (playingName != null)
              Text(
                'Playing $playingName',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            const SizedBox(height: 2),
            Text(
              note,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
