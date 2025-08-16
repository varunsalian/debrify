import 'package:flutter/material.dart';
import '../models/series_playlist.dart';
import '../services/episode_info_service.dart';

class SeriesBrowser extends StatefulWidget {
  final SeriesPlaylist seriesPlaylist;
  final Function(int) onEpisodeSelected;
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

  @override
  void initState() {
    super.initState();
    _initializeSeason();
    _checkTVMazeAvailability();
  }

  void _initializeSeason() {
    if (widget.seriesPlaylist.seasons.isNotEmpty) {
      _selectedSeason = widget.seriesPlaylist.seasons.first.seasonNumber;
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

  @override
  void dispose() {
    super.dispose();
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
      height: MediaQuery.of(context).size.height * 0.9, // Increased to 90% for more space
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
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: episodes.length,
                    itemBuilder: (context, index) {
                      final episode = episodes[index];
                      final isCurrentEpisode = widget.seriesPlaylist.allEpisodes.indexOf(episode) == widget.currentEpisodeIndex;
                      
                      return Container(
                        width: MediaQuery.of(context).size.width * 0.42, // Slightly smaller for better fit
                        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        child: _buildEpisodeCard(episode, index, isCurrentEpisode),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEpisodeCard(SeriesEpisode episode, int index, bool isCurrentEpisode) {
    return GestureDetector(
      onTap: () {
        print('DEBUG: Card tapped! Episode: ${episode.title}');
        // Find the correct index in allEpisodes list
        final allEpisodesIndex = widget.seriesPlaylist.allEpisodes.indexOf(episode);
        print('DEBUG: Found index: $allEpisodesIndex');
        
        if (allEpisodesIndex != -1) {
          print('Playing episode at index: $allEpisodesIndex (${episode.title})');
          // Close the modal bottom sheet first
          Navigator.of(context).pop();
          // Then trigger the episode selection
          widget.onEpisodeSelected(allEpisodesIndex);
        } else {
          print('Episode not found in allEpisodes list: ${episode.title}');
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        height: 320, // Significantly reduced height to prevent overflow
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF1E293B),
              const Color(0xFF334155),
              const Color(0xFF475569),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
          // Add border for currently playing episode
          border: isCurrentEpisode 
              ? Border.all(color: Colors.green, width: 2)
              : null,
        ),
        child: Stack(
          children: [
            Column(
              children: [
                // Episode Poster Image - Compact
                if (episode.episodeInfo?.poster != null)
                  Container(
                    height: 140, // Reduced height to fit better
                    width: double.infinity,
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                      child: Image.network(
                        episode.episodeInfo!.poster!,
                        fit: BoxFit.cover,
                        // Add caching
                        cacheWidth: 300,
                        cacheHeight: 200,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            decoration: BoxDecoration(
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.blue.withValues(alpha: 0.3),
                                  Colors.purple.withValues(alpha: 0.3),
                                ],
                              ),
                            ),
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.tv,
                                    color: Colors.white.withValues(alpha: 0.6),
                                    size: 24,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    episode.seasonEpisodeString.isNotEmpty
                                        ? episode.seasonEpisodeString
                                        : 'Episode ${index + 1}',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.8),
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                
                // Episode Info Section - Compact
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Episode Title - Compact
                        Text(
                          episode.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        
                        const SizedBox(height: 8),
                        
                        // Metadata Row - Compact
                        Row(
                          children: [
                            // Season/Episode
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.blue.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                episode.seasonEpisodeString.isNotEmpty
                                    ? episode.seasonEpisodeString
                                    : 'Episode ${index + 1}',
                                style: const TextStyle(
                                  color: Colors.blue,
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
                        
                        // Tap to play hint
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isCurrentEpisode ? Colors.green.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.2),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                isCurrentEpisode ? Icons.play_arrow : Icons.touch_app,
                                color: isCurrentEpisode ? Colors.green : Colors.white70,
                                size: 14,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                isCurrentEpisode ? 'Now Playing' : 'Tap to Play',
                                style: TextStyle(
                                  color: isCurrentEpisode ? Colors.green : Colors.white70,
                                  fontSize: 12,
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
            
            // Currently Playing Indicator
            if (isCurrentEpisode)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.play_arrow, color: Colors.white, size: 12),
                      const SizedBox(width: 4),
                      const Text(
                        'NOW',
                        style: TextStyle(
                          color: Colors.white,
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
      ),
    );
  }
} 