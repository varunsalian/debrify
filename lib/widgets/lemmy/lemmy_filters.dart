import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/lemmy_service.dart';
import '../../services/storage_service.dart';
import '../../utils/tv_keys.dart';

/// Popular Lemmy video communities for suggestions (handle@instance).
/// Users can type any "community@instance" handle in the picker.
const List<String> kPopularLemmyCommunities = [
  'videos@lemmy.world',
  '[email protected]',
  '[email protected]',
  '[email protected]',
  '[email protected]',
  '[email protected]',
  '[email protected]',
  '[email protected]',
  '[email protected]',
];

/// Lemmy filter bar with community, sort, and time filters
class LemmyFiltersBar extends StatelessWidget {
  final String? selectedCommunity;
  final LemmySort selectedSort;
  final LemmyTimeFilter selectedTimeFilter;
  final bool isSearching;
  final int resultCount;
  final ValueChanged<String?> onCommunityChanged;
  final ValueChanged<LemmySort> onSortChanged;
  final ValueChanged<LemmyTimeFilter> onTimeFilterChanged;
  final VoidCallback? onRandomPressed;
  final bool isRandomLoading;
  final FocusNode? communityFocusNode;
  final FocusNode? sortFocusNode;
  final FocusNode? timeFocusNode;
  final FocusNode? randomFocusNode;

  const LemmyFiltersBar({
    super.key,
    required this.selectedCommunity,
    required this.selectedSort,
    required this.selectedTimeFilter,
    required this.isSearching,
    required this.resultCount,
    required this.onCommunityChanged,
    required this.onSortChanged,
    required this.onTimeFilterChanged,
    this.onRandomPressed,
    this.isRandomLoading = false,
    this.communityFocusNode,
    this.sortFocusNode,
    this.timeFocusNode,
    this.randomFocusNode,
  });

  bool get _showTimeFilter => selectedSort == LemmySort.top;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // Community dropdown
            _CommunityDropdown(
              selectedCommunity: selectedCommunity,
              onChanged: onCommunityChanged,
              focusNode: communityFocusNode,
            ),
            const SizedBox(width: 8),

            // Sort dropdown
            _SortDropdown(
              selectedSort: selectedSort,
              onChanged: onSortChanged,
              focusNode: sortFocusNode,
            ),

            // Time filter (conditional)
            if (_showTimeFilter) ...[
              const SizedBox(width: 8),
              _TimeFilterDropdown(
                selectedTimeFilter: selectedTimeFilter,
                onChanged: onTimeFilterChanged,
                focusNode: timeFocusNode,
              ),
            ],

            // Random button (only when a community is selected)
            if (selectedCommunity != null && onRandomPressed != null) ...[
              const SizedBox(width: 8),
              _RandomButton(
                onPressed: onRandomPressed!,
                isLoading: isRandomLoading,
                focusNode: randomFocusNode,
              ),
            ],

            const SizedBox(width: 8),

            // Result count
            Text(
              '$resultCount video${resultCount != 1 ? 's' : ''}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Community selection dropdown
class _CommunityDropdown extends StatefulWidget {
  final String? selectedCommunity;
  final ValueChanged<String?> onChanged;
  final FocusNode? focusNode;

  const _CommunityDropdown({
    required this.selectedCommunity,
    required this.onChanged,
    this.focusNode,
  });

  @override
  State<_CommunityDropdown> createState() => _CommunityDropdownState();
}

class _CommunityDropdownState extends State<_CommunityDropdown> {
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

  Future<void> _showCommunityPicker() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _CommunityPickerSheet(
        currentCommunity: widget.selectedCommunity,
      ),
    );

    if (result != null) {
      widget.onChanged(result.isEmpty ? null : result);
    }
  }

  /// Shorten a "name@instance" handle for the compact chip label.
  String get _label {
    final c = widget.selectedCommunity;
    if (c == null) return 'All Communities';
    return 'c/${c.split('@').first}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && isActivateKey(event.logicalKey)) {
          _showCommunityPicker();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: _showCommunityPicker,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isFocused
                  ? colorScheme.primary
                  : colorScheme.outline.withValues(alpha: 0.3),
              width: _isFocused ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.tag, size: 16, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                _label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface,
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

/// Sort selection dropdown - TV-friendly
class _SortDropdown extends StatefulWidget {
  final LemmySort selectedSort;
  final ValueChanged<LemmySort> onChanged;
  final FocusNode? focusNode;

  const _SortDropdown({
    required this.selectedSort,
    required this.onChanged,
    this.focusNode,
  });

  @override
  State<_SortDropdown> createState() => _SortDropdownState();
}

class _SortDropdownState extends State<_SortDropdown> {
  bool _isFocused = false;

  static const List<LemmySort> _availableSorts = [
    LemmySort.active,
    LemmySort.hot,
    LemmySort.new_,
    LemmySort.top,
    LemmySort.mostComments,
  ];

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

  Future<void> _showSortPicker() async {
    final result = await showModalBottomSheet<LemmySort>(
      context: context,
      builder: (context) => _SortPickerSheet(
        currentSort: widget.selectedSort,
        availableSorts: _availableSorts,
      ),
    );

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
        if (event is KeyDownEvent && isActivateKey(event.logicalKey)) {
          _showSortPicker();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: _showSortPicker,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isFocused
                  ? colorScheme.primary
                  : colorScheme.outline.withValues(alpha: 0.3),
              width: _isFocused ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                LemmyService.getSortDisplayName(widget.selectedSort),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface,
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

/// Time filter dropdown - TV-friendly
class _TimeFilterDropdown extends StatefulWidget {
  final LemmyTimeFilter selectedTimeFilter;
  final ValueChanged<LemmyTimeFilter> onChanged;
  final FocusNode? focusNode;

  const _TimeFilterDropdown({
    required this.selectedTimeFilter,
    required this.onChanged,
    this.focusNode,
  });

  @override
  State<_TimeFilterDropdown> createState() => _TimeFilterDropdownState();
}

class _TimeFilterDropdownState extends State<_TimeFilterDropdown> {
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

  Future<void> _showTimePicker() async {
    final result = await showModalBottomSheet<LemmyTimeFilter>(
      context: context,
      builder: (context) => _TimePickerSheet(
        currentFilter: widget.selectedTimeFilter,
      ),
    );

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
        if (event is KeyDownEvent && isActivateKey(event.logicalKey)) {
          _showTimePicker();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: _showTimePicker,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isFocused
                  ? colorScheme.primary
                  : colorScheme.outline.withValues(alpha: 0.3),
              width: _isFocused ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                LemmyService.getTimeFilterDisplayName(widget.selectedTimeFilter),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface,
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

/// Bottom sheet for selecting a community with full DPAD support
class _CommunityPickerSheet extends StatefulWidget {
  final String? currentCommunity;

  const _CommunityPickerSheet({this.currentCommunity});

  @override
  State<_CommunityPickerSheet> createState() => _CommunityPickerSheetState();
}

class _CommunityPickerSheetState extends State<_CommunityPickerSheet> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode(debugLabel: 'community-input');
  final FocusNode _goButtonFocusNode = FocusNode(debugLabel: 'community-go-button');

  List<String> _favoriteCommunities = [];
  bool _loading = true;

  final List<FocusNode> _tileFocusNodes = [];
  bool _inputIsFocused = false;

  @override
  void initState() {
    super.initState();
    _inputFocusNode.addListener(_onInputFocusChange);
    _loadFavorites();
  }

  void _onInputFocusChange() {
    if (mounted) {
      setState(() => _inputIsFocused = _inputFocusNode.hasFocus);
    }
  }

  Future<void> _loadFavorites() async {
    final favorites = await StorageService.getLemmyFavoriteCommunities();
    if (!mounted) return;
    setState(() {
      _favoriteCommunities = favorites;
      _loading = false;
    });
    _ensureFocusNodes();
    _autoFocusFirstItem();
  }

  void _ensureFocusNodes() {
    final itemCount = _getTotalItemCount();
    while (_tileFocusNodes.length > itemCount) {
      _tileFocusNodes.removeLast().dispose();
    }
    while (_tileFocusNodes.length < itemCount) {
      final index = _tileFocusNodes.length;
      _tileFocusNodes.add(FocusNode(debugLabel: 'community-tile-$index'));
    }
  }

  int _getTotalItemCount() {
    // "All Communities" + favorites + popular
    return 1 + _favoriteCommunities.length + kPopularLemmyCommunities.length;
  }

  void _autoFocusFirstItem() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_tileFocusNodes.isNotEmpty) {
        _tileFocusNodes[0].requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _inputFocusNode.removeListener(_onInputFocusChange);
    _inputFocusNode.dispose();
    _goButtonFocusNode.dispose();
    for (final node in _tileFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _selectCommunity(String? community) {
    Navigator.of(context).pop(community ?? '');
  }

  void _submitCustomCommunity() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) {
      _selectCommunity(text);
    }
  }

  KeyEventResult _handleInputKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (!mounted) return KeyEventResult.ignored;

    final key = event.logicalKey;
    final text = _controller.text;
    final selection = _controller.selection;
    final textLength = text.length;
    final isTextEmpty = textLength == 0;

    final isSelectionValid = selection.isValid && selection.baseOffset >= 0;
    final isAtStart = !isSelectionValid ||
        (selection.baseOffset == 0 && selection.extentOffset == 0);
    final isAtEnd = !isSelectionValid ||
        (selection.baseOffset == textLength && selection.extentOffset == textLength);

    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.browserBack) {
      try {
        Navigator.of(context).pop();
        return KeyEventResult.handled;
      } catch (e) {
        debugPrint('Error closing sheet: $e');
        return KeyEventResult.ignored;
      }
    }

    if (key == LogicalKeyboardKey.arrowUp) {
      if (isTextEmpty || isAtStart) {
        return KeyEventResult.handled;
      }
    }

    if (key == LogicalKeyboardKey.arrowDown) {
      if (isTextEmpty || isAtEnd) {
        if (_tileFocusNodes.isNotEmpty) {
          try {
            _tileFocusNodes[0].requestFocus();
            return KeyEventResult.handled;
          } catch (e) {
            debugPrint('Error moving focus down: $e');
            return KeyEventResult.ignored;
          }
        }
      }
    }

    if (key == LogicalKeyboardKey.arrowRight) {
      if (isTextEmpty || isAtEnd) {
        try {
          _goButtonFocusNode.requestFocus();
          return KeyEventResult.handled;
        } catch (e) {
          debugPrint('Error moving focus right: $e');
          return KeyEventResult.ignored;
        }
      }
    }

    return KeyEventResult.ignored;
  }

  KeyEventResult _handleTileKeyEvent(
      FocusNode node, KeyEvent event, int index, VoidCallback onSelect) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;

    if (isActivateKey(key)) {
      onSelect();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.browserBack) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowUp) {
      if (index > 0) {
        _tileFocusNodes[index - 1].requestFocus();
      } else {
        _inputFocusNode.requestFocus();
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowDown) {
      if (index < _tileFocusNodes.length - 1) {
        _tileFocusNodes[index + 1].requestFocus();
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return PopScope(
      canPop: true,
      child: DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: FocusScope(
              autofocus: true,
              child: FocusTraversalGroup(
                policy: OrderedTraversalPolicy(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Handle
                    Center(
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 12),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),

                    // Title
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'Select Community',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Custom input with TV-friendly navigation
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: FocusTraversalOrder(
                        order: const NumericFocusOrder(0),
                        child: Row(
                          children: [
                            Expanded(
                              child: Focus(
                                onKeyEvent: _handleInputKeyEvent,
                                skipTraversal: true,
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    border: _inputIsFocused
                                        ? Border.all(color: colorScheme.primary, width: 2)
                                        : null,
                                    boxShadow: _inputIsFocused
                                        ? [
                                            BoxShadow(
                                              color: colorScheme.primary.withValues(alpha: 0.2),
                                              blurRadius: 8,
                                              spreadRadius: 1,
                                            ),
                                          ]
                                        : null,
                                  ),
                                  child: TextField(
                                    controller: _controller,
                                    focusNode: _inputFocusNode,
                                    decoration: InputDecoration(
                                      hintText: 'community@instance',
                                      prefixIcon: const Icon(Icons.tag),
                                      prefixText: 'c/',
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      filled: true,
                                      fillColor: colorScheme.surfaceContainerHighest,
                                    ),
                                    textInputAction: TextInputAction.go,
                                    onSubmitted: (_) => _submitCustomCommunity(),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _TvFocusableIconButton(
                              focusNode: _goButtonFocusNode,
                              icon: Icons.arrow_forward,
                              onPressed: _submitCustomCommunity,
                              onLeftArrow: () => _inputFocusNode.requestFocus(),
                              onDownArrow: _tileFocusNodes.isNotEmpty
                                  ? () => _tileFocusNodes[0].requestFocus()
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // List
                    Expanded(
                      child: _loading
                          ? const Center(child: CircularProgressIndicator())
                          : ListView(
                              controller: scrollController,
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              children: _buildListItems(theme, colorScheme),
                            ),
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

  List<Widget> _buildListItems(ThemeData theme, ColorScheme colorScheme) {
    final items = <Widget>[];
    int focusIndex = 0;

    // All Communities option
    final allIndex = focusIndex;
    items.add(
      FocusTraversalOrder(
        order: NumericFocusOrder(1.0 + allIndex),
        child: _FocusableCommunityTile(
          focusNode: allIndex < _tileFocusNodes.length ? _tileFocusNodes[allIndex] : null,
          label: 'All Communities',
          icon: Icons.public,
          isSelected: widget.currentCommunity == null,
          onTap: () => _selectCommunity(null),
          onKeyEvent: (node, event) => _handleTileKeyEvent(
            node, event, allIndex, () => _selectCommunity(null),
          ),
        ),
      ),
    );
    focusIndex++;

    items.add(const Divider(height: 24));

    // Favorites section
    if (_favoriteCommunities.isNotEmpty) {
      items.add(
        Text(
          'Favorites',
          style: theme.textTheme.labelMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      );
      items.add(const SizedBox(height: 8));

      for (final community in _favoriteCommunities) {
        final currentIndex = focusIndex;
        items.add(
          FocusTraversalOrder(
            order: NumericFocusOrder(1.0 + focusIndex),
            child: _FocusableCommunityTile(
              focusNode: focusIndex < _tileFocusNodes.length ? _tileFocusNodes[focusIndex] : null,
              label: 'c/$community',
              icon: Icons.star,
              isSelected: widget.currentCommunity == community,
              onTap: () => _selectCommunity(community),
              onKeyEvent: (node, event) => _handleTileKeyEvent(
                node, event, currentIndex, () => _selectCommunity(community),
              ),
            ),
          ),
        );
        focusIndex++;
      }
      items.add(const Divider(height: 24));
    }

    // Popular section
    items.add(
      Text(
        'Popular',
        style: theme.textTheme.labelMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
    items.add(const SizedBox(height: 8));

    for (final community in kPopularLemmyCommunities) {
      final currentIndex = focusIndex;
      items.add(
        FocusTraversalOrder(
          order: NumericFocusOrder(1.0 + focusIndex),
          child: _FocusableCommunityTile(
            focusNode: focusIndex < _tileFocusNodes.length ? _tileFocusNodes[focusIndex] : null,
            label: 'c/$community',
            isSelected: widget.currentCommunity == community,
            onTap: () => _selectCommunity(community),
            onKeyEvent: (node, event) => _handleTileKeyEvent(
              node, event, currentIndex, () => _selectCommunity(community),
            ),
          ),
        ),
      );
      focusIndex++;
    }

    items.add(const SizedBox(height: 16));
    return items;
  }
}

/// Focusable community tile with DPAD support
class _FocusableCommunityTile extends StatefulWidget {
  final FocusNode? focusNode;
  final String label;
  final IconData? icon;
  final bool isSelected;
  final VoidCallback onTap;
  final KeyEventResult Function(FocusNode, KeyEvent)? onKeyEvent;

  const _FocusableCommunityTile({
    this.focusNode,
    required this.label,
    this.icon,
    required this.isSelected,
    required this.onTap,
    this.onKeyEvent,
  });

  @override
  State<_FocusableCommunityTile> createState() => _FocusableCommunityTileState();
}

class _FocusableCommunityTileState extends State<_FocusableCommunityTile> {
  bool _isFocused = false;
  final GlobalKey _tileKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    widget.focusNode?.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant _FocusableCommunityTile oldWidget) {
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
      final hasFocus = widget.focusNode?.hasFocus ?? false;
      setState(() => _isFocused = hasFocus);

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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: widget.onKeyEvent,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          key: _tileKey,
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(vertical: 2),
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
              widget.icon ?? Icons.tag,
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
            ),
            trailing: widget.isSelected
                ? Icon(Icons.check, color: _isFocused ? colorScheme.onPrimaryContainer : colorScheme.primary)
                : null,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
    );
  }
}

/// TV-focusable icon button
class _TvFocusableIconButton extends StatefulWidget {
  final FocusNode focusNode;
  final IconData icon;
  final VoidCallback onPressed;
  final VoidCallback? onLeftArrow;
  final VoidCallback? onDownArrow;

  const _TvFocusableIconButton({
    required this.focusNode,
    required this.icon,
    required this.onPressed,
    this.onLeftArrow,
    this.onDownArrow,
  });

  @override
  State<_TvFocusableIconButton> createState() => _TvFocusableIconButtonState();
}

class _TvFocusableIconButtonState extends State<_TvFocusableIconButton> {
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant _TvFocusableIconButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocusChange);
      widget.focusNode.addListener(_onFocusChange);
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    if (mounted) {
      setState(() => _isFocused = widget.focusNode.hasFocus);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;

        if (isActivateKey(event.logicalKey)) {
          widget.onPressed();
          return KeyEventResult.handled;
        }

        if (event.logicalKey == LogicalKeyboardKey.arrowLeft && widget.onLeftArrow != null) {
          widget.onLeftArrow!();
          return KeyEventResult.handled;
        }

        if (event.logicalKey == LogicalKeyboardKey.arrowDown && widget.onDownArrow != null) {
          widget.onDownArrow!();
          return KeyEventResult.handled;
        }

        if (event.logicalKey == LogicalKeyboardKey.escape ||
            event.logicalKey == LogicalKeyboardKey.goBack) {
          Navigator.of(context).pop();
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _isFocused ? colorScheme.primary : colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isFocused ? colorScheme.primary : colorScheme.outline.withValues(alpha: 0.3),
              width: _isFocused ? 2 : 1,
            ),
          ),
          child: Icon(
            widget.icon,
            color: _isFocused ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet for selecting sort option with DPAD support
class _SortPickerSheet extends StatefulWidget {
  final LemmySort currentSort;
  final List<LemmySort> availableSorts;

  const _SortPickerSheet({
    required this.currentSort,
    required this.availableSorts,
  });

  @override
  State<_SortPickerSheet> createState() => _SortPickerSheetState();
}

class _SortPickerSheetState extends State<_SortPickerSheet> {
  final List<FocusNode> _focusNodes = [];

  @override
  void initState() {
    super.initState();
    _initFocusNodes();
  }

  void _initFocusNodes() {
    for (int i = 0; i < widget.availableSorts.length; i++) {
      _focusNodes.add(FocusNode(debugLabel: 'lemmy-sort-option-$i'));
    }
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

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event, int index, LemmySort sort) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (isActivateKey(event.logicalKey)) {
      Navigator.of(context).pop(sort);
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
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Sort By',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 8),
            ...widget.availableSorts.asMap().entries.map((entry) {
              final index = entry.key;
              final sort = entry.value;
              final isSelected = sort == widget.currentSort;

              return _FocusablePickerTile(
                focusNode: index < _focusNodes.length ? _focusNodes[index] : null,
                label: LemmyService.getSortDisplayName(sort),
                isSelected: isSelected,
                onTap: () => Navigator.of(context).pop(sort),
                onKeyEvent: (node, event) => _handleKeyEvent(node, event, index, sort),
              );
            }),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet for selecting time filter with DPAD support
class _TimePickerSheet extends StatefulWidget {
  final LemmyTimeFilter currentFilter;

  const _TimePickerSheet({required this.currentFilter});

  @override
  State<_TimePickerSheet> createState() => _TimePickerSheetState();
}

class _TimePickerSheetState extends State<_TimePickerSheet> {
  final List<FocusNode> _focusNodes = [];

  @override
  void initState() {
    super.initState();
    _initFocusNodes();
  }

  void _initFocusNodes() {
    for (int i = 0; i < LemmyTimeFilter.values.length; i++) {
      _focusNodes.add(FocusNode(debugLabel: 'lemmy-time-option-$i'));
    }
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

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event, int index, LemmyTimeFilter filter) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (isActivateKey(event.logicalKey)) {
      Navigator.of(context).pop(filter);
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
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Time Filter',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 8),
            ...LemmyTimeFilter.values.asMap().entries.map((entry) {
              final index = entry.key;
              final filter = entry.value;
              final isSelected = filter == widget.currentFilter;

              return _FocusablePickerTile(
                focusNode: index < _focusNodes.length ? _focusNodes[index] : null,
                label: LemmyService.getTimeFilterDisplayName(filter),
                isSelected: isSelected,
                onTap: () => Navigator.of(context).pop(filter),
                onKeyEvent: (node, event) => _handleKeyEvent(node, event, index, filter),
              );
            }),
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
  final bool isSelected;
  final VoidCallback onTap;
  final KeyEventResult Function(FocusNode, KeyEvent)? onKeyEvent;

  const _FocusablePickerTile({
    this.focusNode,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.onKeyEvent,
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
    widget.focusNode?.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    if (mounted) {
      final hasFocus = widget.focusNode?.hasFocus ?? false;
      setState(() => _isFocused = hasFocus);

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
      onKeyEvent: widget.onKeyEvent,
      child: GestureDetector(
        onTap: widget.onTap,
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
              widget.isSelected ? Icons.check_circle : Icons.circle_outlined,
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
            ),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
    );
  }
}

class _RandomButton extends StatefulWidget {
  final VoidCallback onPressed;
  final bool isLoading;
  final FocusNode? focusNode;

  const _RandomButton({
    required this.onPressed,
    required this.isLoading,
    this.focusNode,
  });

  @override
  State<_RandomButton> createState() => _RandomButtonState();
}

class _RandomButtonState extends State<_RandomButton> {
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
    if (mounted) setState(() => _isFocused = widget.focusNode?.hasFocus ?? false);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && isActivateKey(event.logicalKey)) {
          if (!widget.isLoading) widget.onPressed();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.isLoading ? null : widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: _isFocused ? colorScheme.primary : colorScheme.tertiaryContainer,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isFocused ? colorScheme.primary : colorScheme.outline.withValues(alpha: 0.3),
              width: _isFocused ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.isLoading)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _isFocused
                        ? colorScheme.onPrimary
                        : colorScheme.onTertiaryContainer,
                  ),
                )
              else
                Icon(
                  Icons.shuffle_rounded,
                  size: 16,
                  color: _isFocused
                      ? colorScheme.onPrimary
                      : colorScheme.onTertiaryContainer,
                ),
              const SizedBox(width: 4),
              Text(
                'Random',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _isFocused
                      ? colorScheme.onPrimary
                      : colorScheme.onTertiaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
