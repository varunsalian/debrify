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
    super.dispose();
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
            Card(
              child: SwitchListTile(
                title: const Text(
                  'Allow NSFW Content',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                subtitle: Text(
                  _allowNsfw
                      ? 'NSFW subreddits and content are visible'
                      : 'NSFW content is hidden',
                  style: const TextStyle(fontSize: 13),
                ),
                secondary: Icon(
                  _allowNsfw ? Icons.visibility : Icons.visibility_off,
                  color: _allowNsfw ? Colors.red : null,
                ),
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
            Row(
              children: [
                Expanded(
                  child: _TvFriendlyTextField(
                    controller: _subredditController,
                    focusNode: _subredditInputFocusNode,
                    labelText: 'Subreddit name',
                    hintText: 'e.g., videos',
                    prefixIcon: const Icon(Icons.tag),
                    onSubmitted: (_) => _addFavoriteSubreddit(),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  focusNode: _addButtonFocusNode,
                  onPressed: _addFavoriteSubreddit,
                  icon: const Icon(Icons.add),
                  label: const Text('Add'),
                ),
              ],
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
                  children: _favoriteSubreddits.map((subreddit) {
                    final isDefault = _defaultSubreddit == subreddit;
                    return ListTile(
                      leading: Icon(
                        isDefault ? Icons.star : Icons.tag,
                        color: isDefault ? Colors.amber : null,
                      ),
                      title: Text('r/$subreddit'),
                      subtitle: isDefault
                          ? const Text(
                              'Default subreddit',
                              style: TextStyle(color: Colors.amber),
                            )
                          : null,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(
                              isDefault ? Icons.star : Icons.star_border,
                              color: isDefault ? Colors.amber : null,
                            ),
                            tooltip: isDefault ? 'Remove default' : 'Set as default',
                            onPressed: () => _setDefaultSubreddit(
                              isDefault ? null : subreddit,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Remove from favorites',
                            onPressed: () => _removeFavoriteSubreddit(subreddit),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
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
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String labelText;
  final String hintText;
  final Widget prefixIcon;
  final ValueChanged<String>? onSubmitted;

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

    final key = event.logicalKey;
    final text = widget.controller.text;
    final selection = widget.controller.selection;
    final textLength = text.length;
    final isTextEmpty = textLength == 0;

    final isSelectionValid = selection.isValid && selection.baseOffset >= 0;
    final isAtStart =
        !isSelectionValid ||
        (selection.baseOffset == 0 && selection.extentOffset == 0);
    final isAtEnd =
        !isSelectionValid ||
        (selection.baseOffset == textLength &&
            selection.extentOffset == textLength);

    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.browserBack) {
      final ctx = node.context;
      if (ctx != null) {
        FocusScope.of(ctx).previousFocus();
        return KeyEventResult.handled;
      }
    }

    if (key == LogicalKeyboardKey.arrowUp) {
      if (isTextEmpty || isAtStart) {
        final ctx = node.context;
        if (ctx != null) {
          FocusScope.of(ctx).focusInDirection(TraversalDirection.up);
          return KeyEventResult.handled;
        }
      }
    }

    if (key == LogicalKeyboardKey.arrowDown) {
      if (isTextEmpty || isAtEnd) {
        final ctx = node.context;
        if (ctx != null) {
          FocusScope.of(ctx).focusInDirection(TraversalDirection.down);
          return KeyEventResult.handled;
        }
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
