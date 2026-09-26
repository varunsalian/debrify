part of '../search_screen.dart';

/// Exercises the real source screen with controllable engine batches.
@visibleForTesting
Widget sourcesScreenForTesting({
  required AdvancedSearchSelection selection,
  required PlaybackMeta meta,
  required Future<Map<String, dynamic>> Function(SearchBatchCallback onBatch)
  search,
  SourceAddonRetry? retry,
  bool bindMode = false,
  bool forcePlayOnTap = false,
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
  child: _SourcesScreen(
    selection: selection,
    meta: meta,
    isTelevision: true,
    bindMode: bindMode,
    forcePlayOnTap: forcePlayOnTap,
  ),
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
  List<Torrent> get _visible => _resultsPresentation.visible;
  final _rowFocus = SourceRowFocusNodes();
  List<FocusNode> get _nodes => _rowFocus.nodes;
  final ScrollController _resultsScroll = ScrollController(
    keepScrollOffset: false,
  );
  late final ProviderSubscription<SavedSourcesState> _savedSourcesSubscription;
  List<SeriesSource> get _bound => _savedSourcesSubscription.read().sources;
  Torrent? get _selectedDirect => _resultsPresentation.selected;
  Torrent? get _cachedEpisodeSource =>
      _savedSourcesSubscription.read().cachedEpisode;
  bool get _showCachedEpisodeSource => _resultsPresentation.showCachedEpisode;
  late final _resultsFocus = SourceResultsFocus(
    controller: _resultsScroll,
    readNodes: () => _nodes,
    filterFocus: _filterFocus,
    pillFocus: _pillFocus,
    isMounted: () => mounted,
    searchToken: () => _searchToken,
    isFrozen: () => _streamFrozen,
    hasPendingResults: () => _pendingNewCount > 0,
    hasSelectedVisible: () => _visible.contains(_selectedDirect),
    hasRailFocus: () => _cinemaKey.currentState?.hasRailFocus ?? false,
    canRecoverEmpty: () => _seasonChipVisible || _hasRetryableAddon,
    isTelevision: () => widget.isTelevision,
    freeze: _freezeStreaming,
    onEvent: _logPickerSelection,
  );
  final int _pickerTraceId = DateTime.now().microsecondsSinceEpoch;
  late final SourcePickerTrace _pickerTrace;

  void _logPickerSelection(
    String event, [
    Map<String, Object?> detail = const {},
  ]) => _pickerTrace.log(
    event,
    search: _searchToken,
    season: widget.selection.season,
    episode: widget.selection.episode,
    visible: _visible,
    selected: _selectedDirect,
    railFocus: _cinemaKey.currentState?.hasRailFocus ?? false,
    filterFocus: _filterFocus.hasFocus,
    pillFocus: _pillFocus.hasFocus,
    television: widget.isTelevision,
    detail: detail,
  );

  // --- redesign toolbar state (unused when _redesign is false) ---
  String? get _sourceFilter => _resultsSubscription.read().toolbar.sourceFilter;

  late final ProviderSubscription<SourcePresentationSettings>
      _settingsSubscription;
  SourcePresentationSettings get _settings => _settingsSubscription.read();
  final _cinemaKey = GlobalKey<CinemaSourcesLayoutState>();

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

  /// Set on the first real interaction (drag scroll, row D-pad move, row menu,
  /// toolbar use). Frozen ⇒ later arrivals buffer as pending results
  /// behind the "+N new sources" pill instead of reshuffling the list under
  /// the user's finger/focus.
  late final ProviderSubscription<SourceResultsState> _resultsSubscription;
  SourceResultsController get _resultsController =>
      ref.read(sourceResultsProvider(_sourcesSession).notifier);
  bool get _streamFrozen => _resultsSubscription.read().frozen;

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
  /// chip menu falls back to the stored derived season inventory.
  List<int> get _availableSeasons => _seasonsSubscription.read().available;

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
  SeriesSource? _bindingFor(Torrent torrent) =>
      ref.read(sourceBindingMatcherProvider).match(_bound, torrent);

  @override
  void initState() {
    super.initState();
    // Deferred reveal diagnostics can run after Ref/subscriptions are disposed.
    _pickerTrace = SourcePickerTrace(
      pickerId: _pickerTraceId,
      emit: ref.read(sourcePickerDiagnosticsProvider),
      isMounted: () => mounted,
      readResults: () => _resultsSubscription.read(),
      readSearching: () => _searching,
      readBoundCount: () => _bound.length,
    );
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
          _resultsPresentation.updateSelected();
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
          _resultsPresentation.clearRetiredProfile();
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
    final ready = await ref.read(sourceStartupProvider).load(_sourcesSession);
    if (!mounted ||
        !ready ||
        _sourcesSession.owner != ProfileSessionMemory.captureOwner()) {
      return;
    }
    await _runSearch();
  }

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
    _pickerTrace.retireResults(_selectedDirect);
    _resultsSubscription.close();
    _pickerTrace.retireSearch();
    _searchSubscription.close();
    _retrySubscription.close();
    _cacheSubscription.close();
    _pickerTrace.retireBound();
    _savedSourcesSubscription.close();
    _settingsSubscription.close();
    _seasonsSubscription.close();
    _kwCtrl.dispose();
    _resultsScroll.dispose();
    _filterFocus.removeListener(_onFilterFocusChanged);
    _filterFocus.dispose();
    _pillFocus.dispose();
    _rowFocus.dispose();
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
    if (!_searchController.prepareSearch()) return;
    if (mounted) setState(() => _loading = true);
    _resultsPresentation.resetForSearch();
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
        _resultsPresentation.present(rows, token);
        if (complete) _resultsPresentation.complete(token);
      },
      onBatchAccepted: (batch) {
        if (mounted && token == _searchToken) _maybeCheckCache(batch);
      },
    );
  }

  void _submitKeyword(String q) {
    final trimmed = q.trim();
    if (trimmed.isEmpty || trimmed == _query) return;
    _query = trimmed;
    _runSearch();
  }

  late final ProviderSubscription<bool> _bindingSubscription;

  bool get _sourceActionActive =>
      mounted && _sourcesSession.owner == ProfileSessionMemory.captureOwner();

  late final _actions = SourceActions(
    ref: ref,
    context: context,
    session: _sourcesSession,
    isMounted: () => mounted,
    isActive: () => _sourceActionActive,
    details: () => (
      selection: widget.selection,
      meta: widget.meta,
      bindMode: widget.bindMode,
      forcePlayOnTap: widget.forcePlayOnTap,
    ),
    readVisible: () => _visible,
    freezeStreaming: _freezeStreaming,
    bindingFor: _bindingFor,
    reloadBound: _reloadBound,
  );

  @override
  Widget build(BuildContext context) => buildSourceScreenFrame(
    context,
    selection: widget.selection,
    keywordQuery: _keywordMode ? _query : null,
    bindMode: widget.bindMode,
    isTelevision: widget.isTelevision,
    art: widget.meta.art,
    posterUrl: widget.meta.posterUrl,
    cinemaKey: _cinemaKey,
    canPinLocal: () =>
        _imdbId.isNotEmpty &&
        ref.read(sourceBindingBridgeProvider).localBindingAvailable,
    onPinLocal: () => unawaited(_actions.pinLocal()),
    providers: () => _cinemaProviders,
    selectedProvider: _sourceFilter,
    onProviderSelected: _selectCinemaProvider,
    onFocusResults: _resultsFocus.focusRememberedRow,
    isSourceFocused: _resultsFocus.rememberFocusedRow,
    resultCount: _visible.length,
    searching: _loading || _searching,
    failed: _error != null,
    bodyBuilder: (scheme, cinema) => _sourcesBody(scheme, cinema: cinema),
  );

  List<CinemaSourceProvider> get _cinemaProviders => projectCinemaSourceProviders(
    torrents: _torrents,
    statuses: _addonStatuses,
    iptv: _iptvSources,
    priority: _sourcePriority,
    aliases: _sourceAliases,
    retrying: _retryingAddons,
  );

  void _selectCinemaProvider(String? key) {
    _resultsController.selectProvider(key);
    _resultsFocus.resetRememberedRow();
    // The rail returns to row zero after changing providers. Mount that row
    // before Right can request its focus; a lazy list left at the previous
    // provider's offset has no attached focus target at index zero.
    if (_resultsScroll.hasClients) _resultsScroll.jumpTo(0);
    _rebuildVisible();
    if (_visible.contains(_selectedDirect)) {
      unawaited(_resultsPresentation.revealSelected(preserveFocus: true));
    }
    for (final status in _addonStatuses) {
      if (status.sourceKey == key && sourceStatusActionable(status)) {
        unawaited(_retryAddon(status));
      }
    }
  }

  Widget _sourcesBody(
    ColorScheme scheme, {
    bool cinema = false,
  }) => buildSourceResultsBody(
    scheme: scheme,
    keywordField: _keywordMode
        ? SourceKeywordField(
            scheme: scheme,
            controller: _kwCtrl,
            onSubmitted: _submitKeyword,
          )
        : null,
    loading: _loading,
    error: _error,
    titleBuilder: _redesign && !_keywordMode && !cinema
        ? () => SourceTitleHeader(
            title: widget.selection.title,
            subtitle: widget.selection.formattedLabel,
            poster: widget.meta.posterUrl,
          )
        : null,
    // Keep season controls with zero rows so an empty season cannot strand
    // the user. Retryable providers likewise retain their recovery controls.
    toolbarBuilder:
        _redesign &&
            (_torrents.isNotEmpty ||
                _seasonChipVisible ||
                _iptvSources.isNotEmpty ||
                _hasRetryableAddon)
        ? () => _toolbarPresentation.build(scheme, showProviders: !cinema)
        : null,
    showProgress: _searching && !cinema,
    visibleCount: _visible.length,
    scrollController: _resultsScroll,
    isTelevision: widget.isTelevision,
    redesign: _redesign,
    onUserScroll: _freezeStreaming,
    hasResults: () => _torrents.isNotEmpty,
    pendingResultsBuilder: _pendingNewCount > 0 ? _newSourcesPill : null,
    itemBuilder: (context, i) {
      final t = _visible[i];
      if (_redesign) {
        return _redesignRow(t, i, cinema: cinema);
      }
      return TorrentResultRow(
        torrent: t,
        index: i,
        focusNode: _nodes[i],
        isTelevision: widget.isTelevision,
        qualityTier: t.qualityTier,
        onTap: () {
          if (widget.bindMode) {
            unawaited(_actions.pin(t));
          } else {
            _actions.play(t, i);
          }
        },
        onLongPress: () => _actions.showMenu(t, i),
        onCopyMagnet: !_actions.canCopy(t)
            ? null
            : () => unawaited(_actions.copyLink(t)),
        onNavigateUp: () => _resultsFocus.rowUp(i, redesign: false),
        onNavigateDown: () => _resultsFocus.rowDown(i),
      );
    },
  );

  /// Whether a chip is worth pressing: a failed addon retries, and a
  /// zero-result addon re-asks (transient upstream failures often read as
  /// empty rather than as an error).
  bool get _hasRetryableAddon => _addonStatuses.any(sourceStatusActionable);

  /// Re-fetch ONE addon and fold whatever it returns into the list through
  /// the normal streaming-merge path — so retry results respect the same
  /// dedupe, series-pack post-processing, and the frozen-list "+N new
  /// sources" pill as any live batch.
  Future<void> _retryAddon(AddonSearchStatus status) async {
    switch (_searchController.retryMode(status)) {
      case SourceRetryMode.ignore:
        return;
      case SourceRetryMode.restartSearch:
        await _runSearch();
        return;
      case SourceRetryMode.addon:
        break;
    }
    final token = _searchToken;
    await _searchController.retryAddon(
      _effectiveSelection,
      status,
      shouldContinue: () => mounted && token == _searchToken,
      onRows: (rows) => _resultsPresentation.present(rows, token),
      onBatchAccepted: (batch) => _maybeCheckCache(batch),
    );
  }

  Widget _newSourcesPill() => SourcePendingResultsPill(
    count: _pendingNewCount,
    focusNode: _pillFocus,
    onAdopt: _resultsPresentation.adoptPending,
    onNavigateDown: _resultsFocus.pillDown,
    onNavigateUp: _resultsFocus.pillUp,
  );

  late final _resultsPresentation = SourceResultsPresentation(
    ref: ref,
    session: _sourcesSession,
    focus: _resultsFocus,
    rowFocus: _rowFocus,
    selection: () => _effectiveSelection,
    bindMode: () => widget.bindMode,
    hasSeasonScope: () => _seasonChipVisible,
    isTelevision: () => widget.isTelevision,
    isMounted: () => mounted,
    searchToken: () => _searchToken,
    redesign: _redesign,
    onChanged: (finishLoading) {
      setState(() {
        if (finishLoading) _loading = false;
      });
    },
    checkCache: _maybeCheckCache,
    onEvent: _logPickerSelection,
  );

  void _freezeStreaming() => _resultsPresentation.freeze();
  void _rebuildVisible() => _resultsPresentation.rebuildVisible();
  int get _pendingNewCount => _resultsSubscription.read().pendingNewCount;

  late final _toolbarPresentation = SourceToolbarPresentation(
    context: context,
    ref: ref,
    session: _sourcesSession,
    hasSeasonScope: () => _seasonChipVisible,
    isSeries: () => widget.selection.isSeries,
    isActive: () => _sourceActionActive,
    rebuildVisible: _rebuildVisible,
    runSearch: _runSearch,
    retryAddon: _retryAddon,
    filterFocus: _filterFocus,
    onFilterDown: _resultsFocus.filterDown,
  );

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

  /// Redesigned result row (flag-gated) — a [SourceRow] with format-logo badges
  /// for detail-screen Sources, or a compact quality-tag row for keyword search
  /// and addon direct/external streams. Reuses the exact tap/pin/menu wiring of
  /// the classic row so behaviour is identical; only the presentation differs.
  Widget _redesignRow(Torrent t, int i, {bool cinema = false}) {
    return buildSourceResultRow(
      torrent: t,
      listIndex: i,
      cinemaLayout: cinema,
      keywordMode: _keywordMode,
      settings: _settings,
      isCurrentSource: identical(t, _selectedDirect),
      isCachedEpisode:
          _showCachedEpisodeSource && identical(t, _cachedEpisodeSource),
      focusNode: _nodes[i],
      isTelevision: widget.isTelevision,
      bindMode: widget.bindMode,
      cacheLabel: _cacheLabel(t),
      onCopy: !_actions.canCopy(t)
          ? null
          : () => unawaited(_actions.copyLink(t)),
      onTap: () {
        if (widget.bindMode) {
          unawaited(_actions.pin(t));
        } else {
          _actions.play(t, i);
        }
      },
      onLongPress: () => _actions.showMenu(t, i),
      onNavigateUp: () => _resultsFocus.rowUp(i, redesign: true),
      onNavigateDown: () => _resultsFocus.rowDown(i),
    );
  }
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
