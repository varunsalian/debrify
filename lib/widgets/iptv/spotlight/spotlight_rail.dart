import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/iptv_playlist.dart';
import '../../../utils/tv_keys.dart';
import '../styles/iptv_style.dart';

/// Source and library navigation for the Spotlight IPTV style.
///
/// The rail derives virtual groups from [IptvPlaylist] and performs no reads,
/// writes, or navigation itself. Every effect is returned to the owning IPTV
/// result view through callbacks.
class SpotlightRail extends StatelessWidget {
  final List<IptvPlaylist> playlists;
  final IptvPlaylist? selectedPlaylist;
  final Map<String, int> sourceCounts;
  final Map<String, int> customListCounts;
  final int favoritesCount;
  final int? continueWatchingCount;
  final int recordingsCount;
  final bool showRecordings;
  final bool recordingActive;
  final bool recordingsSelected;

  final ValueChanged<IptvPlaylist> onSelectPlaylist;
  final VoidCallback? onOpenRecordings;
  final VoidCallback onNewList;
  final VoidCallback onAddPlaylist;
  final VoidCallback onAddAddon;
  final VoidCallback onManageSources;

  /// Optional node for the first visible item, used by the parent's active
  /// layout navigation adapter when focus enters from the app sidebar.
  final FocusNode? firstItemFocusNode;
  final bool autofocusFirstItem;
  final VoidCallback? onUpFromFirstItem;
  final VoidCallback? onExitRight;
  final ScrollController? scrollController;

  const SpotlightRail({
    super.key,
    required this.playlists,
    required this.selectedPlaylist,
    required this.sourceCounts,
    required this.favoritesCount,
    required this.recordingsCount,
    required this.onSelectPlaylist,
    required this.onNewList,
    required this.onAddPlaylist,
    required this.onAddAddon,
    required this.onManageSources,
    this.customListCounts = const <String, int>{},
    this.continueWatchingCount,
    this.showRecordings = true,
    this.recordingActive = false,
    this.recordingsSelected = false,
    this.onOpenRecordings,
    this.firstItemFocusNode,
    this.autofocusFirstItem = false,
    this.onUpFromFirstItem,
    this.onExitRight,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    final favorites = playlists.where((p) => p.isFavorites).toList();
    final continueWatching = playlists
        .where((p) => p.isContinueWatching)
        .toList();
    final lists = playlists.where((p) => p.isCustomList).toList();
    final sources = playlists.where((p) => !p.isVirtual).toList();
    final addons = playlists.where((p) => p.isStremioAddon).toList();

    final sections = <_RailSection>[
      _RailSection(
        label: 'QUICK ACCESS',
        entries: [
          for (final playlist in favorites)
            _RailEntry.playlist(
              playlist: playlist,
              label: 'Favorites',
              icon: Icons.favorite_rounded,
              count: favoritesCount,
              selected: _selected(playlist),
              onPressed: () => onSelectPlaylist(playlist),
            ),
          for (final playlist in continueWatching)
            _RailEntry.playlist(
              playlist: playlist,
              label: 'Continue Watching',
              icon: Icons.history_rounded,
              count: continueWatchingCount,
              selected: _selected(playlist),
              onPressed: () => onSelectPlaylist(playlist),
            ),
          if (showRecordings && onOpenRecordings != null)
            _RailEntry.action(
              id: 'recordings',
              label: 'Recordings',
              icon: Icons.fiber_manual_record_rounded,
              count: recordingsCount,
              selected: recordingsSelected,
              live: recordingActive,
              onPressed: onOpenRecordings!,
            ),
        ],
      ),
      _RailSection(
        label: 'YOUR LISTS',
        entries: [
          for (final playlist in lists)
            _RailEntry.playlist(
              playlist: playlist,
              label: playlist.name,
              icon: Icons.bookmark_rounded,
              count: customListCounts[playlist.id],
              selected: _selected(playlist),
              onPressed: () => onSelectPlaylist(playlist),
            ),
        ],
      ),
      _RailSection(
        label: 'YOUR PLAYLISTS',
        entries: [
          for (final playlist in sources)
            _RailEntry.playlist(
              playlist: playlist,
              label: playlist.name,
              icon: Icons.live_tv_rounded,
              count: sourceCounts[playlist.id],
              selected: _selected(playlist),
              onPressed: () => onSelectPlaylist(playlist),
            ),
        ],
      ),
      _RailSection(
        label: 'STREMIO ADDONS',
        entries: [
          for (final playlist in addons)
            _RailEntry.playlist(
              playlist: playlist,
              label: playlist.name,
              icon: Icons.extension_rounded,
              count: sourceCounts[playlist.id],
              selected: _selected(playlist),
              onPressed: () => onSelectPlaylist(playlist),
            ),
        ],
      ),
      _RailSection(
        label: 'ACTIONS',
        entries: [
          _RailEntry.action(
            id: 'new-list',
            label: 'New list',
            icon: Icons.playlist_add_rounded,
            onPressed: onNewList,
          ),
          _RailEntry.action(
            id: 'add-playlist',
            label: 'Add playlist',
            icon: Icons.add_to_queue_rounded,
            onPressed: onAddPlaylist,
          ),
          _RailEntry.action(
            id: 'add-addon',
            label: 'Add addon',
            icon: Icons.extension_rounded,
            onPressed: onAddAddon,
          ),
          _RailEntry.action(
            id: 'manage-sources',
            label: 'Manage sources',
            icon: Icons.tune_rounded,
            onPressed: onManageSources,
          ),
        ],
      ),
    ];

    var order = 0;
    final children = <Widget>[];
    for (final section in sections) {
      if (section.entries.isEmpty) continue;
      children.add(_RailHeader(section.label));
      for (final entry in section.entries) {
        children.add(
          FocusTraversalOrder(
            order: NumericFocusOrder(order.toDouble()),
            child: _SpotlightRailTile(
              key: ValueKey<String>('spotlight-rail-${entry.id}'),
              entry: entry,
              focusNode: order == 0 ? firstItemFocusNode : null,
              autofocus: order == 0 && autofocusFirstItem,
              onUp: order == 0 ? onUpFromFirstItem : null,
              onExitRight: onExitRight,
            ),
          ),
        );
        order++;
      }
    }

    final t = IptvStyleTokens.spotlight;
    return DecoratedBox(
      key: const ValueKey<String>('spotlight-rail'),
      decoration: BoxDecoration(
        color: t.panel,
        borderRadius: BorderRadius.circular(18),
      ),
      child: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(8, 5, 8, 12),
          children: children,
        ),
      ),
    );
  }

  bool _selected(IptvPlaylist playlist) => selectedPlaylist?.id == playlist.id;
}

class _RailSection {
  final String label;
  final List<_RailEntry> entries;

  const _RailSection({required this.label, required this.entries});
}

class _RailEntry {
  final String id;
  final String label;
  final IconData icon;
  final int? count;
  final bool selected;
  final bool live;
  final VoidCallback onPressed;

  const _RailEntry._({
    required this.id,
    required this.label,
    required this.icon,
    required this.count,
    required this.selected,
    required this.live,
    required this.onPressed,
  });

  factory _RailEntry.playlist({
    required IptvPlaylist playlist,
    required String label,
    required IconData icon,
    required int? count,
    required bool selected,
    required VoidCallback onPressed,
  }) => _RailEntry._(
    id: 'playlist-${playlist.id}',
    label: label,
    icon: icon,
    count: count,
    selected: selected,
    live: false,
    onPressed: onPressed,
  );

  factory _RailEntry.action({
    required String id,
    required String label,
    required IconData icon,
    int? count,
    bool selected = false,
    bool live = false,
    required VoidCallback onPressed,
  }) => _RailEntry._(
    id: id,
    label: label,
    icon: icon,
    count: count,
    selected: selected,
    live: live,
    onPressed: onPressed,
  );
}

class _RailHeader extends StatelessWidget {
  final String label;

  const _RailHeader(this.label);

  @override
  Widget build(BuildContext context) {
    final t = IptvStyleTokens.spotlight;
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(11, 14, 10, 5),
        child: Text(
          label,
          style: TextStyle(
            color: t.fgFaint,
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.35,
          ),
        ),
      ),
    );
  }
}

class _SpotlightRailTile extends StatefulWidget {
  final _RailEntry entry;
  final FocusNode? focusNode;
  final bool autofocus;
  final VoidCallback? onUp;
  final VoidCallback? onExitRight;

  const _SpotlightRailTile({
    super.key,
    required this.entry,
    required this.focusNode,
    required this.autofocus,
    required this.onUp,
    required this.onExitRight,
  });

  @override
  State<_SpotlightRailTile> createState() => _SpotlightRailTileState();
}

class _SpotlightRailTileState extends State<_SpotlightRailTile> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = IptvStyleTokens.spotlight;
    final inverse = _focused;
    final ink = inverse ? t.focusInk! : t.fg;
    final countText = widget.entry.count == null
        ? null
        : _formatCount(widget.entry.count!);
    final semanticsValue = [
      if (widget.entry.selected) 'Selected',
      if (countText != null) '$countText items',
      if (widget.entry.live) 'Recording now',
    ].join(', ');

    return Semantics(
      button: true,
      selected: widget.entry.selected,
      excludeSemantics: true,
      label: widget.entry.label,
      value: semanticsValue.isEmpty ? null : semanticsValue,
      onTap: widget.entry.onPressed,
      child: Focus(
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        onFocusChange: (focused) {
          if (_focused != focused) setState(() => _focused = focused);
          if (focused) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) {
                Scrollable.ensureVisible(
                  context,
                  alignmentPolicy:
                      ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
                  duration: const Duration(milliseconds: 120),
                );
              }
            });
          }
        },
        onKeyEvent: (_, event) {
          if (isActivateOrSpaceKey(event.logicalKey)) {
            if (event is KeyDownEvent) widget.entry.onPressed();
            return KeyEventResult.handled;
          }
          if ((event is KeyDownEvent || event is KeyRepeatEvent) &&
              event.logicalKey == LogicalKeyboardKey.arrowUp &&
              widget.onUp != null) {
            widget.onUp!();
            return KeyEventResult.handled;
          }
          if ((event is KeyDownEvent || event is KeyRepeatEvent) &&
              event.logicalKey == LogicalKeyboardKey.arrowRight &&
              widget.onExitRight != null) {
            widget.onExitRight!();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            onTap: widget.entry.onPressed,
            child: AnimatedContainer(
              key: ValueKey<String>('spotlight-rail-tile-${widget.entry.id}'),
              duration: const Duration(milliseconds: 120),
              height: 40,
              margin: const EdgeInsets.symmetric(vertical: 1),
              padding: const EdgeInsets.symmetric(horizontal: 11),
              decoration: BoxDecoration(
                color: inverse
                    ? t.focusFill
                    : widget.entry.selected
                    ? t.selectedTint
                    : _hovered
                    ? t.focusTint
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                  color: inverse
                      ? t.focusFill!
                      : widget.entry.selected
                      ? t.accent.withValues(alpha: 0.5)
                      : Colors.transparent,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    widget.entry.icon,
                    size: 16,
                    color: inverse
                        ? t.focusInk
                        : widget.entry.live
                        ? t.rec
                        : widget.entry.selected
                        ? t.accent
                        : t.fgDim,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      widget.entry.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: ink,
                        fontSize: 12.25,
                        fontWeight: widget.entry.selected
                            ? FontWeight.w700
                            : FontWeight.w600,
                      ),
                    ),
                  ),
                  if (widget.entry.live)
                    Container(
                      width: 7,
                      height: 7,
                      margin: const EdgeInsets.only(left: 6),
                      decoration: BoxDecoration(
                        color: inverse ? t.focusInk : t.rec,
                        shape: BoxShape.circle,
                      ),
                    )
                  else if (countText != null)
                    Text(
                      countText,
                      style: TextStyle(
                        color: inverse ? t.focusInk : t.fgFaint,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
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

String _formatCount(int value) {
  if (value < 1000) return '$value';
  if (value < 1000000) {
    final thousands = value / 1000;
    return '${thousands.toStringAsFixed(thousands >= 10 ? 0 : 1)}K';
  }
  final millions = value / 1000000;
  return '${millions.toStringAsFixed(millions >= 10 ? 0 : 1)}M';
}
