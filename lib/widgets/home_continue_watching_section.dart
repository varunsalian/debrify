import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models/advanced_search_selection.dart';
import '../services/storage_service.dart';
import '../services/series_source_service.dart';
import '../services/next_episode_service.dart';
import '../services/main_page_bridge.dart';
import '../screens/debrid_downloads_screen.dart';
import '../screens/torbox/torbox_downloads_screen.dart';
import 'add_source_picker_dialog.dart';
import 'home_focus_controller.dart';

/// Continue Watching section for the home screen.
/// Shows recently played movies and series with cinematic cards matching Trakt style.
class HomeContinueWatchingSection extends StatefulWidget {
  final HomeFocusController? focusController;
  final VoidCallback? onRequestFocusAbove;
  final VoidCallback? onRequestFocusBelow;
  final bool isTelevision;
  final void Function(AdvancedSearchSelection selection)? onItemSelected;
  final void Function(AdvancedSearchSelection selection)? onQuickPlay;
  final void Function(AdvancedSearchSelection selection)? onSelectSource;
  final void Function(AdvancedSearchSelection selection)? onSearchPacks;
  final void Function(AdvancedSearchSelection selection, String? addonId, {int? season, int? episode})? onBrowseEpisodes;

  const HomeContinueWatchingSection({
    super.key,
    this.focusController,
    this.onRequestFocusAbove,
    this.onRequestFocusBelow,
    this.isTelevision = false,
    this.onItemSelected,
    this.onQuickPlay,
    this.onSelectSource,
    this.onSearchPacks,
    this.onBrowseEpisodes,
  });

  @override
  State<HomeContinueWatchingSection> createState() =>
      _HomeContinueWatchingSectionState();
}

class _HomeContinueWatchingSectionState
    extends State<HomeContinueWatchingSection> {
  List<Map<String, dynamic>> _items = [];
  Map<String, double> _progressMap = {};
  Map<String, ({int season, int episode})> _episodeInfoMap = {};
  bool _isLoading = true;

  final List<FocusNode> _cardFocusNodes = [];
  final ScrollController _scrollController = ScrollController();
  bool _canScrollLeft = false;
  bool _canScrollRight = false;

  static const _accentColor = Color(0xFF6366F1);

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateScrollIndicators);
    _loadItems();
  }

  @override
  void dispose() {
    widget.focusController?.unregisterSection(HomeSection.continueWatching);
    for (final node in _cardFocusNodes) {
      node.dispose();
    }
    _scrollController.removeListener(_updateScrollIndicators);
    _scrollController.dispose();
    super.dispose();
  }

  void _updateScrollIndicators() {
    if (!mounted || !_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final canLeft = pos.pixels > 0;
    final canRight = pos.pixels < pos.maxScrollExtent;
    if (canLeft != _canScrollLeft || canRight != _canScrollRight) {
      setState(() {
        _canScrollLeft = canLeft;
        _canScrollRight = canRight;
      });
    }
  }

  void _ensureFocusNodes() {
    while (_cardFocusNodes.length < _items.length) {
      _cardFocusNodes.add(FocusNode(
          debugLabel: 'cw_card_${_cardFocusNodes.length}'));
    }
    while (_cardFocusNodes.length > _items.length) {
      _cardFocusNodes.removeLast().dispose();
    }
  }

  Future<void> _loadItems() async {
    setState(() => _isLoading = true);

    try {
      final items = await StorageService.getContinueWatchingItems();
      if (!mounted) return;

      if (items.isEmpty) {
        _finishEmpty();
        return;
      }

      // Load progress and episode info for each item from playback state
      final progressMap = <String, double>{};
      final episodeInfoMap = <String, ({int season, int episode})>{};
      for (final item in items) {
        final imdbId = item['imdbId'] as String?;
        final contentType = item['contentType'] as String?;
        if (imdbId == null) continue;

        if (contentType == 'series') {
          final lastEp = await StorageService.getLastPlayedEpisodeByImdbId(imdbId);
          if (lastEp != null) {
            final finished = lastEp['finished'] == true;
            final posMs = lastEp['positionMs'] as int? ?? 0;
            final durMs = lastEp['durationMs'] as int? ?? 1;
            if (durMs > 0) {
              progressMap[imdbId] = finished ? 100.0 : (posMs / durMs * 100).clamp(0.0, 100.0);
            }
            final s = lastEp['season'] as int?;
            final e = lastEp['episode'] as int?;
            if (s != null && e != null) {
              episodeInfoMap[imdbId] = (season: s, episode: e);
            }
          }
        } else {
          final state = await StorageService.getVideoPlaybackStateByImdbId(imdbId);
          if (state != null) {
            final posMs = state['positionMs'] as int? ?? 0;
            final durMs = state['durationMs'] as int? ?? 1;
            if (durMs > 0) {
              progressMap[imdbId] = (posMs / durMs * 100).clamp(0.0, 100.0);
            }
          }
        }
      }

      if (!mounted) return;

      _items = items;
      _progressMap = progressMap;
      _episodeInfoMap = episodeInfoMap;
      _ensureFocusNodes();

      setState(() {
        _isLoading = false;
      });
      widget.focusController?.registerSection(
        HomeSection.continueWatching,
        hasItems: _items.isNotEmpty,
        focusNodes: _cardFocusNodes,
      );

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateScrollIndicators();
      });
    } catch (e) {
      debugPrint('HomeContinueWatching: Error loading items: $e');
      _finishEmpty();
    }
  }

  void _finishEmpty() {
    if (!mounted) return;
    setState(() {
      _items = [];
      _isLoading = false;
    });
    widget.focusController?.registerSection(
      HomeSection.continueWatching,
      hasItems: false,
      focusNodes: [],
    );
  }

  void _onItemTap(Map<String, dynamic> item) async {
    final title = item['title'] as String? ?? '';
    final contentType = item['contentType'] as String? ?? 'movie';
    final imdbId = item['imdbId'] as String?;
    final isSeries = contentType == 'series';

    // Check if item has bound source (works for both movies and series)
    bool hasBoundSource = false;
    if (imdbId != null && widget.onSelectSource != null) {
      final sources = await SeriesSourceService.getSources(imdbId);
      hasBoundSource = sources.isNotEmpty;
    }
    if (!mounted) return;

    final choice = await showDialog<String>(
      context: context,
      builder: (context) => Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 380),
            decoration: BoxDecoration(
              color: const Color(0xFF141824),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: FocusTraversalGroup(
              child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
                _MenuItem(
                  icon: Icons.play_circle_filled_rounded,
                  label: 'Play',
                  subtitle: 'Quick play with default source',
                  color: const Color(0xFF10B981),
                  onTap: () => Navigator.pop(context, 'quick_play'),
                  autofocus: true,
                  isTelevision: widget.isTelevision,
                ),
                _MenuItem(
                  icon: isSeries ? Icons.view_list_rounded : Icons.search_rounded,
                  label: isSeries ? 'Browse Episodes' : 'Browse Sources',
                  subtitle: isSeries ? 'View seasons and episodes' : 'Find available sources',
                  color: const Color(0xFF818CF8),
                  onTap: () => Navigator.pop(context, 'browse'),
                  isTelevision: widget.isTelevision,
                ),
                if (widget.onSelectSource != null)
                  _MenuItem(
                    icon: hasBoundSource ? Icons.edit_rounded : Icons.add_link_rounded,
                    label: hasBoundSource ? 'Edit Source' : 'Add Source',
                    subtitle: hasBoundSource ? 'Change the bound torrent source' : 'Bind a torrent source for quick play',
                    color: const Color(0xFF60A5FA),
                    onTap: () => Navigator.pop(context, 'select_source'),
                    isTelevision: widget.isTelevision,
                  ),
                if (isSeries && widget.onSearchPacks != null)
                  _MenuItem(
                    icon: Icons.inventory_2_outlined,
                    label: 'Search Season Packs',
                    subtitle: 'Find full season packs to download or add',
                    color: const Color(0xFFFBBF24),
                    onTap: () => Navigator.pop(context, 'search_packs'),
                    isTelevision: widget.isTelevision,
                  ),
                Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
                _MenuItem(
                  icon: Icons.remove_circle_outline_rounded,
                  label: 'Remove from Continue Watching',
                  subtitle: 'Remove from this list',
                  color: const Color(0xFFEF4444),
                  onTap: () => Navigator.pop(context, 'remove'),
                  isTelevision: widget.isTelevision,
                ),
                const SizedBox(height: 8),
              ],
            ),
            ),
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;

    final selection = _selectionFromItem(item);
    if (selection == null) return;

    if (choice == 'quick_play') {
      if (selection.isSeries) {
        // Use cached episode info from _loadItems
        final cachedEp = _episodeInfoMap[selection.imdbId];
        if (cachedEp != null) {
          int season = cachedEp.season;
          int episode = cachedEp.episode;
          // If episode is near-complete (>=90%) or finished, find the real next episode from the catalog
          final progress = _progressMap[selection.imdbId] ?? 0.0; // 0-100
          debugPrint('HomeContinueWatching: Quick Play S${season}E$episode progress=$progress');
          if (progress >= 90) {
            final nextEp = await _findNextEpisode(selection.imdbId, season, episode, item['addonId'] as String?);
            if (!mounted) return;
            if (nextEp != null) {
              season = nextEp.season;
              episode = nextEp.episode;
            } else {
              // No next episode found — fall through to browse
              widget.onItemSelected?.call(selection);
              return;
            }
          }
          final withEpisode = AdvancedSearchSelection(
            imdbId: selection.imdbId,
            isSeries: true,
            title: selection.title,
            year: selection.year,
            contentType: selection.contentType,
            posterUrl: selection.posterUrl,
            season: season,
            episode: episode,
          );
          if (widget.onQuickPlay != null) {
            widget.onQuickPlay!(withEpisode);
          } else {
            widget.onItemSelected?.call(withEpisode);
          }
        } else {
          // No episode from IMDB lookup — try title-based fallback
          int fallbackSeason = 1;
          int fallbackEpisode = 1;
          final titleLastEp = await StorageService.getLastPlayedEpisode(
            seriesTitle: selection.title,
          );
          if (titleLastEp != null) {
            fallbackSeason = titleLastEp['season'] as int? ?? 1;
            fallbackEpisode = titleLastEp['episode'] as int? ?? 1;
          }
          final withEpisode = AdvancedSearchSelection(
            imdbId: selection.imdbId,
            isSeries: true,
            title: selection.title,
            year: selection.year,
            contentType: selection.contentType,
            posterUrl: selection.posterUrl,
            season: fallbackSeason,
            episode: fallbackEpisode,
          );
          if (widget.onQuickPlay != null) {
            widget.onQuickPlay!(withEpisode);
          } else {
            widget.onItemSelected?.call(withEpisode);
          }
        }
      } else {
        if (widget.onQuickPlay != null) {
          widget.onQuickPlay!(selection);
        } else {
          widget.onItemSelected?.call(selection);
        }
      }
    } else if (choice == 'browse') {
      if (selection.isSeries && widget.onBrowseEpisodes != null) {
        final addonId = item['addonId'] as String?;
        final cachedEp = _episodeInfoMap[selection.imdbId];
        widget.onBrowseEpisodes!(selection, addonId,
          season: cachedEp?.season,
          episode: cachedEp?.episode,
        );
      } else {
        widget.onItemSelected?.call(selection);
      }
    } else if (choice == 'select_source') {
      if (hasBoundSource) {
        await _showEditSourceDialog(selection);
      } else {
        await _showAddSourcePicker(selection);
      }
    } else if (choice == 'search_packs') {
      widget.onSearchPacks?.call(selection);
    } else if (choice == 'remove') {
      final imdbId = item['imdbId'] as String?;
      if (imdbId != null) {
        await StorageService.removeContinueWatchingItem(imdbId);
        await StorageService.clearPlaybackStateByImdbId(imdbId);
        if (mounted) _loadItems();
      }
    }
  }

  AdvancedSearchSelection? _selectionFromItem(Map<String, dynamic> item) {
    final imdbId = item['imdbId'] as String?;
    if (imdbId == null) return null;
    return AdvancedSearchSelection(
      imdbId: imdbId,
      isSeries: item['contentType'] == 'series',
      title: item['title'] as String? ?? '',
      year: item['year'] as String?,
      contentType: item['contentType'] as String?,
      posterUrl: item['posterUrl'] as String?,
    );
  }

  /// Find the next episode after the given season/episode using the Stremio catalog addon.
  Future<({int season, int episode})?> _findNextEpisode(
    String imdbId, int currentSeason, int currentEpisode, String? addonId,
  ) async {
    return NextEpisodeService.findNextEpisode(imdbId, currentSeason, currentEpisode);
  }

  Future<void> _showEditSourceDialog(AdvancedSearchSelection selection) async {
    var sources = await SeriesSourceService.getSources(selection.imdbId);
    if (sources.isEmpty || !mounted) return;
    final isMovie = !selection.isSeries;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return Dialog(
              backgroundColor: const Color(0xFF141824),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 450, maxHeight: 500),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.link_rounded, color: Color(0xFF60A5FA), size: 24),
                          const SizedBox(width: 8),
                          Text(
                            isMovie ? 'Movie Source' : 'Series Sources (${sources.length})',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      if (!isMovie) ...[
                        const SizedBox(height: 4),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'First match wins — reorder by priority',
                            style: TextStyle(color: Colors.white38, fontSize: 11),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: sources.length,
                          itemBuilder: (context, index) {
                            final source = sources[index];
                            return ListTile(
                              key: ValueKey(source.torrentHash),
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Container(
                                width: 32, height: 32,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF60A5FA).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Center(
                                  child: Text('${index + 1}', style: const TextStyle(color: Color(0xFF60A5FA), fontWeight: FontWeight.w600)),
                                ),
                              ),
                              title: Text(
                                source.torrentName,
                                style: const TextStyle(fontSize: 13),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: IconButton(
                                icon: Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red.withValues(alpha: 0.7)),
                                onPressed: () async {
                                  await SeriesSourceService.removeSourceByHash(selection.imdbId, source.torrentHash);
                                  final updated = await SeriesSourceService.getSources(selection.imdbId);
                                  setDialogState(() {
                                    sources = updated;
                                  });
                                  if (updated.isEmpty && dialogContext.mounted) {
                                    Navigator.of(dialogContext).pop();
                                  }
                                },
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Add from Debrid button
                      FutureBuilder<List<bool>>(
                        future: Future.wait([
                          StorageService.getApiKey().then((k) => k != null && k.isNotEmpty),
                          StorageService.getTorboxApiKey().then((k) => k != null && k.isNotEmpty),
                        ]),
                        builder: (context, snapshot) {
                          final rdEnabled = snapshot.data?[0] ?? false;
                          final torboxEnabled = snapshot.data?[1] ?? false;
                          if (!rdEnabled && !torboxEnabled) return const SizedBox.shrink();

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.of(dialogContext).pop();
                                  _pushDebridSelectSource(
                                    selection: selection,
                                    rdEnabled: rdEnabled,
                                    torboxEnabled: torboxEnabled,
                                  );
                                },
                                icon: const Icon(Icons.cloud_download_outlined, size: 18, color: Color(0xFF60A5FA)),
                                label: const Text('Add from Debrid', style: TextStyle(color: Color(0xFF60A5FA))),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Color(0xFF60A5FA), width: 1),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            child: const Text('Close'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            icon: Icon(isMovie ? Icons.swap_horiz_rounded : Icons.add_rounded, size: 18),
                            label: Text(isMovie ? 'Change Source' : 'Add Source'),
                            onPressed: () {
                              Navigator.of(dialogContext).pop();
                              widget.onSelectSource?.call(selection);
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Show the add-source picker (Torrent Search / Real-Debrid / TorBox).
  /// Skips the picker if no cloud providers are enabled.
  Future<void> _showAddSourcePicker(AdvancedSearchSelection selection) async {
    final rdKey = await StorageService.getApiKey();
    final torboxKey = await StorageService.getTorboxApiKey();
    final rdEnabled = rdKey != null && rdKey.isNotEmpty;
    final torboxEnabled = torboxKey != null && torboxKey.isNotEmpty;

    if (!mounted) return;

    if (!rdEnabled && !torboxEnabled) {
      widget.onSelectSource?.call(selection);
      return;
    }

    await showAddSourcePickerDialog(
      context,
      onTorrentSearch: () => widget.onSelectSource?.call(selection),
      onRealDebrid: rdEnabled
          ? () => _pushDebridSelectSource(
                selection: selection,
                rdEnabled: true,
                torboxEnabled: false,
              )
          : null,
      onTorbox: torboxEnabled
          ? () => _pushDebridSelectSource(
                selection: selection,
                rdEnabled: false,
                torboxEnabled: true,
              )
          : null,
    );
  }

  void _pushDebridSelectSource({
    required AdvancedSearchSelection selection,
    required bool rdEnabled,
    required bool torboxEnabled,
  }) {
    final imdbId = selection.imdbId;
    final isMovie = !selection.isSeries;

    Future<void> saveSource(SeriesSource source) async {
      if (isMovie) {
        await SeriesSourceService.setSources(imdbId, [source]);
      } else {
        await SeriesSourceService.addSource(imdbId, source);
      }
    }

    void pushRd() {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => DebridDownloadsScreen(
          isPushedRoute: true,
          initialSearchQuery: selection.title,
          selectSourceMode: true,
          onSourceSelected: saveSource,
        ),
      ));
    }

    void pushTorbox() {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => TorboxDownloadsScreen(
          isPushedRoute: true,
          initialSearchQuery: selection.title,
          selectSourceMode: true,
          onSourceSelected: saveSource,
        ),
      ));
    }

    if (rdEnabled && !torboxEnabled) {
      pushRd();
      return;
    }
    if (torboxEnabled && !rdEnabled) {
      pushTorbox();
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF141824),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Select Provider',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.cloud, color: Color(0xFF22C55E)),
              title: const Text('Real-Debrid', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.of(sheetContext).pop();
                pushRd();
              },
            ),
            ListTile(
              leading: const Icon(Icons.cloud, color: Color(0xFF7C3AED)),
              title: const Text('TorBox', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.of(sheetContext).pop();
                pushTorbox();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
          child: Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: _accentColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'Continue Watching',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${_items.length}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        // Horizontal card list
        SizedBox(
          height: 200,
          child: ListView.builder(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _items.length,
            itemBuilder: (context, index) {
              final item = _items[index];
              final imdbId = item['imdbId'] as String? ?? '';
              final progress = _progressMap[imdbId];

              return Padding(
                padding: EdgeInsets.only(
                    right: index < _items.length - 1 ? 16 : 0),
                child: _buildCard(
                  item: item,
                  progressPercent: progress != null ? progress / 100.0 : null,
                  episodeInfo: _episodeInfoMap[imdbId],
                  index: index,
                  focusNode: index < _cardFocusNodes.length
                      ? _cardFocusNodes[index]
                      : null,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Divider(height: 1, thickness: 0.5, color: Color(0x14FFFFFF)),
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _buildCard({
    required Map<String, dynamic> item,
    double? progressPercent,
    ({int season, int episode})? episodeInfo,
    int index = 0,
    FocusNode? focusNode,
  }) {
    return _CardWithFocus(
      onTap: () => _onItemTap(item),
      focusNode: focusNode,
      index: index,
      totalCount: _items.length,
      scrollController: _scrollController,
      onUpPressed: widget.onRequestFocusAbove,
      onDownPressed: widget.onRequestFocusBelow,
      allFocusNodes: _cardFocusNodes,
      isTelevision: widget.isTelevision,
      onFocusChanged: (focused, idx) {
        if (focused) {
          widget.focusController
              ?.saveLastFocusedIndex(HomeSection.continueWatching, idx);
        }
      },
      child: (isFocused, isHovered) {
        final isActive = isFocused || isHovered;
        final screenWidth = MediaQuery.of(context).size.width;
        final isMobile = screenWidth < 600;
        final isHero = index == 0;
        final cardWidth = isMobile
            ? (isHero ? screenWidth * 0.82 : screenWidth * 0.7)
            : (isHero ? 350.0 : 280.0);
        final cardHeight = isMobile
            ? (isHero ? 180.0 : 155.0)
            : (isHero ? 200.0 : 170.0);

        final title = item['title'] as String? ?? '';
        final posterUrl = item['posterUrl'] as String?;
        final contentType = item['contentType'] as String? ?? 'movie';
        final year = item['year'] as String? ?? '';

        final cardStack = Stack(
            fit: StackFit.expand,
            children: [
              // Backdrop image
              _buildBackdropImage(posterUrl, title),

              // Cinematic gradient overlay
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.1),
                        Colors.black.withValues(alpha: 0.75),
                        Colors.black.withValues(alpha: 0.95),
                      ],
                      stops: const [0.0, 0.3, 0.65, 1.0],
                    ),
                  ),
                ),
              ),
              // Left vignette (skip on TV for GPU perf)
              if (!widget.isTelevision)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Colors.black.withValues(alpha: 0.3),
                        Colors.transparent,
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.3, 1.0],
                    ),
                  ),
                ),
              ),

              // Type badge (top left)
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: contentType == 'series'
                        ? _accentColor
                        : const Color(0xFFEF4444),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    contentType == 'series' ? 'SERIES' : 'MOVIE',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),

              // Bottom info area
              Positioned(
                bottom: progressPercent != null ? 5 : 12,
                left: 12,
                right: 12,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        height: 1.2,
                        letterSpacing: -0.2,
                        shadows: widget.isTelevision ? null : const [
                          Shadow(color: Colors.black, blurRadius: 8),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (year.isNotEmpty)
                          Text(
                            year,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withValues(alpha: 0.6),
                            ),
                          ),
                        if (year.isNotEmpty && episodeInfo != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Container(
                              width: 3,
                              height: 3,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.3),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        if (episodeInfo != null)
                          Text(
                            'S${episodeInfo.season.toString().padLeft(2, '0')}E${episodeInfo.episode.toString().padLeft(2, '0')}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withValues(alpha: 0.6),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              // Progress bar
              if (progressPercent != null)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: SizedBox(
                    height: 3.5,
                    child: Stack(
                      children: [
                        Container(
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                        FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: progressPercent.clamp(0.0, 1.0),
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xFFED1C24),
                                  Color(0xFFFF4D4D),
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFED1C24).withValues(alpha: 0.6),
                                  blurRadius: 6,
                                  offset: const Offset(0, -1),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Play overlay on hover/focus
              if (widget.isTelevision && isActive)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.25),
                    child: Center(
                      child: _buildPlayButton(),
                    ),
                  ),
                )
              else if (!widget.isTelevision)
              Positioned.fill(
                child: AnimatedOpacity(
                        opacity: isActive ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 200),
                        child: Container(
                          color: Colors.black.withValues(alpha: 0.25),
                          child: Center(
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(
                                  begin: 0.85, end: isActive ? 1.0 : 0.85),
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOutBack,
                              builder: (context, scale, child) =>
                                  Transform.scale(scale: scale, child: child),
                              child: _buildPlayButton(),
                            ),
                          ),
                        ),
                      ),
              ),
            ],
        );

        final cardDecoration = BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive
                ? Colors.white.withValues(alpha: 0.25)
                : Colors.white.withValues(alpha: 0.08),
            width: isActive ? 1.5 : 0.5,
          ),
          boxShadow: widget.isTelevision
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isActive ? 0.9 : 0.6),
                    blurRadius: isActive ? 30 : 16,
                    offset: const Offset(0, 8),
                  ),
                ],
        );

        if (widget.isTelevision) {
          return Transform.scale(
            scale: isActive ? 1.05 : 1.0,
            child: Container(
              width: cardWidth,
              height: cardHeight,
              clipBehavior: Clip.hardEdge,
              decoration: cardDecoration,
              child: cardStack,
            ),
          );
        }

        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 1.0, end: isActive ? 1.05 : 1.0),
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          builder: (context, scale, child) =>
              Transform.scale(scale: scale, child: child),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            width: cardWidth,
            height: cardHeight,
            decoration: cardDecoration,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: cardStack,
            ),
          ),
        );
      },
    );
  }

  Widget _buildPlayButton() {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.15),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.4),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 16,
          ),
        ],
      ),
      child: ClipOval(
        child: widget.isTelevision
            ? Container(
                color: Colors.black.withValues(alpha: 0.6),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              )
            : BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
      ),
    );
  }

  Widget _buildBackdropImage(String? imageUrl, String title) {
    if (imageUrl != null && imageUrl.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: imageUrl,
        memCacheWidth: 600,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(
          color: const Color(0xFF0D1117),
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                valueColor: AlwaysStoppedAnimation<Color>(
                  Colors.white.withValues(alpha: 0.2),
                ),
              ),
            ),
          ),
        ),
        errorWidget: (context, url, error) => _buildPlaceholder(title),
      );
    }
    return _buildPlaceholder(title);
  }

  Widget _buildPlaceholder(String title) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A1A2E), Color(0xFF0D1117)],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.movie_rounded,
              size: 28,
              color: Colors.white.withValues(alpha: 0.15),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.3),
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Focus-aware card wrapper (DPAD/TV) ────────────────────────────────────────

class _CardWithFocus extends StatefulWidget {
  final VoidCallback? onTap;
  final FocusNode? focusNode;
  final int index;
  final int totalCount;
  final ScrollController? scrollController;
  final VoidCallback? onUpPressed;
  final VoidCallback? onDownPressed;
  final void Function(bool focused, int index)? onFocusChanged;
  final Widget Function(bool isFocused, bool isHovered) child;
  final List<FocusNode>? allFocusNodes;
  final bool isTelevision;

  const _CardWithFocus({
    required this.onTap,
    required this.child,
    this.focusNode,
    this.index = 0,
    this.totalCount = 1,
    this.scrollController,
    this.onUpPressed,
    this.onDownPressed,
    this.onFocusChanged,
    this.allFocusNodes,
    this.isTelevision = false,
  });

  @override
  State<_CardWithFocus> createState() => _CardWithFocusState();
}

class _CardWithFocusState extends State<_CardWithFocus> {
  bool _isFocused = false;
  bool _isHovered = false;
  final GlobalKey _cardKey = GlobalKey();

  void _onFocusChange(bool focused) {
    setState(() => _isFocused = focused);
    widget.onFocusChanged?.call(focused, widget.index);

    if (focused && widget.scrollController != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final context = _cardKey.currentContext;
        if (context != null) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            duration: widget.isTelevision
                ? Duration.zero
                : const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
          );
        }
      });
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.select ||
          event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.gameButtonA) {
        widget.onTap?.call();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        widget.onUpPressed?.call();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        widget.onDownPressed?.call();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        if (widget.isTelevision && widget.allFocusNodes != null) {
          if (widget.index > 0) {
            widget.allFocusNodes![widget.index - 1].requestFocus();
          } else {
            MainPageBridge.focusTvSidebar?.call();
          }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        if (widget.isTelevision && widget.allFocusNodes != null) {
          if (widget.index < widget.allFocusNodes!.length - 1) {
            widget.allFocusNodes![widget.index + 1].requestFocus();
          }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Focus(
        focusNode: widget.focusNode,
        onFocusChange: _onFocusChange,
        onKeyEvent: _handleKeyEvent,
        child: GestureDetector(
          onTap: widget.onTap,
          child: KeyedSubtree(
            key: _cardKey,
            child: widget.child(_isFocused, _isHovered),
          ),
        ),
      ),
    );
  }
}

// ── Menu item for options dialog ──────────────────────────────────────────────

class _MenuItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  final bool autofocus;
  final bool isTelevision;

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.autofocus = false,
    this.isTelevision = false,
  });

  @override
  State<_MenuItem> createState() => _MenuItemState();
}

class _MenuItemState extends State<_MenuItem> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      autofocus: widget.autofocus,
      canRequestFocus: true,
      onTap: widget.onTap,
      onFocusChange: (focused) => setState(() => _focused = focused),
      borderRadius: BorderRadius.circular(8),
      child: widget.isTelevision
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: _focused ? Colors.white.withValues(alpha: 0.08) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: _buildContent(),
            )
          : AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: _focused ? Colors.white.withValues(alpha: 0.08) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: _buildContent(),
            ),
    );
  }

  Widget _buildContent() {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: _focused ? 0.2 : 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(widget.icon, size: 18, color: widget.color),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              Text(widget.subtitle, style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.4))),
            ],
          ),
        ),
      ],
    );
  }
}
