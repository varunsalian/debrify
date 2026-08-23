import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/community/community_channel_model.dart';
import '../../../services/community/community_channels_service.dart';
import '../../../theme/app_theme_scope.dart';
import '../../../utils/tv_keys.dart';
import '../../../widgets/tv_text_field.dart';
import 'spotlight_dialog.dart';

/// Dialog for browsing and selecting community shared channels
class CommunityChannelsDialog extends StatefulWidget {
  final bool isAndroidTv;

  const CommunityChannelsDialog({super.key, required this.isAndroidTv});

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
    // URL input DPAD exits live on the TvTextField (onDownArrow/onRightArrow).

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
      if (isActivateKey(key)) {
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
      if (isActivateKey(key)) {
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

    // If all selected, move focus to Import button; otherwise restore previous focus
    if (widget.isAndroidTv && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        if (_selectAll) {
          // All channels selected - move focus to Import button
          _safeRequestFocus(_importButtonFocusNode);
        } else if (focusedChannelId != null) {
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
    // Capture the channels list for use in closures
    final channelsList = channels;

    for (int i = 0; i < channelsList.length; i++) {
      // Capture loop variables explicitly for closure safety
      final currentIndex = i;
      final channel = channelsList[currentIndex];
      final node = _channelFocusNodes[channel.id];
      if (node == null) continue;

      node.onKeyEvent = (focusNode, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;

        final key = event.logicalKey;

        // Navigate up
        if (key == LogicalKeyboardKey.arrowUp) {
          if (currentIndex > 0) {
            _channelFocusNodes[channelsList[currentIndex - 1].id]
                ?.requestFocus();
          } else {
            _selectAllFocusNode.requestFocus();
          }
          return KeyEventResult.handled;
        }

        // Navigate down
        if (key == LogicalKeyboardKey.arrowDown) {
          if (currentIndex < channelsList.length - 1) {
            _channelFocusNodes[channelsList[currentIndex + 1].id]
                ?.requestFocus();
          } else {
            _cancelButtonFocusNode.requestFocus();
          }
          return KeyEventResult.handled;
        }

        // Navigate to Import button with left/right arrows
        if (key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.arrowRight) {
          _importButtonFocusNode.requestFocus();
          return KeyEventResult.handled;
        }

        // Toggle selection with Enter/Select
        if (isActivateKey(key)) {
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

    if (focusNode == null) return const SizedBox.shrink();

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
          final app = AppThemeScope.of(context);
          final tv = app.debrifyTv;
          final hasFocus = Focus.of(context).hasFocus;
          final fill = hasFocus ? app.core.tx : tv.fillWeak;
          final ink = hasFocus ? app.inkOn(app.core.tx) : app.core.tx;

          return AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            margin: const EdgeInsets.symmetric(vertical: 3),
            transform: hasFocus
                ? (Matrix4.identity()..translateByDouble(0, -2, 0, 1))
                : Matrix4.identity(),
            decoration: BoxDecoration(
              color: fill,
              border: Border.all(color: hasFocus ? app.core.tx : tv.hairline),
              borderRadius: app.shape.br(14),
              boxShadow: hasFocus
                  ? const [
                      BoxShadow(
                        color: Color(0x66000000),
                        blurRadius: 20,
                        offset: Offset(0, 10),
                      ),
                    ]
                  : null,
            ),
            child: CheckboxListTile(
              value: channel.isSelected,
              onChanged: widget.isAndroidTv
                  ? null
                  : (_) => _toggleChannelSelection(channel),
              activeColor: hasFocus ? app.inkOn(app.core.tx) : tv.accent,
              checkColor: hasFocus ? app.core.tx : app.inkOn(tv.accent),
              dense: true,
              visualDensity: VisualDensity.compact,
              title: Text(
                channel.name,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: ink,
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
                        color: hasFocus
                            ? ink.withValues(alpha: .55)
                            : tv.textDim,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: hasFocus
                              ? ink.withValues(alpha: .08)
                              : tv.accent.withValues(alpha: .14),
                          borderRadius: app.shape.br(10),
                        ),
                        child: Text(
                          channel.category.toUpperCase(),
                          style: TextStyle(
                            color: hasFocus ? ink : tv.accent,
                            fontFamily: 'JetBrainsMono',
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: .7,
                          ),
                        ),
                      ),
                      if (channel.updated.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Icon(
                          Icons.update,
                          size: 12,
                          color: hasFocus
                              ? ink.withValues(alpha: .45)
                              : tv.textFaint,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          channel.updated,
                          style: TextStyle(
                            fontSize: 11,
                            color: hasFocus
                                ? ink.withValues(alpha: .45)
                                : tv.textFaint,
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
    final app = AppThemeScope.of(context);
    final tv = app.debrifyTv;
    final selectedCount = _getSelectedChannels().length;
    final totalCount = _manifest?.channels.length ?? 0;
    final listHeight = (MediaQuery.sizeOf(context).height * .48)
        .clamp(280.0, 580.0)
        .toDouble();
    return DebrifyTvSpotlightDialog(
      eyebrow: 'Import · community',
      title: 'Browse community channels',
      subtitle:
          'Fetch a repository, choose one or several channels, then import them together.',
      icon: Icons.people_alt_rounded,
      maxWidth: 900,
      maxHeightFactor: .94,
      scrollable: false,
      actions: [
        DebrifyTvDialogButton(
          focusNode: _cancelButtonFocusNode,
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        DebrifyTvDialogButton(
          focusNode: _importButtonFocusNode,
          label: selectedCount > 0 ? 'Import $selectedCount' : 'Import',
          icon: Icons.download_done_rounded,
          tone: DebrifyTvDialogButtonTone.primary,
          onPressed: selectedCount > 0
              ? () => Navigator.of(context).pop(_getSelectedChannels())
              : null,
        ),
      ],
      child: SizedBox(
        height: listHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final field = TvTextField(
                  controller: _repoUrlController,
                  focusNode: _repoUrlFocusNode,
                  onDownArrow: () => _fetchButtonFocusNode.requestFocus(),
                  onRightArrow: () => _fetchButtonFocusNode.requestFocus(),
                  decoration: InputDecoration(
                    labelText: 'Repository URL',
                    errorText: _errorMessage,
                    prefixIcon: const Icon(Icons.link_rounded),
                  ),
                  autofocus: true,
                  enabled: !_isLoading,
                );
                final fetch = DebrifyTvDialogButton(
                  focusNode: _fetchButtonFocusNode,
                  label: _isLoading ? 'Fetching…' : 'Fetch',
                  icon: Icons.refresh_rounded,
                  onPressed: _isLoading ? null : _fetchChannels,
                );
                if (constraints.maxWidth < 560) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [field, const SizedBox(height: 10), fetch],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: field),
                    const SizedBox(width: 10),
                    fetch,
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            if (_manifest != null && _manifest!.channels.isNotEmpty) ...[
              Focus(
                focusNode: _selectAllFocusNode,
                child: Builder(
                  builder: (context) {
                    final focused = Focus.of(context).hasFocus;
                    final fill = focused ? app.core.tx : tv.fillWeak;
                    final ink = focused ? app.inkOn(app.core.tx) : app.core.tx;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      decoration: BoxDecoration(
                        color: fill,
                        borderRadius: app.shape.br(14),
                        border: Border.all(
                          color: focused ? app.core.tx : tv.hairline,
                        ),
                      ),
                      child: CheckboxListTile(
                        value: _selectAll,
                        onChanged: widget.isAndroidTv
                            ? null
                            : (_) => _toggleSelectAll(),
                        activeColor: focused
                            ? app.inkOn(app.core.tx)
                            : tv.accent,
                        checkColor: focused
                            ? app.core.tx
                            : app.inkOn(tv.accent),
                        title: Text(
                          'Select all',
                          style: TextStyle(
                            color: ink,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        secondary: Text(
                          '$selectedCount / $totalCount',
                          style: TextStyle(
                            color: focused
                                ? ink.withValues(alpha: .55)
                                : tv.accent,
                            fontFamily: 'JetBrainsMono',
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
            ],
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: tv.dialogDeep.withValues(alpha: .48),
                  borderRadius: app.shape.br(16),
                  border: Border.all(color: tv.hairline),
                ),
                child: _manifest != null && _manifest!.channels.isNotEmpty
                    ? ListView.builder(
                        controller: _channelListScrollController,
                        padding: const EdgeInsets.all(6),
                        itemCount: _manifest!.channels.length,
                        // ignore: deprecated_member_use
                        cacheExtent: 200,
                        itemBuilder: (context, index) => RepaintBoundary(
                          child: _buildChannelTile(_manifest!.channels[index]),
                        ),
                      )
                    : Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: _isLoading
                              ? CircularProgressIndicator(color: tv.accent)
                              : Text(
                                  _errorMessage ??
                                      (_manifest == null
                                          ? 'Fetching the community collection…'
                                          : 'No channels found in this repository.'),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: tv.textDim),
                                ),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
