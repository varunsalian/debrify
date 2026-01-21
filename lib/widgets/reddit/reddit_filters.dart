import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/reddit_service.dart';
import '../../services/storage_service.dart';

/// Popular subreddits for suggestions
const List<String> kPopularSubreddits = [
  'videos',
  'funny',
  'aww',
  'Unexpected',
  'nextfuckinglevel',
  'PublicFreakout',
  'interestingasfuck',
  'oddlysatisfying',
  'NatureIsFuckingLit',
  'memes',
  'gaming',
  'sports',
];

/// Reddit filter bar with subreddit, sort, and time filters
class RedditFiltersBar extends StatelessWidget {
  final String? selectedSubreddit;
  final RedditSort selectedSort;
  final RedditTimeFilter selectedTimeFilter;
  final bool isSearching;
  final int resultCount;
  final ValueChanged<String?> onSubredditChanged;
  final ValueChanged<RedditSort> onSortChanged;
  final ValueChanged<RedditTimeFilter> onTimeFilterChanged;
  final FocusNode? subredditFocusNode;
  final FocusNode? sortFocusNode;
  final FocusNode? timeFocusNode;

  const RedditFiltersBar({
    super.key,
    required this.selectedSubreddit,
    required this.selectedSort,
    required this.selectedTimeFilter,
    required this.isSearching,
    required this.resultCount,
    required this.onSubredditChanged,
    required this.onSortChanged,
    required this.onTimeFilterChanged,
    this.subredditFocusNode,
    this.sortFocusNode,
    this.timeFocusNode,
  });

  bool get _showTimeFilter =>
      selectedSort == RedditSort.top || isSearching;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // Subreddit dropdown
          _SubredditDropdown(
            selectedSubreddit: selectedSubreddit,
            onChanged: onSubredditChanged,
            focusNode: subredditFocusNode,
          ),
          const SizedBox(width: 8),

          // Sort dropdown
          _SortDropdown(
            selectedSort: selectedSort,
            isSearching: isSearching,
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

          const Spacer(),

          // Result count
          Text(
            '$resultCount video${resultCount != 1 ? 's' : ''}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Subreddit selection dropdown
class _SubredditDropdown extends StatefulWidget {
  final String? selectedSubreddit;
  final ValueChanged<String?> onChanged;
  final FocusNode? focusNode;

  const _SubredditDropdown({
    required this.selectedSubreddit,
    required this.onChanged,
    this.focusNode,
  });

  @override
  State<_SubredditDropdown> createState() => _SubredditDropdownState();
}

class _SubredditDropdownState extends State<_SubredditDropdown> {
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

  Future<void> _showSubredditPicker() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _SubredditPickerSheet(
        currentSubreddit: widget.selectedSubreddit,
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
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
             event.logicalKey == LogicalKeyboardKey.enter)) {
          _showSubredditPicker();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: _showSubredditPicker,
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
                Icons.tag,
                size: 16,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                widget.selectedSubreddit != null
                    ? 'r/${widget.selectedSubreddit}'
                    : 'All Subreddits',
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
  final RedditSort selectedSort;
  final bool isSearching;
  final ValueChanged<RedditSort> onChanged;
  final FocusNode? focusNode;

  const _SortDropdown({
    required this.selectedSort,
    required this.isSearching,
    required this.onChanged,
    this.focusNode,
  });

  @override
  State<_SortDropdown> createState() => _SortDropdownState();
}

class _SortDropdownState extends State<_SortDropdown> {
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

  List<RedditSort> get _availableSorts {
    if (widget.isSearching) {
      return [RedditSort.relevance, RedditSort.hot, RedditSort.top, RedditSort.new_];
    }
    return [RedditSort.hot, RedditSort.new_, RedditSort.top, RedditSort.rising];
  }

  Future<void> _showSortPicker() async {
    final result = await showModalBottomSheet<RedditSort>(
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
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
             event.logicalKey == LogicalKeyboardKey.enter)) {
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
                RedditService.getSortDisplayName(widget.selectedSort),
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
  final RedditTimeFilter selectedTimeFilter;
  final ValueChanged<RedditTimeFilter> onChanged;
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
    final result = await showModalBottomSheet<RedditTimeFilter>(
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
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
             event.logicalKey == LogicalKeyboardKey.enter)) {
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
                RedditService.getTimeFilterDisplayName(widget.selectedTimeFilter),
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

/// Bottom sheet for selecting subreddit with full DPAD support
class _SubredditPickerSheet extends StatefulWidget {
  final String? currentSubreddit;

  const _SubredditPickerSheet({
    this.currentSubreddit,
  });

  @override
  State<_SubredditPickerSheet> createState() => _SubredditPickerSheetState();
}

class _SubredditPickerSheetState extends State<_SubredditPickerSheet> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode(debugLabel: 'subreddit-input');
  final FocusNode _goButtonFocusNode = FocusNode(debugLabel: 'subreddit-go-button');

  List<String> _favoriteSubreddits = [];
  bool _loading = true;

  // Focus nodes for list items
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
    final favorites = await StorageService.getRedditFavoriteSubreddits();
    if (!mounted) return;
    setState(() {
      _favoriteSubreddits = favorites;
      _loading = false;
    });
    _ensureFocusNodes();
    _autoFocusFirstItem();
  }

  void _ensureFocusNodes() {
    final itemCount = _getTotalItemCount();

    // Dispose extra focus nodes
    while (_tileFocusNodes.length > itemCount) {
      _tileFocusNodes.removeLast().dispose();
    }

    // Add missing focus nodes
    while (_tileFocusNodes.length < itemCount) {
      final index = _tileFocusNodes.length;
      _tileFocusNodes.add(FocusNode(debugLabel: 'subreddit-tile-$index'));
    }
  }

  int _getTotalItemCount() {
    // "All Subreddits" + favorites + popular
    return 1 + _favoriteSubreddits.length + kPopularSubreddits.length;
  }

  void _autoFocusFirstItem() {
    // Use post-frame callback to ensure the sheet is fully built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Focus first list item (All Subreddits) for DPAD navigation
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

  void _selectSubreddit(String? subreddit) {
    Navigator.of(context).pop(subreddit ?? '');
  }

  void _submitCustomSubreddit() {
    if (_controller.text.trim().isNotEmpty) {
      _selectSubreddit(_controller.text.trim());
    }
  }

  KeyEventResult _handleInputKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // Safety check: widget must be mounted
    if (!mounted) return KeyEventResult.ignored;

    final key = event.logicalKey;
    final text = _controller.text;
    final selection = _controller.selection;
    final textLength = text.length;
    final isTextEmpty = textLength == 0;

    // Check if selection is valid
    final isSelectionValid = selection.isValid && selection.baseOffset >= 0;
    final isAtStart = !isSelectionValid ||
        (selection.baseOffset == 0 && selection.extentOffset == 0);
    final isAtEnd = !isSelectionValid ||
        (selection.baseOffset == textLength && selection.extentOffset == textLength);

    // Back/Escape: Close sheet
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

    // Arrow Up: Nothing above input, just consume to prevent default behavior
    if (key == LogicalKeyboardKey.arrowUp) {
      if (isTextEmpty || isAtStart) {
        return KeyEventResult.handled;
      }
    }

    // Arrow Down: Move to first list item
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

    // Arrow Right: Move to go button when at end
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

  KeyEventResult _handleTileKeyEvent(FocusNode node, KeyEvent event, int index, VoidCallback onSelect) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;

    // Select/Enter: Select this subreddit
    if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter) {
      onSelect();
      return KeyEventResult.handled;
    }

    // Back/Escape: Close sheet
    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.browserBack) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }

    // Arrow Up: Move to previous item or input
    if (key == LogicalKeyboardKey.arrowUp) {
      if (index > 0) {
        _tileFocusNodes[index - 1].requestFocus();
      } else {
        _inputFocusNode.requestFocus();
      }
      return KeyEventResult.handled;
    }

    // Arrow Down: Move to next item
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
                        color: colorScheme.onSurfaceVariant.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // Title
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'Select Subreddit',
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
                                            color: colorScheme.primary.withOpacity(0.2),
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
                                    hintText: 'Enter subreddit name',
                                    prefixIcon: const Icon(Icons.tag),
                                    prefixText: 'r/',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    filled: true,
                                    fillColor: colorScheme.surfaceContainerHighest,
                                  ),
                                  textInputAction: TextInputAction.go,
                                  onSubmitted: (_) => _submitCustomSubreddit(),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _TvFocusableIconButton(
                            focusNode: _goButtonFocusNode,
                            icon: Icons.arrow_forward,
                            onPressed: _submitCustomSubreddit,
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

    // All Subreddits option
    items.add(
      FocusTraversalOrder(
        order: NumericFocusOrder(1.0 + focusIndex),
        child: _FocusableSubredditTile(
          focusNode: focusIndex < _tileFocusNodes.length ? _tileFocusNodes[focusIndex] : null,
          label: 'All Subreddits',
          icon: Icons.public,
          isSelected: widget.currentSubreddit == null,
          onTap: () => _selectSubreddit(null),
          onKeyEvent: (node, event) => _handleTileKeyEvent(
            node, event, focusIndex, () => _selectSubreddit(null),
          ),
        ),
      ),
    );
    focusIndex++;

    items.add(const Divider(height: 24));

    // Favorites section
    if (_favoriteSubreddits.isNotEmpty) {
      items.add(
        Text(
          'Favorites',
          style: theme.textTheme.labelMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      );
      items.add(const SizedBox(height: 8));

      for (final sub in _favoriteSubreddits) {
        final currentIndex = focusIndex;
        items.add(
          FocusTraversalOrder(
            order: NumericFocusOrder(1.0 + focusIndex),
            child: _FocusableSubredditTile(
              focusNode: focusIndex < _tileFocusNodes.length ? _tileFocusNodes[focusIndex] : null,
              label: 'r/$sub',
              icon: Icons.star,
              isSelected: widget.currentSubreddit == sub,
              onTap: () => _selectSubreddit(sub),
              onKeyEvent: (node, event) => _handleTileKeyEvent(
                node, event, currentIndex, () => _selectSubreddit(sub),
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

    for (final sub in kPopularSubreddits) {
      final currentIndex = focusIndex;
      items.add(
        FocusTraversalOrder(
          order: NumericFocusOrder(1.0 + focusIndex),
          child: _FocusableSubredditTile(
            focusNode: focusIndex < _tileFocusNodes.length ? _tileFocusNodes[focusIndex] : null,
            label: 'r/$sub',
            isSelected: widget.currentSubreddit == sub,
            onTap: () => _selectSubreddit(sub),
            onKeyEvent: (node, event) => _handleTileKeyEvent(
              node, event, currentIndex, () => _selectSubreddit(sub),
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

/// Focusable subreddit tile with DPAD support
class _FocusableSubredditTile extends StatefulWidget {
  final FocusNode? focusNode;
  final String label;
  final IconData? icon;
  final bool isSelected;
  final VoidCallback onTap;
  final KeyEventResult Function(FocusNode, KeyEvent)? onKeyEvent;

  const _FocusableSubredditTile({
    this.focusNode,
    required this.label,
    this.icon,
    required this.isSelected,
    required this.onTap,
    this.onKeyEvent,
  });

  @override
  State<_FocusableSubredditTile> createState() => _FocusableSubredditTileState();
}

class _FocusableSubredditTileState extends State<_FocusableSubredditTile> {
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode?.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant _FocusableSubredditTile oldWidget) {
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: widget.onKeyEvent,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
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

        if (event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter) {
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
              color: _isFocused ? colorScheme.primary : colorScheme.outline.withOpacity(0.3),
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
  final RedditSort currentSort;
  final List<RedditSort> availableSorts;

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
      _focusNodes.add(FocusNode(debugLabel: 'sort-option-$i'));
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

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event, int index, RedditSort sort) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.enter) {
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
                'Sort By',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Options
            ...widget.availableSorts.asMap().entries.map((entry) {
              final index = entry.key;
              final sort = entry.value;
              final isSelected = sort == widget.currentSort;

              return _FocusablePickerTile(
                focusNode: index < _focusNodes.length ? _focusNodes[index] : null,
                label: RedditService.getSortDisplayName(sort),
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
  final RedditTimeFilter currentFilter;

  const _TimePickerSheet({
    required this.currentFilter,
  });

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
    for (int i = 0; i < RedditTimeFilter.values.length; i++) {
      _focusNodes.add(FocusNode(debugLabel: 'time-option-$i'));
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

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event, int index, RedditTimeFilter filter) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.enter) {
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
                'Time Filter',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Options
            ...RedditTimeFilter.values.asMap().entries.map((entry) {
              final index = entry.key;
              final filter = entry.value;
              final isSelected = filter == widget.currentFilter;

              return _FocusablePickerTile(
                focusNode: index < _focusNodes.length ? _focusNodes[index] : null,
                label: RedditService.getTimeFilterDisplayName(filter),
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
