import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_theme_scope.dart';
import '../../../utils/platform_util.dart';
import '../../../utils/tv_keys.dart';

/// Shared visual and focus grammar for every surface opened from Debrify TV.
///
/// The page itself can use either Debrify TV layout. Overlays always use the
/// Spotlight language: a deep raised panel, mono eyebrow, generous type, soft
/// hairlines, and controls which invert and lift when focused.
class DebrifyTvSpotlightDialog extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget child;
  final List<Widget> actions;
  final double maxWidth;
  final double maxHeightFactor;
  final EdgeInsetsGeometry? contentPadding;
  final bool scrollable;

  const DebrifyTvSpotlightDialog({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.icon,
    required this.child,
    this.subtitle,
    this.actions = const [],
    this.maxWidth = 680,
    this.maxHeightFactor = .88,
    this.contentPadding,
    this.scrollable = true,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final tv = app.debrifyTv;
    final media = MediaQuery.of(context);
    final compact = media.size.width < 520 || media.size.height < 560;
    final inset = compact ? 12.0 : 24.0;
    final padding = contentPadding ?? EdgeInsets.all(compact ? 18 : 28);
    final panel = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [tv.noticeBg, tv.dialogDeep],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: app.shape.br(compact ? 22 : 28),
        border: Border.all(color: tv.hairline),
        boxShadow: const [
          BoxShadow(
            color: Color(0x99000000),
            blurRadius: 56,
            offset: Offset(0, 28),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: compact ? -90 : -120,
            top: compact ? -110 : -150,
            child: IgnorePointer(
              child: Container(
                width: compact ? 220 : 300,
                height: compact ? 220 : 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      tv.accent.withValues(alpha: .18),
                      tv.accent.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: padding,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SpotlightDialogHeader(
                  eyebrow: eyebrow,
                  title: title,
                  subtitle: subtitle,
                  icon: icon,
                  compact: compact,
                ),
                SizedBox(height: compact ? 18 : 26),
                if (scrollable)
                  Flexible(
                    child: SingleChildScrollView(
                      child: FocusTraversalGroup(
                        policy: WidgetOrderTraversalPolicy(),
                        child: child,
                      ),
                    ),
                  )
                else
                  Flexible(
                    child: FocusTraversalGroup(
                      policy: WidgetOrderTraversalPolicy(),
                      child: child,
                    ),
                  ),
                if (actions.isNotEmpty) ...[
                  SizedBox(height: compact ? 18 : 24),
                  Divider(height: 1, color: tv.hairline),
                  SizedBox(height: compact ? 14 : 18),
                  Wrap(
                    alignment: WrapAlignment.end,
                    runAlignment: WrapAlignment.end,
                    spacing: 10,
                    runSpacing: 10,
                    children: actions,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: EdgeInsets.all(inset),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: compact ? 280 : 360,
          maxWidth: maxWidth,
          maxHeight: media.size.height * maxHeightFactor,
        ),
        child: panel,
      ),
    );
  }
}

class _SpotlightDialogHeader extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String? subtitle;
  final IconData icon;
  final bool compact;

  const _SpotlightDialogHeader({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final tv = app.debrifyTv;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: compact ? 44 : 52,
          height: compact ? 44 : 52,
          decoration: BoxDecoration(
            color: tv.fillWeak,
            borderRadius: app.shape.br(compact ? 14 : 17),
            border: Border.all(color: tv.hairline),
          ),
          child: Icon(icon, color: tv.accent, size: compact ? 22 : 26),
        ),
        SizedBox(width: compact ? 14 : 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eyebrow.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tv.accent,
                  fontFamily: 'JetBrainsMono',
                  fontSize: compact ? 9 : 10,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2.1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: TextStyle(
                  color: app.core.tx,
                  fontSize: compact ? 24 : 32,
                  height: 1.05,
                  letterSpacing: -.7,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 8),
                Text(
                  subtitle!,
                  style: TextStyle(
                    color: tv.textDim,
                    fontSize: compact ? 12 : 14,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

enum DebrifyTvDialogButtonTone { normal, primary, danger }

/// A linear-DPAD button. Every arrow is consumed and routed through widget
/// order, so focus never falls back to Flutter's geometry heuristic when the
/// dialog reflows at another screen size.
class DebrifyTvDialogButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final DebrifyTvDialogButtonTone tone;
  final bool autofocus;
  final bool expand;
  final FocusNode? focusNode;

  const DebrifyTvDialogButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.tone = DebrifyTvDialogButtonTone.normal,
    this.autofocus = false,
    this.expand = false,
    this.focusNode,
  });

  @override
  State<DebrifyTvDialogButton> createState() => _DebrifyTvDialogButtonState();
}

class _DebrifyTvDialogButtonState extends State<DebrifyTvDialogButton> {
  bool _focused = false;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowUp) {
      node.previousFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowDown) {
      node.nextFocus();
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent && isActivateOrSpaceKey(key)) {
      widget.onPressed?.call();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final tv = app.debrifyTv;
    final disabled = widget.onPressed == null;
    final focused = _focused && !disabled;
    final danger = widget.tone == DebrifyTvDialogButtonTone.danger;
    final primary = widget.tone == DebrifyTvDialogButtonTone.primary;
    final resting = primary
        ? app.core.tx
        : danger
        ? tv.accent.withValues(alpha: .16)
        : tv.fillWeak;
    final fill = focused ? app.core.tx : resting;
    final ink = focused || primary
        ? app.inkOn(app.core.tx)
        : danger
        ? tv.accent
        : tv.textDim;

    final control = Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      canRequestFocus: !disabled,
      onFocusChange: (value) => setState(() => _focused = value),
      onKeyEvent: _onKey,
      child: Semantics(
        button: true,
        enabled: !disabled,
        label: widget.label,
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: PlatformUtil.isTelevision
                ? Duration.zero
                : const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            constraints: const BoxConstraints(minHeight: 46),
            padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 12),
            transform: focused
                ? (Matrix4.identity()..translateByDouble(0, -2, 0, 1))
                : Matrix4.identity(),
            decoration: BoxDecoration(
              color: disabled ? tv.fillWeak.withValues(alpha: .35) : fill,
              borderRadius: app.shape.br(23),
              border: Border.all(color: focused ? app.core.tx : tv.hairline),
              boxShadow: focused
                  ? const [
                      BoxShadow(
                        color: Color(0x77000000),
                        blurRadius: 24,
                        offset: Offset(0, 12),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.icon != null) ...[
                  Icon(
                    widget.icon,
                    size: 18,
                    color: disabled ? tv.textFaint : ink,
                  ),
                  const SizedBox(width: 9),
                ],
                Text(
                  widget.label,
                  style: TextStyle(
                    color: disabled ? tv.textFaint : ink,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return widget.expand
        ? SizedBox(width: double.infinity, child: control)
        : control;
  }
}

/// Large destination/action card used by import and channel option menus.
class DebrifyTvDialogOptionCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? tag;
  final VoidCallback? onPressed;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool danger;
  final bool vertical;

  const DebrifyTvDialogOptionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onPressed,
    this.tag,
    this.focusNode,
    this.autofocus = false,
    this.danger = false,
    this.vertical = false,
  });

  @override
  State<DebrifyTvDialogOptionCard> createState() =>
      _DebrifyTvDialogOptionCardState();
}

class _DebrifyTvDialogOptionCardState extends State<DebrifyTvDialogOptionCard> {
  bool _focused = false;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowUp) {
      node.previousFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowDown) {
      node.nextFocus();
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent && isActivateOrSpaceKey(key)) {
      widget.onPressed?.call();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final tv = app.debrifyTv;
    final disabled = widget.onPressed == null;
    final focused = _focused && !disabled;
    final restingInk = widget.danger ? tv.accent : app.core.tx;
    final ink = focused ? app.inkOn(app.core.tx) : restingInk;
    final iconTile = Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: focused
            ? app.inkOn(app.core.tx).withValues(alpha: .08)
            : tv.controlBg,
        borderRadius: app.shape.br(15),
      ),
      child: Icon(widget.icon, color: ink, size: 24),
    );
    final labelBlock = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.title,
          maxLines: widget.vertical ? 2 : 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: disabled ? tv.textFaint : ink,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          widget.subtitle,
          maxLines: widget.vertical ? 4 : 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: focused
                ? app.inkOn(app.core.tx).withValues(alpha: .56)
                : tv.textDim,
            fontSize: 12,
            height: 1.3,
          ),
        ),
      ],
    );
    final tagWidget = widget.tag == null
        ? null
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: focused
                  ? app.inkOn(app.core.tx).withValues(alpha: .08)
                  : tv.accent.withValues(alpha: .14),
              borderRadius: app.shape.br(99),
            ),
            child: Text(
              widget.tag!.toUpperCase(),
              style: TextStyle(
                color: focused ? ink : tv.accent,
                fontFamily: 'JetBrainsMono',
                fontSize: 9,
                letterSpacing: .8,
                fontWeight: FontWeight.w700,
              ),
            ),
          );
    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      canRequestFocus: !disabled,
      onFocusChange: (value) => setState(() => _focused = value),
      onKeyEvent: _onKey,
      child: Semantics(
        button: true,
        enabled: !disabled,
        label: widget.title,
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: PlatformUtil.isTelevision
                ? Duration.zero
                : const Duration(milliseconds: 170),
            curve: Curves.easeOutCubic,
            constraints: BoxConstraints(minHeight: widget.vertical ? 210 : 112),
            padding: const EdgeInsets.all(18),
            transform: focused
                ? (Matrix4.identity()..translateByDouble(0, -4, 0, 1))
                : Matrix4.identity(),
            decoration: BoxDecoration(
              color: focused ? app.core.tx : tv.fillWeak,
              borderRadius: app.shape.br(18),
              border: Border.all(color: focused ? app.core.tx : tv.hairline),
              boxShadow: focused
                  ? const [
                      BoxShadow(
                        color: Color(0x88000000),
                        blurRadius: 30,
                        offset: Offset(0, 16),
                      ),
                    ]
                  : null,
            ),
            child: widget.vertical
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      iconTile,
                      const SizedBox(height: 18),
                      labelBlock,
                      if (tagWidget != null) ...[
                        const SizedBox(height: 18),
                        tagWidget,
                      ],
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      iconTile,
                      const SizedBox(width: 16),
                      Expanded(child: labelBlock),
                      if (tagWidget != null) ...[
                        const SizedBox(width: 12),
                        tagWidget,
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class DebrifyTvDialogSection extends StatelessWidget {
  final String label;
  final Widget child;

  const DebrifyTvDialogSection({
    super.key,
    required this.label,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final tv = AppThemeScope.of(context).debrifyTv;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: tv.textFaint,
            fontFamily: 'JetBrainsMono',
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.7,
          ),
        ),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}
