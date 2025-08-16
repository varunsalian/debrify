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

class _SeriesBrowserState extends State<SeriesBrowser> with TickerProviderStateMixin {
  late TabController _tabController;
  final Set<String> _loadingEpisodes = {};
  int _selectedSeason = 1;
  bool _tvmazeAvailable = true;

  @override
  void initState() {
    super.initState();
    _selectedSeason = widget.seriesPlaylist.seasons.first.seasonNumber;
    _tabController = TabController(
      length: widget.seriesPlaylist.seasonCount,
      vsync: this,
    );
    _checkTVMazeAvailability();
    _startBackgroundEpisodeInfoLoading();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _checkTVMazeAvailability() async {
    await EpisodeInfoService.refreshAvailability();
    if (mounted) {
      setState(() {
        _tvmazeAvailable = EpisodeInfoService.isTVMazeAvailable;
      });
    }
  }

  void _startBackgroundEpisodeInfoLoading() {
    if (widget.seriesPlaylist.isSeries && widget.seriesPlaylist.seriesTitle != null && _tvmazeAvailable) {
      _loadEpisodeInfoInBackground();
    }
  }

  Future<void> _loadEpisodeInfoInBackground() async {
    for (final season in widget.seriesPlaylist.seasons) {
      for (final episode in season.episodes) {
        if (episode.seriesInfo.season != null && episode.seriesInfo.episode != null) {
          final episodeKey = '${episode.seriesInfo.season}_${episode.seriesInfo.episode}';
          if (!_loadingEpisodes.contains(episodeKey)) {
            _loadingEpisodes.add(episodeKey);
            _loadEpisodeInfo(episode);
          }
        }
      }
    }
  }

  Future<void> _loadEpisodeInfo(SeriesEpisode episode) async {
    if (episode.seriesInfo.season != null && episode.seriesInfo.episode != null) {
      try {
        final episodeData = await EpisodeInfoService.getEpisodeInfo(
          widget.seriesPlaylist.seriesTitle!,
          episode.seriesInfo.season!,
          episode.seriesInfo.episode!,
        );
        
        if (episodeData != null && mounted) {
          setState(() {
            episode.episodeInfo = EpisodeInfo.fromTVMaze(episodeData);
          });
        }
      } catch (e) {
        print('Failed to load episode info: $e');
      } finally {
        final episodeKey = '${episode.seriesInfo.season}_${episode.seriesInfo.episode}';
        _loadingEpisodes.remove(episodeKey);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF0F172A),
            const Color(0xFF1E293B),
            const Color(0xFF334155),
          ],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Top controls bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // TVMaze status indicator
                  if (!_tvmazeAvailable)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFF59E0B)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            color: Color(0xFFF59E0B),
                            size: 14,
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'Episode info unavailable',
                            style: TextStyle(
                              color: Color(0xFFF59E0B),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    const SizedBox.shrink(),
                  
                  // Season selector
                  if (widget.seriesPlaylist.seasonCount > 1)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF475569).withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFF64748B)),
                      ),
                      child: DropdownButton<int>(
                        value: _selectedSeason,
                        dropdownColor: const Color(0xFF1E293B),
                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                        underline: Container(),
                        icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white70),
                        items: widget.seriesPlaylist.seasons.map((season) {
                          return DropdownMenuItem<int>(
                            value: season.seasonNumber,
                            child: Text(
                              'Season ${season.seasonNumber}',
                              style: const TextStyle(color: Colors.white),
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _selectedSeason = value;
                            });
                          }
                        },
                      ),
                    ),
                ],
              ),
            ),
            
            // Episodes grid
            Expanded(
              child: _buildEpisodesGrid(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEpisodesGrid() {
    final selectedSeason = widget.seriesPlaylist.getSeason(_selectedSeason);
    if (selectedSeason == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.7,
          crossAxisSpacing: 16,
          mainAxisSpacing: 20,
        ),
        itemCount: selectedSeason.episodes.length,
        itemBuilder: (context, index) {
          final episode = selectedSeason.episodes[index];
          final isCurrentEpisode = widget.seriesPlaylist.allEpisodes.indexOf(episode) == widget.currentEpisodeIndex;
          
          return _buildEpisodeCard(episode, isCurrentEpisode);
        },
      ),
    );
  }

  Widget _buildEpisodeCard(SeriesEpisode episode, bool isCurrentEpisode) {
    return Container(
      decoration: BoxDecoration(
        color: isCurrentEpisode 
            ? const Color(0xFFE50914).withValues(alpha: 0.15)
            : const Color(0xFF334155).withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(20),
        border: isCurrentEpisode
            ? Border.all(color: const Color(0xFFE50914), width: 2)
            : Border.all(color: const Color(0xFF475569).withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => widget.onEpisodeSelected(widget.seriesPlaylist.allEpisodes.indexOf(episode)),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Episode poster
                Expanded(
                  flex: 3,
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: const Color(0xFF475569).withValues(alpha: 0.5),
                    ),
                    child: Stack(
                      children: [
                        episode.episodeInfo?.poster != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(
                                  episode.episodeInfo!.poster!,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  height: double.infinity,
                                  errorBuilder: (context, error, stackTrace) {
                                    return _buildPosterPlaceholder(episode);
                                  },
                                ),
                              )
                            : _buildPosterPlaceholder(episode),
                        
                        // Play button overlay
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              isCurrentEpisode ? Icons.play_circle_filled : Icons.play_circle_outline,
                              color: isCurrentEpisode ? const Color(0xFFE50914) : Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                        
                        // Episode number badge
                        Positioned(
                          top: 8,
                          left: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE50914),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              episode.seasonEpisodeString,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 12),
                
                // Episode title
                Expanded(
                  flex: 1,
                  child: Text(
                    episode.episodeInfo?.title ?? episode.displayTitle,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                
                const SizedBox(height: 8),
                
                // Rating and runtime
                if (_tvmazeAvailable && (episode.episodeInfo?.rating != null || episode.episodeInfo?.runtime != null))
                  Row(
                    children: [
                      if (episode.episodeInfo?.rating != null) ...[
                        const Icon(
                          Icons.star,
                          color: Color(0xFFFFD700),
                          size: 12,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          episode.episodeInfo!.rating!.toStringAsFixed(1),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                        ),
                      ],
                      if (episode.episodeInfo?.rating != null && episode.episodeInfo?.runtime != null)
                        const SizedBox(width: 8),
                      if (episode.episodeInfo?.runtime != null) ...[
                        const Icon(
                          Icons.access_time,
                          color: Colors.white70,
                          size: 12,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${episode.episodeInfo!.runtime} min',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                
                // Loading indicator
                if (_tvmazeAvailable && _loadingEpisodes.contains('${episode.seriesInfo.season}_${episode.seriesInfo.episode}'))
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                          ),
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Loading...',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPosterPlaceholder(SeriesEpisode episode) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF475569).withValues(alpha: 0.7),
            const Color(0xFF64748B).withValues(alpha: 0.7),
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
              size: 32,
            ),
            const SizedBox(height: 8),
            Text(
              episode.seasonEpisodeString,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
} 