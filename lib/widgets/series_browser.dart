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

  @override
  void initState() {
    super.initState();
    // Find the season of the current episode
    final currentEpisode = widget.seriesPlaylist.allEpisodes[widget.currentEpisodeIndex];
    if (currentEpisode.seriesInfo.season != null) {
      _selectedSeason = currentEpisode.seriesInfo.season!;
    }
    
    // Check if episode info is already loaded, if not, fetch it
    _ensureEpisodeInfoLoaded();
  }

  Future<void> _ensureEpisodeInfoLoaded() async {
    print('Checking if episode info is already loaded...');
    
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

    // If no episode info is loaded, fetch it
    if (!hasLoadedInfo) {
      print('No episode info found, fetching...');
      if (mounted) {
        setState(() {
          _isLoadingEpisodeInfo = true;
        });
      }
      
      await widget.seriesPlaylist.fetchEpisodeInfo();
      
      if (mounted) {
        setState(() {
          _isLoadingEpisodeInfo = false;
        });
      }
      print('Episode info fetch completed');
    } else {
      print('Episode info already loaded, skipping fetch');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0F172A),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.seriesPlaylist.seriesTitle ?? 'Series',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${widget.seriesPlaylist.seasonCount} Season${widget.seriesPlaylist.seasonCount > 1 ? 's' : ''} • ${widget.seriesPlaylist.totalEpisodes} Episode${widget.seriesPlaylist.totalEpisodes > 1 ? 's' : ''}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          
          // Season selector
          Container(
            height: 60,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: widget.seriesPlaylist.seasons.length,
              itemBuilder: (context, index) {
                final season = widget.seriesPlaylist.seasons[index];
                final isSelected = season.seasonNumber == _selectedSeason;
                
                return Container(
                  margin: const EdgeInsets.only(right: 12),
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
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFF6366F1) : const Color(0xFF334155),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            'Season ${season.seasonNumber}',
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.white70,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
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
          
          const SizedBox(height: 20),
          
          // Episodes horizontal list
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _isLoadingEpisodeInfo
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(
                            color: Colors.white70,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Loading episode information...',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    )
                  : _buildEpisodesHorizontalList(),
            ),
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
        
        return Container(
          width: 200, // Fixed width for each episode card
          margin: const EdgeInsets.only(right: 16),
          child: _EpisodeCard(
            episode: episode,
            isCurrentEpisode: isCurrentEpisode,
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
  final VoidCallback onTap;

  const _EpisodeCard({
    required this.episode,
    required this.isCurrentEpisode,
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
                                child: const Center(
                                  child: Icon(
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
                          right: 8,
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
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      
                      // Rating
                      if (episode.episodeInfo?.rating != null)
                        Positioned(
                          bottom: 8,
                          left: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.star,
                                  color: Color(0xFFFFD700),
                                  size: 12,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  episode.episodeInfo!.rating!,
                                  style: const TextStyle(
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