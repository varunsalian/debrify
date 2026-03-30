import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/tvmaze_service.dart';

class TVMazeSearchDialog extends StatefulWidget {
  final String initialQuery;

  const TVMazeSearchDialog({
    super.key,
    required this.initialQuery,
  });

  @override
  State<TVMazeSearchDialog> createState() => _TVMazeSearchDialogState();
}

class _TVMazeSearchDialogState extends State<TVMazeSearchDialog> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _cancelFocusNode = FocusNode();
  final ScrollController _listScrollController = ScrollController();
  final List<FocusNode> _itemFocusNodes = [];

  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  String? _errorMessage;
  int _selectedIndex = -1;

  // Premium blue accent color
  static const Color kPremiumBlue = Color(0xFF6366F1);

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.initialQuery;
    // Automatically search with initial query
    if (widget.initialQuery.isNotEmpty) {
      _performSearch();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _cancelFocusNode.dispose();
    _listScrollController.dispose();
    for (final node in _itemFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _ensureItemFocusNodes() {
    while (_itemFocusNodes.length < _searchResults.length) {
      _itemFocusNodes.add(FocusNode());
    }
    while (_itemFocusNodes.length > _searchResults.length) {
      _itemFocusNodes.removeLast().dispose();
    }
  }

  Future<void> _performSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isSearching = true;
      _errorMessage = null;
      _searchResults = [];
      _selectedIndex = -1;
    });

    try {
      final results = await TVMazeService.searchShows(query);
      setState(() {
        _searchResults = results;
        _isSearching = false;
        _ensureItemFocusNodes();
        if (results.isEmpty) {
          _errorMessage = 'No shows found for "$query"';
        } else {
          _selectedIndex = 0;
          // Focus first result for DPAD
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_itemFocusNodes.isNotEmpty && mounted) {
              _itemFocusNodes[0].requestFocus();
            }
          });
        }
      });
    } catch (e) {
      setState(() {
        _isSearching = false;
        _errorMessage = 'Failed to search: $e';
      });
    }
  }

  void _selectShow(Map<String, dynamic> show) {
    Navigator.of(context).pop(show);
  }

  void _scrollToSelectedItem() {
    if (!_listScrollController.hasClients || _selectedIndex < 0) return;
    final isCompact = MediaQuery.of(context).size.width < 500;
    final estimatedItemHeight = isCompact ? 110.0 : 152.0;
    final targetOffset = _selectedIndex * estimatedItemHeight;
    final maxScroll = _listScrollController.position.maxScrollExtent;
    final viewportHeight = _listScrollController.position.viewportDimension;

    final currentScroll = _listScrollController.offset;
    final itemTop = targetOffset;
    final itemBottom = targetOffset + estimatedItemHeight;

    if (itemBottom > currentScroll + viewportHeight) {
      _listScrollController.animateTo(
        (itemBottom - viewportHeight).clamp(0.0, maxScroll),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    } else if (itemTop < currentScroll) {
      _listScrollController.animateTo(
        itemTop.clamp(0.0, maxScroll),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  /// Handle DPAD key events on the search field
  KeyEventResult _handleSearchKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_searchResults.isNotEmpty) {
        setState(() => _selectedIndex = 0);
        _itemFocusNodes[0].requestFocus();
        _scrollToSelectedItem();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  /// Handle DPAD key events on result items
  KeyEventResult _handleItemKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_selectedIndex < _searchResults.length - 1) {
        setState(() => _selectedIndex++);
        _itemFocusNodes[_selectedIndex].requestFocus();
        _scrollToSelectedItem();
        return KeyEventResult.handled;
      } else {
        // At last item, move to cancel button
        _cancelFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (_selectedIndex > 0) {
        setState(() => _selectedIndex--);
        _itemFocusNodes[_selectedIndex].requestFocus();
        _scrollToSelectedItem();
        return KeyEventResult.handled;
      } else {
        // At first item, move to search bar
        setState(() => _selectedIndex = -1);
        _searchFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
    } else if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.select) {
      if (_selectedIndex >= 0 && _selectedIndex < _searchResults.length) {
        _selectShow(_searchResults[_selectedIndex]);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  /// Handle DPAD key events on cancel button
  KeyEventResult _handleCancelKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (_searchResults.isNotEmpty) {
        setState(() => _selectedIndex = _searchResults.length - 1);
        _itemFocusNodes[_selectedIndex].requestFocus();
        _scrollToSelectedItem();
      } else {
        _searchFocusNode.requestFocus();
      }
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.select) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _buildShowTile(Map<String, dynamic> show, int index, bool isSelected) {
    final name = show['name'] ?? 'Unknown Show';
    final premiered = show['premiered'] ?? '';
    final network = show['network']?['name'] ?? show['webChannel']?['name'] ?? '';
    final genres = (show['genres'] as List?)?.join(', ') ?? '';
    final summary = show['summary']?.toString().replaceAll(RegExp(r'<[^>]*>'), '') ?? '';
    final imageUrl = show['image']?['medium'] ?? show['image']?['original'];
    final rating = show['rating']?['average'];
    final status = show['status'] ?? '';
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 500;
    final posterWidth = isCompact ? 56.0 : 80.0;
    final posterHeight = isCompact ? 84.0 : 120.0;

    return Focus(
      focusNode: _itemFocusNodes[index],
      onKeyEvent: _handleItemKeyEvent,
      onFocusChange: (hasFocus) {
        if (hasFocus) {
          setState(() {
            _selectedIndex = index;
          });
        }
      },
      child: InkWell(
        onTap: () => _selectShow(show),
        child: Container(
          padding: EdgeInsets.all(isCompact ? 8 : 12),
          decoration: BoxDecoration(
            color: isSelected ? kPremiumBlue.withOpacity(0.1) : Colors.transparent,
            border: Border.all(
              color: isSelected ? kPremiumBlue : Colors.white.withOpacity(0.1),
              width: isSelected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Show poster
              Container(
                width: posterWidth,
                height: posterHeight,
                decoration: BoxDecoration(
                  color: const Color(0xFF333333),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: imageUrl != null
                      ? CachedNetworkImage(
                          imageUrl: imageUrl,
                          memCacheWidth: 200,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => const Center(
                            child: Icon(Icons.tv, color: Colors.white54, size: 32),
                          ),
                          errorWidget: (context, url, error) => const Center(
                            child: Icon(Icons.tv, color: Colors.white54, size: 32),
                          ),
                        )
                      : const Center(
                          child: Icon(Icons.tv, color: Colors.white54, size: 32),
                        ),
                ),
              ),
              SizedBox(width: isCompact ? 8 : 12),
              // Show details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title
                    Text(
                      name,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: isCompact ? 14 : 16,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    // Metadata row
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (premiered.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: kPremiumBlue.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              premiered.substring(0, 4),
                              style: const TextStyle(
                                color: kPremiumBlue,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        if (status.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: status == 'Ended'
                                  ? Colors.red.withOpacity(0.2)
                                  : Colors.green.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              status,
                              style: TextStyle(
                                color: status == 'Ended' ? Colors.red : Colors.green,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        if (rating != null)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star, color: Colors.amber, size: 14),
                              const SizedBox(width: 2),
                              Text(
                                rating.toString(),
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                    if (network.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        network,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (genres.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        genres,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (summary.isNotEmpty && !isCompact) ...[
                      const SizedBox(height: 6),
                      Text(
                        summary,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 11,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 500;

    return Dialog(
      backgroundColor: const Color(0xFF0F172A),
      insetPadding: EdgeInsets.symmetric(
        horizontal: isCompact ? 12 : 40,
        vertical: isCompact ? 24 : 40,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        width: isCompact ? double.infinity : screenWidth * 0.8,
        height: MediaQuery.of(context).size.height * 0.8,
        padding: EdgeInsets.all(isCompact ? 14 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(
                  Icons.search,
                  color: kPremiumBlue,
                  size: isCompact ? 22 : 28,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isCompact ? 'Fix Metadata' : 'Fix Metadata - Search TVMaze',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: isCompact ? 16 : 20,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Close button
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: Colors.white70),
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(4),
                ),
              ],
            ),
            SizedBox(height: isCompact ? 12 : 20),

            // Search field
            Focus(
              onKeyEvent: _handleSearchKeyEvent,
              canRequestFocus: false, // Let the TextField handle focus
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Enter show name...',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.1),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: kPremiumBlue, width: 2),
                  ),
                  prefixIcon: const Icon(Icons.search, color: Colors.white54),
                  suffixIcon: IconButton(
                    onPressed: _isSearching ? null : _performSearch,
                    icon: _isSearching
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: kPremiumBlue,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.arrow_forward, color: kPremiumBlue),
                  ),
                ),
                onSubmitted: (_) => _performSearch(),
              ),
            ),
            SizedBox(height: isCompact ? 12 : 20),

            // Search results
            Expanded(
              child: _isSearching
                  ? const Center(
                      child: CircularProgressIndicator(color: kPremiumBlue),
                    )
                  : _errorMessage != null
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.error_outline,
                                color: Colors.red.withOpacity(0.7),
                                size: 48,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _errorMessage!,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        )
                      : _searchResults.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.tv_off,
                                    color: Colors.white.withOpacity(0.3),
                                    size: 64,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Search for a TV show to fix metadata',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.5),
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.separated(
                              controller: _listScrollController,
                              itemCount: _searchResults.length,
                              separatorBuilder: (context, index) => const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final show = _searchResults[index];
                                final isSelected = index == _selectedIndex;
                                return _buildShowTile(show, index, isSelected);
                              },
                            ),
            ),

            // Cancel button
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: SizedBox(
                width: double.infinity,
                child: Focus(
                  focusNode: _cancelFocusNode,
                  onKeyEvent: _handleCancelKeyEvent,
                  onFocusChange: (hasFocus) {
                    if (hasFocus) setState(() => _selectedIndex = -1);
                  },
                  child: Builder(
                    builder: (context) {
                      final isFocused = Focus.of(context).hasFocus;
                      return OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: BorderSide(
                            color: isFocused ? kPremiumBlue : Colors.white24,
                            width: isFocused ? 2 : 1,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('Cancel'),
                      );
                    },
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
