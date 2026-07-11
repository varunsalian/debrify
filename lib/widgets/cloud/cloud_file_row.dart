import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../screens/debrify_tv/widgets/tv_focus_scroll_wrapper.dart';
import '../../utils/tv_keys.dart';
import 'cloud_theme.dart';

/// Which leading icon chip a [CloudFileRow] shows.
enum CloudRowKind { folder, video, file, season, error }

/// Small status chip rendered on the meta line (e.g. "✓ Cached", "47%").
enum CloudBadgeKind { ok, warn, error, neutral }

class CloudRowBadge {
  final String text;
  final CloudBadgeKind kind;

  const CloudRowBadge(this.text, [this.kind = CloudBadgeKind.neutral]);
}

/// One secondary action of a [CloudFileRow].
///
/// Every action appears in the row's ⋮ menu; [showInStrip] additionally
/// surfaces it as a trailing icon on the row itself (the "strip"). The strip
/// is a shortcut — the menu is the complete, always-reachable set.
class CloudRowAction {
  final IconData icon;
  final String label;
  final VoidCallback onSelected;

  /// Destructive actions (Delete) render red in the ⋮ menu; everything else
  /// is monochrome white, Stremio-style.
  final bool destructive;

  final bool showInStrip;
  final bool enabled;

  const CloudRowAction({
    required this.icon,
    required this.label,
    required this.onSelected,
    this.destructive = false,
    this.showInStrip = false,
    this.enabled = true,
  });
}

/// Shared list row for the cloud/debrid file screens ("Quiet Rows" redesign,
/// see CLOUD_ROW_PLAN.md).
///
/// The row itself is the primary action: tap opens a folder or plays a video
/// ([onTap]); when [onTap] is null (plain files) tap opens the ⋮ menu instead.
/// Secondary actions live in a trailing icon strip + the ⋮ menu.
///
/// DPAD contract (the part that must not regress):
/// - The row is ONE focus node. OK activates it. `→` steps into the strip,
///   `←` walks back; `→` clamps at the last icon.
/// - Strip icon nodes are `skipTraversal: true`: invisible to tab/geometric
///   traversal (so ↑/↓ always land on adjacent ROWS, never a hidden icon) but
///   still programmatically focusable — so `→` can enter them and a closing
///   route (player/dialog) can restore focus onto them.
/// - ↑/↓ from inside the strip fall through to the framework, which moves to
///   the adjacent row geometrically ("vertical always resets to the row").
class CloudFileRow extends StatefulWidget {
  final CloudRowKind kind;
  final String title;

  /// Pre-formatted meta line ("18 files · 12.4 GB · Jun 15"). Null hides it.
  final String? meta;
  final List<CloudRowBadge> badges;

  /// Optional slot under the meta line (e.g. PikPak's inline "Downloading…").
  final Widget? extra;

  /// Primary action (folder → open, video → play). Null ⇒ tap opens the menu.
  final VoidCallback? onTap;
  final List<CloudRowAction> actions;

  final bool selectionMode;
  final bool selected;

  /// False for rows that can't be multi-selected (PikPak virtual seasons).
  final bool selectable;
  final VoidCallback? onToggleSelected;

  /// Screen-owned node for the row (screens keep their `_firstItemFocusNode`
  /// plumbing; it now anchors to the row instead of the old first pill).
  ///
  /// Deliberately NO `autofocus` parameter: on a lazily-built list row it is a
  /// footgun — the ListView disposes the row when scrolled far off-screen, and
  /// on scroll-back the rebuilt row's autofocus steals focus, which makes
  /// TvFocusScrollWrapper ensureVisible() yank the list to the top mid-scroll.
  /// Screens focus the first row imperatively (requestFocus on load) instead.
  final FocusNode? focusNode;

  /// If set, ↑ while the row is focused jumps here (WebDAV: server dropdown).
  final FocusNode? upFocusNode;

  /// If set, ← while the row is focused calls this (WebDAV: TV sidebar
  /// handoff). Unset ⇒ the key falls through, preserving a screen's existing
  /// geometric behavior.
  final VoidCallback? onNavigateLeft;

  const CloudFileRow({
    super.key,
    required this.kind,
    required this.title,
    this.meta,
    this.badges = const [],
    this.extra,
    this.onTap,
    this.actions = const [],
    this.selectionMode = false,
    this.selected = false,
    this.selectable = true,
    this.onToggleSelected,
    this.focusNode,
    this.upFocusNode,
    this.onNavigateLeft,
  });

  @override
  State<CloudFileRow> createState() => _CloudFileRowState();
}

class _CloudFileRowState extends State<CloudFileRow> {
  FocusNode? _internalNode;
  final List<FocusNode> _stripNodes = [];
  final GlobalKey _moreKey = GlobalKey();
  bool _hovered = false;

  FocusNode get _rowNode =>
      widget.focusNode ?? (_internalNode ??= FocusNode(debugLabel: 'cloud-row'));

  List<CloudRowAction> get _stripActions =>
      [for (final a in widget.actions) if (a.showInStrip && a.enabled) a];

  bool get _hasMenu => widget.actions.isNotEmpty;

  /// Strip slots = strip actions + the trailing ⋮ (when there is a menu).
  /// Derived from widget.actions only — never from focus/selection state — so
  /// node lifecycle changes happen exclusively in init/didUpdateWidget.
  int get _stripSlotCount => _stripActions.length + (_hasMenu ? 1 : 0);

  @override
  void initState() {
    super.initState();
    _syncStripNodes();
  }

  @override
  void didUpdateWidget(CloudFileRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncStripNodes();
  }

  void _syncStripNodes() {
    final want = _stripSlotCount;
    while (_stripNodes.length < want) {
      _stripNodes.add(FocusNode(
        debugLabel: 'cloud-row-action-${_stripNodes.length}',
        // Reachable only via the row's explicit ←/→ handling (or a route
        // restoring focus) — never by tab or geometric arrow traversal.
        skipTraversal: true,
      ));
    }
    while (_stripNodes.length > want) {
      final node = _stripNodes.removeLast();
      if (node.hasFocus) _rowNode.requestFocus();
      node.dispose();
    }
  }

  @override
  void dispose() {
    for (final node in _stripNodes) {
      node.dispose();
    }
    _internalNode?.dispose();
    super.dispose();
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  void _handlePrimary() {
    if (widget.selectionMode) {
      if (widget.selectable) widget.onToggleSelected?.call();
      return;
    }
    if (widget.onTap != null) {
      widget.onTap!();
    } else if (_hasMenu) {
      _openMenu();
    }
  }

  void _fireStripSlot(int index) {
    final strip = _stripActions;
    if (index < strip.length) {
      strip[index].onSelected();
    } else {
      _openMenu();
    }
  }

  Future<void> _openMenu({Offset? globalPosition}) async {
    if (widget.actions.isEmpty || !mounted) return;

    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    RelativeRect position;
    final anchorContext = _moreKey.currentContext ?? context;
    final anchorBox = anchorContext.findRenderObject() as RenderBox?;
    if (globalPosition != null) {
      position = RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        overlay.size.width - globalPosition.dx,
        overlay.size.height - globalPosition.dy,
      );
    } else if (anchorBox != null) {
      position = RelativeRect.fromRect(
        Rect.fromPoints(
          anchorBox.localToGlobal(Offset.zero, ancestor: overlay),
          anchorBox.localToGlobal(anchorBox.size.bottomRight(Offset.zero),
              ancestor: overlay),
        ),
        Offset.zero & overlay.size,
      );
    } else {
      position = RelativeRect.fill;
    }

    final hadFocus = _rowNode.hasFocus;
    final chosen = await showMenu<CloudRowAction>(
      context: context,
      position: position,
      color: CloudTheme.menuSurface,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      items: [
        for (final action in widget.actions)
          PopupMenuItem<CloudRowAction>(
            value: action,
            enabled: action.enabled,
            height: 44,
            child: Row(
              children: [
                Icon(
                  action.icon,
                  size: 18,
                  color: !action.enabled
                      ? Colors.white.withValues(alpha: 0.3)
                      : action.destructive
                          ? CloudTheme.red
                          : Colors.white.withValues(alpha: 0.75),
                ),
                const SizedBox(width: 12),
                Text(
                  action.label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    color: !action.enabled
                        ? Colors.white.withValues(alpha: 0.35)
                        : action.destructive
                            ? CloudTheme.red
                            : Colors.white.withValues(alpha: 0.95),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
    // Dismissed without choosing: the menu route already restored focus to
    // whatever opened it (the ⋮ icon or the row), so OK reopens the menu —
    // matching the old PopupMenuButton. Don't re-anchor.
    if (chosen == null) return;
    // Re-anchor focus on the row BEFORE running the action, so if the action
    // pushes a dialog/route its pop restores focus to the row (which always
    // exists) rather than to a strip node that may be gone. Only the refocus
    // needs the row still mounted — the chosen action is a screen-owned
    // callback (delete/download/…) that must run regardless of this row's
    // lifecycle (a background refresh can drop this lazily-built row while the
    // menu is open).
    if (mounted && hadFocus) _rowNode.requestFocus();
    chosen.onSelected();
  }

  // ── Keys ───────────────────────────────────────────────────────────────────

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final isRepeat = event is KeyRepeatEvent;

    if (node.hasPrimaryFocus) {
      // The row itself is focused.
      if (isActivateOrSpaceKey(key)) {
        if (!isRepeat) _handlePrimary();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowRight &&
          !widget.selectionMode &&
          _stripNodes.isNotEmpty) {
        _stripNodes.first.requestFocus();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowLeft &&
          widget.onNavigateLeft != null) {
        if (!isRepeat) widget.onNavigateLeft!();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowUp && widget.upFocusNode != null) {
        widget.upFocusNode!.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // Bubbled up from a focused strip icon.
    final i = _stripNodes.indexWhere((n) => n.hasPrimaryFocus);
    if (i < 0) return KeyEventResult.ignored;
    if (isActivateOrSpaceKey(key)) {
      if (!isRepeat) _fireStripSlot(i);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      // Clamp at the last icon: past it there is nothing meaningful on TV and
      // letting focus escape would strand it.
      if (i < _stripNodes.length - 1) _stripNodes[i + 1].requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (i == 0) {
        _rowNode.requestFocus();
      } else {
        _stripNodes[i - 1].requestFocus();
      }
      return KeyEventResult.handled;
    }
    // ↑/↓: fall through — strip nodes are skipTraversal, so geometric
    // traversal moves focus to the adjacent ROW.
    return KeyEventResult.ignored;
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  static const _iconChipStyles = <CloudRowKind, (IconData, Color)>{
    CloudRowKind.folder: (Icons.folder_rounded, CloudTheme.amber),
    CloudRowKind.video: (Icons.play_arrow_rounded, CloudTheme.blue),
    CloudRowKind.file: (Icons.insert_drive_file_rounded, Colors.white),
    CloudRowKind.season: (Icons.video_library_rounded, CloudTheme.purple),
    CloudRowKind.error: (Icons.error_outline_rounded, CloudTheme.red),
  };

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    final rowFocused = _rowNode.hasPrimaryFocus;
    final parked = !rowFocused && _stripNodes.any((n) => n.hasPrimaryFocus);
    final engaged = _hovered || rowFocused || parked;

    Color borderColor;
    Color bgColor;
    if (rowFocused) {
      borderColor = CloudTheme.accent;
      bgColor = CloudTheme.accent.withValues(alpha: 0.10);
    } else if (parked) {
      borderColor = CloudTheme.accent.withValues(alpha: 0.35);
      bgColor = CloudTheme.accent.withValues(alpha: 0.06);
    } else if (widget.selectionMode && widget.selected) {
      borderColor = CloudTheme.accent.withValues(alpha: 0.55);
      bgColor = CloudTheme.accent.withValues(alpha: 0.08);
    } else if (_hovered) {
      borderColor = Colors.transparent;
      bgColor = Colors.white.withValues(alpha: 0.045);
    } else {
      borderColor = Colors.transparent;
      bgColor = Colors.transparent;
    }

    final (chipIcon, chipColor) = _iconChipStyles[widget.kind]!;
    final iconChip = Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: chipColor.withValues(
            alpha: widget.kind == CloudRowKind.file ? 0.06 : 0.13),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Icon(
        chipIcon,
        size: 19,
        color: widget.kind == CloudRowKind.file
            ? Colors.white.withValues(alpha: 0.55)
            : chipColor,
      ),
    );

    final title = Text(
      widget.title,
      maxLines: compact ? 2 : 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        height: 1.3,
        color: Colors.white.withValues(alpha: 0.95),
      ),
    );

    final metaChildren = <Widget>[
      if (widget.meta != null && widget.meta!.isNotEmpty)
        Text(
          widget.meta!,
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withValues(alpha: 0.5),
          ),
        ),
      for (final badge in widget.badges) _badge(badge),
    ];
    final metaLine = metaChildren.isEmpty
        ? null
        : Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: metaChildren,
          );

    final showStrip = !widget.selectionMode && _stripNodes.isNotEmpty;
    final strip = showStrip ? _buildStrip(engaged: engaged, compact: compact) : null;

    final leadingCheckbox = widget.selectionMode
        ? Padding(
            padding: const EdgeInsets.only(right: 4),
            child: ExcludeFocus(
              child: Checkbox(
                value: widget.selected,
                onChanged: widget.selectable
                    ? (_) => widget.onToggleSelected?.call()
                    : null,
                activeColor: CloudTheme.accent,
                visualDensity: VisualDensity.compact,
                side: BorderSide(
                  color: Colors.white.withValues(alpha: 0.4),
                  width: 1.5,
                ),
              ),
            ),
          )
        : null;

    // One skeleton for both widths; compact only moves the strip onto the
    // meta line (and the title gets its second line via maxLines above).
    final content = Row(
      crossAxisAlignment:
          compact ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        if (leadingCheckbox != null) leadingCheckbox,
        iconChip,
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              title,
              if (compact && (metaLine != null || strip != null)) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(child: metaLine ?? const SizedBox.shrink()),
                    if (strip != null) strip,
                  ],
                ),
              ] else if (!compact && metaLine != null) ...[
                const SizedBox(height: 4),
                metaLine,
              ],
              if (widget.extra != null) ...[
                const SizedBox(height: 6),
                widget.extra!,
              ],
            ],
          ),
        ),
        if (!compact && strip != null) ...[
          const SizedBox(width: 8),
          strip,
        ],
        if (!compact &&
            !widget.selectionMode &&
            widget.kind == CloudRowKind.folder &&
            widget.onTap != null)
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: Colors.white.withValues(alpha: 0.3),
            ),
          ),
      ],
    );

    return TvFocusScrollWrapper(
      child: Focus(
        focusNode: _rowNode,
        onKeyEvent: _onKeyEvent,
        onFocusChange: (_) {
          if (mounted) setState(() {});
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _handlePrimary,
            onLongPressStart: widget.selectionMode
                ? null
                : (details) => _openMenu(globalPosition: details.globalPosition),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(bottom: 4),
              padding: compact
                  ? const EdgeInsets.fromLTRB(12, 10, 8, 8)
                  : const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: borderColor, width: 1.5),
              ),
              child: content,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStrip({required bool engaged, required bool compact}) {
    final strip = _stripActions;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < strip.length; i++)
          _stripIcon(
            slot: i,
            icon: strip[i].icon,
            tooltip: strip[i].label,
            onTap: strip[i].onSelected,
            engaged: engaged,
            compact: compact,
          ),
        if (_hasMenu)
          _stripIcon(
            slot: strip.length,
            icon: Icons.more_vert,
            tooltip: 'More options',
            onTap: () => _openMenu(),
            engaged: engaged,
            compact: compact,
            anchorKey: _moreKey,
          ),
      ],
    );
  }

  Widget _stripIcon({
    required int slot,
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    required bool engaged,
    required bool compact,
    Key? anchorKey,
  }) {
    final node = _stripNodes[slot];
    final focused = node.hasPrimaryFocus;
    final size = compact ? 36.0 : 32.0;
    return Focus(
      focusNode: node,
      onFocusChange: (_) {
        if (mounted) setState(() {});
      },
      child: Tooltip(
        message: tooltip,
        waitDuration: const Duration(milliseconds: 500),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          // Pad the hit target past the painted box to ~44dp (Material touch
          // minimum): a near-miss lands on this icon — like the old 48dp
          // IconButton — instead of falling through to the row's open/play.
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 4,
              vertical: (44 - size) / 2,
            ),
            child: AnimatedContainer(
              key: anchorKey,
              duration: const Duration(milliseconds: 150),
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: focused
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: focused ? CloudTheme.accent : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Icon(
                icon,
                size: 18,
                color: focused
                    ? Colors.white
                    : Colors.white.withValues(alpha: engaged ? 0.9 : 0.45),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _badge(CloudRowBadge badge) {
    final (fg, bgAlpha) = switch (badge.kind) {
      CloudBadgeKind.ok => (CloudTheme.green, 0.14),
      CloudBadgeKind.warn => (CloudTheme.amber, 0.13),
      CloudBadgeKind.error => (CloudTheme.red, 0.12),
      CloudBadgeKind.neutral => (Colors.white.withValues(alpha: 0.6), 0.06),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: bgAlpha),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        badge.text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          color: fg,
        ),
      ),
    );
  }
}
