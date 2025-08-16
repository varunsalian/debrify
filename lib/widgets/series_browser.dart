import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/series_playlist.dart';

class SeriesBrowser extends StatefulWidget {
  final SeriesPlaylist seriesPlaylist;
  final int currentEpisodeIndex;
  final Function(int episodeIndex) onEpisodeSelected;

  const SeriesBrowser({
    super.key,
    required this.seriesPlaylist,
    required this.currentEpisodeIndex,
    required this.onEpisodeSelected,
  });

  @override
  State<SeriesBrowser> createState() => _SeriesBrowserState();
}

class _SeriesBrowserState extends State<SeriesBrowser> {
  int _selectedSeason = 1;
  bool _isLoadingEpisodeInfo = false;
  Set<String> _loadingEpisodes = {};

  @override
  void initState() {
    super.initState();
    // Find the season of the current episode
    final currentEpisode = widget.seriesPlaylist.allEpisodes[widget.currentEpisodeIndex];
    if (currentEpisode.seriesInfo.season != null) {
      _selectedSeason = currentEpisode.seriesInfo.season!;
    }
    
    // Start background loading of episode info
    _startBackgroundEpisodeInfoLoading();
  }

  Future<void> _startBackgroundEpisodeInfoLoading() async {
    print('Starting background episode info loading...');
    
    // Check if any episode already has info loaded
    bool hasLoadedInfo = false;
    for (final season in widget.seriesPlaylist.seasons) {
      for (final episode in season.episodes) {
        if (episode.episodeInfo != null) {
          hasLoadedInfo = true;
          print('Found existing episode info for: ${episode.seriesInfo.title} S${episode.seriesInfo.season}E${episode.seriesInfo.episode}');
          break;
        }
      }
      if (hasLoadedInfo) break;
    }

    // If no episode info is loaded, start background loading
    if (!hasLoadedInfo) {
      print('No episode info found, starting background loading...');
      _loadEpisodeInfoInBackground();
    } else {
      print('Episode info already loaded, skipping background loading');
    }
  }

  Future<void> _loadEpisodeInfoInBackground() async {
    if (!widget.seriesPlaylist.isSeries || widget.seriesPlaylist.seriesTitle == null) return;

    // Load episode info for all episodes in the background
    for (final season in widget.seriesPlaylist.seasons) {
      for (final episode in season.episodes) {
        if (episode.seriesInfo.season != null && episode.seriesInfo.episode != null) {
          final episodeKey = 'S${episode.seriesInfo.season}E${episode.seriesInfo.episode}';
          
          // Skip if already loaded or currently loading
          if (episode.episodeInfo != null || _loadingEpisodes.contains(episodeKey)) {
            continue;
          }

          // Mark as loading
          setState(() {
            _loadingEpisodes.add(episodeKey);
          });

          try {
            final episodeInfo = await widget.seriesPlaylist.getEpisodeInfoForEpisode(
              widget.seriesPlaylist.seriesTitle!,
              episode.seriesInfo.season!,
              episode.seriesInfo.episode!,
            );
            
            if (mounted) {
              setState(() {
                episode.episodeInfo = episodeInfo;
                _loadingEpisodes.remove(episodeKey);
              });
            }
          } catch (e) {
            print('Failed to fetch episode info for $episodeKey: $e');
            if (mounted) {
              setState(() {
                _loadingEpisodes.remove(episodeKey);
              });
            }
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0F172A),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.tv_rounded, color: Colors.white, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.seriesPlaylist.seriesTitle ?? 'Series',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (widget.seriesPlaylist.allEpisodes.isNotEmpty)
                        Text(
                          '${widget.seriesPlaylist.allEpisodes.length} episodes',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ],
            ),
          ),
          
          // Season selector
          if (widget.seriesPlaylist.seasons.length > 1) ...[
            Container(
              height: 50,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: widget.seriesPlaylist.seasons.length,
                itemBuilder: (context, index) {
                  final season = widget.seriesPlaylist.seasons[index];
                  final isSelected = season.seasonNumber == _selectedSeason;
                  
                  return Container(
                    margin: const EdgeInsets.only(right: 8),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _selectedSeason = season.seasonNumber;
                          });
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0xFF6366F1) : const Color(0xFF334155),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              'Season ${season.seasonNumber}',
                              style: TextStyle(
                                color: isSelected ? Colors.white : Colors.white70,
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
          
          // Episodes list
          Expanded(
            child: _buildEpisodesHorizontalList(),
          ),
        ],
      ),
    );
  }

  Widget _buildEpisodesHorizontalList() {
    final selectedSeason = widget.seriesPlaylist.getSeason(_selectedSeason);
    if (selectedSeason == null) {
      return const Center(
        child: Text(
          'No episodes found for this season',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    return ListView.builder(
      scrollDirection: Axis.horizontal,
      itemCount: selectedSeason.episodes.length,
      itemBuilder: (context, index) {
        final episode = selectedSeason.episodes[index];
        final isCurrentEpisode = episode.originalIndex == widget.currentEpisodeIndex;
        final episodeKey = 'S${episode.seriesInfo.season}E${episode.seriesInfo.episode}';
        final isLoading = _loadingEpisodes.contains(episodeKey);
        
        return Container(
          width: 200, // Fixed width for each episode card
          margin: const EdgeInsets.only(right: 16),
          child: _EpisodeCard(
            episode: episode,
            isCurrentEpisode: isCurrentEpisode,
            isLoading: isLoading,
            onTap: () {
              widget.onEpisodeSelected(episode.originalIndex);
              Navigator.of(context).pop();
            },
          ),
        );
      },
    );
  }
}

class _EpisodeCard extends StatelessWidget {
  final SeriesEpisode episode;
  final bool isCurrentEpisode;
  final bool isLoading;
  final VoidCallback onTap;

  const _EpisodeCard({
    required this.episode,
    required this.isCurrentEpisode,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(12),
            border: isCurrentEpisode
                ? Border.all(color: const Color(0xFF6366F1), width: 2)
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Episode thumbnail
              Expanded(
                flex: 3,
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      topRight: Radius.circular(12),
                    ),
                  ),
                  child: Stack(
                    children: [
                      // Episode poster or placeholder
                      ClipRRect(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(12),
                          topRight: Radius.circular(12),
                        ),
                        child: episode.episodeInfo?.poster != null
                            ? CachedNetworkImage(
                                imageUrl: episode.episodeInfo!.poster!,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: double.infinity,
                                placeholder: (context, url) => Container(
                                  color: const Color(0xFF334155),
                                  child: const Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white70,
                                    ),
                                  ),
                                ),
                                errorWidget: (context, url, error) => Container(
                                  color: const Color(0xFF334155),
                                  child: const Center(
                                    child: Icon(
                                      Icons.play_circle_outline,
                                      size: 48,
                                      color: Colors.white70,
                                    ),
                                  ),
                                ),
                              )
                            : Container(
                                color: const Color(0xFF334155),
                                child: Center(
                                  child: isLoading
                                      ? const CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white70,
                                        )
                                      : const Icon(
                                          Icons.play_circle_outline,
                                          size: 48,
                                          color: Colors.white70,
                                        ),
                                ),
                              ),
                      ),
                      
                      // Current episode indicator
                      if (isCurrentEpisode)
                        Positioned(
                          top: 8,
                          left: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6366F1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'NOW',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      
                      // Loading indicator overlay
                      if (isLoading)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              
              // Episode info
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        episode.seasonEpisodeString,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Expanded(
                        child: Text(
                          episode.episodeInfo?.title ?? episode.displayTitle,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
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