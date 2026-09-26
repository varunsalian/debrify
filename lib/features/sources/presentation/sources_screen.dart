import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/advanced_search_selection.dart';
import '../../../models/addon_search_status.dart';
import '../../../models/cinema_source_provider.dart';
import '../../../models/iptv_source_result.dart';
import '../../../models/playback_meta.dart';
import '../../../models/series_source.dart';
import '../../../models/torrent.dart';
import '../../../widgets/cinema_sources_layout.dart'
    show CinemaSourcesLayoutState;
import '../../../widgets/torrent_result_row.dart';
import '../../../widgets/source_row.dart';
import '../application/source_session_ownership.dart';
import '../application/source_startup.dart';
import '../application/source_picker_diagnostics.dart';
import '../application/source_binding_match_dependencies.dart';
import '../application/source_provider_projection.dart';
import '../application/source_binding_controller.dart';
import '../application/source_results_controller.dart';
import '../application/source_search_controller.dart';
import '../application/source_retry_controller.dart';
import '../application/source_cache_controller.dart';
import '../application/saved_sources_controller.dart';
import '../application/source_settings_controller.dart';
import '../application/source_seasons_controller.dart';
import '../models/source_results_state.dart';
import '../models/source_search_state.dart';
import '../models/source_search_request.dart';
import '../models/source_cache_state.dart';
import '../models/saved_sources_state.dart';
import '../models/source_presentation_settings.dart';
import '../models/source_seasons_state.dart';
import '../models/sources_session.dart';
import 'source_results_presentation.dart';
import 'source_picker_trace.dart';
import 'source_toolbar_presentation.dart';
import 'source_actions.dart';
import 'source_results_body.dart';
import 'source_screen_frame.dart';
import 'source_result_row.dart';
import 'source_row_focus_nodes.dart';
import 'source_binding_bridge.dart';
import 'source_results_focus.dart';
import 'source_title_header.dart';
import 'source_keyword_field.dart';
import 'source_pending_results_pill.dart';

class SourcesScreen extends ConsumerStatefulWidget {
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

  const SourcesScreen({
    super.key,
    required this.selection,
    required this.meta,
    required this.isTelevision,
    this.bindMode = false,
    this.keywordSeed,
    this.forcePlayOnTap = false,
  });

  @override
  ConsumerState<SourcesScreen> createState() => _SourcesScreenState();
}

class _SourcesScreenState extends ConsumerState<SourcesScreen> {
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
  late final SourceSessionOwnership _sessionOwnership;
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
    _sessionOwnership = ref.read(sourceSessionOwnershipProvider);
    _query = widget.keywordSeed ?? '';
    _kwCtrl = TextEditingController(text: _query);
    _sourcesSession = SourcesSession(
      owner: _sessionOwnership.capture(),
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
        if (!_sessionOwnership.isCurrent(_sourcesSession)) {
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
    if (!mounted || !ready || !_sessionOwnership.isCurrent(_sourcesSession)) {
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
      mounted && _sessionOwnership.isCurrent(_sourcesSession);

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

  List<CinemaSourceProvider> get _cinemaProviders =>
      projectCinemaSourceProviders(
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
