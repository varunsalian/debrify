import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/iptv_playlist.dart';
import '../../services/iptv_service.dart';
import '../../services/storage_service.dart';

class IptvSettingsPage extends StatefulWidget {
  const IptvSettingsPage({super.key});

  @override
  State<IptvSettingsPage> createState() => _IptvSettingsPageState();
}

class _IptvSettingsPageState extends State<IptvSettingsPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _urlController = TextEditingController();
  final FocusNode _backButtonFocusNode = FocusNode(debugLabel: 'iptv-back-button');
  final FocusNode _nameInputFocusNode = FocusNode(debugLabel: 'iptv-name-input');
  final FocusNode _urlInputFocusNode = FocusNode(debugLabel: 'iptv-url-input');
  final FocusNode _addButtonFocusNode = FocusNode(debugLabel: 'iptv-add-button');

  // Focus nodes for playlist items (2 per item: star + delete)
  final List<FocusNode> _playlistFocusNodes = [];

  List<IptvPlaylist> _playlists = [];
  String? _defaultPlaylistId;
  bool _loading = true;
  bool _isAdding = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _backButtonFocusNode.dispose();
    _nameInputFocusNode.dispose();
    _urlInputFocusNode.dispose();
    _addButtonFocusNode.dispose();
    for (final node in _playlistFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _ensureFocusNodes() {
    // 2 focus nodes per playlist (star button + delete button)
    final needed = _playlists.length * 2;

    while (_playlistFocusNodes.length > needed) {
      _playlistFocusNodes.removeLast().dispose();
    }

    while (_playlistFocusNodes.length < needed) {
      final index = _playlistFocusNodes.length;
      _playlistFocusNodes.add(FocusNode(debugLabel: 'iptv-playlist-$index'));
    }
  }

  Future<void> _loadSettings() async {
    final playlists = await StorageService.getIptvPlaylists();
    final defaultId = await StorageService.getIptvDefaultPlaylist();

    if (!mounted) return;

    setState(() {
      _playlists = playlists;
      _defaultPlaylistId = defaultId;
      _loading = false;
    });
    _ensureFocusNodes();
  }

  Future<void> _addPlaylist() async {
    final name = _nameController.text.trim();
    final url = _urlController.text.trim();

    if (name.isEmpty) {
      _showSnackBar('Please enter a playlist name');
      return;
    }

    if (url.isEmpty) {
      _showSnackBar('Please enter a playlist URL');
      return;
    }

    if (!IptvService.isValidPlaylistUrl(url)) {
      _showSnackBar('Please enter a valid HTTP/HTTPS URL');
      return;
    }

    // Check for duplicate URL
    if (_playlists.any((p) => p.url == url)) {
      _showSnackBar('This playlist URL already exists');
      return;
    }

    setState(() => _isAdding = true);

    // Validate URL by trying to fetch it
    final result = await IptvService.instance.fetchPlaylist(url);

    if (!mounted) return;

    if (result.hasError) {
      setState(() => _isAdding = false);
      _showSnackBar('Failed to load playlist: ${result.error}');
      return;
    }

    if (result.isEmpty) {
      setState(() => _isAdding = false);
      _showSnackBar('Playlist is empty or invalid');
      return;
    }

    // Create new playlist
    final playlist = IptvPlaylist(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      url: url,
      addedAt: DateTime.now(),
    );

    final newPlaylists = [..._playlists, playlist];
    await StorageService.setIptvPlaylists(newPlaylists);

    setState(() {
      _playlists = newPlaylists;
      _nameController.clear();
      _urlController.clear();
      _isAdding = false;
    });
    _ensureFocusNodes();

    _showSnackBar('Added "$name" (${result.channels.length} channels)', isError: false);
  }

  Future<void> _removePlaylist(IptvPlaylist playlist) async {
    final newPlaylists = _playlists.where((p) => p.id != playlist.id).toList();
    await StorageService.setIptvPlaylists(newPlaylists);

    // If removed playlist was the default, clear default
    if (_defaultPlaylistId == playlist.id) {
      await StorageService.setIptvDefaultPlaylist(null);
      setState(() => _defaultPlaylistId = null);
    }

    // Clear cache for this playlist
    IptvService.instance.clearCache(playlist.url);

    // Remove favorites that belonged to this playlist
    await StorageService.removeIptvFavoritesByPlaylistId(playlist.id);

    setState(() => _playlists = newPlaylists);
    _ensureFocusNodes();
    _showSnackBar('Removed "${playlist.name}"', isError: false);
  }

  Future<void> _setDefaultPlaylist(IptvPlaylist? playlist) async {
    await StorageService.setIptvDefaultPlaylist(playlist?.id);
    setState(() => _defaultPlaylistId = playlist?.id);
    _showSnackBar(
      playlist != null ? 'Default set to "${playlist.name}"' : 'Default cleared',
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

  List<Widget> _buildPlaylistsList() {
    final items = <Widget>[];

    for (int i = 0; i < _playlists.length; i++) {
      final playlist = _playlists[i];
      final isDefault = _defaultPlaylistId == playlist.id;
      final starFocusIndex = i * 2;
      final deleteFocusIndex = i * 2 + 1;

      items.add(
        FocusTraversalOrder(
          order: NumericFocusOrder(4.0 + i),
          child: _FocusablePlaylistTile(
            playlist: playlist,
            isDefault: isDefault,
            starFocusNode: starFocusIndex < _playlistFocusNodes.length
                ? _playlistFocusNodes[starFocusIndex]
                : null,
            deleteFocusNode: deleteFocusIndex < _playlistFocusNodes.length
                ? _playlistFocusNodes[deleteFocusIndex]
                : null,
            onSetDefault: () => _setDefaultPlaylist(isDefault ? null : playlist),
            onDelete: () => _removePlaylist(playlist),
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
      appBar: AppBar(
        title: const Text('IPTV Playlists'),
        leading: _TvFocusableBackButton(
          focusNode: _backButtonFocusNode,
          onDownArrow: () => _nameInputFocusNode.requestFocus(),
        ),
      ),
      body: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'IPTV M3U Playlists',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Add M3U playlist URLs to watch IPTV channels.',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 24),

            // Add playlist form
            Text(
              'Add Playlist',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            // Name input
            FocusTraversalOrder(
              order: const NumericFocusOrder(1),
              child: _TvFriendlyTextField(
                controller: _nameController,
                focusNode: _nameInputFocusNode,
                labelText: 'Playlist Name',
                hintText: 'e.g., My IPTV',
                prefixIcon: const Icon(Icons.label_outline),
                onUpArrow: () => _backButtonFocusNode.requestFocus(),
                onDownArrow: () => _urlInputFocusNode.requestFocus(),
              ),
            ),
            const SizedBox(height: 12),

            // URL input
            FocusTraversalOrder(
              order: const NumericFocusOrder(2),
              child: _TvFriendlyTextField(
                controller: _urlController,
                focusNode: _urlInputFocusNode,
                labelText: 'Playlist URL',
                hintText: 'https://example.com/playlist.m3u',
                prefixIcon: const Icon(Icons.link),
                onUpArrow: () => _nameInputFocusNode.requestFocus(),
                onDownArrow: () => _addButtonFocusNode.requestFocus(),
                onRightArrow: () => _addButtonFocusNode.requestFocus(),
                onSubmitted: (_) => _addPlaylist(),
              ),
            ),
            const SizedBox(height: 12),

            // Add button
            FocusTraversalOrder(
              order: const NumericFocusOrder(3),
              child: Align(
                alignment: Alignment.centerRight,
                child: _TvFocusableButton(
                  focusNode: _addButtonFocusNode,
                  icon: _isAdding ? Icons.hourglass_empty : Icons.add,
                  label: _isAdding ? 'Adding...' : 'Add Playlist',
                  onPressed: _isAdding ? () {} : _addPlaylist,
                  onLeftArrow: () => _urlInputFocusNode.requestFocus(),
                  onUpArrow: () => _urlInputFocusNode.requestFocus(),
                  onDownArrow: _playlists.isNotEmpty && _playlistFocusNodes.isNotEmpty
                      ? () => _playlistFocusNodes[0].requestFocus()
                      : null,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Playlists list
            Text(
              'Your Playlists',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap the star to set a default playlist.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),

            if (_playlists.isEmpty)
              Card(
                child: Padding(
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
                        'No playlists yet',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Add an M3U playlist URL above',
                        style: theme.textTheme.bodySmall?.copyWith(
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
                  children: _buildPlaylistsList(),
                ),
              ),
            const SizedBox(height: 24),

            // Default Playlist Info
            if (_defaultPlaylistId != null)
              Card(
                color: Colors.amber.withOpacity(0.1),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Colors.amber),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Your default playlist will load automatically when you select IPTV.',
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
    this.onLeftArrow,
    this.onRightArrow,
    this.onUpArrow,
    this.onDownArrow,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String labelText;
  final String hintText;
  final Widget prefixIcon;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onLeftArrow;
  final VoidCallback? onRightArrow;
  final VoidCallback? onUpArrow;
  final VoidCallback? onDownArrow;

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
  void didUpdateWidget(covariant _TvFriendlyTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_handleFocusChange);
      widget.focusNode.addListener(_handleFocusChange);
    }
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
    if (!mounted) return KeyEventResult.ignored;

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

    // Back/Escape - unfocus the text field
    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.browserBack) {
      widget.focusNode.unfocus();
      return KeyEventResult.handled;
    }

    // Navigate up - always allow escaping up (TV pattern)
    if (key == LogicalKeyboardKey.arrowUp) {
      if (widget.onUpArrow != null) {
        widget.onUpArrow!();
        return KeyEventResult.handled;
      }
    }

    // Navigate down - always allow escaping down (TV pattern)
    if (key == LogicalKeyboardKey.arrowDown) {
      if (widget.onDownArrow != null) {
        widget.onDownArrow!();
        return KeyEventResult.handled;
      }
    }

    // Navigate right - only when at end of text
    if (key == LogicalKeyboardKey.arrowRight) {
      if ((isTextEmpty || isAtEnd) && widget.onRightArrow != null) {
        widget.onRightArrow!();
        return KeyEventResult.handled;
      }
    }

    // Navigate left - only when at start of text
    if (key == LogicalKeyboardKey.arrowLeft) {
      if ((isTextEmpty || isAtStart) && widget.onLeftArrow != null) {
        widget.onLeftArrow!();
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: _handleKeyEvent,
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
                    color: theme.colorScheme.primary.withOpacity(0.2),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: TextField(
          controller: widget.controller,
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

/// TV-focusable button with icon and label
class _TvFocusableButton extends StatefulWidget {
  const _TvFocusableButton({
    required this.focusNode,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.onLeftArrow,
    this.onUpArrow,
    this.onDownArrow,
  });

  final FocusNode focusNode;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final VoidCallback? onLeftArrow;
  final VoidCallback? onUpArrow;
  final VoidCallback? onDownArrow;

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

        if (event.logicalKey == LogicalKeyboardKey.arrowUp && widget.onUpArrow != null) {
          widget.onUpArrow!();
          return KeyEventResult.handled;
        }

        if (event.logicalKey == LogicalKeyboardKey.arrowDown && widget.onDownArrow != null) {
          widget.onDownArrow!();
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
                    color: colorScheme.primary.withOpacity(0.3),
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

/// Focusable playlist tile with star and delete buttons
class _FocusablePlaylistTile extends StatefulWidget {
  const _FocusablePlaylistTile({
    required this.playlist,
    required this.isDefault,
    this.starFocusNode,
    this.deleteFocusNode,
    required this.onSetDefault,
    required this.onDelete,
  });

  final IptvPlaylist playlist;
  final bool isDefault;
  final FocusNode? starFocusNode;
  final FocusNode? deleteFocusNode;
  final VoidCallback onSetDefault;
  final VoidCallback onDelete;

  @override
  State<_FocusablePlaylistTile> createState() => _FocusablePlaylistTileState();
}

class _FocusablePlaylistTileState extends State<_FocusablePlaylistTile> {
  bool _starFocused = false;
  bool _deleteFocused = false;

  @override
  void initState() {
    super.initState();
    widget.starFocusNode?.addListener(_onStarFocusChange);
    widget.deleteFocusNode?.addListener(_onDeleteFocusChange);
  }

  @override
  void didUpdateWidget(covariant _FocusablePlaylistTile oldWidget) {
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
        color: isAnyFocused ? colorScheme.primaryContainer.withOpacity(0.3) : null,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        leading: Icon(
          widget.isDefault ? Icons.star : Icons.playlist_play,
          color: widget.isDefault ? Colors.amber : null,
        ),
        title: Text(widget.playlist.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.playlist.url,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            if (widget.isDefault)
              const Text(
                'Default playlist',
                style: TextStyle(color: Colors.amber, fontSize: 12),
              ),
          ],
        ),
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
              tooltip: 'Remove playlist',
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
                    color: colorScheme.primary.withOpacity(0.3),
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

/// TV-focusable back button for AppBar
class _TvFocusableBackButton extends StatefulWidget {
  const _TvFocusableBackButton({
    required this.focusNode,
    this.onDownArrow,
  });

  final FocusNode focusNode;
  final VoidCallback? onDownArrow;

  @override
  State<_TvFocusableBackButton> createState() => _TvFocusableBackButtonState();
}

class _TvFocusableBackButtonState extends State<_TvFocusableBackButton> {
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant _TvFocusableBackButton oldWidget) {
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

  void _goBack() {
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;

        // Select/Enter to go back
        if (event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter) {
          _goBack();
          return KeyEventResult.handled;
        }

        // Back button to go back
        if (event.logicalKey == LogicalKeyboardKey.goBack ||
            event.logicalKey == LogicalKeyboardKey.browserBack ||
            event.logicalKey == LogicalKeyboardKey.escape) {
          _goBack();
          return KeyEventResult.handled;
        }

        // Down arrow to go to name field
        if (event.logicalKey == LogicalKeyboardKey.arrowDown && widget.onDownArrow != null) {
          widget.onDownArrow!();
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: _isFocused
              ? Border.all(color: colorScheme.primary, width: 2)
              : null,
          boxShadow: _isFocused
              ? [
                  BoxShadow(
                    color: colorScheme.primary.withOpacity(0.3),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: _isFocused ? colorScheme.primary : null,
          ),
          tooltip: 'Go back',
          onPressed: _goBack,
          style: IconButton.styleFrom(
            backgroundColor: _isFocused ? colorScheme.primaryContainer : null,
          ),
        ),
      ),
    );
  }
}
