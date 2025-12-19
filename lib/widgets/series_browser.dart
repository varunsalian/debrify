import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/series_playlist.dart';
import '../services/episode_info_service.dart';
import '../services/storage_service.dart';
import '../services/tvmaze_service.dart';
import 'tvmaze_search_dialog.dart';

// Premium blue accent used throughout the playlist view
const Color kPremiumBlue = Color(0xFF6366F1);

class SeriesBrowser extends StatefulWidget {
  final SeriesPlaylist seriesPlaylist;
  final Function(int season, int episode) onEpisodeSelected;
  final int currentEpisodeIndex;
  final Map<String, dynamic>? playlistItem; // For Fix Metadata feature

  const SeriesBrowser({
    super.key,
    required this.seriesPlaylist,
    required this.onEpisodeSelected,
    required this.currentEpisodeIndex,
    this.playlistItem, // Optional playlist item data
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
  Map<String, Map<String, dynamic>> _episodeProgress = {}; // Map of "season_episode" -> progress data

  @override
  void initState() {
    super.initState();
    _initializeSeason();
    _checkTVMazeAvailability();
    _loadLastPlayedEpisode();
    _loadFinishedEpisodes();
    _loadEpisodeProgress();
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
    _loadEpisodeProgress();
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
          return;
        }
      }
      
      // Fallback
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
      _loadEpisodeInfoInBackground();
    } else {
    }
  }

  Future<int?> _getOverrideShowId() async {
    // Check if there's a saved mapping for this playlist item
    if (widget.playlistItem != null) {
      final mapping = await StorageService.getTVMazeSeriesMapping(widget.playlistItem!);
      if (mapping != null && mapping['tvmazeShowId'] != null) {
        print('Using saved TVMaze mapping: Show ID ${mapping['tvmazeShowId']} (${mapping['showName']})');
        return mapping['tvmazeShowId'] as int;
      }
    }
    return null;
  }

  Future<void> _loadEpisodeInfoInBackground() async {
    final selectedSeason = widget.seriesPlaylist.getSeason(_selectedSeason);
    if (selectedSeason == null) {
      return;
    }

    // Clear previous loading states for this season
    _loadingEpisodes.clear();

    for (final episode in selectedSeason.episodes) {
      if (episode.seriesInfo.season != null && episode.seriesInfo.episode != null) {
        final episodeKey = '${episode.seriesInfo.season}_${episode.seriesInfo.episode}';
        if (!_loadingEpisodes.contains(episodeKey)) {
          _loadingEpisodes.add(episodeKey);
          _loadEpisodeInfo(episode);
        }
      }
    }
  }

  Future<void> _loadEpisodeInfo(SeriesEpisode episode) async {
    if (episode.seriesInfo.season != null && episode.seriesInfo.episode != null) {
      try {
        // Check if we have a saved TVMaze show ID override
        final overrideShowId = await _getOverrideShowId();

        Map<String, dynamic>? episodeData;

        if (overrideShowId != null) {
          // Use the saved show ID directly
          final episodes = await TVMazeService.getEpisodes(overrideShowId);
          // Find the specific episode
          for (final ep in episodes) {
            if (ep['season'] == episode.seriesInfo.season && ep['number'] == episode.seriesInfo.episode) {
              episodeData = ep;
              break;
            }
          }
        } else {
          // Fall back to searching by series title
          episodeData = await EpisodeInfoService.getEpisodeInfo(
            widget.seriesPlaylist.seriesTitle!,
            episode.seriesInfo.season!,
            episode.seriesInfo.episode!,
          );
        }

        if (episodeData != null && mounted) {
          setState(() {
            episode.episodeInfo = EpisodeInfo.fromTVMaze(episodeData!);
          });
        }
      } catch (e) {
        print('Error loading episode info: $e');
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
    }
  }

  /// Load episode progress for the entire series
  Future<void> _loadEpisodeProgress() async {
    try {
      if (widget.seriesPlaylist.isSeries && widget.seriesPlaylist.seriesTitle != null) {
        final allEpisodeProgress = await StorageService.getEpisodeProgress(
          seriesTitle: widget.seriesPlaylist.seriesTitle!,
        );
        setState(() {
          _episodeProgress = allEpisodeProgress;
        });
      }
    } catch (e) {
    }
  }

  /// Show the Fix Metadata dialog to manually select a TV show
  Future<void> _showFixMetadataDialog() async {
    if (widget.playlistItem == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Fix Metadata is not available for this content'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Show the search dialog
    final selectedShow = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => TVMazeSearchDialog(
        initialQuery: widget.seriesPlaylist.seriesTitle ?? '',
      ),
    );

    if (selectedShow != null && mounted) {
      // 1. Get OLD mapping (before it's overwritten)
      final oldMapping = await StorageService.getTVMazeSeriesMapping(widget.playlistItem!);
      final oldShowId = oldMapping?['tvmazeShowId'] as int?;

      // 2. Clear old show ID cache if it exists
      if (oldShowId != null && oldShowId != selectedShow['id']) {
        debugPrint('🧹 Clearing old show ID cache: $oldShowId');
        await TVMazeService.clearShowCache(oldShowId);
        await EpisodeInfoService.clearShowCache(oldShowId);
      }

      // 3. Clear series name cache (existing logic)
      await EpisodeInfoService.clearSeriesCache(widget.seriesPlaylist.seriesTitle ?? '');
      await TVMazeService.clearSeriesCache(widget.seriesPlaylist.seriesTitle ?? '');

      // 4. Save new mapping
      await StorageService.saveTVMazeSeriesMapping(
        playlistItem: widget.playlistItem!,
        tvmazeShowId: selectedShow['id'] as int,
        showName: selectedShow['name'] as String,
      );

      // Update playlist item poster/cover image
      await _updatePlaylistPoster(selectedShow);

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Metadata fixed! Using "${selectedShow['name']}" from TVMaze'),
            backgroundColor: Colors.green,
          ),
        );
      }

      // Reload episode info with the new show ID
      setState(() {
        _tvmazeAvailable = true;
      });
      _startBackgroundEpisodeInfoLoading();
    }
  }

  /// Update the playlist item's poster/cover image with the TVMaze show poster
  Future<void> _updatePlaylistPoster(Map<String, dynamic> showInfo) async {
    if (widget.playlistItem == null) return;

    try {
      // Extract poster URL from TVMaze show data
      // TVMaze provides 'image' with 'medium' and 'original' URLs
      final image = showInfo['image'];
      String? posterUrl;

      if (image != null && image is Map<String, dynamic>) {
        // Prefer original over medium for better quality
        posterUrl = image['original'] as String? ?? image['medium'] as String?;
      }

      if (posterUrl == null || posterUrl.isEmpty) {
        print('No poster URL found in TVMaze show data');
        return;
      }

      print('🎬 Updating playlist poster with: $posterUrl');

      // CRITICAL: Save poster override to persistent storage
      // This ensures the poster persists across app restarts
      await StorageService.savePlaylistPosterOverride(
        playlistItem: widget.playlistItem!,
        posterUrl: posterUrl,
      );

      // Also update the in-memory playlist item for immediate UI update
      final provider = (widget.playlistItem!['provider'] as String?) ?? 'realdebrid';
      bool updated = false;

      if (provider.toLowerCase() == 'realdebrid') {
        final rdTorrentId = widget.playlistItem!['rdTorrentId'] as String?;
        if (rdTorrentId != null) {
          updated = await StorageService.updatePlaylistItemPoster(
            posterUrl,
            rdTorrentId: rdTorrentId,
          );
        }
      } else if (provider.toLowerCase() == 'torbox') {
        final torboxTorrentId = widget.playlistItem!['torboxTorrentId'];
        if (torboxTorrentId != null) {
          // Torbox uses integer IDs, but updatePlaylistItemPoster expects String
          // We need to update the playlist manually
          final items = await StorageService.getPlaylistItemsRaw();
          final itemIndex = items.indexWhere(
            (item) => item['torboxTorrentId'] == torboxTorrentId,
          );

          if (itemIndex >= 0) {
            items[itemIndex]['posterUrl'] = posterUrl;
            await StorageService.savePlaylistItemsRaw(items);
            updated = true;
          }
        }
      } else if (provider.toLowerCase() == 'pikpak') {
        final pikpakCollectionId = widget.playlistItem!['pikpakCollectionId'] as String?;
        if (pikpakCollectionId != null) {
          updated = await StorageService.updatePlaylistItemPoster(
            posterUrl,
            pikpakCollectionId: pikpakCollectionId,
          );
        }
      }

      if (updated) {
        print('✅ Successfully updated playlist poster in memory and persistent storage');
      } else {
        print('⚠️ Updated persistent storage but in-memory update failed - poster will still persist on restart');
      }
    } catch (e) {
      print('❌ Error updating playlist poster: $e');
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
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedSeason = widget.seriesPlaylist.getSeason(_selectedSeason);
    if (selectedSeason == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final episodes = selectedSeason.episodes;
    return Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0F172A),
              Color(0xFF0B1220),
              Color(0xFF0F172A),
            ],
          ),
        ),
      child: Column(
        children: [
          // Netflix-style Top Controls Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                  child: IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.close, 
                      color: Colors.white, 
                      size: 20
                    ),
                    style: IconButton.styleFrom(
                      padding: const EdgeInsets.all(8),
                      minimumSize: const Size(36, 36),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: kPremiumBlue.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: kPremiumBlue.withOpacity(0.5),
                        width: 1,
                      ),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: _selectedSeason,
                        dropdownColor: const Color(0xFF1A1A1A),
                        style: const TextStyle(
                          color: Colors.white, 
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        icon: const Icon(
                          Icons.keyboard_arrow_down, 
                          color: kPremiumBlue, 
                          size: 18
                        ),
                        items: widget.seriesPlaylist.seasons.map((season) {
                          return DropdownMenuItem(
                            value: season.seasonNumber,
                            child: Text(
                              'Season ${season.seasonNumber}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
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
                            // Load episode progress for the new season
                            _loadEpisodeProgress();
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
                // Fix Metadata button
                if (widget.playlistItem != null) ...[
                  Focus(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _showFixMetadataDialog,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.orange.withOpacity(0.5),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(
                                Icons.build,
                                color: Colors.orange,
                                size: 14,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Fix Metadata',
                                style: TextStyle(
                                  color: Colors.orange,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _tvmazeAvailable
                        ? const Color(0xFF059669).withOpacity(0.2)
                        : const Color(0xFFEF4444).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _tvmazeAvailable
                          ? const Color(0xFF059669)
                          : const Color(0xFFEF4444),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    _tvmazeAvailable ? 'TVMaze ✓' : 'TVMaze ✗',
                    style: TextStyle(
                      color: _tvmazeAvailable
                          ? const Color(0xFF059669)
                          : const Color(0xFFEF4444),
                      fontSize: 10,
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
                ? const Center(
                    child: Text(
                      'No episodes found',
                      style: TextStyle(
                        color: Colors.white70, 
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
    
    // Get progress data for this episode
    double progress = 0.0;
    if (episode.seriesInfo.season != null && episode.seriesInfo.episode != null) {
      final episodeKey = '${episode.seriesInfo.season}_${episode.seriesInfo.episode}';
      final progressData = _episodeProgress[episodeKey];
      if (progressData != null) {
        final positionMs = progressData['positionMs'] as int? ?? 0;
        final durationMs = progressData['durationMs'] as int? ?? 1;
        if (durationMs > 0) {
          progress = (positionMs / durationMs).clamp(0.0, 1.0);
        }
      }
    }
    
    return GestureDetector(
      onTap: () {
        if (episode.seriesInfo.season != null && episode.seriesInfo.episode != null) {
          Navigator.of(context).pop();
          widget.onEpisodeSelected(episode.seriesInfo.season!, episode.seriesInfo.episode!);
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: isCurrentEpisode 
            ? kPremiumBlue.withOpacity(0.2)
            : isLastPlayed 
              ? const Color(0xFF059669).withOpacity(0.1)
              : isFinished
                ? const Color(0xFF059669).withOpacity(0.1)
                : const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isCurrentEpisode 
              ? kPremiumBlue
              : isLastPlayed 
                ? const Color(0xFF059669)
                : isFinished
                  ? const Color(0xFF059669)
                  : Colors.white.withOpacity(0.1),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: isCurrentEpisode 
                ? kPremiumBlue.withOpacity(0.3)
                : Colors.black.withOpacity(0.3),
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
                                color: const Color(0xFF333333),
                                child: const Center(
                                  child: Icon(Icons.tv, color: Colors.white54, size: 24),
                                ),
                              ),
                              errorWidget: (context, url, error) => Container(
                                color: const Color(0xFF333333),
                                child: const Center(
                                  child: Icon(Icons.error, color: Colors.white54, size: 24),
                                ),
                              ),
                            )
                          : Container(
                              color: const Color(0xFF333333),
                              child: const Center(
                                child: Icon(Icons.tv, color: Colors.white54, size: 24),
                              ),
                            ),
                    ),
                  ),
                  // Progress bar at the bottom of the image
                  if (progress > 0.0 && !isFinished)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 2,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: progress,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  kPremiumBlue,
                                  kPremiumBlue.withValues(alpha: 0.8),
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: kPremiumBlue.withValues(alpha: 0.5),
                                  blurRadius: 4,
                                  offset: const Offset(0, 0),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  // Progress percentage indicator (only show if progress > 10%)
                  if (progress > 0.1 && !isFinished)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: kPremiumBlue.withValues(alpha: 0.8),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          '${(progress * 100).round()}%',
                          style: const TextStyle(
                            color: kPremiumBlue,
                            fontSize: 8,
                            fontWeight: FontWeight.w600,
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
                          color: kPremiumBlue,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: kPremiumBlue.withOpacity(0.5),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.play_arrow,
                              color: Colors.white,
                              size: 12,
                            ),
                            SizedBox(width: 2),
                            Text(
                              'NOW',
                              style: TextStyle(
                                color: Colors.white,
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
                          color: const Color(0xFF059669),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.replay,
                              color: Colors.white,
                              size: 12,
                            ),
                            SizedBox(width: 2),
                            Text(
                              'LAST',
                              style: TextStyle(
                                color: Colors.white,
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
                          color: const Color(0xFF059669),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 12,
                            ),
                            SizedBox(width: 2),
                            Text(
                              'DONE',
                              style: TextStyle(
                                color: Colors.white,
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
                        episode.displayTitle,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          fontSize: 11,
                          height: 1.2,
                        ),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    
                    const SizedBox(height: 6),

                    // Episode description
                    if (episode.episodeInfo?.plot != null &&
                        episode.episodeInfo!.plot!.isNotEmpty) ...[
                      Text(
                        episode.episodeInfo!.plot!,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                          height: 1.25,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                    ],
                    
                    // Metadata Row
                    Row(
                      children: [
                        // Season/Episode
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                            color: kPremiumBlue.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            episode.seasonEpisodeString.isNotEmpty
                                ? episode.seasonEpisodeString
                                : 'Episode ${index + 1}',
                            style: const TextStyle(
                              color: kPremiumBlue,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        
                        const SizedBox(width: 6),
                        
                        // Runtime
                        if (episode.episodeInfo?.runtime != null) ...[
                          const Icon(
                            Icons.access_time, 
                            color: Colors.white54, 
                            size: 10
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '${episode.episodeInfo!.runtime} min',
                            style: const TextStyle(
                              color: Colors.white54, 
                              fontSize: 10
                            ),
                          ),
                        ],
                      ],
                    ),
                    
                    const Spacer(),
                    
                    // Netflix-style Play button
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: isCurrentEpisode
                              ? [
                                  kPremiumBlue,
                                  kPremiumBlue.withOpacity(0.8),
                                ]
                              : isFinished
                                  ? [
                                      const Color(0xFF059669),
                                      const Color(0xFF059669).withOpacity(0.8),
                                    ]
                                  : [
                                      const Color(0xFF333333),
                                      const Color(0xFF333333).withOpacity(0.8),
                                    ],
                        ),
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: isCurrentEpisode
                                ? kPremiumBlue.withOpacity(0.3)
                                : Colors.black.withOpacity(0.2),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.play_arrow,
                            color: Colors.white,
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isCurrentEpisode ? 'Now Playing' : 'Play',
                            style: const TextStyle(
                              color: Colors.white,
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


} 