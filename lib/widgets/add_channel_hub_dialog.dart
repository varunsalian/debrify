import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import '../models/channel_hub.dart';
import '../services/channel_hub_service.dart';

class AddChannelHubDialog extends StatefulWidget {
  final ChannelHub? initialHub;

  const AddChannelHubDialog({
    super.key,
    this.initialHub,
  });

  @override
  State<AddChannelHubDialog> createState() => _AddChannelHubDialogState();
}

class _AddChannelHubDialogState extends State<AddChannelHubDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _searchController = TextEditingController();
  
  List<Map<String, dynamic>> _searchResults = [];
  List<SeriesInfo> _selectedSeries = [];
  bool _isSearching = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialHub != null) {
      _nameController.text = widget.initialHub!.name;
      _selectedSeries = List.from(widget.initialHub!.series);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _searchSeries(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    try {
      final response = await http.get(
        Uri.parse('https://api.tvmaze.com/search/shows?q=${Uri.encodeComponent(query.trim())}'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List<dynamic> results = json.decode(response.body);
        setState(() {
          _searchResults = results.map((r) => r['show'] as Map<String, dynamic>).toList().take(10).toList();
          _isSearching = false;
        });
      } else {
        setState(() {
          _searchResults = [];
          _isSearching = false;
        });
      }
    } catch (e) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error searching: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  void _addSeries(Map<String, dynamic> show) {
    final series = SeriesInfo.fromTVMazeShow(show);
    if (!_selectedSeries.any((s) => s.id == series.id)) {
      setState(() {
        _selectedSeries.add(series);
      });
    }
    _searchController.clear();
    setState(() {
      _searchResults = [];
    });
  }

  void _removeSeries(SeriesInfo series) {
    setState(() {
      _selectedSeries.removeWhere((s) => s.id == series.id);
    });
  }

  Future<void> _saveChannelHub() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
    });

    try {
      final hub = ChannelHub(
        id: widget.initialHub?.id ?? ChannelHubService.generateId(),
        name: _nameController.text.trim(),
        series: _selectedSeries,
        createdAt: widget.initialHub?.createdAt ?? DateTime.now(),
      );

      final success = await ChannelHubService.saveChannelHub(hub);
      
      if (success && mounted) {
        Navigator.of(context).pop(hub);
      } else {
        throw Exception('Failed to save channel hub');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildNameField(),
                      const SizedBox(height: 24),
                      _buildSeriesSearch(),
                      const SizedBox(height: 16),
                      _buildSelectedSeries(),
                    ],
                  ),
                ),
              ),
              _buildActions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.tv_rounded,
            color: Theme.of(context).colorScheme.onPrimary,
            size: 24,
          ),
          const SizedBox(width: 12),
          Text(
            widget.initialHub != null ? 'Edit Channel Hub' : 'Create Channel Hub',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Theme.of(context).colorScheme.onPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(
              Icons.close,
              color: Theme.of(context).colorScheme.onPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNameField() {
    return TextFormField(
      controller: _nameController,
      decoration: const InputDecoration(
        labelText: 'Channel Hub Name',
        hintText: 'Enter a name for your channel hub',
        prefixIcon: Icon(Icons.edit),
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Please enter a name';
        }
        return null;
      },
    );
  }

  Widget _buildSeriesSearch() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Add Series',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _searchController,
                decoration: InputDecoration(
                  labelText: 'Search for TV series',
                  hintText: 'Enter series name to search...',
                  prefixIcon: const Icon(Icons.search),
                ),
                onFieldSubmitted: (value) {
                  if (value.trim().isNotEmpty) {
                    _searchSeries(value);
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _isSearching 
                  ? null 
                  : () {
                      if (_searchController.text.trim().isNotEmpty) {
                        _searchSeries(_searchController.text);
                      }
                    },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              child: _isSearching
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Search'),
            ),
          ],
        ),
        if (_searchResults.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _searchResults.length,
              itemBuilder: (context, index) {
                final show = _searchResults[index];
                final isSelected = _selectedSeries.any((s) => s.id == show['id']);
                
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: show['image']?['medium'] != null
                          ? CachedNetworkImage(
                              imageUrl: show['image']['medium'],
                              width: 50,
                              height: 50,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                width: 50,
                                height: 50,
                                color: Theme.of(context).colorScheme.surfaceContainer,
                                child: const CircularProgressIndicator(strokeWidth: 2),
                              ),
                              errorWidget: (context, url, error) {
                                return Container(
                                  width: 50,
                                  height: 50,
                                  color: Theme.of(context).colorScheme.surfaceContainer,
                                  child: Icon(
                                    Icons.tv_rounded,
                                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                                  ),
                                );
                              },
                            )
                          : Container(
                              width: 50,
                              height: 50,
                              color: Theme.of(context).colorScheme.surfaceContainer,
                              child: Icon(
                                Icons.tv_rounded,
                                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                              ),
                            ),
                    ),
                    title: Text(
                      show['name'],
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    subtitle: Text(
                      show['genres']?.join(', ') ?? 'No genres',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    trailing: IconButton(
                      onPressed: isSelected ? null : () => _addSeries(show),
                      icon: Icon(
                        isSelected ? Icons.check_circle : Icons.add_circle_outline,
                        color: isSelected 
                            ? Theme.of(context).colorScheme.primary 
                            : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSelectedSeries() {
    if (_selectedSeries.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainer.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              Icons.info_outline,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'No series added yet. Search and add your favorite TV shows!',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Selected Series (${_selectedSeries.length})',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        ...(_selectedSeries.map((series) => Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: series.imageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: series.imageUrl!,
                      width: 50,
                      height: 50,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        width: 50,
                        height: 50,
                        color: Theme.of(context).colorScheme.surfaceContainer,
                        child: const CircularProgressIndicator(strokeWidth: 2),
                      ),
                      errorWidget: (context, url, error) {
                        return Container(
                          width: 50,
                          height: 50,
                          color: Theme.of(context).colorScheme.surfaceContainer,
                          child: Icon(
                            Icons.tv_rounded,
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                          ),
                        );
                      },
                    )
                  : Container(
                      width: 50,
                      height: 50,
                      color: Theme.of(context).colorScheme.surfaceContainer,
                      child: Icon(
                        Icons.tv_rounded,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
            ),
            title: Text(
              series.name,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            subtitle: Text(
              series.genres.join(', '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            trailing: IconButton(
              onPressed: () => _removeSeries(series),
              icon: Icon(
                Icons.remove_circle_outline,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        )).toList()),
      ],
    );
  }

  Widget _buildActions() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer.withValues(alpha: 0.3),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
      ),
      child: Row(
        children: [
          TextButton(
            onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          const Spacer(),
          ElevatedButton(
            onPressed: _isSaving ? null : _saveChannelHub,
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Create Channel Hub'),
          ),
        ],
      ),
    );
  }
} 