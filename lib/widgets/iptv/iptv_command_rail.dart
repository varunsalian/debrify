import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/iptv_playlist.dart';
import '../../services/iptv_media_store.dart' show IptvListMeta;
import '../../utils/tv_keys.dart';
import 'iptv_stage_panel.dart' show IptvMonogram;

/// The Command Center's left rail: every destination on one column —
/// LIBRARY (Favorites · Continue · Scheduled), SOURCES (playlists with
/// counts), LISTS (the user's own), and a Manage footer.
///
/// DPAD contract: items are plain focusables, so geometry does the work —
/// LEFT from the channel grid's first column lands here, LEFT from here has
/// no candidate and bubbles to the shell's global action (the app sidebar,
/// preserving the LEFT-only policy with zero interception code). UP/DOWN
/// walk the column; OK/RIGHT select.
///
/// Perf: a static column — no per-frame work, counts are precomputed by the
/// caller once per playlist load, and selection state is a plain rebuild.
class IptvCommandRail extends StatelessWidget {
  final List<IptvPlaylist> playlists;
  final IptvPlaylist? selectedPlaylist;
  final List<IptvListMeta> customLists;

  /// playlist.id → channel count (real sources only), precomputed.
  final Map<String, int> sourceCounts;
  final int favoritesCount;
  final int scheduledCount;

  /// False hides the Scheduled entry entirely — recording disabled or
  /// unsupported must not advertise a scheduler that would refuse to work
  /// (settings hides its scheduled row in the same state).
  final bool showScheduled;

  /// True while the recording engine is capturing — the Scheduled entry
  /// wears a live dot. (Optional; false hides it.)
  final bool recordingActive;

  final ValueChanged<IptvPlaylist> onSelectPlaylist;
  final VoidCallback onOpenScheduled;
  final VoidCallback onManageSources;

  const IptvCommandRail({
    super.key,
    required this.playlists,
    required this.selectedPlaylist,
    required this.customLists,
    required this.sourceCounts,
    required this.favoritesCount,
    required this.scheduledCount,
    required this.onSelectPlaylist,
    required this.onOpenScheduled,
    required this.onManageSources,
    this.showScheduled = true,
    this.recordingActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final favorites = playlists.where((p) => p.isFavorites).toList();
    final continueWatching =
        playlists.where((p) => p.isContinueWatching).toList();
    final sources = playlists.where((p) => !p.isVirtual).toList();
    final addonSources = playlists.where((p) => p.isStremioAddon).toList();
    final listPlaylists = playlists.where((p) => p.isCustomList).toList();

    return Container(
      width: 196,
      decoration: BoxDecoration(
        color: const Color(0xFF080B18).withValues(alpha: 0.65),
        border: Border(
          right: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
        ),
      ),
      child: FocusTraversalGroup(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(8, 14, 8, 10),
          children: [
            const _RailHeader('LIBRARY'),
            for (final p in favorites)
              _RailItem(
                icon: Icons.star_rounded,
                iconColor: const Color(0xFFF5C042),
                label: 'Favorites',
                count: favoritesCount,
                selected: selectedPlaylist?.id == p.id,
                // Top focus edge of the rail: UP stays here instead of
                // leaking into whichever pane sits upper-right.
                swallowUp: true,
                onSelect: () => onSelectPlaylist(p),
              ),
            for (final p in continueWatching)
              _RailItem(
                icon: Icons.history_rounded,
                label: 'Continue',
                selected: selectedPlaylist?.id == p.id,
                onSelect: () => onSelectPlaylist(p),
              ),
            if (showScheduled)
              _RailItem(
                icon: Icons.fiber_manual_record_rounded,
                iconColor: const Color(0xFFF43F5E),
                label: 'Scheduled',
                count: scheduledCount,
                selected: false,
                chevron: true,
                liveDot: recordingActive,
                onSelect: onOpenScheduled,
              ),
            const _RailHeader('SOURCES'),
            for (final p in sources)
              _RailItem(
                mark: IptvMonogram(name: p.name, size: 24),
                label: p.name,
                count: sourceCounts[p.id],
                selected: selectedPlaylist?.id == p.id,
                onSelect: () => onSelectPlaylist(p),
              ),
            if (addonSources.isNotEmpty) ...[
              const _RailHeader('ADDONS'),
              for (final p in addonSources)
                _RailItem(
                  icon: Icons.extension_rounded,
                  label: p.name,
                  selected: selectedPlaylist?.id == p.id,
                  onSelect: () => onSelectPlaylist(p),
                ),
            ],
            if (listPlaylists.isNotEmpty) ...[
              const _RailHeader('LISTS'),
              for (final p in listPlaylists)
                _RailItem(
                  icon: Icons.bookmark_rounded,
                  label: p.name,
                  count: _listCount(p),
                  selected: selectedPlaylist?.id == p.id,
                  onSelect: () => onSelectPlaylist(p),
                ),
            ],
            const SizedBox(height: 10),
            _RailItem(
              icon: Icons.tune_rounded,
              label: 'Manage sources',
              selected: false,
              chevron: true,
              // Bottom focus edge — DOWN stops here.
              swallowDown: true,
              onSelect: onManageSources,
            ),
          ],
        ),
      ),
    );
  }

  int? _listCount(IptvPlaylist listPlaylist) {
    for (final meta in customLists) {
      if (listPlaylist.id == 'iptv-list-${meta.id}') return meta.channelCount;
    }
    return null;
  }
}

class _RailHeader extends StatelessWidget {
  final String text;
  const _RailHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 5),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.32),
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}

class _RailItem extends StatefulWidget {
  final IconData? icon;
  final Color? iconColor;
  final Widget? mark;
  final String label;
  final int? count;
  final bool selected;
  final bool chevron;
  final bool liveDot;
  final bool swallowUp;
  final bool swallowDown;
  final VoidCallback onSelect;

  const _RailItem({
    this.icon,
    this.iconColor,
    this.mark,
    required this.label,
    this.count,
    required this.selected,
    this.chevron = false,
    this.liveDot = false,
    this.swallowUp = false,
    this.swallowDown = false,
    required this.onSelect,
  });

  @override
  State<_RailItem> createState() => _RailItemState();
}

class _RailItemState extends State<_RailItem> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFF5C042);
    final row = Container(
      height: 36,
      margin: const EdgeInsets.symmetric(vertical: 1),
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        color: widget.selected
            ? const Color(0xFF8A5CFF).withValues(alpha: 0.16)
            : _focused
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.transparent,
        border: Border.all(
          color: _focused ? gold : Colors.transparent,
          width: 1.8,
        ),
      ),
      child: Row(
        children: [
          if (widget.mark != null)
            widget.mark!
          else
            Icon(
              widget.icon,
              size: 16,
              color: widget.iconColor ??
                  Colors.white.withValues(alpha: widget.selected ? 0.9 : 0.55),
            ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: widget.selected
                    ? const Color(0xFFE4DCFF)
                    : Colors.white.withValues(alpha: 0.72),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (widget.liveDot)
            Container(
              width: 7,
              height: 7,
              margin: const EdgeInsets.only(left: 5),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFF43F5E),
              ),
            )
          else if (widget.count != null)
            Text(
              _fmtCount(widget.count!),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.34),
                fontSize: 10,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            )
          else if (widget.chevron)
            Icon(
              Icons.chevron_right_rounded,
              size: 15,
              color: Colors.white.withValues(alpha: 0.3),
            ),
        ],
      ),
    );

    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (node, event) {
        // RIGHT selects too (the documented contract): without this,
        // traversal walks into the guide while it still shows the PREVIOUS
        // source — a silently wrong screen.
        if (event is KeyDownEvent &&
            (isActivateOrSpaceKey(event.logicalKey) ||
                event.logicalKey == LogicalKeyboardKey.arrowRight)) {
          widget.onSelect();
          return KeyEventResult.handled;
        }
        // Swallow RIGHT repeats so holding the key can't multi-trigger.
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          return KeyEventResult.handled;
        }
        // Vertical containment at the rail's edges — never leak into the
        // panes to the right.
        if (widget.swallowUp &&
            event.logicalKey == LogicalKeyboardKey.arrowUp) {
          return KeyEventResult.handled;
        }
        if (widget.swallowDown &&
            event.logicalKey == LogicalKeyboardKey.arrowDown) {
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onSelect,
        behavior: HitTestBehavior.opaque,
        child: row,
      ),
    );
  }

  String _fmtCount(int n) {
    if (n >= 10000) return '${(n / 1000).round()}k';
    if (n >= 1000) {
      final k = n / 1000;
      return '${k.toStringAsFixed(k >= 9.95 ? 0 : 1)}k';
    }
    return '$n';
  }
}
