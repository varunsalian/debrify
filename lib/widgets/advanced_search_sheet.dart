import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/advanced_search_selection.dart';
import '../services/imdb_lookup_service.dart';

class AdvancedSearchSheet extends StatefulWidget {
  final AdvancedSearchSelection? initialSelection;

  const AdvancedSearchSheet({super.key, this.initialSelection});

  @override
  State<AdvancedSearchSheet> createState() => _AdvancedSearchSheetState();
}

class _AdvancedSearchSheetState extends State<AdvancedSearchSheet> {
  late bool _isSeries;
  late TextEditingController _queryController;
  late TextEditingController _seasonController;
  late TextEditingController _episodeController;
  late FocusNode _queryFocusNode;
  late FocusNode _seasonFocusNode;
  late FocusNode _episodeFocusNode;
  late FocusNode _movieChipFocusNode;
  late FocusNode _seriesChipFocusNode;
  late FocusNode _cancelButtonFocusNode;
  List<FocusNode> _resultFocusNodes = [];
  List<ImdbTitleResult> _results = const [];
  ImdbTitleResult? _selected;
  bool _isSearching = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _isSeries = widget.initialSelection?.isSeries ?? false;
    _queryController = TextEditingController(
      text: widget.initialSelection?.title ?? '',
    );
    _seasonController = TextEditingController(
      text: widget.initialSelection?.season?.toString() ?? '',
    );
    _episodeController = TextEditingController(
      text: widget.initialSelection?.episode?.toString() ?? '',
    );
    _queryFocusNode = FocusNode(debugLabel: 'advanced_query');
    _seasonFocusNode = FocusNode(debugLabel: 'advanced_season');
    _episodeFocusNode = FocusNode(debugLabel: 'advanced_episode');
    _movieChipFocusNode = FocusNode(debugLabel: 'advanced_movie_chip');
    _seriesChipFocusNode = FocusNode(debugLabel: 'advanced_series_chip');
    _cancelButtonFocusNode = FocusNode(debugLabel: 'advanced_cancel');
    _selected = widget.initialSelection == null
        ? null
        : ImdbTitleResult(
            imdbId: widget.initialSelection!.imdbId,
            title: widget.initialSelection!.title,
            year: widget.initialSelection!.year,
            posterUrl: null,
          );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_queryFocusNode.hasFocus) {
        _queryFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _queryController.dispose();
    _seasonController.dispose();
    _episodeController.dispose();
    _queryFocusNode.dispose();
    _seasonFocusNode.dispose();
    _episodeFocusNode.dispose();
    _movieChipFocusNode.dispose();
    _seriesChipFocusNode.dispose();
    _cancelButtonFocusNode.dispose();
    for (final node in _resultFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _refreshResultFocusNodes() {
    for (final node in _resultFocusNodes) {
      node.dispose();
    }
    _resultFocusNodes = List.generate(
      _results.length,
      (index) => FocusNode(debugLabel: 'advanced_result_$index'),
    );
  }

  Future<void> _performLookup() async {
    final query = _queryController.text.trim();
    if (query.length < 2) {
      setState(() {
        _errorMessage = 'Enter at least 2 characters to search IMDb.';
        _results = const [];
        _refreshResultFocusNodes();
        _selected = null;
      });
      return;
    }

    debugPrint('AdvancedSearchSheet: Looking up "$query" (isSeries=$_isSeries)');
    setState(() {
      _isSearching = true;
      _errorMessage = null;
    });

    try {
      final results = await ImdbLookupService.searchTitles(query);
      debugPrint('AdvancedSearchSheet: IMDb returned ${results.length} result(s)');
      setState(() {
        _results = results;
        _refreshResultFocusNodes();
        if (results.isEmpty) {
          _errorMessage = 'No IMDb matches found.';
          _selected = null;
        }
      });

      // Auto-focus first result for better TV/DPAD experience
      if (results.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _resultFocusNodes.isNotEmpty) {
            _resultFocusNodes.first.requestFocus();
          }
        });
      }
    } catch (e) {
      debugPrint('AdvancedSearchSheet: Lookup error $e');
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
        _results = const [];
        _refreshResultFocusNodes();
        _selected = null;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
      }
    }
  }

  void _toggleSeries(bool isSeries) {
    setState(() {
      _isSeries = isSeries;
    });
  }

  KeyEventResult _handleQueryKey(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_isSeries) {
        FocusScope.of(context).requestFocus(_seasonFocusNode);
      } else if (_resultFocusNodes.isNotEmpty) {
        FocusScope.of(context).requestFocus(_resultFocusNodes.first);
      } else {
        FocusScope.of(context).requestFocus(_cancelButtonFocusNode);
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      FocusScope.of(context).requestFocus(_movieChipFocusNode);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleResultKey(int index, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (index == 0) {
        final target = _isSeries ? _seasonFocusNode : _queryFocusNode;
        FocusScope.of(context).requestFocus(target);
        return KeyEventResult.handled;
      }
      FocusScope.of(context).requestFocus(_resultFocusNodes[index - 1]);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (index >= _resultFocusNodes.length - 1) {
        FocusScope.of(context).requestFocus(_cancelButtonFocusNode);
        return KeyEventResult.handled;
      }
      FocusScope.of(context).requestFocus(_resultFocusNodes[index + 1]);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.space) {
      final item = _results[index];
      if (!_validateSeriesFields()) {
        return KeyEventResult.handled;
      }
      _completeSelection(item);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleCancelKey(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (_resultFocusNodes.isNotEmpty) {
        FocusScope.of(context)
            .requestFocus(_resultFocusNodes[_resultFocusNodes.length - 1]);
      } else {
        final target = _isSeries ? _episodeFocusNode : _queryFocusNode;
        FocusScope.of(context).requestFocus(target);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleSeasonKey(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      FocusScope.of(context).requestFocus(_queryFocusNode);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      FocusScope.of(context).requestFocus(_episodeFocusNode);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleEpisodeKey(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      FocusScope.of(context).requestFocus(_seasonFocusNode);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_resultFocusNodes.isNotEmpty) {
        FocusScope.of(context).requestFocus(_resultFocusNodes.first);
      } else {
        FocusScope.of(context).requestFocus(_cancelButtonFocusNode);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  bool _validateSeriesFields() {
    if (!_isSeries) return true;
    final seasonText = _seasonController.text.trim();
    if (seasonText.isNotEmpty && int.tryParse(seasonText) == null) {
      setState(() {
        _errorMessage = 'Season must be a number if provided.';
      });
      return false;
    }
    final episodeText = _episodeController.text.trim();
    if (episodeText.isNotEmpty && int.tryParse(episodeText) == null) {
      setState(() {
        _errorMessage = 'Episode must be a number if provided.';
      });
      return false;
    }
    return true;
  }

  void _completeSelection(ImdbTitleResult imdbSelection) {
    int? season;
    int? episode;
    if (_isSeries) {
      season = int.tryParse(_seasonController.text.trim());
      final episodeText = _episodeController.text.trim();
      episode = episodeText.isEmpty ? 1 : int.tryParse(episodeText);
    }

    final selection = AdvancedSearchSelection(
      imdbId: imdbSelection.imdbId,
      isSeries: _isSeries,
      title: imdbSelection.title,
      year: imdbSelection.year,
      season: season,
      episode: episode,
    );

    debugPrint(
      'AdvancedSearchSheet: Submitting imdbId=${imdbSelection.imdbId} isSeries=$_isSeries season=$season episode=$episode',
    );

    Navigator.of(context).pop(selection);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: FractionallySizedBox(
        heightFactor: 0.9,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Advanced Torrent Search',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FocusTraversalGroup(
                policy: OrderedTraversalPolicy(),
                child: Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      focusNode: _movieChipFocusNode,
                      autofocus: true,
                      label: const Text('Movie'),
                      selected: !_isSeries,
                      onSelected: (selected) {
                        if (selected) _toggleSeries(false);
                      },
                    ),
                    ChoiceChip(
                      focusNode: _seriesChipFocusNode,
                      label: const Text('Series'),
                      selected: _isSeries,
                      onSelected: (selected) {
                        if (selected) _toggleSeries(true);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Focus(
                onKeyEvent: (node, event) => _handleQueryKey(event),
                child: TextField(
                  controller: _queryController,
                  focusNode: _queryFocusNode,
                  decoration: InputDecoration(
                    labelText: 'IMDb title search',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.search_rounded),
                      onPressed: _performLookup,
                    ),
                  ),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _performLookup(),
                ),
              ),
              if (_isSeries) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Focus(
                        onKeyEvent: (node, event) => _handleSeasonKey(event),
                        child: TextField(
                          controller: _seasonController,
                          focusNode: _seasonFocusNode,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Season',
                          ),
                          textInputAction: TextInputAction.next,
                          onSubmitted: (_) =>
                              FocusScope.of(context).requestFocus(_episodeFocusNode),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Focus(
                        onKeyEvent: (node, event) => _handleEpisodeKey(event),
                        child: TextField(
                          controller: _episodeController,
                          focusNode: _episodeFocusNode,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Episode',
                          ),
                          textInputAction: TextInputAction.done,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  style: const TextStyle(color: Color(0xFFF87171)),
                ),
              ],
              const SizedBox(height: 12),
              Expanded(
                child: _isSearching
                    ? const Center(child: CircularProgressIndicator())
                    : _results.isEmpty
                        ? Center(
                            child: Text(
                              'Search IMDb to see matches.',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.6),
                              ),
                            ),
                          )
                        : ListView.builder(
                            itemCount: _results.length,
                            itemBuilder: (context, index) {
                              final item = _results[index];
                              final focusNode = _resultFocusNodes[index];
                              return _FocusableImdbResultTile(
                                item: item,
                                focusNode: focusNode,
                                isSelected: _selected?.imdbId == item.imdbId,
                                onKeyEvent: (event) =>
                                    _handleResultKey(index, event),
                                onTap: () {
                                  if (!_validateSeriesFields()) {
                                    return;
                                  }
                                  _completeSelection(item);
                                },
                              );
                            },
                          ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: Focus(
                  focusNode: _cancelButtonFocusNode,
                  onKeyEvent: (node, event) => _handleCancelKey(event),
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// TV-optimized IMDB result tile with DPAD focus indicators
class _FocusableImdbResultTile extends StatefulWidget {
  final ImdbTitleResult item;
  final FocusNode focusNode;
  final bool isSelected;
  final KeyEventResult Function(KeyEvent) onKeyEvent;
  final VoidCallback onTap;

  const _FocusableImdbResultTile({
    required this.item,
    required this.focusNode,
    required this.isSelected,
    required this.onKeyEvent,
    required this.onTap,
  });

  @override
  State<_FocusableImdbResultTile> createState() =>
      _FocusableImdbResultTileState();
}

class _FocusableImdbResultTileState extends State<_FocusableImdbResultTile> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (focused) {
        setState(() {
          _isFocused = focused;
        });
        // Auto-scroll to ensure focused item is visible
        if (focused) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            duration: const Duration(milliseconds: 200),
          );
        }
      },
      onKeyEvent: (node, event) => widget.onKeyEvent(event),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: _isFocused
              ? Colors.white.withValues(alpha: 0.15)
              : widget.isSelected
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _isFocused
                ? Colors.white.withValues(alpha: 0.8)
                : Colors.transparent,
            width: 2,
          ),
          boxShadow: _isFocused
              ? [
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.2),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: ListTile(
          title: Text(
            widget.item.title,
            style: TextStyle(
              color: Colors.white,
              fontWeight: _isFocused ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          subtitle: Text(
            widget.item.year ?? 'Year unknown',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
          trailing: _isFocused
              ? Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: Colors.white.withValues(alpha: 0.6),
                )
              : null,
          onTap: widget.onTap,
        ),
      ),
    );
  }
}
