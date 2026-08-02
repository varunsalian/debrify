import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/android_native_downloader.dart';
import '../../../services/desktop_schedule_service.dart';
import '../../../services/iptv_epg_service.dart';
import '../../../services/live_recording_service.dart';
import '../../../widgets/recording_limit_dialogs.dart';
import '../../../services/storage_service.dart';
import '../../../utils/platform_util.dart';
import '../../../utils/tv_keys.dart';
import '../../../models/iptv_playlist.dart';
import '../../../widgets/iptv/iptv_epg_panel.dart';
import '../../../widgets/tv_text_field.dart';

typedef IptvGuideChannelSelected =
    Future<void> Function(List<IptvChannel> channels, int index);

typedef IptvGuideProgrammeSelected =
    Future<void> Function(IptvChannel channel, EpgProgramme programme);

/// Catalog position owned by the guide after a browse request.
///
/// A nullable [selectedCategory] deliberately represents "All", so callers
/// must not replace it with the launch-time category when reopening the guide.
class IptvGuideContext {
  final List<String> categories;
  final String? sourceId;
  final String sourceName;
  final String? selectedCategory;
  final String contentType;

  IptvGuideContext({
    required List<String> categories,
    required this.sourceId,
    required this.sourceName,
    required this.selectedCategory,
    required this.contentType,
  }) : categories = List<String>.unmodifiable(categories);
}

/// Adaptive IPTV guide overlay for the Flutter video player.
///
/// Phones use a touch-first bottom sheet and an explicit calendar button on
/// every row. Large tablets/desktops use a two-pane channel + schedule layout.
/// Both presentations share the same catalog, favorite, EPG and playback
/// state so changing the window size never changes behavior.
class IptvChannelSheet extends StatefulWidget {
  final List<IptvChannel> channels;
  final int currentIndex;
  final IptvGuideChannelSelected onChannelSelected;
  final IptvGuideProgrammeSelected? onPlayProgramme;
  final VoidCallback onClose;
  final List<String> categories;
  final String? sourceId;
  final String? sourceName;
  final String? selectedCategory;
  final String contentType;
  final List<Map<String, dynamic>> sources;
  final Future<Map<String, dynamic>?> Function(Map<String, dynamic>)?
  browseProvider;
  final ValueChanged<IptvGuideContext>? onContextChanged;

  const IptvChannelSheet({
    super.key,
    required this.channels,
    required this.currentIndex,
    required this.onChannelSelected,
    this.onPlayProgramme,
    required this.onClose,
    this.categories = const [],
    this.sourceId,
    this.sourceName,
    this.selectedCategory,
    this.contentType = 'live',
    this.sources = const [],
    this.browseProvider,
    this.onContextChanged,
  });

  @override
  State<IptvChannelSheet> createState() => _IptvChannelSheetState();
}

enum _FocusZone { search, channels }

enum _CompactPane { channels, schedule }

class _IptvChannelSheetState extends State<IptvChannelSheet>
    with TickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _keyboardFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  late AnimationController _animController;
  late Animation<Offset> _slideAnim;
  late Animation<double> _fadeAnim;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  late List<IptvChannel> _channels;
  List<IptvChannel> _filteredChannels = [];
  int _focusedIndex = 0;
  _FocusZone _focusZone = _FocusZone.channels;
  _CompactPane _compactPane = _CompactPane.channels;
  IptvChannel? _scheduleChannel;

  /// Engine flag + Android 10+ probe passed — future EPG rows may offer
  /// "Record" (still gated per channel on recordability).
  bool _recordSchedulingAvailable = false;
  late List<String> _categories;
  late String? _sourceId;
  late String _sourceName;
  late String? _selectedCategory;
  late String _contentType;
  late List<Map<String, dynamic>> _sources;
  Set<String> _favoriteUrls = <String>{};
  bool _favoritesOnly = false;

  /// A submitted search is browsing every category. The category it
  /// interrupted is parked here and restored when the search is cleared.
  bool _allCategorySearch = false;
  String? _categoryBeforeSearch;

  /// The query the loaded list actually answers. The "press enter" prompt is
  /// only true of a query that has been typed but not yet submitted — once
  /// the results are in, the header goes back to counting them.
  String _submittedQuery = '';
  bool _browseLoading = false;
  String? _browseError;
  int _browseTicket = 0;

  // Design tokens
  static const _accent = Color(0xFF00E5FF);
  static const _accentAlt = Color(0xFF00B8D4);
  static const _surfaceDark = Color(0xFF101016);

  @override
  void initState() {
    super.initState();

    _channels = List.from(widget.channels);
    _filteredChannels = List.from(_channels);
    _categories = List<String>.from(widget.categories);
    _sourceId = widget.sourceId;
    _sourceName = widget.sourceName ?? 'IPTV';
    _selectedCategory = widget.selectedCategory;
    _contentType = widget.contentType;
    _sources = List<Map<String, dynamic>>.from(widget.sources);

    if (widget.currentIndex >= 0 && widget.currentIndex < _channels.length) {
      final cur = _channels[widget.currentIndex];
      final idx = _filteredChannels.indexWhere(
        (c) => c.url == cur.url && c.name == cur.name,
      );
      if (idx >= 0) {
        _focusedIndex = idx;
        _scheduleChannel = cur;
      }
    }
    if (_scheduleChannel == null && _channels.isNotEmpty) {
      _scheduleChannel = _channels.first;
    }
    unawaited(_loadFavorites());

    // Whether future programmes may offer "Record": on Android, engine flag
    // on AND the device can publish recordings (10+); on desktop, the in-app
    // scheduler exists unconditionally. Per-channel recordability is checked
    // where the schedule pane builds.
    if (Platform.isAndroid) {
      unawaited(() async {
        final on = await LiveRecordingService.engineEnabled();
        if (!on) return;
        // needs_permission still shows the REC rows — pressing one requests
        // the pre-Q storage grant.
        final support = await LiveRecordingService.engineSupport();
        if (support != 'unsupported' && mounted) {
          setState(() => _recordSchedulingAvailable = true);
        }
      }());
    } else if (DesktopScheduleService.instance.isSupported) {
      _recordSchedulingAvailable = true;
    }

    // Slide + fade in
    _animController = AnimationController(
      duration: const Duration(milliseconds: 350),
      vsync: this,
    );
    _slideAnim = Tween<Offset>(begin: const Offset(1.0, 0.0), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
        );
    _fadeAnim = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));

    // Pulsing glow for now-playing
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _animController.forward();

    _searchFocusNode.addListener(() {
      if (!_searchFocusNode.hasFocus) return;
      // Entering the field widens the scope to every category, exactly when
      // the native guide does it (beginIptvAllCategorySearch on focus). Doing
      // it only on submit meant the typed filter still had the category
      // applied, so a channel from anywhere else could not appear and the
      // search read as broken.
      _beginAllCategorySearch();
      if (_focusZone != _FocusZone.search) {
        setState(() => _focusZone = _FocusZone.search);
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToFocused());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _keyboardFocusNode.dispose();
    _scrollController.dispose();
    _animController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  // ─── Filtering ───────────────────────────────────────────────────────

  void _applyFilters() {
    // Typing does NOT narrow the list. The loaded channels are a page of the
    // source, so filtering them as you type empties the list for anything
    // that simply is not on this page — which reads as "no such channel"
    // when the channel exists and the query has just never been run. The
    // native guide leaves the list alone until the query is submitted and
    // says so in the header; this now matches.
    //
    // Sheets with no browse provider are the exception: a series' episode
    // list has no source to submit to, so there local filtering IS the
    // search.
    final query = widget.browseProvider == null
        ? _searchController.text.trim().toLowerCase()
        : '';
    setState(() {
      _filteredChannels = _channels.where((c) {
        if (_favoritesOnly && !_favoriteUrls.contains(c.url)) return false;
        if (_selectedCategory != null &&
            _selectedCategory!.isNotEmpty &&
            c.group != _selectedCategory) {
          return false;
        }
        return query.isEmpty || c.searchKey.contains(query);
      }).toList();

      final cur =
          (widget.currentIndex >= 0 &&
              widget.currentIndex < widget.channels.length)
          ? widget.channels[widget.currentIndex]
          : null;
      final idx = cur == null
          ? -1
          : _filteredChannels.indexWhere(
              (c) => c.url == cur.url && c.name == cur.name,
            );
      _focusedIndex = idx >= 0
          ? idx
          : _filteredChannels.isNotEmpty
          ? _focusedIndex.clamp(0, _filteredChannels.length - 1)
          : 0;
    });
  }

  Future<void> _loadFavorites() async {
    final favorites = await StorageService.getIptvFavoriteChannels();
    if (!mounted) return;
    setState(() => _favoriteUrls = favorites.keys.toSet());
  }

  String? _originSourceId(IptvChannel channel) =>
      channel.attributes['source_playlist_id'] ??
      channel.attributes['series_playlist_id'] ??
      _sourceId;

  Future<void> _toggleFavorite(IptvChannel channel) async {
    final next = !_favoriteUrls.contains(channel.url);
    setState(() {
      if (next) {
        _favoriteUrls.add(channel.url);
      } else {
        _favoriteUrls.remove(channel.url);
      }
    });
    await StorageService.setIptvChannelFavorited(
      channel.url,
      next,
      channelName: channel.name,
      logoUrl: channel.logoUrl,
      group: channel.group,
      playlistId: _originSourceId(channel),
      channelNumber: channel.channelNumber,
      httpHeaders: channel.httpHeaders,
    );
    if (mounted && _favoritesOnly) _applyFilters();
  }

  /// Park the current category and widen the scope to the whole source.
  ///
  /// Search is a temporary all-categories browsing context, entered the
  /// moment the field takes focus — the same trigger as the native guide's
  /// `beginIptvAllCategorySearch`. Left scoped to the selected category, the
  /// obvious search (pick "Sports", look for "BBC") returned nothing with no
  /// hint a filter was suppressing it. The category is remembered and put
  /// back when the search is cleared or the guide closes.
  ///
  /// Deliberately does not re-browse: the native guide leaves the visible list
  /// alone until the query is submitted, and refetching on every focus would
  /// throw away the list the user is looking at.
  void _beginAllCategorySearch() {
    if (_allCategorySearch) return;
    _allCategorySearch = true;
    _categoryBeforeSearch = _selectedCategory;
    if (_selectedCategory == null) return;
    setState(() => _selectedCategory = null);
    _applyFilters();
    _notifyContextChanged();
  }

  /// Run the typed query against the whole source. Submitting is the only
  /// thing that searches — typing never does.
  Future<void> _submitSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      await _clearSearch();
      return;
    }
    _beginAllCategorySearch();
    _submittedQuery = query;
    await _requestBrowse(category: null, query: query);
  }

  /// Close the guide, putting back the category an unfinished search parked.
  ///
  /// A submitted search persists `selectedCategory: null` to the player, but
  /// the category it interrupted lives only in this state — closing without
  /// restoring it would dispose the only record, so the guide would reopen on
  /// "All" over a category-scoped channel ring. The native guide restores the
  /// same way on close (`restoreIptvCategoryAfterSearch` in `hideIptvGuide`).
  void _handleClose() {
    _submittedQuery = '';
    if (_allCategorySearch) {
      _selectedCategory = _categoryBeforeSearch;
      _allCategorySearch = false;
      _categoryBeforeSearch = null;
      _notifyContextChanged();
    }
    widget.onClose();
  }

  /// Drop the query and put back whatever category the search interrupted.
  Future<void> _clearSearch() async {
    _searchController.clear();
    _submittedQuery = '';
    if (!_allCategorySearch) {
      if (widget.browseProvider == null) {
        _applyFilters();
      } else {
        await _requestBrowse(query: '');
      }
      return;
    }
    final restored = _categoryBeforeSearch;
    _allCategorySearch = false;
    _categoryBeforeSearch = null;
    setState(() => _selectedCategory = restored);
    if (widget.browseProvider == null) {
      _applyFilters();
      _notifyContextChanged();
      return;
    }
    await _requestBrowse(category: restored, query: '');
  }

  Future<void> _selectCategory(String? category) async {
    _selectedCategory = category;
    _favoritesOnly = false;
    // An explicit category choice ends the search context rather than being
    // undone by a later restore.
    _allCategorySearch = false;
    _categoryBeforeSearch = null;
    _submittedQuery = '';
    _searchController.clear();
    if (widget.browseProvider == null) {
      _applyFilters();
      _notifyContextChanged();
      return;
    }
    await _requestBrowse(category: category, query: '');
  }

  Future<void> _selectSource(Map<String, dynamic> source) async {
    final id = source['id'] as String?;
    if (id == null || id.isEmpty) return;
    _sourceId = id;
    _sourceName = (source['name'] as String?) ?? 'IPTV';
    _selectedCategory = null;
    _favoritesOnly = source['isFavorites'] == true;
    // The parked category belongs to the source being left. Carrying it over
    // would make a later search-clear apply the old source's category as a
    // filter on this one, which can match nothing at all.
    _allCategorySearch = false;
    _categoryBeforeSearch = null;
    _submittedQuery = '';
    _searchController.clear();
    await _requestBrowse(sourceId: id, category: null, query: '');
  }

  Future<void> _requestBrowse({
    String? sourceId,
    String? category,
    required String query,
  }) async {
    final provider = widget.browseProvider;
    if (provider == null) {
      _applyFilters();
      return;
    }
    final ticket = ++_browseTicket;
    setState(() {
      _browseLoading = true;
      _browseError = null;
    });
    try {
      final result = await provider({
        'action': 'browse',
        'sourceId': sourceId ?? _sourceId,
        'contentType': _contentType,
        'category': category ?? _selectedCategory,
        'query': query,
      });
      if (!mounted || ticket != _browseTicket) return;
      if (result == null) {
        setState(() {
          _browseLoading = false;
          _browseError = 'Unable to load channels';
        });
        return;
      }
      final rawChannels = result['channels'];
      final nextChannels = rawChannels is List
          ? rawChannels
                .whereType<Map>()
                .map((raw) => _channelFromMap(Map<String, dynamic>.from(raw)))
                .toList()
          : <IptvChannel>[];
      final rawCategories = result['categories'];
      setState(() {
        _channels = nextChannels;
        _filteredChannels = List<IptvChannel>.from(nextChannels);
        _sourceId = result['sourceId'] as String? ?? _sourceId;
        _sourceName = result['sourceName'] as String? ?? _sourceName;
        _contentType = result['contentType'] as String? ?? _contentType;
        if (rawCategories is List) {
          _categories = rawCategories.whereType<String>().toList();
        }
        if (result.containsKey('selectedCategory')) {
          _selectedCategory = result['selectedCategory'] as String?;
        }
        _focusedIndex = 0;
        _scheduleChannel = nextChannels.isEmpty ? null : nextChannels.first;
        _browseLoading = false;
      });
      _notifyContextChanged();
    } catch (error) {
      if (!mounted || ticket != _browseTicket) return;
      setState(() {
        _browseLoading = false;
        _browseError = 'Unable to load channels';
      });
    }
  }

  void _notifyContextChanged() {
    widget.onContextChanged?.call(
      IptvGuideContext(
        categories: _categories,
        sourceId: _sourceId,
        sourceName: _sourceName,
        selectedCategory: _selectedCategory,
        contentType: _contentType,
      ),
    );
  }

  static IptvChannel _channelFromMap(Map<String, dynamic> raw) {
    final headers = <String, String>{};
    final rawHeaders = raw['httpHeaders'];
    if (rawHeaders is Map) {
      rawHeaders.forEach((key, value) {
        if (key is String && value != null) headers[key] = value.toString();
      });
    }
    final attributes = <String, String>{};
    final rawAttributes = raw['attributes'];
    if (rawAttributes is Map) {
      rawAttributes.forEach((key, value) {
        if (key is String && value != null) attributes[key] = value.toString();
      });
    }
    final sourceId = raw['sourceId'] as String?;
    final seriesId = raw['seriesId'] as String?;
    if (sourceId?.isNotEmpty == true) {
      attributes['source_playlist_id'] = sourceId!;
    }
    if (seriesId?.isNotEmpty == true) attributes['series_id'] = seriesId!;
    if (raw['seriesName'] != null) {
      attributes['series_name'] = raw['seriesName'].toString();
    }
    if (raw['season'] != null) attributes['season'] = raw['season'].toString();
    if (raw['episode'] != null) {
      attributes['episode'] = raw['episode'].toString();
    }
    if (raw['hasNextEpisode'] != null) {
      attributes['has_next_episode'] = raw['hasNextEpisode'].toString();
    }
    return IptvChannel(
      channelNumber: (raw['channelNumber'] as num?)?.toInt(),
      name: raw['name'] as String? ?? 'Unknown channel',
      url: raw['url'] as String? ?? '',
      logoUrl: raw['logoUrl'] as String?,
      group: raw['group'] as String?,
      duration: (raw['duration'] as num?)?.toInt(),
      contentType: raw['contentType'] as String?,
      attributes: attributes,
      httpHeaders: headers,
    );
  }

  // ─── Scrolling ───────────────────────────────────────────────────────

  void _scrollToFocused() {
    if (_filteredChannels.isEmpty || !_scrollController.hasClients) return;
    const h = 72.0;
    final target = _focusedIndex * h;
    final vp = _scrollController.position.viewportDimension;
    final cur = _scrollController.offset;
    if (target < cur || target > cur + vp - h) {
      _scrollController.animateTo(
        (target - vp / 2 + h / 2).clamp(
          0.0,
          _scrollController.position.maxScrollExtent,
        ),
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
      );
    }
  }

  // ─── Keyboard / DPAD ────────────────────────────────────────────────

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return;

    if (event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.goBack) {
      if (_compactPane == _CompactPane.schedule) {
        setState(() => _compactPane = _CompactPane.channels);
      } else {
        _handleClose();
      }
      return;
    }

    switch (_focusZone) {
      case _FocusZone.search:
        _handleSearchKeys(event);
        break;
      case _FocusZone.channels:
        _handleChannelKeys(event);
        break;
    }
  }

  void _handleSearchKeys(KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _searchFocusNode.unfocus();
      setState(() => _focusZone = _FocusZone.channels);
    }
  }

  void _handleChannelKeys(KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (_focusedIndex > 0) {
        setState(() {
          _focusedIndex--;
          _scheduleChannel = _filteredChannels[_focusedIndex];
        });
        _scrollToFocused();
      } else {
        _searchFocusNode.requestFocus();
        setState(() => _focusZone = _FocusZone.search);
      }
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_focusedIndex < _filteredChannels.length - 1) {
        setState(() {
          _focusedIndex++;
          _scheduleChannel = _filteredChannels[_focusedIndex];
        });
        _scrollToFocused();
      }
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (_filteredChannels.isNotEmpty) {
        setState(() {
          _scheduleChannel = _filteredChannels[_focusedIndex];
          _compactPane = _CompactPane.schedule;
        });
      }
    } else if (isActivateKey(event.logicalKey)) {
      if (_filteredChannels.isNotEmpty) {
        final ch = _filteredChannels[_focusedIndex];
        final oi = _channels.indexWhere(
          (c) => c.url == ch.url && c.name == ch.name,
        );
        if (oi >= 0) unawaited(widget.onChannelSelected(_channels, oi));
      }
    }
  }

  int _getOriginalIndex(IptvChannel channel) {
    return _channels.indexWhere(
      (c) => c.url == channel.url && c.name == channel.name,
    );
  }

  // ─── Build ──────────────────────────────────────────────────────────

  /// TV: skip the frosted-glass BackdropFilter. The panel fill is 97% opaque,
  /// so the blur is barely visible — but its saveLayer re-blurs the live video
  /// underneath on every frame, which weak TV GPUs can't afford.
  Widget _frost(Widget child) {
    if (PlatformUtil.isAndroidTvCached) return child;
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              math.min(constraints.maxWidth, constraints.maxHeight) < 600 ||
              constraints.maxWidth < 720;
          final wide =
              constraints.maxWidth >= 1050 && constraints.maxHeight >= 560;
          final width = compact
              ? constraints.maxWidth
              : math.min(
                  constraints.maxWidth * (wide ? 0.82 : 0.72),
                  wide ? 1120.0 : 760.0,
                );
          final height = compact
              ? math.min(constraints.maxHeight * 0.94, 760.0)
              : constraints.maxHeight;
          final radius = compact
              ? const BorderRadius.vertical(top: Radius.circular(24))
              : const BorderRadius.only(
                  topLeft: Radius.circular(26),
                  bottomLeft: Radius.circular(26),
                );

          return Stack(
            children: [
              GestureDetector(
                onTap: _handleClose,
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: Container(color: Colors.black54),
                ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                width: width,
                height: height,
                child: SlideTransition(
                  position: _slideAnim,
                  child: ClipRRect(
                    borderRadius: radius,
                    child: _frost(
                      Container(
                        key: ValueKey(
                          wide ? 'iptv-guide-wide' : 'iptv-guide-compact',
                        ),
                        decoration: BoxDecoration(
                          color: _surfaceDark.withValues(alpha: 0.98),
                          borderRadius: radius,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.07),
                          ),
                        ),
                        child: _buildResponsivePanel(
                          compact: compact,
                          wide: wide,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildResponsivePanel({required bool compact, required bool wide}) {
    if (wide) {
      return Column(
        children: [
          _buildHeader(compact: false),
          Expanded(
            child: Row(
              children: [
                SizedBox(width: 430, child: _buildBrowserPane(compact: false)),
                VerticalDivider(
                  width: 1,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
                Expanded(child: _buildSchedulePane(compact: false)),
              ],
            ),
          ),
          _buildKeyboardHints(),
        ],
      );
    }

    return Column(
      children: [
        if (compact)
          Center(
            child: Container(
              width: 38,
              height: 4,
              margin: const EdgeInsets.only(top: 9),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        _buildHeader(compact: compact),
        Expanded(
          child: _compactPane == _CompactPane.channels
              ? _buildBrowserPane(compact: compact)
              : _buildSchedulePane(compact: true),
        ),
      ],
    );
  }

  Widget _buildBrowserPane({required bool compact}) {
    return Column(
      children: [
        _buildNowPlayingCard(compact: compact),
        _buildSearchBar(),
        _buildFilterBar(),
        if (_browseLoading)
          const LinearProgressIndicator(
            minHeight: 2,
            color: _accent,
            backgroundColor: Colors.transparent,
          ),
        if (_browseError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Text(
              _browseError!,
              style: const TextStyle(color: Color(0xFFFF8A8A), fontSize: 11),
            ),
          ),
        Expanded(child: _buildChannelList(compact: compact)),
      ],
    );
  }

  // ─── Header ─────────────────────────────────────────────────────────

  Widget _buildHeader({required bool compact}) {
    return Container(
      padding: EdgeInsets.fromLTRB(20, compact ? 10 : 16, 14, 10),
      child: Row(
        children: [
          Container(
            width: compact ? 34 : 40,
            height: compact ? 34 : 40,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_accent, _accentAlt],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.live_tv_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _compactPane == _CompactPane.schedule && compact
                      ? 'Programme Guide'
                      : 'Live TV Guide',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: compact ? 17 : 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _compactPane == _CompactPane.schedule && compact
                      ? (_scheduleChannel?.name ?? 'Select a channel')
                      // Typing does not search — submitting does. Without
                      // saying so, a typed query that changes nothing on
                      // screen reads as a search that found nothing. Native
                      // puts the same prompt in the same place.
                      : (widget.browseProvider != null &&
                            _searchController.text.trim().isNotEmpty &&
                            _searchController.text.trim() != _submittedQuery)
                      ? 'Press enter to search all channels'
                      : '${_filteredChannels.length} of ${_channels.length} channels',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          if (compact && _compactPane == _CompactPane.schedule)
            IconButton(
              tooltip: 'Back to channels',
              onPressed: () =>
                  setState(() => _compactPane = _CompactPane.channels),
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white70),
            ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: _handleClose,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                ),
                child: Icon(
                  Icons.close_rounded,
                  color: Colors.white.withValues(alpha: 0.5),
                  size: 18,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNowPlayingCard({required bool compact}) {
    if (widget.currentIndex < 0 ||
        widget.currentIndex >= widget.channels.length) {
      return const SizedBox.shrink();
    }
    final channel = widget.channels[widget.currentIndex];
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, compact ? 8 : 10),
      child: Material(
        color: _accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() {
            _scheduleChannel = channel;
            _compactPane = _CompactPane.schedule;
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                _GuideLogo(channel: channel, size: compact ? 38 : 42),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        channel.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      _TileSubLine(channel: channel, isFocused: true),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const _LivePill(label: 'NOW'),
                if (compact) ...[
                  const SizedBox(width: 6),
                  Icon(
                    Icons.calendar_month_rounded,
                    color: _accent.withValues(alpha: 0.8),
                    size: 20,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Search ─────────────────────────────────────────────────────────

  Widget _buildSearchBar() {
    final hasFocus = _focusZone == _FocusZone.search;
    final hasQuery = _searchController.text.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: hasFocus
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.white.withValues(alpha: 0.04),
          border: Border.all(
            color: hasFocus
                ? _accent.withValues(alpha: 0.4)
                : Colors.transparent,
            width: 1.5,
          ),
          boxShadow: hasFocus
              ? [
                  BoxShadow(
                    color: _accent.withValues(alpha: 0.08),
                    blurRadius: 16,
                  ),
                ]
              : [],
        ),
        child: TvTextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w400,
          ),
          decoration: InputDecoration(
            hintText: 'Search channels or categories...',
            hintStyle: TextStyle(
              color: Colors.white.withValues(alpha: 0.25),
              fontSize: 13,
              fontWeight: FontWeight.w400,
            ),
            prefixIcon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                hasQuery ? Icons.filter_list_rounded : Icons.search_rounded,
                key: ValueKey(hasQuery),
                color: hasFocus
                    ? _accent.withValues(alpha: 0.7)
                    : Colors.white.withValues(alpha: 0.3),
                size: 20,
              ),
            ),
            suffixIcon: SizedBox(
              width: hasQuery ? 96 : 48,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (hasQuery)
                    IconButton(
                      tooltip: 'Clear search',
                      icon: Icon(
                        Icons.clear_rounded,
                        color: Colors.white.withValues(alpha: 0.4),
                        size: 18,
                      ),
                      onPressed: () => unawaited(_clearSearch()),
                    ),
                  IconButton(
                    tooltip: 'Search full source',
                    icon: Icon(
                      Icons.arrow_forward_rounded,
                      color: _accent.withValues(alpha: 0.75),
                      size: 19,
                    ),
                    onPressed: _submitSearch,
                  ),
                ],
              ),
            ),
            suffixIconConstraints: BoxConstraints(
              minWidth: hasQuery ? 96 : 48,
              maxWidth: hasQuery ? 96 : 48,
            ),
            filled: false,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 13,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
          onChanged: (_) {
            // Rebuilds for the header prompt and the clear button. With a
            // provider the list is untouched until submit; without one this
            // is the only search there is.
            _applyFilters();
          },
          onSubmitted: (_) => unawaited(_submitSearch()),
          textInputAction: TextInputAction.search,
        ),
      ),
    );
  }

  /// Pick a category from a searchable list.
  ///
  /// Categories used to be laid out as chips in a horizontally scrolling row,
  /// which a mouse cannot scroll — on desktop every chip past the fold, plus
  /// the "More" menu and the Saved filter behind them, was simply
  /// unreachable. A source can carry hundreds of categories, so a picker with
  /// its own search is the only shape that fits them all on any input.
  Future<void> _openCategoryPicker() async {
    final choice = await showDialog<_CategoryChoice>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (_) => _CategoryPickerDialog(
        categories: _categories,
        selected: _favoritesOnly ? null : _selectedCategory,
      ),
    );
    if (choice == null || !mounted) return;
    await _selectCategory(choice.value);
  }

  Widget _buildFilterBar() {
    final categoryLabel = _favoritesOnly
        ? 'All'
        : (_selectedCategory ?? 'All');
    // Three fixed controls, so the row cannot overflow and nothing depends on
    // being able to scroll it.
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 7),
      child: SizedBox(
        height: 36,
        child: Row(
          children: [
            Flexible(
              child: _GuideMenuButton(
                icon: Icons.dns_rounded,
                label: _sourceName,
                options: [
                  for (final source in _sources)
                    _GuideMenuOption(
                      value: source,
                      label: source['name'] as String? ?? 'IPTV',
                    ),
                ],
                onSelected: (value) => unawaited(_selectSource(value)),
              ),
            ),
            const SizedBox(width: 7),
            Flexible(
              child: _GuideDropdownButton(
                icon: Icons.category_rounded,
                label: categoryLabel,
                // A picked category is the strongest filter on screen; show it
                // as selected the way the old chip did.
                selected: !_favoritesOnly && _selectedCategory != null,
                onTap: () => unawaited(_openCategoryPicker()),
              ),
            ),
            const SizedBox(width: 7),
            _FilterChip(
              icon: Icons.favorite_rounded,
              label: 'Saved',
              selected: _favoritesOnly,
              onTap: () {
                setState(() {
                  _favoritesOnly = !_favoritesOnly;
                  if (_favoritesOnly) _selectedCategory = null;
                });
                _applyFilters();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSchedulePane({required bool compact}) {
    final channel = _scheduleChannel;
    if (channel == null) {
      return Center(
        child: Text(
          'Select a channel to view its schedule',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.45)),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(compact ? 18 : 24, 12, 18, 12),
          child: Row(
            children: [
              _GuideLogo(channel: channel, size: 46),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      channel.name,
                      maxLines: compact ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        if (channel.group?.isNotEmpty == true) channel.group!,
                        if (channel.channelNumber != null)
                          'Channel ${channel.channelNumber}',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.42),
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: _favoriteUrls.contains(channel.url)
                    ? 'Remove favorite'
                    : 'Add favorite',
                onPressed: () => unawaited(_toggleFavorite(channel)),
                icon: Icon(
                  _favoriteUrls.contains(channel.url)
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: _favoriteUrls.contains(channel.url)
                      ? const Color(0xFFF43F5E)
                      : Colors.white54,
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),
        Expanded(
          child: EpgScheduleList(
            key: ValueKey('schedule-${channel.url}'),
            channel: channel,
            isTelevision: PlatformUtil.isAndroidTvCached,
            onPlayProgramme: widget.onPlayProgramme == null
                ? null
                : (programme) {
                    unawaited(widget.onPlayProgramme!(channel, programme));
                  },
            // isSchedulableUrl, not engineRecordableUrl: with nobody watching
            // at alarm time there is no player probe, so only URLs KNOWN to be
            // progressive TS may be scheduled (an extensionless HLS URL would
            // record playlist text and call it saved).
            onRecordProgramme: !_recordSchedulingAvailable ||
                    !LiveRecordingService.isSchedulableUrl(channel.url)
                ? null
                : (programme) {
                    unawaited(_confirmScheduleRecording(channel, programme));
                  },
          ),
        ),
      ],
    );
  }

  /// Confirm-and-schedule for a now-airing (records the rest) or future
  /// programme. Self-contained: the sheet holds the channel context (url,
  /// headers, name), so the host player never needs to know scheduling
  /// exists.
  Future<void> _confirmScheduleRecording(
    IptvChannel channel,
    EpgProgramme programme,
  ) async {
    if (!LiveRecordingService.isSchedulableUrl(channel.url)) return;
    final recordUrl = LiveRecordingService.engineRecordableUrl(channel.url);
    if (recordUrl == null || !mounted) return;
    if (Platform.isAndroid &&
        !await LiveRecordingService.ensureEngineReady()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Storage access is needed to save recordings'),
        ),
      );
      return;
    }
    if (!mounted) return;
    if (!await ensureRecordingCapacity(
      context,
      startMs: programme.start.millisecondsSinceEpoch,
      endMs: programme.stop.millisecondsSinceEpoch,
      candidateUrl: recordUrl,
    )) {
      return;
    }
    if (!mounted) return;
    String clock(DateTime t) => MaterialLocalizations.of(context)
        .formatTimeOfDay(TimeOfDay.fromDateTime(t));
    final airsNow = !programme.start.isAfter(DateTime.now()) &&
        programme.stop.isAfter(DateTime.now());
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF14141D),
        title: const Text(
          'Record programme',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        content: Text(
          '${programme.title}\n'
          '${channel.name} · ${clock(programme.start)} – ${clock(programme.stop)}'
          '${airsNow ? '\n\nAlready airing — records the rest, '
              'from now until it ends.' : ''}',
          style: const TextStyle(color: Colors.white70, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Record'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final result = DesktopScheduleService.instance.isSupported
        ? await DesktopScheduleService.instance.add(
            url: recordUrl,
            channelName: channel.name,
            programmeTitle: programme.title,
            startMs: programme.start.millisecondsSinceEpoch,
            endMs: programme.stop.millisecondsSinceEpoch,
            headers: channel.playbackHeaders,
          )
        : await LiveRecordingService.schedule(
            url: recordUrl,
            channelName: channel.name,
            programmeTitle: programme.title,
            startMs: programme.start.millisecondsSinceEpoch,
            endMs: programme.stop.millisecondsSinceEpoch,
            headers: channel.playbackHeaders,
          );
    if (!mounted) return;
    if (result.errorCode == 'exact_alarms_required') {
      // Without the grant an inexact alarm couldn't legally start the
      // recording service from the background, so scheduling is refused
      // outright — offer the grant right here.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Allow "Alarms & reminders" for Debrify to schedule recordings',
          ),
          action: SnackBarAction(
            label: 'Settings',
            onPressed: () =>
                unawaited(LiveRecordingService.openExactAlarmSettings()),
          ),
        ),
      );
      return;
    }
    final message = result.ok
        ? (airsNow
              ? 'Recording starts in a few seconds'
              : 'Recording scheduled')
        : switch (result.errorCode) {
            'duplicate' => 'Already scheduled',
            'overlap' => 'Overlaps another scheduled recording',
            'bad_time' => 'This programme is already over',
            _ => "Couldn't schedule recording",
          };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildKeyboardHints() {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Row(
        children: [
          _KeyHint(keyLabel: 'Enter', action: 'Play'),
          const SizedBox(width: 20),
          _KeyHint(keyLabel: '→', action: 'Schedule'),
          const Spacer(),
          _KeyHint(keyLabel: 'Esc', action: 'Close'),
        ],
      ),
    );
  }

  // ─── Channel List ───────────────────────────────────────────────────

  Widget _buildChannelList({required bool compact}) {
    if (_filteredChannels.isEmpty) {
      // The list can only be empty here because a submitted search (or a
      // category) came back with nothing. If the user has since typed a NEW
      // query, saying "no channels found" would again describe a search that
      // was never run — point at the submit instead.
      final pending =
          widget.browseProvider != null &&
          _searchController.text.trim().isNotEmpty &&
          _searchController.text.trim() != _submittedQuery;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                shape: BoxShape.circle,
              ),
              child: Icon(
                pending
                    ? Icons.search_rounded
                    : Icons.satellite_alt_rounded,
                color: Colors.white.withValues(alpha: 0.1),
                size: 32,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              pending ? 'Search all channels' : 'No channels found',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              pending
                  ? 'Nothing loaded matches "${_searchController.text.trim()}" —'
                        ' press enter to search the whole source'
                  : 'Try a different search term',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.2),
                fontSize: 12,
              ),
            ),
            if (pending) ...[
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () => unawaited(_submitSearch()),
                icon: const Icon(Icons.search_rounded, size: 17),
                label: const Text('Search all channels'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF7C5CFF),
                  foregroundColor: Colors.white,
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    final inChannelZone = _focusZone == _FocusZone.channels;

    final playing =
        (widget.currentIndex >= 0 &&
            widget.currentIndex < widget.channels.length)
        ? widget.channels[widget.currentIndex]
        : null;
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      itemCount: _filteredChannels.length,
      itemExtent: compact ? 78 : 72,
      itemBuilder: (context, index) {
        final channel = _filteredChannels[index];
        final origIdx = _getOriginalIndex(channel);
        final isCurrent =
            playing != null &&
            channel.url == playing.url &&
            channel.name == playing.name;
        final isFocused = inChannelZone && index == _focusedIndex;

        return _ChannelTile(
          channel: channel,
          isFocused: isFocused,
          isCurrent: isCurrent,
          channelNumber: channel.channelNumber ?? (origIdx + 1),
          pulseAnim: _pulseAnim,
          isFavorited: _favoriteUrls.contains(channel.url),
          onTap: () {
            if (origIdx >= 0) {
              unawaited(widget.onChannelSelected(_channels, origIdx));
            }
          },
          onFavorite: () => unawaited(_toggleFavorite(channel)),
          onSchedule: () => setState(() {
            _scheduleChannel = channel;
            _compactPane = _CompactPane.schedule;
          }),
        );
      },
    );
  }
}

class _GuideMenuOption {
  final Map<String, dynamic> value;
  final String label;
  const _GuideMenuOption({required this.value, required this.label});
}

class _GuideMenuButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final List<_GuideMenuOption> options;
  final ValueChanged<Map<String, dynamic>> onSelected;

  const _GuideMenuButton({
    required this.icon,
    required this.label,
    required this.options,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<Map<String, dynamic>>(
      enabled: options.isNotEmpty,
      color: const Color(0xFF1A1A24),
      onSelected: onSelected,
      itemBuilder: (_) => [
        for (final option in options)
          PopupMenuItem(value: option.value, child: Text(option.label)),
      ],
      child: Container(
        constraints: const BoxConstraints(minWidth: 92, maxWidth: 170),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white54, size: 15),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (options.isNotEmpty) ...[
              const SizedBox(width: 5),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Colors.white38,
                size: 16,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Rebuild an [IptvChannel] from a browse-provider channel map.
///
/// Exposed because the player consumes the same payload when it re-anchors its
/// channel ring to a category. Both sides must parse it identically — a
/// channel rebuilt differently in the two places stops matching itself, and
/// the playing row can no longer be found in its own list.
IptvChannel iptvChannelFromBrowsePayload(Map<String, dynamic> raw) =>
    _IptvChannelSheetState._channelFromMap(raw);

/// A dropdown-looking button that opens a picker rather than a popup menu —
/// for lists too long to sit in a [PopupMenuButton].
class _GuideDropdownButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _GuideDropdownButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? const Color(0xFF7C5CFF)
          : Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          constraints: const BoxConstraints(minWidth: 92, maxWidth: 190),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? Colors.transparent
                  : Colors.white.withValues(alpha: 0.06),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: selected ? Colors.white : Colors.white54,
                size: 15,
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? Colors.white : Colors.white70,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 5),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                color: selected ? Colors.white70 : Colors.white38,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The picked category. Wrapped so that "All" (a null category) is
/// distinguishable from dismissing the dialog without choosing.
class _CategoryChoice {
  final String? value;
  const _CategoryChoice(this.value);
}

/// Searchable category list. Works on every input the guide runs under:
/// pointer, DPAD (the rows are focusable and the field is a [TvTextField],
/// so TV gets the in-app keyboard), and touch.
class _CategoryPickerDialog extends StatefulWidget {
  final List<String> categories;
  final String? selected;

  const _CategoryPickerDialog({
    required this.categories,
    required this.selected,
  });

  @override
  State<_CategoryPickerDialog> createState() => _CategoryPickerDialogState();
}

class _CategoryPickerDialogState extends State<_CategoryPickerDialog> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// "All" always survives filtering when the query is empty, so the list is
  /// never headed by a category when the user has not searched for one.
  List<String?> get _matches {
    final query = _query.trim().toLowerCase();
    final all = <String?>[null, ...widget.categories];
    if (query.isEmpty) return all;
    return [
      for (final category in all)
        if ((category ?? 'All').toLowerCase().contains(query)) category,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final matches = _matches;

    return Dialog(
      backgroundColor: const Color(0xFF14141C),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 460,
          maxHeight: size.height * 0.72,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              child: Row(
                children: [
                  const Icon(
                    Icons.category_rounded,
                    color: Colors.white54,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Category',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '${widget.categories.length}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.35),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                // Deliberately not autofocused: on TV that would throw the
                // in-app keyboard over the list before the user has looked
                // at it.
                child: TvTextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search categories…',
                    hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.25),
                      fontSize: 13,
                    ),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      color: Colors.white.withValues(alpha: 0.3),
                      size: 19,
                    ),
                    filled: false,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
            ),
            Flexible(
              child: matches.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                      child: Text(
                        'No category matches "${_query.trim()}"',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 13,
                        ),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.only(bottom: 12),
                      itemCount: matches.length,
                      itemBuilder: (_, index) {
                        final category = matches[index];
                        final isSelected = category == widget.selected;
                        return _CategoryPickerRow(
                          label: category ?? 'All',
                          selected: isSelected,
                          onTap: () => Navigator.of(
                            context,
                          ).pop(_CategoryChoice(category)),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryPickerRow extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryPickerRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          color: selected
              ? const Color(0xFF7C5CFF).withValues(alpha: 0.16)
              : Colors.transparent,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? Colors.white : Colors.white70,
                    fontSize: 13.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              if (selected)
                const Icon(
                  Icons.check_rounded,
                  color: Color(0xFF7C5CFF),
                  size: 18,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? const Color(0xFF7C5CFF)
          : Colors.white.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 14,
                  color: selected ? Colors.white : Colors.white54,
                ),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white60,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KeyHint extends StatelessWidget {
  final String keyLabel;
  final String action;
  const _KeyHint({required this.keyLabel, required this.action});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(
            keyLabel,
            style: const TextStyle(color: Colors.white70, fontSize: 9),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          action,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

class _GuideLogo extends StatelessWidget {
  final IptvChannel channel;
  final double size;
  const _GuideLogo({required this.channel, required this.size});

  @override
  Widget build(BuildContext context) {
    final hasLogo = channel.logoUrl?.isNotEmpty == true;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      clipBehavior: Clip.antiAlias,
      child: hasLogo
          ? CachedNetworkImage(
              imageUrl: channel.logoUrl!,
              memCacheWidth: 120,
              fit: BoxFit.contain,
              errorWidget: (_, __, ___) => _letter(),
            )
          : _letter(),
    );
  }

  Widget _letter() {
    return Center(
      child: Text(
        channel.name.isEmpty ? '?' : channel.name[0].toUpperCase(),
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _LivePill extends StatelessWidget {
  final String label;
  const _LivePill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF42E8B4),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF07110E),
          fontSize: 8,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Channel Tile
// ═══════════════════════════════════════════════════════════════════════════

class _TileAction extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _TileAction({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 44),
      padding: EdgeInsets.zero,
      icon: Icon(icon, color: color, size: 18),
    );
  }
}

class _ChannelTile extends StatelessWidget {
  final IptvChannel channel;
  final bool isFocused;
  final bool isCurrent;
  final int channelNumber;
  final Animation<double> pulseAnim;
  final bool isFavorited;
  final VoidCallback onTap;
  final VoidCallback onFavorite;
  final VoidCallback onSchedule;

  static const _accent = Color(0xFF00E5FF);
  static const _accentAlt = Color(0xFF00B8D4);
  static const _liveDot = Color(0xFFFF3D71);

  static Color _avatarColor(String name) {
    const hues = [0.0, 15.0, 160.0, 190.0, 210.0, 240.0, 270.0, 300.0, 330.0];
    final index = name.hashCode.abs() % hues.length;
    return HSLColor.fromAHSL(1.0, hues[index], 0.6, 0.6).toColor();
  }

  const _ChannelTile({
    required this.channel,
    required this.isFocused,
    required this.isCurrent,
    required this.channelNumber,
    required this.pulseAnim,
    required this.isFavorited,
    required this.onTap,
    required this.onFavorite,
    required this.onSchedule,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: ValueKey('iptv-channel-${channel.url}'),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          gradient: isFocused
              ? LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Colors.white.withValues(alpha: 0.12),
                    Colors.white.withValues(alpha: 0.06),
                  ],
                )
              : isCurrent
              ? LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    _accent.withValues(alpha: 0.08),
                    _accent.withValues(alpha: 0.02),
                  ],
                )
              : null,
          color: (!isFocused && !isCurrent) ? Colors.transparent : null,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isFocused
                ? _accent.withValues(alpha: 0.5)
                : isCurrent
                ? _accent.withValues(alpha: 0.12)
                : Colors.transparent,
            width: isFocused ? 1.5 : 1,
          ),
          boxShadow: isFocused
              ? [
                  BoxShadow(
                    color: _accent.withValues(alpha: 0.1),
                    blurRadius: 16,
                    spreadRadius: 2,
                  ),
                ]
              : [],
        ),
        child: Row(
          children: [
            // Channel number
            SizedBox(
              width: 30,
              child: Text(
                channelNumber.toString().padLeft(2, ' '),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isCurrent
                      ? _accent.withValues(alpha: 0.8)
                      : isFocused
                      ? Colors.white.withValues(alpha: 0.5)
                      : Colors.white.withValues(alpha: 0.18),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: 10),
            // Logo
            _buildLogo(),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    channel.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isCurrent
                          ? _accent
                          : isFocused
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.85),
                      fontSize: 13.5,
                      fontWeight: isFocused || isCurrent
                          ? FontWeight.w600
                          : FontWeight.w400,
                      letterSpacing: -0.2,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: _TileSubLine(channel: channel, isFocused: isFocused),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _TileAction(
              tooltip: isFavorited ? 'Remove favorite' : 'Add favorite',
              icon: isFavorited
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              color: isFavorited ? const Color(0xFFF43F5E) : Colors.white38,
              onTap: onFavorite,
            ),
            _TileAction(
              tooltip: 'Programme guide',
              icon: Icons.calendar_month_rounded,
              color: _accent.withValues(alpha: 0.75),
              onTap: onSchedule,
            ),
            if (isCurrent)
              _buildNowBadge()
            else if (channel.isLive)
              _buildLiveBadge(),
          ],
        ),
      ),
    );
  }

  Widget _buildLogo() {
    final hasLogo = channel.logoUrl != null && channel.logoUrl!.isNotEmpty;

    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: Colors.white.withValues(alpha: 0.05),
        border: Border.all(
          color: isCurrent
              ? _accent.withValues(alpha: 0.15)
              : isFocused
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.white.withValues(alpha: 0.03),
        ),
        boxShadow: isCurrent
            ? [BoxShadow(color: _accent.withValues(alpha: 0.08), blurRadius: 8)]
            : [],
      ),
      clipBehavior: Clip.antiAlias,
      child: hasLogo
          ? CachedNetworkImage(
              imageUrl: channel.logoUrl!,
              memCacheWidth: 120,
              fit: BoxFit.contain,
              placeholder: (_, __) => _buildLetterAvatar(),
              errorWidget: (_, __, ___) => _buildLetterAvatar(),
            )
          : _buildLetterAvatar(),
    );
  }

  Widget _buildLetterAvatar() {
    final letter = channel.name.isNotEmpty
        ? channel.name[0].toUpperCase()
        : '?';
    final color = _avatarColor(channel.name);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withValues(alpha: 0.25), color.withValues(alpha: 0.1)],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
          color: color.withValues(alpha: 0.85),
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildLiveBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: _liveDot.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: _liveDot.withValues(alpha: 0.8),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: _liveDot.withValues(alpha: 0.4),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'LIVE',
            style: TextStyle(
              color: _liveDot.withValues(alpha: 0.7),
              fontSize: 8,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNowBadge() {
    return AnimatedBuilder(
      animation: pulseAnim,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                _accent.withValues(alpha: 0.8 + pulseAnim.value * 0.2),
                _accentAlt.withValues(alpha: 0.6 + pulseAnim.value * 0.2),
              ],
            ),
            borderRadius: BorderRadius.circular(6),
            boxShadow: [
              BoxShadow(
                color: _accent.withValues(alpha: 0.2 + pulseAnim.value * 0.1),
                blurRadius: 10,
              ),
            ],
          ),
          child: const Text(
            'NOW',
            style: TextStyle(
              color: Colors.white,
              fontSize: 8,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
        );
      },
    );
  }
}

/// The tile's sub-line: the airing programme ("Now: …") when the channel has
/// guide data, the category group otherwise. Each tile fetches for itself —
/// ListView.builder only builds visible tiles, so this is naturally
/// viewport-scoped, and the small delay keeps a fast DPAD scroll through a
/// big list from firing a request per passing row (the EPG service coalesces
/// and caches the rest).
class _TileSubLine extends StatefulWidget {
  final IptvChannel channel;
  final bool isFocused;
  const _TileSubLine({required this.channel, required this.isFocused});

  @override
  State<_TileSubLine> createState() => _TileSubLineState();
}

class _TileSubLineState extends State<_TileSubLine> {
  EpgProgramme? _now;
  Timer? _fetchDelay;

  @override
  void initState() {
    super.initState();
    // XMLTV guides can land after the sheet's tiles were built (the first
    // download takes minutes) — same race the page's rail card handles.
    IptvEpgService.instance.contextVersion.addListener(_onEpgContextChanged);
    _sync();
  }

  void _onEpgContextChanged() {
    if (!mounted) return;
    _fetchDelay?.cancel();
    setState(_sync);
  }

  @override
  void didUpdateWidget(_TileSubLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The list recycles this element for a different channel (scrolling,
    // filtering) — never let the old channel's programme linger. A build
    // follows didUpdateWidget, so plain assignment inside _sync suffices.
    if (oldWidget.channel.url != widget.channel.url) {
      _fetchDelay?.cancel();
      _sync();
    }
  }

  /// Assigns [_now] from cache (or schedules the fetch). Callers that are
  /// not already followed by a build must wrap this in setState.
  void _sync() {
    _now = null;
    if (!IptvEpgService.isEpgCapable(widget.channel)) return;
    final cached = IptvEpgService.instance.peekNowNext(widget.channel.url);
    if (cached != null) {
      _now = cached.now;
      return;
    }
    final url = widget.channel.url;
    _fetchDelay = Timer(const Duration(milliseconds: 350), () async {
      final result = await IptvEpgService.instance.nowNext(url);
      if (mounted && url == widget.channel.url) {
        setState(() => _now = result.now);
      }
    });
  }

  @override
  void dispose() {
    IptvEpgService.instance.contextVersion.removeListener(_onEpgContextChanged);
    _fetchDelay?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = _now;
    final group = widget.channel.group;
    if (now == null && (group == null || group.isEmpty)) {
      return const SizedBox.shrink();
    }
    return Text(
      now != null ? 'Now:  ${now.title}' : group!,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: now != null
            ? const Color(
                0xFF00E5FF,
              ).withValues(alpha: widget.isFocused ? 0.75 : 0.5)
            : Colors.white.withValues(alpha: widget.isFocused ? 0.4 : 0.22),
        fontSize: 10.5,
        fontWeight: now != null ? FontWeight.w500 : FontWeight.w400,
      ),
    );
  }
}
