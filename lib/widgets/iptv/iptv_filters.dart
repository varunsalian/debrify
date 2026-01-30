import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/iptv_playlist.dart';

/// IPTV filter bar with playlist and category dropdowns
class IptvFiltersBar extends StatelessWidget {
  final List<IptvPlaylist> playlists;
  final IptvPlaylist? selectedPlaylist;
  final List<String> categories;
  final String? selectedCategory;
  final int channelCount;
  final bool isLoading;
  final ValueChanged<IptvPlaylist?> onPlaylistChanged;
  final ValueChanged<String?> onCategoryChanged;
  final VoidCallback? onAddPlaylist;
  final FocusNode? playlistFocusNode;
  final FocusNode? categoryFocusNode;
  // DPAD navigation callbacks
  final VoidCallback? onUpArrowPressed;
  final VoidCallback? onDownArrowPressed;

  const IptvFiltersBar({
    super.key,
    required this.playlists,
    required this.selectedPlaylist,
    required this.categories,
    required this.selectedCategory,
    required this.channelCount,
    required this.isLoading,
    required this.onPlaylistChanged,
    required this.onCategoryChanged,
    this.onAddPlaylist,
    this.playlistFocusNode,
    this.categoryFocusNode,
    this.onUpArrowPressed,
    this.onDownArrowPressed,
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
                  onRightArrowPressed: hasCategories ? () => categoryFocusNode?.requestFocus() : null,
                ),
              ),
              const SizedBox(width: 8),

              // Category dropdown (only if we have categories)
              if (hasCategories)
                Flexible(
                  child: _CategoryDropdown(
                    categories: categories,
                    selectedCategory: selectedCategory,
                    onChanged: onCategoryChanged,
                    focusNode: categoryFocusNode,
                    onUpArrowPressed: onUpArrowPressed,
                    onDownArrowPressed: onDownArrowPressed,
                    onLeftArrowPressed: () => playlistFocusNode?.requestFocus(),
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
                  Text(
                    '$channelCount channel${channelCount != 1 ? 's' : ''}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ],
          );
        },
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

        if (event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter) {
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
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isFocused
                  ? colorScheme.primary
                  : colorScheme.outline.withOpacity(0.3),
              width: _isFocused ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.playlist_play,
                size: 16,
                color: colorScheme.onSurfaceVariant,
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
  final String? selectedCategory;
  final ValueChanged<String?> onChanged;
  final FocusNode? focusNode;
  final VoidCallback? onUpArrowPressed;
  final VoidCallback? onDownArrowPressed;
  final VoidCallback? onLeftArrowPressed;

  const _CategoryDropdown({
    required this.categories,
    required this.selectedCategory,
    required this.onChanged,
    this.focusNode,
    this.onUpArrowPressed,
    this.onDownArrowPressed,
    this.onLeftArrowPressed,
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
    final result = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _CategoryPickerSheet(
        categories: widget.categories,
        selectedCategory: widget.selectedCategory,
      ),
    );

    if (result != null) {
      widget.onChanged(result.isEmpty ? null : result);
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

        if (event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter) {
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

        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: _showCategoryPicker,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isFocused
                  ? colorScheme.primary
                  : colorScheme.outline.withOpacity(0.3),
              width: _isFocused ? 2 : 1,
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

    if (event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.enter) {
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
                  subtitle: playlist.url,
                  icon: isSelected ? Icons.check_circle : Icons.playlist_play,
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

/// Bottom sheet for selecting category with DPAD support
class _CategoryPickerSheet extends StatefulWidget {
  final List<String> categories;
  final String? selectedCategory;

  const _CategoryPickerSheet({
    required this.categories,
    required this.selectedCategory,
  });

  @override
  State<_CategoryPickerSheet> createState() => _CategoryPickerSheetState();
}

class _CategoryPickerSheetState extends State<_CategoryPickerSheet> {
  final List<FocusNode> _focusNodes = [];

  @override
  void initState() {
    super.initState();
    _initFocusNodes();
  }

  void _initFocusNodes() {
    // +1 for "All Categories" option
    for (int i = 0; i < widget.categories.length + 1; i++) {
      _focusNodes.add(FocusNode(debugLabel: 'iptv-category-$i'));
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

    if (event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.enter) {
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
              child: Text(
                'Select Category',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Options
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  // All Categories option
                  _FocusablePickerTile(
                    focusNode: _focusNodes.isNotEmpty ? _focusNodes[0] : null,
                    label: 'All Categories',
                    icon: widget.selectedCategory == null ? Icons.check_circle : Icons.folder_outlined,
                    isSelected: widget.selectedCategory == null,
                    onTap: () => Navigator.of(context).pop(''),
                    onKeyEvent: (node, event) => _handleKeyEvent(
                      node, event, 0, () => Navigator.of(context).pop(''),
                    ),
                  ),

                  // Category options
                  ...widget.categories.asMap().entries.map((entry) {
                    final index = entry.key + 1; // +1 for "All Categories"
                    final category = entry.value;
                    final isSelected = category == widget.selectedCategory;

                    return _FocusablePickerTile(
                      focusNode: index < _focusNodes.length ? _focusNodes[index] : null,
                      label: category,
                      icon: isSelected ? Icons.check_circle : Icons.folder_outlined,
                      isSelected: isSelected,
                      onTap: () => Navigator.of(context).pop(category),
                      onKeyEvent: (node, event) => _handleKeyEvent(
                        node, event, index, () => Navigator.of(context).pop(category),
                      ),
                    );
                  }),
                ],
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

  const _FocusablePickerTile({
    this.focusNode,
    required this.label,
    this.subtitle,
    required this.icon,
    required this.isSelected,
    required this.onTap,
    this.onKeyEvent,
  });

  @override
  State<_FocusablePickerTile> createState() => _FocusablePickerTileState();
}

class _FocusablePickerTileState extends State<_FocusablePickerTile> {
  bool _isFocused = false;

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
    widget.focusNode?.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    if (mounted) {
      setState(() => _isFocused = widget.focusNode?.hasFocus ?? false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: widget.onKeyEvent,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
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
