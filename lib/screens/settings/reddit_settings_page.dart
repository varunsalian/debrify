import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/analytics_service.dart';
import '../../services/storage_service.dart';
import '../../utils/tv_keys.dart';
import '../../widgets/tv_text_field.dart';
import 'widgets/settings_widgets.dart';

class RedditSettingsPage extends StatefulWidget {
  const RedditSettingsPage({super.key});

  @override
  State<RedditSettingsPage> createState() => _RedditSettingsPageState();
}

class _RedditSettingsPageState extends State<RedditSettingsPage> {
  final TextEditingController _subredditController = TextEditingController();
  final FocusNode _subredditInputFocusNode = FocusNode(
    debugLabel: 'reddit-subreddit-input',
  );
  final FocusNode _addButtonFocusNode = FocusNode(
    debugLabel: 'reddit-add-button',
  );
  final FocusNode _nsfwToggleFocusNode = FocusNode(
    debugLabel: 'reddit-nsfw-toggle',
  );

  // Focus nodes for favorite subreddit items (2 per item: star + delete)
  final List<FocusNode> _favoriteFocusNodes = [];

  bool _allowNsfw = false;
  List<String> _favoriteSubreddits = [];
  String? _defaultSubreddit;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('reddit_settings');
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
    final cleanName = subreddit.replaceFirst(
      RegExp(r'^r/', caseSensitive: false),
      '',
    );

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
    final newFavorites = _favoriteSubreddits
        .where((s) => s != subreddit)
        .toList();
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
        backgroundColor: isError ? kSettingsRed : kSettingsGreen,
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
            onSetDefault: () =>
                _setDefaultSubreddit(isDefault ? null : subreddit),
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
      return const SettingsPageScaffold(
        title: 'Reddit Settings',
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return SettingsPageScaffold(
      title: 'Reddit Settings',
      body: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kSettingsMaxWidth),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const SettingsPageHeader(
                  icon: Icons.forum_rounded,
                  title: 'Reddit Integration',
                  subtitle: 'Browse and play videos from Reddit subreddits.',
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
                    iconColor: _allowNsfw ? kSettingsRed : null,
                    value: _allowNsfw,
                    onChanged: _toggleNsfw,
                  ),
                ),
                const SizedBox(height: 24),

                // Favorite Subreddits
                const Text(
                  'Favorite Subreddits',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Add subreddits for quick access in the filter dropdown.',
                  style: TextStyle(fontSize: 12.5, color: kSettingsDim),
                ),
                const SizedBox(height: 16),

                // Add subreddit input
                FocusTraversalOrder(
                  order: const NumericFocusOrder(2),
                  child: Row(
                    children: [
                      Expanded(
                        child: TvTextField(
                          controller: _subredditController,
                          focusNode: _subredditInputFocusNode,
                          labelText: 'Subreddit name',
                          hintText: 'e.g., videos',
                          prefixIcon: const Icon(Icons.tag),
                          onSubmitted: (_) => _addFavoriteSubreddit(),
                          onRightArrow: () =>
                              _addButtonFocusNode.requestFocus(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      _TvFocusableButton(
                        focusNode: _addButtonFocusNode,
                        icon: Icons.add,
                        label: 'Add',
                        onPressed: _addFavoriteSubreddit,
                        onLeftArrow: () =>
                            _subredditInputFocusNode.requestFocus(),
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
                            color: kSettingsDim2,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No favorite subreddits yet',
                            style: TextStyle(
                              fontSize: 13.5,
                              color: kSettingsDim,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Card(child: Column(children: _buildFavoritesList())),
                const SizedBox(height: 24),

                // Default Subreddit Info
                if (_defaultSubreddit != null)
                  SettingsInfoBanner(
                    text:
                        'r/$_defaultSubreddit will load automatically when you select Reddit.',
                    tone: SettingsBannerTone.warning,
                  ),
              ],
            ),
          ),
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
    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;

        if (isActivateKey(event.logicalKey)) {
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
              ? Border.all(color: kSettingsAccent, width: 2)
              : null,
          boxShadow: _isFocused
              ? [
                  BoxShadow(
                    color: kSettingsAccent.withValues(alpha: 0.2),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Card(
          margin: EdgeInsets.zero,
          color: _isFocused ? kSettingsPanel2 : null,
          child: SwitchListTile(
            title: Text(
              widget.title,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            subtitle: Text(
              widget.subtitle,
              style: TextStyle(fontSize: 13, color: kSettingsDim),
            ),
            secondary: Icon(
              widget.icon,
              color:
                  widget.iconColor ??
                  (_isFocused ? kSettingsAccent2 : kSettingsDim),
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
    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;

        if (isActivateKey(event.logicalKey)) {
          widget.onPressed();
          return KeyEventResult.handled;
        }

        if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
            widget.onLeftArrow != null) {
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
              ? Border.all(color: kSettingsAccent2, width: 2)
              : null,
          boxShadow: _isFocused
              ? [
                  BoxShadow(
                    color: kSettingsAccent.withValues(alpha: 0.3),
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
      setState(
        () => _deleteFocused = widget.deleteFocusNode?.hasFocus ?? false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAnyFocused = _starFocused || _deleteFocused;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        color: isAnyFocused ? kSettingsPanel2 : null,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        leading: Icon(
          widget.isDefault ? Icons.star : Icons.tag,
          color: widget.isDefault ? kSettingsAmber : null,
        ),
        title: Text('r/${widget.subreddit}'),
        subtitle: widget.isDefault
            ? const Text(
                'Default subreddit',
                style: TextStyle(color: kSettingsAmber),
              )
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _FocusableIconButton(
              focusNode: widget.starFocusNode,
              icon: widget.isDefault ? Icons.star : Icons.star_border,
              color: widget.isDefault ? kSettingsAmber : null,
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
    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;

        if (isActivateKey(event.logicalKey)) {
          widget.onPressed();
          return KeyEventResult.handled;
        }

        if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
            widget.onLeftArrow != null) {
          widget.onLeftArrow!();
          return KeyEventResult.handled;
        }

        if (event.logicalKey == LogicalKeyboardKey.arrowRight &&
            widget.onRightArrow != null) {
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
              ? Border.all(color: kSettingsAccent, width: 2)
              : null,
          boxShadow: _isFocused
              ? [
                  BoxShadow(
                    color: kSettingsAccent.withValues(alpha: 0.3),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: IconButton(
          icon: Icon(
            widget.icon,
            color: _isFocused ? kSettingsAccent2 : widget.color,
          ),
          tooltip: widget.tooltip,
          onPressed: widget.onPressed,
          style: IconButton.styleFrom(
            backgroundColor: _isFocused ? kSettingsPanel2 : null,
          ),
        ),
      ),
    );
  }
}
