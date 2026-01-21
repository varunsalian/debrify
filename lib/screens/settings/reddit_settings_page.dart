import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/storage_service.dart';

class RedditSettingsPage extends StatefulWidget {
  const RedditSettingsPage({super.key});

  @override
  State<RedditSettingsPage> createState() => _RedditSettingsPageState();
}

class _RedditSettingsPageState extends State<RedditSettingsPage> {
  final TextEditingController _subredditController = TextEditingController();
  final FocusNode _subredditInputFocusNode = FocusNode(debugLabel: 'reddit-subreddit-input');
  final FocusNode _addButtonFocusNode = FocusNode(debugLabel: 'reddit-add-button');
  final FocusNode _nsfwToggleFocusNode = FocusNode(debugLabel: 'reddit-nsfw-toggle');

  // Focus nodes for favorite subreddit items (2 per item: star + delete)
  final List<FocusNode> _favoriteFocusNodes = [];

  bool _allowNsfw = false;
  List<String> _favoriteSubreddits = [];
  String? _defaultSubreddit;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _subredditController.dispose();
    _subredditInputFocusNode.dispose();
    _addButtonFocusNode.dispose();
    _nsfwToggleFocusNode.dispose();
    for (final node in _favoriteFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _ensureFocusNodes() {
    // 2 focus nodes per favorite (star button + delete button)
    final needed = _favoriteSubreddits.length * 2;

    while (_favoriteFocusNodes.length > needed) {
      _favoriteFocusNodes.removeLast().dispose();
    }

    while (_favoriteFocusNodes.length < needed) {
      final index = _favoriteFocusNodes.length;
      _favoriteFocusNodes.add(FocusNode(debugLabel: 'reddit-fav-$index'));
    }
  }

  Future<void> _loadSettings() async {
    final allowNsfw = await StorageService.getRedditAllowNsfw();
    final favorites = await StorageService.getRedditFavoriteSubreddits();
    final defaultSub = await StorageService.getRedditDefaultSubreddit();

    if (!mounted) return;

    setState(() {
      _allowNsfw = allowNsfw;
      _favoriteSubreddits = favorites;
      _defaultSubreddit = defaultSub;
      _loading = false;
    });
    _ensureFocusNodes();
  }

  Future<void> _toggleNsfw(bool value) async {
    await StorageService.setRedditAllowNsfw(value);
    setState(() => _allowNsfw = value);
    _showSnackBar(
      value ? 'NSFW content enabled' : 'NSFW content disabled',
      isError: false,
    );
  }

  Future<void> _addFavoriteSubreddit() async {
    final subreddit = _subredditController.text.trim();
    if (subreddit.isEmpty) {
      _showSnackBar('Please enter a subreddit name');
      return;
    }

    // Remove r/ prefix if present
    final cleanName = subreddit.replaceFirst(RegExp(r'^r/', caseSensitive: false), '');

    if (_favoriteSubreddits.contains(cleanName)) {
      _showSnackBar('Subreddit already in favorites');
      return;
    }

    final newFavorites = [..._favoriteSubreddits, cleanName];
    await StorageService.setRedditFavoriteSubreddits(newFavorites);

    setState(() {
      _favoriteSubreddits = newFavorites;
      _subredditController.clear();
    });
    _ensureFocusNodes();

    _showSnackBar('Added r/$cleanName to favorites', isError: false);
  }

  Future<void> _removeFavoriteSubreddit(String subreddit) async {
    final newFavorites = _favoriteSubreddits.where((s) => s != subreddit).toList();
    await StorageService.setRedditFavoriteSubreddits(newFavorites);

    // If removed subreddit was the default, clear default
    if (_defaultSubreddit == subreddit) {
      await StorageService.setRedditDefaultSubreddit(null);
      setState(() => _defaultSubreddit = null);
    }

    setState(() => _favoriteSubreddits = newFavorites);
    _ensureFocusNodes();
    _showSnackBar('Removed r/$subreddit from favorites', isError: false);
  }

  Future<void> _setDefaultSubreddit(String? subreddit) async {
    await StorageService.setRedditDefaultSubreddit(subreddit);
    setState(() => _defaultSubreddit = subreddit);
    _showSnackBar(
      subreddit != null ? 'Default set to r/$subreddit' : 'Default cleared',
      isError: false,
    );
  }

  void _showSnackBar(String message, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  List<Widget> _buildFavoritesList() {
    final items = <Widget>[];

    for (int i = 0; i < _favoriteSubreddits.length; i++) {
      final subreddit = _favoriteSubreddits[i];
      final isDefault = _defaultSubreddit == subreddit;
      final starFocusIndex = i * 2;
      final deleteFocusIndex = i * 2 + 1;

      items.add(
        FocusTraversalOrder(
          order: NumericFocusOrder(3.0 + i),
          child: _FocusableFavoriteTile(
            subreddit: subreddit,
            isDefault: isDefault,
            starFocusNode: starFocusIndex < _favoriteFocusNodes.length
                ? _favoriteFocusNodes[starFocusIndex]
                : null,
            deleteFocusNode: deleteFocusIndex < _favoriteFocusNodes.length
                ? _favoriteFocusNodes[deleteFocusIndex]
                : null,
            onSetDefault: () => _setDefaultSubreddit(isDefault ? null : subreddit),
            onDelete: () => _removeFavoriteSubreddit(subreddit),
          ),
        ),
      );
    }

    return items;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Reddit Settings')),
      body: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Reddit Integration',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Browse and play videos from Reddit subreddits.',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 24),

            // NSFW Toggle
            FocusTraversalOrder(
              order: const NumericFocusOrder(1),
              child: _FocusableSwitchCard(
                focusNode: _nsfwToggleFocusNode,
                title: 'Allow NSFW Content',
                subtitle: _allowNsfw
                    ? 'NSFW subreddits and content are visible'
                    : 'NSFW content is hidden',
                icon: _allowNsfw ? Icons.visibility : Icons.visibility_off,
                iconColor: _allowNsfw ? Colors.red : null,
                value: _allowNsfw,
                onChanged: _toggleNsfw,
              ),
            ),
            const SizedBox(height: 24),

            // Favorite Subreddits
            Text(
              'Favorite Subreddits',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add subreddits for quick access in the filter dropdown.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),

            // Add subreddit input
            FocusTraversalOrder(
              order: const NumericFocusOrder(2),
              child: Row(
                children: [
                  Expanded(
                    child: _TvFriendlyTextField(
                      controller: _subredditController,
                      focusNode: _subredditInputFocusNode,
                      labelText: 'Subreddit name',
                      hintText: 'e.g., videos',
                      prefixIcon: const Icon(Icons.tag),
                      onSubmitted: (_) => _addFavoriteSubreddit(),
                      onRightArrow: () => _addButtonFocusNode.requestFocus(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _TvFocusableButton(
                    focusNode: _addButtonFocusNode,
                    icon: Icons.add,
                    label: 'Add',
                    onPressed: _addFavoriteSubreddit,
                    onLeftArrow: () => _subredditInputFocusNode.requestFocus(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Favorites list
            if (_favoriteSubreddits.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(
                        Icons.star_border,
                        size: 48,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No favorite subreddits yet',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Card(
                child: Column(
                  children: _buildFavoritesList(),
                ),
              ),
            const SizedBox(height: 24),

            // Default Subreddit Info
            if (_defaultSubreddit != null)
              Card(
                color: Colors.amber.withValues(alpha: 0.1),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Colors.amber),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'r/$_defaultSubreddit will load automatically when you select Reddit.',
                          style: TextStyle(
                            color: Colors.amber.shade700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A TV-friendly TextField that allows escaping with DPAD
class _TvFriendlyTextField extends StatefulWidget {
  const _TvFriendlyTextField({
    required this.controller,
    required this.focusNode,
    required this.labelText,
    required this.hintText,
    required this.prefixIcon,
    this.onSubmitted,
    this.onRightArrow,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String labelText;
  final String hintText;
  final Widget prefixIcon;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onRightArrow;

  @override
  State<_TvFriendlyTextField> createState() => _TvFriendlyTextFieldState();
}

class _TvFriendlyTextFieldState extends State<_TvFriendlyTextField> {
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_handleFocusChange);
    super.dispose();
  }

  void _handleFocusChange() {
    if (mounted) {
      setState(() {
        _isFocused = widget.focusNode.hasFocus;
      });
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // Safety check: widget must be mounted to access context
    if (!mounted) return KeyEventResult.ignored;

    final key = event.logicalKey;
    final text = widget.controller.text;
    final selection = widget.controller.selection;
    final textLength = text.length;
    final isTextEmpty = textLength == 0;

    // Check if selection is valid
    final isSelectionValid = selection.isValid && selection.baseOffset >= 0;
    final isAtStart =
        !isSelectionValid ||
        (selection.baseOffset == 0 && selection.extentOffset == 0);
    final isAtEnd =
        !isSelectionValid ||
        (selection.baseOffset == textLength &&
            selection.extentOffset == textLength);

    // Allow escape from TextField with back button
    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.browserBack) {
      final ctx = node.context;
      if (ctx != null && mounted) {
        try {
          FocusScope.of(ctx).previousFocus();
          return KeyEventResult.handled;
        } catch (e) {
          debugPrint('Error handling escape key: $e');
          return KeyEventResult.ignored;
        }
      }
    }

    // Navigate up: allow if text is empty or cursor at start
    if (key == LogicalKeyboardKey.arrowUp) {
      if (isTextEmpty || isAtStart) {
        final ctx = node.context;
        if (ctx != null && mounted) {
          try {
            FocusScope.of(ctx).focusInDirection(TraversalDirection.up);
            return KeyEventResult.handled;
          } catch (e) {
            debugPrint('Error handling arrow up: $e');
            return KeyEventResult.ignored;
          }
        }
      }
    }

    // Navigate down: allow if text is empty or cursor at end
    if (key == LogicalKeyboardKey.arrowDown) {
      if (isTextEmpty || isAtEnd) {
        final ctx = node.context;
        if (ctx != null && mounted) {
          try {
            FocusScope.of(ctx).focusInDirection(TraversalDirection.down);
            return KeyEventResult.handled;
          } catch (e) {
            debugPrint('Error handling arrow down: $e');
            return KeyEventResult.ignored;
          }
        }
      }
    }

    // Navigate right: allow if text is empty or cursor at end
    if (key == LogicalKeyboardKey.arrowRight) {
      if ((isTextEmpty || isAtEnd) && widget.onRightArrow != null) {
        widget.onRightArrow!();
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Focus(
      onKeyEvent: _handleKeyEvent,
      skipTraversal: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: _isFocused
              ? Border.all(color: theme.colorScheme.primary, width: 2)
              : null,
          boxShadow: _isFocused
              ? [
                  BoxShadow(
                    color: theme.colorScheme.primary.withValues(alpha: 0.2),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: TextField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          decoration: InputDecoration(
            labelText: widget.labelText,
            hintText: widget.hintText,
            prefixIcon: widget.prefixIcon,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: widget.onSubmitted,
        ),
      ),
    );
  }
}

/// A focusable switch card for TV navigation
class _FocusableSwitchCard extends StatefulWidget {
  const _FocusableSwitchCard({
    required this.focusNode,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.iconColor,
    required this.value,
    required this.onChanged,
  });

  final FocusNode focusNode;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color? iconColor;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  State<_FocusableSwitchCard> createState() => _FocusableSwitchCardState();
}

class _FocusableSwitchCardState extends State<_FocusableSwitchCard> {
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant _FocusableSwitchCard oldWidget) {
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;

        if (event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter) {
          widget.onChanged(!widget.value);
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: _isFocused
              ? Border.all(color: colorScheme.primary, width: 2)
              : null,
          boxShadow: _isFocused
              ? [
                  BoxShadow(
                    color: colorScheme.primary.withValues(alpha: 0.2),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Card(
          margin: EdgeInsets.zero,
          color: _isFocused ? colorScheme.primaryContainer : null,
          child: SwitchListTile(
            title: Text(
              widget.title,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: _isFocused ? colorScheme.onPrimaryContainer : null,
              ),
            ),
            subtitle: Text(
              widget.subtitle,
              style: TextStyle(
                fontSize: 13,
                color: _isFocused ? colorScheme.onPrimaryContainer.withValues(alpha: 0.8) : null,
              ),
            ),
            secondary: Icon(
              widget.icon,
              color: _isFocused ? colorScheme.onPrimaryContainer : widget.iconColor,
            ),
            value: widget.value,
            onChanged: widget.onChanged,
          ),
        ),
      ),
    );
  }
}

/// TV-focusable button with icon and label
class _TvFocusableButton extends StatefulWidget {
  const _TvFocusableButton({
    required this.focusNode,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.onLeftArrow,
  });

  final FocusNode focusNode;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final VoidCallback? onLeftArrow;

  @override
  State<_TvFocusableButton> createState() => _TvFocusableButtonState();
}

class _TvFocusableButtonState extends State<_TvFocusableButton> {
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant _TvFocusableButton oldWidget) {
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

        return KeyEventResult.ignored;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: _isFocused
              ? Border.all(color: colorScheme.primary, width: 2)
              : null,
          boxShadow: _isFocused
              ? [
                  BoxShadow(
                    color: colorScheme.primary.withValues(alpha: 0.3),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: FilledButton.icon(
          onPressed: widget.onPressed,
          icon: Icon(widget.icon),
          label: Text(widget.label),
          style: FilledButton.styleFrom(
            backgroundColor: _isFocused ? colorScheme.primary : null,
          ),
        ),
      ),
    );
  }
}

/// Focusable favorite subreddit tile with star and delete buttons
class _FocusableFavoriteTile extends StatefulWidget {
  const _FocusableFavoriteTile({
    required this.subreddit,
    required this.isDefault,
    this.starFocusNode,
    this.deleteFocusNode,
    required this.onSetDefault,
    required this.onDelete,
  });

  final String subreddit;
  final bool isDefault;
  final FocusNode? starFocusNode;
  final FocusNode? deleteFocusNode;
  final VoidCallback onSetDefault;
  final VoidCallback onDelete;

  @override
  State<_FocusableFavoriteTile> createState() => _FocusableFavoriteTileState();
}

class _FocusableFavoriteTileState extends State<_FocusableFavoriteTile> {
  bool _starFocused = false;
  bool _deleteFocused = false;

  @override
  void initState() {
    super.initState();
    widget.starFocusNode?.addListener(_onStarFocusChange);
    widget.deleteFocusNode?.addListener(_onDeleteFocusChange);
  }

  @override
  void didUpdateWidget(covariant _FocusableFavoriteTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.starFocusNode != widget.starFocusNode) {
      oldWidget.starFocusNode?.removeListener(_onStarFocusChange);
      widget.starFocusNode?.addListener(_onStarFocusChange);
    }
    if (oldWidget.deleteFocusNode != widget.deleteFocusNode) {
      oldWidget.deleteFocusNode?.removeListener(_onDeleteFocusChange);
      widget.deleteFocusNode?.addListener(_onDeleteFocusChange);
    }
  }

  @override
  void dispose() {
    widget.starFocusNode?.removeListener(_onStarFocusChange);
    widget.deleteFocusNode?.removeListener(_onDeleteFocusChange);
    super.dispose();
  }

  void _onStarFocusChange() {
    if (mounted) {
      setState(() => _starFocused = widget.starFocusNode?.hasFocus ?? false);
    }
  }

  void _onDeleteFocusChange() {
    if (mounted) {
      setState(() => _deleteFocused = widget.deleteFocusNode?.hasFocus ?? false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isAnyFocused = _starFocused || _deleteFocused;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        color: isAnyFocused ? colorScheme.primaryContainer.withValues(alpha: 0.3) : null,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        leading: Icon(
          widget.isDefault ? Icons.star : Icons.tag,
          color: widget.isDefault ? Colors.amber : null,
        ),
        title: Text('r/${widget.subreddit}'),
        subtitle: widget.isDefault
            ? const Text(
                'Default subreddit',
                style: TextStyle(color: Colors.amber),
              )
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _FocusableIconButton(
              focusNode: widget.starFocusNode,
              icon: widget.isDefault ? Icons.star : Icons.star_border,
              color: widget.isDefault ? Colors.amber : null,
              tooltip: widget.isDefault ? 'Remove default' : 'Set as default',
              onPressed: widget.onSetDefault,
              onRightArrow: () => widget.deleteFocusNode?.requestFocus(),
            ),
            _FocusableIconButton(
              focusNode: widget.deleteFocusNode,
              icon: Icons.delete_outline,
              tooltip: 'Remove from favorites',
              onPressed: widget.onDelete,
              onLeftArrow: () => widget.starFocusNode?.requestFocus(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Focusable icon button for TV navigation
class _FocusableIconButton extends StatefulWidget {
  const _FocusableIconButton({
    this.focusNode,
    required this.icon,
    this.color,
    this.tooltip,
    required this.onPressed,
    this.onLeftArrow,
    this.onRightArrow,
  });

  final FocusNode? focusNode;
  final IconData icon;
  final Color? color;
  final String? tooltip;
  final VoidCallback onPressed;
  final VoidCallback? onLeftArrow;
  final VoidCallback? onRightArrow;

  @override
  State<_FocusableIconButton> createState() => _FocusableIconButtonState();
}

class _FocusableIconButtonState extends State<_FocusableIconButton> {
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode?.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant _FocusableIconButton oldWidget) {
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

        if (event.logicalKey == LogicalKeyboardKey.arrowRight && widget.onRightArrow != null) {
          widget.onRightArrow!();
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: _isFocused
              ? Border.all(color: colorScheme.primary, width: 2)
              : null,
          boxShadow: _isFocused
              ? [
                  BoxShadow(
                    color: colorScheme.primary.withValues(alpha: 0.3),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: IconButton(
          icon: Icon(
            widget.icon,
            color: _isFocused ? colorScheme.primary : widget.color,
          ),
          tooltip: widget.tooltip,
          onPressed: widget.onPressed,
          style: IconButton.styleFrom(
            backgroundColor: _isFocused ? colorScheme.primaryContainer : null,
          ),
        ),
      ),
    );
  }
}
