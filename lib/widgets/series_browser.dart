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
            const Color(0xFF1E293B),
            const Color(0xFF0F172A),
          ],
        ),
      ),
      child: Column(
        children: [
          // Header with series title and season selector
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF334155).withValues(alpha: 0.3),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
            ),
            child: Column(
              children: [
                // Series title
                if (widget.seriesPlaylist.seriesTitle != null)
                  Text(
                    widget.seriesPlaylist.seriesTitle!,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                const SizedBox(height: 16),
                
                // TVMaze status indicator
                if (!_tvmazeAvailable)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFF59E0B)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          color: Color(0xFFF59E0B),
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'Episode info unavailable',
                          style: TextStyle(
                            color: Color(0xFFF59E0B),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                
                const SizedBox(height: 16),
                
                // Season selector
                if (widget.seriesPlaylist.seasonCount > 1)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF475569).withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: DropdownButton<int>(
                      value: _selectedSeason,
                      dropdownColor: const Color(0xFF1E293B),
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                      underline: Container(),
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
          
          // Episodes list
          Expanded(
            child: _buildEpisodesList(),
          ),
        ],
      ),
    );
  }

  Widget _buildEpisodesList() {
    final selectedSeason = widget.seriesPlaylist.getSeason(_selectedSeason);
    if (selectedSeason == null) return const SizedBox.shrink();

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: selectedSeason.episodes.length,
      itemBuilder: (context, index) {
        final episode = selectedSeason.episodes[index];
        final isCurrentEpisode = widget.seriesPlaylist.allEpisodes.indexOf(episode) == widget.currentEpisodeIndex;
        
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: isCurrentEpisode 
                ? const Color(0xFFE50914).withValues(alpha: 0.2)
                : const Color(0xFF334155).withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(16),
            border: isCurrentEpisode
                ? Border.all(color: const Color(0xFFE50914), width: 2)
                : null,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => widget.onEpisodeSelected(widget.seriesPlaylist.allEpisodes.indexOf(episode)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Episode poster or placeholder
                    Container(
                      width: 80,
                      height: 120,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: const Color(0xFF475569).withValues(alpha: 0.5),
                      ),
                      child: episode.episodeInfo?.poster != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                episode.episodeInfo!.poster!,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return _buildPosterPlaceholder(episode);
                                },
                              ),
                            )
                          : _buildPosterPlaceholder(episode),
                    ),
                    
                    const SizedBox(width: 16),
                    
                    // Episode details
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Episode number and title
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE50914),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  episode.seasonEpisodeString,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  episode.episodeInfo?.title ?? episode.displayTitle,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          
                          const SizedBox(height: 8),
                          
                          // Rating and runtime (only show if TVMaze is available)
                          if (_tvmazeAvailable && (episode.episodeInfo?.rating != null || episode.episodeInfo?.runtime != null))
                            Row(
                              children: [
                                if (episode.episodeInfo?.rating != null) ...[
                                  const Icon(
                                    Icons.star,
                                    color: Color(0xFFFFD700),
                                    size: 16,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    episode.episodeInfo!.rating!.toStringAsFixed(1),
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                                if (episode.episodeInfo?.rating != null && episode.episodeInfo?.runtime != null)
                                  const SizedBox(width: 16),
                                if (episode.episodeInfo?.runtime != null) ...[
                                  const Icon(
                                    Icons.access_time,
                                    color: Colors.white70,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${episode.episodeInfo!.runtime} min',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          
                          const SizedBox(height: 8),
                          
                          // Episode description (only show if TVMaze is available)
                          if (_tvmazeAvailable && episode.episodeInfo?.plot != null)
                            Text(
                              episode.episodeInfo!.plot!,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                                height: 1.4,
                              ),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          
                          // Loading indicator (only show if TVMaze is available)
                          if (_tvmazeAvailable && _loadingEpisodes.contains('${episode.seriesInfo.season}_${episode.seriesInfo.episode}'))
                            const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Loading...',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    
                    // Play button
                    Container(
                      margin: const EdgeInsets.only(left: 8),
                      child: Icon(
                        isCurrentEpisode ? Icons.play_circle_filled : Icons.play_circle_outline,
                        color: isCurrentEpisode ? const Color(0xFFE50914) : Colors.white70,
                        size: 32,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPosterPlaceholder(SeriesEpisode episode) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
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