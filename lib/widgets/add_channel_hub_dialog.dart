import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import '../models/channel_hub.dart';
import '../services/channel_hub_service.dart';
import '../services/torrentio_service.dart';

class AddChannelHubDialog extends StatefulWidget {
  final ChannelHub? initialHub;

  const AddChannelHubDialog({
    super.key,
    this.initialHub,
  });

  @override
  State<AddChannelHubDialog> createState() => _AddChannelHubDialogState();
}

class _AddChannelHubDialogState extends State<AddChannelHubDialog>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _seriesSearchController = TextEditingController();
  final _moviesSearchController = TextEditingController();
  String _selectedQuality = '720p';
  
  late TabController _tabController;
  
  List<dynamic> _seriesSearchResults = [];
  List<dynamic> _moviesSearchResults = [];
  List<SeriesInfo> _selectedSeries = [];
  List<MovieInfo> _selectedMovies = [];
  bool _isSearchingSeries = false;
  bool _isSearchingMovies = false;
  bool _isSaving = false;
  bool _isAddingMovie = false;
  String? _hubId; // Store the hub ID for Torrentio cache keys

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    
    // Set the hub ID (either existing or generate immediately for new hubs)
    _hubId = widget.initialHub?.id ?? ChannelHubService.generateId();
    
    if (widget.initialHub != null) {
      _nameController.text = widget.initialHub!.name;
      _selectedQuality = widget.initialHub!.quality;
      _selectedSeries = List.from(widget.initialHub!.series);
      _selectedMovies = List.from(widget.initialHub!.movies);
    }
    
    // Add listener to name controller to update UI when text changes
    _nameController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _seriesSearchController.dispose();
    _moviesSearchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _searchSeries(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _seriesSearchResults = [];
      });
      return;
    }

    setState(() {
      _isSearchingSeries = true;
    });

    try {
      final response = await http.get(
        Uri.parse('https://api.tvmaze.com/search/shows?q=${Uri.encodeComponent(query.trim())}'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List<dynamic> results = json.decode(response.body);
        setState(() {
          _seriesSearchResults = results.map((r) => r['show'] as Map<String, dynamic>).toList().take(10).toList();
          _isSearchingSeries = false;
        });
      } else {
        setState(() {
          _seriesSearchResults = [];
          _isSearchingSeries = false;
        });
      }
    } catch (e) {
      setState(() {
        _seriesSearchResults = [];
        _isSearchingSeries = false;
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

  Future<void> _searchMovies(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _moviesSearchResults = [];
      });
      return;
    }

    setState(() {
      _isSearchingMovies = true;
    });

    try {
      final response = await http.get(
        Uri.parse('https://search.imdbot.workers.dev/?q=${Uri.encodeComponent(query.trim())}'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        final List<dynamic> results = data['description'] ?? [];
        
        setState(() {
          _moviesSearchResults = results.take(10).toList();
          _isSearchingMovies = false;
        });
      } else {
        setState(() {
          _moviesSearchResults = [];
          _isSearchingMovies = false;
        });
      }
    } catch (e) {
      setState(() {
        _moviesSearchResults = [];
        _isSearchingMovies = false;
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
    try {
      final series = SeriesInfo.fromTVMazeShow(show);
      if (!_selectedSeries.any((s) => s.id == series.id)) {
        setState(() {
          _selectedSeries.add(series);
        });
      }
      _seriesSearchController.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error adding series: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _addMovie(Map<String, dynamic> movie) async {
    if (_isAddingMovie) return; // Prevent multiple simultaneous additions
    
    setState(() {
      _isAddingMovie = true;
    });

    try {
      // Get detailed movie info
      final detailResponse = await http.get(
        Uri.parse('https://search.imdbot.workers.dev/?tt=${movie['#IMDB_ID']}'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 30));

      if (detailResponse.statusCode == 200) {
        final detailData = json.decode(detailResponse.body);
        
        // Check if it's actually a movie
        final short = detailData['short'];
        if (short == null || short['@type'] != 'Movie') {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('"${movie['#TITLE']}" is not a movie. Please select only movies.'),
                backgroundColor: Theme.of(context).colorScheme.error,
                duration: const Duration(seconds: 3),
              ),
            );
          }
          return;
        }
        
        final movieInfo = MovieInfo.fromIMDBDetail(detailData, originalImdbId: movie['#IMDB_ID']);
        
        if (!_selectedMovies.any((m) => m.id == movieInfo.id)) {
          // Fetch Torrentio streams for this movie
          try {
            final streams = await TorrentioService.getMovieStreams(movieInfo.id, hubId: _hubId)
                .timeout(const Duration(seconds: 30));
            final updatedMovieInfo = movieInfo.copyWith(
              torrentioStreams: streams,
              hasTorrentioData: streams.isNotEmpty,
            );
            
            setState(() {
              _selectedMovies.add(updatedMovieInfo);
            });
          } catch (e) {
            // If Torrentio fetch fails, still add the movie without streams
            setState(() {
              _selectedMovies.add(movieInfo);
            });
          }
        }
      } else {
        // Fallback to search result if detail fails
        final movieInfo = MovieInfo.fromIMDBSearch(movie);
        if (!_selectedMovies.any((m) => m.id == movieInfo.id)) {
          // Fetch Torrentio streams for this movie
          try {
            final streams = await TorrentioService.getMovieStreams(movieInfo.id, hubId: _hubId)
                .timeout(const Duration(seconds: 30));
            final updatedMovieInfo = movieInfo.copyWith(
              torrentioStreams: streams,
              hasTorrentioData: streams.isNotEmpty,
            );
            
            setState(() {
              _selectedMovies.add(updatedMovieInfo);
            });
          } catch (e) {
            // If Torrentio fetch fails, still add the movie without streams
            setState(() {
              _selectedMovies.add(movieInfo);
            });
          }
        }
      }
    } catch (e) {
      // Check if the error is due to not being a movie
      if (e.toString().contains('Not a movie')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('"${movie['#TITLE']}" is not a movie. Please select only movies.'),
              backgroundColor: Theme.of(context).colorScheme.error,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return;
      }
      
      // For parsing errors or other issues, try fallback to search result
      try {
        final movieInfo = MovieInfo.fromIMDBSearch(movie);
        if (!_selectedMovies.any((m) => m.id == movieInfo.id)) {
          // Fetch Torrentio streams for this movie
          try {
            final streams = await TorrentioService.getMovieStreams(movieInfo.id, hubId: _hubId)
                .timeout(const Duration(seconds: 30));
            final updatedMovieInfo = movieInfo.copyWith(
              torrentioStreams: streams,
              hasTorrentioData: streams.isNotEmpty,
            );
            
            setState(() {
              _selectedMovies.add(updatedMovieInfo);
            });
            
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Added "${movie['#TITLE']}" with basic info (detailed info unavailable)'),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  duration: const Duration(seconds: 2),
                ),
              );
            }
          } catch (streamError) {
            // If Torrentio fetch fails, still add the movie without streams
            setState(() {
              _selectedMovies.add(movieInfo);
            });
            
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Added "${movie['#TITLE']}" with basic info'),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  duration: const Duration(seconds: 2),
                ),
              );
            }
          }
        }
      } catch (fallbackError) {
        // If even the fallback fails, show error
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to add "${movie['#TITLE']}": ${e.toString()}'),
              backgroundColor: Theme.of(context).colorScheme.error,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } finally {
      setState(() {
        _isAddingMovie = false;
      });
    }
    
    _moviesSearchController.clear();
  }

  void _removeSeries(SeriesInfo series) {
    setState(() {
      _selectedSeries.removeWhere((s) => s.id == series.id);
    });
  }

  void _removeMovie(MovieInfo movie) {
    setState(() {
      _selectedMovies.removeWhere((m) => m.id == movie.id);
    });
  }

  Future<void> _saveChannelHub() async {
    // Validate form first
    if (!_formKey.currentState!.validate()) {
      // If validation fails, switch to the hub info tab to show the error
      _tabController.animateTo(0);
      return;
    }

    // Additional check for name
    if (_nameController.text.trim().isEmpty) {
      _tabController.animateTo(0);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Please enter a name for the channel hub'),
            backgroundColor: Theme.of(context).colorScheme.error,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final hub = ChannelHub(
        id: _hubId!,
        name: _nameController.text.trim(),
        quality: _selectedQuality,
        series: _selectedSeries,
        movies: _selectedMovies,
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
              _buildTabs(),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildHubInfoTab(),
                    _buildMoviesTab(),
                    _buildSeriesTab(),
                  ],
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

  Widget _buildTabs() {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: TabBar(
        controller: _tabController,
        labelColor: Theme.of(context).colorScheme.primary,
        unselectedLabelColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
        indicatorColor: Theme.of(context).colorScheme.primary,
        tabs: const [
          Tab(text: 'Hub Info'),
          Tab(text: 'Movies'),
          Tab(text: 'Series'),
        ],
      ),
    );
  }

  Widget _buildHubInfoTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildNameField(),
          const SizedBox(height: 16),
          _buildQualityField(),
          const SizedBox(height: 24),
          _buildHubStats(),
        ],
      ),
    );
  }

  Widget _buildMoviesTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildMoviesSearch(),
          const SizedBox(height: 16),
          _buildSelectedMovies(),
        ],
      ),
    );
  }

  Widget _buildSeriesTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSeriesSearch(),
          const SizedBox(height: 16),
          _buildSelectedSeries(),
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

  Widget _buildQualityField() {
    return DropdownButtonFormField<String>(
      value: _selectedQuality,
      decoration: const InputDecoration(
        labelText: 'Quality',
        hintText: 'Select preferred quality',
        prefixIcon: Icon(Icons.high_quality),
      ),
      items: const [
        DropdownMenuItem(value: '720p', child: Text('720p')),
        DropdownMenuItem(value: '1080p', child: Text('1080p')),
        DropdownMenuItem(value: '4k', child: Text('4K')),
      ],
      onChanged: (value) {
        if (value != null) {
          setState(() {
            _selectedQuality = value;
          });
        }
      },
    );
  }

  Widget _buildHubStats() {
    final totalItems = _selectedSeries.length + _selectedMovies.length;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Hub Statistics',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                icon: Icons.tv_rounded,
                title: 'Series',
                count: _selectedSeries.length,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                icon: Icons.movie_rounded,
                title: 'Movies',
                count: _selectedMovies.length,
                color: Theme.of(context).colorScheme.secondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                Icons.inventory_2_rounded,
                color: Theme.of(context).colorScheme.primary,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total Items',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '$totalItems items in this hub',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String title,
    required int count,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            color: color,
            size: 24,
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            count.toString(),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
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
                controller: _seriesSearchController,
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
              onPressed: _isSearchingSeries 
                  ? null 
                  : () {
                      if (_seriesSearchController.text.trim().isNotEmpty) {
                        _searchSeries(_seriesSearchController.text);
                      }
                    },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              child: _isSearchingSeries
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Search'),
            ),
          ],
        ),
        if (_seriesSearchResults.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _seriesSearchResults.length,
              itemBuilder: (context, index) {
                final show = _seriesSearchResults[index];
                final showId = show['id'];
                final isSelected = showId != null && _selectedSeries.any((s) => s.id == showId);
                
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
                      show['name']?.toString() ?? 'Unknown Series',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    subtitle: Text(
                      (show['genres'] as List<dynamic>?)?.join(', ') ?? 'No genres',
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

  Widget _buildMoviesSearch() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Add Movies',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _moviesSearchController,
                decoration: InputDecoration(
                  labelText: 'Search for movies',
                  hintText: 'Enter movie name to search...',
                  prefixIcon: const Icon(Icons.search),
                ),
                onFieldSubmitted: (value) {
                  if (value.trim().isNotEmpty && !_isAddingMovie) {
                    _searchMovies(value);
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: (_isSearchingMovies || _isAddingMovie)
                  ? null 
                  : () {
                      if (_moviesSearchController.text.trim().isNotEmpty) {
                        _searchMovies(_moviesSearchController.text);
                      }
                    },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              child: _isSearchingMovies
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Search'),
            ),
          ],
        ),
        if (_moviesSearchResults.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _moviesSearchResults.length,
              itemBuilder: (context, index) {
                final movie = _moviesSearchResults[index];
                final isSelected = _selectedMovies.any((m) => m.id == movie['#IMDB_ID']);
                
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: movie['#IMG_POSTER'] != null
                          ? CachedNetworkImage(
                              imageUrl: movie['#IMG_POSTER'],
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
                                    Icons.movie_rounded,
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
                                Icons.movie_rounded,
                                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                              ),
                            ),
                    ),
                    title: Text(
                      movie['#TITLE'] ?? 'Unknown Movie',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    subtitle: Text(
                      movie['#YEAR']?.toString() ?? 'Unknown Year',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    trailing: _isAddingMovie 
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : IconButton(
                            onPressed: isSelected || _isAddingMovie ? null : () => _addMovie(movie),
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
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              Icons.tv_rounded,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
              size: 24,
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
        const SizedBox(height: 12),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _selectedSeries.length,
          itemBuilder: (context, index) {
            final series = _selectedSeries[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: series.originalImageUrl != null
                      ? CachedNetworkImage(
                          imageUrl: series.originalImageUrl!,
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
            );
          },
        ),
      ],
    );
  }

  Widget _buildSelectedMovies() {
    if (_selectedMovies.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              Icons.movie_rounded,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'No movies added yet. Search and add your favorite movies!',
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
          'Selected Movies (${_selectedMovies.length})',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _selectedMovies.length,
          itemBuilder: (context, index) {
            final movie = _selectedMovies[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: movie.originalImageUrl != null
                      ? CachedNetworkImage(
                          imageUrl: movie.originalImageUrl!,
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
                                Icons.movie_rounded,
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
                            Icons.movie_rounded,
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                ),
                title: Text(
                  movie.name,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                subtitle: Text(
                  movie.year ?? 'Unknown Year',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                trailing: IconButton(
                  onPressed: () => _removeMovie(movie),
                  icon: Icon(
                    Icons.remove_circle_outline,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildActions() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.primary,
              ),
              child: const Text('Cancel'),
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: (_isSaving || _nameController.text.trim().isEmpty) ? null : _saveChannelHub,
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
              disabledBackgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              disabledForegroundColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38),
            ),
            child: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(widget.initialHub != null ? 'Update' : 'Create'),
          ),
        ],
      ),
    );
  }
} 