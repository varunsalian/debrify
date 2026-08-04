import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/iptv_playlist.dart';
import '../../utils/tv_keys.dart';
import '../see_all/see_all_theme.dart';

/// Opens the playlist picker bottom sheet (the same sheet the classic filter
/// bar's dropdown shows) and returns the chosen playlist, or null on dismiss.
/// Public so the TV source rail's overflow chip can reuse it.
Future<IptvPlaylist?> showIptvPlaylistPicker(
  BuildContext context, {
  required List<IptvPlaylist> playlists,
  IptvPlaylist? selectedPlaylist,
  VoidCallback? onAddPlaylist,
}) {
  return showModalBottomSheet<IptvPlaylist?>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _PlaylistPickerSheet(
      playlists: playlists,
      selectedPlaylist: selectedPlaylist,
      onAddPlaylist: onAddPlaylist,
    ),
  );
}

/// IPTV filter bar with playlist and category dropdowns
class IptvFiltersBar extends StatelessWidget {
  final List<IptvPlaylist> playlists;
  final IptvPlaylist? selectedPlaylist;
  final List<String> categories;
  final String? selectedCategory;

  /// Channel count per category (redesign) — shown in the category picker so
  /// "Sports" reads as "Sports (120)". Null keeps the classic labels.
  final Map<String, int>? categoryCounts;
  final int channelCount;
  final bool isLoading;

  /// Channels are streaming in (progressive Stremio load): the count is real
  /// but not final, so it renders with a spinner instead of as a settled
  /// total.
  final bool isLoadingMore;
  final ValueChanged<IptvPlaylist?> onPlaylistChanged;
  final ValueChanged<String?> onCategoryChanged;
  final VoidCallback? onAddPlaylist;
  final FocusNode? playlistFocusNode;
  final FocusNode? categoryFocusNode;
  // Content type filter (for Xtream Codes)
  final bool showContentTypeFilter;
  final String selectedContentType;
  final ValueChanged<String>? onContentTypeChanged;
  final FocusNode? contentTypeFocusNode;
  // DPAD navigation callbacks
  final VoidCallback? onUpArrowPressed;
  final VoidCallback? onDownArrowPressed;

  /// Non-null shows the Recordings entry (record-dot icon) at the bar's end —
  /// the classic layout's only front door to the Recordings hub (the rail
  /// that carries it on TV/desktop doesn't exist here). [recordingLive]
  /// paints it red while any capture runs, so the page shows recording state
  /// at a glance.
  final VoidCallback? onOpenRecordings;
  final bool recordingLive;

  /// Non-null lets a category be hidden by long-pressing (or holding OK on)
  /// it in the picker. Null on sources that have no stored catalog to hide
  /// against, which is also what keeps the hint off those pickers.
  final ValueChanged<String>? onHideCategory;

  const IptvFiltersBar({
    super.key,
    required this.playlists,
    required this.selectedPlaylist,
    required this.categories,
    required this.selectedCategory,
    this.categoryCounts,
    required this.channelCount,
    required this.isLoading,
    this.isLoadingMore = false,
    required this.onPlaylistChanged,
    required this.onCategoryChanged,
    this.onAddPlaylist,
    this.playlistFocusNode,
    this.categoryFocusNode,
    this.showContentTypeFilter = false,
    this.selectedContentType = 'live',
    this.onContentTypeChanged,
    this.contentTypeFocusNode,
    this.onUpArrowPressed,
    this.onDownArrowPressed,
    this.onOpenRecordings,
    this.recordingLive = false,
    this.onHideCategory,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bool hasCategories = categories.isNotEmpty && selectedPlaylist != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Hide channel count on small screens (< 400px)
          final showChannelCount = constraints.maxWidth >= 400;

          // Determine DPAD right-arrow targets from playlist dropdown
          VoidCallback? playlistRightArrow;
          if (showContentTypeFilter) {
            playlistRightArrow = () => contentTypeFocusNode?.requestFocus();
          } else if (hasCategories) {
            playlistRightArrow = () => categoryFocusNode?.requestFocus();
          }

          // Determine DPAD left-arrow target from category dropdown
          VoidCallback? categoryLeftArrow;
          if (showContentTypeFilter) {
            categoryLeftArrow = () => contentTypeFocusNode?.requestFocus();
          } else {
            categoryLeftArrow = () => playlistFocusNode?.requestFocus();
          }

          return Row(
            children: [
              // Playlist dropdown - flexible to shrink on small screens
              Flexible(
                child: _PlaylistDropdown(
                  playlists: playlists,
                  selectedPlaylist: selectedPlaylist,
                  onChanged: onPlaylistChanged,
                  onAddPlaylist: onAddPlaylist,
                  focusNode: playlistFocusNode,
                  onUpArrowPressed: onUpArrowPressed,
                  onDownArrowPressed: onDownArrowPressed,
                  onRightArrowPressed: playlistRightArrow,
                ),
              ),

              // Content type toggle (only for Xtream Codes playlists)
              if (showContentTypeFilter) ...[
                const SizedBox(width: 8),
                _ContentTypeToggle(
                  selectedContentType: selectedContentType,
                  onChanged: onContentTypeChanged ?? (_) {},
                  focusNode: contentTypeFocusNode,
                  onUpArrowPressed: onUpArrowPressed,
                  onDownArrowPressed: onDownArrowPressed,
                  onLeftArrowPressed: () => playlistFocusNode?.requestFocus(),
                  onRightArrowPressed: hasCategories
                      ? () => categoryFocusNode?.requestFocus()
                      : null,
                ),
              ],
              const SizedBox(width: 8),

              // Category dropdown (only if we have categories)
              if (hasCategories)
                Flexible(
                  child: _CategoryDropdown(
                    categories: categories,
                    categoryCounts: categoryCounts,
                    selectedCategory: selectedCategory,
                    onChanged: onCategoryChanged,
                    focusNode: categoryFocusNode,
                    onUpArrowPressed: onUpArrowPressed,
                    onDownArrowPressed: onDownArrowPressed,
                    onLeftArrowPressed: categoryLeftArrow,
                    onRightArrowPressed: null,
                    onHideCategory: onHideCategory,
                  ),
                ),

              // Channel count or loading indicator (hidden on small screens)
              if (showChannelCount) ...[
                const Spacer(),
                if (isLoading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (selectedPlaylist != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isLoadingMore) ...[
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        '$channelCount channel${channelCount != 1 ? 's' : ''}'
                        '${isLoadingMore ? '…' : ''}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
              ],
              if (onOpenRecordings != null) ...[
                if (!showChannelCount) const Spacer(),
                const SizedBox(width: 4),
                _RecordingsButton(
                  live: recordingLive,
                  onPressed: onOpenRecordings!,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// The bar's Recordings entry: a record-dot that reads dim when idle and
/// red (with a soft glow) while any capture runs. Static styling only.
class _RecordingsButton extends StatelessWidget {
  final bool live;
  final VoidCallback onPressed;
  const _RecordingsButton({required this.live, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    const rec = Color(0xFFF43F5E);
    return IconButton(
      tooltip: live ? 'Recording now — open Recordings' : 'Recordings',
      visualDensity: VisualDensity.compact,
      onPressed: onPressed,
      icon: Container(
        decoration: live
            ? BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: rec.withValues(alpha: 0.45),
                    blurRadius: 9,
                    spreadRadius: 1,
                  ),
                ],
              )
            : null,
        child: Icon(
          Icons.fiber_manual_record_rounded,
          size: 20,
          color: live
              ? rec
              : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Playlist selection dropdown
class _PlaylistDropdown extends StatefulWidget {
  final List<IptvPlaylist> playlists;
  final IptvPlaylist? selectedPlaylist;
  final ValueChanged<IptvPlaylist?> onChanged;
  final VoidCallback? onAddPlaylist;
  final FocusNode? focusNode;
  final VoidCallback? onUpArrowPressed;
  final VoidCallback? onDownArrowPressed;
  final VoidCallback? onRightArrowPressed;

  const _PlaylistDropdown({
    required this.playlists,
    required this.selectedPlaylist,
    required this.onChanged,
    this.onAddPlaylist,
    this.focusNode,
    this.onUpArrowPressed,
    this.onDownArrowPressed,
    this.onRightArrowPressed,
  });

  @override
  State<_PlaylistDropdown> createState() => _PlaylistDropdownState();
}

class _PlaylistDropdownState extends State<_PlaylistDropdown> {
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode?.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    widget.focusNode?.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    setState(() => _isFocused = widget.focusNode?.hasFocus ?? false);
  }

  Future<void> _showPlaylistPicker() async {
    final result = await showModalBottomSheet<IptvPlaylist?>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _PlaylistPickerSheet(
        playlists: widget.playlists,
        selectedPlaylist: widget.selectedPlaylist,
        onAddPlaylist: widget.onAddPlaylist,
      ),
    );

    // Call onChanged if a playlist was selected (not cancelled)
    if (result != null) {
      widget.onChanged(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;

        if (isActivateKey(event.logicalKey)) {
          _showPlaylistPicker();
          return KeyEventResult.handled;
        }

        if (event.logicalKey == LogicalKeyboardKey.arrowUp && widget.onUpArrowPressed != null) {
          widget.onUpArrowPressed!();
          return KeyEventResult.handled;
        }

        if (event.logicalKey == LogicalKeyboardKey.arrowDown && widget.onDownArrowPressed != null) {
          widget.onDownArrowPressed!();
          return KeyEventResult.handled;
        }

        if (event.logicalKey == LogicalKeyboardKey.arrowRight && widget.onRightArrowPressed != null) {
          widget.onRightArrowPressed!();
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: _showPlaylistPicker,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          // House glass chip (kSeeAll board language). Constant border width —
          // a 1→2px focus ring resizes the chip and reflows the whole bar.
          decoration: BoxDecoration(
            color: kSeeAllPanel,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              width: 2,
              color: _isFocused ? kSeeAllAccent : kSeeAllLine,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.selectedPlaylist?.isFavorites == true
                    ? Icons.star_rounded
                    : widget.selectedPlaylist?.isCustomList == true
                        ? Icons.bookmark_rounded
                    : widget.selectedPlaylist?.isXtreamCodes == true
                        ? Icons.login
                        : widget.selectedPlaylist?.isLocalFile == true
                            ? Icons.folder
                            : Icons.playlist_play,
                size: 16,
                color: kSeeAllAccent2,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  widget.selectedPlaylist?.name ?? 'Select Playlist',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.arrow_drop_down,
                size: 20,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Category selection dropdown
class _CategoryDropdown extends StatefulWidget {
  final List<String> categories;
  final Map<String, int>? categoryCounts;
  final String? selectedCategory;
  final ValueChanged<String?> onChanged;
  final FocusNode? focusNode;
  final VoidCallback? onUpArrowPressed;
  final VoidCallback? onDownArrowPressed;
  final VoidCallback? onLeftArrowPressed;
  final VoidCallback? onRightArrowPressed;
  final ValueChanged<String>? onHideCategory;

  const _CategoryDropdown({
    required this.categories,
    this.categoryCounts,
    required this.selectedCategory,
    required this.onChanged,
    this.focusNode,
    this.onUpArrowPressed,
    this.onDownArrowPressed,
    this.onLeftArrowPressed,
    this.onRightArrowPressed,
    this.onHideCategory,
  });

  @override
  State<_CategoryDropdown> createState() => _CategoryDropdownState();
}

class _CategoryDropdownState extends State<_CategoryDropdown> {
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode?.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    widget.focusNode?.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    setState(() => _isFocused = widget.focusNode?.hasFocus ?? false);
  }

  Future<void> _showCategoryPicker() async {
    final result = await showModalBottomSheet<_CategoryChoice>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _CategoryPickerSheet(
        categories: widget.categories,
        categoryCounts: widget.categoryCounts,
        selectedCategory: widget.selectedCategory,
        canHide: widget.onHideCategory != null,
      ),
    );

    if (result == null) return;
    // The sheet is closed before the hide runs, so its confirmation opens
    // over the page rather than over a list that is about to change.
    if (result.hide) {
      widget.onHideCategory?.call(result.category);
      return;
    }
    widget.onChanged(result.category.isEmpty ? null : result.category);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;

        if (isActivateKey(event.logicalKey)) {
          _showCategoryPicker();
          return KeyEventResult.handled;
        }

        if (event.logicalKey == LogicalKeyboardKey.arrowUp && widget.onUpArrowPressed != null) {
          widget.onUpArrowPressed!();
          return KeyEventResult.handled;
        }

        if (event.logicalKey == LogicalKeyboardKey.arrowDown && widget.onDownArrowPressed != null) {
          widget.onDownArrowPressed!();
          return KeyEventResult.handled;
        }

        if (event.logicalKey == LogicalKeyboardKey.arrowLeft && widget.onLeftArrowPressed != null) {
          widget.onLeftArrowPressed!();
          return KeyEventResult.handled;
        }

        if (event.logicalKey == LogicalKeyboardKey.arrowRight && widget.onRightArrowPressed != null) {
          widget.onRightArrowPressed!();
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: _showCategoryPicker,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: kSeeAllPanel,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              width: 2,
              color: _isFocused ? kSeeAllAccent : kSeeAllLine,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.folder_outlined,
                size: 16,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  widget.selectedCategory ?? 'All Categories',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.arrow_drop_down,
                size: 20,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Content type toggle (Live TV / Movies / Series) for Xtream Codes playlists
class _ContentTypeToggle extends StatefulWidget {
  final String selectedContentType;
  final ValueChanged<String> onChanged;
  final FocusNode? focusNode;
  final VoidCallback? onUpArrowPressed;
  final VoidCallback? onDownArrowPressed;
  final VoidCallback? onLeftArrowPressed;
  final VoidCallback? onRightArrowPressed;

  const _ContentTypeToggle({
    required this.selectedContentType,
    required this.onChanged,
    this.focusNode,
    this.onUpArrowPressed,
    this.onDownArrowPressed,
    this.onLeftArrowPressed,
    this.onRightArrowPressed,
  });

  @override
  State<_ContentTypeToggle> createState() => _ContentTypeToggleState();
}

class _ContentTypeToggleState extends State<_ContentTypeToggle> {
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode?.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    widget.focusNode?.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    setState(() => _isFocused = widget.focusNode?.hasFocus ?? false);
  }

  /// Advance to the next content type in order. Keeps the control a single
  /// focus target on TV (OK cycles Live → Movies → Series), and each segment
  /// is still directly tappable on touch.
  void _toggle() {
    const order = ['live', 'vod', 'series'];
    final i = order.indexOf(widget.selectedContentType);
    widget.onChanged(order[(i + 1) % order.length]);
  }

  Widget _segment(
    ThemeData theme,
    ColorScheme colorScheme, {
    required String value,
    required IconData icon,
    required String label,
  }) {
    final selected = widget.selectedContentType == value;
    return GestureDetector(
      onTap: () => widget.onChanged(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? kSeeAllAccent : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: selected ? Colors.white : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: selected ? Colors.white : colorScheme.onSurfaceVariant,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;

        if (isActivateKey(event.logicalKey)) {
          _toggle();
          return KeyEventResult.handled;
        }

        if (event.logicalKey == LogicalKeyboardKey.arrowUp && widget.onUpArrowPressed != null) {
          widget.onUpArrowPressed!();
          return KeyEventResult.handled;
        }

        if (event.logicalKey == LogicalKeyboardKey.arrowDown && widget.onDownArrowPressed != null) {
          widget.onDownArrowPressed!();
          return KeyEventResult.handled;
        }

        if (event.logicalKey == LogicalKeyboardKey.arrowLeft && widget.onLeftArrowPressed != null) {
          widget.onLeftArrowPressed!();
          return KeyEventResult.handled;
        }

        if (event.logicalKey == LogicalKeyboardKey.arrowRight && widget.onRightArrowPressed != null) {
          widget.onRightArrowPressed!();
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      },
      // Control-wide tap cycles (edge/padding hits included — the segments'
      // own detectors win where they overlap), so no part of the pill is a
      // dead zone on touch.
      child: GestureDetector(
        onTap: _toggle,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          decoration: BoxDecoration(
            color: kSeeAllPanel,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              width: 2,
              color: _isFocused ? kSeeAllAccent : kSeeAllLine,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _segment(theme, colorScheme,
                  value: 'live', icon: Icons.live_tv, label: 'Live'),
              _segment(theme, colorScheme,
                  value: 'vod', icon: Icons.movie, label: 'Movies'),
              _segment(theme, colorScheme,
                  value: 'series', icon: Icons.video_library, label: 'Series'),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet for selecting playlist with DPAD support
class _PlaylistPickerSheet extends StatefulWidget {
  final List<IptvPlaylist> playlists;
  final IptvPlaylist? selectedPlaylist;
  final VoidCallback? onAddPlaylist;

  const _PlaylistPickerSheet({
    required this.playlists,
    required this.selectedPlaylist,
    this.onAddPlaylist,
  });

  @override
  State<_PlaylistPickerSheet> createState() => _PlaylistPickerSheetState();
}

class _PlaylistPickerSheetState extends State<_PlaylistPickerSheet> {
  final List<FocusNode> _focusNodes = [];

  @override
  void initState() {
    super.initState();
    _initFocusNodes();
  }

  void _initFocusNodes() {
    // One for each playlist + one for "Add Playlist" button if present
    final count = widget.playlists.length + (widget.onAddPlaylist != null ? 1 : 0);
    for (int i = 0; i < count; i++) {
      _focusNodes.add(FocusNode(debugLabel: 'iptv-playlist-$i'));
    }
    // Auto-focus first item after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _focusNodes.isNotEmpty) {
        _focusNodes[0].requestFocus();
      }
    });
  }

  @override
  void dispose() {
    for (final node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event, int index, VoidCallback onSelect) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (isActivateKey(event.logicalKey)) {
      onSelect();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.goBack ||
        event.logicalKey == LogicalKeyboardKey.browserBack) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowUp && index > 0) {
      _focusNodes[index - 1].requestFocus();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowDown && index < _focusNodes.length - 1) {
      _focusNodes[index + 1].requestFocus();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: FocusScope(
        autofocus: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Select Playlist',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Playlists
            if (widget.playlists.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(
                      Icons.playlist_add,
                      size: 48,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No playlists added yet',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              )
            else
              ...widget.playlists.asMap().entries.map((entry) {
                final index = entry.key;
                final playlist = entry.value;
                final isSelected = playlist == widget.selectedPlaylist;

                return _FocusablePickerTile(
                  focusNode: index < _focusNodes.length ? _focusNodes[index] : null,
                  label: playlist.name,
                  subtitle: playlist.isFavorites
                      ? 'Your starred channels'
                      : playlist.isCustomList
                          ? 'Your list'
                          : playlist.isXtreamCodes
                          ? 'Xtream Codes - ${playlist.serverUrl}'
                          : playlist.isLocalFile ? 'Local file' : playlist.url,
                  icon: isSelected
                      ? Icons.check_circle
                      : playlist.isFavorites
                          ? Icons.star_rounded
                          : playlist.isCustomList
                              ? Icons.bookmark_rounded
                          : playlist.isXtreamCodes
                              ? Icons.login
                              : (playlist.isLocalFile ? Icons.folder : Icons.playlist_play),
                  isSelected: isSelected,
                  onTap: () => Navigator.of(context).pop(playlist),
                  onKeyEvent: (node, event) => _handleKeyEvent(
                    node, event, index, () => Navigator.of(context).pop(playlist),
                  ),
                );
              }),

            // Add playlist button
            if (widget.onAddPlaylist != null) ...[
              const Divider(),
              _FocusablePickerTile(
                focusNode: _focusNodes.isNotEmpty ? _focusNodes.last : null,
                label: 'Add Playlist',
                icon: Icons.add,
                isSelected: false,
                onTap: () {
                  Navigator.of(context).pop();
                  widget.onAddPlaylist!();
                },
                onKeyEvent: (node, event) => _handleKeyEvent(
                  node, event, _focusNodes.length - 1, () {
                    Navigator.of(context).pop();
                    widget.onAddPlaylist!();
                  },
                ),
              ),
            ],

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

/// What the category sheet closed with: a category to select, or one to hide.
class _CategoryChoice {
  const _CategoryChoice(this.category, {this.hide = false});

  /// Empty means "All categories" (never valid with [hide]).
  final String category;
  final bool hide;
}

/// Bottom sheet for selecting category with DPAD support
class _CategoryPickerSheet extends StatefulWidget {
  final List<String> categories;
  final Map<String, int>? categoryCounts;
  final String? selectedCategory;

  /// Whether long-press / hold-OK on a category offers to hide it. False on
  /// sources with no stored catalog to hide against.
  final bool canHide;

  const _CategoryPickerSheet({
    required this.categories,
    this.categoryCounts,
    required this.selectedCategory,
    this.canHide = false,
  });

  @override
  State<_CategoryPickerSheet> createState() => _CategoryPickerSheetState();
}

class _CategoryPickerSheetState extends State<_CategoryPickerSheet> {
  /// Lazily created, keyed by option index (0 = "All Categories") — a big
  /// playlist has hundreds of categories, and pre-creating a FocusNode (and
  /// tile) for every one froze the sheet open. Nodes exist only for tiles the
  /// lazy list has actually built; DPAD only ever asks for a neighbor of a
  /// built tile, which the list's cache extent has already built too.
  final Map<int, FocusNode> _focusNodes = {};

  int get _optionCount => widget.categories.length + 1;

  FocusNode _nodeFor(int index) => _focusNodes.putIfAbsent(
        index,
        () => FocusNode(debugLabel: 'iptv-category-$index'),
      );

  @override
  void initState() {
    super.initState();
    // Auto-focus first item after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _nodeFor(0).requestFocus();
    });
  }

  @override
  void dispose() {
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event, int index, VoidCallback onSelect) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (isActivateKey(event.logicalKey)) {
      onSelect();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.goBack ||
        event.logicalKey == LogicalKeyboardKey.browserBack) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowUp && index > 0) {
      _nodeFor(index - 1).requestFocus();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowDown && index < _optionCount - 1) {
      _nodeFor(index + 1).requestFocus();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.6,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: FocusScope(
        autofocus: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Select Category',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  // Once, in the header — a per-row caption would repeat
                  // itself down a list that can run to hundreds of entries.
                  if (widget.canHide)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        'Long-press (or hold OK on) a category to hide it',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Options — built lazily; index 0 is "All Categories". shrinkWrap
            // only for short lists (it forces building every child): big lists
            // trade a full-height sheet for an instant open.
            Flexible(
              child: ListView.builder(
                shrinkWrap: widget.categories.length <= 40,
                itemCount: _optionCount,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    void pickAll() => Navigator.of(
                      context,
                    ).pop(const _CategoryChoice(''));
                    return _FocusablePickerTile(
                      focusNode: _nodeFor(0),
                      label: 'All Categories',
                      icon: widget.selectedCategory == null
                          ? Icons.check_circle
                          : Icons.folder_outlined,
                      isSelected: widget.selectedCategory == null,
                      onTap: pickAll,
                      onKeyEvent: (node, event) =>
                          _handleKeyEvent(node, event, 0, pickAll),
                    );
                  }
                  final category = widget.categories[index - 1];
                  final isSelected = category == widget.selectedCategory;
                  final count = widget.categoryCounts?[category];
                  void pick() =>
                      Navigator.of(context).pop(_CategoryChoice(category));
                  return _FocusablePickerTile(
                    focusNode: _nodeFor(index),
                    label: count != null ? '$category  ($count)' : category,
                    icon: isSelected ? Icons.check_circle : Icons.folder_outlined,
                    isSelected: isSelected,
                    onTap: pick,
                    onHold: widget.canHide
                        ? () => Navigator.of(
                            context,
                          ).pop(_CategoryChoice(category, hide: true))
                        : null,
                    onKeyEvent: (node, event) =>
                        _handleKeyEvent(node, event, index, pick),
                  );
                },
              ),
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

/// Focusable picker tile for DPAD navigation
class _FocusablePickerTile extends StatefulWidget {
  final FocusNode? focusNode;
  final String label;
  final String? subtitle;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;
  final KeyEventResult Function(FocusNode, KeyEvent)? onKeyEvent;

  /// Secondary action: long-press, or hold OK on a remote. Wiring it changes
  /// how OK is read — the tile then acts on key-UP, so a press can be told
  /// from a hold.
  final VoidCallback? onHold;

  const _FocusablePickerTile({
    this.focusNode,
    required this.label,
    this.subtitle,
    required this.icon,
    required this.isSelected,
    required this.onTap,
    this.onKeyEvent,
    this.onHold,
  });

  @override
  State<_FocusablePickerTile> createState() => _FocusablePickerTileState();
}

class _FocusablePickerTileState extends State<_FocusablePickerTile> {
  bool _isFocused = false;
  final GlobalKey _tileKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    widget.focusNode?.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant _FocusablePickerTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode?.removeListener(_onFocusChange);
      widget.focusNode?.addListener(_onFocusChange);
    }
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    widget.focusNode?.removeListener(_onFocusChange);
    super.dispose();
  }

  /// Same 500ms as every other hold-OK in the app.
  static const _holdDuration = Duration(milliseconds: 500);
  Timer? _holdTimer;
  bool _sawSelectDown = false;
  bool _holdFired = false;

  void _startHold() {
    _holdFired = false;
    _holdTimer?.cancel();
    _holdTimer = Timer(_holdDuration, () {
      _holdFired = true;
      _sawSelectDown = false;
      widget.onHold?.call();
    });
  }

  void _cancelHold() {
    _holdTimer?.cancel();
    _holdTimer = null;
  }

  /// OK on a tile that has a hold action: the tap fires on key-UP, so that a
  /// press held past [_holdDuration] runs the secondary action instead. A
  /// key-up with no matching key-down on this tile (focus arrived mid-press)
  /// is swallowed rather than treated as a tap.
  KeyEventResult _handleSelectKey(KeyEvent event) {
    if (event is KeyDownEvent) {
      _sawSelectDown = true;
      _startHold();
      return KeyEventResult.handled;
    }
    if (event is KeyUpEvent) {
      _cancelHold();
      final wasPress = _sawSelectDown && !_holdFired;
      _sawSelectDown = false;
      _holdFired = false;
      if (wasPress) widget.onTap();
      return KeyEventResult.handled;
    }
    return KeyEventResult.handled; // swallow auto-repeat
  }

  void _onFocusChange() {
    if (mounted) {
      final hasFocus = widget.focusNode?.hasFocus ?? false;
      setState(() => _isFocused = hasFocus);
      if (!hasFocus) {
        // The key-up will land elsewhere; a timer firing after that would
        // act on a tile the user has already left.
        _cancelHold();
        _sawSelectDown = false;
      }

      // Scroll into view when focused
      if (hasFocus) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final context = _tileKey.currentContext;
          if (context != null) {
            Scrollable.ensureVisible(
              context,
              alignment: 0.5,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
            );
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (node, event) {
        // A holdable tile owns OK itself; everything else (BACK, up, down)
        // still belongs to the list that built it.
        if (widget.onHold != null &&
            (isActivateKey(event.logicalKey) ||
                event.logicalKey == LogicalKeyboardKey.space)) {
          return _handleSelectKey(event);
        }
        return widget.onKeyEvent?.call(node, event) ?? KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onHold,
        child: AnimatedContainer(
          key: _tileKey,
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          decoration: BoxDecoration(
            color: _isFocused
                ? colorScheme.primaryContainer
                : (widget.isSelected ? colorScheme.surfaceContainerHighest : null),
            borderRadius: BorderRadius.circular(8),
            border: _isFocused
                ? Border.all(color: colorScheme.primary, width: 2)
                : null,
          ),
          child: ListTile(
            leading: Icon(
              widget.icon,
              color: _isFocused
                  ? colorScheme.onPrimaryContainer
                  : (widget.isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant),
            ),
            title: Text(
              widget.label,
              style: TextStyle(
                fontWeight: widget.isSelected || _isFocused ? FontWeight.bold : FontWeight.normal,
                color: _isFocused
                    ? colorScheme.onPrimaryContainer
                    : (widget.isSelected ? colorScheme.primary : colorScheme.onSurface),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: widget.subtitle != null
                ? Text(
                    widget.subtitle!,
                    style: TextStyle(
                      fontSize: 12,
                      color: _isFocused
                          ? colorScheme.onPrimaryContainer.withOpacity(0.7)
                          : colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )
                : null,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
    );
  }
}
