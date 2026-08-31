import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import '../../../services/desktop_schedule_service.dart';
import '../../../services/iptv_epg_service.dart';
import '../../../services/live_recording_service.dart';
import '../../../widgets/recording_limit_dialogs.dart';
import '../../../services/storage_service.dart';
import '../../../utils/platform_util.dart';
import '../../../utils/tv_keys.dart';
import '../../../utils/tv_search_focus_handoff.dart';
import '../../../models/iptv_playlist.dart';
import '../../../widgets/iptv/iptv_epg_panel.dart';
import '../../../widgets/iptv/styles/iptv_style.dart';
import '../../../widgets/tv_text_field.dart';
import 'player_guide_style.dart';
import 'spotlight_dialog.dart';

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

  /// The in-player guide look + its tokens, resolved once by the owner.
  /// Classic (null tokens) takes the untouched legacy paint everywhere.
  final PlayerGuideStyle style;
  final IptvStyleTokens? tokens;

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
    this.style = PlayerGuideStyle.classic,
    this.tokens,
  });

  @override
  State<IptvChannelSheet> createState() => IptvChannelSheetState();
}

enum _FocusZone { search, channels, filters }

enum _CompactPane { channels, schedule }

class IptvChannelSheetState extends State<IptvChannelSheet>
    with TickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _keyboardFocusNode = FocusNode();
  final TvSearchFocusHandoff _searchSubmitFocus = TvSearchFocusHandoff();
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

  /// DPAD position in the filter row: 0 source, 1 category, 2 favorites.
  int _filterIndex = 0;

  /// Scope around the schedule pane. Entering the pane hands REAL focus to
  /// its rows (they were always focusable — the guide just never let go),
  /// and the scope keeps directional traversal from escaping into the
  /// search field or header buttons.
  final FocusScopeNode _scheduleScope = FocusScopeNode(
    debugLabel: 'iptv-guide-schedule',
  );
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

  /// Styled-look tokens, or null on the classic path. Every restyled build
  /// site branches on this FIRST and keeps its legacy expression verbatim
  /// in the null branch.
  IptvStyleTokens? get _t =>
      widget.style == PlayerGuideStyle.classic ? null : widget.tokens;

  /// Corner grammar per look: glass keeps the soft legacy radii, edition
  /// squares off to a hairline-ledger 10, console to an instrument 4.
  double get _styledRadius => switch (widget.style) {
    PlayerGuideStyle.glass => 18,
    PlayerGuideStyle.edition => 10,
    PlayerGuideStyle.console => 4,
    PlayerGuideStyle.spotlight => 12,
    PlayerGuideStyle.classic => 14,
  };

  @override
  void initState() {
    super.initState();

    // A television opens this over the player, whose root Focus already holds
    // focus in this scope — so `autofocus: true` on the KeyboardListener never
    // wins and the sheet renders its virtual focus while receiving no keys at
    // all (the DPAD appears dead). Claim focus explicitly once mounted.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _keyboardFocusNode.requestFocus();
    });
    // …and keep it for as long as the sheet is up. The player promises to
    // ignore every key while this overlay is open, so the sheet losing real
    // focus to ANYTHING outside itself (a late instance-ready refocus, a bar
    // raise) leaves the whole guide deaf — the virtual white focus freezes
    // and the DPAD appears dead. The sheet's own legitimate holders (search
    // field, schedule pane, filter pickers) are exempt.
    _keyboardFocusNode.addListener(_onKeyboardFocusChanged);

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
    _keyboardFocusNode.removeListener(_onKeyboardFocusChanged);
    _keyboardFocusNode.dispose();
    _scheduleScope.dispose();
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

  Future<({String id, int revision})?> _recordingResource(
    IptvChannel channel,
  ) async {
    final sourceId = _originSourceId(channel);
    if (sourceId == null) return null;
    // Fresh read first: `_sources` is the payload captured at player launch,
    // and every sources save bumps every source's revision — a schedule
    // seeded from the stale copy would be refused when it fires.
    try {
      final playlists = await StorageService.getIptvPlaylists(
        forSettings: false,
      );
      for (final playlist in playlists) {
        if (playlist.id != sourceId) continue;
        final id = playlist.connectionResourceId;
        final revision = playlist.connectionResourceRevision;
        if (id != null && id.isNotEmpty && revision != null) {
          return (id: id, revision: revision);
        }
      }
    } catch (_) {
      // Storage unavailable mid-session: fall through to the launch payload.
    }
    for (final source in _sources) {
      if (source['id'] != sourceId) continue;
      final id = source['connectionResourceId']?.toString();
      final revision = (source['connectionResourceRevision'] as num?)?.toInt();
      if (id != null && id.isNotEmpty && revision != null) {
        return (id: id, revision: revision);
      }
    }
    return null;
  }

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
      _searchSubmitFocus.cancel();
      await _clearSearch();
      return;
    }
    _searchSubmitFocus.arm(enabled: PlatformUtil.isTelevision);
    _beginAllCategorySearch();
    _submittedQuery = query;
    await _requestBrowse(category: null, query: query);
    if (!mounted || query != _submittedQuery) return;
    if (_browseError != null || _filteredChannels.isEmpty) {
      _searchSubmitFocus.cancel();
      return;
    }
    _searchSubmitFocus.complete(
      field: _searchFocusNode,
      isMounted: () => mounted,
      requestFocus: () {
        if (!mounted) return;
        setState(() => _focusZone = _FocusZone.channels);
        _keyboardFocusNode.requestFocus();
        _scrollToFocused();
      },
      targetHasFocus: () =>
          _keyboardFocusNode.hasFocus && _focusZone == _FocusZone.channels,
    );
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
    if (raw['tvArchive'] != null) {
      attributes['tv_archive'] = raw['tvArchive'].toString();
    }
    if (raw['tvArchiveDuration'] != null) {
      attributes['tv_archive_duration'] = raw['tvArchiveDuration'].toString();
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

  /// True while one of the sheet's own picker dialogs holds focus — the
  /// re-claim below must not fight a route the sheet itself opened.
  bool _pickerOpen = false;

  void _onKeyboardFocusChanged() {
    if (_keyboardFocusNode.hasFocus) return;
    if (_focusHeldElsewhereLegitimately) return;
    // Re-checked post-frame: focus hops through transient states inside one
    // update (e.g. keyboard → schedule row), and only a loss that SETTLED
    // outside the sheet is theft.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _keyboardFocusNode.hasFocus ||
          _focusHeldElsewhereLegitimately) {
        return;
      }
      _keyboardFocusNode.requestFocus();
    });
  }

  bool get _focusHeldElsewhereLegitimately =>
      _pickerOpen || _searchFocusNode.hasFocus || _scheduleScope.hasFocus;

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

  /// The BACK contract, callable by the host.
  ///
  /// On tvOS the Menu press never reaches this widget — it arrives at the
  /// player's PopScope — so without this the host would close the whole guide
  /// from the schedule pane and skip [_handleClose]'s category restoration.
  /// Returns true when it consumed the press.
  bool handleHostBack() {
    if (_compactPane == _CompactPane.schedule) {
      _leaveSchedulePane();
      return true;
    }
    if (_focusZone == _FocusZone.filters) {
      setState(() => _focusZone = _FocusZone.channels);
      return true;
    }
    _handleClose();
    return true;
  }

  /// Walks the schedule pane back to the channel list and takes the DPAD
  /// back from the pane's rows.
  void _leaveSchedulePane() {
    setState(() => _compactPane = _CompactPane.channels);
    _keyboardFocusNode.requestFocus();
  }

  /// EVERY way into the schedule pane goes through here: on TV the pane's
  /// rows must be handed real focus, or a touch/pointer entry would leave
  /// the DPAD stranded outside a pane that now gates its focusability.
  void _enterSchedulePane(IptvChannel channel) {
    setState(() {
      _scheduleChannel = channel;
      _compactPane = _CompactPane.schedule;
    });
    if (!PlatformUtil.isTelevision) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _compactPane != _CompactPane.schedule) return;
      _scheduleScope.traversalDescendants.firstOrNull?.requestFocus();
    });
  }

  /// CONSUMES every key it owns (returns handled) — a KeyboardListener
  /// cannot consume, and unconsumed arrows also run directional focus
  /// traversal, which can move primary focus somewhere invisible and kill
  /// the DPAD (the player-menu failure, measured on the Apple TV).
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final isRepeat = event is KeyRepeatEvent;
    final back =
        key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack;

    // BACK and OK act on the initial press only — a held BACK would
    // otherwise walk schedule->channels AND close on the next repeat.
    // Arrows keep their repeat (that's how a long list is scrolled).
    if (isRepeat && (back || isActivateOrSpaceKey(key))) {
      return KeyEventResult.handled;
    }

    // Schedule pane active: REAL focus lives on the pane's rows, which own
    // OK, and directional traversal moves between them inside the scope.
    // The guide takes only LEFT and BACK — both walk back to the channels.
    if (_compactPane == _CompactPane.schedule) {
      if (back || key == LogicalKeyboardKey.arrowLeft) {
        _leaveSchedulePane();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (back) {
      // Consumed outright, so no TvOverlayBack tail: the press never
      // reaches the player root (a lingering mark would swallow the NEXT
      // deliberate back instead).
      if (_focusZone == _FocusZone.filters) {
        setState(() => _focusZone = _FocusZone.channels);
      } else {
        _handleClose();
      }
      return KeyEventResult.handled;
    }

    switch (_focusZone) {
      case _FocusZone.search:
        return _handleSearchKeys(event);
      case _FocusZone.filters:
        return _handleFilterKeys(event);
      case _FocusZone.channels:
        return _handleChannelKeys(event);
    }
  }

  KeyEventResult _handleSearchKeys(KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _searchFocusNode.unfocus();
      // Reclaim the sheet's key listener: unfocusing clears the scope's
      // focused child, and without this the list paints a focused row but
      // stops receiving DPAD keys entirely.
      _keyboardFocusNode.requestFocus();
      setState(() => _focusZone = _FocusZone.filters);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// The filter row is a real zone now — Source / Category / Favorites were
  /// unreachable by DPAD before this.
  KeyEventResult _handleFilterKeys(KeyEvent event) {
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (_filterIndex > 0) setState(() => _filterIndex--);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      if (_filterIndex < 2) setState(() => _filterIndex++);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() => _focusZone = _FocusZone.channels);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _searchFocusNode.requestFocus();
      setState(() => _focusZone = _FocusZone.search);
      return KeyEventResult.handled;
    }
    if (isActivateKey(key)) {
      switch (_filterIndex) {
        case 0:
          unawaited(_openSourceMenu());
        case 1:
          unawaited(_openCategoryPicker());
        case 2:
          _toggleFavoritesFilter();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _toggleFavoritesFilter() {
    setState(() {
      _favoritesOnly = !_favoritesOnly;
      if (_favoritesOnly) _selectedCategory = null;
    });
    _applyFilters();
  }

  KeyEventResult _handleChannelKeys(KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (_focusedIndex > 0) {
        setState(() {
          _focusedIndex--;
          _scheduleChannel = _filteredChannels[_focusedIndex];
        });
        _scrollToFocused();
      } else {
        setState(() => _focusZone = _FocusZone.filters);
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_focusedIndex < _filteredChannels.length - 1) {
        setState(() {
          _focusedIndex++;
          _scheduleChannel = _filteredChannels[_focusedIndex];
        });
        _scrollToFocused();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (_filteredChannels.isNotEmpty) {
        _enterSchedulePane(_filteredChannels[_focusedIndex]);
      }
      return KeyEventResult.handled;
    }
    if (isActivateKey(event.logicalKey)) {
      if (_filteredChannels.isNotEmpty) {
        final ch = _filteredChannels[_focusedIndex];
        final oi = _channels.indexWhere(
          (c) => c.url == ch.url && c.name == ch.name,
        );
        if (oi >= 0) unawaited(widget.onChannelSelected(_channels, oi));
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
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
    if (PlatformUtil.isTelevision) return child;
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
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
          // Spotlight goes full-bleed on the big screen: the guide IS the
          // surface, over the dimmed picture — no floating card chrome.
          final fullBleed =
              widget.style == PlayerGuideStyle.spotlight && !compact;
          final width = fullBleed
              ? constraints.maxWidth
              : compact
              ? constraints.maxWidth
              : math.min(
                  constraints.maxWidth * (wide ? 0.82 : 0.72),
                  wide ? 1120.0 : 760.0,
                );
          final height = compact
              ? math.min(constraints.maxHeight * 0.94, 760.0)
              : constraints.maxHeight;
          final t = _t;
          BorderRadius radius;
          if (t == null) {
            radius = compact
                ? const BorderRadius.vertical(top: Radius.circular(24))
                : const BorderRadius.only(
                    topLeft: Radius.circular(26),
                    bottomLeft: Radius.circular(26),
                  );
          } else {
            final r = widget.style == PlayerGuideStyle.glass
                ? 24.0
                : _styledRadius;
            radius = compact
                ? BorderRadius.vertical(top: Radius.circular(r))
                : BorderRadius.only(
                    topLeft: Radius.circular(r),
                    bottomLeft: Radius.circular(r),
                  );
          }
          if (fullBleed) radius = BorderRadius.zero;

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
                        decoration: t == null
                            ? BoxDecoration(
                                color: _surfaceDark.withValues(alpha: 0.98),
                                borderRadius: radius,
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.07),
                                ),
                              )
                            : BoxDecoration(
                                color: t.panel,
                                borderRadius: radius,
                                border: fullBleed
                                    ? null
                                    : Border.all(color: t.hairline),
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
                  color: _t == null
                      ? Colors.white.withValues(alpha: 0.08)
                      : _t!.hairline,
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
                color: _t == null
                    ? Colors.white.withValues(alpha: 0.22)
                    : _t!.hairline2,
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
          LinearProgressIndicator(
            minHeight: 2,
            color: _t == null ? _accent : _t!.accent,
            backgroundColor: Colors.transparent,
          ),
        if (_browseError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Text(
              _browseError!,
              style: TextStyle(
                color: _t == null ? const Color(0xFFFF8A8A) : _t!.rec,
                fontSize: 11,
              ),
            ),
          ),
        Expanded(child: _buildChannelList(compact: compact)),
      ],
    );
  }

  // ─── Header ─────────────────────────────────────────────────────────

  Widget _buildHeader({required bool compact}) {
    final t = _t;
    if (t != null) return _buildHeaderStyled(compact: compact, t: t);
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
              onPressed: _leaveSchedulePane,
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

  /// The header line each styled look owns. The sub-line logic (schedule
  /// channel name / press-enter prompt / count) is shared with classic —
  /// it's state, not paint.
  Widget _buildHeaderStyled({
    required bool compact,
    required IptvStyleTokens t,
  }) {
    final isSchedule = _compactPane == _CompactPane.schedule && compact;
    final title = isSchedule ? 'Programme Guide' : 'Live TV Guide';
    final subtitle = isSchedule
        ? (_scheduleChannel?.name ?? 'Select a channel')
        : (widget.browseProvider != null &&
              _searchController.text.trim().isNotEmpty &&
              _searchController.text.trim() != _submittedQuery)
        ? 'Press enter to search all channels'
        : '${_filteredChannels.length} of ${_channels.length} channels';
    final style = widget.style;

    final Widget identity;
    if (style == PlayerGuideStyle.edition) {
      // Editorial: a kicker over a serif title, no icon tile.
      identity = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isSchedule ? 'PROGRAMME' : 'GUIDE',
            style: TextStyle(
              color: t.fgDim,
              fontSize: 10,
              fontFamily: t.captionFamily,
              fontStyle: FontStyle.italic,
              letterSpacing: 2.2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            isSchedule ? (_scheduleChannel?.name ?? title) : 'Live Television',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: t.fg,
              fontSize: compact ? 19 : 22,
              fontFamily: t.headlineFamily,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: t.fgFaint, fontSize: 11.5),
          ),
        ],
      );
    } else {
      final console = style == PlayerGuideStyle.console;
      identity = Row(
        children: [
          Container(
            width: compact ? 34 : 40,
            height: compact ? 34 : 40,
            decoration: BoxDecoration(
              color: t.selectedTint,
              borderRadius: BorderRadius.circular(console ? 4 : 12),
              border: Border.all(color: t.hairline2),
            ),
            child: Icon(Icons.live_tv_rounded, color: t.accent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  console
                      ? (isSchedule ? 'PROGRAMME GUIDE' : 'CHANNEL GUIDE')
                      : title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.fg,
                    fontSize: console
                        ? (compact ? 15 : 17)
                        : (compact ? 17 : 20),
                    fontWeight: FontWeight.w700,
                    fontFamily: console && t.nameFamily.isNotEmpty
                        ? t.nameFamily
                        : null,
                    letterSpacing: console ? 1.2 : -0.5,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.fgFaint,
                    fontSize: console ? 11 : 12,
                    fontFamily: console && t.monoFamily.isNotEmpty
                        ? t.monoFamily
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Container(
      padding: EdgeInsets.fromLTRB(20, compact ? 10 : 16, 14, 10),
      child: Row(
        children: [
          Expanded(child: identity),
          if (compact && _compactPane == _CompactPane.schedule)
            IconButton(
              tooltip: 'Back to channels',
              onPressed: _leaveSchedulePane,
              icon: Icon(Icons.arrow_back_rounded, color: t.fgMid),
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
                  color: t.focusTint,
                  shape: BoxShape.circle,
                  border: Border.all(color: t.hairline),
                ),
                child: Icon(Icons.close_rounded, color: t.fgDim, size: 18),
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
    final t = _t;
    if (t != null) {
      final console = widget.style == PlayerGuideStyle.console;
      final edition = widget.style == PlayerGuideStyle.edition;
      final radius = BorderRadius.circular(_styledRadius);
      return Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, compact ? 8 : 10),
        child: Material(
          color: t.selectedTint,
          borderRadius: radius,
          child: InkWell(
            borderRadius: radius,
            onTap: () => _enterSchedulePane(channel),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: radius,
                border: edition || console
                    ? Border(
                        left: BorderSide(
                          color: edition ? t.fg : t.accent,
                          width: 2,
                        ),
                      )
                    : Border.all(color: t.accent),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  _GuideLogo(
                    channel: channel,
                    size: compact ? 38 : 42,
                    tokens: t,
                    circle: edition,
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          channel.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: t.fg,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            fontFamily: console && t.nameFamily.isNotEmpty
                                ? t.nameFamily
                                : null,
                          ),
                        ),
                        const SizedBox(height: 2),
                        _TileSubLine(
                          channel: channel,
                          isFocused: true,
                          tokens: t,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StyledTag(
                    label: 'NOW',
                    color: edition ? t.fg : t.accent,
                    onDark: t.bg,
                    square: console,
                    outline: edition,
                    monoFamily: console ? t.monoFamily : '',
                  ),
                  if (compact) ...[
                    const SizedBox(width: 6),
                    Icon(
                      Icons.calendar_month_rounded,
                      color: t.fgDim,
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
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, compact ? 8 : 10),
      child: Material(
        color: _accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _enterSchedulePane(channel),
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

    // Branch-first per expression: `t == null` keeps every legacy value
    // verbatim; the styled side reads only tokens.
    final t = _t;
    final radius = t == null ? 14.0 : _styledRadius;
    final console = t != null && widget.style == PlayerGuideStyle.console;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          color: t == null
              ? (hasFocus
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.white.withValues(alpha: 0.04))
              : (hasFocus ? t.focusTint : t.selectedTint),
          border: Border.all(
            color: t == null
                ? (hasFocus
                      ? _accent.withValues(alpha: 0.4)
                      : Colors.transparent)
                : (hasFocus ? t.accent : t.hairline),
            width: 1.5,
          ),
          boxShadow: hasFocus
              ? [
                  BoxShadow(
                    color: t == null
                        ? _accent.withValues(alpha: 0.08)
                        : t.focusTint,
                    blurRadius: 16,
                  ),
                ]
              : [],
        ),
        child: TvTextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          style: TextStyle(
            color: t == null ? Colors.white : t.fg,
            fontSize: 14,
            fontWeight: FontWeight.w400,
            fontFamily: console && t.monoFamily.isNotEmpty
                ? t.monoFamily
                : null,
          ),
          decoration: InputDecoration(
            hintText: 'Search channels or categories...',
            hintStyle: TextStyle(
              color: t == null
                  ? Colors.white.withValues(alpha: 0.25)
                  : t.fgFaint,
              fontSize: 13,
              fontWeight: FontWeight.w400,
            ),
            prefixIcon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                hasQuery ? Icons.filter_list_rounded : Icons.search_rounded,
                key: ValueKey(hasQuery),
                color: t == null
                    ? (hasFocus
                          ? _accent.withValues(alpha: 0.7)
                          : Colors.white.withValues(alpha: 0.3))
                    : (hasFocus ? t.accent : t.fgFaint),
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
                        color: t == null
                            ? Colors.white.withValues(alpha: 0.4)
                            : t.fgDim,
                        size: 18,
                      ),
                      onPressed: () => unawaited(_clearSearch()),
                    ),
                  IconButton(
                    tooltip: 'Search full source',
                    icon: Icon(
                      Icons.arrow_forward_rounded,
                      color: t == null
                          ? _accent.withValues(alpha: 0.75)
                          : (widget.style == PlayerGuideStyle.edition
                                ? t.fgMid
                                : t.accent),
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
              borderRadius: BorderRadius.circular(radius),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(radius),
              borderSide: BorderSide.none,
            ),
          ),
          onChanged: (_) {
            _searchSubmitFocus.cancel();
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
    _pickerOpen = true;
    final _CategoryChoice? choice;
    try {
      choice = await showDialog<_CategoryChoice>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.6),
        builder: (_) => _CategoryPickerDialog(
          categories: _categories,
          selected: _favoritesOnly ? null : _selectedCategory,
          tokens: _t,
        ),
      );
    } finally {
      _pickerOpen = false;
    }
    if (!mounted) return;
    // The dialog route held focus — take the DPAD back either way.
    _keyboardFocusNode.requestFocus();
    if (choice == null) return;
    await _selectCategory(choice.value);
  }

  bool _dpadOnFilter(int i) =>
      _focusZone == _FocusZone.filters && _filterIndex == i;

  /// Source picker — shared by the pill's tap and the filter zone's OK.
  Future<void> _openSourceMenu() async {
    final options = [
      for (final source in _sources)
        _GuideMenuOption(
          value: source,
          label: source['name'] as String? ?? 'IPTV',
        ),
    ];
    if (options.isEmpty) return;
    _pickerOpen = true;
    final Map<String, dynamic>? choice;
    try {
      choice = await showDialog<Map<String, dynamic>>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.6),
        builder: (_) => _GuideSelectDialog(
          icon: Icons.dns_rounded,
          title: _sourceName,
          options: options,
          tokens: _t,
        ),
      );
    } finally {
      _pickerOpen = false;
    }
    if (!mounted) return;
    _keyboardFocusNode.requestFocus();
    if (choice != null) unawaited(_selectSource(choice));
  }

  Widget _buildFilterBar() {
    final categoryLabel = _favoritesOnly ? 'All' : (_selectedCategory ?? 'All');
    // Console readouts are uppercase mono, per the instrument grammar.
    final console = _t != null && widget.style == PlayerGuideStyle.console;
    final labelFamily = console ? _t!.monoFamily : '';
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
                hasOptions: _sources.isNotEmpty,
                onOpen: () => unawaited(_openSourceMenu()),
                dpadFocused: _dpadOnFilter(0),
                tokens: _t,
                radius: _t == null ? 10 : _styledRadius,
                labelFamily: labelFamily,
                upperLabels: console,
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
                dpadFocused: _dpadOnFilter(1),
                tokens: _t,
                radius: _t == null ? 10 : _styledRadius,
                labelFamily: labelFamily,
                upperLabels: console,
              ),
            ),
            const SizedBox(width: 7),
            _FilterChip(
              icon: Icons.favorite_rounded,
              label: 'Saved',
              selected: _favoritesOnly,
              onTap: _toggleFavoritesFilter,
              dpadFocused: _dpadOnFilter(2),
              tokens: _t,
              radius: _t == null ? 10 : _styledRadius,
              labelFamily: labelFamily,
              upperLabels: console,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSchedulePane({required bool compact}) {
    final t = _t;
    final channel = _scheduleChannel;
    if (channel == null) {
      return Center(
        child: Text(
          'Select a channel to view its schedule',
          style: TextStyle(
            color: t == null ? Colors.white.withValues(alpha: 0.45) : t.fgDim,
          ),
        ),
      );
    }
    final edition = t != null && widget.style == PlayerGuideStyle.edition;
    final console = t != null && widget.style == PlayerGuideStyle.console;
    final favorited = _favoriteUrls.contains(channel.url);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(compact ? 18 : 24, 12, 18, 12),
          child: Row(
            children: [
              _GuideLogo(
                channel: channel,
                size: 46,
                tokens: t,
                circle: edition,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      channel.name,
                      maxLines: compact ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t == null ? Colors.white : t.fg,
                        fontSize: 17,
                        fontWeight: edition ? FontWeight.w400 : FontWeight.w800,
                        fontFamily: edition
                            ? t.headlineFamily
                            : (console && t.nameFamily.isNotEmpty
                                  ? t.nameFamily
                                  : null),
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
                        color: t == null
                            ? Colors.white.withValues(alpha: 0.42)
                            : t.fgFaint,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: favorited ? 'Remove favorite' : 'Add favorite',
                onPressed: () => unawaited(_toggleFavorite(channel)),
                icon: Icon(
                  favorited
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  // Favorite mapping per the plan: glass/console accent when
                  // active, edition cream; inactive always fgFaint.
                  color: t == null
                      ? (favorited ? const Color(0xFFF43F5E) : Colors.white54)
                      : (favorited ? (edition ? t.fg : t.accent) : t.fgFaint),
                ),
              ),
            ],
          ),
        ),
        Divider(
          height: 1,
          color: t == null ? Colors.white.withValues(alpha: 0.08) : t.hairline,
        ),
        Expanded(
          child: FocusScope(
            node: _scheduleScope,
            // Gated: in wide layouts this pane is always mounted, and its
            // rows/anchors carry autofocus — ungated they could steal
            // primary focus (e.g. when loading settles) while the DPAD is
            // still on the channel list.
            descendantsAreFocusable: _compactPane == _CompactPane.schedule,
            child: EpgScheduleList(
              key: ValueKey('schedule-${channel.url}'),
              channel: channel,
              isTelevision: PlatformUtil.isTelevision,
              tokens: t,
              onPlayProgramme: widget.onPlayProgramme == null
                  ? null
                  : (programme) {
                      unawaited(widget.onPlayProgramme!(channel, programme));
                    },
              // isSchedulableUrl, not engineRecordableUrl: with nobody watching
              // at alarm time there is no player probe, so only URLs KNOWN to be
              // progressive TS may be scheduled (an extensionless HLS URL would
              // record playlist text and call it saved).
              onRecordProgramme:
                  !_recordSchedulingAvailable ||
                      !LiveRecordingService.isSchedulableUrl(channel.url)
                  ? null
                  : (programme) {
                      unawaited(_confirmScheduleRecording(channel, programme));
                    },
            ),
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
    if (Platform.isAndroid && !await LiveRecordingService.ensureEngineReady()) {
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
    String clock(DateTime t) => MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(t));
    final airsNow =
        !programme.start.isAfter(DateTime.now()) &&
        programme.stop.isAfter(DateTime.now());
    final confirmed = await showSpotlightDialog<bool>(
      context,
      builder: (dialogContext) => SpotlightDialogCard(
        title: 'Record programme?',
        statusDot: SpotlightDialogCard.statusRed,
        bodyText: '${programme.title} · ${channel.name}',
        metaText:
            '${clock(programme.start)} – ${clock(programme.stop)}'
            '${airsNow ? ' · already airing — records the rest' : ''}',
        actions: [
          SpotlightDialogAction(
            'Cancel',
            () => Navigator.of(dialogContext).pop(false),
          ),
          SpotlightDialogAction(
            'Record',
            () => Navigator.of(dialogContext).pop(true),
            solid: true,
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final resource = await _recordingResource(channel);
    if (!mounted) return;
    final result = DesktopScheduleService.instance.isSupported
        ? await DesktopScheduleService.instance.add(
            url: recordUrl,
            channelName: channel.name,
            programmeTitle: programme.title,
            startMs: programme.start.millisecondsSinceEpoch,
            endMs: programme.stop.millisecondsSinceEpoch,
            headers: channel.playbackHeaders,
            connectionResourceId: resource?.id,
            resourceAuthorizationRevision: resource?.revision,
          )
        : await LiveRecordingService.schedule(
            url: recordUrl,
            channelName: channel.name,
            programmeTitle: programme.title,
            startMs: programme.start.millisecondsSinceEpoch,
            endMs: programme.stop.millisecondsSinceEpoch,
            headers: channel.playbackHeaders,
            connectionResourceId: resource?.id,
            resourceAuthorizationRevision: resource?.revision,
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildKeyboardHints() {
    final t = _t;
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: t == null
                ? Colors.white.withValues(alpha: 0.06)
                : t.hairline,
          ),
        ),
      ),
      child: Row(
        children: [
          _KeyHint(keyLabel: 'Enter', action: 'Play', tokens: t),
          const SizedBox(width: 20),
          _KeyHint(keyLabel: '→', action: 'Schedule', tokens: t),
          const Spacer(),
          _KeyHint(keyLabel: 'Esc', action: 'Close', tokens: t),
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
      final t = _t;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: t == null
                    ? Colors.white.withValues(alpha: 0.03)
                    : t.focusTint,
                shape: BoxShape.circle,
              ),
              child: Icon(
                pending ? Icons.search_rounded : Icons.satellite_alt_rounded,
                color: t == null
                    ? Colors.white.withValues(alpha: 0.1)
                    : t.fgFaint,
                size: 32,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              pending ? 'Search all channels' : 'No channels found',
              style: TextStyle(
                color: t == null
                    ? Colors.white.withValues(alpha: 0.4)
                    : t.fgDim,
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
                color: t == null
                    ? Colors.white.withValues(alpha: 0.2)
                    : t.fgFaint,
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
                  backgroundColor: t == null
                      ? const Color(0xFF7C5CFF)
                      : (widget.style == PlayerGuideStyle.edition
                            ? t.fg
                            : t.accent),
                  foregroundColor: t == null
                      ? Colors.white
                      : t.bg.withAlpha(0xFF),
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
          tokens: _t,
          guideStyle: widget.style,
          onTap: () {
            if (origIdx >= 0) {
              unawaited(widget.onChannelSelected(_channels, origIdx));
            }
          },
          onFavorite: () => unawaited(_toggleFavorite(channel)),
          onSchedule: () => _enterSchedulePane(channel),
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
  final bool hasOptions;

  /// Opens the select dialog (owned by the sheet state, so the filter
  /// zone's OK and this tap share one path).
  final VoidCallback onOpen;
  final bool dpadFocused;
  final IptvStyleTokens? tokens;
  final double radius;
  final String labelFamily;
  final bool upperLabels;

  const _GuideMenuButton({
    required this.icon,
    required this.label,
    required this.hasOptions,
    required this.onOpen,
    this.dpadFocused = false,
    this.tokens,
    this.radius = 10,
    this.labelFamily = '',
    this.upperLabels = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    // Spotlight inverse focus: solid fill + flipped ink; other styles get
    // an accent ring so the new filter zone is visible everywhere.
    final fill = dpadFocused ? t?.focusFill : null;
    final ink = fill != null ? t!.focusInk! : null;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(radius),
      child: InkWell(
        onTap: hasOptions ? onOpen : null,
        borderRadius: BorderRadius.circular(radius),
        child: Container(
          constraints: const BoxConstraints(minWidth: 92, maxWidth: 170),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            color:
                fill ??
                (t == null
                    ? Colors.white.withValues(alpha: 0.06)
                    : t.focusTint),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: dpadFocused && fill == null
                  ? (t == null ? Colors.white : t.accent)
                  : t == null
                  ? Colors.white.withValues(alpha: 0.06)
                  : t.hairline,
              width: dpadFocused && fill == null ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color:
                    ink?.withValues(alpha: 0.7) ??
                    (t == null ? Colors.white54 : t.fgDim),
                size: 15,
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  upperLabels ? label.toUpperCase() : label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: ink ?? (t == null ? Colors.white70 : t.fgMid),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    fontFamily: labelFamily.isEmpty ? null : labelFamily,
                  ),
                ),
              ),
              if (hasOptions) ...[
                const SizedBox(width: 5),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color:
                      ink?.withValues(alpha: 0.55) ??
                      (t == null ? Colors.white38 : t.fgFaint),
                  size: 16,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Select dialog behind [_GuideMenuButton] — the guide's picker chrome
/// (token panel, hairline, [_CategoryPickerRow]s) for short option lists.
class _GuideSelectDialog extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<_GuideMenuOption> options;
  final IptvStyleTokens? tokens;

  const _GuideSelectDialog({
    required this.icon,
    required this.title,
    required this.options,
    this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final t = tokens;
    return Dialog(
      // Dialogs need an opaque surface — the token panel's over-video alpha
      // is flattened here (same rule as the category picker).
      backgroundColor: t == null
          ? const Color(0xFF14141C)
          : t.panel.withAlpha(0xFF),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: t == null ? BorderSide.none : BorderSide(color: t.hairline2),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 420,
          maxHeight: size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
              child: Row(
                children: [
                  Icon(
                    icon,
                    color: t == null ? Colors.white54 : t.fgDim,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t == null ? Colors.white : t.fg,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '${options.length}',
                    style: TextStyle(
                      color: t == null
                          ? Colors.white.withValues(alpha: 0.35)
                          : t.fgFaint,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 12),
                itemCount: options.length,
                itemBuilder: (_, index) {
                  final option = options[index];
                  return _CategoryPickerRow(
                    label: option.label,
                    // The button doesn't know the active entry, same as the
                    // popup it replaces — rows render unselected.
                    selected: false,
                    onTap: () => Navigator.of(context).pop(option.value),
                    tokens: t,
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

/// Rebuild an [IptvChannel] from a browse-provider channel map.
///
/// Exposed because the player consumes the same payload when it re-anchors its
/// channel ring to a category. Both sides must parse it identically — a
/// channel rebuilt differently in the two places stops matching itself, and
/// the playing row can no longer be found in its own list.
IptvChannel iptvChannelFromBrowsePayload(Map<String, dynamic> raw) =>
    IptvChannelSheetState._channelFromMap(raw);

/// A dropdown-looking button that opens a picker rather than a popup menu —
/// for lists too long to sit in a [PopupMenuButton].
class _GuideDropdownButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool dpadFocused;
  final IptvStyleTokens? tokens;
  final double radius;
  final String labelFamily;
  final bool upperLabels;

  const _GuideDropdownButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.dpadFocused = false,
    this.tokens,
    this.radius = 10,
    this.labelFamily = '',
    this.upperLabels = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    // Spotlight inverse focus first, then the styled selected state: a quiet
    // token tint + accent text instead of the legacy purple slab.
    final fill = dpadFocused ? t?.focusFill : null;
    final ink = fill != null ? t!.focusInk! : null;
    return Material(
      color:
          fill ??
          (t == null
              ? (selected
                    ? const Color(0xFF7C5CFF)
                    : Colors.white.withValues(alpha: 0.06))
              : (selected ? t.selectedTint : t.focusTint)),
      borderRadius: BorderRadius.circular(radius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: Container(
          constraints: const BoxConstraints(minWidth: 92, maxWidth: 190),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: dpadFocused && fill == null
                  ? (t == null ? Colors.white : t.accent)
                  : t == null
                  ? (selected
                        ? Colors.transparent
                        : Colors.white.withValues(alpha: 0.06))
                  : (selected ? t.accent : t.hairline),
              width: dpadFocused && fill == null ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color:
                    ink?.withValues(alpha: 0.7) ??
                    (t == null
                        ? (selected ? Colors.white : Colors.white54)
                        : (selected ? t.accent : t.fgDim)),
                size: 15,
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  upperLabels ? label.toUpperCase() : label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color:
                        ink ??
                        (t == null
                            ? (selected ? Colors.white : Colors.white70)
                            : (selected ? t.accent : t.fgMid)),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    fontFamily: labelFamily.isEmpty ? null : labelFamily,
                  ),
                ),
              ),
              const SizedBox(width: 5),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                color:
                    ink?.withValues(alpha: 0.55) ??
                    (t == null
                        ? (selected ? Colors.white70 : Colors.white38)
                        : (selected ? t.fgMid : t.fgFaint)),
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
  final IptvStyleTokens? tokens;

  const _CategoryPickerDialog({
    required this.categories,
    required this.selected,
    this.tokens,
  });

  @override
  State<_CategoryPickerDialog> createState() => _CategoryPickerDialogState();
}

class _CategoryPickerDialogState extends State<_CategoryPickerDialog> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final FocusNode _firstMatchFocusNode = FocusNode();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _firstMatchFocusNode.dispose();
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

  void _focusFirstMatch() {
    if (_matches.isNotEmpty) _firstMatchFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final matches = _matches;
    final t = widget.tokens;

    return Dialog(
      // Dialogs need an opaque surface — the token panel's over-video alpha
      // is flattened here.
      backgroundColor: t == null
          ? const Color(0xFF14141C)
          : t.panel.withAlpha(0xFF),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: t == null ? BorderSide.none : BorderSide(color: t.hairline2),
      ),
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
                  Icon(
                    Icons.category_rounded,
                    color: t == null ? Colors.white54 : t.fgDim,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Category',
                      style: TextStyle(
                        color: t == null ? Colors.white : t.fg,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '${widget.categories.length}',
                    style: TextStyle(
                      color: t == null
                          ? Colors.white.withValues(alpha: 0.35)
                          : t.fgFaint,
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
                  color: t == null
                      ? Colors.white.withValues(alpha: 0.05)
                      : t.focusTint,
                  borderRadius: BorderRadius.circular(12),
                  border: t == null ? null : Border.all(color: t.hairline),
                ),
                // Deliberately not autofocused: on TV that would throw the
                // in-app keyboard over the list before the user has looked
                // at it.
                child: TvTextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  style: TextStyle(
                    color: t == null ? Colors.white : t.fg,
                    fontSize: 14,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search categories…',
                    hintStyle: TextStyle(
                      color: t == null
                          ? Colors.white.withValues(alpha: 0.25)
                          : t.fgFaint,
                      fontSize: 13,
                    ),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      color: t == null
                          ? Colors.white.withValues(alpha: 0.3)
                          : t.fgFaint,
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
                  onSubmitted: (_) => _focusFirstMatch(),
                  onDownArrow: _focusFirstMatch,
                  textInputAction: TextInputAction.search,
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
                          color: t == null
                              ? Colors.white.withValues(alpha: 0.4)
                              : t.fgDim,
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
                          focusNode: index == 0 ? _firstMatchFocusNode : null,
                          onTap: () => Navigator.of(
                            context,
                          ).pop(_CategoryChoice(category)),
                          tokens: t,
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
  final FocusNode? focusNode;
  final VoidCallback onTap;
  final IptvStyleTokens? tokens;

  const _CategoryPickerRow({
    required this.label,
    required this.selected,
    this.focusNode,
    required this.onTap,
    this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        focusNode: focusNode,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          color: selected
              ? (t == null
                    ? const Color(0xFF7C5CFF).withValues(alpha: 0.16)
                    : t.selectedTint)
              : Colors.transparent,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t == null
                        ? (selected ? Colors.white : Colors.white70)
                        : (selected ? t.fg : t.fgMid),
                    fontSize: 13.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              if (selected)
                Icon(
                  Icons.check_rounded,
                  color: t == null ? const Color(0xFF7C5CFF) : t.accent,
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
  final bool dpadFocused;
  final IptvStyleTokens? tokens;
  final double radius;
  final String labelFamily;
  final bool upperLabels;

  const _FilterChip({
    required this.label,
    this.icon,
    required this.selected,
    required this.onTap,
    this.dpadFocused = false,
    this.tokens,
    this.radius = 10,
    this.labelFamily = '',
    this.upperLabels = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final fill = dpadFocused ? t?.focusFill : null;
    final ink = fill != null ? t!.focusInk! : null;
    return Material(
      color:
          fill ??
          (t == null
              ? (selected
                    ? const Color(0xFF7C5CFF)
                    : Colors.white.withValues(alpha: 0.05))
              : (selected ? t.selectedTint : t.focusTint)),
      borderRadius: BorderRadius.circular(radius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: dpadFocused && fill == null
                ? Border.all(
                    color: t == null ? Colors.white : t.accent,
                    width: 1.5,
                  )
                : t == null
                ? null
                : Border.all(color: selected ? t.accent : t.hairline),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 14,
                  color:
                      ink?.withValues(alpha: 0.7) ??
                      (t == null
                          ? (selected ? Colors.white : Colors.white54)
                          : (selected ? t.accent : t.fgDim)),
                ),
                const SizedBox(width: 5),
              ],
              Text(
                upperLabels ? label.toUpperCase() : label,
                style: TextStyle(
                  color:
                      ink ??
                      (t == null
                          ? (selected ? Colors.white : Colors.white60)
                          : (selected ? t.accent : t.fgMid)),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  fontFamily: labelFamily.isEmpty ? null : labelFamily,
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
  final IptvStyleTokens? tokens;
  const _KeyHint({required this.keyLabel, required this.action, this.tokens});

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          decoration: BoxDecoration(
            color: t == null
                ? Colors.white.withValues(alpha: 0.08)
                : t.focusTint,
            borderRadius: BorderRadius.circular(5),
            border: t == null ? null : Border.all(color: t.hairline),
          ),
          child: Text(
            keyLabel,
            style: TextStyle(
              color: t == null ? Colors.white70 : t.fgMid,
              fontSize: 9,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          action,
          style: TextStyle(
            color: t == null ? Colors.white.withValues(alpha: 0.4) : t.fgFaint,
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
  final IptvStyleTokens? tokens;

  /// Edition's grammar: channel marks are circles, not rounded squares.
  final bool circle;
  const _GuideLogo({
    required this.channel,
    required this.size,
    this.tokens,
    this.circle = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final hasLogo = channel.logoUrl?.isNotEmpty == true;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: t == null
            ? Colors.white.withValues(alpha: 0.06)
            : t.selectedTint,
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(10),
        border: Border.all(
          color: t == null ? Colors.white.withValues(alpha: 0.06) : t.hairline,
        ),
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
    final t = tokens;
    return Center(
      child: Text(
        channel.name.isEmpty ? '?' : channel.name[0].toUpperCase(),
        style: TextStyle(
          color: t == null ? Colors.white70 : t.fg,
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

/// The styled looks' NOW/LIVE tag. Glass fills a rounded pill with [color];
/// edition ([outline]) is bare small-caps cream text — no pill, no border,
/// matching the native edition grammar; console squares the corners and
/// sets the mono face — one widget, three grammars, token colors only.
class _StyledTag extends StatelessWidget {
  final String label;
  final Color color;

  /// Text color when the tag is filled — the style's bg so the label
  /// punches out of the fill.
  final Color onDark;
  final bool square;
  final bool outline;
  final String monoFamily;

  const _StyledTag({
    required this.label,
    required this.color,
    required this.onDark,
    this.square = false,
    this.outline = false,
    this.monoFamily = '',
  });

  @override
  Widget build(BuildContext context) {
    if (outline) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 8,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(square ? 2 : 5),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: onDark.withAlpha(0xFF),
          fontSize: 8,
          fontWeight: FontWeight.w900,
          letterSpacing: square ? 1.2 : 0.5,
          fontFamily: monoFamily.isEmpty ? null : monoFamily,
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
  final IptvStyleTokens? tokens;
  final PlayerGuideStyle guideStyle;

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
    this.tokens,
    this.guideStyle = PlayerGuideStyle.classic,
  });

  bool get _edition => tokens != null && guideStyle == PlayerGuideStyle.edition;
  bool get _console => tokens != null && guideStyle == PlayerGuideStyle.console;

  /// Spotlight inverse focus: the focused row is a solid [focusFill] pill
  /// and every ink on it flips to [focusInk].
  bool get _inverse => tokens?.focusFill != null && isFocused;

  /// Row chrome per look. Classic keeps its verbatim gradient/border/glow;
  /// glass swaps to a quiet token tint + accent ring; edition rules a ledger
  /// (hairline under every row, cream left rule when focused); console is a
  /// squared instrument row whose focus cue is the corner brackets painted
  /// by [IptvFocusBracketsPainter] below.
  BoxDecoration _decoration(IptvStyleTokens? t) {
    final fill = t?.focusFill;
    if (fill != null) {
      return BoxDecoration(
        color: isFocused
            ? fill
            : isCurrent
            ? t!.selectedTint
            : Colors.transparent,
        borderRadius: BorderRadius.circular(11),
        boxShadow: isFocused
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 18,
                  offset: const Offset(0, 5),
                ),
              ]
            : const [],
      );
    }
    if (t == null) {
      return BoxDecoration(
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
      );
    }
    if (_edition) {
      return BoxDecoration(
        color: isFocused
            ? t.selectedTint
            : isCurrent
            ? t.focusTint
            : Colors.transparent,
        border: Border(
          left: BorderSide(
            color: isFocused ? t.fg : Colors.transparent,
            width: 2,
          ),
          bottom: BorderSide(color: t.hairline),
        ),
      );
    }
    if (_console) {
      return BoxDecoration(
        color: isFocused
            ? t.focusTint
            : isCurrent
            ? t.selectedTint
            : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
      );
    }
    // Glass.
    return BoxDecoration(
      color: isFocused
          ? t.focusTint
          : isCurrent
          ? t.selectedTint
          : Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: isFocused
            ? t.accent
            : isCurrent
            ? t.hairline2
            : Colors.transparent,
        width: isFocused ? 1.5 : 1,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    return GestureDetector(
      key: ValueKey('iptv-channel-${channel.url}'),
      onTap: onTap,
      child: CustomPaint(
        foregroundPainter: _console && isFocused
            ? IptvFocusBracketsPainter(t!.accent)
            : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: _decoration(t),
          child: Row(
            children: [
              // Channel number
              SizedBox(
                width: 30,
                child: Text(
                  _console
                      ? channelNumber.toString().padLeft(3, '0')
                      : channelNumber.toString().padLeft(2, ' '),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: t == null
                        ? (isCurrent
                              ? _accent.withValues(alpha: 0.8)
                              : isFocused
                              ? Colors.white.withValues(alpha: 0.5)
                              : Colors.white.withValues(alpha: 0.18))
                        : _inverse
                        ? t.focusInk!.withValues(alpha: 0.45)
                        : (isCurrent
                              ? (_edition ? t.fg : t.accent)
                              : isFocused
                              ? t.fgDim
                              : t.fgFaint),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    fontFamily: _console && t!.monoFamily.isNotEmpty
                        ? t.monoFamily
                        : null,
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
                        color: t == null
                            ? (isCurrent
                                  ? _accent
                                  : isFocused
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.85))
                            : _inverse
                            ? t.focusInk!
                            : (isCurrent
                                  ? (_edition ? t.fg : t.accent)
                                  : isFocused
                                  ? t.fg
                                  : t.fgMid),
                        fontSize: 13.5,
                        fontWeight: isFocused || isCurrent
                            ? FontWeight.w600
                            : FontWeight.w400,
                        fontFamily: _console && t!.nameFamily.isNotEmpty
                            ? t.nameFamily
                            : null,
                        letterSpacing: -0.2,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: _TileSubLine(
                        channel: channel,
                        isFocused: isFocused,
                        tokens: t,
                        inkOverride: _inverse
                            ? t!.focusInk!.withValues(alpha: 0.55)
                            : null,
                      ),
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
                color: t == null
                    ? (isFavorited ? const Color(0xFFF43F5E) : Colors.white38)
                    : _inverse
                    ? t.focusInk!.withValues(alpha: isFavorited ? 0.85 : 0.45)
                    : (isFavorited ? (_edition ? t.fg : t.accent) : t.fgFaint),
                onTap: onFavorite,
              ),
              _TileAction(
                tooltip: 'Programme guide',
                icon: Icons.calendar_month_rounded,
                color: t == null
                    ? _accent.withValues(alpha: 0.75)
                    : _inverse
                    ? t.focusInk!.withValues(alpha: 0.55)
                    : t.fgDim,
                onTap: onSchedule,
              ),
              if (isCurrent)
                _buildNowBadge()
              else if (channel.isLive)
                _buildLiveBadge(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    final t = tokens;
    final hasLogo = channel.logoUrl != null && channel.logoUrl!.isNotEmpty;

    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        shape: _edition ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: _edition
            ? null
            : BorderRadius.circular(t == null ? 10 : (_console ? 4 : 10)),
        color: t == null
            ? Colors.white.withValues(alpha: 0.05)
            : _inverse
            ? t.focusInk!.withValues(alpha: 0.16)
            : t.selectedTint,
        border: Border.all(
          color: t == null
              ? (isCurrent
                    ? _accent.withValues(alpha: 0.15)
                    : isFocused
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.white.withValues(alpha: 0.03))
              : _inverse
              ? t.focusInk!.withValues(alpha: 0.15)
              : t.hairline,
        ),
        boxShadow: isCurrent && t == null
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
    final t = tokens;
    final letter = channel.name.isNotEmpty
        ? channel.name[0].toUpperCase()
        : '?';
    if (t != null) {
      // Styled looks drop the per-name HSL lottery for one calm tone —
      // the tile bg already carries selectedTint, so just the letter.
      return Container(
        alignment: Alignment.center,
        child: Text(
          letter,
          style: TextStyle(
            color: _inverse ? t.focusInk!.withValues(alpha: 0.6) : t.fg,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
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
    final t = tokens;
    if (t != null) {
      if (_console) {
        // Console LIVE is a square outlined tag, per the instrument grammar.
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: t.live, width: 1),
          ),
          child: Text(
            'LIVE',
            style: TextStyle(
              color: t.live,
              fontSize: 8,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              fontFamily: t.monoFamily.isEmpty ? null : t.monoFamily,
            ),
          ),
        );
      }
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: t.live, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            'LIVE',
            style: TextStyle(
              color: t.live,
              fontSize: 8,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      );
    }
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
    final t = tokens;
    if (t != null) {
      // Static tag — the styled looks don't pulse (nothing animates unless
      // it must), and each keeps its single accent.
      return _StyledTag(
        label: 'NOW',
        color: _edition ? t.fg : t.accent,
        onDark: t.bg,
        square: _console,
        outline: _edition,
        monoFamily: _console ? t.monoFamily : '',
      );
    }
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
  final IptvStyleTokens? tokens;

  /// Set on Spotlight's white focus pill — the row ink flipped dark.
  final Color? inkOverride;
  const _TileSubLine({
    required this.channel,
    required this.isFocused,
    this.tokens,
    this.inkOverride,
  });

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
    final t = widget.tokens;
    return Text(
      now != null ? 'Now:  ${now.title}' : group!,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color:
            widget.inkOverride ??
            (t == null
                ? (now != null
                      ? const Color(
                          0xFF00E5FF,
                        ).withValues(alpha: widget.isFocused ? 0.75 : 0.5)
                      : Colors.white.withValues(
                          alpha: widget.isFocused ? 0.4 : 0.22,
                        ))
                : (now != null
                      ? (widget.isFocused ? t.fgMid : t.fgDim)
                      : t.fgFaint)),
        fontSize: 10.5,
        fontWeight: now != null ? FontWeight.w500 : FontWeight.w400,
      ),
    );
  }
}
