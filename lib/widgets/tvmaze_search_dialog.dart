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
  final FocusNode _listFocusNode = FocusNode();

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
    _listFocusNode.dispose();
    super.dispose();
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
        if (results.isEmpty) {
          _errorMessage = 'No shows found for "$query"';
        } else {
          // Auto-select first result for better DPAD navigation
          _selectedIndex = 0;
          // Move focus to list after search completes
          _listFocusNode.requestFocus();
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

  Widget _buildShowTile(Map<String, dynamic> show, int index, bool isSelected) {
    final name = show['name'] ?? 'Unknown Show';
    final premiered = show['premiered'] ?? '';
    final network = show['network']?['name'] ?? show['webChannel']?['name'] ?? '';
    final genres = (show['genres'] as List?)?.join(', ') ?? '';
    final summary = show['summary']?.toString().replaceAll(RegExp(r'<[^>]*>'), '') ?? '';
    final imageUrl = show['image']?['medium'] ?? show['image']?['original'];
    final rating = show['rating']?['average'];
    final status = show['status'] ?? '';

    return Focus(
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
          padding: const EdgeInsets.all(12),
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
                width: 80,
                height: 120,
                decoration: BoxDecoration(
                  color: const Color(0xFF333333),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: imageUrl != null
                      ? CachedNetworkImage(
                          imageUrl: imageUrl,
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
              const SizedBox(width: 12),
              // Show details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title and year
                    Text(
                      name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    // Metadata row
                    Row(
                      children: [
                        if (premiered.isNotEmpty) ...[
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
                          const SizedBox(width: 8),
                        ],
                        if (status.isNotEmpty) ...[
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
                          const SizedBox(width: 8),
                        ],
                        if (rating != null) ...[
                          Icon(Icons.star, color: Colors.amber, size: 14),
                          const SizedBox(width: 2),
                          Text(
                            rating.toString(),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                        ],
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
                    if (summary.isNotEmpty) ...[
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
    return Dialog(
      backgroundColor: const Color(0xFF0F172A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.8,
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(
                  Icons.search,
                  color: kPremiumBlue,
                  size: 28,
                ),
                const SizedBox(width: 12),
                const Text(
                  'Fix Metadata - Search TVMaze',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                // Close button
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: Colors.white70),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Search field
            Row(
              children: [
                Expanded(
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
                    ),
                    onSubmitted: (_) => _performSearch(),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _isSearching ? null : _performSearch,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPremiumBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isSearching
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('Search'),
                ),
              ],
            ),
            const SizedBox(height: 20),

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
                          : Shortcuts(
                              shortcuts: <LogicalKeySet, Intent>{
                                LogicalKeySet(LogicalKeyboardKey.arrowUp): const _MoveSelectionIntent(-1),
                                LogicalKeySet(LogicalKeyboardKey.arrowDown): const _MoveSelectionIntent(1),
                                LogicalKeySet(LogicalKeyboardKey.enter): const _SelectItemIntent(),
                                LogicalKeySet(LogicalKeyboardKey.select): const _SelectItemIntent(),
                              },
                              child: Actions(
                                actions: <Type, Action<Intent>>{
                                  _MoveSelectionIntent: CallbackAction<_MoveSelectionIntent>(
                                    onInvoke: (intent) {
                                      setState(() {
                                        if (intent.direction == -1) {
                                          // Move up
                                          if (_selectedIndex > 0) {
                                            _selectedIndex--;
                                          }
                                        } else {
                                          // Move down
                                          if (_selectedIndex < _searchResults.length - 1) {
                                            _selectedIndex++;
                                          }
                                        }
                                      });
                                      return null;
                                    },
                                  ),
                                  _SelectItemIntent: CallbackAction<_SelectItemIntent>(
                                    onInvoke: (_) {
                                      if (_selectedIndex >= 0 && _selectedIndex < _searchResults.length) {
                                        _selectShow(_searchResults[_selectedIndex]);
                                      }
                                      return null;
                                    },
                                  ),
                                },
                                child: Focus(
                                  focusNode: _listFocusNode,
                                  autofocus: _searchResults.isNotEmpty,
                                  child: ListView.separated(
                                    itemCount: _searchResults.length,
                                    separatorBuilder: (context, index) => const SizedBox(height: 8),
                                    itemBuilder: (context, index) {
                                      final show = _searchResults[index];
                                      final isSelected = index == _selectedIndex;
                                      return _buildShowTile(show, index, isSelected);
                                    },
                                  ),
                                ),
                              ),
                            ),
            ),

            // Instructions
            Container(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.keyboard, color: Colors.white.withOpacity(0.3), size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'Use arrow keys to navigate • Enter to select • ESC to cancel',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.3),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Custom intents for keyboard navigation
class _MoveSelectionIntent extends Intent {
  final int direction;
  const _MoveSelectionIntent(this.direction);
}

class _SelectItemIntent extends Intent {
  const _SelectItemIntent();
}