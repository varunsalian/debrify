import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/iptv_playlist.dart';
import '../../utils/tv_keys.dart';
import '../browse/brand_accent.dart';
import '../home/home_theme.dart';
import '../see_all/see_all_theme.dart';

/// Width the rail occupies in the two-pane Row. The expanded state is an
/// overlay (never a resize): widening the Row live would re-lay-out the
/// preview stage and resize its video surface mid-play.
const double kIptvSourceRailWidth = 64.0;

/// Width of the rail when it renders inline-expanded (wide desktop windows):
/// a persistent labeled source list instead of the hover overlay — no
/// ambiguity about what's open, nothing to dismiss.
const double kIptvSourceRailExpandedWidth = 232.0;

/// The TV two-pane source rail (redesign): every source one DPAD-LEFT away.
///
/// Collapsed it is a 64px column of icon chips — Favorites, Continue
/// watching, each playlist as a brand-tinted monogram, a gear for Manage.
/// While any rail chip is focused, an overlay panel expands over it showing
/// names and source types; it snaps in and out (no tween — TV GPU rule).
///
/// Focus grammar:
/// - The chips are ordinary traversable nodes, so LEFT from the guide/filters
///   lands here geometrically (nothing else exists on the far left).
/// - UP/DOWN walk the rail; RIGHT hands focus back via [onRight].
/// - LEFT is deliberately NOT handled: it bubbles to the app-wide handler,
///   which opens the TV sidebar — the rail sits at the content's true left
///   edge, so it inherits the "LEFT at the edge opens the menu" contract.
///
/// When there are more sources than fit the height, the tail collapses into
/// a "more" chip that opens the full picker via [onOverflow]; the selected
/// source is always kept visible.
class IptvSourceRail extends StatefulWidget {
  final List<IptvPlaylist> playlists;
  final String? selectedId;
  final ValueChanged<IptvPlaylist> onSelect;
  final VoidCallback onManage;
  final VoidCallback onOverflow;

  /// Drives the expanded panel's surface: on TV it must be fully opaque (it
  /// overlays the preview's underlay punch-hole — translucency ghosts the
  /// video), while desktop composites in-layer (Texture) and gets a glassy
  /// translucent panel that keeps the content behind readable.
  final bool isTelevision;

  /// Render as a persistent [kIptvSourceRailExpandedWidth]-wide labeled list
  /// (wide desktop windows) instead of the collapsed icon column with its
  /// hover/focus overlay. The host sizes the Row accordingly.
  final bool inlineExpanded;

  /// RIGHT from any chip — the host decides where focus goes (filters row).
  final VoidCallback? onRight;

  const IptvSourceRail({
    super.key,
    required this.playlists,
    required this.selectedId,
    required this.onSelect,
    required this.onManage,
    required this.onOverflow,
    required this.isTelevision,
    this.inlineExpanded = false,
    this.onRight,
  });

  @override
  State<IptvSourceRail> createState() => _IptvSourceRailState();
}

/// One rail slot: a playlist, or the fixed "more"/"manage" chips.
class _RailEntry {
  final String key;
  final IptvPlaylist? playlist;
  final IconData? icon;
  final String label;
  final String subtitle;
  const _RailEntry({
    required this.key,
    this.playlist,
    this.icon,
    required this.label,
    required this.subtitle,
  });
}

class _IptvSourceRailState extends State<IptvSourceRail> {
  /// Keyed by entry key (playlist id / 'more' / 'manage') — playlists are
  /// re-instantiated on every settings reload, so instance identity would
  /// leak nodes; ids are stable.
  final Map<String, FocusNode> _nodes = {};
  final LayerLink _link = LayerLink();
  final OverlayPortalController _overlay = OverlayPortalController();

  bool _expanded = false;
  bool _railHover = false;
  bool _panelHover = false;
  double _panelHeight = 0;
  List<_RailEntry> _entries = const [];

  FocusNode _nodeFor(String key) => _nodes.putIfAbsent(key, () {
    final node = FocusNode(debugLabel: 'iptv-rail-$key');
    node.addListener(_syncExpansion);
    return node;
  });

  /// Expansion = any chip focused (TV/DPAD) OR pointer over the rail/panel
  /// (desktop). The panel's own hover keeps it open while the mouse travels
  /// right onto a label row — the panel appears OVER the rail, so the rail's
  /// exit fires the moment the panel's enter does. Inline mode has no
  /// overlay at all; only the row-highlight repaint applies.
  void _syncExpansion() {
    if (widget.inlineExpanded) {
      if (mounted) setState(() {});
      return;
    }
    final expanded =
        _railHover || _panelHover || _nodes.values.any((node) => node.hasFocus);
    if (expanded == _expanded) {
      // Same expansion state, but WHICH chip is focused likely changed — the
      // open panel highlights it, so repaint.
      if (_expanded && mounted) setState(() {});
      return;
    }
    _expanded = expanded;
    if (mounted) setState(() {});
    if (expanded) {
      _overlay.show();
    } else {
      _overlay.hide();
    }
  }

  bool _sweepScheduled = false;

  /// Sweep nodes whose entries no longer exist — a deleted playlist, or the
  /// 'more' chip after the source count drops back under capacity. Validated
  /// against the ACTUAL current entries (capacity depends on layout height,
  /// so didUpdateWidget can't know them); the disposal itself runs post-frame
  /// because build is not a legal place to dispose. If the vanished entry was
  /// focused, focus moves to the first chip instead of dying on the scope.
  void _scheduleStaleNodeSweep() {
    if (_sweepScheduled) return;
    final valid = {for (final e in _entries) e.key};
    if (!_nodes.keys.any((key) => !valid.contains(key))) return;
    _sweepScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sweepScheduled = false;
      if (!mounted) return;
      final validNow = {for (final e in _entries) e.key};
      final stale = [
        for (final key in _nodes.keys)
          if (!validNow.contains(key)) key,
      ];
      var refocus = false;
      for (final key in stale) {
        final node = _nodes.remove(key)!;
        node.removeListener(_syncExpansion);
        if (node.hasFocus) {
          refocus = true;
          node.unfocus();
        }
        node.dispose();
      }
      if (refocus && _entries.isNotEmpty) {
        _nodeFor(_entries.first.key).requestFocus();
      }
    });
  }

  @override
  void dispose() {
    for (final node in _nodes.values) {
      node.removeListener(_syncExpansion);
      node.dispose();
    }
    super.dispose();
  }

  /// Which sources fit, given the rail height. The selected source is always
  /// among them (swapped into the last visible slot when it would be cut).
  List<_RailEntry> _computeEntries(double height) {
    const itemExtent = 48.0;
    const chrome = 12.0 + 8.0 + 48.0; // top pad + bottom pad + manage slot
    final capacity = (((height - chrome) / itemExtent).floor()).clamp(1, 100);

    var sources = widget.playlists;
    var overflow = false;
    if (sources.length > capacity) {
      overflow = true;
      final visible = sources.take(capacity > 1 ? capacity - 1 : 0).toList();
      final selectedIndex = sources.indexWhere(
        (p) => p.id == widget.selectedId,
      );
      if (visible.isNotEmpty && selectedIndex >= visible.length) {
        visible[visible.length - 1] = sources[selectedIndex];
      }
      sources = visible;
    }

    String subtitleFor(IptvPlaylist p) {
      if (p.isFavorites) return 'Starred channels';
      if (p.isContinueWatching) return 'In progress';
      if (p.isStremioAddon) return 'Stremio addon';
      if (p.isXtreamCodes) return 'Xtream login';
      if (p.isLocalFile) return 'Local file';
      return 'M3U playlist';
    }

    return [
      for (final p in sources)
        _RailEntry(
          key: p.id,
          playlist: p,
          label: p.name,
          subtitle: subtitleFor(p),
        ),
      if (overflow)
        const _RailEntry(
          key: 'more',
          icon: Icons.more_horiz_rounded,
          label: 'All sources',
          subtitle: 'Open the full list',
        ),
      const _RailEntry(
        key: 'manage',
        icon: Icons.settings_rounded,
        label: 'Manage sources',
        subtitle: 'Add · edit · remove',
      ),
    ];
  }

  /// Snap the hover overlay closed NOW — the pointer flags are force-cleared
  /// because a click is a completed intent: the panel lingering after a
  /// selection reads as "did that take?" (and a missed exit event would
  /// otherwise leave it stranded open).
  void _collapseOverlay() {
    _railHover = false;
    _panelHover = false;
    if (!_expanded) return;
    _expanded = false;
    if (mounted) setState(() {});
    _overlay.hide();
  }

  void _activate(_RailEntry entry) {
    // Pointer platforms: selection closes the panel. TV keeps it open — there
    // the panel mirrors DPAD focus, which is still on the rail.
    if (!widget.isTelevision && !widget.inlineExpanded) _collapseOverlay();
    switch (entry.key) {
      case 'more':
        widget.onOverflow();
      case 'manage':
        widget.onManage();
      default:
        final playlist = entry.playlist;
        if (playlist != null) widget.onSelect(playlist);
    }
  }

  KeyEventResult _onKey(int index, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (isActivateOrSpaceKey(key)) {
      // Down only — a held OK must not machine-gun selections.
      if (event is KeyDownEvent) _activate(_entries[index]);
      return KeyEventResult.handled;
    }
    // Arrows act on down AND repeat (hold-to-walk the rail), and are always
    // consumed so a hold can't skid past the rail into geometric traversal.
    if (key == LogicalKeyboardKey.arrowUp) {
      if (index > 0) _nodeFor(_entries[index - 1].key).requestFocus();
      return KeyEventResult.handled; // top chip swallows UP — rail edge
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (index < _entries.length - 1) {
        _nodeFor(_entries[index + 1].key).requestFocus();
      }
      return KeyEventResult.handled; // bottom chip swallows DOWN
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      widget.onRight?.call();
      return KeyEventResult.handled;
    }
    // LEFT stays unhandled on purpose: it bubbles to the app-wide edge
    // handler, which opens the TV sidebar (the rail IS the left edge).
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _panelHeight = constraints.maxHeight;
        _entries = _computeEntries(constraints.maxHeight);
        _scheduleStaleNodeSweep();
        if (widget.inlineExpanded) {
          // Mode switch can leave the overlay from the narrow layout behind —
          // it must never coexist with the inline list.
          if (_overlay.isShowing) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && widget.inlineExpanded && _overlay.isShowing) {
                _overlay.hide();
              }
            });
          }
          return _buildInlineRail();
        }
        return CompositedTransformTarget(
          link: _link,
          child: OverlayPortal(
            controller: _overlay,
            overlayChildBuilder: (context) => CompositedTransformFollower(
              link: _link,
              showWhenUnlinked: false,
              targetAnchor: Alignment.topLeft,
              followerAnchor: Alignment.topLeft,
              child: _buildExpandedPanel(),
            ),
            child: _buildCollapsedRail(),
          ),
        );
      },
    );
  }

  /// Wide-desktop mode: the labeled source list lives permanently in the
  /// layout. Nothing pops over anything, nothing needs dismissing — what you
  /// see is what's there.
  Widget _buildInlineRail() {
    String? focusedKey;
    for (final entry in _nodes.entries) {
      if (entry.value.hasFocus) {
        focusedKey = entry.key;
        break;
      }
    }
    return Container(
      width: kIptvSourceRailExpandedWidth,
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < _entries.length; i++) ...[
            if (_entries[i].key == 'manage') const Spacer(),
            _InlineRailRow(
              entry: _entries[i],
              selected:
                  _entries[i].playlist != null &&
                  _entries[i].key == widget.selectedId,
              focused: _entries[i].key == focusedKey,
              focusNode: _nodeFor(_entries[i].key),
              onKeyEvent: (event) => _onKey(i, event),
              onTap: () => _activate(_entries[i]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCollapsedRail() {
    return MouseRegion(
      onEnter: (_) {
        _railHover = true;
        _syncExpansion();
      },
      onExit: (_) {
        _railHover = false;
        _syncExpansion();
      },
      child: Container(
        width: kIptvSourceRailWidth,
        padding: const EdgeInsets.only(top: 12, bottom: 8),
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
          ),
        ),
        child: Column(
          children: [
            for (var i = 0; i < _entries.length; i++) ...[
              if (_entries[i].key == 'manage') const Spacer(),
              _RailChip(
                entry: _entries[i],
                selected:
                    _entries[i].playlist != null &&
                    _entries[i].key == widget.selectedId,
                focusNode: _nodeFor(_entries[i].key),
                onKeyEvent: (event) => _onKey(i, event),
                onTap: () => _activate(_entries[i]),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// The expanded overlay: covers the collapsed rail and continues right with
  /// names. On TV it's display only — focus and keys stay on the chips
  /// underneath, the panel just draws where that focus is. With a pointer the
  /// panel is itself interactive: its hover keeps the rail expanded and its
  /// rows are clickable.
  Widget _buildExpandedPanel() {
    String? focusedKey;
    for (final entry in _nodes.entries) {
      if (entry.value.hasFocus) {
        focusedKey = entry.key;
        break;
      }
    }
    return MouseRegion(
      onEnter: (_) {
        _panelHover = true;
        _syncExpansion();
      },
      onExit: (_) {
        _panelHover = false;
        _syncExpansion();
      },
      child: Container(
        width: 252,
        height: _panelHeight,
        padding: const EdgeInsets.only(top: 12, bottom: 8),
        decoration: BoxDecoration(
          // TV: fully opaque ON PURPOSE — the panel overlays the live preview
          // stage, whose TV underlay engine punches a BlendMode.clear hole to
          // the video SurfaceView behind Flutter; any translucency over that
          // hole breaks the punch-through and ghosts the video (house
          // invariant: nothing layer-based over the hole). Desktop renders
          // the preview in-layer (media_kit Texture), so a translucent glass
          // panel is safe there and keeps the page readable behind it.
          color: widget.isTelevision
              ? const Color(0xFF120F20)
              : const Color(0xD9120F20),
          border: Border(
            right: BorderSide(color: kSeeAllAccent.withValues(alpha: 0.25)),
          ),
          boxShadow: [
            BoxShadow(
              color: widget.isTelevision
                  ? const Color(0x99000000)
                  : const Color(0x40000000),
              blurRadius: widget.isTelevision ? 26 : 16,
              offset: const Offset(10, 0),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final entry in _entries) ...[
              if (entry.key == 'manage') const Spacer(),
              _PanelRow(
                entry: entry,
                selected:
                    entry.playlist != null && entry.key == widget.selectedId,
                focused: entry.key == focusedKey,
                onTap: () => _activate(entry),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One row of the inline (wide-desktop) rail: hover-highlighted, clickable,
/// focusable for keyboard users. Same visual language as the overlay panel's
/// rows — this IS that row, just living in the layout instead of over it.
class _InlineRailRow extends StatefulWidget {
  final _RailEntry entry;
  final bool selected;
  final bool focused;
  final FocusNode focusNode;
  final KeyEventResult Function(KeyEvent) onKeyEvent;
  final VoidCallback onTap;

  const _InlineRailRow({
    required this.entry,
    required this.selected,
    required this.focused,
    required this.focusNode,
    required this.onKeyEvent,
    required this.onTap,
  });

  @override
  State<_InlineRailRow> createState() => _InlineRailRowState();
}

class _InlineRailRowState extends State<_InlineRailRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (node, event) => widget.onKeyEvent(event),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: _PanelRow(
          entry: widget.entry,
          selected: widget.selected,
          focused: widget.focused || _hovered,
          onTap: widget.onTap,
        ),
      ),
    );
  }
}

/// A collapsed rail chip: 48px slot, centered 40px art (monogram / icon).
class _RailChip extends StatefulWidget {
  final _RailEntry entry;
  final bool selected;
  final FocusNode focusNode;
  final KeyEventResult Function(KeyEvent) onKeyEvent;
  final VoidCallback onTap;

  const _RailChip({
    required this.entry,
    required this.selected,
    required this.focusNode,
    required this.onKeyEvent,
    required this.onTap,
  });

  @override
  State<_RailChip> createState() => _RailChipState();
}

class _RailChipState extends State<_RailChip> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (node, event) => widget.onKeyEvent(event),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          height: 48,
          width: kIptvSourceRailWidth,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Selected marker: accent sliver on the rail's outer edge.
              if (widget.selected)
                Positioned(
                  left: 0,
                  top: 12,
                  bottom: 12,
                  child: Container(
                    width: 3,
                    decoration: const BoxDecoration(
                      color: kSeeAllAccent2,
                      borderRadius: BorderRadius.horizontal(
                        right: Radius.circular(3),
                      ),
                    ),
                  ),
                ),
              _SourceGlyph(
                entry: widget.entry,
                selected: widget.selected,
                focused: _focused,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The 40px source mark: gold star (Favorites), progress ring (Continue),
/// puzzle (Stremio), gear/dots (fixed chips), or a brand-tinted monogram of
/// the source's name — so ten IPTV logins still read apart at a glance.
class _SourceGlyph extends StatelessWidget {
  final _RailEntry entry;
  final bool selected;
  final bool focused;

  const _SourceGlyph({
    required this.entry,
    required this.selected,
    required this.focused,
  });

  @override
  Widget build(BuildContext context) {
    final playlist = entry.playlist;
    final Color ring = focused
        ? HomeTheme.focusGold
        : selected
        ? kSeeAllAccent.withValues(alpha: 0.75)
        : Colors.white.withValues(alpha: 0.09);

    IconData? icon = entry.icon;
    Color iconColor = Colors.white.withValues(alpha: 0.62);
    Color plate = const Color(0xFF1B1730);
    String? monogram;

    if (playlist != null) {
      if (playlist.isFavorites) {
        icon = Icons.star_rounded;
        iconColor = HomeTheme.focusGold;
      } else if (playlist.isContinueWatching) {
        icon = Icons.history_rounded;
        iconColor = const Color(0xFF4ADE80);
      } else if (playlist.isStremioAddon) {
        icon = Icons.extension_rounded;
        iconColor = kSeeAllAccent2;
      } else {
        final brand = brandAccentFor(playlist.name);
        plate = Color.alphaBlend(
          brand.withValues(alpha: 0.30),
          const Color(0xFF1B1730),
        );
        monogram = playlist.name.trim().isEmpty
            ? '?'
            : playlist.name.trim()[0].toUpperCase();
      }
    }

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: plate,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ring, width: focused ? 2 : 1.2),
        boxShadow: focused
            ? [
                BoxShadow(
                  color: HomeTheme.focusGold.withValues(alpha: 0.30),
                  blurRadius: 14,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      alignment: Alignment.center,
      child: monogram != null
          ? Text(
              monogram,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            )
          : Icon(icon, size: 19, color: iconColor),
    );
  }
}

/// One row of the expanded overlay: the same glyph plus name and source type.
class _PanelRow extends StatelessWidget {
  final _RailEntry entry;
  final bool selected;
  final bool focused;
  final VoidCallback? onTap;

  const _PanelRow({
    required this.entry,
    required this.selected,
    required this.focused,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 48,
        padding: const EdgeInsets.only(right: 10),
        color: focused
            ? kSeeAllAccent.withValues(alpha: 0.16)
            : Colors.transparent,
        child: Row(
          children: [
            SizedBox(
              width: kIptvSourceRailWidth,
              child: Center(
                child: _SourceGlyph(
                  entry: entry,
                  selected: selected,
                  focused: focused,
                ),
              ),
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: focused ? 1 : 0.85),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    entry.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.42),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_rounded, size: 16, color: kSeeAllAccent2),
          ],
        ),
      ),
    );
  }
}
