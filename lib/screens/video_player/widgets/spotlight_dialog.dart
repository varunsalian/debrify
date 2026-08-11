import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../utils/platform_util.dart';

/// The player's small-confirm grammar (Spotlight): one centered glass card
/// with hairline border and tvOS pill buttons — replacing the assorted
/// Material AlertDialogs. The focused pill is solid white with black text;
/// on touch, the recommended action is the solid one.
///
/// Deliberately NOT used for theme-managed dialogs (recording limit/capacity
/// in lib/widgets) — those ride the app token layer with byte-identical
/// legacy guarantees and must not be repainted from here.
Future<T?> showSpotlightDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: 'dismiss',
    barrierColor: Colors.black.withValues(alpha: 0.55),
    transitionDuration: const Duration(milliseconds: 190),
    pageBuilder: (dialogContext, _, __) => builder(dialogContext),
    transitionBuilder: (context, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class SpotlightDialogAction {
  final String label;
  final VoidCallback onTap;

  /// The recommended action: solid on touch, autofocused on TV.
  final bool solid;

  const SpotlightDialogAction(this.label, this.onTap, {this.solid = false});
}

class SpotlightDialogCard extends StatelessWidget {
  static const ink = Colors.white;
  static const statusRed = Color(0xFFE23D4C);

  final String title;

  /// Optional status dot before the title (e.g. [statusRed] for recording).
  final Color? statusDot;

  /// Body content; [bodyText]/[metaText] are the common two-line shape,
  /// [child] takes over when the card needs real widgets (text fields).
  final String? bodyText;
  final String? metaText;
  final Widget? child;

  final List<SpotlightDialogAction> actions;

  const SpotlightDialogCard({
    super.key,
    required this.title,
    this.statusDot,
    this.bodyText,
    this.metaText,
    this.child,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: 400,
      padding: const EdgeInsets.fromLTRB(26, 24, 26, 18),
      decoration: BoxDecoration(
        color: PlatformUtil.isAndroidTvCached
            ? const Color(0xF5101012)
            : const Color(0xFF101012).withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ink.withValues(alpha: 0.14), width: 0.75),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 34,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (statusDot != null) ...[
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: statusDot,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: ink,
                    fontSize: 16.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (bodyText != null) ...[
            const SizedBox(height: 6),
            Text(
              bodyText!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ink.withValues(alpha: 0.62),
                fontSize: 12.5,
                height: 1.5,
              ),
            ),
          ],
          if (metaText != null) ...[
            const SizedBox(height: 4),
            Text(
              metaText!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ink.withValues(alpha: 0.42),
                fontSize: 11.5,
                height: 1.45,
              ),
            ),
          ],
          if (child != null) ...[const SizedBox(height: 14), child!],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 18),
            Row(
              children: [
                for (final (i, action) in actions.indexed) ...[
                  if (i > 0) const SizedBox(width: 10),
                  Expanded(child: SpotlightPillButton(action: action)),
                ],
              ],
            ),
          ],
        ],
      ),
    );

    final glass = PlatformUtil.isAndroidTvCached
        ? card
        : ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
              child: card,
            ),
          );

    return Center(
      child: Material(color: Colors.transparent, child: glass),
    );
  }
}

/// tvOS pill button: focused = solid white with black text (+ slight scale);
/// unfocused = soft white fill. On touch (no focus), the recommended action
/// renders solid instead.
class SpotlightPillButton extends StatefulWidget {
  final SpotlightDialogAction action;

  const SpotlightPillButton({super.key, required this.action});

  @override
  State<SpotlightPillButton> createState() => _SpotlightPillButtonState();
}

class _SpotlightPillButtonState extends State<SpotlightPillButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final tv = PlatformUtil.isTelevision;
    final white = _focused || (!tv && widget.action.solid);
    final button = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.action.onTap,
      child: AnimatedScale(
        scale: _focused ? 1.04 : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: white
                ? SpotlightDialogCard.ink
                : SpotlightDialogCard.ink.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(11),
            boxShadow: _focused
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Text(
            widget.action.label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: white
                  ? Colors.black
                  : SpotlightDialogCard.ink.withValues(alpha: 0.85),
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
    if (!tv) return button;
    return Focus(
      autofocus: widget.action.solid,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final k = event.logicalKey;
        if (k == LogicalKeyboardKey.enter ||
            k == LogicalKeyboardKey.numpadEnter ||
            k == LogicalKeyboardKey.select ||
            k == LogicalKeyboardKey.gameButtonA ||
            k == LogicalKeyboardKey.space) {
          widget.action.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: button,
    );
  }
}
