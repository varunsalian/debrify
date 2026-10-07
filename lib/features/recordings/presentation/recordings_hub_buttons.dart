import 'package:debrify/features/recordings/presentation/recordings_hub_tokens.dart';
import 'package:debrify/utils/tv_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ── Buttons ─────────────────────────────────────────────────────────────────
class _HubButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool filled;
  final bool danger;
  final bool autofocus;
  final VoidCallback onPressed;

  /// Explicit DOWN target — same right-edge geometry trap as
  /// [_HubIconButton.onDown]: without it, DOWN from the hub bar's Schedule
  /// button can land on a library row's DELETE when nothing focusable sits
  /// between them.
  final VoidCallback? onDown;

  const _HubButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.filled = false,
    this.danger = false,
    this.autofocus = false,
    this.onDown,
  });

  @override
  State<_HubButton> createState() => _HubButtonState();
}

typedef RecordingsHubHubButton = _HubButton;

class _HubButtonState extends State<_HubButton> {
  /// Live, never cached: Flutter does not guarantee the falling edge of
  /// `onFocusChange` — popping a route opened with OK restores focus to the
  /// modal scope rather than to a row, so rows that were focus-walked on the
  /// way in are never told they lost it and keep painting as focused. See the
  /// note on `_SettingsTileState._focused` in
  /// `settings/widgets/settings_widgets.dart`.
  FocusNode? _ownFocusNode;
  FocusNode get _focusNode => _ownFocusNode ??= FocusNode();
  bool get _focused => _focusNode.hasFocus;

  @override
  void dispose() {
    _ownFocusNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color fill;
    final Color fg;
    if (widget.danger) {
      fill = kRecordingsHubRec.withValues(alpha: _focused ? 0.32 : 0.16);
      fg = const Color(0xFFFF8CA3);
    } else if (widget.filled) {
      fill = kRecordingsHubAccent.withValues(alpha: _focused ? 0.42 : 0.22);
      fg = const Color(0xFFD9CBFF);
    } else {
      fill = Colors.white.withValues(alpha: _focused ? 0.12 : 0.06);
      fg = Colors.white.withValues(alpha: 0.85);
    }
    return Focus(
      autofocus: widget.autofocus,
      focusNode: _focusNode,
      onFocusChange: (_) => setState(() {}),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && isActivateOrSpaceKey(event.logicalKey)) {
          widget.onPressed();
          return KeyEventResult.handled;
        }
        if (widget.onDown != null &&
            event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.arrowDown) {
          widget.onDown!();
          return KeyEventResult.handled;
        }
        // Swallow DOWN repeats while redirecting (see _HubIconButton).
        if (widget.onDown != null &&
            event.logicalKey == LogicalKeyboardKey.arrowDown) {
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onPressed,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _focused ? kRecordingsHubGold : Colors.transparent,
              width: 1.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 17, color: fg),
              const SizedBox(width: 7),
              Text(
                widget.label,
                style: TextStyle(
                  color: fg,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HubIconButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  /// Explicit DOWN target. The folder button shares the right edge with the
  /// library rows' delete icons, so pure geometry would move DOWN onto a
  /// DELETE — callers pass this to send focus to the row's card instead.
  final VoidCallback? onDown;

  const _HubIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.onDown,
  });

  @override
  State<_HubIconButton> createState() => _HubIconButtonState();
}

typedef RecordingsHubHubIconButton = _HubIconButton;

class _HubIconButtonState extends State<_HubIconButton> {
  /// Live, never cached: Flutter does not guarantee the falling edge of
  /// `onFocusChange` — popping a route opened with OK restores focus to the
  /// modal scope rather than to a row, so rows that were focus-walked on the
  /// way in are never told they lost it and keep painting as focused. See the
  /// note on `_SettingsTileState._focused` in
  /// `settings/widgets/settings_widgets.dart`.
  FocusNode? _ownFocusNode;
  FocusNode get _focusNode => _ownFocusNode ??= FocusNode();
  bool get _focused => _focusNode.hasFocus;

  @override
  void dispose() {
    _ownFocusNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      onFocusChange: (_) => setState(() {}),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && isActivateOrSpaceKey(event.logicalKey)) {
          widget.onPressed();
          return KeyEventResult.handled;
        }
        if (widget.onDown != null &&
            event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.arrowDown) {
          widget.onDown!();
          return KeyEventResult.handled;
        }
        // Swallow DOWN repeats while redirecting, so a held key can't slip
        // one event through geometric traversal mid-move.
        if (widget.onDown != null &&
            event.logicalKey == LogicalKeyboardKey.arrowDown) {
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Tooltip(
        message: widget.tooltip,
        child: GestureDetector(
          onTap: widget.onPressed,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: _focused ? 0.12 : 0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _focused ? kRecordingsHubGold : Colors.transparent,
                width: 1.8,
              ),
            ),
            child: Icon(
              widget.icon,
              size: 18,
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),
        ),
      ),
    );
  }
}

class _RowIconButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  const _RowIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  State<_RowIconButton> createState() => _RowIconButtonState();
}

typedef RecordingsHubRowIconButton = _RowIconButton;

class _RowIconButtonState extends State<_RowIconButton> {
  /// Live, never cached: Flutter does not guarantee the falling edge of
  /// `onFocusChange` — popping a route opened with OK restores focus to the
  /// modal scope rather than to a row, so rows that were focus-walked on the
  /// way in are never told they lost it and keep painting as focused. See the
  /// note on `_SettingsTileState._focused` in
  /// `settings/widgets/settings_widgets.dart`.
  FocusNode? _ownFocusNode;
  FocusNode get _focusNode => _ownFocusNode ??= FocusNode();
  bool get _focused => _focusNode.hasFocus;

  @override
  void dispose() {
    _ownFocusNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      onFocusChange: (_) => setState(() {}),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && isActivateOrSpaceKey(event.logicalKey)) {
          widget.onPressed();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Tooltip(
        message: widget.tooltip,
        child: GestureDetector(
          onTap: widget.onPressed,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: _focused
                  ? kRecordingsHubRec.withValues(alpha: 0.2)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: _focused ? kRecordingsHubGold : Colors.transparent,
                width: 1.8,
              ),
            ),
            child: Icon(
              widget.icon,
              size: 17,
              color: _focused
                  ? const Color(0xFFFF8CA3)
                  : Colors.white.withValues(alpha: 0.4),
            ),
          ),
        ),
      ),
    );
  }
}
