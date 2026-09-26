part of '../search_screen.dart';

/// Exercises the real source screen with controllable engine batches.
@visibleForTesting
Widget sourcesScreenForTesting({
  required AdvancedSearchSelection selection,
  required PlaybackMeta meta,
  required Future<Map<String, dynamic>> Function(SearchBatchCallback onBatch)
  search,
  SourceAddonRetry? retry,
}) => ProviderScope(
  overrides: [
    sourceSearchRepositoryProvider.overrideWith(
      (ref, session) => ServiceSourceSearchRepository(
        owner: session.owner,
        searchOverride: search,
        retryAddon: retry,
      ),
    ),
  ],
  child: _SourcesScreen(selection: selection, meta: meta, isTelevision: true),
);

class _SourcesScreen extends ConsumerStatefulWidget {
  final AdvancedSearchSelection selection;
  final PlaybackMeta meta;
  final bool isTelevision;

  /// When true the screen is a source PICKER: tapping a row pins it as the
  /// bound source and pops (used by the "Select Source" entry points). When
  /// false it's the normal Sources list: tap plays, long-press pins/unpins.
  final bool bindMode;

  /// When non-null the screen searches TORRENTS BY FREE-TEXT KEYWORD (seeded
  /// with this query, editable) instead of by the selection's IMDb id — used by
  /// the "Keyword Search" add-source option. Implies [bindMode]. The selection
  /// still supplies the pin target (imdbId / movie-vs-series).
  final String? keywordSeed;

  /// The user reached this list by pressing PLAY (see the "Play button opens"
  /// modes), so picking a row is a play instruction that has already been
  /// given — tapping one starts playback instead of running the post-torrent
  /// action, which would otherwise ask "Play / Download / Playlist?" for a
  /// choice the user made two taps ago. False for the Sources button and the
  /// episode long-press, where no play intent was expressed.
  final bool forcePlayOnTap;

  const _SourcesScreen({
    required this.selection,
    required this.meta,
    required this.isTelevision,
    this.bindMode = false,
    this.keywordSeed,
    this.forcePlayOnTap = false,
  });

  @override
  ConsumerState<_SourcesScreen> createState() => _SourcesScreenState();
}

class _SourcesScreenState extends ConsumerState<_SourcesScreen> {
  bool _loading = true;
  String? get _error => _searchSubscription.read().error;
  List<Torrent> get _torrents => _resultsSubscription.read().displayed;
  List<IptvSourceResult> get _iptvSources => _searchSubscription.read().iptv;

  /// The rows actually rendered — [_torrents] after the redesign toolbar's
  /// source-group filter, quality/rip/language filter, and sort are applied.
  /// Equals [_torrents] when the redesign is off (no toolbar). [_nodes] is kept
  /// in lock-step with THIS list, never [_torrents].
  List<Torrent> _visible = [];
  final List<FocusNode> _nodes = [];
  final ScrollController _resultsScroll = ScrollController(
    keepScrollOffset: false,
  );
  late final ProviderSubscription<SavedSourcesState> _savedSourcesSubscription;
  List<SeriesSource> get _bound => _savedSourcesSubscription.read().sources;
  // Delayed focus diagnostics may run after subscriptions are disposed.
  int _disposedBoundCount = 0;
  Torrent? _selectedDirect;
  Torrent? get _cachedEpisodeSource =>
      _savedSourcesSubscription.read().cachedEpisode;
  bool _showCachedEpisodeSource = false;
  int _selectionFocusRun = 0;
  final int _pickerTraceId = DateTime.now().microsecondsSinceEpoch;

  void _logPickerSelection(
    String event, [
    Map<String, Object?> detail = const {},
  ]) {
    final selected = _selectedDirect;
    final fields = <String, Object?>{
      'picker': _pickerTraceId,
      'search': _searchToken,
      'season': widget.selection.season,
      'episode': widget.selection.episode,
      'bound_count': mounted ? _bound.length : _disposedBoundCount,
      'results': mounted ? _torrents.length : _disposedResultCount,
      'visible': _visible.length,
      'match_index': mounted
          ? selected == null
                ? -1
                : _torrents.indexOf(selected)
          : _disposedMatchIndex,
      'visible_index': selected == null ? -1 : _visible.indexOf(selected),
      'searching': mounted ? _searching : _disposedSearching,
      'frozen': mounted ? _streamFrozen : _disposedFrozen,
      'rail_focus': _cinemaKey.currentState?.hasRailFocus ?? false,
      'filter_focus': _filterFocus.hasFocus,
      'pill_focus': _pillFocus.hasFocus,
      'tv': widget.isTelevision,
      'provider_filter': mounted ? _sourceFilter != null : _disposedProviderFilter,
      ...detail,
    };
    DiagnosticLog.instance.recordEvent(
      source: 'source_selection',
      event: 'picker_$event',
      fields: fields.map(
        (key, value) =>
            MapEntry(key, value is String ? DiagnosticLabel(value) : value),
      ),
    );
    // Scalars survive the privacy filter; no addon configuration or URLs.
    debugPrint(
      'SourcePicker: event=$event ${fields.entries.map((e) => '${e.key}=${e.value}').join(' ')}',
    );
  }

  void _updateSelectedDirect() {
    _selectedDirect = null;
    if (_bound.isNotEmpty && _bound.first.isMediaServer) {
      for (final candidate in _torrents) {
        if (MediaServerService.bindingFor(candidate)?.bindingKey == _bound.first.bindingKey) {
          _selectedDirect = candidate;
          break;
        }
      }
      return;
    }
    if (_bound.isNotEmpty && _bound.first.isIptvDirect) {
      final pin = _bound.first;
      for (final candidate in _torrents) {
        if (IptvSourceSearch.owns(candidate) &&
            candidate.iptvPlaylistId == pin.iptvPlaylistId &&
            candidate.iptvCatalogType == pin.iptvCatalogType &&
            candidate.iptvEntryKey == pin.iptvEntryKey) {
          _selectedDirect = candidate;
          break;
        }
      }
      _logPickerSelection('match', {
        'reason': _selectedDirect == null ? 'iptv_entry_not_found' : 'matched',
      });
      return;
    }
    if (_bound.isEmpty || !_bound.first.isAddonDirect) {
      _logPickerSelection('match', {
        'reason': _bound.isEmpty ? 'no_saved_source' : 'primary_not_direct',
      });
      return;
    }
    final pin = _bound.first;
    final candidates =
        _torrents
            .where((t) => t.isDirectStream && t.stremioAddonKey == pin.addonKey)
            .toList()
          ..sort(
            (a, b) => (a.stremioStreamIndex ?? 0).compareTo(
              b.stremioStreamIndex ?? 0,
            ),
          );
    _selectedDirect = StremioService.selectPinnedDirectStream(
      candidates,
      streamKey: pin.streamKey ?? '',
      streamIndex: pin.streamIndex ?? 0,
      bingeGroup: pin.bingeGroup,
    );
    final groupMatches = candidates
        .where((t) => t.stremioBingeGroup == pin.bingeGroup)
        .length;
    final profileMatches = candidates
        .where((t) => t.stremioStreamKey == pin.streamKey)
        .length;
    _logPickerSelection('match', {
      'direct_results': _torrents.where((t) => t.isDirectStream).length,
      'addon_matches': candidates.length,
      'uses_binge_group': pin.bingeGroup?.isNotEmpty == true,
      'group_matches': groupMatches,
      'profile_matches': profileMatches,
      'saved_stream_index': pin.streamIndex,
      'matched_stream_index': _selectedDirect?.stremioStreamIndex,
      'reason': _selectedDirect != null
          ? 'matched'
          : candidates.isEmpty
          ? 'addon_configuration_not_found'
          : pin.bingeGroup?.isNotEmpty == true
          ? 'binge_group_not_found'
          : 'stream_identity_not_found',
    });
  }

  // Lazy rows have no Focus context until built. Walk the viewport until the
  // target mounts, then align precisely using its actual (variable) height.
  Future<void> _revealSelectedDirect({bool preserveFocus = false}) async {
    final run = ++_selectionFocusRun;
    final token = _searchToken;
    final target = _selectedDirect;
    if (target == null) {
      _logPickerSelection('reveal_skipped', {'reason': 'no_match'});
      return;
    }
    final index = _visible.indexOf(target);
    if (index < 0) {
      _logPickerSelection('reveal_skipped', {'reason': 'match_not_visible'});
      return;
    }
    _logPickerSelection('reveal_start');
    while (mounted &&
        run == _selectionFocusRun &&
        token == _searchToken &&
        (preserveFocus || !_streamFrozen)) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted ||
          run != _selectionFocusRun ||
          token != _searchToken ||
          (!preserveFocus && _streamFrozen) ||
          _filterFocus.hasFocus ||
          _pillFocus.hasFocus ||
          (!preserveFocus &&
              (_cinemaKey.currentState?.hasRailFocus ?? false)) ||
          index >= _nodes.length) {
        _logPickerSelection('reveal_skipped', {
          'reason': !mounted
              ? 'unmounted'
              : run != _selectionFocusRun
              ? 'newer_result_batch'
              : token != _searchToken
              ? 'new_search'
              : _streamFrozen
              ? 'user_interaction'
              : _filterFocus.hasFocus
              ? 'filter_focused'
              : _pillFocus.hasFocus
              ? 'new_results_focused'
              : (_cinemaKey.currentState?.hasRailFocus ?? false)
              ? 'sidebar_focused'
              : 'missing_focus_node',
        });
        return;
      }
      final rowContext = _nodes[index].context;
      if (rowContext != null && rowContext.mounted) {
        if (preserveFocus) _lastCinemaSource = index;
        if (widget.isTelevision && !preserveFocus) _nodes[index].requestFocus();
        await Scrollable.ensureVisible(rowContext, alignment: 0.3);
        _logPickerSelection('reveal_complete', {
          'focus_requested': widget.isTelevision && !preserveFocus,
        });
        return;
      }
      if (!_resultsScroll.hasClients) {
        _logPickerSelection('reveal_skipped', {
          'reason': 'scroll_not_attached',
        });
        return;
      }
      final position = _resultsScroll.position;
      final attached = <int>[
        for (var i = 0; i < _nodes.length; i++)
          if (_nodes[i].context != null) i,
      ];
      final backwards = attached.isNotEmpty && index < attached.first;
      final next =
          (position.pixels + (backwards ? -1 : 1) * position.viewportDimension)
              .clamp(position.minScrollExtent, position.maxScrollExtent);
      if (next == position.pixels) {
        _logPickerSelection('reveal_skipped', {
          'reason': 'scroll_boundary_before_row_mounted',
        });
        return;
      }
      position.jumpTo(next);
      WidgetsBinding.instance.ensureVisualUpdate();
    }
  }

  // --- redesign toolbar state (unused when _redesign is false) ---
  SourceToolbarState get _toolbar => _resultsSubscription.read().toolbar;
  TorrentFilterState get _filters => _toolbar.filters;
  String get _sortBy => _toolbar.sortBy;
  bool get _sortAsc => _toolbar.sortAsc;
  String? get _sourceFilter => _toolbar.sourceFilter;
  bool _disposedProviderFilter = false;

  late final ProviderSubscription<SourcePresentationSettings>
      _settingsSubscription;
  SourcePresentationSettings get _settings => _settingsSubscription.read();
  bool get _useAddonText => _settings.useAddonText;
  bool get _showAddonLogos => _settings.showAddonLogos;
  final _cinemaKey = GlobalKey<CinemaSourcesLayoutState>();
  int _lastCinemaSource = 0;

  /// D-pad anchor for the redesigned toolbar: the filter funnel. Pressing UP
  /// from the first row focuses this on TV so the remote can reach the toolbar
  /// (the list otherwise consumes UP and the toolbar is unreachable).
  final FocusNode _filterFocus = FocusNode(debugLabel: 'src_filter');

  /// Per-addon outcomes for the current search — every APPLICABLE Stremio
  /// addon, including failed and zero-result ones (which the result list
  /// alone makes invisible). Drives the status strip under the toolbar.
  List<AddonSearchStatus> get _addonStatuses =>
      _searchSubscription.read().addonStatuses;

  /// Addon ids with a retry in flight — their chip shows a spinner.
  late final ProviderSubscription<Set<String>> _retrySubscription;
  Set<String> get _retryingAddons => _retrySubscription.read();
  SourceRetryController get _retryController =>
      ref.read(sourceRetryProvider(_sourcesSession).notifier);

  /// The user's Quick Play "Addon Priority" order for this tab (empty =
  /// never customized = keep the shipped provider ordering). Also
  /// orders the source pills and their retry states.
  List<String> get _sourcePriority => _settings.priority.providers;
  Map<String, String> get _sourceAliases => _settings.priority.aliases;

  late final ProviderSubscription<SourceCacheState> _cacheSubscription;
  SourceCacheController get _cacheController =>
      ref.read(sourceCacheProvider(_sourcesSession).notifier);

  // --- streaming search: rows appear per engine as each one finishes, instead
  // of waiting for the slowest engine's timeout. ---
  late final ProviderSubscription<SourceSearchState> _searchSubscription;
  SourceSearchController get _searchController =>
      ref.read(sourceSearchProvider(_sourcesSession).notifier);
  bool get _searching => _searchSubscription.read().searching;
  bool _disposedSearching = false;

  /// Set on the first real interaction (drag scroll, row D-pad move, row menu,
  /// toolbar use). Frozen ⇒ later arrivals buffer into [_pendingTorrents]
  /// behind the "+N new sources" pill instead of reshuffling the list under
  /// the user's finger/focus.
  late final ProviderSubscription<SourceResultsState> _resultsSubscription;
  SourceResultsController get _resultsController =>
      ref.read(sourceResultsProvider(_sourcesSession).notifier);
  bool get _streamFrozen => _resultsSubscription.read().frozen;
  bool _disposedFrozen = false;
  int _disposedResultCount = 0;
  int _disposedMatchIndex = -1;

  /// Post-processed FULL result set waiting behind the pill while frozen.
  List<Torrent>? get _pendingTorrents => _resultsSubscription.read().pending;

  /// D-pad target for the "+N new sources" pill (UP from row 0 reaches it
  /// when visible; UP again reaches the toolbar funnel).
  final FocusNode _pillFocus = FocusNode(debugLabel: 'src_new_pill');

  /// Free-text keyword-bind mode: an editable query that seeds a pack search.
  bool get _keywordMode => widget.keywordSeed != null;
  late final TextEditingController _kwCtrl;
  String _query = '';

  // --- season scoping (pack-search mode: series, no specific episode) ---
  /// Currently selected season override; null = All Seasons (the selection's
  /// original whole-series/season scope).
  late final SourcesSession _sourcesSession;
  late final ProviderSubscription<SourceSeasonsState> _seasonsSubscription;
  SourceSeasonsController get _seasonsController =>
      ref.read(sourceSeasonsProvider(_sourcesSession).notifier);
  int? get _selectedSeason => _seasonsSubscription.read().selected;

  /// Seasons from the meta addon (authoritative). Empty until fetched; the
  /// chip menu falls back to [_derivedSeasons].
  List<int> get _availableSeasons => _seasonsSubscription.read().available;

  /// Seasons derived from the last UNSCOPED (All Seasons) result set's
  /// coverage info — the chip-menu fallback when the meta fetch fails. Only
  /// snapshotted on unscoped searches: a season-scoped result set is already
  /// filtered and would collapse the menu to the selected season.
  List<int> get _derivedSeasons => _seasonsSubscription.read().derived;

  /// Whether the "Season" scope chip applies: only for a series pack search
  /// (no specific episode), never in keyword mode.
  bool get _seasonChipVisible =>
      !_keywordMode &&
      widget.selection.isSeries &&
      widget.selection.episode == null;

  /// Monotonic guard so a slow earlier search can't clobber a newer one.
  int _searchToken = 0;

  /// Stremio-style redesigned presentation — now the default. Kept as a field
  /// (rather than inlined) so the classic-row branches remain an easy fallback.
  final bool _redesign = true;

  String get _imdbId => widget.selection.imdbId;
  bool get _isMovie => !widget.selection.isSeries;
  SeriesSource? _bindingFor(Torrent torrent) {
    for (final source in _bound) {
      if (source.isMediaServer && MediaServerService.bindingFor(torrent)?.bindingKey == source.bindingKey) return source;
      if (IptvSourceSearch.owns(torrent) &&
          source.isIptvDirect &&
          source.iptvPlaylistId == torrent.iptvPlaylistId &&
          source.iptvCatalogType == torrent.iptvCatalogType &&
          source.iptvEntryKey == torrent.iptvEntryKey) {
        return source;
      }
      if (torrent.isDirectStream &&
          source.matchesAddonDirect(
            candidateAddonKey: torrent.stremioAddonKey,
            candidateStreamKey: torrent.stremioStreamKey,
            candidateBingeGroup: torrent.stremioBingeGroup,
          )) {
        return source;
      }
      if (torrent.streamType == StreamType.torrent &&
          source.torrentHash.isNotEmpty &&
          source.torrentHash == torrent.infohash) {
        return source;
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _query = widget.keywordSeed ?? '';
    _kwCtrl = TextEditingController(text: _query);
    _sourcesSession = SourcesSession(
      owner: ProfileSessionMemory.captureOwner(),
      viewIdentity: Object(),
      selection: widget.selection,
      catalogItem: widget.meta.catalogItem,
      metadataAddonId: widget.meta.addonId,
      keywordMode: _keywordMode,
      contentType: widget.meta.contentType,
    );
    _seasonsSubscription = ref.listenManual(
      sourceSeasonsProvider(_sourcesSession),
      (previous, next) {
        if (mounted) setState(() {});
      },
    );
    _settingsSubscription = ref.listenManual(
      sourceSettingsProvider(_sourcesSession),
      (previous, next) {
        if (mounted) setState(() {});
      },
    );
    _savedSourcesSubscription = ref.listenManual(
      savedSourcesProvider(_sourcesSession),
      (previous, next) {
        if (!mounted) return;
        setState(() {
          if (next.cacheUnavailable) _logPickerSelection('cache_unavailable');
          _updateSelectedDirect();
          _logPickerSelection('saved_sources_loaded');
        });
      },
    );
    _cacheSubscription = ref.listenManual(
      sourceCacheProvider(_sourcesSession),
      (previous, next) {
        if (mounted && previous?.repaintRevision != next.repaintRevision) {
          setState(() {});
        }
      },
    );
    _retrySubscription = ref.listenManual(
      sourceRetryProvider(_sourcesSession),
      (previous, next) {
        if (mounted) setState(() {});
      },
    );
    _searchSubscription = ref.listenManual(
      sourceSearchProvider(_sourcesSession),
      (previous, next) {
        if (!mounted) return;
        setState(() {
          if (next.error != null || next.iptv.isNotEmpty) _loading = false;
        });
      },
    );
    _resultsSubscription = ref.listenManual(
      sourceResultsProvider(_sourcesSession),
      (previous, next) {
        if (!mounted) return;
        if (_sourcesSession.owner != ProfileSessionMemory.captureOwner()) {
          _visible = [];
          _syncStreamNodes();
        }
        setState(() {});
      },
    );
    _bindingSubscription = ref.listenManual(
      sourceBindingProvider(_sourcesSession),
      (previous, next) {},
    );
    // Rebuild the toolbar when the funnel gains/loses focus so its D-pad
    // highlight tracks — Focus alone doesn't guarantee a parent rebuild.
    _filterFocus.addListener(_onFilterFocusChanged);
    _loadCacheConfig();
    unawaited(_initializeSources());
    if (_seasonChipVisible) unawaited(_seasonsController.load());
  }

  Future<void> _initializeSources() async {
    // Priority must be known before the first engine batch lands. Loading it
    // beside the search and rebuilding afterwards used the toolbar's
    // user-interaction path, which froze streaming and parked every later
    // batch behind the "+N new sources" pill.
    await Future.wait([
      ref.read(sourceSettingsProvider(_sourcesSession).notifier).load(),
      _reloadBound(),
    ]);
    if (!mounted ||
        _sourcesSession.owner != ProfileSessionMemory.captureOwner()) {
      return;
    }
    await _runSearch();
  }

  List<int> _seasonMenuNumbers() => sourceSeasonMenu(
    available: _availableSeasons,
    derived: _derivedSeasons,
    selected: _selectedSeason,
  );

  /// The search scope: the incoming selection with the Season chip's override
  /// applied (season-only, episode stays null → season-pack search).
  AdvancedSearchSelection get _effectiveSelection {
    final base = widget.selection;
    if (!_seasonChipVisible || _selectedSeason == base.season) return base;
    return base.scopedToSeason(_selectedSeason);
  }

  @override
  void dispose() {
    _bindingSubscription.close();
    _disposedProviderFilter = _sourceFilter != null;
    _disposedFrozen = _streamFrozen;
    _disposedResultCount = _torrents.length;
    _disposedMatchIndex = _selectedDirect == null
        ? -1
        : _torrents.indexOf(_selectedDirect!);
    _resultsSubscription.close();
    _disposedSearching = _searching;
    _searchSubscription.close();
    _retrySubscription.close();
    _cacheSubscription.close();
    _disposedBoundCount = _bound.length;
    _savedSourcesSubscription.close();
    _settingsSubscription.close();
    _seasonsSubscription.close();
    _kwCtrl.dispose();
    _resultsScroll.dispose();
    _filterFocus.removeListener(_onFilterFocusChanged);
    _filterFocus.dispose();
    _pillFocus.dispose();
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  Future<void> _reloadBound() async {
    // Pin/unpin can finish after this route has left the Navigator.
    if (!mounted) return;
    await ref.read(savedSourcesProvider(_sourcesSession).notifier).reload();
  }

  /// Run the source search (free-text keyword pack search in keyword-bind mode,
  /// otherwise the IMDb-exact search) and rebuild the row focus nodes. Guarded
  /// by a token so a slow earlier re-search can't clobber a newer one's results
  /// or leak its focus nodes.
  Future<void> _runSearch() async {
    final token = ++_searchToken;
    // Search and cache/retry generations retire together; widgets retain the
    // token only for focus and row-adoption callbacks.
    _cacheController.beginSearch();
    _retryController.beginSearch();
    _resultsController.beginSearch();
    if (mounted) setState(() => _loading = true);
    for (final n in _nodes) {
      n.dispose();
    }
    _nodes.clear();
    // An IPTV status can expose the body before the first non-empty batch.
    // Never retain rows whose focus nodes were just disposed.
    _visible = [];
    await _searchController.search(
      SourceSearchRequest(
        selection: _effectiveSelection,
        keyword: _keywordMode ? _query : null,
        availableSeasons: _availableSeasons,
      ),
      priority: _sourcePriority,
      aliases: _sourceAliases,
      shouldContinue: () => mounted && token == _searchToken,
      onRows: (rows, complete) {
        if (!mounted || token != _searchToken) return;
        _presentStreaming(rows, token);
        if (complete) _finishSearch(token);
      },
      onBatchAccepted: (batch) {
        if (mounted && token == _searchToken) _maybeCheckCache(batch);
      },
    );
  }

  /// Post-processes a (provisional or final) raw result set exactly like the
  /// pre-streaming search did, then either applies it to the list or — when
  /// the user has started interacting ([_streamFrozen]) — parks it behind the
  /// "+N new sources" pill so rows never reshuffle mid-read.
  void _presentStreaming(List<Torrent> raw, int token) {
    if (!mounted || token != _searchToken) return;
    final prepared = prepareSourceResults(
      raw,
      selection: _effectiveSelection,
      bindMode: widget.bindMode,
      isIptvSource: IptvSourceSearch.owns,
      searching: _searching,
      cachedEpisodeSource: _cachedEpisodeSource,
      bound: _bound,
    );
    final torrents = prepared.torrents;
    if (prepared.cachedEpisodeInserted) {
      _logPickerSelection('cached_episode_inserted');
    }
    if (_resultsController.bufferIfFrozen(torrents)) {
      _logPickerSelection('batch_buffered', {
        'pending_results': torrents.length,
      });
      if (mounted) setState(() {}); // pill count / banner update
      return;
    }
    _applyStreamingResults(torrents);
  }

  /// Swaps the displayed result set, preserving the focused row BY IDENTITY
  /// across the reshuffle (a late engine can insert rows above the D-pad
  /// focus; without this the remote lands on a different torrent).
  void _applyStreamingResults(List<Torrent> torrents) {
    ++_selectionFocusRun;
    // Identity-preserving refocus only makes sense for USER-placed focus —
    // i.e. after a freeze (adopt-pending / toolbar paths). During live
    // streaming the only focus is the programmatic TV anchor on row 0;
    // following it by identity would drag the viewport down as better rows
    // insert above (review round: "the anchor is not user intent").
    Torrent? focusedTorrent;
    if (_streamFrozen) {
      for (var i = 0; i < _nodes.length && i < _visible.length; i++) {
        if (_nodes[i].hasFocus) {
          focusedTorrent = _visible[i];
          break;
        }
      }
    }
    _resultsController.display(torrents);
    _updateSelectedDirect();
    _showCachedEpisodeSource = torrents.any(
      (t) => identical(t, _cachedEpisodeSource),
    );
    _visible = _redesign ? _applyToolbar(_torrents) : _torrents;
    _syncStreamNodes();
    _logPickerSelection('focus_decision', {
      'reason': focusedTorrent != null
          ? 'preserve_user_focus'
          : _streamFrozen
          ? 'user_interaction'
          : _selectedDirect == null
          ? 'no_match'
          : !_visible.contains(_selectedDirect)
          ? 'match_filtered_or_deduplicated'
          : 'reveal_match',
    });
    if (mounted) {
      setState(() {
        _loading = false;
      });
    }
    if (focusedTorrent != null) {
      final idx = _visible.indexWhere(
        (t) =>
            identical(t, focusedTorrent) ||
            (t.hasRealInfoHash &&
                t.infohash.isNotEmpty &&
                t.infohash == focusedTorrent!.infohash),
      );
      if (idx >= 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && idx < _nodes.length) _nodes[idx].requestFocus();
        });
      }
    } else if (!_streamFrozen && _visible.contains(_selectedDirect)) {
      unawaited(_revealSelectedDirect());
    } else if (widget.isTelevision && !_streamFrozen) {
      // Live streaming on TV: keep the remote anchored to the TOP row (the
      // best-ranked source right now) — the anchor exists from the first
      // batch instead of waiting for the slowest engine.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            _nodes.isEmpty ||
            _streamFrozen ||
            _visible.contains(_selectedDirect)) {
          return;
        }
        if (_filterFocus.hasFocus ||
            _pillFocus.hasFocus ||
            (_cinemaKey.currentState?.hasRailFocus ?? false)) {
          return;
        }
        _nodes.first.requestFocus();
      });
    }
  }

  /// Grows/shrinks [_nodes] to match [_visible] without ever disposing the
  /// focused node unanchored. Removed nodes are disposed POST-FRAME — their
  /// row widgets are still mounted this frame, and unmounting a Focus widget
  /// whose node is already disposed asserts (same rule _rebuildVisible
  /// documents).
  void _syncStreamNodes() {
    while (_nodes.length < _visible.length) {
      _nodes.add(FocusNode(debugLabel: 'src_${_nodes.length}'));
    }
    if (_nodes.length > _visible.length) {
      final removed = <FocusNode>[];
      while (_nodes.length > _visible.length) {
        final node = _nodes.removeLast();
        if (node.hasFocus && _nodes.isNotEmpty) _nodes.last.requestFocus();
        removed.add(node);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final node in removed) {
          node.dispose();
        }
      });
    }
  }

  /// Completion-only steps: season snapshot, cache badges, TV focus anchor.
  void _finishSearch(int token) {
    if (!mounted || token != _searchToken) return;
    final sel = _effectiveSelection;
    // Snapshot the chip-menu fallback seasons from unscoped results only —
    // a season-scoped set is already filtered and would collapse the menu.
    // Use the FULL set even when part of it is parked behind the pill.
    final fullSet = _pendingTorrents ?? _torrents;
    if (_seasonChipVisible && sel.season == null) {
      _seasonsController.acceptResults(fullSet, unscoped: true);
    }
    // A source-group pill selected for a previous search may not exist in the
    // new result set — checked ONLY here, against the authoritative full set:
    // an early batch that merely hasn't delivered that source yet must not
    // silently clear the user's filter mid-stream.
    if (_resultsController.reconcileProvider(fullSet, _sourceAliases)) {
      if (_pendingTorrents == null) {
        _visible = _redesign ? _applyToolbar(_torrents) : _torrents;
        _syncStreamNodes();
      }
    }
    // Final result set: sweep any hash not yet dispatched by a streaming batch
    // (non-blocking). In-flight batch checks share this generation and merge as
    // they land, so already-shown badges never flicker off.
    setState(() {
      _loading = false;
    });
    _maybeCheckCache();
    // On TV give the D-pad an initial anchor when nothing is focused yet.
    // With ZERO rows (e.g. a season scope with no packs) anchor the filter
    // funnel instead so the remote can still reach the toolbar and recover.
    // Never steal focus the user already placed somewhere mid-stream.
    if (widget.isTelevision) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_visible.contains(_selectedDirect) ||
            _nodes.any((n) => n.hasFocus) ||
            _filterFocus.hasFocus ||
            _pillFocus.hasFocus ||
            (_cinemaKey.currentState?.hasRailFocus ?? false)) {
          return;
        }
        if (_nodes.isNotEmpty) {
          _nodes.first.requestFocus();
        } else if (_seasonChipVisible || _hasRetryableAddon) {
          _filterFocus.requestFocus();
        }
      });
    }
  }

  /// First real user interaction → stop live-reshuffling; buffer new arrivals
  /// behind the pill instead.
  void _freezeStreaming() {
    ++_selectionFocusRun;
    _resultsController.freeze();
  }

  int get _pendingNewCount => _resultsSubscription.read().pendingNewCount;

  /// Folds the parked result set into the list (pill tap / toolbar use) and
  /// refreshes the ⚡ badges for the fresh rows.
  void _adoptPending() {
    final p = _pendingTorrents;
    if (p == null) return;
    _applyStreamingResults(p);
    // Parked rows were already badged as their batches streamed in; this is a
    // cheap additive mop-up for any straggler hash (skips already-checked).
    _maybeCheckCache();
  }

  void _submitKeyword(String q) {
    final trimmed = q.trim();
    if (trimmed.isEmpty || trimmed == _query) return;
    _query = trimmed;
    _runSearch();
  }

  late final ProviderSubscription<bool> _bindingSubscription;

  void _play(Torrent t, int i) {
    // Swallow a SELECT that leaks through as the row menu / provider picker
    // closes on TV (armed via DialogTapGuard.markKeyAction in the menu).
    if (DialogTapGuard.shouldIgnoreTap()) return;
    _playNow(t, i);
  }

  void _playNow(Torrent t, int i) {
    _freezeStreaming();
    unawaited(
      TorrentPlaybackService.activateTorrent(
        context,
        t,
        forcePlay: widget.forcePlayOnTap,
        meta: widget.meta,
        // The rendered list — [_visible] equals [_torrents] with the redesign
        // off, but is the source-filtered/sorted list when on, so the index and
        // the in-player Sources switcher stay in sync with what the user sees.
        sources: _visible,
        sourceIndex: i,
        searchKeyword: widget.selection.title,
      ).then((_) => _reloadBound()),
    );
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  bool _hasDeferredEpisodeTarget(Torrent torrent) =>
      torrent.seasonNumber != null &&
      RegExp(
        r'^S\d+E\d+$',
        caseSensitive: false,
      ).hasMatch(torrent.episodeIdentifier ?? '');

  bool _canCopySource(Torrent torrent) =>
      torrent.copyLink != null ||
      (IptvSourceSearch.isDeferredXtreamSeries(torrent) &&
          _hasDeferredEpisodeTarget(torrent));

  Future<void> _copySourceLink(Torrent torrent) async {
    if (IptvSourceSearch.isDeferredXtreamSeries(torrent)) {
      if (!_hasDeferredEpisodeTarget(torrent)) {
        _snack('Choose an episode before copying its IPTV link.');
        return;
      }
      _snack('Finding this IPTV episode…');
      final resolution = await IptvSourceSearch.resolveXtreamSeriesEpisode(
        torrent,
      );
      if (!mounted) return;
      if (resolution.source == null) {
        _snack(
          resolution.status == IptvEpisodeResolutionStatus.missing
              ? '${torrent.episodeIdentifier ?? 'This episode'} is not available in this IPTV series.'
              : 'Could not check this IPTV series. Try again.',
        );
        return;
      }
      torrent = resolution.source!;
    }
    final link = torrent.copyLink;
    if (link == null) {
      _snack('No link available for this source.');
      return;
    }
    await Clipboard.setData(ClipboardData(text: link));
    if (mounted) _snack('Link copied to clipboard');
  }

  Future<void> _pin(Torrent t) async {
    if (t.isExternalStream) {
      _snack("External links can't be pinned as a playback source.");
      return;
    }
    await _bindSource(
      (saveBinding) => IptvSourceSearch.owns(t)
          ? TorrentPlaybackService.bindIptvSource(
              context,
              t,
              imdbId: _imdbId,
              isMovie: _isMovie,
              saveBinding: saveBinding,
            )
          : t.isDirectStream
          ? TorrentPlaybackService.bindDirectSource(
              context,
              t,
              imdbId: _imdbId,
              isMovie: _isMovie,
              saveBinding: saveBinding,
              addonCatalogId: widget.selection.stremioCatalogId,
              addonCatalogKey: widget.selection.stremioAddonKey,
            )
          : TorrentPlaybackService.bindSource(
              context,
              t,
              imdbId: _imdbId,
              isMovie: _isMovie,
              saveBinding: saveBinding,
              addonCatalogId: widget.selection.stremioCatalogId,
              addonCatalogKey: widget.selection.stremioAddonKey,
            ),
    );
  }

  Future<void> _unpin(SeriesSource source) async {
    if (!mounted) return;
    await ref
        .read(savedSourcesProvider(_sourcesSession).notifier)
        .remove(source);
  }

  Future<void> _pinLocal() => _bindSource(
    (saveBinding) => TorrentPlaybackService.bindLocalSource(
      context,
      imdbId: _imdbId,
      isMovie: _isMovie,
      saveBinding: saveBinding,
      title: widget.selection.title,
      year: widget.selection.year,
    ),
  );

  Future<void> _bindSource(SourceBindingOperation operation) async {
    if (!mounted) return;
    final ready = await ref
        .read(sourceBindingProvider(_sourcesSession).notifier)
        .bind(operation, viewIsActive: () => mounted);
    if (ready &&
        widget.bindMode &&
        mounted &&
        _sourcesSession.owner == ProfileSessionMemory.captureOwner()) {
      Navigator.of(context).pop();
    }
  }

  void _showRowMenu(Torrent t, int i) {
    _freezeStreaming();
    final app = AppThemeScope.of(context);
    final binding = _bindingFor(t);
    final stream = t.isDirectStream || t.isExternalStream;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: app.home.sheetBg,
      builder: (_) => SourceRowActionsSheet(
        app: app,
        kind: !stream
            ? SourceRowActionKind.torrent
            : t.isExternalStream
            ? SourceRowActionKind.external
            : MediaServerService.owns(t)
            ? SourceRowActionKind.mediaServer
            : IptvSourceSearch.owns(t)
            ? SourceRowActionKind.iptv
            : SourceRowActionKind.addon,
        bound: binding != null,
        onPlay: () => _playNow(t, i),
        onTogglePin: t.isExternalStream
            ? null
            : () => unawaited(binding != null ? _unpin(binding) : _pin(t)),
        onCopy: stream || _canCopySource(t)
            ? () => unawaited(_copySourceLink(t))
            : null,
        onDownload:
            stream &&
                ProfilePolicyGuard.allowsSync(ProfileFeature.downloads) &&
                TorrentPlaybackService.supportsDirectStreamDownload(t)
            ? () => unawaited(
                TorrentPlaybackService.downloadDirectStream(context, t),
              )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final cinema = useCinemaSourcesLayout(
          constraints,
          isTelevision: widget.isTelevision,
        );
        return Scaffold(
          backgroundColor: scheme.surface,
          appBar: cinema
              ? null
              : AppBar(
                  title: Text(
                    _keywordMode
                        ? 'Find a source for ${widget.selection.title}'
                        : widget.bindMode
                        ? 'Pick a source for ${widget.selection.title}'
                        : widget.selection.formattedLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  actions: [
                    // Pin an on-device file/folder as the source. Desktop only — hidden on
                    // Android/iOS (incl. Android TV) where local binding is unavailable, so
                    // it's never a dead-end D-pad stop.
                    if (_imdbId.isNotEmpty &&
                        TorrentPlaybackService.localBindingAvailable)
                      IconButton(
                        tooltip: 'Pin an on-device file or folder',
                        icon: const Icon(Icons.folder_open_rounded),
                        onPressed: () => unawaited(_pinLocal()),
                      ),
                  ],
                ),
          body: cinema
              ? SafeArea(
                  child: CinemaSourcesLayout(
                    key: _cinemaKey,
                    contextTitle: _keywordMode
                        ? _query
                        : widget.selection.title,
                    contextLabel: !_keywordMode && widget.selection.isSeries
                        ? widget.selection.formattedLabel
                        : null,
                    art: _keywordMode
                        ? null
                        : widget.meta.art ??
                              PlayLoaderArt(
                                posterUrl: widget.meta.posterUrl,
                                yearLabel: widget.selection.year,
                              ),
                    title: _keywordMode
                        ? 'Search results'
                        : widget.bindMode
                        ? 'Pick a source'
                        : 'Choose a source',
                    subtitle: _keywordMode
                        ? 'Find a source for ${widget.selection.title}'
                        : widget.selection.formattedLabel,
                    onBack: () => Navigator.of(context).maybePop(),
                    backLabel: _keywordMode ? 'Back' : 'Details',
                    headerAction:
                        _imdbId.isNotEmpty &&
                            TorrentPlaybackService.localBindingAvailable
                        ? IconButton(
                            tooltip: 'Pin an on-device file or folder',
                            icon: const Icon(Icons.folder_open_rounded),
                            onPressed: () => unawaited(_pinLocal()),
                          )
                        : null,
                    providers: _cinemaProviders,
                    selectedProvider: _sourceFilter,
                    onProviderSelected: _selectCinemaProvider,
                    onFocusResults: () {
                      if (_nodes.isNotEmpty) {
                        _nodes[_lastCinemaSource.clamp(0, _nodes.length - 1)]
                            .requestFocus();
                      } else if (_filterFocus.context != null) {
                        _filterFocus.requestFocus();
                      }
                    },
                    isSourceFocused: () {
                      final index = _nodes.indexWhere((node) => node.hasFocus);
                      if (index >= 0) {
                        _lastCinemaSource = index;
                        _freezeStreaming();
                      }
                      return index >= 0;
                    },
                    resultCount: _visible.length,
                    searching: _loading || _searching,
                    failed: _error != null,
                    isTelevision: widget.isTelevision,
                    child: _sourcesBody(scheme, cinema: true),
                  ),
                )
              : _sourcesBody(scheme),
        );
      },
    );
  }

  List<CinemaSourceProvider> get _cinemaProviders {
    final counts = <String, int>{};
    final names = <String, String>{};
    for (final status in _addonStatuses) {
      names.putIfAbsent(status.sourceKey, () => status.name);
    }
    for (final t in _torrents) {
      final key = SourcePriority.keyForSource(
        t.source,
        aliases: _sourceAliases,
      );
      counts[key] = (counts[key] ?? 0) + 1;
      names.putIfAbsent(
        key,
        () => t.addonDisplayName ?? _providerLabel(t.source),
      );
    }
    for (final source in _iptvSources) {
      names[source.key] = 'IPTV · ${source.name}';
    }
    final iptvMessages = {
      for (final source in _iptvSources)
        if (source.retryableFailure) source.key: source.message,
    };
    final keys = SourcePriority.orderBy(
      names.keys.toList()..sort(),
      (key) => key,
      _sourcePriority,
      aliases: _sourceAliases,
    );
    return [
      CinemaSourceProvider(
        id: null,
        label: 'All sources',
        count: _torrents.length,
      ),
      for (final key in keys)
        CinemaSourceProvider(
          id: key,
          label: names[key]!.isEmpty ? 'Other sources' : names[key]!,
          count: counts[key] ?? 0,
          message: iptvMessages[key] ?? _mediaServerMessages[key],
          failed: _addonStatuses.any((s) => s.sourceKey == key && s.failed),
          loading: _addonStatuses.any(
            (s) => s.sourceKey == key && _retryingAddons.contains(s.requestKey),
          ),
        ),
    ];
  }

  Map<String, String> get _mediaServerMessages => {
    for (final status in _addonStatuses)
      if (status.sourceKey.startsWith('mediaserver:') && status.error != null)
        status.sourceKey: status.error!,
  };

  void _selectCinemaProvider(String? key) {
    _resultsController.selectProvider(key);
    _lastCinemaSource = 0;
    // The rail returns to row zero after changing providers. Mount that row
    // before Right can request its focus; a lazy list left at the previous
    // provider's offset has no attached focus target at index zero.
    if (_resultsScroll.hasClients) _resultsScroll.jumpTo(0);
    _rebuildVisible();
    if (_visible.contains(_selectedDirect)) {
      unawaited(_revealSelectedDirect(preserveFocus: true));
    }
    for (final status in _addonStatuses) {
      if (status.sourceKey == key && _statusActionable(status)) {
        unawaited(_retryAddon(status));
      }
    }
  }

  Widget _sourcesBody(ColorScheme scheme, {bool cinema = false}) => Column(
    children: [
      if (_keywordMode)
        SourceKeywordField(
          scheme: scheme,
          controller: _kwCtrl,
          onSubmitted: _submitKeyword,
        ),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? _centered(scheme, 'Search failed.\n$_error')
            : Column(
                children: [
                  if (_redesign && !_keywordMode && !cinema)
                    SourceTitleHeader(
                      title: widget.selection.title,
                      subtitle: widget.selection.formattedLabel,
                      poster: widget.meta.posterUrl,
                    ),
                  // Keep the toolbar when a season scope is available even
                  // with zero results — otherwise a no-result season would
                  // strand the user with no way to switch back.
                  if (_redesign &&
                      (_torrents.isNotEmpty ||
                          _seasonChipVisible ||
                          _iptvSources.isNotEmpty ||
                          _hasRetryableAddon))
                    _redesignToolbar(scheme, showProviders: !cinema),
                  if (_searching && !cinema) _searchingStrip(),
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: _visible.isEmpty
                              ? _centered(
                                  scheme,
                                  _torrents.isEmpty
                                      ? 'No sources found.'
                                      : 'No matches for your filters.',
                                )
                              : NotificationListener<ScrollNotification>(
                                  // A user drag (not the programmatic
                                  // ensureVisible scrolls) freezes live
                                  // reshuffling.
                                  onNotification: (n) {
                                    if (n is ScrollStartNotification &&
                                        n.dragDetails != null) {
                                      _freezeStreaming();
                                    }
                                    return false;
                                  },
                                  child: SourceListScrollAnchor(
                                    child: ListView.builder(
                                      controller: _resultsScroll,
                                      padding: EdgeInsets.symmetric(
                                        // Spotlight expands the focused
                                        // SourceRow beyond its layout box.
                                        // At the top of the list there is no
                                        // negative scroll extent to reveal
                                        // it, so reserve TV focus room here.
                                        vertical: widget.isTelevision ? 24 : 8,
                                        horizontal: _redesign ? 10 : 0,
                                      ),
                                      cacheExtent: 1200,
                                      itemCount: _visible.length,
                                      itemBuilder: (context, i) {
                                        final t = _visible[i];
                                        if (_redesign) {
                                          return _redesignRow(
                                            t,
                                            i,
                                            cinema: cinema,
                                          );
                                        }
                                        return TorrentResultRow(
                                          torrent: t,
                                          index: i,
                                          focusNode: _nodes[i],
                                          isTelevision: widget.isTelevision,
                                          qualityTier: t.qualityTier,
                                          onTap: () {
                                            if (widget.bindMode) {
                                              unawaited(_pin(t));
                                            } else {
                                              _play(t, i);
                                            }
                                          },
                                          onLongPress: () => _showRowMenu(t, i),
                                          onCopyMagnet: !_canCopySource(t)
                                              ? null
                                              : () => unawaited(
                                                  _copySourceLink(t),
                                                ),
                                          onNavigateUp: () {
                                            _freezeStreaming();
                                            if (i > 0) {
                                              _nodes[i - 1].requestFocus();
                                            } else if (_pendingNewCount > 0) {
                                              _pillFocus.requestFocus();
                                            }
                                          },
                                          onNavigateDown: () {
                                            _freezeStreaming();
                                            if (i < _nodes.length - 1) {
                                              _nodes[i + 1].requestFocus();
                                            }
                                          },
                                        );
                                      },
                                    ),
                                  ),
                                ),
                        ),
                        // Frozen-mode arrivals wait behind this pill so
                        // the list never reshuffles under the user.
                        if (_pendingNewCount > 0)
                          Positioned(
                            top: 10,
                            left: 0,
                            right: 0,
                            child: Center(child: _newSourcesPill()),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    ],
  );

  /// Whether a chip is worth pressing: a failed addon retries, and a
  /// zero-result addon re-asks (transient upstream failures often read as
  /// empty rather than as an error).
  bool _statusActionable(AddonSearchStatus s) => s.failed || s.count == 0;

  bool get _hasRetryableAddon => _addonStatuses.any(_statusActionable);

  /// Re-fetch ONE addon and fold whatever it returns into the list through
  /// the normal streaming-merge path — so retry results respect the same
  /// dedupe, series-pack post-processing, and the frozen-list "+N new
  /// sources" pill as any live batch.
  Future<void> _retryAddon(AddonSearchStatus status) async {
    if (status.sourceKey.startsWith('mediaserver:')) {
      if (!_searching) await _runSearch();
      return;
    }
    final token = _searchToken;
    final batch = await _retryController.retry(_effectiveSelection, status);
    if (batch == null || !mounted || token != _searchToken) return;
    final rows = _searchController.acceptRetry(status, batch);
    if (rows == null) return;
    _presentStreaming(rows, token);
    _maybeCheckCache(batch);
  }

  /// Slim "still searching" strip under the toolbar while engines are in
  /// flight — rows are already usable, this just says more may arrive.
  Widget _searchingStrip() {
    final app = AppThemeScope.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      child: Row(
        children: [
          const SizedBox(
            width: 11,
            height: 11,
            child: CircularProgressIndicator(strokeWidth: 1.6),
          ),
          const SizedBox(width: 8),
          Text(
            'Still searching sources…',
            style: TextStyle(
              fontSize: 11.5,
              color: app.fade(app.core.tx, 0.55),
            ),
          ),
        ],
      ),
    );
  }

  Widget _newSourcesPill() => SourcePendingResultsPill(
    count: _pendingNewCount,
    focusNode: _pillFocus,
    onAdopt: _adoptPending,
    onNavigateDown: () {
      if (_nodes.isNotEmpty) _nodes.first.requestFocus();
    },
    onNavigateUp: () {
      // Classic has no attached toolbar funnel: preserve normal key bubbling.
      if (_filterFocus.context == null) return false;
      _filterFocus.requestFocus();
      return true;
    },
  );

  /// Derives the rendered list from [_torrents]: source-group filter →
  /// quality/rip/language filter → provider priority + stable dedupe →
  /// optional explicit field sort. "Addon order" is the default.
  List<Torrent> _applyToolbar(List<Torrent> src) =>
      _resultsController.project(src, _settings.priority);

  /// Recompute [_visible] and rebuild [_nodes] in lock-step after a toolbar
  /// change (source pill, sort, or filter). The ListView stays mounted (no
  /// loading flip), so the old nodes are disposed AFTER the rebuild frame —
  /// letting each reused row State and its Focus widget migrate onto the new
  /// node first (disposing mid-frame would assert / drop the listener).
  ///
  /// Deliberately does NOT move D-pad focus: this is always triggered from a
  /// toolbar control (pill / sort / funnel) which keeps its own focus. Yanking
  /// focus into the list would both disorient the user AND let the SELECT that
  /// triggered the change land on the newly-focused first row — activating it
  /// (adding the first result to the debrid) as an unwanted "double tap".
  void _rebuildVisible() {
    // Toolbar use is a deliberate reshuffle: freeze live streaming updates
    // and fold any parked arrivals in first, so the user filters/sorts the
    // complete set they can see.
    _freezeStreaming();
    if (_pendingTorrents != null) {
      _resultsController.display(_pendingTorrents!);
      _maybeCheckCache();
    }
    final old = List<FocusNode>.from(_nodes);
    _nodes.clear();
    _visible = _applyToolbar(_torrents);
    _updateSelectedDirect();
    for (var i = 0; i < _visible.length; i++) {
      _nodes.add(FocusNode(debugLabel: 'src_$i'));
    }
    if (mounted) setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final n in old) {
        n.dispose();
      }
    });
  }

  /// The redesigned toolbar: source-group pills + sort + filter funnel, then the
  /// active-filter pills row when filters are applied.
  Widget _redesignToolbar(ColorScheme scheme, {bool showProviders = true}) {
    final app = AppThemeScope.of(context);
    final accent = app.home.chromeAccent;
    final line = app.fade(app.core.tx, 0.08);
    final dim = app.fade(app.core.tx, 0.55);

    final sources = <String>{
      for (final t in _torrents)
        if (t.source.isNotEmpty) t.source,
    };
    final labelsByKey = <String, String>{
      for (final status in _addonStatuses) status.sourceKey: status.name,
    };
    final sourceByKey = <String, String>{
      for (final source in sources.toList()..sort())
        SourcePriority.keyForSource(source, aliases: _sourceAliases): source,
      for (final source in _iptvSources) source.key: source.key,
    };
    for (final torrent in _torrents) {
      final key = SourcePriority.keyForSource(
        torrent.source,
        aliases: _sourceAliases,
      );
      labelsByKey.putIfAbsent(
        key,
        () => torrent.addonDisplayName ?? _providerLabel(torrent.source),
      );
    }
    for (final source in _iptvSources) {
      labelsByKey[source.key] = 'IPTV · ${source.name}';
    }
    final retryByKey = <String, AddonSearchStatus>{
      for (final status in _addonStatuses)
        if (_statusActionable(status) &&
            !sourceByKey.containsKey(status.sourceKey))
          status.sourceKey: status,
    };
    final providerKeys = <String>[
      ...sourceByKey.keys,
      for (final key in retryByKey.keys)
        if (!sourceByKey.containsKey(key)) key,
    ];
    final sortedKeys = SourcePriority.orderBy(
      providerKeys,
      (key) => key,
      _sourcePriority,
      aliases: _sourceAliases,
    );

    Widget pill({
      required String key,
      required Widget child,
      required bool on,
      required VoidCallback? onTap,
    }) => Padding(
      key: ValueKey(key),
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: on ? accent : app.fade(app.core.tx, 0.05),
        borderRadius: app.shape.brPill,
        child: InkWell(
          borderRadius: app.shape.brPill,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
            child: child,
          ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showProviders && (sortedKeys.length > 1 || retryByKey.isNotEmpty ||
            _iptvSources.any((s) => s.retryableFailure)))
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              children: [
                if (sourceByKey.isNotEmpty)
                  pill(
                    key: 'source-pill-all',
                    on: _sourceFilter == null,
                    onTap: () {
                      _resultsController.selectProvider(null);
                      _rebuildVisible();
                    },
                    child: Text(
                      'All',
                      style: TextStyle(
                        color: _sourceFilter == null ? app.inkOn(accent) : dim,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                for (final key in sortedKeys)
                  if (retryByKey[key] case final status?)
                    pill(
                      key: 'source-pill-$key',
                      on: false,
                      onTap: () => unawaited(_retryAddon(status)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 110),
                            child: Text(
                              status.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: status.failed
                                    ? Theme.of(context).colorScheme.error
                                    : dim,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 5),
                          if (_retryingAddons.contains(status.requestKey))
                            const SizedBox.square(
                              dimension: 11,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                              ),
                            )
                          else
                            Icon(
                              Icons.refresh_rounded,
                              size: 14,
                              color: status.failed
                                  ? Theme.of(context).colorScheme.error
                                  : dim,
                            ),
                        ],
                      ),
                    )
                  else if (sourceByKey[key] case final source?)
                    pill(
                      key: 'source-pill-$key',
                      on: _sourceFilter == key,
                      onTap: () {
                        _resultsController.selectProvider(key);
                        _rebuildVisible();
                      },
                      child: Text(
                        labelsByKey[key] ?? _providerLabel(source),
                        style: TextStyle(
                          color: _sourceFilter == key ? app.inkOn(accent) : dim,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
              ],
            ),
          ),
        if (showProviders)
          for (final entry in _mediaServerMessages.entries)
            if (_sourceFilter == null || _sourceFilter == entry.key)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
                child: Text(entry.value,
                    style: TextStyle(color: scheme.error, fontSize: 12)),
              ),
        if (showProviders)
          for (final source in _iptvSources)
            if (source.retryableFailure &&
                (_sourceFilter == null || _sourceFilter == source.key))
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
                child: Text('IPTV · ${source.name}: ${source.message}',
                  style: TextStyle(color: scheme.error, fontSize: 12)),
              ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
          child: Row(
            children: [
              // Season scope (pack-search mode): narrows the search to one
              // season's packs, like the old Home's season dropdown.
              if (_seasonChipVisible)
                PopupMenuButton<int>(
                  initialValue: _selectedSeason ?? 0,
                  tooltip: 'Season',
                  color: const Color(0xFF1E1B2C),
                  onSelected: (v) {
                    final next = v == 0 ? null : v;
                    if (!_seasonsController.select(next)) return;
                    unawaited(_runSearch());
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 0, child: Text('All Seasons')),
                    for (final s in _seasonMenuNumbers())
                      PopupMenuItem(value: s, child: Text('Season $s')),
                  ],
                  child: _tbChip(
                    _selectedSeason != null ? accent : line,
                    dim,
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: 'Season  ',
                            style: TextStyle(color: dim),
                          ),
                          TextSpan(
                            text: _selectedSeason == null
                                ? 'All'
                                : '$_selectedSeason',
                            style: const TextStyle(color: Color(0xFFF1F1F6)),
                          ),
                        ],
                      ),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              const Spacer(),
              PopupMenuButton<String>(
                initialValue: _sortBy,
                tooltip: 'Sort',
                color: const Color(0xFF1E1B2C),
                onSelected: (v) {
                  _resultsController.selectSort(v);
                  _rebuildVisible();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'source', child: Text('Addon order')),
                  PopupMenuItem(value: 'name', child: Text('Name')),
                  PopupMenuItem(value: 'size', child: Text('Size')),
                  PopupMenuItem(value: 'seeders', child: Text('Seeders')),
                  PopupMenuItem(value: 'date', child: Text('Date')),
                ],
                child: _tbChip(
                  line,
                  dim,
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: 'Sort  ',
                          style: TextStyle(color: dim),
                        ),
                        TextSpan(
                          text: _sortLabel(_sortBy),
                          style: const TextStyle(color: Color(0xFFF1F1F6)),
                        ),
                      ],
                    ),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              if (_sortBy != 'source')
                InkWell(
                  borderRadius: app.shape.br(9),
                  onTap: () {
                    _resultsController.toggleSortDirection();
                    _rebuildVisible();
                  },
                  child: _tbChip(
                    line,
                    dim,
                    Icon(
                      _sortAsc
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded,
                      size: 16,
                      color: dim,
                    ),
                  ),
                ),
              const SizedBox(width: 6),
              Focus(
                focusNode: _filterFocus,
                onKeyEvent: (node, event) {
                  if (event is! KeyDownEvent) return KeyEventResult.ignored;
                  if (isActivateKey(event.logicalKey)) {
                    unawaited(_openFilters());
                    return KeyEventResult.handled;
                  }
                  // DOWN returns to pending arrivals first, then the list;
                  // the funnel is the toolbar anchor.
                  if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                    if (_pendingNewCount > 0) {
                      _pillFocus.requestFocus();
                    } else if (_nodes.isNotEmpty) {
                      _nodes.first.requestFocus();
                    }
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: Builder(
                  builder: (_) {
                    final focused = _filterFocus.hasFocus;
                    final tint = (!_filters.isEmpty || focused) ? accent : dim;
                    return InkWell(
                      borderRadius: app.shape.br(9),
                      // The outer Focus is the sole focus target; don't let the
                      // InkWell add a competing node that breaks D-pad traversal.
                      canRequestFocus: false,
                      onTap: _openFilters,
                      child: _tbChip(
                        focused || !_filters.isEmpty ? accent : line,
                        dim,
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.filter_list_rounded,
                              size: 16,
                              color: tint,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              'Filter',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: tint,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        if (!_filters.isEmpty) _activeFilterPills(accent, dim),
      ],
    );
  }

  Widget _tbChip(Color border, Color fg, Widget child) {
    final app = AppThemeScope.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: app.fade(app.core.tx, 0.05),
        border: Border.all(color: border),
        borderRadius: app.shape.br(9),
      ),
      child: child,
    );
  }

  Widget _activeFilterPills(Color accent, Color dim) {
    final app = AppThemeScope.of(context);
    final labels = <String>[
      for (final q in _filters.qualities) 'Quality · ${_qualityFilterLabel(q)}',
      for (final r in _filters.ripSources) 'Source · ${_ripFilterLabel(r)}',
      for (final l in _filters.languages) 'Lang · ${_langFilterLabel(l)}',
      for (final s in _filters.sizes) 'Size · ${_sizeFilterLabel(s)}',
      for (final d in _filters.dynamicRanges) 'Range · ${_rangeFilterLabel(d)}',
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Wrap(
        spacing: 7,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final l in labels)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: app.fade(app.core.tx, 0.06),
                border: Border.all(color: app.fade(app.core.tx, 0.08)),
                borderRadius: app.shape.brPill,
              ),
              child: Text(
                l,
                style: TextStyle(
                  color: dim,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          InkWell(
            onTap: () {
              _resultsController.setFilters(const TorrentFilterState.empty());
              _rebuildVisible();
            },
            child: Text(
              'Clear',
              style: TextStyle(
                color: accent,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _onFilterFocusChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadCacheConfig() async {
    if (await _cacheController.configure() && mounted) _maybeCheckCache();
  }

  void _maybeCheckCache([List<Torrent>? rows]) {
    if (!mounted || !_redesign) return;
    unawaited(_cacheController.check(rows ?? _torrents));
  }

  String? _cacheLabel(Torrent torrent) =>
      _cacheSubscription.read().label(torrent);

  Future<void> _openFilters() async {
    final result = await showDialog<TorrentFilterState>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: TorrentFiltersSheet(
          initialState: _filters,
          sizeNote: widget.selection.isSeries
              ? 'Not applied to series — pack sizes are per-episode.'
              : 'Applies to movies only — ignored for series.',
        ),
      ),
    );
    if (!mounted || result == null || result == _filters) return;
    _resultsController.setFilters(result);
    _rebuildVisible();
  }

  String _providerLabel(String s) {
    for (final source in _iptvSources) {
      if (source.key == s) return 'IPTV · ${source.name}';
    }
    return _prettySource(s);
  }

  static String _prettySource(String s) {
    final v = s.startsWith('stremio:') ? s.substring(8) : s;
    return v.isEmpty ? s : v[0].toUpperCase() + v.substring(1);
  }

  static String _sortLabel(String v) => switch (v) {
    'name' => 'Name',
    'size' => 'Size',
    'seeders' => 'Seeders',
    'date' => 'Date',
    _ => 'Addon order',
  };

  static String _qualityFilterLabel(QualityTier q) => switch (q) {
    QualityTier.ultraHd => '4K',
    QualityTier.fullHd => '1080p',
    QualityTier.hd => '720p',
    QualityTier.sd => '480p',
  };

  static String _ripFilterLabel(RipSourceCategory r) => switch (r) {
    RipSourceCategory.web => 'WEB',
    RipSourceCategory.bluRay => 'BluRay',
    RipSourceCategory.hdrip => 'HDRip',
    RipSourceCategory.dvdrip => 'DVDRip',
    RipSourceCategory.cam => 'CAM',
    RipSourceCategory.other => 'Other',
  };

  static String _langFilterLabel(AudioLanguage l) =>
      l.name[0].toUpperCase() + l.name.substring(1);

  static String _sizeFilterLabel(SizeBucket s) => switch (s) {
    SizeBucket.under500mb => '< 500 MB',
    SizeBucket.mb500to1gb => '500 MB – 1 GB',
    SizeBucket.gb1to1p5 => '1 – 1.5 GB',
    SizeBucket.gb1p5to2p5 => '1.5 – 2.5 GB',
    SizeBucket.gb2p5to4 => '2.5 – 4 GB',
    SizeBucket.gb4to6 => '4 – 6 GB',
    SizeBucket.gb6to10 => '6 – 10 GB',
    SizeBucket.gb10to20 => '10 – 20 GB',
    SizeBucket.gb20to40 => '20 – 40 GB',
    SizeBucket.over40gb => '> 40 GB',
  };

  static String _rangeFilterLabel(DynamicRange d) => switch (d) {
    DynamicRange.sdr => 'SDR',
    DynamicRange.hdr => 'HDR',
  };

  /// Redesigned result row (flag-gated) — a [SourceRow] with format-logo badges
  /// for detail-screen Sources, or a compact quality-tag row for keyword search
  /// and addon direct/external streams. Reuses the exact tap/pin/menu wiring of
  /// the classic row so behaviour is identical; only the presentation differs.
  Widget _redesignRow(Torrent t, int i, {bool cinema = false}) {
    final isStream = t.isDirectStream || t.isExternalStream;
    final tags = (_keywordMode || isStream)
        ? const <FormatTag>[]
        : FormatTagDetector.detect(t.name);
    return SourceRow(
      isCurrentSource: identical(t, _selectedDirect),
      notice: _showCachedEpisodeSource && identical(t, _cachedEpisodeSource)
          ? 'Last played source · Not returned by the latest search. Using its cached link.'
          : null,
      listIndex: i,
      cinemaLayout: cinema,
      title: t.displayTitle,
      addonText: _useAddonText ? t.addonPresentation : null,
      addonName: _showAddonLogos ? t.addonDisplayName : null,
      addonLogo: t.addonLogo,
      titleMaxLines: 6,
      subtitle: _rowSubtitle(t),
      focusNode: _nodes[i],
      isTelevision: widget.isTelevision,
      showPlayPill: !widget.bindMode && widget.isTelevision,
      formatTags: tags,
      badgeName: t.name,
      badgeDescription: t.badgeDescription,
      qualityTag: tags.isEmpty ? _qualityLabel(t) : null,
      cacheLabel: _cacheLabel(t),
      coverageBadge: _keywordMode ? null : _coverageLabel(t),
      streamBadge: t.isExternalStream
          ? 'External'
          : t.isDirectStream
          ? 'Direct'
          : null,
      onCopy: !_canCopySource(t) ? null : () => unawaited(_copySourceLink(t)),
      onTap: () {
        if (widget.bindMode) {
          unawaited(_pin(t));
        } else {
          _play(t, i);
        }
      },
      onLongPress: () => _showRowMenu(t, i),
      onNavigateUp: () {
        _freezeStreaming();
        if (i > 0) {
          _nodes[i - 1].requestFocus();
        } else if (_pendingNewCount > 0) {
          // From the first row, UP reaches the "+N new sources" pill first.
          _pillFocus.requestFocus();
        } else if (widget.isTelevision) {
          // From the first row, UP reaches the toolbar (otherwise unreachable
          // by remote — the list consumes UP).
          _filterFocus.requestFocus();
        }
      },
      onNavigateDown: () {
        _freezeStreaming();
        if (i < _nodes.length - 1) _nodes[i + 1].requestFocus();
      },
    );
  }

  /// `size · ↑seeders · ↓leechers · SOURCE` meta line for a redesigned row.
  String _rowSubtitle(Torrent t) {
    final parts = <String>[];
    final sourceLabel = t.addonDisplayName ?? t.source;
    if (t.isDirectStream || t.isExternalStream) {
      if (t.sizeBytes > 0) parts.add(_fmtSize(t.sizeBytes));
      if (sourceLabel.isNotEmpty) parts.add(sourceLabel.toUpperCase());
      return parts.join(' · ');
    }
    if (t.sizeBytes > 0) parts.add(_fmtSize(t.sizeBytes));
    if (t.seeders > 0) parts.add('↑ ${t.seeders}');
    if (t.leechers > 0) parts.add('↓ ${t.leechers}');
    if (sourceLabel.isNotEmpty) parts.add(sourceLabel.toUpperCase());
    final date = _fmtDate(t.createdUnix);
    if (date != null) parts.add(date);
    return parts.join(' · ');
  }

  /// Relative upload date ("2d ago"), matching the classic row. Null when the
  /// torrent carries no date.
  static String? _fmtDate(int createdUnix) {
    if (createdUnix <= 0) return null;
    final then = DateTime.fromMillisecondsSinceEpoch(createdUnix * 1000);
    final d = DateTime.now().difference(then);
    if (d.inDays >= 365) return '${(d.inDays / 365).floor()}y ago';
    if (d.inDays >= 30) return '${(d.inDays / 30).floor()}mo ago';
    if (d.inDays >= 7) return '${(d.inDays / 7).floor()}w ago';
    if (d.inDays >= 1) return '${d.inDays}d ago';
    if (d.inHours >= 1) return '${d.inHours}h ago';
    return 'Today';
  }

  static String? _qualityLabel(Torrent t) {
    // Use the same resolution logic as the F badges (pixel tokens win over the
    // loose UHD/4K keyword) so the compact/keyword quality pill stays consistent
    // with them — the `qualityTier` extension mislabels "UHD BluRay 1080p".
    final tags = FormatTagDetector.detect(t.name);
    if (tags.contains(FormatTag.uhd4k)) return '4K';
    if (tags.contains(FormatTag.fullHd)) return '1080p';
    if (tags.contains(FormatTag.hd720)) return '720p';
    return null; // SD / unknown — no pill
  }

  String? _coverageLabel(Torrent t) {
    switch (t.coverageType) {
      case 'completeSeries':
        return 'Complete Series';
      case 'multiSeasonPack':
        return 'Multi-Season';
      case 'seasonPack':
        return t.seasonNumber != null
            ? 'Season ${t.seasonNumber}'
            : 'Season Pack';
      case 'singleEpisode':
        return t.episodeIdentifier;
      default:
        return null;
    }
  }

  static String _fmtSize(int bytes) {
    if (bytes <= 0) return '';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var size = bytes.toDouble();
    var u = 0;
    while (size >= 1024 && u < units.length - 1) {
      size /= 1024;
      u++;
    }
    return '${size.toStringAsFixed(size >= 100 || u == 0 ? 0 : 1)} ${units[u]}';
  }

  Widget _centered(ColorScheme scheme, String text) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: scheme.onSurfaceVariant),
      ),
    ),
  );
}

/// The Discover glass stage's still backdrop: the focused (rail-shown) title's
/// backdrop drawn full-frame behind both panes, veiled by [_DiscoverStageVeils]
/// above it. Adoption is dwell-debounced (~380ms) so rapid DPAD arrowing never
/// decodes a full-bleed image per step — the first artwork after an empty stage
/// paints immediately. Only real `background` art is used (never a blown-up
/// poster); titles without it browse on the plain ink wash.
class _DiscoverStageBackdrop extends StatefulWidget {
  final ValueListenable<StremioMeta?> shown;

  /// How long the DPAD must rest before this adopts a new backdrop. The STAGE
  /// layout passes ZERO: its feed is already settled upstream (the identity
  /// block's own settle), so a second dwell here would only make the art trail
  /// the title it belongs to.
  final Duration dwell;

  /// Crossfade swaps instead of snapping them. The two-pane keeps the snap —
  /// a full-screen crossfade is a saveLayer on weak TV GPUs, and behind a
  /// grid it buys little. The STAGE turns it on: the art IS the layout there,
  /// and its swaps are already rate-limited by the settle, so this matches the
  /// Home board's own full-bleed art, which crossfades on the same cadence.
  final bool crossfade;

  const _DiscoverStageBackdrop({
    required this.shown,
    this.dwell = const Duration(milliseconds: 380),
    this.crossfade = false,
  });

  @override
  State<_DiscoverStageBackdrop> createState() => _DiscoverStageBackdropState();
}

class _DiscoverStageBackdropState extends State<_DiscoverStageBackdrop> {
  String? _url;
  Timer? _dwell;

  static String? _bgOf(StremioMeta? m) {
    final bg = m?.background;
    return (bg != null && bg.isNotEmpty) ? bg : null;
  }

  @override
  void initState() {
    super.initState();
    widget.shown.addListener(_onShown);
    _url = _bgOf(widget.shown.value);
  }

  @override
  void dispose() {
    _dwell?.cancel();
    widget.shown.removeListener(_onShown);
    super.dispose();
  }

  void _onShown() {
    final next = _bgOf(widget.shown.value);
    if (next == _url) return;
    _dwell?.cancel();
    // Cleared (source swap) or the focused title has no backdrop: drop to ink
    // now — holding another title's art behind the wrong detail reads wrong.
    if (next == null) {
      setState(() => _url = null);
      return;
    }
    // First art onto an empty stage: no dwell, the page should dress itself
    // promptly. Subsequent moves debounce.
    if (_url == null) {
      setState(() => _url = next);
      return;
    }
    if (widget.dwell == Duration.zero) {
      setState(() => _url = next);
      return;
    }
    _dwell = Timer(widget.dwell, () {
      if (!mounted) return;
      final cur = _bgOf(widget.shown.value);
      if (cur != null && cur != _url) setState(() => _url = cur);
    });
  }

  @override
  Widget build(BuildContext context) {
    final url = _url;
    // Per-IMAGE fades stay off in both modes (a CachedNetworkImage crossfade
    // runs on every arrival, including cache hits). Slight upward bias keeps
    // faces/titles in the art's clear zone.
    final art = url == null
        ? const SizedBox.shrink()
        : CachedNetworkImage(
            key: ValueKey(url),
            imageUrl: url,
            fit: BoxFit.cover,
            alignment: const Alignment(0, -0.4),
            memCacheWidth: HomeTheme.heroBackdropCacheWidthTv,
            fadeInDuration: Duration.zero,
            fadeOutDuration: Duration.zero,
            placeholder: (_, __) => const SizedBox.shrink(),
            errorWidget: (_, __, ___) => const SizedBox.shrink(),
          );
    if (!widget.crossfade) return art;
    // Android TV keeps the two-pane's SNAP even on the stage: the switcher's
    // crossfade is a full-screen saveLayer on that GLES2 pipeline — the exact
    // cost the two-pane documented when it declined the fade — and a rest can
    // pay it twice (the raw list art, then the /meta-enriched background a
    // moment later). On an Amlogic box those frames land right when the user
    // is about to move again, which reads as navigation lag.
    if (PlatformUtil.isAndroidTvCached) return art;
    // Between two SETTLED titles — at most one swap per rest — so the
    // saveLayer this costs is bounded, exactly as on the Home board's stage.
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      // LOSING the art snaps instead of fading. Catalog list items usually
      // arrive with no `background` at all — it comes with the /meta
      // enrichment a moment later — so a symmetric crossfade would dip the
      // whole frame to ink and back on nearly every rest. Only the arrival is
      // worth animating.
      reverseDuration: url == null
          ? Duration.zero
          : const Duration(milliseconds: 240),
      // EXPAND, not the default centre-and-shrink-wrap: a switcher's stock
      // layout hands its children loose constraints, which would let each
      // backdrop paint at its own intrinsic size instead of covering the
      // frame — outgoing and incoming art must both be the same full-bleed
      // crop, or the swap reads as a jump in zoom.
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.expand,
        children: [...previous, if (current != null) current],
      ),
      child: art,
    );
  }
}

/// The Discover glass stage's tint veils — the mock's gradient recipe, painted
/// in the page ink so the art dissolves into the canvas: loudest art behind the
/// detail column, near-opaque under the grid, plus a vertical top kiss and deep
/// bottom melt.
///
/// Three states on a lights ladder, eased between so every step feels staged:
/// browse (art dressed in the mock's tint), playback ([showing] — art-zone
/// stops thin to ~.35 so the video actually reads, 900ms in), and theater
/// ([theater], a few seconds into uninterrupted playback — the veils fall to
/// near-clear (~.12) and the whole page commits to the picture, on a slow
/// 1.2s ease). Lights-up from any state is a snappy 250ms (a DPAD move means
/// the user is browsing again). Direct translucent paint (DecoratedBox with
/// lerped colors, never an Opacity layer), so it is safe over the underlay
/// trailer's punched hole; the gradient only re-paints during the transitions,
/// never at idle.
class _DiscoverStageVeils extends StatelessWidget {
  final ValueListenable<bool> showing;
  final ValueListenable<bool> theater;

  /// STAGE layout: there is no pane divide to light for, so the tint moves to
  /// where the text actually is — a left column and a bottom ramp under the
  /// shelf, with the right/upper art left clear. Same browse→playback→theater
  /// ladder and the same baked-alpha paint (never an Opacity layer, which
  /// forces a per-frame full-screen saveLayer on weak TV GPUs).
  final bool stage;

  const _DiscoverStageVeils({
    required this.showing,
    required this.theater,
    this.stage = false,
  });

  /// Page ink at an alpha walked along the browse→playback→theater ladder by
  /// [phase] (0..2). [base] is the page ink, captured once at build — this
  /// runs per transition frame. withValues (not fade): the ladder's alphas
  /// are ABSOLUTE, and the ground token is opaque on every theme, so the two
  /// are equivalent here.
  static Color _ink(
    Color base,
    double browse,
    double play,
    double deep,
    double phase,
  ) {
    final a = phase <= 1.0
        ? browse + (play - browse) * phase
        : play + (deep - play) * (phase - 1.0);
    return base.withValues(alpha: a);
  }

  @override
  Widget build(BuildContext context) {
    final ink = AppThemeScope.of(context).home.bg;
    return IgnorePointer(
      child: ValueListenableBuilder<bool>(
        valueListenable: showing,
        builder: (_, on, __) => ValueListenableBuilder<bool>(
          valueListenable: theater,
          builder: (_, deep, __) => TweenAnimationBuilder<double>(
            tween: Tween(end: deep ? 2.0 : (on ? 1.0 : 0.0)),
            duration: deep
                ? const Duration(milliseconds: 1200)
                : on
                ? const Duration(milliseconds: 900)
                // Lights-up fires on the KEYPRESS that interrupts a
                // trailer, and each of its frames re-lerps and repaints
                // three full-screen gradients — on an Amlogic/Mali box
                // that lands as input lag on the exact frame the user
                // pressed. Snap it there; the slow lights-down legs run
                // at rest, where nobody is waiting on a frame.
                : PlatformUtil.isAndroidTvCached
                ? Duration.zero
                : const Duration(milliseconds: 250),
            curve: Curves.easeInOutCubic,
            builder: (_, t, __) => stage
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      // Left column: seats the identity block. Dissolves by
                      // two thirds across so the art keeps the right half.
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              _ink(ink, 0.88, 0.56, 0.10, t),
                              _ink(ink, 0.60, 0.34, 0.06, t),
                              const Color(0x000D0B1A),
                            ],
                            stops: const [0.0, 0.32, 0.66],
                          ),
                        ),
                      ),
                      // Bottom ramp: seats the shelf and the filter line's
                      // opposite edge; top edge gets a whisper so the filter
                      // segments stay legible over bright art.
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              _ink(ink, 0.94, 0.70, 0.16, t),
                              _ink(ink, 0.74, 0.46, 0.10, t),
                              const Color(0x000D0B1A),
                              _ink(ink, 0.30, 0.14, 0.04, t),
                            ],
                            stops: const [0.0, 0.20, 0.52, 1.0],
                          ),
                        ),
                      ),
                      // The text pocket, straight off the Canvas board: the
                      // identity block's meta line and plot are allowed to run
                      // to half the frame, past where the left column has
                      // dissolved, and the bottom ramp alone leaves their
                      // right end sitting on bare artwork. Centred under the
                      // block, gone well before mid-screen so the art keeps
                      // its glow everywhere else.
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: const Alignment(-0.72, 0.55),
                            radius: 0.95,
                            colors: [
                              _ink(ink, 0.80, 0.45, 0.06, t),
                              const Color(0x000D0B1A),
                            ],
                            stops: const [0.12, 1.0],
                          ),
                        ),
                      ),
                    ],
                  )
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              _ink(
                                ink,
                                0.58,
                                0.34,
                                0.10,
                                t,
                              ), // art zone / rail text
                              _ink(ink, 0.62, 0.38, 0.12, t),
                              // Theater goes near-clear on the grid side too — the
                              // panel content fades itself, so the video must not be
                              // buried under ink there ("black right side").
                              _ink(ink, 0.84, 0.68, 0.18, t), // the pane divide
                              _ink(ink, 0.94, 0.86, 0.24, t), // under the grid
                              _ink(ink, 1.0, 0.92, 0.30, t),
                            ],
                            stops: const [0.0, 0.34, 0.52, 0.74, 1.0],
                          ),
                        ),
                      ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              _ink(
                                ink,
                                0.34,
                                0.15,
                                0.06,
                                t,
                              ), // settle the top edge
                              const Color(0x000D0B1A),
                              const Color(0x000D0B1A),
                              _ink(
                                ink,
                                0.88,
                                0.58,
                                0.28,
                                t,
                              ), // melt into the bottom
                            ],
                            stops: const [0.0, 0.26, 0.55, 0.92],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Lights-off over the grid while the trailer PLAYS (pre-theater): an animated
/// baked-color wash covering the panel side (posters + filter line recede,
/// Home-rows style), feathered over its first 15% so no hard seam cuts the
/// stage at the pane divide. In THEATER the wash dissolves back to zero — there
/// the panel content fades itself (host-side AnimatedOpacity) and ink here
/// would just bury the now-unveiled video. Sits ABOVE the two-pane. Any DPAD
/// move drops the signals and the lights snap back up in 250ms.
class _DiscoverGridDim extends StatelessWidget {
  final ValueListenable<bool> showing;
  final ValueListenable<bool> theater;
  final double leftInset;

  const _DiscoverGridDim({
    required this.showing,
    required this.theater,
    required this.leftInset,
  });

  @override
  Widget build(BuildContext context) {
    final ink = AppThemeScope.of(context).home.bg;
    return Positioned(
      left: leftInset,
      top: 0,
      right: 0,
      bottom: 0,
      // RepaintBoundary inside the Positioned (which must stay a direct Stack
      // child): the dim animates a panel-wide gradient per frame during the
      // 250/900ms transitions — keep those frames off the stage layer.
      child: RepaintBoundary(
        child: IgnorePointer(
          child: ValueListenableBuilder<bool>(
            valueListenable: showing,
            builder: (_, on, __) => ValueListenableBuilder<bool>(
              valueListenable: theater,
              builder: (_, deep, __) => TweenAnimationBuilder<double>(
                tween: Tween(end: deep ? 2.0 : (on ? 1.0 : 0.0)),
                duration: deep
                    ? const Duration(milliseconds: 1200)
                    : on
                    ? const Duration(milliseconds: 900)
                    : const Duration(milliseconds: 250),
                curve: Curves.easeInOutCubic,
                builder: (_, t, __) {
                  // 0→1: 0 → .52 (playback); 1→2: .52 → 0 (theater unveils).
                  final a = t <= 1.0 ? 0.52 * t : 0.52 * (2.0 - t);
                  if (a <= 0.001) return const SizedBox.shrink();
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        // withValues (not fade): absolute alphas over an
                        // always-opaque ground token — equivalent, and the
                        // ramp's 0.0 end must stay a true clear.
                        colors: [
                          ink.withValues(alpha: 0.0),
                          ink.withValues(alpha: a),
                        ],
                        stops: const [0.0, 0.15],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
