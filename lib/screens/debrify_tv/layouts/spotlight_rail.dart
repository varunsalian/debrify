import 'package:flutter/material.dart';

import '../../../models/debrify_tv/channel.dart';
import '../../../theme/app_theme_scope.dart';

/// Presentational pieces of the Spotlight rail. All focus ROUTING lives in
/// the arm (`spotlight_layout.dart`) — these widgets draw a node's state and
/// forward key events to the router they were handed, nothing more.
///
/// The mock (`dev/design/mockups/debrify_tv_spotlight_mockup/`) is the spec; it
/// is drawn at 1920×1080 and every number here is logical (÷2).

/// The mono-flavoured uppercase eyebrow ("DEBRIFY TV", group labels).
class SpotlightKick extends StatelessWidget {
  final String text;
  final Color color;
  final double fontSize;
  const SpotlightKick(
    this.text, {
    super.key,
    required this.color,
    this.fontSize = 10.5,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
        letterSpacing: fontSize * 0.22,
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

/// "Pinned · 2" / "Everything else · 10" divider between rail groups.
class SpotlightGroupLabel extends StatelessWidget {
  final String label;
  final int count;
  const SpotlightGroupLabel(this.label, this.count, {super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final faint = app.debrifyTv.textFaint;
    return Padding(
      padding: const EdgeInsets.only(top: 11, bottom: 6, left: 2, right: 2),
      child: Row(
        children: [
          Expanded(child: SpotlightKick(label, color: faint, fontSize: 9)),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: faint.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

/// A rail pill button — Quick Play (primary) and the utility rows.
class SpotlightRailButton extends StatelessWidget {
  final FocusNode focusNode;
  final KeyEventResult Function(FocusNode, KeyEvent) onKey;
  final VoidCallback? onActivate;
  final IconData icon;
  final String label;
  final String? trailing;
  final bool primary;
  final bool compact;

  const SpotlightRailButton({
    super.key,
    required this.focusNode,
    required this.onKey,
    required this.onActivate,
    required this.icon,
    required this.label,
    this.trailing,
    this.primary = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final tv = app.debrifyTv;
    return Focus(
      focusNode: focusNode,
      onKeyEvent: onKey,
      child: ListenableBuilder(
        listenable: focusNode,
        builder: (context, _) {
          final focused = focusNode.hasFocus;
          final disabled = onActivate == null;
          // Focus grammar: text rows invert and lift — never a coloured ring.
          final Color fill = focused
              ? app.core.tx
              : primary
              ? app.core.tx.withValues(alpha: 0.92)
              : tv.fillWeak;
          final Color ink = focused || primary
              ? app.inkOn(app.core.tx)
              : tv.textDim;
          final double height = compact ? 34 : 42;
          return RepaintBoundary(
            child: GestureDetector(
              onTap: onActivate,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                height: height,
                padding: const EdgeInsets.symmetric(horizontal: 13),
                transform: focused
                    ? (Matrix4.identity()..translateByDouble(0, -2, 0, 1))
                    : Matrix4.identity(),
                decoration: BoxDecoration(
                  color: disabled ? tv.fillWeak.withValues(alpha: 0.5) : fill,
                  borderRadius: BorderRadius.circular(height / 2),
                  border: Border.all(
                    color: focused ? app.core.tx : tv.hairline,
                    width: 1,
                  ),
                  boxShadow: focused
                      ? const [
                          BoxShadow(
                            color: Color(0x66000000),
                            blurRadius: 20,
                            offset: Offset(0, 10),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  children: [
                    Icon(icon, size: compact ? 13 : 15, color: ink),
                    SizedBox(width: compact ? 7 : 8),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: compact ? 11.5 : 13.5,
                          fontWeight: FontWeight.w700,
                          color: ink,
                        ),
                      ),
                    ),
                    if (trailing != null)
                      SpotlightKick(
                        trailing!,
                        color: ink.withValues(alpha: 0.4),
                        fontSize: 8.5,
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A utility icon in the row under Quick Play — Search, Add, Import,
/// Settings. Same focus grammar as every rail control: invert and lift,
/// never a coloured ring. [active] tints the resting state with the accent
/// (the Search icon while a filter is applied).
class SpotlightUtilityButton extends StatelessWidget {
  final FocusNode focusNode;
  final KeyEventResult Function(FocusNode, KeyEvent) onKey;
  final VoidCallback? onActivate;
  final ValueChanged<bool> onFocusChange;
  final IconData icon;
  final String label;
  final bool active;

  const SpotlightUtilityButton({
    super.key,
    required this.focusNode,
    required this.onKey,
    required this.onActivate,
    required this.onFocusChange,
    required this.icon,
    required this.label,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final tv = app.debrifyTv;
    return Focus(
      focusNode: focusNode,
      onFocusChange: onFocusChange,
      onKeyEvent: onKey,
      child: ListenableBuilder(
        listenable: focusNode,
        builder: (context, _) {
          final focused = focusNode.hasFocus;
          final disabled = onActivate == null;
          final Color fill = focused
              ? app.core.tx
              : active
              ? tv.accent.withValues(alpha: 0.2)
              : tv.fillWeak;
          final Color ink = focused
              ? app.inkOn(app.core.tx)
              : active
              ? tv.accent
              : tv.textDim;
          return RepaintBoundary(
            child: Semantics(
              label: label,
              button: true,
              child: GestureDetector(
                onTap: onActivate,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOutCubic,
                  width: 34,
                  height: 34,
                  transform: focused
                      ? (Matrix4.identity()..translateByDouble(0, -2, 0, 1))
                      : Matrix4.identity(),
                  decoration: BoxDecoration(
                    color: disabled ? tv.fillWeak.withValues(alpha: 0.5) : fill,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: focused ? app.core.tx : tv.hairline,
                      width: 1,
                    ),
                    boxShadow: focused
                        ? const [
                            BoxShadow(
                              color: Color(0x66000000),
                              blurRadius: 20,
                              offset: Offset(0, 10),
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(
                    icon,
                    size: 15,
                    color: disabled ? tv.textFaint : ink,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// One channel row: number badge, name + caption, health pip slot.
class SpotlightChannelRow extends StatelessWidget {
  final DebrifyTvChannel channel;
  final bool pinned;

  /// Whether this channel is the one the stage is showing (independent of
  /// DPAD focus — focus can be on Quick Play while the stage still shows the
  /// last channel).
  final bool staged;
  final String caption;

  /// Health pip colour, when phase 4's rail health has resolved one. Null
  /// draws no pip at all — never a placeholder that could read as "healthy".
  final Color? pip;
  final FocusNode focusNode;
  final ValueChanged<bool> onFocusChange;
  final KeyEventResult Function(FocusNode, KeyEvent) onKey;
  final VoidCallback onActivate;
  final VoidCallback onLongPress;

  const SpotlightChannelRow({
    super.key,
    required this.channel,
    required this.pinned,
    required this.staged,
    required this.caption,
    required this.pip,
    required this.focusNode,
    required this.onFocusChange,
    required this.onKey,
    required this.onActivate,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final tv = app.debrifyTv;
    return Focus(
      focusNode: focusNode,
      onFocusChange: onFocusChange,
      onKeyEvent: onKey,
      child: ListenableBuilder(
        listenable: focusNode,
        builder: (context, _) {
          final focused = focusNode.hasFocus;
          // Inverted (focused) row: theme ink becomes the ground.
          final Color ground = focused
              ? app.core.tx
              : staged
              ? tv.fillWeak
              : Colors.transparent;
          final Color nameInk = focused ? app.inkOn(app.core.tx) : app.core.tx;
          final Color captionInk = focused
              ? app.inkOn(app.core.tx).withValues(alpha: 0.55)
              : tv.textFaint;
          return RepaintBoundary(
            child: GestureDetector(
              onTap: onActivate,
              onLongPress: onLongPress,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                height: 46,
                margin: const EdgeInsets.only(bottom: 3),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                transform: focused
                    ? (Matrix4.identity()..scaleByDouble(1.022, 1.022, 1, 1))
                    : Matrix4.identity(),
                transformAlignment: Alignment.center,
                decoration: BoxDecoration(
                  color: ground,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: focused
                      ? const [
                          BoxShadow(
                            color: Color(0x80000000),
                            blurRadius: 22,
                            offset: Offset(0, 10),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 36,
                          height: 30,
                          decoration: BoxDecoration(
                            color: focused
                                ? app.inkOn(app.core.tx).withValues(alpha: 0.09)
                                : staged
                                ? tv.accent.withValues(alpha: 0.2)
                                : tv.fillWeak,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            channel.channelNumber.toString().padLeft(2, '0'),
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                              color: focused
                                  ? app.inkOn(app.core.tx)
                                  : staged
                                  ? tv.accent
                                  : app.core.tx.withValues(alpha: 0.72),
                            ),
                          ),
                        ),
                        if (pinned)
                          Positioned(
                            top: -4,
                            right: -4,
                            child: Icon(
                              Icons.star_rounded,
                              size: 11,
                              color: tv.favorite,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            channel.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              height: 1.1,
                              color: nameInk,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            caption,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              height: 1.2,
                              color: captionInk,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (pip != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: pip,
                          boxShadow: [
                            BoxShadow(
                              color: pip!.withValues(alpha: 0.5),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
