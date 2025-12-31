import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/community/community_channel_model.dart';
import '../../../services/community/community_channels_service.dart';

/// Dialog for browsing and selecting community shared channels
class CommunityChannelsDialog extends StatefulWidget {
  final bool isAndroidTv;

  const CommunityChannelsDialog({required this.isAndroidTv});

  @override
  State<CommunityChannelsDialog> createState() =>
      CommunityChannelsDialogState();
}

class CommunityChannelsDialogState extends State<CommunityChannelsDialog> {
  final TextEditingController _repoUrlController = TextEditingController(
    text: CommunityChannelsService.defaultRepoUrl,
  );
  final FocusNode _repoUrlFocusNode = FocusNode();
  final FocusNode _fetchButtonFocusNode = FocusNode();
  final FocusNode _selectAllFocusNode = FocusNode();
  final FocusNode _cancelButtonFocusNode = FocusNode();
  final FocusNode _importButtonFocusNode = FocusNode();
  final ScrollController _channelListScrollController = ScrollController();

  CommunityChannelManifest? _manifest;
  bool _isLoading = false;
  String? _errorMessage;
  bool _selectAll = false;
  Map<String, FocusNode> _channelFocusNodes = {};
  bool _isFetching = false;

  @override
  void initState() {
    super.initState();
    // Set up focus nodes for keyboard navigation
    if (widget.isAndroidTv) {
      _setupFocusNavigation();
    }
    // Auto-fetch channels on dialog open
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchChannels();
    });
  }

  void _setupFocusNavigation() {
    // Setup DPAD navigation for URL input field
    _repoUrlFocusNode.onKeyEvent = (node, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;

      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.arrowDown) {
        _fetchButtonFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowRight &&
          _repoUrlController.selection.baseOffset ==
              _repoUrlController.text.length) {
        _fetchButtonFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };

    // Setup DPAD navigation for fetch button
    _fetchButtonFocusNode.onKeyEvent = (node, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;

      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.arrowUp) {
        _repoUrlFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowLeft) {
        _repoUrlFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        if (_manifest != null && _manifest!.channels.isNotEmpty) {
          _selectAllFocusNode.requestFocus();
        } else {
          _cancelButtonFocusNode.requestFocus();
        }
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };

    // Setup DPAD navigation for select all checkbox
    _selectAllFocusNode.onKeyEvent = (node, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;

      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.arrowUp) {
        _fetchButtonFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown &&
          _channelFocusNodes.isNotEmpty) {
        _channelFocusNodes.values.first.requestFocus();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter) {
        setState(() {
          _toggleSelectAll();
        });
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };

    // Setup DPAD navigation for Cancel button
    _cancelButtonFocusNode.onKeyEvent = (node, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;

      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.arrowUp) {
        if (_channelFocusNodes.isNotEmpty) {
          _channelFocusNodes.values.last.requestFocus();
        } else if (_manifest != null) {
          _selectAllFocusNode.requestFocus();
        } else {
          _fetchButtonFocusNode.requestFocus();
        }
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowRight) {
        _importButtonFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };

    // Setup DPAD navigation for Import button
    _importButtonFocusNode.onKeyEvent = (node, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;

      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.arrowUp) {
        if (_channelFocusNodes.isNotEmpty) {
          _channelFocusNodes.values.last.requestFocus();
        } else if (_manifest != null) {
          _selectAllFocusNode.requestFocus();
        } else {
          _fetchButtonFocusNode.requestFocus();
        }
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowLeft) {
        _cancelButtonFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter) {
        // Trigger import action if there are selected channels
        final selectedChannels = _getSelectedChannels();
        if (selectedChannels.isNotEmpty) {
          Navigator.of(context).pop(selectedChannels);
        }
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };
  }

  @override
  void dispose() {
    _repoUrlController.dispose();
    _repoUrlFocusNode.dispose();
    _fetchButtonFocusNode.dispose();
    _selectAllFocusNode.dispose();
    _cancelButtonFocusNode.dispose();
    _importButtonFocusNode.dispose();
    _channelListScrollController.dispose();
    for (final node in _channelFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _toggleSelectAll() {
    // Track which specific node was focused by finding the focused channel ID
    String? focusedChannelId;
    if (widget.isAndroidTv) {
      for (final entry in _channelFocusNodes.entries) {
        if (entry.value.hasFocus) {
          focusedChannelId = entry.key;
          break;
        }
      }
    }

    setState(() {
      _selectAll = !_selectAll;
      if (_manifest != null) {
        for (final channel in _manifest!.channels) {
          channel.isSelected = _selectAll;
        }
      }
    });

    // Restore focus to the specific channel that was focused
    if (widget.isAndroidTv && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        if (focusedChannelId != null) {
          final node = _channelFocusNodes[focusedChannelId];
          _safeRequestFocus(node);
        } else {
          // Fallback to select all if no channel was focused
          _safeRequestFocus(_selectAllFocusNode);
        }
      });
    }
  }

  void _toggleChannelSelection(CommunityChannel channel) {
    // Track the specific channel ID that's being toggled
    final channelId = channel.id;

    setState(() {
      channel.isSelected = !channel.isSelected;
      // Update select all state if needed
      if (_manifest != null) {
        _selectAll = _manifest!.channels.every((c) => c.isSelected);
      }
    });

    // Restore focus to the specific channel that was interacted with
    if (widget.isAndroidTv && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        // Use the specific channel's focus node to avoid race conditions
        final node = _channelFocusNodes[channelId];
        _safeRequestFocus(node);
      });
    }
  }

  void _safeRequestFocus(FocusNode? node) {
    if (node != null && mounted) {
      try {
        node.requestFocus();
      } catch (e) {
        // Silently catch any disposal race conditions
        debugPrint('[CommunityChannelsDialog] Failed to request focus: $e');
      }
    }
  }

  Future<void> _fetchChannels() async {
    // Prevent concurrent fetches
    if (_isFetching) {
      return;
    }

    final url = _repoUrlController.text.trim();
    if (url.isEmpty) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Please enter a repository URL';
      });
      return;
    }

    if (!CommunityChannelsService.isValidRepoUrl(url)) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Please enter a valid URL';
      });
      return;
    }

    _isFetching = true;

    // Keep reference to old focus nodes but DON'T dispose them yet
    final oldFocusNodes = Map<String, FocusNode>.from(_channelFocusNodes);

    if (!mounted) {
      _isFetching = false;
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _manifest = null;
      _selectAll = false;
    });

    try {
      final manifest = await CommunityChannelsService.fetchManifest(url);

      if (!mounted) {
        _isFetching = false;
        return;
      }

      // Create NEW focus nodes BEFORE disposing old ones
      final newFocusNodes = <String, FocusNode>{};
      for (final channel in manifest.channels) {
        if (!mounted) {
          // Clean up any nodes we created if widget was disposed
          for (final node in newFocusNodes.values) {
            node.dispose();
          }
          _isFetching = false;
          return;
        }
        newFocusNodes[channel.id] = FocusNode();
      }

      // Only proceed if still mounted
      if (!mounted) {
        // Dispose new nodes if widget was disposed during async operation
        for (final node in newFocusNodes.values) {
          node.dispose();
        }
        _isFetching = false;
        return;
      }

      // Atomically swap the focus nodes
      _channelFocusNodes = newFocusNodes;

      // Setup navigation between channel items
      if (widget.isAndroidTv) {
        _setupChannelFocusNavigation(manifest.channels);
      }

      if (!mounted) {
        _isFetching = false;
        return;
      }

      setState(() {
        _manifest = manifest;
        _isLoading = false;
      });

      // Dispose old nodes AFTER setState completes and new nodes are in use
      // Schedule disposal for next frame to ensure rebuild is complete
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          for (final node in oldFocusNodes.values) {
            node.dispose();
          }
        });
      }

      _isFetching = false;
    } catch (e) {
      if (!mounted) {
        _isFetching = false;
        return;
      }

      setState(() {
        _errorMessage = CommunityChannelsService.getErrorMessage(e);
        _isLoading = false;
      });

      _isFetching = false;
    }
  }

  void _setupChannelFocusNavigation(List<CommunityChannel> channels) {
    for (int i = 0; i < channels.length; i++) {
      final channel = channels[i];
      final node = _channelFocusNodes[channel.id];
      if (node == null) continue;

      node.onKeyEvent = (focusNode, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;

        final key = event.logicalKey;

        // Navigate up
        if (key == LogicalKeyboardKey.arrowUp) {
          if (i > 0) {
            _channelFocusNodes[channels[i - 1].id]?.requestFocus();
          } else {
            _selectAllFocusNode.requestFocus();
          }
          return KeyEventResult.handled;
        }

        // Navigate down
        if (key == LogicalKeyboardKey.arrowDown) {
          if (i < channels.length - 1) {
            _channelFocusNodes[channels[i + 1].id]?.requestFocus();
          } else {
            _cancelButtonFocusNode.requestFocus();
          }
          return KeyEventResult.handled;
        }

        // Toggle selection with Enter/Select
        if (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter) {
          _toggleChannelSelection(channel);
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      };
    }
  }

  List<CommunityChannel> _getSelectedChannels() {
    if (_manifest == null) return [];
    return _manifest!.channels.where((c) => c.isSelected).toList();
  }

  Widget _buildChannelTile(CommunityChannel channel) {
    final focusNode = _channelFocusNodes[channel.id];

    // Handle null focusNode gracefully - return simple tile without focus handling
    if (focusNode == null) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border.all(
            color: Theme.of(context).dividerColor.withOpacity(0.3),
            width: 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: CheckboxListTile(
          value: channel.isSelected,
          onChanged: widget.isAndroidTv ? null : (_) => _toggleChannelSelection(channel),
          activeColor: Theme.of(context).primaryColor,
          checkColor: Colors.white,
          dense: true,
          visualDensity: VisualDensity.compact,
          title: Text(channel.name),
          subtitle: Text(channel.category),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 4,
          ),
        ),
      );
    }

    // Define category colors for better visual appeal
    Color getCategoryColor(String category) {
      switch (category.toLowerCase()) {
        case 'movies':
          return const Color(0xFF9C27B0); // Purple
        case 'series':
        case 'tv':
          return const Color(0xFF2196F3); // Blue
        case 'sports':
          return const Color(0xFF4CAF50); // Green
        case 'news':
          return const Color(0xFFFF5722); // Deep Orange
        case 'kids':
          return const Color(0xFFFFC107); // Amber
        case 'documentary':
          return const Color(0xFF00BCD4); // Cyan
        case 'music':
          return const Color(0xFFE91E63); // Pink
        default:
          return const Color(0xFF607D8B); // Blue Grey
      }
    }

    return Focus(
      focusNode: focusNode,
      onFocusChange: (hasFocus) {
        if (hasFocus && mounted) {
          setState(() {}); // Rebuild to show focus highlight

          // Auto-scroll to make focused item visible
          if (widget.isAndroidTv) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              // Check all conditions before attempting scroll
              if (!mounted) return;
              if (!_channelListScrollController.hasClients) return;

              final context = focusNode.context;
              if (context == null) return;

              final renderObject = context.findRenderObject();
              if (renderObject == null || !renderObject.attached) return;

              try {
                _channelListScrollController.position.ensureVisible(
                  renderObject,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  alignment: 0.5, // Center the item in the viewport
                );
              } catch (e) {
                debugPrint('[CommunityChannelsDialog] Scroll error: $e');
              }
            });
          }
        }
      },
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          final categoryColor = getCategoryColor(channel.category);

          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
            decoration: BoxDecoration(
              color: hasFocus
                  ? const Color(0xFF00E5FF).withOpacity(0.25)
                  : Theme.of(context).colorScheme.surface,
              border: Border.all(
                color: hasFocus
                    ? const Color(0xFF00E5FF)
                    : Theme.of(context).dividerColor.withOpacity(0.3),
                width: hasFocus ? 3 : 1,
              ),
              borderRadius: BorderRadius.circular(8),
              boxShadow: hasFocus
                  ? [
                      BoxShadow(
                        color: const Color(0xFF00E5FF).withOpacity(0.5),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 2,
                        offset: const Offset(0, 1),
                      ),
                    ],
            ),
            child: CheckboxListTile(
              value: channel.isSelected,
              onChanged: widget.isAndroidTv ? null : (_) => _toggleChannelSelection(channel),
              activeColor: Theme.of(context).primaryColor,
              checkColor: Colors.white,
              dense: true,
              visualDensity: VisualDensity.compact,
              title: Text(
                channel.name,
                style: TextStyle(
                  fontWeight: hasFocus ? FontWeight.bold : FontWeight.w500,
                  fontSize: hasFocus ? 15 : 14,
                  color: hasFocus
                      ? Theme.of(context).colorScheme.onSurface
                      : Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.9),
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (channel.description.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      channel.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              categoryColor.withOpacity(hasFocus ? 0.9 : 0.8),
                              categoryColor.withOpacity(hasFocus ? 1.0 : 0.9),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: categoryColor.withOpacity(0.2),
                              blurRadius: 2,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Text(
                          channel.category.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                      if (channel.updated.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Icon(
                          Icons.update,
                          size: 12,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.5),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          channel.updated,
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.5),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 4,
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedCount = _getSelectedChannels().length;
    final totalCount = _manifest?.channels.length ?? 0;

    // Wrap in GestureDetector to absorb taps that land outside the dialog content
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {}, // Absorb taps on the barrier area
      child: Dialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 8,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final screenWidth = MediaQuery.of(context).size.width;
          final screenHeight = MediaQuery.of(context).size.height;
          final isSmallScreen = screenWidth < 500;
          final dialogWidth = screenWidth > 1200 ? 800.0 : (screenWidth > 800 ? 700.0 : screenWidth * 0.95);
          final dialogHeight = screenHeight * (isSmallScreen ? 0.75 : 0.7);

          return Container(
            width: dialogWidth,
            height: dialogHeight,
            padding: EdgeInsets.all(isSmallScreen ? 12 : 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                Row(
                  children: [
                    Icon(
                      Icons.cloud_download,
                      color: Theme.of(context).primaryColor,
                      size: 24,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Community Channels',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Content
                Expanded(
                  child: Padding(
        padding: EdgeInsets.all(isSmallScreen ? 2 : 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // URL Input and Fetch Button
            Container(
              padding: EdgeInsets.all(isSmallScreen ? 4 : 6),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surfaceVariant.withOpacity(0.3),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _repoUrlController,
                      focusNode: _repoUrlFocusNode,
                      style: TextStyle(fontSize: isSmallScreen ? 12 : 14),
                      decoration: InputDecoration(
                        hintText: 'Repository URL',
                        errorText: _errorMessage,
                        prefixIcon: Icon(
                          Icons.link,
                          size: isSmallScreen ? 16 : 20,
                          color: Theme.of(
                            context,
                          ).primaryColor.withOpacity(0.7),
                        ),
                        isDense: true,
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: Theme.of(context).primaryColor,
                            width: 2,
                          ),
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: isSmallScreen ? 8 : 12,
                          vertical: isSmallScreen ? 6 : 8,
                        ),
                      ),
                      autofocus: true,
                      enabled: !_isLoading,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Focus(
                    focusNode: _fetchButtonFocusNode,
                    child: Builder(
                      builder: (context) {
                        final hasFocus = Focus.of(context).hasFocus;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            gradient: LinearGradient(
                              colors: _isLoading
                                  ? [Colors.grey.shade400, Colors.grey.shade500]
                                  : [
                                      const Color(0xFF42A5F5),
                                      const Color(0xFF2196F3),
                                    ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            border: hasFocus ? Border.all(
                              color: const Color(0xFF00E5FF),
                              width: 3,
                            ) : null,
                            boxShadow: hasFocus
                                ? [
                                    BoxShadow(
                                      color: const Color(0xFF00E5FF).withOpacity(0.5),
                                      blurRadius: 12,
                                      spreadRadius: 2,
                                    ),
                                  ]
                                : [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.15),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                          ),
                          child: IconButton(
                            onPressed: _isLoading ? null : _fetchChannels,
                            style: IconButton.styleFrom(
                              padding: const EdgeInsets.all(12),
                              backgroundColor: Colors.transparent,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            icon: _isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.download_rounded, size: 22),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Select All / Channel count - More compact
            if (_manifest != null && _manifest!.channels.isNotEmpty) ...[
              Focus(
                focusNode: _selectAllFocusNode,
                child: Builder(
                  builder: (context) {
                    final hasFocus = Focus.of(context).hasFocus;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        color: hasFocus
                            ? const Color(0xFF00E5FF).withOpacity(0.25)
                            : Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
                        border: Border.all(
                          color: hasFocus
                              ? const Color(0xFF00E5FF)
                              : Theme.of(context).dividerColor.withOpacity(0.3),
                          width: hasFocus ? 3 : 1,
                        ),
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: hasFocus
                            ? [
                                BoxShadow(
                                  color: const Color(0xFF00E5FF).withOpacity(0.5),
                                  blurRadius: 12,
                                  spreadRadius: 2,
                                ),
                              ]
                            : [],
                      ),
                      child: CheckboxListTile(
                        value: _selectAll,
                        onChanged: widget.isAndroidTv ? null : (_) => _toggleSelectAll(),
                        activeColor: Theme.of(context).primaryColor,
                        checkColor: Colors.white,
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        title: Row(
                          children: [
                            Text(
                              'Select All',
                              style: TextStyle(
                                fontWeight: hasFocus
                                    ? FontWeight.bold
                                    : FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: selectedCount > 0
                                    ? Theme.of(
                                        context,
                                      ).primaryColor.withOpacity(0.2)
                                    : Colors.grey.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '$selectedCount / $totalCount',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: selectedCount > 0
                                      ? Theme.of(context).primaryColor
                                      : Colors.grey.shade600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 6),
              Divider(
                color: Theme.of(context).dividerColor.withOpacity(0.2),
                thickness: 0.5,
                height: 1,
              ),
              const SizedBox(height: 6),
            ],

            // Channel List - Optimized padding
            if (_manifest != null && _manifest!.channels.isNotEmpty)
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.background.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.all(4),
                  child: ListView.builder(
                    controller: _channelListScrollController,
                    itemCount: _manifest!.channels.length,
                    cacheExtent: 200.0, // Pre-cache items for smoother scrolling
                    addRepaintBoundaries: true, // Optimize repainting
                    itemBuilder: (context, index) {
                      return RepaintBoundary(
                        child: _buildChannelTile(_manifest!.channels[index]),
                      );
                    },
                  ),
                ),
              )
            else if (_manifest != null && _manifest!.channels.isEmpty)
              const Expanded(
                child: Center(
                  child: Text('No channels found in this repository'),
                ),
              )
            else if (!_isLoading && _errorMessage == null)
              const Expanded(
                child: Center(
                  child: Text(
                    'Enter a repository URL and click "Fetch Channels" to browse available channels',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else if (_errorMessage != null)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 48,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              const Spacer(),
          ],
        ),
                  ),
                ),
                // Action buttons
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Focus(
                      focusNode: _cancelButtonFocusNode,
                      child: Builder(
                        builder: (context) {
                          final hasFocus = Focus.of(context).hasFocus;
                          return Container(
                            decoration: hasFocus ? BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFF00E5FF), width: 3),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF00E5FF).withOpacity(0.5),
                                  blurRadius: 12,
                                  spreadRadius: 2,
                                ),
                              ],
                            ) : null,
                            child: TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                backgroundColor: Colors.grey.shade600,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: Text(
                                'Cancel',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: hasFocus ? FontWeight.bold : FontWeight.w500,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Focus(
                      focusNode: _importButtonFocusNode,
                      child: Builder(
                        builder: (context) {
                          final hasFocus = Focus.of(context).hasFocus;
                          final hasSelection = selectedCount > 0;

                          return Container(
                            decoration: hasFocus ? BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFF00E5FF), width: 3),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF00E5FF).withOpacity(0.5),
                                  blurRadius: 12,
                                  spreadRadius: 2,
                                ),
                              ],
                            ) : null,
                            child: FilledButton(
                              onPressed: hasSelection
                                  ? () => Navigator.of(context).pop(_getSelectedChannels())
                                  : null,
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                backgroundColor: hasSelection
                                    ? const Color(0xFF4CAF50)
                                    : Colors.grey.shade400,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: Text(
                                hasSelection ? 'Import ($selectedCount)' : 'Import',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: hasFocus ? FontWeight.bold : FontWeight.w500,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    ),
    );
  }
}

