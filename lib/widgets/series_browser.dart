import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/series_playlist.dart';
import '../services/episode_info_service.dart';
import '../services/storage_service.dart';
import '../services/tvmaze_service.dart';
import '../utils/episode_progress_merge.dart';
import '../utils/series_parser.dart';
import 'tvmaze_search_dialog.dart';

/// Palette for the series playlist sheet.
/// Netflix-inspired: near-black neutral ground, cinema-red accent, calm states.
class _BrowserColors {
  static const bg0 = Color(0xFF0A0A0C);
  static const bg1 = Color(0xFF17171B);
  static const surface = Color(0x0DFFFFFF); // ~5% white
  static const surfaceHi = Color(0x1AFFFFFF); // ~10% white
  static const line = Color(0x1FFFFFFF); // ~12% white
  static const ink = Color(0xFFF5F5F7);
  static const inkDim = Color(0xFFB2B2BA);
  static const inkFaint = Color(0xFF77777F);
  static const accent = Color(0xFFE50914); // Netflix red
  static const accentSoft = Color(0x24E50914); // ~14%
  static const accentLine = Color(0x66E50914); // ~40%
  static const done = Color(0xFF56D6A0);
  static const menuBg = Color(0xFF1C1C21);

  /// Distinct placeholder "stills" so episodes read apart before posters load.
  static const thumbGradients = <List<Color>>[
    [Color(0xFF3A2226), Color(0xFF241A2E)],
    [Color(0xFF2A2320), Color(0xFF1E2830)],
    [Color(0xFF3A1E24), Color(0xFF2E1A28)],
    [Color(0xFF262024), Color(0xFF201E2C)],
    [Color(0xFF302026), Color(0xFF1C2230)],
    [Color(0xFF2E2028), Color(0xFF281E22)],
  ];
}

class SeriesBrowser extends StatefulWidget {
  final SeriesPlaylist seriesPlaylist;
  final Function(int season, int episode) onEpisodeSelected;
  final int currentEpisodeIndex;
  final Map<String, dynamic>? playlistItem; // For Fix Metadata feature
  final String? imdbId; // Show IMDb id, for per-episode Trakt progress lookup

  /// Full-guide mode: render EVERY episode of the show (from TVMaze), not
  /// just the ones present in the pack. Absent episodes show dimmed with a
  /// fetch affordance; tapping one still calls [onEpisodeSelected], and the
  /// host resolves it to a fetch (the S/E won't map to a playlist index).
  /// Only enable when the host can actually fetch absent episodes.
  final bool showAllEpisodes;

  const SeriesBrowser({
    super.key,
    required this.seriesPlaylist,
    required this.onEpisodeSelected,
    required this.currentEpisodeIndex,
    this.playlistItem, // Optional playlist item data
    this.imdbId,
    this.showAllEpisodes = false,
  });

  @override
  State<SeriesBrowser> createState() => _SeriesBrowserState();
}

class _SeriesBrowserState extends State<SeriesBrowser> {
  final Set<String> _loadingEpisodes = {};
  bool _tvmazeAvailable = false;
  bool _tvmazeChecked = false; // True once the availability probe has resolved
  int _selectedSeason = 1;
  bool _denseView = false;
  // Episodes expanded to show their description in dense view, keyed by
  // season/episode/originalIndex — placeholders share originalIndex -1, so a
  // bare index would expand every placeholder at once.
  final Set<String> _expandedDense = {};

  // Full-guide mode: the show's complete TVMaze episode list and the merged
  // (pack ∪ TVMaze) per-season views derived from it. Placeholder rows for
  // absent episodes are synthesized once and cached so their identity is
  // stable across rebuilds.
  List<Map<String, dynamic>> _fullEpisodes = [];
  final Map<int, List<SeriesEpisode>> _mergedSeasonCache = {};
  final ScrollController _scrollController = ScrollController();
  Map<String, dynamic>? _lastPlayedEpisode;
  Map<String, Set<int>> _finishedEpisodes =
      {}; // Map of season -> Set of episode numbers
  Map<String, Map<String, dynamic>> _episodeProgress =
      {}; // Map of "season_episode" -> progress data
  // Trakt cross-device progress ("season_episode" -> percent 0-100). Shown as a
  // bar only when there's no local resume for that episode (local wins the bar
  // because it's ms-precise; Trakt fills in episodes watched on other devices).
  Map<String, double> _traktEpisodeProgress = {};
  // Simkl's launch-time snapshot, kept separate from local state so a remote
  // mark-unwatched can clear on the next launch without deleting local history.
  Map<String, double> _simklEpisodeProgress = {};

  // Top padding on the episode grid; part of the scroll-centering math.
  static const double _gridTopPadding = 4.0;

  // Each dense-view row appends a 1px Divider (see _buildDenseRow), so its
  // laid-out height is _lastRowExtent + this. The comfortable GridView has no
  // divider, so it's only added to the stride when _denseView is on.
  static const double _denseRowDivider = 1.0;

  // Layout values captured during build so _recenterCurrentEpisode can
  // compute offsets that match the grid actually on screen.
  int _lastColumns = 1;
  double _lastRowExtent = 132;
  double _lastRowSpacing = 10;

  @override
  void initState() {
    super.initState();
    // Full list may already have been fetched by the player's own TVMaze pass.
    _fullEpisodes = widget.seriesPlaylist.fullTvmazeEpisodes;
    _initializeSeason();
    _loadViewMode();
    _checkTVMazeAvailability();
    _loadLastPlayedEpisode();
    _loadFinishedEpisodes();
    _loadEpisodeProgress();
    // Position (without animation) on the current episode after first layout.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _recenterCurrentEpisode(animate: false);
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
          orElse: () => widget
              .seriesPlaylist
              .allEpisodes
              .first, // Fallback to first episode
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

  Future<void> _loadViewMode() async {
    final dense = await StorageService.getSeriesBrowserDenseView();
    if (mounted && dense != _denseView) {
      setState(() {
        _denseView = dense;
      });
      // The initState scroll ran against comfortable-row extents; re-position
      // (still without animation) now that the dense rows are in effect. Using
      // animate:false here avoids a competing animation with the initState pass.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _recenterCurrentEpisode(animate: false);
      });
    }
  }

  Future<void> _checkTVMazeAvailability() async {
    await EpisodeInfoService.refreshAvailability();
    if (!mounted) return;
    setState(() {
      _tvmazeAvailable = EpisodeInfoService.isTVMazeAvailable;
      _tvmazeChecked = true;
    });

    // Start loading episode info after TVMaze availability is confirmed
    if (_tvmazeAvailable) {
      _startBackgroundEpisodeInfoLoading();
    }
  }

  void _startBackgroundEpisodeInfoLoading() {
    if (widget.seriesPlaylist.isSeries &&
        widget.seriesPlaylist.seriesTitle != null &&
        _tvmazeAvailable) {
      _loadEpisodeInfoInBackground();
    }
  }

  Future<int?> _getOverrideShowId() async {
    // Check if there's a saved mapping for this playlist item
    if (widget.playlistItem != null) {
      final mapping = await StorageService.getTVMazeSeriesMapping(
        widget.playlistItem!,
      );
      if (mapping != null && mapping['tvmazeShowId'] != null) {
        debugPrint(
          'Using saved TVMaze mapping: Show ID ${mapping['tvmazeShowId']} (${mapping['showName']})',
        );
        return mapping['tvmazeShowId'] as int;
      }
    }
    return null;
  }

  Future<void> _loadEpisodeInfoInBackground() async {
    // Clear previous loading states for this season
    _loadingEpisodes.clear();

    // Fetch all episodes ONCE upfront (avoid per-episode API calls)
    List<Map<String, dynamic>> allEpisodes = _fullEpisodes;

    // Try to get show ID from: 1) SeriesPlaylist, 2) saved mapping, 3) IMDB lookup
    int? showId =
        widget.seriesPlaylist.tvmazeShowId ?? await _getOverrideShowId();

    // If no show ID yet but we have IMDB ID, do IMDB lookup
    if (showId == null && widget.seriesPlaylist.imdbId != null) {
      try {
        final showInfo = await TVMazeService.lookupByImdbId(
          widget.seriesPlaylist.imdbId!,
        );
        if (showInfo != null && showInfo['id'] != null) {
          showId = showInfo['id'] as int;
          // Store for future use
          widget.seriesPlaylist.tvmazeShowId = showId;
        }
      } catch (e) {
        debugPrint('Error looking up show by IMDB ID: $e');
      }
    }

    if (allEpisodes.isEmpty && showId != null) {
      try {
        allEpisodes = await TVMazeService.getEpisodes(showId);
      } catch (e) {
        debugPrint('Error fetching episodes for show ID $showId: $e');
      }
    }

    // Retain the full list: the guide's full-mode view is derived from it,
    // and the SeriesPlaylist keeps it for the player (next/prev beyond pack).
    if (allEpisodes.isNotEmpty && !identical(allEpisodes, _fullEpisodes)) {
      widget.seriesPlaylist.fullTvmazeEpisodes = allEpisodes;
      if (mounted) {
        setState(() {
          _fullEpisodes = allEpisodes;
          _mergedSeasonCache.clear();
        });
      } else {
        _fullEpisodes = allEpisodes;
        _mergedSeasonCache.clear();
      }
    }

    final selectedSeason = widget.seriesPlaylist.getSeason(_selectedSeason);
    if (selectedSeason == null) {
      return;
    }

    // Process each episode using pre-fetched list or fallback to title search
    for (final episode in selectedSeason.episodes) {
      if (episode.seriesInfo.season != null &&
          episode.seriesInfo.episode != null) {
        final episodeKey =
            '${episode.seriesInfo.season}_${episode.seriesInfo.episode}';
        if (!_loadingEpisodes.contains(episodeKey)) {
          _loadingEpisodes.add(episodeKey);
          _loadEpisodeInfo(episode, allEpisodes);
        }
      }
    }
  }

  Future<void> _loadEpisodeInfo(
    SeriesEpisode episode,
    List<Map<String, dynamic>> prefetchedEpisodes,
  ) async {
    if (episode.seriesInfo.season != null &&
        episode.seriesInfo.episode != null) {
      try {
        Map<String, dynamic>? episodeData;

        if (prefetchedEpisodes.isNotEmpty) {
          // Use pre-fetched episodes list (no API call)
          for (final ep in prefetchedEpisodes) {
            if (ep['season'] == episode.seriesInfo.season &&
                ep['number'] == episode.seriesInfo.episode) {
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
        debugPrint('Error loading episode info: $e');
      } finally {
        final episodeKey =
            '${episode.seriesInfo.season}_${episode.seriesInfo.episode}';
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
      if (lastEpisode != null && mounted) {
        setState(() {
          _lastPlayedEpisode = lastEpisode;
        });
      }
    } catch (e) {
      // Last played is optional
    }
  }

  /// Load finished episodes for the entire series
  Future<void> _loadFinishedEpisodes() async {
    try {
      if (widget.seriesPlaylist.isSeries &&
          widget.seriesPlaylist.seriesTitle != null) {
        final allFinishedEpisodes = await StorageService.getFinishedEpisodes(
          seriesTitle: widget.seriesPlaylist.seriesTitle!,
        );
        if (mounted) {
          setState(() {
            _finishedEpisodes = allFinishedEpisodes;
          });
        }
      }
    } catch (e) {
      // Finished state is optional
    }
  }

  /// Load episode progress for the entire series
  Future<void> _loadEpisodeProgress() async {
    try {
      if (widget.seriesPlaylist.isSeries &&
          widget.seriesPlaylist.seriesTitle != null) {
        final imdbId = widget.imdbId;
        final results = await Future.wait([
          StorageService.getEpisodeProgress(
            seriesTitle: widget.seriesPlaylist.seriesTitle!,
          ),
          (imdbId != null && imdbId.isNotEmpty)
              ? StorageService.getEpisodeTraktProgress(imdbId: imdbId)
              : Future.value(const <String, double>{}),
          (imdbId != null && imdbId.isNotEmpty)
              ? StorageService.getEpisodeSimklProgress(imdbId: imdbId)
              : Future.value(const <String, double>{}),
        ]);
        if (mounted) {
          setState(() {
            _episodeProgress = results[0] as Map<String, Map<String, dynamic>>;
            _traktEpisodeProgress = results[1] as Map<String, double>;
            _simklEpisodeProgress = results[2] as Map<String, double>;
          });
        }
      }
    } catch (e) {
      // Progress is optional
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
      final oldMapping = await StorageService.getTVMazeSeriesMapping(
        widget.playlistItem!,
      );
      final oldShowId = oldMapping?['tvmazeShowId'] as int?;

      // 2. Clear old show ID cache if it exists
      if (oldShowId != null && oldShowId != selectedShow['id']) {
        debugPrint('🧹 Clearing old show ID cache: $oldShowId');
        await TVMazeService.clearShowCache(oldShowId);
        await EpisodeInfoService.clearShowCache(oldShowId);
      }

      // 3. Clear series name cache (existing logic)
      await EpisodeInfoService.clearSeriesCache(
        widget.seriesPlaylist.seriesTitle ?? '',
      );
      await TVMazeService.clearSeriesCache(
        widget.seriesPlaylist.seriesTitle ?? '',
      );

      // 4. Save new mapping
      await StorageService.saveTVMazeSeriesMapping(
        playlistItem: widget.playlistItem!,
        tvmazeShowId: selectedShow['id'] as int,
        showName: selectedShow['name'] as String,
      );

      // Save IMDB ID from the selected show's externals
      final externals = selectedShow['externals'];
      if (externals is Map<String, dynamic>) {
        final imdbId = externals['imdb'];
        if (imdbId is String && imdbId.startsWith('tt')) {
          widget.seriesPlaylist.imdbId = imdbId;
          final rdId = widget.playlistItem?['rdTorrentId'] as String?;
          final torboxId = widget.playlistItem?['torboxTorrentId']?.toString();
          final pikpakId = widget.playlistItem?['pikpakFileId'] as String?;
          final isPremiumize =
              (widget.playlistItem?['provider'] as String?)?.toLowerCase() ==
              'premiumize';
          final premiumizeHash = isPremiumize
              ? (widget.playlistItem?['torrent_hash'] as String?)
              : null;
          final premiumizeItemId = isPremiumize
              ? (widget.playlistItem?['premiumizeItemId']?.toString())
              : null;
          final isAllDebrid =
              (widget.playlistItem?['provider'] as String?)?.toLowerCase() ==
              'alldebrid';
          final allDebridHash = isAllDebrid
              ? (widget.playlistItem?['torrent_hash'] as String?)
              : null;
          await StorageService.updatePlaylistItemImdbId(
            imdbId,
            rdTorrentId: rdId,
            torboxTorrentId: torboxId,
            pikpakCollectionId: pikpakId,
            premiumizeHash: premiumizeHash,
            premiumizeItemId: premiumizeItemId,
            allDebridHash: allDebridHash,
            force: true,
          );
        }
      }

      // Update playlist item poster/cover image
      await _updatePlaylistPoster(selectedShow);

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Metadata fixed! Using "${selectedShow['name']}" from TVMaze',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }

      // Clear stale tvmazeShowId so _getOverrideShowId() reads the new mapping
      widget.seriesPlaylist.tvmazeShowId = null;

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
        debugPrint('No poster URL found in TVMaze show data');
        return;
      }

      debugPrint('🎬 Updating playlist poster with: $posterUrl');

      // CRITICAL: Save poster override to persistent storage
      // This ensures the poster persists across app restarts
      await StorageService.savePlaylistPosterOverride(
        playlistItem: widget.playlistItem!,
        posterUrl: posterUrl,
      );

      // Also update the in-memory playlist item for immediate UI update
      final provider =
          (widget.playlistItem!['provider'] as String?) ?? 'realdebrid';
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
        final pikpakCollectionId =
            widget.playlistItem!['pikpakFileId'] as String?;
        if (pikpakCollectionId != null) {
          updated = await StorageService.updatePlaylistItemPoster(
            posterUrl,
            pikpakCollectionId: pikpakCollectionId,
          );
        }
      } else if (provider.toLowerCase() == 'premiumize') {
        final premiumizeHash = widget.playlistItem!['torrent_hash'] as String?;
        final premiumizeItemId = widget.playlistItem!['premiumizeItemId']
            ?.toString();
        if (premiumizeHash != null && premiumizeHash.isNotEmpty) {
          updated = await StorageService.updatePlaylistItemPoster(
            posterUrl,
            premiumizeHash: premiumizeHash,
          );
        } else if (premiumizeItemId != null && premiumizeItemId.isNotEmpty) {
          updated = await StorageService.updatePlaylistItemPoster(
            posterUrl,
            premiumizeItemId: premiumizeItemId,
          );
        }
      } else if (provider.toLowerCase() == 'alldebrid') {
        final allDebridHash = widget.playlistItem!['torrent_hash'] as String?;
        if (allDebridHash != null && allDebridHash.isNotEmpty) {
          updated = await StorageService.updatePlaylistItemPoster(
            posterUrl,
            allDebridHash: allDebridHash,
          );
        }
      }

      if (updated) {
        debugPrint(
          '✅ Successfully updated playlist poster in memory and persistent storage',
        );
      } else {
        debugPrint(
          '⚠️ Updated persistent storage but in-memory update failed - poster will still persist on restart',
        );
      }
    } catch (e) {
      debugPrint('❌ Error updating playlist poster: $e');
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Positions the list so the current episode is centered. When the current
  /// episode isn't in the selected season (or nothing is playing), resets to
  /// the top — otherwise a stale offset from a taller/previous layout could
  /// strand the list at the bottom after a density or season change.
  /// Pass [animate] false for initial positioning to avoid a scroll animation.
  void _recenterCurrentEpisode({bool animate = true}) {
    if (!_scrollController.hasClients) return;

    final episodeIndexInSeason = _episodesForSeason(_selectedSeason).indexWhere(
      (episode) => episode.originalIndex == widget.currentEpisodeIndex,
    );

    if (widget.currentEpisodeIndex < 0 || episodeIndexInSeason == -1) {
      _scrollController.jumpTo(0);
      return;
    }

    // Center the row containing the current episode, using the extents
    // captured during the last build (they match the live layout).
    final rowIndex = episodeIndexInSeason ~/ _lastColumns;
    final rowStride =
        _lastRowExtent + _lastRowSpacing + (_denseView ? _denseRowDivider : 0);
    final viewport = _scrollController.position.viewportDimension;
    final target =
        _gridTopPadding +
        rowIndex * rowStride -
        (viewport - _lastRowExtent) / 2;
    final offset = target.clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );

    if (animate) {
      _scrollController.animateTo(
        offset,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    } else {
      _scrollController.jumpTo(offset);
    }
  }

  void _onSeasonChanged(int seasonNumber) {
    if (seasonNumber == _selectedSeason) return;
    setState(() {
      _selectedSeason = seasonNumber;
    });
    // Load episode info for the new season. Finished/progress maps are
    // series-wide and already loaded in initState — no per-season reload.
    _startBackgroundEpisodeInfoLoading();
    // Center the current episode in the new season, or reset to the top if it
    // isn't in this season (handled inside _recenterCurrentEpisode).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _recenterCurrentEpisode();
    });
  }

  void _setDenseView(bool dense) {
    if (dense == _denseView) return;
    setState(() {
      _denseView = dense;
      // Open the compact list clean; also keeps row heights uniform so the
      // re-center below lands correctly.
      _expandedDense.clear();
    });
    StorageService.setSeriesBrowserDenseView(dense);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _recenterCurrentEpisode();
    });
  }

  String _seasonLabel(int seasonNumber) {
    return seasonNumber == 0 ? 'Specials' : 'Season $seasonNumber';
  }

  /// Seasons for the picker: the pack's seasons, plus (in full-guide mode)
  /// every season TVMaze knows about. Specials (season 0) sort last.
  List<({int number, int count})> _guideSeasons() {
    final counts = <int, int>{};
    for (final s in widget.seriesPlaylist.seasons) {
      counts[s.seasonNumber] = s.episodes.length;
    }
    if (widget.showAllEpisodes) {
      final tvCounts = <int, int>{};
      for (final ep in _fullEpisodes) {
        final s = ep['season'] as int?;
        if (s == null) continue;
        tvCounts[s] = (tvCounts[s] ?? 0) + 1;
      }
      tvCounts.forEach((s, c) {
        final existing = counts[s];
        counts[s] = existing == null ? c : math.max(existing, c);
      });
    }
    final numbers = counts.keys.toList()..sort();
    if (numbers.remove(0)) numbers.add(0);
    return [for (final n in numbers) (number: n, count: counts[n]!)];
  }

  /// Episodes for [seasonNumber]: the pack's files as-is, or (in full-guide
  /// mode) the union with TVMaze — absent episodes become placeholder rows
  /// with originalIndex -1 that render dimmed and resolve to a fetch on tap.
  /// Placeholders are cached so their identity is stable across rebuilds.
  List<SeriesEpisode> _episodesForSeason(int seasonNumber) {
    final pack =
        widget.seriesPlaylist.getSeason(seasonNumber)?.episodes ??
        const <SeriesEpisode>[];
    if (!widget.showAllEpisodes || _fullEpisodes.isEmpty) return pack;
    final cached = _mergedSeasonCache[seasonNumber];
    if (cached != null) return cached;

    final byNumber = <int, SeriesEpisode>{};
    for (final ep in pack) {
      final n = ep.seriesInfo.episode;
      if (n != null) byNumber.putIfAbsent(n, () => ep);
    }
    final tvEpisodes =
        _fullEpisodes.where((m) => m['season'] == seasonNumber).toList()..sort(
          (a, b) => ((a['number'] as int?) ?? 0).compareTo(
            (b['number'] as int?) ?? 0,
          ),
        );
    final merged = <SeriesEpisode>[];
    final used = <SeriesEpisode>{};
    for (final tv in tvEpisodes) {
      final n = tv['number'] as int?;
      if (n == null) continue;
      final packEp = byNumber[n];
      if (packEp != null) {
        merged.add(packEp);
        used.add(packEp);
      } else {
        merged.add(
          SeriesEpisode(
            url: '',
            title: (tv['name'] as String?) ?? 'Episode $n',
            filename: '',
            seriesInfo: SeriesInfo(
              title: widget.seriesPlaylist.seriesTitle,
              season: seasonNumber,
              episode: n,
              isSeries: true,
            ),
            originalIndex: -1,
          )..episodeInfo = EpisodeInfo.fromTVMaze(tv),
        );
      }
    }
    // Pack files TVMaze doesn't know about keep showing, after the known ones.
    for (final ep in pack) {
      if (!used.contains(ep)) merged.add(ep);
    }
    _mergedSeasonCache[seasonNumber] = merged;
    return merged;
  }

  double _progressFor(SeriesEpisode episode) {
    if (episode.seriesInfo.season == null ||
        episode.seriesInfo.episode == null) {
      return 0.0;
    }
    final episodeKey =
        '${episode.seriesInfo.season}_${episode.seriesInfo.episode}';
    // FURTHEST-WATCHED WINS across local, Trakt, and Simkl, matching the merged
    // details page. Tracker snapshots can fill episodes watched elsewhere but
    // never regress a deeper local position.
    double local = 0.0;
    final progressData = _episodeProgress[episodeKey];
    if (progressData != null) {
      final positionMs = progressData['positionMs'] as int? ?? 0;
      final durationMs = progressData['durationMs'] as int? ?? 1;
      if (durationMs > 0) local = (positionMs / durationMs).clamp(0.0, 1.0);
    }
    final traktPercent = _traktEpisodeProgress[episodeKey];
    final simklPercent = _simklEpisodeProgress[episodeKey];
    final tracker =
        (furthestEpisodeTrackerPercent([traktPercent, simklPercent]) ?? 0.0) /
        100;
    // Active rewatch: a tracker says finished but there's a real in-progress
    // local position — show the live local bar rather than a completed card.
    if (tracker >= 0.95 && local > 0 && local < 0.95) return local;
    return local >= tracker ? local : tracker;
  }

  bool _isFinished(SeriesEpisode episode) {
    final season = episode.seriesInfo.season;
    final number = episode.seriesInfo.episode;
    if (season == null || number == null) return false;
    if (_finishedEpisodes[season.toString()]?.contains(number) == true) {
      return true;
    }
    final key = '${season}_$number';
    final trakt = _traktEpisodeProgress[key] ?? 0.0;
    final simkl = _simklEpisodeProgress[key] ?? 0.0;
    if (trakt < 95.0 && simkl < 95.0) return false;

    // A real local partial means the user has started a rewatch; match the
    // progress-bar rule and show that active state instead of a remote tick.
    final progressData = _episodeProgress[key];
    if (progressData != null) {
      final positionMs = progressData['positionMs'] as int? ?? 0;
      final durationMs = progressData['durationMs'] as int? ?? 0;
      if (durationMs > 0) {
        final local = positionMs / durationMs;
        if (local > 0 && local < 0.95) return false;
      }
    }
    return true;
  }

  bool _isLastPlayed(SeriesEpisode episode) {
    return _lastPlayedEpisode != null &&
        episode.seriesInfo.season == _lastPlayedEpisode!['season'] &&
        episode.seriesInfo.episode == _lastPlayedEpisode!['episode'];
  }

  void _onEpisodeTap(SeriesEpisode episode) {
    if (episode.seriesInfo.season != null &&
        episode.seriesInfo.episode != null) {
      Navigator.of(context).pop();
      widget.onEpisodeSelected(
        episode.seriesInfo.season!,
        episode.seriesInfo.episode!,
      );
    }
  }

  String _denseKey(SeriesEpisode episode) =>
      '${episode.seriesInfo.season}_${episode.seriesInfo.episode}_${episode.originalIndex}';

  void _toggleDenseExpanded(SeriesEpisode episode) {
    final key = _denseKey(episode);
    setState(() {
      if (!_expandedDense.remove(key)) {
        _expandedDense.add(key);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final episodes = _episodesForSeason(_selectedSeason);
    if (episodes.isEmpty &&
        widget.seriesPlaylist.getSeason(_selectedSeason) == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_BrowserColors.bg1, _BrowserColors.bg0],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // A bottom sheet stretched across a desktop window looks broken;
          // cap content width and center it.
          final contentWidth = math.min(constraints.maxWidth, 1120.0);
          final hPad = (contentWidth * 0.04).clamp(14.0, 28.0);

          return Center(
            child: SizedBox(
              width: contentWidth,
              child: Column(
                children: [
                  _buildHeader(hPad),
                  _buildMetadataWarning(hPad),
                  Expanded(
                    child: episodes.isEmpty
                        ? const Center(
                            child: Text(
                              'No episodes found',
                              style: TextStyle(
                                color: _BrowserColors.inkDim,
                                fontSize: 16,
                              ),
                            ),
                          )
                        : _buildEpisodeGrid(
                            context,
                            episodes,
                            contentWidth,
                            hPad,
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(double hPad) {
    final seriesTitle = widget.seriesPlaylist.seriesTitle;
    final seasons = _guideSeasons();

    return Padding(
      padding: EdgeInsets.fromLTRB(hPad, 8, hPad, 10),
      child: Column(
        children: [
          // Grabber handle
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (seriesTitle != null && seriesTitle.isNotEmpty)
                      Text(
                        seriesTitle.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _BrowserColors.inkFaint,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.4,
                        ),
                      ),
                    _buildSeasonPicker(seasons),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _buildViewToggle(),
              if (widget.playlistItem != null) ...[
                const SizedBox(width: 8),
                _buildOverflowMenu(),
              ],
              const SizedBox(width: 8),
              _buildIconButton(
                icon: Icons.close,
                tooltip: 'Close',
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Quiet, failure-only notice. Shown only after the availability probe has
  /// resolved unavailable — never as an always-on status badge, and never
  /// during the brief loading window before the probe returns.
  Widget _buildMetadataWarning(double hPad) {
    if (!_tvmazeChecked ||
        _tvmazeAvailable ||
        !widget.seriesPlaylist.isSeries) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 8),
      child: Row(
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            size: 14,
            color: _BrowserColors.inkFaint,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "Couldn't load episode details — check your connection.",
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _BrowserColors.inkFaint,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeasonPicker(List<({int number, int count})> seasons) {
    final label = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            _seasonLabel(_selectedSeason),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _BrowserColors.ink,
              fontSize: 19,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
        ),
        if (seasons.length > 1) ...[
          const SizedBox(width: 3),
          const Icon(Icons.expand_more, color: _BrowserColors.accent, size: 20),
        ],
      ],
    );

    if (seasons.length <= 1) {
      return label;
    }

    return PopupMenuButton<int>(
      tooltip: 'Choose season',
      color: _BrowserColors.menuBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _BrowserColors.line),
      ),
      position: PopupMenuPosition.under,
      onSelected: _onSeasonChanged,
      itemBuilder: (context) => seasons.map((season) {
        final isSelected = season.number == _selectedSeason;
        return PopupMenuItem<int>(
          value: season.number,
          child: Row(
            children: [
              Text(
                _seasonLabel(season.number),
                style: TextStyle(
                  color: isSelected
                      ? _BrowserColors.accent
                      : _BrowserColors.ink,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              Text(
                '${season.count} ep',
                style: const TextStyle(
                  color: _BrowserColors.inkFaint,
                  fontSize: 12,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        );
      }).toList(),
      child: label,
    );
  }

  Widget _buildViewToggle() {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: _BrowserColors.surface,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: _BrowserColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSegmentButton(
            icon: Icons.view_agenda_outlined,
            tooltip: 'Comfortable list',
            active: !_denseView,
            onTap: () => _setDenseView(false),
          ),
          const SizedBox(width: 2),
          _buildSegmentButton(
            icon: Icons.view_headline,
            tooltip: 'Compact list',
            active: _denseView,
            onTap: () => _setDenseView(true),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentButton({
    required IconData icon,
    required String tooltip,
    required bool active,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active ? _BrowserColors.surfaceHi : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 34,
            height: 30,
            child: Icon(
              icon,
              size: 17,
              color: active ? _BrowserColors.ink : _BrowserColors.inkDim,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOverflowMenu() {
    return PopupMenuButton<String>(
      tooltip: 'More',
      color: _BrowserColors.menuBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _BrowserColors.line),
      ),
      position: PopupMenuPosition.under,
      onSelected: (value) {
        if (value == 'fix_metadata') {
          _showFixMetadataDialog();
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem<String>(
          value: 'fix_metadata',
          child: Row(
            children: [
              Icon(
                Icons.build_outlined,
                color: _BrowserColors.inkDim,
                size: 17,
              ),
              SizedBox(width: 10),
              Text(
                'Fix metadata',
                style: TextStyle(
                  color: _BrowserColors.ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
      child: _buildIconButtonShell(
        child: const Icon(
          Icons.more_horiz,
          color: _BrowserColors.inkDim,
          size: 18,
        ),
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: _BrowserColors.surface,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: _buildIconButtonShell(
            withBackground: false,
            child: Icon(icon, color: _BrowserColors.inkDim, size: 18),
          ),
        ),
      ),
    );
  }

  Widget _buildIconButtonShell({
    required Widget child,
    bool withBackground = true,
  }) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: withBackground ? _BrowserColors.surface : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _BrowserColors.line),
      ),
      child: Center(child: child),
    );
  }

  Widget _buildEpisodeGrid(
    BuildContext context,
    List<SeriesEpisode> episodes,
    double contentWidth,
    double hPad,
  ) {
    // Rows use a fixed mainAxisExtent, so cap how far text is allowed to scale
    // and budget the row height for exactly that. The GridView subtree is
    // wrapped in a matching clamp below so text never outgrows its cell.
    const maxTextScale = 1.6;
    final textScale = (MediaQuery.textScalerOf(context).scale(14.0) / 14.0)
        .clamp(1.0, maxTextScale);

    final int columns;
    final double rowExtent;
    final double rowSpacing;
    double thumbWidth = 0;
    double thumbHeight = 0;
    int plotLines = 2;

    if (_denseView) {
      columns = 1;
      rowSpacing = 0;
      rowExtent = 52.0 * textScale;
    } else {
      // Two columns of rows once the sheet is wide enough (iPad / desktop).
      columns = contentWidth >= 900 ? 2 : 1;
      rowSpacing = 10;
      const columnGap = 16.0;
      final columnWidth =
          (contentWidth - hPad * 2 - (columns - 1) * columnGap) / columns;
      thumbWidth = (columnWidth * 0.34).clamp(112.0, 168.0);
      thumbHeight = thumbWidth * 9 / 16;
      plotLines = columns == 2 ? 3 : 2;
      final textBlockHeight = (plotLines == 3 ? 150.0 : 130.0) * textScale;
      rowExtent = math.max(thumbHeight + 20, textBlockHeight);
    }

    // Capture layout for _recenterCurrentEpisode
    _lastColumns = columns;
    _lastRowExtent = rowExtent;
    _lastRowSpacing = rowSpacing;

    // Dense rows can expand inline to show a description, so they need variable
    // height — a ListView, not the fixed-extent GridView the comfortable view uses.
    final Widget content = _denseView
        ? ListView.builder(
            controller: _scrollController,
            padding: EdgeInsets.fromLTRB(hPad, _gridTopPadding, hPad, 28),
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: episodes.length,
            itemBuilder: (context, index) {
              final episode = episodes[index];
              final isCurrent =
                  episode.originalIndex == widget.currentEpisodeIndex;
              return _buildDenseRow(
                episode: episode,
                index: index,
                isCurrent: isCurrent,
                isFinished: _isFinished(episode),
                progress: _progressFor(episode),
                collapsedHeight: rowExtent,
                showDivider: index < episodes.length - 1,
              );
            },
          )
        : GridView.builder(
            controller: _scrollController,
            padding: EdgeInsets.fromLTRB(hPad, _gridTopPadding, hPad, 28),
            physics: const AlwaysScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisExtent: rowExtent,
              crossAxisSpacing: 16,
              mainAxisSpacing: rowSpacing,
            ),
            itemCount: episodes.length,
            itemBuilder: (context, index) {
              final episode = episodes[index];
              final isCurrent =
                  episode.originalIndex == widget.currentEpisodeIndex;
              return _buildEpisodeRow(
                episode: episode,
                index: index,
                isCurrent: isCurrent,
                isFinished: _isFinished(episode),
                isLastPlayed: _isLastPlayed(episode),
                progress: _progressFor(episode),
                thumbWidth: thumbWidth,
                thumbHeight: thumbHeight,
                plotLines: plotLines,
              );
            },
          );

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: maxTextScale,
      child: content,
    );
  }

  // ===== Comfortable row =====

  Widget _buildEpisodeRow({
    required SeriesEpisode episode,
    required int index,
    required bool isCurrent,
    required bool isFinished,
    required bool isLastPlayed,
    required double progress,
    required double thumbWidth,
    required double thumbHeight,
    required int plotLines,
  }) {
    final plot = episode.episodeInfo?.plot;
    final available = episode.originalIndex >= 0;

    return Material(
      color: isCurrent ? _BrowserColors.accentSoft : _BrowserColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () => _onEpisodeTap(episode),
        borderRadius: BorderRadius.circular(14),
        splashColor: _BrowserColors.accent.withValues(alpha: 0.08),
        highlightColor: Colors.white.withValues(alpha: 0.04),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isCurrent ? _BrowserColors.accentLine : Colors.transparent,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Opacity(
                opacity: available ? 1.0 : 0.55,
                child: _buildThumbnail(
                  episode: episode,
                  index: index,
                  width: thumbWidth,
                  height: thumbHeight,
                  progress: progress,
                  isFinished: isFinished,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          episode.seriesInfo.episode != null
                              ? 'E${episode.seriesInfo.episode}'
                              : '${index + 1}',
                          style: const TextStyle(
                            color: _BrowserColors.inkFaint,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            episode.displayTitle,
                            maxLines: plot == null || plot.isEmpty ? 2 : 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: available
                                  ? _BrowserColors.ink
                                  : _BrowserColors.inkDim,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.1,
                              height: 1.25,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (plot != null && plot.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        plot,
                        maxLines: plotLines,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _BrowserColors.inkDim,
                          fontSize: 12.5,
                          height: 1.35,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    _buildStateTags(
                      isCurrent: isCurrent,
                      isFinished: isFinished,
                      isLastPlayed: isLastPlayed,
                      progress: progress,
                      available: available,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnail({
    required SeriesEpisode episode,
    required int index,
    required double width,
    required double height,
    required double progress,
    required bool isFinished,
  }) {
    final gradientColors = _BrowserColors
        .thumbGradients[index % _BrowserColors.thumbGradients.length];
    final placeholder = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
        ),
      ),
      child: Center(
        child: Text(
          '${episode.seriesInfo.episode ?? index + 1}',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.24),
            fontSize: math.min(26, height * 0.4),
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );

    final runtime = episode.episodeInfo?.runtime;

    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (episode.episodeInfo?.poster != null)
              CachedNetworkImage(
                imageUrl: episode.episodeInfo!.poster!,
                memCacheWidth: 340,
                fit: BoxFit.cover,
                placeholder: (context, url) => placeholder,
                errorWidget: (context, url, error) => placeholder,
              )
            else
              placeholder,
            // Duration chip
            if (runtime != null)
              Positioned(
                right: 5,
                bottom: progress > 0 && !isFinished ? 8 : 5,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    '${runtime}m',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            // Thin progress bar along the bottom
            if (progress > 0 && !isFinished)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  height: 3,
                  color: Colors.black.withValues(alpha: 0.45),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: progress,
                    child: Container(color: _BrowserColors.accent),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStateTags({
    required bool isCurrent,
    required bool isFinished,
    required bool isLastPlayed,
    required double progress,
    bool available = true,
  }) {
    final tags = <Widget>[];

    if (!available) {
      tags.add(
        const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.download_rounded,
              color: _BrowserColors.inkFaint,
              size: 14,
            ),
            SizedBox(width: 3),
            Text(
              'Tap to fetch',
              style: TextStyle(
                color: _BrowserColors.inkFaint,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    if (isCurrent) {
      tags.add(
        const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.play_arrow_rounded,
              color: _BrowserColors.accent,
              size: 15,
            ),
            SizedBox(width: 2),
            Text(
              'Now playing',
              style: TextStyle(
                color: _BrowserColors.accent,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    } else if (isFinished) {
      tags.add(
        const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_rounded, color: _BrowserColors.done, size: 14),
            SizedBox(width: 3),
            Text(
              'Watched',
              style: TextStyle(
                color: _BrowserColors.done,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    } else if (progress > 0.01) {
      tags.add(
        Text.rich(
          TextSpan(
            text: 'Resume · ',
            style: const TextStyle(
              color: _BrowserColors.inkDim,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            children: [
              TextSpan(
                text: '${(progress * 100).round()}%',
                style: const TextStyle(
                  color: _BrowserColors.ink,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (isLastPlayed && !isCurrent) {
      tags.add(
        const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.replay_rounded,
              color: _BrowserColors.inkFaint,
              size: 13,
            ),
            SizedBox(width: 3),
            Text(
              'Last watched',
              style: TextStyle(
                color: _BrowserColors.inkFaint,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    if (tags.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: 12,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: tags,
    );
  }

  // ===== Dense row (compact list with mini thumbnail + expandable description) =====

  Widget _buildDenseRow({
    required SeriesEpisode episode,
    required int index,
    required bool isCurrent,
    required bool isFinished,
    required double progress,
    required double collapsedHeight,
    required bool showDivider,
  }) {
    final runtime = episode.episodeInfo?.runtime;
    final expanded = _expandedDense.contains(_denseKey(episode));
    final available = episode.originalIndex >= 0;

    final collapsedRow = SizedBox(
      height: collapsedHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            Opacity(
              opacity: available ? 1.0 : 0.55,
              child: _buildMiniThumb(
                episode: episode,
                index: index,
                progress: progress,
                isFinished: isFinished,
                isCurrent: isCurrent,
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 38,
              child: Text(
                episode.seriesInfo.episode != null
                    ? 'E${episode.seriesInfo.episode}'
                    : '${index + 1}',
                style: const TextStyle(
                  color: _BrowserColors.inkFaint,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            Expanded(
              child: Text(
                episode.displayTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: available ? _BrowserColors.ink : _BrowserColors.inkDim,
                  fontSize: 14,
                  fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 10),
            if (!available) ...[
              const Icon(
                Icons.download_rounded,
                color: _BrowserColors.inkFaint,
                size: 15,
              ),
              const SizedBox(width: 10),
            ],
            if (progress > 0.01 && !isFinished && !isCurrent) ...[
              Text(
                '${(progress * 100).round()}%',
                style: const TextStyle(
                  color: _BrowserColors.inkDim,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 10),
            ],
            if (runtime != null)
              Text(
                '${runtime}m',
                style: const TextStyle(
                  color: _BrowserColors.inkFaint,
                  fontSize: 12.5,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            // Expand arrow — opens the description without starting playback.
            IconButton(
              onPressed: () => _toggleDenseExpanded(episode),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
              splashRadius: 18,
              tooltip: expanded ? 'Hide details' : 'Show details',
              icon: AnimatedRotation(
                turns: expanded ? 0.5 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: const Icon(
                  Icons.expand_more,
                  color: _BrowserColors.inkFaint,
                  size: 20,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: isCurrent ? _BrowserColors.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                onTap: () => _onEpisodeTap(episode),
                borderRadius: BorderRadius.circular(10),
                splashColor: _BrowserColors.accent.withValues(alpha: 0.08),
                highlightColor: Colors.white.withValues(alpha: 0.04),
                child: collapsedRow,
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                alignment: Alignment.topCenter,
                child: expanded
                    ? _buildDenseExpandedContent(episode)
                    : const SizedBox(width: double.infinity, height: 0),
              ),
            ],
          ),
        ),
        if (showDivider && !isCurrent && !expanded)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Divider(height: 1, thickness: 1, color: _BrowserColors.line),
          ),
      ],
    );
  }

  Widget _buildMiniThumb({
    required SeriesEpisode episode,
    required int index,
    required double progress,
    required bool isFinished,
    required bool isCurrent,
  }) {
    const w = 54.0;
    const h = 32.0;
    final gradientColors = _BrowserColors
        .thumbGradients[index % _BrowserColors.thumbGradients.length];
    final placeholder = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
        ),
      ),
      child: Center(
        child: Icon(
          Icons.tv_rounded,
          size: 15,
          color: Colors.white.withValues(alpha: 0.25),
        ),
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: w,
        height: h,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (episode.episodeInfo?.poster != null)
              CachedNetworkImage(
                imageUrl: episode.episodeInfo!.poster!,
                memCacheWidth: 160,
                fit: BoxFit.cover,
                placeholder: (context, url) => placeholder,
                errorWidget: (context, url, error) => placeholder,
              )
            else
              placeholder,
            if (isCurrent)
              Container(
                color: Colors.black.withValues(alpha: 0.35),
                child: const Center(
                  child: Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              )
            else if (isFinished)
              Container(
                color: Colors.black.withValues(alpha: 0.45),
                child: const Center(
                  child: Icon(
                    Icons.check_rounded,
                    color: _BrowserColors.done,
                    size: 18,
                  ),
                ),
              )
            else if (progress > 0)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  height: 3,
                  color: Colors.black.withValues(alpha: 0.45),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: progress,
                    child: Container(color: _BrowserColors.accent),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDenseExpandedContent(SeriesEpisode episode) {
    final plot = episode.episodeInfo?.plot;
    final hasPlot = plot != null && plot.isNotEmpty;

    return Padding(
      // Indent under the thumbnail so the text aligns with the title column.
      padding: const EdgeInsets.fromLTRB(76, 0, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            hasPlot ? plot : 'No description available yet.',
            style: TextStyle(
              color: hasPlot ? _BrowserColors.inkDim : _BrowserColors.inkFaint,
              fontSize: 12.5,
              height: 1.4,
              fontStyle: hasPlot ? FontStyle.normal : FontStyle.italic,
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Material(
              color: _BrowserColors.accent,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                onTap: () => _onEpisodeTap(episode),
                borderRadius: BorderRadius.circular(8),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Play',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
