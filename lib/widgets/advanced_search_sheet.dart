import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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
    _selected = widget.initialSelection == null
        ? null
        : ImdbTitleResult(
            imdbId: widget.initialSelection!.imdbId,
            title: widget.initialSelection!.title,
            year: widget.initialSelection!.year,
            posterUrl: null,
          );
  }

  @override
  void dispose() {
    _queryController.dispose();
    _seasonController.dispose();
    _episodeController.dispose();
    super.dispose();
  }

  Future<void> _performLookup() async {
    final query = _queryController.text.trim();
    if (query.length < 2) {
      setState(() {
        _errorMessage = 'Enter at least 2 characters to search IMDb.';
        _results = const [];
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
        if (results.isEmpty) {
          _errorMessage = 'No IMDb matches found.';
          _selected = null;
        }
      });
    } catch (e) {
      debugPrint('AdvancedSearchSheet: Lookup error $e');
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
        _results = const [];
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
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Movie'),
                    selected: !_isSeries,
                    onSelected: (selected) {
                      if (selected) _toggleSeries(false);
                    },
                  ),
                  ChoiceChip(
                    label: const Text('Series'),
                    selected: _isSeries,
                    onSelected: (selected) {
                      if (selected) _toggleSeries(true);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _queryController,
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
              if (_isSeries) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _seasonController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Season',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _episodeController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Episode',
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
                              return ListTile(
                                title: Text(
                                  item.title,
                                  style: const TextStyle(color: Colors.white),
                                ),
                                subtitle: Text(
                                  item.year ?? 'Year unknown',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.7),
                                  ),
                                ),
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
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
