import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/tv_keys.dart';

/// One action row in [showDebridActionSheet].
class DebridActionItem {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;

  /// Short label used when this action renders as a primary pill (e.g. "Play"
  /// instead of "Play now"). Falls back to [title].
  final String? pillLabel;

  const DebridActionItem({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.enabled = true,
    this.pillLabel,
    required this.onTap,
  });
}

/// The app's "Added to `<provider>`" post-add chooser — the Neon Sheet.
///
/// On phones it slides up as a glassy bottom sheet with the three primary
/// actions (Play / Download / Playlist) as big pills in thumb reach and the
/// rest as a quiet compact list. On desktop and TV the identical component
/// floats as a centered card. DPAD: pills traverse left/right, then down into
/// the list. Each action pops the sheet first, then runs.
Future<void> showDebridActionSheet(
  BuildContext context, {
  required String providerLabel,
  required String torrentName,
  required List<Color> gradient,
  required IconData providerIcon,
  required String subtitle,
  required List<DebridActionItem> actions,
}) {
  final isPhone = MediaQuery.of(context).size.width < 600;
  if (isPhone) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (sheetContext) => _NeonActionSheet(
        providerLabel: providerLabel,
        torrentName: torrentName,
        gradient: gradient,
        providerIcon: providerIcon,
        subtitle: subtitle,
        actions: actions,
        asBottomSheet: true,
      ),
    );
  }
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: _NeonActionSheet(
          providerLabel: providerLabel,
          torrentName: torrentName,
          gradient: gradient,
          providerIcon: providerIcon,
          subtitle: subtitle,
          actions: actions,
          asBottomSheet: false,
        ),
      ),
    ),
  );
}

class _NeonActionSheet extends StatelessWidget {
  final String providerLabel;
  final String torrentName;
  final List<Color> gradient;
  final IconData providerIcon;
  final String subtitle;
  final List<DebridActionItem> actions;
  final bool asBottomSheet;

  const _NeonActionSheet({
    required this.providerLabel,
    required this.torrentName,
    required this.gradient,
    required this.providerIcon,
    required this.subtitle,
    required this.actions,
    required this.asBottomSheet,
  });

  @override
  Widget build(BuildContext context) {
    // First three actions are the primaries (Play / Download / Playlist —
    // the order _showChooser builds); everything else goes to the quiet list.
    final pillCount = actions.length >= 4 ? 3 : actions.length;
    final pills = actions.sublist(0, pillCount);
    final rest = actions.sublist(pillCount);
    // Autofocus the first *enabled* action — "Play" can be disabled (no video
    // URL), and autofocusing a non-focusable node strands DPAD on TV.
    final firstEnabledPill = pills.indexWhere((a) => a.enabled);
    final firstEnabledRest = firstEnabledPill >= 0
        ? -1
        : rest.indexWhere((a) => a.enabled);

    final radius = asBottomSheet
        ? const BorderRadius.vertical(top: Radius.circular(26))
        : BorderRadius.circular(26);

    void close() => Navigator.of(context).pop();

    return FocusTraversalGroup(
      policy: ReadingOrderTraversalPolicy(),
      // The drop shadow sits OUTSIDE the ClipRRect — inside it the clip would
      // swallow it and the sheet would sit flat on the scrim.
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.55),
              blurRadius: 40,
              offset: asBottomSheet
                  ? const Offset(0, -8)
                  : const Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xF212141D),
                borderRadius: radius,
                border:
                    Border.all(color: Colors.white.withValues(alpha: 0.10)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (asBottomSheet)
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(top: 10, bottom: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      18,
                      asBottomSheet ? 8 : 18,
                      asBottomSheet ? 18 : 12,
                      14,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: gradient,
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            providerIcon,
                            color: Colors.white,
                            size: 21,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                providerLabel.toUpperCase(),
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.55),
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.6,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                torrentName,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13.5,
                                  height: 1.3,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // The sheet dismisses by swipe/back; the floating card
                        // needs an explicit close affordance.
                        if (!asBottomSheet) _NeonCloseButton(onTap: close),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                    child: Row(
                      children: [
                        for (var i = 0; i < pills.length; i++) ...[
                          if (i > 0) const SizedBox(width: 10),
                          Expanded(
                            child: _NeonPill(
                              item: pills[i],
                              hero: i == 0,
                              autofocus: i == firstEnabledPill,
                              onActivate: () {
                                close();
                                pills[i].onTap();
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (rest.isNotEmpty)
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var i = 0; i < rest.length; i++)
                              _NeonListRow(
                                item: rest[i],
                                autofocus: i == firstEnabledRest,
                                onActivate: () {
                                  close();
                                  rest[i].onTap();
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                  // Bottom safe-area: showModalBottomSheet's useSafeArea only
                  // covers the top/sides, so pad past gesture-nav bars here.
                  SizedBox(
                    height: asBottomSheet
                        ? 14 + MediaQuery.paddingOf(context).bottom
                        : 12,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shared focus/hover/DPAD plumbing for the sheet's interactive pieces.
/// Activation fires on key-up (matching the app's other TV dialogs) and only
/// when enabled; disabled pieces can't take focus.
class _NeonFocusable extends StatefulWidget {
  final bool enabled;
  final bool autofocus;
  final VoidCallback onActivate;
  final Widget Function(BuildContext context, bool active) builder;

  const _NeonFocusable({
    required this.enabled,
    required this.autofocus,
    required this.onActivate,
    required this.builder,
  });

  @override
  State<_NeonFocusable> createState() => _NeonFocusableState();
}

class _NeonFocusableState extends State<_NeonFocusable> {
  bool _focused = false;
  bool _hovered = false;
  late FocusHighlightMode _highlightMode;

  @override
  void initState() {
    super.initState();
    _highlightMode = FocusManager.instance.highlightMode;
    FocusManager.instance.addHighlightModeListener(_onHighlightModeChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_onHighlightModeChanged);
    super.dispose();
  }

  void _onHighlightModeChanged(FocusHighlightMode mode) {
    if (mounted) setState(() => _highlightMode = mode);
  }

  /// Focus paints only for DPAD/keyboard input. Autofocus grants focus even
  /// under touch, and without this gate the Play pill opens pre-highlighted
  /// (scaled, ringed) on phones as if a remote were pointing at it.
  bool get _showFocus =>
      _focused && _highlightMode == FocusHighlightMode.traditional;

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (!isActivateKey(event.logicalKey)) return KeyEventResult.ignored;
    if (event is KeyDownEvent) return KeyEventResult.handled;
    if (event is KeyUpEvent) {
      if (widget.enabled) widget.onActivate();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.enabled && (_showFocus || _hovered);
    return Focus(
      autofocus: widget.autofocus,
      canRequestFocus: widget.enabled,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: _handleKeyEvent,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: widget.enabled ? SystemMouseCursors.click : MouseCursor.defer,
        child: GestureDetector(
          onTap: widget.enabled ? widget.onActivate : null,
          child: widget.builder(context, active),
        ),
      ),
    );
  }
}

/// A big primary pill (icon chip over a short label). The hero pill (Play)
/// carries the neon fill + glow; the others stay glassy until focused.
class _NeonPill extends StatelessWidget {
  final DebridActionItem item;
  final bool hero;
  final bool autofocus;
  final VoidCallback onActivate;

  const _NeonPill({
    required this.item,
    required this.hero,
    required this.autofocus,
    required this.onActivate,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: item.enabled ? 1.0 : 0.35,
      child: _NeonFocusable(
        enabled: item.enabled,
        autofocus: autofocus,
        onActivate: onActivate,
        builder: (context, active) {
          // The hero pill (Play) sits slightly brighter than its siblings;
          // focus/hover is a plain white ring — no per-action color.
          final lit = active || (hero && item.enabled);
          return AnimatedScale(
            scale: active ? 1.04 : 1.0,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(
                  alpha: active ? 0.14 : (lit ? 0.10 : 0.05),
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withValues(
                    alpha: active ? 0.85 : (lit ? 0.22 : 0.09),
                  ),
                  width: active ? 1.6 : 1,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: lit ? 0.14 : 0.08),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      item.icon,
                      color: Colors.white.withValues(alpha: 0.92),
                      size: 20,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    item.pillLabel ?? item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A quiet compact row for the secondary actions.
class _NeonListRow extends StatelessWidget {
  final DebridActionItem item;
  final bool autofocus;
  final VoidCallback onActivate;

  const _NeonListRow({
    required this.item,
    required this.autofocus,
    required this.onActivate,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: item.enabled ? 1.0 : 0.35,
      child: _NeonFocusable(
        enabled: item.enabled,
        autofocus: autofocus,
        onActivate: onActivate,
        builder: (context, active) => AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: active
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: active
                  ? Colors.white.withValues(alpha: 0.55)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Icon(
                item.icon,
                size: 17,
                color: Colors.white.withValues(alpha: active ? 0.95 : 0.55),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.42),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: Colors.white.withValues(alpha: active ? 0.8 : 0.25),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NeonCloseButton extends StatelessWidget {
  final VoidCallback onTap;
  const _NeonCloseButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _NeonFocusable(
      enabled: true,
      autofocus: false,
      onActivate: onTap,
      builder: (context, active) => Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: active ? 0.16 : 0.06),
          shape: BoxShape.circle,
          border: Border.all(
            color: active
                ? Colors.white.withValues(alpha: 0.5)
                : Colors.transparent,
          ),
        ),
        child: Icon(
          Icons.close_rounded,
          size: 17,
          color: Colors.white.withValues(alpha: active ? 0.95 : 0.6),
        ),
      ),
    );
  }
}
