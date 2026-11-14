import 'package:debrify/features/detail_showcase/presentation/showcase_style.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Opens one trivia, goof or quote in full. The rail's cards cut long entries
/// off, and on a TV there was no way to read the rest.
///
/// UP/DOWN scroll a long entry, OK or Back closes, and focus returns to the
/// card that opened it.
///
/// [kind] is the card's eyebrow ('Trivia', 'Goof' or 'Quote').
Future<void> showDidYouKnowReader(
  BuildContext context, {
  required String kind,
  required String text,
}) => showDialog<void>(
  context: context,
  builder: (_) => _DidYouKnowReader(kind: kind, text: text),
);

class _DidYouKnowReader extends StatelessWidget {
  final String kind;
  final String text;

  const _DidYouKnowReader({required this.kind, required this.text});

  static const _step = 96.0;

  // The focus sits inside the scroll view, so it scrolls the list it is in
  // rather than owning a controller.
  static KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final context = node.context;
    if (context == null) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      final position = Scrollable.maybeOf(context)?.position;
      if (position == null) return KeyEventResult.handled;
      final delta = key == LogicalKeyboardKey.arrowDown ? _step : -_step;
      final target = (position.pixels + delta).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      position.animateTo(
        target,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
      );
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent) {
      return sActivate(event, () => Navigator.of(context).pop());
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final quote = kind == 'Quote';
    final height = MediaQuery.sizeOf(context).height;
    return Dialog(
      backgroundColor: Color.lerp(app.home.bg, app.core.tx, 0.07),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: sInk.withValues(alpha: 0.12)),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 640, maxHeight: height * 0.75),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      kind.toUpperCase(),
                      style: st(
                        12,
                        w: FontWeight.w700,
                        a: 0.5,
                      ).copyWith(letterSpacing: 1.4),
                    ),
                  ),
                  // For pointers only: the reader itself holds focus, and
                  // OK or Back close it from a remote.
                  ExcludeFocus(
                    child: IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(
                        Icons.close_rounded,
                        color: sInk.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  child: Focus(
                    autofocus: true,
                    onKeyEvent: _onKey,
                    child: Text(
                      quote ? '“$text”' : text,
                      style: st(16, a: quote ? 0.9 : 0.85).copyWith(
                        height: 1.55,
                        fontStyle: quote ? FontStyle.italic : FontStyle.normal,
                      ),
                    ),
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
