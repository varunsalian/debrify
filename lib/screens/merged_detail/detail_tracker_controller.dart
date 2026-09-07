import 'package:flutter/material.dart';

import '../../services/mdblist/mdblist_menu_helpers.dart';
import '../../services/mdblist/mdblist_models.dart';
import '../../services/simkl/simkl_menu_helpers.dart';
import '../../services/simkl/simkl_service.dart';
import '../../services/trakt/trakt_service.dart';
import '../../theme/app_theme_scope.dart';
import '../../widgets/detail/detail_tracker_sheets.dart';
import '../../widgets/tracker_brand_marks.dart';
import '../../widgets/trakt/trakt_menu_helpers.dart';

/// Everything the tracker block reads off its host, re-read on every access so
/// a rebuilt host (a fresh option list, an enriched title) is seen the same way
/// the State's own `widget.`/`_item` reads used to see it.
class DetailTrackerInputs {
  const DetailTrackerInputs({
    required this.title,
    required this.isTelevision,
    this.traktMenuOptions = const [],
    this.traktMenuBuilder,
    this.onTraktAction,
    this.traktStatusLoader,
    this.onTraktRate,
    this.simklMenuOptions = const [],
    this.simklMenuBuilder,
    this.onSimklAction,
    this.simklStatusLoader,
    this.onSimklRate,
    this.mdblistMenuOptions = const [],
    this.mdblistMenuBuilder,
    this.onMdblistAction,
    this.mdblistStatusLoader,
  });

  /// The title the sheets head themselves with — the enriched name when one
  /// has landed, so it tracks the page rather than the route argument.
  final String title;
  final bool isTelevision;

  final List<TraktMenuOption> traktMenuOptions;
  final List<TraktMenuOption> Function(TraktTitleStatus? status)?
  traktMenuBuilder;
  final Future<void> Function(TraktItemMenuAction action)? onTraktAction;
  final Future<TraktTitleStatus?> Function()? traktStatusLoader;
  final Future<void> Function(int rating)? onTraktRate;

  final List<SimklMenuOption> simklMenuOptions;
  final List<SimklMenuOption> Function(SimklTitleStatus? status)?
  simklMenuBuilder;
  final Future<void> Function(SimklItemMenuAction action)? onSimklAction;
  final Future<SimklTitleStatus?> Function()? simklStatusLoader;
  final Future<void> Function(int rating)? onSimklRate;

  final List<MdblistMenuOption> mdblistMenuOptions;
  final List<MdblistMenuOption> Function(MdblistTitleStatus? status)?
  mdblistMenuBuilder;
  final Future<void> Function(MdblistItemMenuAction action)? onMdblistAction;
  final Future<MdblistTitleStatus?> Function()? mdblistStatusLoader;
}

/// The merged detail page's tracker-status engine: the live Trakt / Simkl /
/// MDBList relationships to the title, the pill labels compressed out of them,
/// the app-vs-tracker split of the one incoming Trakt option list, and the
/// three quick-actions sheets that change any of it.
///
/// A [ChangeNotifier] rather than a widget because the same state feeds three
/// separate surfaces (the action row's pills, the [DetailModel] the alternate
/// layouts render from, and the primary button's "Rewatch" label): the host
/// listens once and rebuilds, exactly as its `setState` calls used to.
class DetailTrackerController extends ChangeNotifier {
  DetailTrackerController({required this.read});

  /// Live view of the host's configuration. Called at every use rather than
  /// captured, so it behaves like the `widget.…` reads it replaces.
  final DetailTrackerInputs Function() read;

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// The user's live Trakt relationship to this title (watchlist / collection /
  /// watched / rating). Null until [DetailTrackerInputs.traktStatusLoader]
  /// resolves — the menu then falls back to the add-only `traktMenuOptions`.
  /// Re-read after a quick action and when the player pops back.
  TraktTitleStatus? _traktStatus;
  TraktTitleStatus? get traktStatus => _traktStatus;

  /// Whether the status loaders have answered at least once. A null status
  /// means "untracked" only *after* this flips — before it, the answer simply
  /// isn't in yet, and the pill must not claim the title is untracked.
  bool _traktStatusResolved = false;
  bool _simklStatusResolved = false;
  bool _mdblistStatusResolved = false;

  /// The user's live Simkl relationship to this title. Null until
  /// `simklStatusLoader` resolves — mirrors [traktStatus] one-for-one.
  SimklTitleStatus? _simklStatus;
  SimklTitleStatus? get simklStatus => _simklStatus;

  MdblistTitleStatus? _mdblistStatus;
  MdblistTitleStatus? get mdblistStatus => _mdblistStatus;

  /// The quick-actions strip to render: rebuilt against [traktStatus] when a
  /// builder was supplied, else the static list passed in.
  List<TraktMenuOption> get _menuOptions {
    final inputs = read();
    return inputs.traktMenuBuilder?.call(_traktStatus) ??
        inputs.traktMenuOptions;
  }

  /// Debrify's own actions. They arrive inside the Trakt option list (that list
  /// has always carried both), but none of them touch Trakt — so they get the
  /// neutral "More" sheet and the Trakt sheet stays purely Trakt. Being app
  /// actions they're also available when Trakt is disconnected, which the old
  /// single-menu arrangement only managed by keeping an always-present Trakt
  /// button.
  static const Set<TraktItemMenuAction> appOwnedActions = {
    TraktItemMenuAction.selectSource,
    TraktItemMenuAction.addToStremioTv,
    TraktItemMenuAction.playRandomEpisode,
    TraktItemMenuAction.searchPacks,
    TraktItemMenuAction.removeFromPlayback,
  };

  List<TraktMenuOption> get appMenuOptions => [
    for (final o in _menuOptions)
      if (appOwnedActions.contains(o.action)) o,
  ];

  List<TraktMenuOption> get traktOnlyMenuOptions => [
    for (final o in _menuOptions)
      if (!appOwnedActions.contains(o.action)) o,
  ];

  /// The Simkl quick-actions strip to render: rebuilt against [simklStatus]
  /// when a builder was supplied, else the static list passed in.
  List<SimklMenuOption> get menuOptionsSimkl {
    final inputs = read();
    return inputs.simklMenuBuilder?.call(_simklStatus) ??
        inputs.simklMenuOptions;
  }

  List<MdblistMenuOption> get menuOptionsMdblist {
    final inputs = read();
    return inputs.mdblistMenuBuilder?.call(_mdblistStatus) ??
        inputs.mdblistMenuOptions;
  }

  // ── Status loads ──────────────────────────────────────────────────────────

  /// Kick every tracker's status read at once — the page's opening beat, and
  /// again whenever the player pops back.
  void loadAll() {
    loadTraktStatus();
    loadSimklStatus();
    loadMdblistStatus();
  }

  /// Resolve the user's Trakt relationship to this title so the menu shows
  /// Add ↔ Remove toggles and the hero can badge Watchlist/Collection/Watched/
  /// rating. Silent on failure — the menu just stays add-only.
  Future<void> loadTraktStatus() async {
    final loader = read().traktStatusLoader;
    if (loader == null) return;
    try {
      final status = (await loader())?.preserveWatchedFrom(_traktStatus);
      if (_disposed || status == null) return;
      _traktStatus = status;
      notifyListeners();
    } catch (_) {
    } finally {
      // Resolved either way: a failed read is still an answered question as
      // far as the pill is concerned — it stops saying "Checking…" and falls
      // back to the untracked form rather than spinning forever.
      if (!_disposed && !_traktStatusResolved) {
        _traktStatusResolved = true;
        notifyListeners();
      }
    }
  }

  /// Resolve the user's Simkl relationship to this title — mirrors
  /// [loadTraktStatus] exactly.
  Future<void> loadSimklStatus() async {
    final loader = read().simklStatusLoader;
    if (loader == null) return;
    try {
      final status = await loader();
      if (_disposed || status == null) return;
      _simklStatus = status;
      notifyListeners();
    } catch (_) {
    } finally {
      if (!_disposed && !_simklStatusResolved) {
        _simklStatusResolved = true;
        notifyListeners();
      }
    }
  }

  Future<void> loadMdblistStatus() async {
    final loader = read().mdblistStatusLoader;
    if (loader == null) return;
    try {
      final status = await loader();
      if (_disposed || status == null) return;
      _mdblistStatus = status;
      notifyListeners();
    } catch (_) {
    } finally {
      if (!_disposed && !_mdblistStatusResolved) {
        _mdblistStatusResolved = true;
        notifyListeners();
      }
    }
  }

  // ── Pill state ────────────────────────────────────────────────────────────

  /// Whether Trakt holds any relationship to this title. Drives the pill's
  /// tinted (tracked) vs. outline (untracked) form.
  bool get traktTracked {
    final s = _traktStatus;
    return s != null &&
        (s.inWatchlist ||
            s.inCollection ||
            s.titleWatched == true ||
            s.rating != null);
  }

  bool get simklTracked =>
      _simklStatus?.currentStatus != null || _simklStatus?.rating != null;

  bool get mdblistTracked {
    final s = _mdblistStatus;
    return s != null &&
        (s.inWatchlist ||
            s.collected ||
            s.watched ||
            s.completed == true ||
            s.dropped == true ||
            s.rating != null);
  }

  /// The live Trakt state, compressed to fit inside the pill. Trakt allows
  /// several relationships at once, so they're joined with "·" and capped at
  /// two — the rating rides in the pill's own compartment, not here.
  ///
  /// While the loader is still out this reads "Checking…" rather than "Not
  /// tracked": the row keeps its geometry either way, and asserting the title
  /// *isn't* on your watchlist when it is — for however long the call takes —
  /// is worse than admitting we don't know yet.
  String get traktPillLabel {
    final s = _traktStatus;
    if (s == null &&
        !_traktStatusResolved &&
        read().traktStatusLoader != null) {
      return 'Checking…';
    }
    if (s == null) return 'Not tracked';
    final parts = <String>[
      if (s.inWatchlist) 'Watchlist',
      if (s.inCollection) 'Collected',
      if (s.titleWatched == true) 'Watched',
    ];
    if (parts.isEmpty) {
      if (s.rating != null) return 'Rated';
      return s.titleWatched == null ? 'Status unavailable' : 'Not tracked';
    }
    return parts.take(2).join(' · ');
  }

  /// Simkl is single-state by definition, so its pill never needs to join
  /// anything — it's the one watchlist status, or nothing.
  String get simklPillLabel {
    final status = _simklStatus?.currentStatus;
    if (status != null) return _simklStatusLabel(status);
    if (_simklStatus?.rating != null) return 'Rated';
    if (!_simklStatusResolved && read().simklStatusLoader != null) {
      return 'Checking…';
    }
    return 'Not tracked';
  }

  String get mdblistPillLabel {
    final s = _mdblistStatus;
    if (s == null &&
        !_mdblistStatusResolved &&
        read().mdblistStatusLoader != null) {
      return 'Checking…';
    }
    if (s == null) return 'Not tracked';
    final parts = <String>[
      if (s.inWatchlist) 'Watchlist',
      if (s.collected) 'Collected',
      if (s.completed == true || s.watched) 'Watched',
      if (s.dropped == true) 'Dropped',
    ];
    if (parts.isEmpty) return s.rating == null ? 'Not tracked' : 'Rated';
    return parts.take(2).join(' · ');
  }

  static String _simklStatusLabel(String status) {
    switch (status) {
      case 'plantowatch':
        return 'Plan to Watch';
      case 'watching':
        return 'Watching';
      case 'hold':
        return 'On Hold';
      case 'completed':
        return 'Completed';
      case 'dropped':
        return 'Dropped';
      default:
        return status;
    }
  }

  // ── Sheets ────────────────────────────────────────────────────────────────

  /// Debrify's own actions, in a plain labelled list. Closes on selection —
  /// each of these leaves the sheet anyway (a picker, a search, playback).
  void showAppActionsMenu(BuildContext context) {
    final inputs = read();
    final options = appMenuOptions;
    if (options.isEmpty || inputs.onTraktAction == null) return;
    showModalBottomSheet<void>(
      context: context,
      // Same standard sheet chrome as the per-episode ⋮ menu.
      backgroundColor: AppThemeScope.of(context).sheetSurface,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetCtx) => DetailQuickActionsMenu(
        title: inputs.title,
        options: options,
        isTelevision: inputs.isTelevision,
        onSelected: (action) async {
          Navigator.of(sheetCtx).pop();
          await read().onTraktAction?.call(action);
          // Binding a source changes the pill's count, and "Remove from
          // Continue Watching" changes the resume label.
          if (!_disposed) notifyListeners();
        },
      ),
    );
  }

  /// The Trakt sheet: watchlist / collection / watched as switches, plus an
  /// inline rating strip and the list actions.
  ///
  /// Unlike the app sheet this one stays open — a tracker sheet is somewhere
  /// you set several things at once, and each row re-reads the live status so
  /// the switches show the truth rather than an optimistic guess.
  void showTraktQuickActionsMenu(BuildContext context) {
    final inputs = read();
    if (traktOnlyMenuOptions.isEmpty || inputs.onTraktAction == null) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppThemeScope.of(context).sheetSurface,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetCtx) => DetailTraktSheet(
        title: inputs.title,
        isTelevision: inputs.isTelevision,
        status: _traktStatus,
        optionsFor: (status) => [
          for (final o
              in read().traktMenuBuilder?.call(status) ??
                  read().traktMenuOptions)
            if (!appOwnedActions.contains(o.action)) o,
        ],
        onAction: (action) async {
          await read().onTraktAction?.call(action);
        },
        onRate: inputs.onTraktRate,
        statusLoader: inputs.traktStatusLoader,
        // Keep the pill in sync with whatever the sheet did while it was open.
        onChanged: (status) {
          if (!_disposed) {
            _traktStatus = status;
            _traktStatusResolved = true;
            notifyListeners();
          }
        },
      ),
    );
  }

  /// Simkl's own sheet — mirrors [showTraktQuickActionsMenu], but Simkl's five
  /// statuses are mutually exclusive, so they render as an exclusive toggle
  /// group instead of a list of "Move to X" commands.
  void showSimklQuickActionsMenu(BuildContext context) {
    final inputs = read();
    if (menuOptionsSimkl.isEmpty || inputs.onSimklAction == null) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppThemeScope.of(context).sheetSurface,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetCtx) => DetailSimklSheet(
        title: inputs.title,
        isTelevision: inputs.isTelevision,
        status: _simklStatus,
        optionsFor: (status) =>
            read().simklMenuBuilder?.call(status) ?? read().simklMenuOptions,
        onAction: (action) async {
          await read().onSimklAction?.call(action);
        },
        onRate: inputs.onSimklRate,
        statusLoader: inputs.simklStatusLoader,
        onChanged: (status) {
          if (!_disposed) {
            _simklStatus = status;
            _simklStatusResolved = true;
            notifyListeners();
          }
        },
      ),
    );
  }

  void showMdblistQuickActionsMenu(BuildContext context) {
    final inputs = read();
    if (menuOptionsMdblist.isEmpty || inputs.onMdblistAction == null) return;
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640, maxHeight: 620),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            children: [
              Text(
                inputs.title,
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              const Text(
                'MDBList',
                style: TextStyle(
                  color: kMdblistPurple,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              for (final option in menuOptionsMdblist)
                ListTile(
                  leading: Icon(option.icon, color: option.color),
                  title: Text(option.label),
                  onTap: () async {
                    await read().onMdblistAction?.call(option.action);
                    await loadMdblistStatus();
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
