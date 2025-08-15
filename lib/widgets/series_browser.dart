import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    // Find the season of the current episode
    final currentEpisode = widget.seriesPlaylist.allEpisodes[widget.currentEpisodeIndex];
    if (currentEpisode.seriesInfo.season != null) {
      _selectedSeason = currentEpisode.seriesInfo.season!;
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
          
          // Episodes grid
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _buildEpisodesGrid(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEpisodesGrid() {
    final selectedSeason = widget.seriesPlaylist.getSeason(_selectedSeason);
    if (selectedSeason == null) {
      return const Center(
        child: Text(
          'No episodes found for this season',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        childAspectRatio: 0.7,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: selectedSeason.episodes.length,
      itemBuilder: (context, index) {
        final episode = selectedSeason.episodes[index];
        final isCurrentEpisode = episode.originalIndex == widget.currentEpisodeIndex;
        
        return _EpisodeCard(
          episode: episode,
          isCurrentEpisode: isCurrentEpisode,
          onTap: () {
            widget.onEpisodeSelected(episode.originalIndex);
            Navigator.of(context).pop();
          },
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
              // Episode thumbnail placeholder
              Expanded(
                flex: 3,
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFF334155),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      topRight: Radius.circular(12),
                    ),
                  ),
                  child: Stack(
                    children: [
                      Center(
                        child: Icon(
                          Icons.play_circle_outline,
                          size: 48,
                          color: Colors.white.withValues(alpha: 0.3),
                        ),
                      ),
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
                          episode.displayTitle,
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