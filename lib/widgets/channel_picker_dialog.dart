import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/debrify_tv_channel_record.dart';
import '../services/debrify_tv_repository.dart';
import '../services/debrify_tv_cache_service.dart';
import '../models/debrify_tv_cache.dart';

/// Result returned when user selects or creates a channel
class ChannelPickerResult {
  final String channelId;
  final String channelName;
  final bool isNewChannel;

  const ChannelPickerResult({
    required this.channelId,
    required this.channelName,
    required this.isNewChannel,
  });
}

/// DPAD-compatible dialog for selecting existing channel or creating new one
class ChannelPickerDialog extends StatefulWidget {
  final String searchKeyword;

  const ChannelPickerDialog({
    super.key,
    required this.searchKeyword,
  });

  @override
  State<ChannelPickerDialog> createState() => _ChannelPickerDialogState();
}

class _ChannelPickerDialogState extends State<ChannelPickerDialog> {
  List<DebrifyTvChannelRecord> _channels = [];
  bool _isLoading = true;
  bool _isCreating = false;

  final List<FocusNode> _itemFocusNodes = [];
  final FocusNode _createButtonFocusNode = FocusNode();
  final TextEditingController _nameController = TextEditingController();
  final FocusNode _nameFieldFocusNode = FocusNode();
  final FocusNode _confirmButtonFocusNode = FocusNode();
  final FocusNode _cancelButtonFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _loadChannels();
  }

  @override
  void dispose() {
    for (final node in _itemFocusNodes) {
      node.dispose();
    }
    _createButtonFocusNode.dispose();
    _nameController.dispose();
    _nameFieldFocusNode.dispose();
    _confirmButtonFocusNode.dispose();
    _cancelButtonFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadChannels() async {
    debugPrint('[ChannelPicker] Loading channels...');
    try {
      final channels = await DebrifyTvRepository.instance.fetchAllChannels();
      debugPrint('[ChannelPicker] Loaded ${channels.length} channels');
      for (var ch in channels) {
        debugPrint('[ChannelPicker]   - ${ch.name} (${ch.channelId}): keywords=${ch.keywords}');
      }

      if (mounted) {
        setState(() {
          _channels = channels;
          _isLoading = false;
        });
        _ensureFocusNodes();

        // Auto-focus create button after loading
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _createButtonFocusNode.requestFocus();
          }
        });
      }
    } catch (e) {
      debugPrint('[ChannelPicker] ERROR loading channels: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _ensureFocusNodes() {
    // Dispose old nodes
    while (_itemFocusNodes.length > _channels.length) {
      _itemFocusNodes.removeLast().dispose();
    }

    // Add new nodes
    while (_itemFocusNodes.length < _channels.length) {
      _itemFocusNodes.add(FocusNode(debugLabel: 'channel-${_itemFocusNodes.length}'));
    }
  }

  void _handleChannelSelect(DebrifyTvChannelRecord channel) {
    debugPrint('[ChannelPicker] User selected existing channel: ${channel.name} (${channel.channelId})');
    debugPrint('[ChannelPicker] Channel keywords at selection: ${channel.keywords}');
    Navigator.of(context).pop(
      ChannelPickerResult(
        channelId: channel.channelId,
        channelName: channel.name,
        isNewChannel: false,
      ),
    );
  }

  void _handleCreateNew() {
    debugPrint('[ChannelPicker] User tapped "Create New Channel"');
    setState(() {
      _isCreating = true;
    });

    // Auto-focus name field
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _nameFieldFocusNode.requestFocus();
      }
    });
  }

  Future<void> _createChannel() async {
    final name = _nameController.text.trim();
    debugPrint('[ChannelPicker] Creating new channel with name: "$name"');
    debugPrint('[ChannelPicker] Initial keyword: "${widget.searchKeyword}"');

    if (name.isEmpty) {
      debugPrint('[ChannelPicker] ERROR: Empty channel name');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Channel name cannot be empty'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final now = DateTime.now();
      final channelId = now.microsecondsSinceEpoch.toString();

      final channel = DebrifyTvChannelRecord(
        channelId: channelId,
        name: name,
        keywords: [widget.searchKeyword],
        avoidNsfw: true,
        channelNumber: 0, // Auto-assigned by repository
        createdAt: now,
        updatedAt: now,
      );

      debugPrint('[ChannelPicker] Channel record created: ${channel.channelId}');
      debugPrint('[ChannelPicker] Channel keywords: ${channel.keywords}');

      // Save channel to database
      debugPrint('[ChannelPicker] Saving channel to database...');
      await DebrifyTvRepository.instance.upsertChannel(channel);
      debugPrint('[ChannelPicker] Channel saved to database');

      if (!mounted) return;

      // Initialize empty cache entry with warming status
      final normalizedKeyword = widget.searchKeyword.toLowerCase();
      debugPrint('[ChannelPicker] Creating cache entry with normalized keyword: "$normalizedKeyword"');

      final cacheEntry = DebrifyTvChannelCacheEntry.empty(
        channelId: channelId,
        normalizedKeywords: [normalizedKeyword],
        status: DebrifyTvCacheStatus.warming,
      );

      debugPrint('[ChannelPicker] Saving cache entry...');
      await DebrifyTvCacheService.saveEntry(cacheEntry);
      debugPrint('[ChannelPicker] Cache entry saved');

      if (mounted) {
        debugPrint('[ChannelPicker] SUCCESS: Returning new channel result');
        Navigator.of(context).pop(
          ChannelPickerResult(
            channelId: channelId,
            channelName: name,
            isNewChannel: true,
          ),
        );
      }
    } catch (e) {
      debugPrint('[ChannelPicker] ERROR creating channel: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create channel: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _cancelCreate() {
    setState(() {
      _isCreating = false;
      _nameController.clear();
    });

    // Refocus create button
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _createButtonFocusNode.requestFocus();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Container(
          color: const Color(0xFF0F172A),
          constraints: const BoxConstraints(maxHeight: 600),
          child: _isCreating ? _buildCreateView() : _buildSelectionView(),
        ),
      ),
    );
  }

  Widget _buildSelectionView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 12),
        Container(
          width: 42,
          height: 5,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF10B981), Color(0xFF059669)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.connected_tv, color: Colors.white),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Add to Channel',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Select a channel or create new',
                      style: TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, color: Colors.white54),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: Color(0xFF1E293B)),
        if (_isLoading)
          const Padding(
            padding: EdgeInsets.all(40),
            child: CircularProgressIndicator(
              color: Color(0xFF10B981),
            ),
          )
        else
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                _ChannelSelectionTile(
                  icon: Icons.add_circle_outline,
                  title: 'Create New Channel',
                  subtitle: 'Start fresh with "${widget.searchKeyword}"',
                  isCreateNew: true,
                  focusNode: _createButtonFocusNode,
                  autofocus: true,
                  onTap: _handleCreateNew,
                ),
                if (_channels.isNotEmpty)
                  const Divider(height: 1, color: Color(0xFF1E293B)),
                ..._channels.asMap().entries.map((entry) {
                  final index = entry.key;
                  final channel = entry.value;
                  return _ChannelSelectionTile(
                    icon: Icons.tv_rounded,
                    title: channel.name,
                    subtitle: '${channel.keywords.length} keyword(s) • Channel ${channel.channelNumber}',
                    focusNode: _itemFocusNodes[index],
                    onTap: () => _handleChannelSelect(channel),
                  );
                }),
                if (_channels.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        'No channels yet. Create your first one!',
                        style: TextStyle(
                          color: Colors.white38,
                          fontSize: 13,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildCreateView() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.tv_rounded,
                  color: Color(0xFF10B981),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Create Channel',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Focus(
            focusNode: _nameFieldFocusNode,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.enter) {
                _confirmButtonFocusNode.requestFocus();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: TextField(
              controller: _nameController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Channel Name',
                labelStyle: const TextStyle(color: Colors.white60),
                hintText: 'e.g., Action Movies',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF111827),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF1F2937)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF1F2937)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF10B981), width: 2),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Keyword: "${widget.searchKeyword}" will be auto-added',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Focus(
                focusNode: _cancelButtonFocusNode,
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent &&
                      (event.logicalKey == LogicalKeyboardKey.select ||
                          event.logicalKey == LogicalKeyboardKey.enter ||
                          event.logicalKey == LogicalKeyboardKey.space)) {
                    _cancelCreate();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: TextButton(
                  onPressed: _cancelCreate,
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Focus(
                focusNode: _confirmButtonFocusNode,
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent &&
                      (event.logicalKey == LogicalKeyboardKey.select ||
                          event.logicalKey == LogicalKeyboardKey.enter ||
                          event.logicalKey == LogicalKeyboardKey.space)) {
                    _createChannel();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _createChannel,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Create'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Individual channel selection tile with DPAD support
class _ChannelSelectionTile extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isCreateNew;
  final bool autofocus;
  final FocusNode focusNode;
  final VoidCallback onTap;

  const _ChannelSelectionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.focusNode,
    required this.onTap,
    this.isCreateNew = false,
    this.autofocus = false,
  });

  @override
  State<_ChannelSelectionTile> createState() => _ChannelSelectionTileState();
}

class _ChannelSelectionTileState extends State<_ChannelSelectionTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: (focused) {
        if (mounted) {
          setState(() => _focused = focused);
        }
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: InkWell(
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF111827),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _focused ? const Color(0xFF10B981) : const Color(0xFF1F2937),
              width: _focused ? 2 : 1,
            ),
            boxShadow: _focused
                ? [
                    BoxShadow(
                      color: const Color(0xFF10B981).withValues(alpha: 0.3),
                      blurRadius: 8,
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Icon(
                widget.icon,
                color: widget.isCreateNew ? const Color(0xFF10B981) : Colors.white70,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: widget.isCreateNew ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: Colors.white38,
                size: 14,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
