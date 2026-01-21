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

/// Sort selection dropdown
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Focus(
      focusNode: widget.focusNode,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 8),
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
        child: DropdownButtonHideUnderline(
          child: DropdownButton<RedditSort>(
            value: widget.selectedSort,
            items: _availableSorts.map((sort) {
              return DropdownMenuItem(
                value: sort,
                child: Text(RedditService.getSortDisplayName(sort)),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) widget.onChanged(value);
            },
            dropdownColor: colorScheme.surfaceContainerHigh,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

/// Time filter dropdown
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Focus(
      focusNode: widget.focusNode,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 8),
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
        child: DropdownButtonHideUnderline(
          child: DropdownButton<RedditTimeFilter>(
            value: widget.selectedTimeFilter,
            items: RedditTimeFilter.values.map((filter) {
              return DropdownMenuItem(
                value: filter,
                child: Text(RedditService.getTimeFilterDisplayName(filter)),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) widget.onChanged(value);
            },
            dropdownColor: colorScheme.surfaceContainerHigh,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet for selecting subreddit
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
  final FocusNode _inputFocusNode = FocusNode();
  List<String> _favoriteSubreddits = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    final favorites = await StorageService.getRedditFavoriteSubreddits();
    if (!mounted) return;
    setState(() {
      _favoriteSubreddits = favorites;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  void _selectSubreddit(String? subreddit) {
    Navigator.of(context).pop(subreddit ?? '');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DraggableScrollableSheet(
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

              // Custom input
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _controller,
                  focusNode: _inputFocusNode,
                  decoration: InputDecoration(
                    hintText: 'Enter subreddit name',
                    prefixIcon: const Icon(Icons.tag),
                    prefixText: 'r/',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.arrow_forward),
                      onPressed: () {
                        if (_controller.text.trim().isNotEmpty) {
                          _selectSubreddit(_controller.text.trim());
                        }
                      },
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: colorScheme.surfaceContainerHighest,
                  ),
                  textInputAction: TextInputAction.go,
                  onSubmitted: (value) {
                    if (value.trim().isNotEmpty) {
                      _selectSubreddit(value.trim());
                    }
                  },
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
                        children: [
                          // All Subreddits option
                          _SubredditTile(
                            label: 'All Subreddits',
                            icon: Icons.public,
                            isSelected: widget.currentSubreddit == null,
                            onTap: () => _selectSubreddit(null),
                          ),
                          const Divider(height: 24),

                          // Favorites section (if any)
                          if (_favoriteSubreddits.isNotEmpty) ...[
                            Text(
                              'Favorites',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ..._favoriteSubreddits.map((sub) => _SubredditTile(
                              label: 'r/$sub',
                              icon: Icons.star,
                              isSelected: widget.currentSubreddit == sub,
                              onTap: () => _selectSubreddit(sub),
                            )),
                            const Divider(height: 24),
                          ],

                          // Popular
                          Text(
                            'Popular',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...kPopularSubreddits.map((sub) => _SubredditTile(
                            label: 'r/$sub',
                            isSelected: widget.currentSubreddit == sub,
                            onTap: () => _selectSubreddit(sub),
                          )),
                          const SizedBox(height: 16),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SubredditTile extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _SubredditTile({
    required this.label,
    this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListTile(
      leading: Icon(
        icon ?? Icons.tag,
        color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
      ),
      title: Text(
        label,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? colorScheme.primary : colorScheme.onSurface,
        ),
      ),
      trailing: isSelected
          ? Icon(Icons.check, color: colorScheme.primary)
          : null,
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }
}
