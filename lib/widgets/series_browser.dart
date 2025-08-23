import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/series_playlist.dart';
import '../services/episode_info_service.dart';
import '../services/storage_service.dart';

class SeriesBrowser extends StatefulWidget {
  final SeriesPlaylist seriesPlaylist;
  final Function(int season, int episode) onEpisodeSelected;
  final int currentEpisodeIndex;

  const SeriesBrowser({
    super.key,
    required this.seriesPlaylist,
    required this.onEpisodeSelected,
    required this.currentEpisodeIndex,
  });

  @override
  State<SeriesBrowser> createState() => _SeriesBrowserState();
}

class _SeriesBrowserState extends State<SeriesBrowser> {
  final Set<String> _loadingEpisodes = {};
  bool _tvmazeAvailable = false;
  int _selectedSeason = 1;
  final ScrollController _scrollController = ScrollController();
  Map<String, dynamic>? _lastPlayedEpisode;
  Map<String, Set<int>> _finishedEpisodes = {}; // Map of season -> Set of episode numbers

  @override
  void initState() {
    super.initState();
    _initializeSeason();
    _checkTVMazeAvailability();
    _loadLastPlayedEpisode();
    _loadFinishedEpisodes();
    // Schedule scrolling to current episode after the widget is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToCurrentEpisode();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Refresh finished episodes when dependencies change (e.g., when modal is shown)
    _loadFinishedEpisodes();
  }

  void _initializeSeason() {
    if (widget.seriesPlaylist.seasons.isNotEmpty) {
      // Find the current episode from the currentEpisodeIndex
      if (widget.currentEpisodeIndex >= 0) {
        // Find the episode with the matching original index
        final currentEpisode = widget.seriesPlaylist.allEpisodes.firstWhere(
          (episode) => episode.originalIndex == widget.currentEpisodeIndex,
          orElse: () => widget.seriesPlaylist.allEpisodes.first, // Fallback to first episode
        );
        
        if (currentEpisode.seriesInfo.season != null) {
          _selectedSeason = currentEpisode.seriesInfo.season!;
          print('Auto-selected season ${_selectedSeason} for current episode S${currentEpisode.seriesInfo.season}E${currentEpisode.seriesInfo.episode}');
          return;
        }
      }
      
      // Fallback to first season if current episode not found or not a series
      _selectedSeason = widget.seriesPlaylist.seasons.first.seasonNumber;
      print('Fallback to first season: $_selectedSeason');
    }
  }

  Future<void> _checkTVMazeAvailability() async {
    await EpisodeInfoService.refreshAvailability();
    setState(() {
      _tvmazeAvailable = EpisodeInfoService.isTVMazeAvailable;
    });
    
    // Start loading episode info after TVMaze availability is confirmed
    if (_tvmazeAvailable) {
      _startBackgroundEpisodeInfoLoading();
    }
  }

  void _startBackgroundEpisodeInfoLoading() {
    if (widget.seriesPlaylist.isSeries && widget.seriesPlaylist.seriesTitle != null && _tvmazeAvailable) {
      print('Starting background episode info loading for: ${widget.seriesPlaylist.seriesTitle}');
      _loadEpisodeInfoInBackground();
    } else {
      print('Episode info loading skipped - Series: ${widget.seriesPlaylist.isSeries}, Title: ${widget.seriesPlaylist.seriesTitle}, TVMaze: $_tvmazeAvailable');
    }
  }

  Future<void> _loadEpisodeInfoInBackground() async {
    final selectedSeason = widget.seriesPlaylist.getSeason(_selectedSeason);
    if (selectedSeason == null) {
      print('No season found for season number: $_selectedSeason');
      return;
    }

    print('Loading episode info for ${selectedSeason.episodes.length} episodes in season $_selectedSeason');

    // Clear previous loading states for this season
    _loadingEpisodes.clear();

    for (final episode in selectedSeason.episodes) {
      if (episode.seriesInfo.season != null && episode.seriesInfo.episode != null) {
        final episodeKey = '${episode.seriesInfo.season}_${episode.seriesInfo.episode}';
        if (!_loadingEpisodes.contains(episodeKey)) {
          print('Loading episode info for S${episode.seriesInfo.season}E${episode.seriesInfo.episode}');
          _loadingEpisodes.add(episodeKey);
          _loadEpisodeInfo(episode);
        }
      } else {
        print('Skipping episode - missing season/episode info: ${episode.title}');
      }
    }
  }

  Future<void> _loadEpisodeInfo(SeriesEpisode episode) async {
    if (episode.seriesInfo.season != null && episode.seriesInfo.episode != null) {
      try {
        print('Fetching episode info for S${episode.seriesInfo.season}E${episode.seriesInfo.episode} from TVMaze');
        final episodeData = await EpisodeInfoService.getEpisodeInfo(
          widget.seriesPlaylist.seriesTitle!,
          episode.seriesInfo.season!,
          episode.seriesInfo.episode!,
        );
        
        if (episodeData != null && mounted) {
          print('Successfully loaded episode info for S${episode.seriesInfo.season}E${episode.seriesInfo.episode}');
          setState(() {
            episode.episodeInfo = EpisodeInfo.fromTVMaze(episodeData);
          });
        } else {
          print('No episode data returned for S${episode.seriesInfo.season}E${episode.seriesInfo.episode}');
        }
      } catch (e) {
        print('Failed to load episode info for S${episode.seriesInfo.season}E${episode.seriesInfo.episode}: $e');
      } finally {
        final episodeKey = '${episode.seriesInfo.season}_${episode.seriesInfo.episode}';
        _loadingEpisodes.remove(episodeKey);
      }
    }
  }

  /// Load the last played episode for this series
  Future<void> _loadLastPlayedEpisode() async {
    try {
      final lastEpisode = await StorageService.getLastPlayedEpisode(
        seriesTitle: widget.seriesPlaylist.seriesTitle ?? 'Unknown Series',
      );
      if (lastEpisode != null) {
        setState(() {
          _lastPlayedEpisode = lastEpisode;
        });
      }
    } catch (e) {
      print('Error loading last played episode: $e');
    }
  }

  /// Load finished episodes for the entire series
  Future<void> _loadFinishedEpisodes() async {
    try {
      if (widget.seriesPlaylist.isSeries && widget.seriesPlaylist.seriesTitle != null) {
        final allFinishedEpisodes = await StorageService.getFinishedEpisodes(
          seriesTitle: widget.seriesPlaylist.seriesTitle!,
        );
        setState(() {
          _finishedEpisodes = allFinishedEpisodes;
        });
      }
    } catch (e) {
      print('Error loading finished episodes: $e');
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToCurrentEpisode() {
    if (widget.currentEpisodeIndex >= 0 && 
        widget.currentEpisodeIndex < widget.seriesPlaylist.allEpisodes.length) {
      final selectedSeason = widget.seriesPlaylist.getSeason(_selectedSeason);
      
      if (selectedSeason != null) {
        // Find the index of the current episode within the selected season
        final episodeIndexInSeason = selectedSeason.episodes.indexWhere(
          (episode) => episode.originalIndex == widget.currentEpisodeIndex
        );
        
        if (episodeIndexInSeason != -1) {
          // Calculate scroll position to center the current episode
          final itemWidth = MediaQuery.of(context).size.width * 0.42 + 8; // card width + margin
          final scrollPosition = episodeIndexInSeason * itemWidth - 
                               (MediaQuery.of(context).size.width - itemWidth) / 2;
          
          // Animate to the current episode
          _scrollController.animateTo(
            scrollPosition.clamp(0.0, _scrollController.position.maxScrollExtent),
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
          );
          
          print('Scrolled to current episode at index $episodeIndexInSeason in season $_selectedSeason');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedSeason = widget.seriesPlaylist.getSeason(_selectedSeason);
    if (selectedSeason == null) {
      print('DEBUG: selectedSeason is null for season $_selectedSeason');
      return const Center(child: CircularProgressIndicator());
    }

    final episodes = selectedSeason.episodes;
    print('DEBUG: selectedSeason: ${selectedSeason.seasonNumber}, episodes count: ${episodes.length}');
    print('DEBUG: episodes: ${episodes.map((e) => e.title).toList()}');
    
    return Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.surface,
              Theme.of(context).colorScheme.surfaceVariant,
              Theme.of(context).colorScheme.surface,
            ],
          ),
        ),
      child: Column(
        children: [
          // Top Controls Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(
                    Icons.close, 
                    color: Theme.of(context).colorScheme.onSurface, 
                    size: 20
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 40, 
                    minHeight: 40
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3)
                      ),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: _selectedSeason,
                        dropdownColor: Theme.of(context).colorScheme.surface,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface, 
                          fontSize: 12
                        ),
                        icon: Icon(
                          Icons.keyboard_arrow_down, 
                          color: Theme.of(context).colorScheme.onSurface, 
                          size: 16
                        ),
                        items: widget.seriesPlaylist.seasons.map((season) {
                          return DropdownMenuItem(
                            value: season.seasonNumber,
                            child: Text(
                              'Season ${season.seasonNumber}',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _selectedSeason = value;
                            });
                            // Load episode info for the new season
                            _startBackgroundEpisodeInfoLoading();
                            // Load finished episodes for the new season
                            _loadFinishedEpisodes();
                            // Scroll to current episode in the new season
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              _scrollToCurrentEpisode();
                            });
                          }
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: _tvmazeAvailable 
                        ? Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.2) 
                        : Theme.of(context).colorScheme.error.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _tvmazeAvailable 
                          ? Theme.of(context).colorScheme.tertiary 
                          : Theme.of(context).colorScheme.error,
                      width: 1,
                    ),
                  ),
                  child: Text(
                    _tvmazeAvailable ? 'TVMaze ✓' : 'TVMaze ✗',
                    style: TextStyle(
                      color: _tvmazeAvailable 
                          ? Theme.of(context).colorScheme.tertiary 
                          : Theme.of(context).colorScheme.error,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Horizontal Episode Carousel
          Expanded(
            child: episodes.isEmpty
                ? Center(
                    child: Text(
                      'No episodes found',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant, 
                        fontSize: 18
                      ),
                    ),
                  )
                : GridView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    physics: const AlwaysScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 0.65,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                    ),
                    itemCount: episodes.length,
                    itemBuilder: (context, index) {
                      final episode = episodes[index];
                      final isCurrentEpisode = episode.originalIndex == widget.currentEpisodeIndex;
                      final isLastPlayed = _lastPlayedEpisode != null &&
                          episode.seriesInfo.season == _lastPlayedEpisode!['season'] &&
                          episode.seriesInfo.episode == _lastPlayedEpisode!['episode'];
                      final isFinished = episode.seriesInfo.season != null && 
                          episode.seriesInfo.episode != null &&
                          _finishedEpisodes[episode.seriesInfo.season.toString()]?.contains(episode.seriesInfo.episode) == true;
                      
                      return _buildEpisodeCard(episode, index, isCurrentEpisode, isLastPlayed, isFinished);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEpisodeCard(SeriesEpisode episode, int index, bool isCurrentEpisode, bool isLastPlayed, bool isFinished) {
    final tag = 'poster-${widget.seriesPlaylist.seriesTitle}-${episode.seriesInfo.season}-${episode.seriesInfo.episode}';
    
    return GestureDetector(
      onTap: () {
        if (episode.seriesInfo.season != null && episode.seriesInfo.episode != null) {
          print('Playing episode S${episode.seriesInfo.season}E${episode.seriesInfo.episode} (${episode.title})');
          Navigator.of(context).pop();
          widget.onEpisodeSelected(episode.seriesInfo.season!, episode.seriesInfo.episode!);
        } else {
          print('Episode missing season/episode info: ${episode.title}');
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: isCurrentEpisode 
            ? Theme.of(context).colorScheme.primary.withOpacity(0.2)
            : isLastPlayed 
              ? Theme.of(context).colorScheme.tertiary.withOpacity(0.1)
              : isFinished
                ? Theme.of(context).colorScheme.tertiary.withOpacity(0.1)
                : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isCurrentEpisode 
              ? Theme.of(context).colorScheme.primary
              : isLastPlayed 
                ? Theme.of(context).colorScheme.tertiary
                : isFinished
                  ? Theme.of(context).colorScheme.tertiary
                  : Colors.transparent,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: isCurrentEpisode 
                ? Theme.of(context).colorScheme.primary.withOpacity(0.3)
                : Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Episode image
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
              child: Stack(
                children: [
                  SizedBox(
                    height: 110,
                    width: double.infinity,
                    child: Hero(
                      tag: tag,
                      child: episode.episodeInfo?.poster != null
                          ? CachedNetworkImage(
                              imageUrl: episode.episodeInfo!.poster!,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                color: Theme.of(context).colorScheme.surfaceVariant,
                                child: Center(
                                  child: Icon(Icons.tv, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 24),
                                ),
                              ),
                              errorWidget: (context, url, error) => Container(
                                color: Theme.of(context).colorScheme.surfaceVariant,
                                child: Center(
                                  child: Icon(Icons.error, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 24),
                                ),
                              ),
                            )
                          : Container(
                              color: Theme.of(context).colorScheme.surfaceVariant,
                              child: Center(
                                child: Icon(Icons.tv, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 24),
                              ),
                            ),
                    ),
                  ),
                  // Current episode indicator
                  if (isCurrentEpisode)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.play_arrow,
                              color: Theme.of(context).colorScheme.onPrimary,
                              size: 12,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              'NOW',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onPrimary,
                                fontSize: 8,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  // Last played indicator
                  if (isLastPlayed && !isCurrentEpisode)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.tertiary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.replay,
                              color: Theme.of(context).colorScheme.onTertiary,
                              size: 12,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              'LAST',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onTertiary,
                                fontSize: 8,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  // Finished indicator
                  if (isFinished && !isCurrentEpisode && !isLastPlayed)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.tertiary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.check,
                              color: Theme.of(context).colorScheme.onTertiary,
                              size: 12,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              'DONE',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onTertiary,
                                fontSize: 8,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            
            // Episode info
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Episode title
                    Flexible(
                      child: Text(
                        episode.filename,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 11,
                          height: 1.2,
                        ),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    
                    const SizedBox(height: 6),
                    
                    // Metadata Row
                    Row(
                      children: [
                        // Season/Episode
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            episode.seasonEpisodeString.isNotEmpty
                                ? episode.seasonEpisodeString
                                : 'Episode ${index + 1}',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        
                        const SizedBox(width: 6),
                        
                        // Runtime
                        if (episode.episodeInfo?.runtime != null) ...[
                          Icon(
                            Icons.access_time, 
                            color: Theme.of(context).colorScheme.onSurfaceVariant, 
                            size: 10
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '${episode.episodeInfo!.runtime} min',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurfaceVariant, 
                              fontSize: 10
                            ),
                          ),
                        ],
                      ],
                    ),
                    
                    const Spacer(),
                    
                    // Play button
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: isCurrentEpisode
                              ? [
                                  Theme.of(context).colorScheme.primary,
                                  Theme.of(context).colorScheme.primary.withOpacity(0.8),
                                ]
                              : isFinished
                                  ? [
                                      Theme.of(context).colorScheme.tertiary,
                                      Theme.of(context).colorScheme.tertiary.withOpacity(0.8),
                                    ]
                                  : [
                                      Theme.of(context).colorScheme.surfaceVariant,
                                      Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.8),
                                    ],
                        ),
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: isCurrentEpisode
                                ? Theme.of(context).colorScheme.primary.withOpacity(0.3)
                                : Colors.black.withOpacity(0.1),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            isCurrentEpisode ? Icons.play_arrow : Icons.play_arrow,
                            color: isCurrentEpisode 
                                ? Theme.of(context).colorScheme.onPrimary
                                : Theme.of(context).colorScheme.onSurfaceVariant,
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isCurrentEpisode ? 'Now Playing' : 'Play',
                            style: TextStyle(
                              color: isCurrentEpisode 
                                  ? Theme.of(context).colorScheme.onPrimary
                                  : Theme.of(context).colorScheme.onSurfaceVariant,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
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

  String _cleanSummary(String summary) {
    // Remove HTML tags and extra whitespace
    return summary.replaceAll(RegExp(r'<[^>]*>'), '').replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  }
} 