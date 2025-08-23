import 'package:flutter/material.dart';
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
      height: MediaQuery.of(context).size.height * 0.85, // Reduced to 85% for more breathing room
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.grey[900]!,
            Colors.black,
            Colors.grey[800]!,
          ],
        ),
      ),
      child: Column(
        children: [
          // Top Controls Bar - Made more compact
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: Colors.white, size: 24),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: _selectedSeason,
                        dropdownColor: Colors.grey[850],
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 20),
                        items: widget.seriesPlaylist.seasons.map((season) {
                          return DropdownMenuItem(
                            value: season.seasonNumber,
                            child: Text(
                              'Season ${season.seasonNumber}',
                              style: const TextStyle(fontWeight: FontWeight.w600),
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
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _tvmazeAvailable ? Colors.green.withValues(alpha: 0.2) : Colors.red.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _tvmazeAvailable ? Colors.green : Colors.red,
                      width: 1,
                    ),
                  ),
                  child: Text(
                    _tvmazeAvailable ? 'TVMaze ✓' : 'TVMaze ✗',
                    style: TextStyle(
                      color: _tvmazeAvailable ? Colors.green : Colors.red,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Horizontal Episode Carousel - Takes most of the space
          Expanded(
            child: episodes.isEmpty
                ? const Center(
                    child: Text(
                      'No episodes found',
                      style: TextStyle(color: Colors.white70, fontSize: 18),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: episodes.length,
                    itemBuilder: (context, index) {
                      final episode = episodes[index];
                      // Fix: Compare original indices instead of sorted indices
                      final isCurrentEpisode = episode.originalIndex == widget.currentEpisodeIndex;
                      
                      // Check if this is the last played episode
                      final isLastPlayed = _lastPlayedEpisode != null &&
                          episode.seriesInfo.season == _lastPlayedEpisode!['season'] &&
                          episode.seriesInfo.episode == _lastPlayedEpisode!['episode'];
                      
                      // Check if this episode is finished
                      final isFinished = episode.seriesInfo.season != null && 
                          episode.seriesInfo.episode != null &&
                          _finishedEpisodes[episode.seriesInfo.season.toString()]?.contains(episode.seriesInfo.episode) == true;
                      
                      return Container(
                        width: MediaQuery.of(context).size.width * 0.42, // Slightly smaller for better fit
                        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2), // Reduced vertical margin
                        child: _buildEpisodeCard(episode, index, isCurrentEpisode, isLastPlayed, isFinished),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEpisodeCard(SeriesEpisode episode, int index, bool isCurrentEpisode, bool isLastPlayed, bool isFinished) {
    final tag = 'poster-${widget.seriesPlaylist.seriesTitle}-${episode.seriesInfo.season}-${episode.seriesInfo.episode}';
    final scrollOffset = _scrollController.hasClients ? _scrollController.offset : 0.0;
    final parallax = ((index * 40.0 - scrollOffset) / MediaQuery.of(context).size.width).clamp(-8.0, 8.0);
    return GestureDetector(
      onTap: () {
        print('DEBUG: Card tapped! Episode: ${episode.title}');
        
        // Use season/episode directly instead of finding index
        if (episode.seriesInfo.season != null && episode.seriesInfo.episode != null) {
          print('Playing episode S${episode.seriesInfo.season}E${episode.seriesInfo.episode} (${episode.title})');
          // Close the modal bottom sheet first
          Navigator.of(context).pop();
          // Then trigger the episode selection with season/episode
          widget.onEpisodeSelected(episode.seriesInfo.season!, episode.seriesInfo.episode!);
        } else {
          print('Episode missing season/episode info: ${episode.title}');
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), // Reduced vertical margin
        height: 280, // Further reduced height to prevent overflow
        decoration: BoxDecoration(
          color: isCurrentEpisode 
            ? Theme.of(context).colorScheme.primary.withOpacity(0.2) // Current episode - primary background
            : isLastPlayed 
              ? Theme.of(context).colorScheme.tertiary.withOpacity(0.1) // Last played - tertiary background
              : isFinished
                ? Theme.of(context).colorScheme.tertiary.withOpacity(0.1) // Finished - tertiary background
                : Theme.of(context).colorScheme.surface, // Normal - surface background
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isCurrentEpisode 
              ? Theme.of(context).colorScheme.primary // Current episode - primary border
              : isLastPlayed 
                ? Theme.of(context).colorScheme.tertiary // Last played - tertiary border
                : isFinished
                  ? Theme.of(context).colorScheme.tertiary // Finished - tertiary border
                  : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Episode image with overlay
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                  child: SizedBox(
                    height: 120, // Reduced height
                    width: double.infinity,
                    child: Transform.translate(
                      offset: Offset(parallax, 0),
                      child: Hero(
                        tag: tag,
                        child: episode.episodeInfo?.poster != null
                            ? CachedNetworkImage(
                                imageUrl: episode.episodeInfo!.poster!,
                                fit: BoxFit.cover,
                                placeholder: (context, url) => Container(
                                  color: Theme.of(context).colorScheme.surfaceVariant,
                                  child: Center(
                                    child: Icon(Icons.tv, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 32),
                                  ),
                                ),
                                errorWidget: (context, url, error) => Container(
                                  color: Theme.of(context).colorScheme.surfaceVariant,
                                  child: Center(
                                    child: Icon(Icons.error, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 32),
                                  ),
                                ),
                              )
                            : Container(
                                color: Theme.of(context).colorScheme.surfaceVariant,
                                child: Center(
                                  child: Icon(Icons.tv, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 32),
                                ),
                              ),
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
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                                              child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.play_arrow, color: Theme.of(context).colorScheme.onPrimary, size: 16),
                            const SizedBox(width: 4),
                            Text(
                              'NOW',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onPrimary,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
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
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.tertiary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.history, color: Theme.of(context).colorScheme.onTertiary, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            'LAST',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onTertiary,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                // Finished episode indicator
                if (isFinished && !isCurrentEpisode && !isLastPlayed)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.tertiary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle, color: Theme.of(context).colorScheme.onTertiary, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            'DONE',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onTertiary,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            
            // Episode Info Section - Compact
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(10), // Reduced padding
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Episode Title - Compact
                    Text(
                      episode.title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    
                    const SizedBox(height: 6), // Reduced spacing
                    
                    // Metadata Row - Compact
                    Row(
                      children: [
                        // Season/Episode
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                        
                        const SizedBox(width: 8),
                        
                        // Runtime
                        if (episode.episodeInfo?.runtime != null) ...[
                          const Icon(Icons.access_time, color: Colors.white70, size: 12),
                          const SizedBox(width: 2),
                          Text(
                            '${episode.episodeInfo!.runtime} min',
                            style: const TextStyle(color: Colors.white70, fontSize: 10),
                          ),
                          const SizedBox(width: 8),
                        ],
                        
                        // Rating
                        if (episode.episodeInfo?.rating != null) ...[
                          const Icon(Icons.star, color: Colors.amber, size: 12),
                          const SizedBox(width: 2),
                          Text(
                            episode.episodeInfo!.rating!.toStringAsFixed(1),
                            style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.w600, fontSize: 10),
                          ),
                        ] else if (_tvmazeAvailable) ...[
                          Text(
                            'No rating',
                            style: TextStyle(color: Colors.red.withValues(alpha: 0.7), fontSize: 8),
                          ),
                        ],
                      ],
                    ),
                    
                    const Spacer(),
                    
                    // Tap to play hint - More compact
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10), // Reduced padding
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isCurrentEpisode 
                            ? Colors.green.withValues(alpha: 0.3) 
                            : isFinished
                              ? const Color(0xFF059669).withValues(alpha: 0.3)
                              : Colors.white.withValues(alpha: 0.2),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            isCurrentEpisode 
                              ? Icons.play_arrow 
                              : isFinished
                                ? Icons.replay
                                : Icons.touch_app,
                            color: isCurrentEpisode 
                              ? Colors.green 
                              : isFinished
                                ? const Color(0xFF059669)
                                : Colors.white70,
                            size: 12, // Smaller icon
                          ),
                          const SizedBox(width: 4), // Reduced spacing
                          Text(
                            isCurrentEpisode 
                              ? 'Now Playing' 
                              : isFinished
                                ? 'Replay'
                                : 'Tap to Play',
                            style: TextStyle(
                              color: isCurrentEpisode 
                                ? Colors.green 
                                : isFinished
                                  ? const Color(0xFF059669)
                                  : Colors.white70,
                              fontSize: 11, // Smaller font
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
} 