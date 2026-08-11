import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_motion.dart';
import '../theme/app_theme_scope.dart';
import 'desktop_sidebar_nav.dart' show DesktopNavEntry;

/// The pointer-world sibling of the TV rail's 'pill' style: no rail at all —
/// content runs full-bleed and a floating capsule at the top-left shows the
/// current tab. Clicking the capsule opens the menu as an overlay panel over
/// the page; picking an entry, clicking away or pressing Escape closes it.
///
/// Deliberately NOT a reuse of [TvSidebarNav]'s pill: that one is welded to
/// the DPAD focus model (skip-traversal nodes, the LEFT-only door, edge glow
/// driven by where content focus sits). This one is pure pointer — hover and
/// click — with the same *ideas*: the capsule holds its label for a moment
/// after you arrive somewhere, then fades to a quiet icon.
///
/// Mounted as a `Positioned.fill` layer over the content. Its base Stack has
/// no full-screen hit surface while closed — only the capsule itself is
/// clickable — so the page underneath keeps every interaction.
class DesktopPillNav extends StatefulWidget {
  /// Index into [entries] of the active screen.
  final int currentIndex;
  final List<DesktopNavEntry> entries;

  /// Called with the index into [entries] that was picked.
  final ValueChanged<int> onTap;

  /// Finger-sized targets (touch tablets — iPad / Android tablet).
  final bool expanded;

  const DesktopPillNav({
    super.key,
    required this.currentIndex,
    required this.entries,
    required this.onTap,
    this.expanded = false,
  });

  /// Handles for tests.
  static const Key pillKey = ValueKey('desktop-sidebar-pill');
  static const Key scrimKey = ValueKey('desktop-sidebar-scrim');
  static const Key panelKey = ValueKey('desktop-sidebar-panel');

  @override
  State<DesktopPillNav> createState() => _DesktopPillNavState();
}

class _DesktopPillNavState extends State<DesktopPillNav> {
  bool _open = false;

  /// The capsule's label is up: briefly after arriving on a tab, and while
  /// the pointer rests on the capsule. Idle, the capsule quiets down to a
  /// dim icon so it never competes with the page it floats over.
  bool _labelUp = true;
  bool _pillHovered = false;
  Timer? _hold;

  /// How long the capsule keeps its label after a tab change — long enough
  /// to read where you are, short enough to be gone before it nags.
  static const Duration _labelHold = Duration(milliseconds: 1400);

  /// Escape-to-close. Requested on open, released on close, so the page's
  /// own keyboard handling is untouched while the menu is shut.
  final FocusNode _panelFocus =
      FocusNode(debugLabel: 'desktop-pill-panel');

  /// Whatever held keyboard focus when the panel opened (a search field,
  /// mid-word). Restored on the close paths that stay on the same tab —
  /// scrim, Escape — so opening the menu to peek never costs the user their
  /// caret. A pick switches tabs and deliberately does not restore.
  FocusNode? _restoreFocus;

  /// True from open until the scrim's CLOSE fade finishes. The modal hit
  /// surface must outlive `_open` by the fade: dropping it the instant the
  /// scrim starts fading lets a quick second click land on whatever page
  /// control happens to sit under the pointer.
  bool _scrimBlocking = false;

  @override
  void initState() {
    super.initState();
    // Orient on mount: show which tab this is, then quiet down.
    _showLabel();
  }

  @override
  void didUpdateWidget(DesktopPillNav old) {
    super.didUpdateWidget(old);
    // Arriving somewhere new is exactly when the label earns its keep.
    if (old.currentIndex != widget.currentIndex) _showLabel();
  }

  @override
  void dispose() {
    _hold?.cancel();
    _panelFocus.dispose();
    super.dispose();
  }

  void _showLabel() {
    _hold?.cancel();
    if (!_labelUp) setState(() => _labelUp = true);
    _labelUp = true;
    _hold = Timer(_labelHold, () {
      if (!mounted || _pillHovered) return;
      setState(() => _labelUp = false);
    });
  }

  void _openPanel() {
    final prev = FocusManager.instance.primaryFocus;
    // A bare scope means nothing real was focused — nothing to give back.
    _restoreFocus =
        (prev != null && prev != _panelFocus && prev is! FocusScopeNode)
            ? prev
            : null;
    setState(() {
      _open = true;
      _scrimBlocking = true;
    });
    _panelFocus.requestFocus();
  }

  void _close({bool restoreFocus = true}) {
    if (!_open) return;
    // _scrimBlocking stays true — the scrim's onEnd clears it when the
    // close fade lands.
    setState(() => _open = false);
    final prev = _restoreFocus;
    _restoreFocus = null;
    if (restoreFocus &&
        prev != null &&
        (prev.context?.mounted ?? false) &&
        prev.canRequestFocus) {
      prev.requestFocus();
    } else {
      _panelFocus.unfocus();
    }
    _showLabel();
  }

  void _pick(int i) {
    _close(restoreFocus: false);
    widget.onTap(i);
  }

  @override
  Widget build(BuildContext context) {
    final motion = AppMotion.of(context);
    final slide = motion.scaled(const Duration(milliseconds: 200));
    // This layer is a Positioned.fill OVER the shell's SafeArea, so system
    // insets (an iPad/landscape-cutout left notch, a status bar) must be
    // taken here — the scrim stays full-bleed on purpose, but the capsule
    // and the panel's content have to stay reachable.
    final insets = MediaQuery.paddingOf(context);
    return Stack(
      children: [
        // Scrim — always mounted so open/close cross-fades. The hit surface
        // outlives `_open` by the fade (see _scrimBlocking) so a quick
        // second click can't reach the page through a half-faded veil.
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !_open && !_scrimBlocking,
            child: AnimatedOpacity(
              opacity: _open ? 1 : 0,
              duration: slide,
              curve: Curves.easeOut,
              onEnd: () {
                if (!_open && mounted) {
                  setState(() => _scrimBlocking = false);
                }
              },
              child: GestureDetector(
                key: DesktopPillNav.scrimKey,
                behavior: HitTestBehavior.opaque,
                onTap: _close,
                child: ColoredBox(
                  color: AppThemeScope.of(context).shell.sidebarScrim,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          child: IgnorePointer(
            ignoring: !_open,
            child: AnimatedSlide(
              // Past -1.0: the panel casts a shadow, and exactly -1 leaves
              // its blur peeking in from the edge while closed.
              offset: _open ? Offset.zero : const Offset(-1.1, 0),
              duration: slide,
              curve: Curves.easeOutCubic,
              child: _panel(context),
            ),
          ),
        ),
        // The capsule. Kept mounted while the panel is open (the panel
        // covers it) so the open/close transition never pops it in and out.
        Positioned(
          left: 14 + insets.left,
          // Below the frameless window's invisible drag strip.
          top: 34 + insets.top,
          child: AnimatedOpacity(
            opacity: _open ? 0 : 1,
            duration: slide,
            child: IgnorePointer(ignoring: _open, child: _pill(context)),
          ),
        ),
      ],
    );
  }

  Widget _pill(BuildContext context) {
    final app = AppThemeScope.of(context);
    final motion = AppMotion.of(context);
    final entry = widget.entries.isEmpty
        ? null
        : widget.entries[
            widget.currentIndex.clamp(0, widget.entries.length - 1)];
    if (entry == null) return const SizedBox.shrink();
    final lit = _labelUp || _pillHovered;
    final pad = widget.expanded ? 14.0 : 11.0;
    final vpad = widget.expanded ? 11.0 : 8.0;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        if (!mounted) return;
        setState(() => _pillHovered = true);
        _showLabel();
      },
      onExit: (_) {
        if (!mounted) return;
        setState(() => _pillHovered = false);
        _showLabel();
      },
      child: GestureDetector(
        onTap: _openPanel,
        behavior: HitTestBehavior.opaque,
        child: AnimatedOpacity(
          // Quiet at rest — present enough to find, dim enough to ignore.
          opacity: lit ? 1.0 : 0.55,
          duration: motion.scaled(const Duration(milliseconds: 180)),
          child: Container(
            key: DesktopPillNav.pillKey,
            padding:
                EdgeInsets.symmetric(horizontal: pad, vertical: vpad),
            decoration: BoxDecoration(
              color: app.shell.railBg,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: app.fade(app.core.tx, 0.10)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x59000000),
                  blurRadius: 18,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(entry.icon,
                    size: widget.expanded ? 22 : 19,
                    color: app.shell.navAccent),
                // The label collapses to nothing when the capsule quiets —
                // AnimatedSize so the pill shrinks around it instead of
                // clipping mid-word.
                AnimatedSize(
                  duration:
                      motion.scaled(const Duration(milliseconds: 180)),
                  curve: Curves.easeOut,
                  alignment: Alignment.centerLeft,
                  child: lit
                      ? Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text(
                            entry.label,
                            maxLines: 1,
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface,
                              fontSize: widget.expanded ? 13.5 : 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _panel(BuildContext context) {
    final app = AppThemeScope.of(context);
    final width = widget.expanded ? 268.0 : 236.0;
    final children = <Widget>[];
    String? lastSection;
    for (var i = 0; i < widget.entries.length; i++) {
      final e = widget.entries[i];
      if (lastSection != null && e.section != lastSection) {
        children.add(
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
            child: Container(
              height: 1,
              color: app.fade(app.core.tx, 0.06),
            ),
          ),
        );
      }
      lastSection = e.section;
      children.add(
        _PanelItem(
          icon: e.icon,
          label: e.label,
          selected: i == widget.currentIndex,
          expanded: widget.expanded,
          onTap: () => _pick(i),
        ),
      );
    }
    return Focus(
      focusNode: _panelFocus,
      onKeyEvent: (_, e) {
        if (e is KeyDownEvent &&
            e.logicalKey == LogicalKeyboardKey.escape) {
          _close();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Container(
        key: DesktopPillNav.panelKey,
        width: width,
        decoration: BoxDecoration(
          color: app.shell.railBg,
          border: Border(
            right: BorderSide(color: app.fade(app.core.tx, 0.08)),
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x73000000),
              blurRadius: 32,
              offset: Offset(6, 0),
            ),
          ],
        ),
        // The panel's INK runs edge to edge; its content steps inside the
        // system insets (cutout on the left, status bar up top) so every
        // row stays tappable.
        child: SafeArea(
          right: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 26, 20, 14),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: app.shape.br(8),
                      child: Image.asset(
                        'assets/app_icon.png',
                        width: 26,
                        height: 26,
                        // Tests (and a broken bundle) have no asset — the
                        // panel must not render a red error box for chrome.
                        errorBuilder: (_, __, ___) =>
                            const SizedBox(width: 26, height: 26),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(top: 2, bottom: 16),
                  children: children,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One row of the overlay panel: icon + label, hover highlight, accent when
/// active. Horizontal rows rather than the rail's stacked icon cells — a
/// temporary menu reads top-to-bottom like a list, not like a dock.
class _PanelItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final bool expanded;
  final VoidCallback onTap;

  const _PanelItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.expanded,
    required this.onTap,
  });

  @override
  State<_PanelItem> createState() => _PanelItemState();
}

class _PanelItemState extends State<_PanelItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final motion = AppMotion.of(context);
    final cs = Theme.of(context).colorScheme;
    final Color fg = widget.selected
        ? app.shell.navAccent
        : (_hovered ? cs.onSurface : app.fade(app.core.tx, 0.62));
    final Color bg = widget.selected
        ? app.shell.navAccent.withValues(alpha: 0.14)
        : (_hovered ? app.fade(app.core.tx, 0.05) : Colors.transparent);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) {
          if (mounted) setState(() => _hovered = true);
        },
        onExit: (_) {
          if (mounted) setState(() => _hovered = false);
        },
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: motion.scaled(const Duration(milliseconds: 130)),
            curve: Curves.easeOut,
            padding: EdgeInsets.symmetric(
              horizontal: 12,
              vertical: widget.expanded ? 12 : 9,
            ),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: app.shape.br(12),
            ),
            child: Row(
              children: [
                Icon(widget.icon,
                    size: widget.expanded ? 24 : 21, color: fg),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: fg,
                      fontSize: widget.expanded ? 13.5 : 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
