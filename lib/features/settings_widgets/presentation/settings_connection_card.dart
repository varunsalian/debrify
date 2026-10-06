import 'package:debrify/features/settings_widgets/presentation/settings_connection_info.dart';
import 'package:debrify/services/main_page_bridge.dart' show MainPageBridge;
import 'package:debrify/theme/app_focus.dart';
import 'package:debrify/theme/app_motion.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/theme/widgets/parallax_focus.dart';
import 'package:debrify/utils/tv_reveal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Uniform monochrome initials chip for a connection provider ("RD", "JP").
/// Replaces the old per-provider colored gradient icon boxes — status is
/// carried by the dot/text instead, keeping the chrome calm like Stremio.
String settingsInitialsFor(String title) {
  final words = title
      .split(RegExp(r'[\s&]+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.length >= 2) return (words[0][0] + words[1][0]).toUpperCase();
  if (words.isEmpty) return '?';
  // Single word: prefer internal capitals (AllDebrid → AD, PikPak → PP).
  final caps = words[0].replaceAll(RegExp(r'[^A-Z]'), '');
  if (caps.length >= 2) return caps.substring(0, 2);
  return words[0].length >= 2
      ? words[0].substring(0, 2).toUpperCase()
      : words[0].toUpperCase();
}

/// Flat provider row: mono initials chip · name + caption · status dot + text
/// · chevron. Focus/hover paints the accent ring, Stremio-style.
///
/// The manual DPAD neighbor wiring (and the sidebar hand-off on left from the
/// left column) is preserved verbatim from the original card — do not swap it
/// for default traversal without testing on real TV hardware.
class ConnectionCard extends StatefulWidget {
  final ConnectionInfo info;
  final FocusNode? focusNode;
  final bool isLeftColumn;
  final FocusNode? leftNeighbor;
  final FocusNode? rightNeighbor;
  final FocusNode? upNeighbor;
  final FocusNode? downNeighbor;

  const ConnectionCard({
    super.key,
    required this.info,
    this.focusNode,
    this.isLeftColumn = true,
    this.leftNeighbor,
    this.rightNeighbor,
    this.upNeighbor,
    this.downNeighbor,
  });

  @override
  State<ConnectionCard> createState() => _ConnectionCardState();
}

class _ConnectionCardState extends State<ConnectionCard> {
  /// The wrapper's own node, so focus can be read rather than remembered —
  /// see the note on `_SettingsTileState._focused`.
  final FocusNode _wrapNode = FocusNode(debugLabel: 'ConnectionCard');

  bool _hovered = false;

  /// Live, never cached. `hasFocus` is DESCENDANT-inclusive, so this wrapper
  /// reads true while the card's own InkWell below it holds focus — which is
  /// the intent, and the same value `Focus.onFocusChange` used to deliver.
  bool get _focused => _wrapNode.hasFocus;

  /// The theme's tempo, resolved in the one hook that may depend on inherited
  /// widgets and still re-runs when they change. The reveal below fires from a
  /// key handler, which is no place for a scope lookup.
  late AppMotion _motion;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motion = AppMotion.of(context);
  }

  @override
  void dispose() {
    _wrapNode.dispose();
    super.dispose();
  }

  // Helper to focus and scroll into view
  void _focusAndScroll(FocusNode target) {
    target.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (target.context != null) {
        tvRevealMinimal(
          target.context!,
          duration: _motion.scaled(const Duration(milliseconds: 200)),
        );
      }
    });
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (widget.leftNeighbor != null) {
        _focusAndScroll(widget.leftNeighbor!);
        return KeyEventResult.handled;
      } else if (widget.isLeftColumn && MainPageBridge.focusTvSidebar != null) {
        // Left column with no left neighbor: open sidebar
        MainPageBridge.focusTvSidebar!();
        return KeyEventResult.handled;
      }
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (widget.rightNeighbor != null) {
        _focusAndScroll(widget.rightNeighbor!);
        return KeyEventResult.handled;
      }
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (widget.upNeighbor != null) {
        _focusAndScroll(widget.upNeighbor!);
        return KeyEventResult.handled;
      }
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (widget.downNeighbor != null) {
        _focusAndScroll(widget.downNeighbor!);
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    final info = widget.info;
    final bool active = settingsConnectionIsReady(info);
    // One color for both the dot and the status text so they can't disagree.
    final Color baseStateColor = info.connected
        ? (active ? t.success : t.danger)
        : t.dim2;
    final bool lit = _focused || _hovered;
    final bool spotlight = app.id == 'spotlight';
    final bool inverse =
        spotlight && lit && app.focus.expression == FocusExpression.parallax;
    final Color foreground = inverse ? app.inkOn(app.core.tx) : app.core.tx;
    final Color stateColor = inverse
        ? Color.lerp(baseStateColor, foreground, 0.42)!
        : baseStateColor;
    final radius = spotlight ? app.shape.br(13) : BorderRadius.circular(14);

    return ParallaxFocus(
      focused: _focused,
      shape: ParallaxShape.settingsRow,
      radius: radius,
      child: Focus(
        focusNode: _wrapNode,
        onKeyEvent: _onKeyEvent,
        // hasFocus includes the InkWell child node, so this lights up when the
        // card's InkWell receives DPAD focus.
        onFocusChange: (_) => setState(() {}),
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          // Plain Container (snap, no tween): animating a blurred BoxShadow
          // re-rasterizes per frame and janks weak TV GPUs (see
          // tv_sidebar_nav.dart for the same rule).
          child: Container(
            decoration: BoxDecoration(
              color: inverse
                  ? app.core.tx
                  : (lit
                        ? t.panel2
                        : spotlight
                        ? app.fade(app.core.tx, 0.047)
                        : t.panel),
              borderRadius: radius,
              border: Border.all(
                color: inverse ? app.core.tx : (_focused ? t.accent : t.line),
                width: 1,
              ),
              boxShadow: _focused && !inverse
                  ? [
                      BoxShadow(
                        color: t.accent.withValues(alpha: 0.28),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : null,
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: radius,
              child: InkWell(
                focusNode: widget.focusNode,
                borderRadius: radius,
                onTap: () async {
                  await info.onTap();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 13,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: inverse
                              ? foreground.withValues(alpha: 0.08)
                              : app.fade(
                                  app.core.tx,
                                  spotlight ? 0.065 : 0.055,
                                ),
                          borderRadius: app.shape.br(11),
                          border: Border.all(
                            color: inverse
                                ? foreground.withValues(alpha: 0.1)
                                : t.line,
                          ),
                        ),
                        child: Text(
                          settingsInitialsFor(info.title),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                            color: inverse
                                ? foreground
                                : (lit ? t.accent2 : t.dim),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              info.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: spotlight
                                    ? foreground
                                    : Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              info.caption,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: inverse
                                    ? foreground.withValues(alpha: 0.5)
                                    : t.dim,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: stateColor,
                          shape: BoxShape.circle,
                          boxShadow: active
                              ? [
                                  BoxShadow(
                                    color: stateColor.withValues(alpha: 0.55),
                                    blurRadius: 7,
                                  ),
                                ]
                              : null,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        info.status,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: stateColor,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: inverse
                            ? foreground.withValues(alpha: 0.42)
                            : t.dim2,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
