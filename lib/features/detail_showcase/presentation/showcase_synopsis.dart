import 'package:debrify/features/detail_showcase/presentation/showcase_did_you_know_reader.dart';
import 'package:debrify/features/detail_showcase/presentation/showcase_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The wide identity's synopsis.
///
/// The hero band has a fixed height, so the text stays clamped to [maxLines].
/// When it does not fit, "… MORE" is set into the end of the last line —
/// never on a line of its own, which would grow the band — and opens the whole
/// text in the reader. Before this the cut text had no way to be read at all.
///
/// Reachable by tap or click, and on a remote by UP from the button row:
/// [node] is entered by the layout, UP leaves for the back button through
/// [onExitUp] and DOWN returns to the buttons through [onExitDown]. The node
/// is attached only while MORE is shown; the layout tests it with
/// `detailNodeMounted` (a detached node keeps its stale `context`).
class ShowcaseSynopsis extends StatefulWidget {
  final String text;
  final TextStyle style;
  final int maxLines;
  final FocusNode? node;
  final VoidCallback? onExitUp;
  final VoidCallback? onExitDown;
  final VoidCallback? onFocused;

  const ShowcaseSynopsis({
    super.key,
    required this.text,
    required this.style,
    this.maxLines = 3,
    this.node,
    this.onExitUp,
    this.onExitDown,
    this.onFocused,
  });

  @override
  State<ShowcaseSynopsis> createState() => _ShowcaseSynopsisState();
}

class _ShowcaseSynopsisState extends State<ShowcaseSynopsis> {
  bool _focused = false;
  bool _hovered = false;

  void _open() =>
      showDidYouKnowReader(context, kind: 'Synopsis', text: widget.text.trim());

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    switch (e.logicalKey) {
      case LogicalKeyboardKey.arrowUp:
        widget.onExitUp?.call();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        widget.onExitDown?.call();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
      case LogicalKeyboardKey.arrowRight:
        // Nothing beside it; keep the cursor here rather than letting the
        // layout's band walk move it from a node it does not know.
        return KeyEventResult.handled;
    }
    return sActivate(e, _open);
  }

  TextStyle _moreStyle(TextStyle base) {
    final active = _focused || _hovered;
    return base.copyWith(
      color: sInk.withValues(alpha: active ? 1 : 0.92),
      fontWeight: FontWeight.w700,
      letterSpacing: 0.8,
      decoration: active ? TextDecoration.underline : null,
      decorationColor: sInk,
      // An underline alone is too faint to find from across a room.
      backgroundColor: _focused ? sInk.withValues(alpha: 0.22) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Measured in the style the Text will actually paint with: without the
    // inherited font family the painter measures another font, and MORE
    // lands a line early.
    final style = DefaultTextStyle.of(context).style.merge(widget.style);
    return LayoutBuilder(
      builder: (context, constraints) {
        // Built here, not in build(): a width change re-runs only this, and
        // the cue must follow the reset below.
        final moreStyle = _moreStyle(style);
        final head = synopsisHeadBeforeMore(
          text: widget.text,
          style: style,
          moreStyle: moreStyle,
          maxLines: widget.maxLines,
          maxWidth: constraints.maxWidth,
          textScaler: MediaQuery.textScalerOf(context),
          textDirection: Directionality.of(context),
        );
        if (head == null) {
          // MORE is gone; its Focus no longer reports, so drop the cue it
          // left behind or a returning MORE shows up looking focused.
          _focused = false;
          _hovered = false;
          return Text(
            widget.text,
            maxLines: widget.maxLines,
            overflow: TextOverflow.ellipsis,
            style: style,
          );
        }
        return Focus(
          focusNode: widget.node,
          onFocusChange: (f) {
            setState(() => _focused = f);
            if (f) widget.onFocused?.call();
          },
          onKeyEvent: _onKey,
          child: Semantics(
            button: true,
            label: 'Read the full synopsis',
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => _hovered = true),
              onExit: (_) => setState(() => _hovered = false),
              child: GestureDetector(
                onTap: _open,
                behavior: HitTestBehavior.opaque,
                child: Text.rich(
                  _composed(head, style, moreStyle),
                  maxLines: widget.maxLines,
                  overflow: TextOverflow.clip,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

final _space = RegExp(r'\s');

TextSpan _composed(String head, TextStyle style, TextStyle moreStyle) =>
    TextSpan(
      style: style,
      children: [
        TextSpan(text: '$head… '),
        TextSpan(text: 'MORE', style: moreStyle),
      ],
    );

bool _exceeds(
  InlineSpan span,
  int maxLines,
  double maxWidth,
  TextScaler textScaler,
  TextDirection textDirection,
) {
  final painter = TextPainter(
    text: span,
    maxLines: maxLines,
    textDirection: textDirection,
    textScaler: textScaler,
  )..layout(maxWidth: maxWidth);
  final exceeds = painter.didExceedMaxLines;
  painter.dispose();
  return exceeds;
}

/// The part of [text] that fits in [maxLines] with "… MORE" after it, or
/// null when the whole text fits and needs no MORE.
///
/// Starts from where the last line would have to end to leave room for the
/// tail, then backs off a word at a time until the composed line really fits:
/// measuring the tail on its own can be off by a glyph's kerning, and a MORE
/// pushed onto a line past [maxLines] would be clipped away unseen.
String? synopsisHeadBeforeMore({
  required String text,
  required TextStyle style,
  required TextStyle moreStyle,
  required int maxLines,
  required double maxWidth,
  required TextScaler textScaler,
  required TextDirection textDirection,
}) {
  final trimmed = text.trim();
  if (!maxWidth.isFinite ||
      maxWidth <= 0 ||
      !_exceeds(
        TextSpan(text: trimmed, style: style),
        maxLines,
        maxWidth,
        textScaler,
        textDirection,
      )) {
    return null;
  }
  final painter = TextPainter(
    text: TextSpan(text: trimmed, style: style),
    maxLines: maxLines,
    textDirection: textDirection,
    textScaler: textScaler,
  )..layout(maxWidth: maxWidth);
  final tail = TextPainter(
    text: _composed('', style, moreStyle),
    maxLines: 1,
    textDirection: textDirection,
    textScaler: textScaler,
  )..layout();
  final lines = painter.computeLineMetrics();
  final last = lines[(maxLines < lines.length ? maxLines : lines.length) - 1];
  final x = textDirection == TextDirection.ltr
      ? maxWidth - tail.width
      : tail.width;
  final y = last.baseline - last.ascent / 2;
  final cut = painter
      .getPositionForOffset(Offset(x.clamp(0.0, maxWidth), y))
      .offset
      .clamp(0, trimmed.length);
  painter.dispose();
  tail.dispose();

  var head = trimmed.substring(0, cut).trimRight();
  // Don't end on half a word.
  if (cut < trimmed.length && !_space.hasMatch(trimmed[cut])) {
    final space = head.lastIndexOf(_space);
    if (space > 0) head = head.substring(0, space).trimRight();
  }
  while (_exceeds(
    _composed(head, style, moreStyle),
    maxLines,
    maxWidth,
    textScaler,
    textDirection,
  )) {
    final space = head.lastIndexOf(_space);
    // Text with no spaces to back off to (CJK, one long token) backs off a
    // character at a time instead. The head shrinks every pass, so this ends.
    head = space > 0
        ? head.substring(0, space).trimRight()
        : head.characters.skipLast(1).toString();
    if (head.isEmpty) return null;
  }
  // Drop a dangling comma or full stop before the ellipsis.
  return head.replaceFirst(RegExp(r'[,;:.\s]+$'), '');
}
