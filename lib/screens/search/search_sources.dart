import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/advanced_search_selection.dart';
import '../../models/torrent.dart';
import '../../models/torrent_filter_state.dart';
import '../../models/stremio_addon.dart';
import '../../services/storage/quick_play_policy_prefs.dart';
import '../../services/storage/provider_credential_prefs.dart';
import '../../services/cloud/cloud_provider_registry.dart';
import '../../services/engine/dynamic_engine.dart';
import '../../services/engine/settings_manager.dart';
import '../../services/local_series_completion_service.dart';
import '../../models/profiles/profile_policy.dart';
import '../../services/profiles/profile_policy_guard.dart';
import '../../services/series_source_service.dart';
import '../../services/source_priority.dart';
import '../../services/stremio_service.dart';
import '../../services/storage_service.dart';
import '../../services/torrent_playback_service.dart';
import '../../services/torrent_service.dart';
import '../../theme/app_theme_scope.dart';
import '../../utils/dialog_tap_guard.dart';
import '../../utils/format_tag_detector.dart';
import '../../utils/torrent_filter_matcher.dart';
import '../../utils/tv_keys.dart';
import '../../widgets/source_row.dart';
import '../../widgets/torrent_filters_sheet.dart';
import '../../widgets/tv_text_field.dart';

/// Public entry to the private Sources route owned by this library.
Widget buildSearchSources({
  required AdvancedSearchSelection selection,
  required PlaybackMeta meta,
  required bool isTelevision,
  bool bindMode = false,
  String? keywordSeed,
  bool forcePlayOnTap = false,
}) => _SourcesScreen(
  selection: selection,
  meta: meta,
  isTelevision: isTelevision,
  bindMode: bindMode,
  keywordSeed: keywordSeed,
  forcePlayOnTap: forcePlayOnTap,
);

class _SourcesScreen extends StatefulWidget {
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
  State<_SourcesScreen> createState() => _SourcesScreenState();
}

class _SourcesScreenState extends State<_SourcesScreen> {
  bool _loading = true;
  String? _error;
  List<Torrent> _torrents = [];

  /// The rows actually rendered — [_torrents] after the toolbar's
  /// source-group filter, quality/rip/language filter, and sort are applied.
  /// [_nodes] is kept in lock-step with THIS list, never [_torrents].
  List<Torrent> _visible = [];
  final List<FocusNode> _nodes = [];
  List<SeriesSource> _bound = [];

  // --- redesign toolbar state ---
  TorrentFilterState _filters = const TorrentFilterState.empty();
  String _sortBy = 'source'; // source | name | size | seeders | date
  bool _sortAsc = false;
  String? _sourceFilter; // null = all sources; else a normalized provider key

  /// D-pad anchor for the redesigned toolbar: the filter funnel. Pressing UP
  /// from the first row focuses this on TV so the remote can reach the toolbar
  /// (the list otherwise consumes UP and the toolbar is unreachable).
  final FocusNode _filterFocus = FocusNode(debugLabel: 'src_filter');

  /// Per-addon outcomes for the current search — every APPLICABLE Stremio
  /// addon, including failed and zero-result ones (which the result list
  /// alone makes invisible). Drives the status strip under the toolbar.
  List<AddonSearchStatus> _addonStatuses = [];

  /// Addon ids with a retry in flight — their chip shows a spinner.
  final Set<String> _retryingAddons = {};

  /// The user's Quick Play "Addon Priority" order for this tab (empty =
  /// never customized = keep the shipped provider ordering). Also
  /// orders the source pills and their retry states.
  List<String> _sourcePriority = const [];
  Map<String, String> _sourceAliases = const {};

  // --- cached-availability badges (redesign only): checked async after results
  // arrive, only for TorBox / Premiumize when their cache-check pref is on and
  // the provider is configured. Maps: infohash(lowercased) -> isCached. ---
  bool _tbCacheOn = false;
  bool _pmCacheOn = false;
  String? _tbKey;
  String? _pmKey;
  Map<String, bool>? _tbCache;
  Map<String, bool>? _pmCache;
  int _cacheToken = 0;

  /// Infohashes already dispatched to a provider cache-check for the current
  /// [_cacheToken] generation. Streaming batches accumulate cumulatively, so
  /// this lets each batch check only the hashes an earlier batch hasn't —
  /// no provider hash is ever queried twice per search.
  final Set<String> _cacheChecked = {};

  // --- streaming search: rows appear per engine as each one finishes, instead
  // of waiting for the slowest engine's timeout. ---
  /// Raw per-source batches accumulated for the CURRENT search token. Batches
  /// retain each provider's response order; provider priority and stable
  /// dedupe are applied when the rendered list is derived.
  final List<List<Torrent>> _streamBatches = [];

  /// True while engines are still in flight (drives the "Still searching…"
  /// strip under the toolbar).
  bool _searching = false;

  /// Set on the first real interaction (drag scroll, row D-pad move, row menu,
  /// toolbar use). Frozen ⇒ later arrivals buffer into [_pendingTorrents]
  /// behind the "+N new sources" pill instead of reshuffling the list under
  /// the user's finger/focus.
  bool _streamFrozen = false;

  /// Post-processed FULL result set waiting behind the pill while frozen.
  List<Torrent>? _pendingTorrents;

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
  int? _selectedSeason;

  /// Seasons from the meta addon (authoritative). Empty until fetched; the
  /// chip menu falls back to [_derivedSeasons].
  List<int> _availableSeasons = [];

  /// Seasons derived from the last UNSCOPED (All Seasons) result set's
  /// coverage info — the chip-menu fallback when the meta fetch fails. Only
  /// snapshotted on unscoped searches: a season-scoped result set is already
  /// filtered and would collapse the menu to the selected season.
  List<int> _derivedSeasons = [];

  /// Whether the "Season" scope chip applies: only for a series pack search
  /// (no specific episode), never in keyword mode.
  bool get _seasonChipVisible =>
      !_keywordMode &&
      widget.selection.isSeries &&
      widget.selection.episode == null;

  /// Monotonic guard so a slow earlier search can't clobber a newer one.
  int _searchToken = 0;

  String get _imdbId => widget.selection.imdbId;
  bool get _isMovie => !widget.selection.isSeries;
  SeriesSource? _bindingFor(Torrent torrent) {
    for (final source in _bound) {
      if (torrent.isDirectStream &&
          source.matchesAddonDirect(
            candidateAddonKey: torrent.stremioAddonKey,
            candidateStreamKey: torrent.stremioStreamKey,
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
    _selectedSeason = widget.selection.season;
    // Rebuild the toolbar when the funnel gains/loses focus so its D-pad
    // highlight tracks — Focus alone doesn't guarantee a parent rebuild.
    _filterFocus.addListener(_onFilterFocusChanged);
    _loadCacheConfig();
    unawaited(_initializeSources());
    if (_seasonChipVisible) unawaited(_loadSeasons());
  }

  Future<void> _initializeSources() async {
    // Priority must be known before the first engine batch lands. Loading it
    // beside the search and rebuilding afterwards used the toolbar's
    // user-interaction path, which froze streaming and parked every later
    // batch behind the "+N new sources" pill.
    await Future.wait([_loadSourcePriority(), _reloadBound()]);
    if (!mounted) return;
    await _runSearch();
  }

  Future<void> _loadSourcePriority() async {
    try {
      final rules = await QuickPlayPolicyPrefs.getQuickPlayRules(
        isMovie: !widget.selection.isSeries,
      );
      final aliases = await SourcePriority.engineAliases();
      if (!mounted) return;
      _sourcePriority = rules.sourcePriority;
      _sourceAliases = aliases;
    } catch (_) {}
  }

  /// Fetch the show's season numbers from the first meta-capable addon for the
  /// Season chip menu. Best-effort: on failure the chip menu falls back to
  /// seasons derived from the current results' coverage info.
  Future<void> _loadSeasons() async {
    if (_imdbId.isEmpty) return;
    try {
      final stremio = StremioService.instance;
      final metaAddon = await stremio.firstMetaCapableAddon();
      if (metaAddon == null) return;
      final videos = await stremio.fetchSeriesMeta(metaAddon, _imdbId);
      if (videos == null || !mounted) return;
      unawaited(
        LocalSeriesCompletionService.instance.recordRawEpisodeInventory(
          imdbId: _imdbId,
          seriesTitle: widget.selection.title,
          videos: videos,
        ),
      );
      final seasons = <int>{};
      for (final v in videos) {
        final s = (v['season'] as num?)?.toInt();
        if (s != null && s > 0) seasons.add(s);
      }
      if (seasons.isEmpty) return;
      setState(() => _availableSeasons = seasons.toList()..sort());
    } catch (_) {
      // Chip falls back to result-derived seasons.
    }
  }

  /// Seasons offered by the Season chip: the meta addon's list when loaded,
  /// otherwise [_derivedSeasons] (from the last unscoped results).
  List<int> _seasonMenuNumbers() {
    final base = _availableSeasons.isNotEmpty
        ? _availableSeasons
        : _derivedSeasons;
    // Keep the currently selected season listed even if nothing covers it.
    if (_selectedSeason != null && !base.contains(_selectedSeason)) {
      return ([...base, _selectedSeason!])..sort();
    }
    return base;
  }

  /// Distinct season numbers inferable from [torrents]' coverage info (pack
  /// season numbers and range bounds).
  static List<int> _deriveSeasons(List<Torrent> torrents) {
    final derived = <int>{};
    for (final t in torrents) {
      final n = t.seasonNumber;
      if (n != null && n > 0) derived.add(n);
      final start = t.startSeason;
      final end = t.endSeason;
      if (start != null && end != null && end >= start && end - start <= 50) {
        for (var s = start; s <= end; s++) {
          if (s > 0) derived.add(s);
        }
      }
    }
    return derived.toList()..sort();
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
    _kwCtrl.dispose();
    _filterFocus.removeListener(_onFilterFocusChanged);
    _filterFocus.dispose();
    _pillFocus.dispose();
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  Future<void> _reloadBound() async {
    final bound = _imdbId.isEmpty
        ? <SeriesSource>[]
        : await SeriesSourceService.getSources(_imdbId);
    if (!mounted) return;
    setState(() => _bound = bound);
  }

  /// Series pack/bind post-filter — ported verbatim from the old Home
  /// ([TorrentSearchScreen]) so this Sources list matches it. For a series with
  /// no specific episode: (1) drop direct-link (single-episode) streams — they
  /// can't be a season/series pack; (2) when a season is requested but no
  /// episode, keep only torrents that cover that season.
  List<Torrent> _filterSeriesPacks(
    List<Torrent> torrents,
    AdvancedSearchSelection sel,
  ) {
    var filtered = torrents;

    // Direct links are individual episode streams that can't be added as a
    // season/series pack. Movies are single files, so they're left alone.
    if (sel.isSeries && sel.episode == null) {
      filtered = filtered
          .where((torrent) => torrent.streamType == StreamType.torrent)
          .toList(growable: false);
    }

    // Filter by season when a season is specified but no episode, so only
    // torrents that include the requested season remain.
    if (sel.isSeries && sel.season != null && sel.episode == null) {
      final requestedSeason = sel.season!;
      filtered = filtered
          .where((torrent) {
            switch (torrent.coverageType) {
              case 'completeSeries':
                // Always include complete series (they include all seasons).
                return true;
              case 'multiSeasonPack':
                // Include if the requested season is within the range.
                if (torrent.startSeason != null && torrent.endSeason != null) {
                  return torrent.startSeason! <= requestedSeason &&
                      torrent.endSeason! >= requestedSeason;
                }
                // If season range data is missing, exclude to be safe.
                return false;
              case 'seasonPack':
                // Include only if it matches the requested season exactly.
                return torrent.seasonNumber == requestedSeason;
              case 'singleEpisode':
                // Keep only if the name resolves to the requested season.
                final name = torrent.name.toUpperCase();
                final seasonPadded = requestedSeason.toString().padLeft(2, '0');
                final seasonPatterns = [
                  'S$seasonPadded', // S04
                  'S$requestedSeason', // S4
                  'SEASON $requestedSeason', // Season 4
                  'SEASON$requestedSeason', // Season4
                  '${requestedSeason}X', // 4x (for 4x01 format)
                ];
                for (final pattern in seasonPatterns) {
                  if (name.contains(pattern)) return true;
                }
                // If we can't determine the season, exclude the single episode.
                return false;
              default:
                // Unknown coverage type — keep it to avoid over-filtering.
                return true;
            }
          })
          .toList(growable: false);
    }
    return filtered;
  }

  /// Run the source search (free-text keyword pack search in keyword-bind mode,
  /// otherwise the IMDb-exact search) and rebuild the row focus nodes. Guarded
  /// by a token so a slow earlier re-search can't clobber a newer one's results
  /// or leak its focus nodes.
  Future<void> _runSearch() async {
    final token = ++_searchToken;
    _streamBatches.clear();
    // New search → reset the cache generation: drop the previous set's badges
    // and checked-hash memo so streaming batches re-check from scratch. The
    // bumped token also invalidates any still-in-flight check from the old set.
    _cacheToken++;
    _cacheChecked.clear();
    _tbCache = null;
    _pmCache = null;
    _searching = true;
    _streamFrozen = false;
    _pendingTorrents = null;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _addonStatuses = const [];
        _retryingAddons.clear();
      });
    }
    for (final n in _nodes) {
      n.dispose();
    }
    _nodes.clear();
    try {
      final sel = _effectiveSelection;
      // Streaming: each engine's batch lands as soon as THAT engine finishes,
      // so first rows show in seconds instead of after the slowest engine's
      // timeout. Raw batches retain each provider's order; provider priority
      // and stable dedupe are applied by the toolbar presentation below. The
      // awaited result stays authoritative and snaps the list to it on
      // completion.
      void onBatch(String source, List<Torrent> batch) {
        if (!mounted || token != _searchToken || batch.isEmpty) return;
        // A timed-out engine's original future keeps running after the
        // timeout fires — its late batch must not mutate the list after the
        // awaited result already snapped it to the authoritative set.
        if (!_searching) return;
        _streamBatches.add(batch);
        _presentStreaming(
          TorrentService.mergeSearchResults(
            _streamBatches,
            preserveSourceOrder: true,
          ),
          token,
        );
        // Badge THIS engine's new rows as soon as it lands — additive, so the
        // final sweep in _finishSearch only mops up any hash no batch carried.
        _maybeCheckCache(batch);
      }

      // Match Home's Sources list: the Stremio-aware search returns BOTH torrents
      // AND addon direct-link streams for movies/series, and resolves IPTV/non-IMDb
      // items straight from the addon (it skips the on-device torrent engines for
      // non-standard content types by contentType). Previously this path was
      // torrent-only, so addon direct links never appeared in the Search tab's
      // Sources list even though Home showed them.
      final res = _keywordMode
          ? await TorrentService.searchAllEngines(
              _query,
              onBatch: onBatch,
              preserveSourceOrder: true,
            )
          : await TorrentService.searchByImdbWithStremio(
              sel.imdbId,
              isMovie: !sel.isSeries,
              season: sel.season,
              episode: sel.episode,
              contentType: sel.contentType,
              // Known seasons (from the Season chip's meta fetch) scope the
              // smart-fallback probing to seasons that actually exist.
              availableSeasons: _availableSeasons.isNotEmpty
                  ? _availableSeasons
                  : null,
              onBatch: onBatch,
              preserveSourceOrder: true,
            );
      if (!mounted || token != _searchToken) return;
      _searching = false;
      // Keyword search runs engines only — no addon statuses to show.
      // The strip follows the user's Addon Priority order when one is set.
      _addonStatuses = SourcePriority.orderBy(
        (res['addonStatuses'] as List<AddonSearchStatus>? ?? const [])
            .where(
              (status) =>
                  !SourcePriority.isRecommendationOnlyAddon(status.addonId),
            )
            .toList(growable: false),
        (status) => status.sourceKey,
        _sourcePriority,
      );
      _presentStreaming((res['torrents'] as List).cast<Torrent>(), token);
      _finishSearch(token);
    } catch (e) {
      if (!mounted || token != _searchToken) return;
      setState(() {
        _searching = false;
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// Post-processes a (provisional or final) raw result set exactly like the
  /// pre-streaming search did, then either applies it to the list or — when
  /// the user has started interacting ([_streamFrozen]) — parks it behind the
  /// "+N new sources" pill so rows never reshuffle mid-read.
  void _presentStreaming(List<Torrent> raw, int token) {
    if (!mounted || token != _searchToken) return;
    final sel = _effectiveSelection;
    // Ready-to-play addon URLs are the most useful first choice on the Sources
    // page. Keep the service's shared ranking untouched (Quick Play also uses
    // it), and invert the transport order only for this view. Explicit toolbar
    // sorts are applied later and therefore still win.
    final sourceOrdered = SourcePriority.directAddonLinksFirst(raw);
    // Series pack/bind post-processing — ported from the old Home
    // (torrent_search_screen) so this list matches. For a specific episode
    // (episode drill-down), show EVERYTHING the episode-scoped query returned
    // — engines + addon streams, torrents and direct links alike, in standard
    // merge order. No curateEpisodeCandidates here: that filter serves the
    // auto-play probe path; on this page it dropped direct links lacking an
    // S/E token in the name and floated season packs, hiding exactly the
    // per-episode sources the user drilled down for. Pack-NAMED rows the
    // episode query genuinely returned stay visible by design. Otherwise
    // (whole series/season, no episode) drop direct-link singles and apply the
    // requested season scope while retaining provider order. The Sources
    // browser does not apply an implicit relevance sort.
    final List<Torrent> torrents;
    if (sel.isSeries && sel.season != null && sel.episode != null) {
      torrents = sourceOrdered;
    } else {
      torrents = _filterSeriesPacks(sourceOrdered, sel);
    }
    if (_streamFrozen) {
      _pendingTorrents = torrents;
      if (mounted) setState(() {}); // pill count / banner update
      return;
    }
    _applyStreamingResults(torrents);
  }

  /// Swaps the displayed result set, preserving the focused row BY IDENTITY
  /// across the reshuffle (a late engine can insert rows above the D-pad
  /// focus; without this the remote lands on a different torrent).
  void _applyStreamingResults(List<Torrent> torrents) {
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
    _torrents = torrents;
    _visible = _applyToolbar(torrents);
    _syncStreamNodes();
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
    } else if (widget.isTelevision && !_streamFrozen) {
      // Live streaming on TV: keep the remote anchored to the TOP row (the
      // best-ranked source right now) — the anchor exists from the first
      // batch instead of waiting for the slowest engine.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _nodes.isEmpty || _streamFrozen) return;
        if (_filterFocus.hasFocus || _pillFocus.hasFocus) return;
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
      _derivedSeasons = _deriveSeasons(fullSet);
    }
    // A source-group pill selected for a previous search may not exist in the
    // new result set — checked ONLY here, against the authoritative full set:
    // an early batch that merely hasn't delivered that source yet must not
    // silently clear the user's filter mid-stream.
    if (_sourceFilter != null &&
        !fullSet.any(
          (t) =>
              SourcePriority.keyForSource(
                t.source,
                aliases: _sourceAliases,
              ) ==
              _sourceFilter,
        )) {
      _sourceFilter = null;
      if (_pendingTorrents == null) {
        _visible = _applyToolbar(_torrents);
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
    // On TV the list is the only content — give the D-pad an anchor to move
    // from, otherwise the remote has nothing focused and can't select a row.
    // With ZERO rows (e.g. a season scope with no packs) anchor the filter
    // funnel instead so the remote can still reach the toolbar and recover.
    // Never steal focus the user already placed somewhere mid-stream.
    if (widget.isTelevision) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_nodes.any((n) => n.hasFocus) ||
            _filterFocus.hasFocus ||
            _pillFocus.hasFocus) {
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
    _streamFrozen = true;
  }

  /// Identity key for pending-row diffing (infohash when real, else the
  /// name+URL pair addon streams are distinguished by).
  static String _rowKey(Torrent t) => t.hasRealInfoHash && t.infohash.isNotEmpty
      ? 'h:${t.infohash.toLowerCase()}'
      : 'n:${t.name}|${t.directUrl ?? ''}';

  /// Rows waiting behind the pill (0 hides it) — a SET difference, not a
  /// length delta: episode curation can shrink the pending set below the
  /// displayed length even when it carries genuinely new rows.
  int get _pendingNewCount {
    final p = _pendingTorrents;
    if (p == null) return 0;
    final shown = {for (final t in _torrents) _rowKey(t)};
    var count = 0;
    for (final t in p) {
      if (!shown.contains(_rowKey(t))) count++;
    }
    return count;
  }

  /// Folds the parked result set into the list (pill tap / toolbar use) and
  /// refreshes the ⚡ badges for the fresh rows.
  void _adoptPending() {
    final p = _pendingTorrents;
    if (p == null) return;
    _pendingTorrents = null;
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

  bool _pinning = false;

  void _play(Torrent t, int i) {
    // Swallow a SELECT that leaks through as the row menu / provider picker
    // closes on TV (armed via DialogTapGuard.markKeyAction in the menu).
    if (DialogTapGuard.shouldIgnoreTap()) return;
    _playNow(t, i);
  }

  void _playNow(Torrent t, int i) {
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
      ),
    );
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _copySourceLink(Torrent torrent) async {
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
    if (_pinning) return; // guard concurrent binds (double-tap on TV)
    _pinning = true;
    try {
      final ok = t.isDirectStream
          ? await TorrentPlaybackService.bindDirectSource(
              context,
              t,
              imdbId: _imdbId,
              isMovie: _isMovie,
            )
          : await TorrentPlaybackService.bindSource(
              context,
              t,
              imdbId: _imdbId,
              isMovie: _isMovie,
            );
      if (!mounted) return;
      if (ok) {
        await _reloadBound();
        if (widget.bindMode && mounted) Navigator.of(context).pop();
      }
    } finally {
      _pinning = false;
    }
  }

  Future<void> _unpin(SeriesSource source) async {
    await SeriesSourceService.removeSourceEntry(_imdbId, source);
    await _reloadBound();
  }

  Future<void> _pinLocal() async {
    if (_pinning) return;
    _pinning = true;
    try {
      final ok = await TorrentPlaybackService.bindLocalSource(
        context,
        imdbId: _imdbId,
        isMovie: _isMovie,
        title: widget.selection.title,
        year: widget.selection.year,
      );
      if (!mounted) return;
      if (ok) {
        await _reloadBound();
        if (widget.bindMode && mounted) Navigator.of(context).pop();
      }
    } finally {
      _pinning = false;
    }
  }

  void _showRowMenu(Torrent t, int i) {
    _freezeStreaming();
    // Direct / external addon streams have no infohash to pin — offer the
    // stream-appropriate actions (play/open + copy link), mirroring Home's
    // direct-stream action sheet.
    if (t.isDirectStream || t.isExternalStream) {
      _showStreamRowMenu(t, i);
      return;
    }
    final app = AppThemeScope.of(context);
    final binding = _bindingFor(t);
    final bound = binding != null;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: app.home.sheetBg,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.play_arrow_rounded, color: app.core.tx),
              title: const Text('Play'),
              onTap: () {
                DialogTapGuard.markKeyAction();
                Navigator.of(sheetCtx).pop();
                _playNow(t, i);
              },
            ),
            ListTile(
              leading: Icon(
                bound ? Icons.link_off_rounded : Icons.link_rounded,
                color: const Color(0xFFF59E0B),
              ),
              title: Text(bound ? 'Unpin source' : 'Pin as source'),
              subtitle: Text(
                bound
                    ? 'Stop reusing this source'
                    : 'Reuse this source for instant playback',
                style: TextStyle(color: app.fade(app.core.tx, 0.5)),
              ),
              onTap: () {
                DialogTapGuard.markKeyAction();
                Navigator.of(sheetCtx).pop();
                if (bound) {
                  unawaited(_unpin(binding));
                } else {
                  unawaited(_pin(t));
                }
              },
            ),
            if (t.copyLink != null)
              ListTile(
                leading: const Icon(
                  Icons.copy_rounded,
                  color: Color(0xFFF59E0B),
                ),
                title: const Text('Copy link'),
                onTap: () {
                  DialogTapGuard.markKeyAction();
                  Navigator.of(sheetCtx).pop();
                  unawaited(_copySourceLink(t));
                },
              ),
          ],
        ),
      ),
    );
  }

  /// Options sheet for a direct / external addon stream. Playable direct links
  /// can be pinned by addon provenance; external browser links remain open-only.
  void _showStreamRowMenu(Torrent t, int i) {
    final app = AppThemeScope.of(context);
    final external = t.isExternalStream;
    final binding = _bindingFor(t);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: app.home.sheetBg,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                external ? Icons.open_in_new_rounded : Icons.play_arrow_rounded,
                color: app.core.tx,
              ),
              title: Text(external ? 'Open externally' : 'Play now'),
              subtitle: Text(
                external
                    ? 'Open this link in your browser'
                    : 'Stream directly — no debrid needed',
                style: TextStyle(color: app.fade(app.core.tx, 0.5)),
              ),
              onTap: () {
                DialogTapGuard.markKeyAction();
                Navigator.of(sheetCtx).pop();
                _playNow(t, i);
              },
            ),
            if (!external)
              ListTile(
                leading: Icon(
                  binding != null ? Icons.link_off_rounded : Icons.link_rounded,
                  color: const Color(0xFFF59E0B),
                ),
                title: Text(binding != null ? 'Unpin source' : 'Pin as source'),
                subtitle: Text(
                  binding != null
                      ? 'Stop refreshing this stream for playback'
                      : 'Re-fetch a fresh link from this addon when played',
                  style: TextStyle(color: app.fade(app.core.tx, 0.5)),
                ),
                onTap: () {
                  DialogTapGuard.markKeyAction();
                  Navigator.of(sheetCtx).pop();
                  if (binding != null) {
                    unawaited(_unpin(binding));
                  } else {
                    unawaited(_pin(t));
                  }
                },
              ),
            ListTile(
              leading: const Icon(Icons.copy_rounded, color: Color(0xFFF59E0B)),
              title: const Text('Copy link'),
              onTap: () async {
                DialogTapGuard.markKeyAction();
                Navigator.of(sheetCtx).pop();
                await _copySourceLink(t);
              },
            ),
            if (ProfilePolicyGuard.allowsSync(ProfileFeature.downloads))
              ListTile(
                leading: const Icon(
                  Icons.download_rounded,
                  color: Color(0xFF60A5FA),
                ),
                title: const Text('Download to device'),
                subtitle: Text(
                  'Save this stream to your device',
                  style: TextStyle(color: app.fade(app.core.tx, 0.5)),
                ),
                onTap: () {
                  DialogTapGuard.markKeyAction();
                  Navigator.of(sheetCtx).pop();
                  unawaited(
                    TorrentPlaybackService.downloadDirectStream(context, t),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
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
      body: Column(
        children: [
          if (_keywordMode) _keywordSearchField(scheme),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? _centered(scheme, 'Search failed.\n$_error')
                : Column(
                    children: [
                      if (!_keywordMode) _redesignHero(scheme),
                      // Keep the toolbar when a season scope is available even
                      // with zero results — otherwise a no-result season would
                      // strand the user with no way to switch back.
                      if (_torrents.isNotEmpty ||
                          _seasonChipVisible ||
                          _hasRetryableAddon)
                        _redesignToolbar(scheme),
                      if (_searching) _searchingStrip(),
                      if (_bound.isNotEmpty) _pinnedBanner(),
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
                                      child: ListView.builder(
                                        padding: EdgeInsets.symmetric(
                                          // Spotlight expands the focused
                                          // SourceRow beyond its layout box.
                                          // At the top of the list there is no
                                          // negative scroll extent to reveal
                                          // it, so reserve TV focus room here.
                                          vertical: widget.isTelevision
                                              ? 24
                                              : 8,
                                          horizontal: 10,
                                        ),
                                        cacheExtent: 1200,
                                        itemCount: _visible.length,
                                        itemBuilder: (context, i) {
                                          final t = _visible[i];
                                          return _redesignRow(t, i);
                                        },
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
      ),
    );
  }

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
    if (_retryingAddons.contains(status.addonId)) return;
    final token = _searchToken;
    setState(() => _retryingAddons.add(status.addonId));
    try {
      final sel = _effectiveSelection;
      final batch = await StremioService.instance.retryAddonStreams(
        addonId: status.addonId,
        type: sel.contentType ?? (sel.isSeries ? 'series' : 'movie'),
        imdbId: sel.imdbId,
        season: sel.season,
        episode: sel.episode,
        timeout: StremioService.manualRetryTimeout,
        preserveOrder: true,
      );
      if (!mounted || token != _searchToken) return;
      setState(() {
        _retryingAddons.remove(status.addonId);
        _addonStatuses = [
          for (final s in _addonStatuses)
            s.addonId == status.addonId ? status.withResult(batch.length) : s,
        ];
      });
      if (batch.isEmpty) return;
      _streamBatches.add(batch);
      _presentStreaming(
        TorrentService.mergeSearchResults(
          _streamBatches,
          preserveSourceOrder: true,
        ),
        token,
      );
      _maybeCheckCache(batch);
    } catch (_) {
      if (!mounted || token != _searchToken) return;
      // Keep the failed state on the chip — it IS the error indicator.
      setState(() => _retryingAddons.remove(status.addonId));
    }
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

  /// The "+N new sources" pill: tap (or OK on TV) folds the parked arrivals
  /// into the list; DOWN returns to the rows, UP reaches the toolbar funnel.
  Widget _newSourcesPill() {
    final app = AppThemeScope.of(context);
    final accent = app.home.chromeAccent;
    final n = _pendingNewCount;
    return Focus(
      focusNode: _pillFocus,
      onKeyEvent: (node, e) {
        if (e is! KeyDownEvent) return KeyEventResult.ignored;
        if (isActivateKey(e.logicalKey)) {
          _adoptPending();
          if (_nodes.isNotEmpty) _nodes.first.requestFocus();
          return KeyEventResult.handled;
        }
        if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
          if (_nodes.isNotEmpty) _nodes.first.requestFocus();
          return KeyEventResult.handled;
        }
        if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
          // The toolbar funnel only exists in redesign mode — in the classic
          // list _filterFocus is never attached, so let the key fall through
          // rather than focusing a parentless node (dead D-pad stop).
          if (_filterFocus.context != null) {
            _filterFocus.requestFocus();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        }
        return KeyEventResult.ignored;
      },
      child: ListenableBuilder(
        listenable: _pillFocus,
        builder: (context, _) {
          final focused = _pillFocus.hasFocus;
          return GestureDetector(
            onTap: () {
              _adoptPending();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: focused ? app.core.tx : accent,
                borderRadius: app.shape.brPill,
                border: Border.all(
                  color: focused ? app.core.tx : Colors.transparent,
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.arrow_upward_rounded,
                    size: 14,
                    // Same rule as the keyword pill: unfocused the fill is the
                    // accent, so the ink is scored against it rather than
                    // hardcoded white.
                    color: focused
                        ? const Color(0xFF17131F)
                        : app.inkOn(accent),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$n new source${n == 1 ? '' : 's'}',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: focused
                          ? const Color(0xFF17131F)
                          : app.inkOn(accent),
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

  /// Derives the rendered list from [_torrents]: source-group filter →
  /// quality/rip/language filter → provider priority + stable dedupe →
  /// optional explicit field sort. "Addon order" is the default.
  List<Torrent> _applyToolbar(List<Torrent> src) {
    var list = src;
    if (_sourceFilter != null) {
      list = list
          .where(
            (t) =>
                SourcePriority.keyForSource(
                  t.source,
                  aliases: _sourceAliases,
                ) ==
                _sourceFilter,
          )
          .toList();
    }
    // Size buckets are meaningless for series: addon packs report a single
    // episode's size, so a size filter would match against a misleading
    // number. Drop the facet before matching when browsing a series.
    final effectiveFilters = widget.selection.isSeries
        ? _filters.copyWith(sizes: const <SizeBucket>{})
        : _filters;
    list = TorrentFilterMatcher.apply(list, effectiveFilters);
    list = SourcePriority.orderAndDedupe(
      list,
      _sourcePriority,
      aliases: _sourceAliases,
    );
    if (_sortBy != 'source') {
      list = List<Torrent>.from(list);
      int cmp(Torrent a, Torrent b) {
        switch (_sortBy) {
          case 'name':
            return a.displayTitle.toLowerCase().compareTo(
              b.displayTitle.toLowerCase(),
            );
          case 'size':
            return a.sizeBytes.compareTo(b.sizeBytes);
          case 'seeders':
            return a.seeders.compareTo(b.seeders);
          case 'date':
            return a.createdUnix.compareTo(b.createdUnix);
          default:
            return 0;
        }
      }

      list.sort((a, b) => _sortAsc ? cmp(a, b) : cmp(b, a));
    }
    return list;
  }

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
      _torrents = _pendingTorrents!;
      _pendingTorrents = null;
      _maybeCheckCache();
    }
    final old = List<FocusNode>.from(_nodes);
    _nodes.clear();
    _visible = _applyToolbar(_torrents);
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
  Widget _redesignToolbar(ColorScheme scheme) {
    final app = AppThemeScope.of(context);
    final accent = app.home.chromeAccent;
    final line = app.fade(app.core.tx, 0.08);
    final dim = app.fade(app.core.tx, 0.55);

    final sources = <String>{
      for (final t in _torrents)
        if (t.source.isNotEmpty) t.source,
    };
    final sourceByKey = <String, String>{
      for (final source in sources.toList()..sort())
        SourcePriority.keyForSource(source, aliases: _sourceAliases): source,
    };
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
        if (sortedKeys.length > 1 || retryByKey.isNotEmpty)
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
                      _sourceFilter = null;
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
                          if (_retryingAddons.contains(status.addonId))
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
                        _sourceFilter = key;
                        _rebuildVisible();
                      },
                      child: Text(
                        _prettySource(source),
                        style: TextStyle(
                          color: _sourceFilter == key
                              ? app.inkOn(accent)
                              : dim,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
              ],
            ),
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
                    if (next == _selectedSeason) return;
                    setState(() => _selectedSeason = next);
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
                  _sortBy = v;
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
                    _sortAsc = !_sortAsc;
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
              _filters = const TorrentFilterState.empty();
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

  /// Resolve which providers to cache-check: the pref is on, the integration is
  /// enabled, and a key is present. Only TorBox and Premiumize expose a
  /// pre-check API (RD/AllDebrid discover cachedness only by adding).
  Future<void> _loadCacheConfig() async {
    final r = await Future.wait([
      ProviderCredentialPrefs.getTorboxCacheCheckEnabled(),
      ProviderCredentialPrefs.getTorboxIntegrationEnabled(),
      StorageService.getTorboxApiKey(),
      ProviderCredentialPrefs.getPremiumizeCacheCheckEnabled(),
      ProviderCredentialPrefs.getPremiumizeIntegrationEnabled(),
      StorageService.getPremiumizeApiKey(),
    ]);
    final tbKey = r[2] as String?;
    final pmKey = r[5] as String?;
    if (!mounted) return;
    _tbCacheOn =
        (r[0] as bool) && (r[1] as bool) && (tbKey?.isNotEmpty ?? false);
    _pmCacheOn =
        (r[3] as bool) && (r[4] as bool) && (pmKey?.isNotEmpty ?? false);
    _tbKey = tbKey;
    _pmKey = pmKey;
    _maybeCheckCache();
  }

  /// Kick an additive cache check iff a provider is
  /// checkable. [rows] scopes the check to a specific set (a streaming batch);
  /// null sweeps the whole current list. Called from every path that adds rows
  /// (each batch, search completion, adopt) — [_runCacheCheck] skips hashes an
  /// earlier call already dispatched, so it's cheap to over-call.
  void _maybeCheckCache([List<Torrent>? rows]) {
    if (!_tbCacheOn && !_pmCacheOn) return;
    unawaited(_runCacheCheck(rows ?? _torrents));
  }

  /// Non-blocking: results are already rendered; this fills the cache maps for
  /// the not-yet-confirmed hashes in [rows] and setStates to add the ⚡ badges.
  /// MERGES into the maps (never replaces) so earlier batches' badges survive;
  /// the [_cacheToken] generation guards against a stale search applying. A hash
  /// enters [_cacheChecked] only after every enabled provider resolved for it,
  /// so a thrown check leaves it retryable by a later batch or the finish sweep.
  Future<void> _runCacheCheck(List<Torrent> rows) async {
    final token = _cacheToken;
    final list = <String>[];
    for (final t in rows) {
      if (!t.hasRealInfoHash) continue;
      final h = t.infohash.trim().toLowerCase();
      // contains (not add): memoize post-success below, not on dispatch.
      if (h.isEmpty || _cacheChecked.contains(h)) continue;
      list.add(h);
    }
    if (list.isEmpty) return;

    // "Done" = provider not enabled (nothing to do) OR its check succeeded.
    bool tbDone = !(_tbCacheOn && _tbKey != null);
    bool pmDone = !(_pmCacheOn && _pmKey != null);
    if (_tbCacheOn && _tbKey != null) {
      try {
        final cached = await CloudProviderRegistry.instance.checkCachedHashes(
          list,
        );
        if (!mounted || token != _cacheToken) return;
        (_tbCache ??= {}).addAll({for (final h in list) h: cached.contains(h)});
        tbDone = true;
      } catch (_) {}
    }
    if (_pmCacheOn && _pmKey != null) {
      try {
        final res = await CloudProviderRegistry.instance.checkCache(list);
        if (!mounted || token != _cacheToken) return;
        (_pmCache ??= {}).addAll({
          for (var i = 0; i < list.length; i++)
            list[i]: i < res.length && res[i],
        });
        pmDone = true;
      } catch (_) {}
    }
    // Only memoize hashes every enabled provider resolved; a failed provider
    // leaves them out so the finish sweep re-queries them.
    if (tbDone && pmDone) _cacheChecked.addAll(list);
    if (mounted && token == _cacheToken) setState(() {});
  }

  /// `TB`, `PM`, or `TB | PM` for a cached torrent; null when not cached / not
  /// yet checked / no real infohash.
  String? _cacheLabel(Torrent t) {
    if (!t.hasRealInfoHash) return null;
    final h = t.infohash.trim().toLowerCase();
    if (h.isEmpty) return null;
    final labels = <String>[
      if (_tbCacheOn && (_tbCache?[h] ?? false)) 'TB',
      if (_pmCacheOn && (_pmCache?[h] ?? false)) 'PM',
    ];
    return labels.isEmpty ? null : labels.join(' | ');
  }

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
    _filters = result;
    _rebuildVisible();
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
  Widget _redesignRow(Torrent t, int i) {
    final isStream = t.isDirectStream || t.isExternalStream;
    final tags = (_keywordMode || isStream)
        ? const <FormatTag>[]
        : FormatTagDetector.detect(t.name);
    return SourceRow(
      title: t.displayTitle,
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
      onCopy: t.copyLink == null ? null : () => unawaited(_copySourceLink(t)),
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
    if (t.isDirectStream || t.isExternalStream) {
      if (t.sizeBytes > 0) parts.add(_fmtSize(t.sizeBytes));
      if (t.source.isNotEmpty) parts.add(t.source.toUpperCase());
      return parts.join(' · ');
    }
    if (t.sizeBytes > 0) parts.add(_fmtSize(t.sizeBytes));
    if (t.seeders > 0) parts.add('↑ ${t.seeders}');
    if (t.leechers > 0) parts.add('↓ ${t.leechers}');
    if (t.source.isNotEmpty) parts.add(t.source.toUpperCase());
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

  /// Backdrop hero for the redesigned Sources screen — the title over a dimmed
  /// poster, matching the Stremio look. Non-keyword only (keyword search has no
  /// single title to feature).
  Widget _redesignHero(ColorScheme scheme) {
    final app = AppThemeScope.of(context);
    final bg = app.home.bg;
    final poster = widget.meta.posterUrl;
    return SizedBox(
      height: 128,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (poster != null && poster.isNotEmpty)
            Image.network(
              poster,
              fit: BoxFit.cover,
              // Decode at a capped width — the hero is only a ~128px strip, so a
              // full-res poster is wasted memory (and OOMs 2GB TV boxes).
              cacheWidth: 640,
              filterQuality: FilterQuality.low,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                // Byte-exact fades of the page ink: 0x59 and 0x8C of 0xFF.
                colors: [
                  app.fade(bg, 0x59 / 0xFF),
                  app.fade(bg, 0x8C / 0xFF),
                  bg,
                ],
                stops: const [0.0, 0.55, 1.0],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.selection.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: app.core.tx,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.selection.formattedLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: app.fade(app.core.tx, 0.62),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Editable free-text search box shown at the top of the keyword-bind screen.
  Widget _keywordSearchField(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: TvTextField(
        controller: _kwCtrl,
        textInputAction: TextInputAction.search,
        onSubmitted: _submitKeyword,
        style: TextStyle(color: scheme.onSurface),
        decoration: InputDecoration(
          hintText: 'Search torrents by keyword',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: IconButton(
            tooltip: 'Search',
            icon: const Icon(Icons.arrow_forward_rounded),
            onPressed: () => _submitKeyword(_kwCtrl.text),
          ),
          filled: true,
          fillColor: scheme.surfaceContainerHighest,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _pinnedBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.link_rounded,
                color: Color(0xFFF59E0B),
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                _bound.length == 1 ? 'Pinned source' : 'Pinned sources',
                style: const TextStyle(
                  color: Color(0xFFF59E0B),
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ..._bound.map(
            (s) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      s.torrentName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5),
                    ),
                  ),
                  InkWell(
                    onTap: () => unawaited(_unpin(s)),
                    borderRadius: BorderRadius.circular(8),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(
                        Icons.close_rounded,
                        color: Colors.white70,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
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

// ─── Shared Stremio-themed "Sources" dialog pieces (keyword + catalog) ───────

/// A pill knob switch, purple when on. Purely visual — the parent row owns the
/// tap/DPAD toggle so the whole row is one focus target.
class _SrcMiniToggle extends StatelessWidget {
  final bool value;
  const _SrcMiniToggle({required this.value});

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      width: 44,
      height: 26,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: value ? app.home.chromeAccent : app.fade(app.core.tx, 0.16),
        borderRadius: app.shape.brPill,
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            // ON, the knob sits on the OPAQUE accent track — a hardcoded white
            // knob is invisible on Noir's/Frost's #FFFFFF accent, so it is
            // scored like ink. OFF, the track is a dim wash over the dialog,
            // where page ink is what reads.
            color: value ? app.inkOn(app.home.chromeAccent) : app.core.tx,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

/// One toggle row in a Sources dialog: leading state chip, label (+ optional
/// subtitle), trailing [_SrcMiniToggle]. Focusable — Select/OK or tap flips it,
/// arrows fall through to directional focus so the list is DPAD-navigable.
class _SrcToggleRow extends StatefulWidget {
  final String label;
  final String? subtitle;
  final bool enabled;
  final bool autofocus;
  final ValueChanged<bool> onToggle;
  const _SrcToggleRow({
    required this.label,
    required this.enabled,
    required this.onToggle,
    this.subtitle,
    this.autofocus = false,
  });

  @override
  State<_SrcToggleRow> createState() => _SrcToggleRowState();
}

class _SrcToggleRowState extends State<_SrcToggleRow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final on = widget.enabled;
    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (isActivateKey(key) || key == LogicalKeyboardKey.space) {
          widget.onToggle(!on);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onToggle(!on),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _focused
                ? app.fade(app.core.tx, 0.08)
                : app.fade(app.core.tx, 0.03),
            borderRadius: app.shape.br(14),
            border: Border.all(
              color: _focused
                  ? app.fade(app.core.tx, 0.9)
                  : app.fade(app.core.tx, 0.06),
              width: _focused ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: on
                      ? app.fade(app.home.chromeAccent, 0.18)
                      : app.fade(app.core.tx, 0.05),
                  borderRadius: app.shape.br(10),
                ),
                child: Icon(
                  on ? Icons.check_circle_rounded : Icons.block_rounded,
                  size: 18,
                  color: on
                      ? app.home.chromeAccent
                      : app.fade(app.core.tx, 0.3),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: app.fade(app.core.tx, on ? 0.95 : 0.55),
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (widget.subtitle != null) ...[
                      const SizedBox(height: 1),
                      Text(
                        widget.subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: app.fade(app.core.tx, 0.4),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _SrcMiniToggle(value: on),
            ],
          ),
        ),
      ),
    );
  }
}

/// A focusable pill button for the Sources dialog header/footer actions
/// (Enable all / Disable all / Done). Filled = purple primary (Done).
class _SrcActionChip extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool filled;
  final VoidCallback onTap;
  const _SrcActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  @override
  State<_SrcActionChip> createState() => _SrcActionChipState();
}

class _SrcActionChipState extends State<_SrcActionChip> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (isActivateKey(key) || key == LogicalKeyboardKey.space) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: widget.filled
                ? app.fade(app.home.chromeAccent, _focused ? 1.0 : 0.9)
                : app.fade(app.core.tx, _focused ? 0.14 : 0.06),
            borderRadius: app.shape.brPill,
            border: Border.all(
              color: _focused
                  ? app.fade(app.core.tx, 0.9)
                  : app.fade(app.core.tx, 0.12),
              width: _focused ? 1.6 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 16,
                // Filled = the accent at 0.9–1.0 alpha over an opaque dialog,
                // i.e. effectively the accent itself; score the ink against it
                // (alpha is ignored by inkOn) instead of assuming white.
                color: widget.filled
                    ? app.inkOn(app.home.chromeAccent)
                    : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 7),
              Text(
                widget.label,
                style: TextStyle(
                  color: widget.filled
                      ? app.inkOn(app.home.chromeAccent)
                      : scheme.onSurface,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Stremio-themed shell for the Sources dialogs: dark glass card, purple icon
/// chip header, optional Enable-all/Disable-all row, scrolling [body], Done.
class _SrcDialogShell extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget body;
  final VoidCallback? onEnableAll;
  final VoidCallback? onDisableAll;
  const _SrcDialogShell({
    required this.title,
    required this.subtitle,
    required this.body,
    this.onEnableAll,
    this.onDisableAll,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 580),
        child: Container(
          decoration: BoxDecoration(
            color: app.home.dialogBg,
            borderRadius: app.shape.br(22),
            border: Border.all(color: app.fade(app.core.tx, 0.08)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 34,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          // Group so DPAD directional focus stays inside the dialog and walks
          // the rows/actions in a predictable order (mirrors the debrid action
          // sheet, the app's proven TV-dialog pattern).
          child: FocusTraversalGroup(
            policy: ReadingOrderTraversalPolicy(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [app.seeAll.accent, app.seeAll.accent2],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: app.shape.br(13),
                        ),
                        child: Icon(
                          Icons.dns_rounded,
                          color: app.core.tx,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: app.fade(app.core.tx, 0.5),
                                fontSize: 12,
                                height: 1.25,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (onEnableAll != null || onDisableAll != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Row(
                      children: [
                        if (onEnableAll != null)
                          _SrcActionChip(
                            icon: Icons.done_all_rounded,
                            label: 'Enable all',
                            onTap: onEnableAll!,
                          ),
                        if (onDisableAll != null) ...[
                          const SizedBox(width: 8),
                          _SrcActionChip(
                            icon: Icons.remove_done_rounded,
                            label: 'Disable all',
                            onTap: onDisableAll!,
                          ),
                        ],
                      ],
                    ),
                  ),
                Flexible(child: body),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: _SrcActionChip(
                      icon: Icons.check_rounded,
                      label: 'Done',
                      filled: true,
                      onTap: () => Navigator.of(context).pop(),
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

Widget _srcDialogMessage(BuildContext context, String text) {
  final app = AppThemeScope.of(context);
  return Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
    child: Text(
      text,
      style: TextStyle(color: app.fade(app.core.tx, 0.6), height: 1.4),
    ),
  );
}

Widget _srcDialogLoading(BuildContext context) => SizedBox(
  height: 120,
  child: Center(
    child: CircularProgressIndicator(
      color: AppThemeScope.of(context).home.chromeAccent,
    ),
  ),
);

/// Enable/disable the search-capable Stremio addons queried by catalog search.
/// Stores the DISABLED set (empty = all on) via StorageService so it sticks.
class CatalogSourcesDialog extends StatefulWidget {
  // ignore: use_key_in_widget_constructors
  const CatalogSourcesDialog();

  @override
  State<CatalogSourcesDialog> createState() => _CatalogSourcesDialogState();
}

class _CatalogSourcesDialogState extends State<CatalogSourcesDialog> {
  List<StremioAddon> _addons = [];
  Set<String> _disabled = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final addons = await StremioService.instance.getSearchableAddons();
    final disabled = await StorageService.getCatalogSearchDisabledAddons();
    if (!mounted) return;
    setState(() {
      _addons = addons;
      _disabled = disabled;
      _loading = false;
    });
  }

  // Persist immediately so the choice sticks even if the app is killed before
  // the dialog closes.
  void _toggle(String addonId, bool enabled) {
    setState(() {
      if (enabled) {
        _disabled.remove(addonId);
      } else {
        _disabled.add(addonId);
      }
    });
    StorageService.setCatalogSearchDisabledAddons(_disabled);
  }

  void _enableAll() {
    setState(() => _disabled = {});
    StorageService.setCatalogSearchDisabledAddons(_disabled);
  }

  void _disableAll() {
    setState(() => _disabled = _addons.map((a) => a.id).toSet());
    StorageService.setCatalogSearchDisabledAddons(_disabled);
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (_loading) {
      body = _srcDialogLoading(context);
    } else if (_addons.isEmpty) {
      body = _srcDialogMessage(
        context,
        'No search-capable addons installed. Add a catalog addon that '
        'supports search (e.g. Cinemeta) from Addons.',
      );
    } else {
      body = ListView.builder(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
        shrinkWrap: true,
        itemCount: _addons.length,
        itemBuilder: (context, i) {
          final a = _addons[i];
          final searchable = a.catalogs.where((c) => c.supportsSearch).length;
          return _SrcToggleRow(
            label: a.name,
            subtitle: searchable > 1 ? '$searchable searchable catalogs' : null,
            enabled: !_disabled.contains(a.id),
            autofocus: i == 0,
            onToggle: (v) => _toggle(a.id, v),
          );
        },
      );
    }
    return _SrcDialogShell(
      title: 'Search sources',
      subtitle: 'Choose which addons catalog search queries.',
      onEnableAll: _addons.isEmpty ? null : _enableAll,
      onDisableAll: _addons.isEmpty ? null : _disableAll,
      body: body,
    );
  }
}

class KeywordSourcesDialog extends StatefulWidget {
  // ignore: use_key_in_widget_constructors
  const KeywordSourcesDialog();

  @override
  State<KeywordSourcesDialog> createState() => _KeywordSourcesDialogState();
}

class _KeywordSourcesDialogState extends State<KeywordSourcesDialog> {
  final SettingsManager _settings = SettingsManager();
  List<DynamicEngine> _engines = [];
  final Map<String, bool> _enabled = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Use the same combined set the search actually queries — registry engines
    // PLUS user-configured IndexerManager (Jackett/Prowlarr/Torznab) engines —
    // so those indexers are toggleable here, not silently queried but hidden.
    final engines = await TorrentService.getKeywordSearchEngines();
    for (final e in engines) {
      // Seed with the SAME per-engine default the search uses
      // (TorrentService._isEngineSelected), so a source the user configured as
      // disabled by default doesn't show ON here while not actually being
      // queried. Hardcoding `true` desynced IndexerManager engines.
      final def = e.settingsConfig.enabled?.defaultBool ?? true;
      _enabled[e.name] = await _settings.getEnabled(e.name, def);
    }
    if (!mounted) return;
    setState(() {
      _engines = engines;
      _loading = false;
    });
  }

  void _set(String name, bool v) {
    setState(() => _enabled[name] = v);
    _settings.setEnabled(name, v);
  }

  void _setAll(bool v) {
    setState(() {
      for (final e in _engines) {
        _enabled[e.name] = v;
      }
    });
    for (final e in _engines) {
      _settings.setEnabled(e.name, v);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (_loading) {
      body = _srcDialogLoading(context);
    } else if (_engines.isEmpty) {
      body = _srcDialogMessage(context, 'No search sources installed.');
    } else {
      body = ListView.builder(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
        shrinkWrap: true,
        itemCount: _engines.length,
        itemBuilder: (context, i) {
          final e = _engines[i];
          return _SrcToggleRow(
            label: e.displayName,
            enabled: _enabled[e.name] ?? true,
            autofocus: i == 0,
            onToggle: (v) => _set(e.name, v),
          );
        },
      );
    }
    return _SrcDialogShell(
      title: 'Search sources',
      subtitle: 'Choose which trackers keyword search queries.',
      onEnableAll: _engines.isEmpty ? null : () => _setAll(true),
      onDisableAll: _engines.isEmpty ? null : () => _setAll(false),
      body: body,
    );
  }
}
