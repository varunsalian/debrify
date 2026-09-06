import 'dart:async';

import '../models/stremio_addon.dart';
import 'storage_service.dart';
import 'trakt/trakt_list_source.dart';
import 'watched_filter.dart';
import 'simkl/simkl_list_source.dart';
import 'mdblist/mdblist_list_source.dart';

/// ID grammar for the opt-in extra Home rows (see
/// [StorageService.getHomeExtraRows]). Kept together so the board, the
/// resolver and the Home Rows manager can never drift on what an id means.
class HomeExtraRowIds {
  HomeExtraRowIds._();

  static const String traktPrefix = 'traktlist:';
  static const String traktCustomPrefix = 'traktlist:custom:';
  static const String traktLikedPrefix = 'traktlist:liked:';
  static const String simklPrefix = 'simkllist:';
  static const String mdblistPrefix = 'mdblistlist:';
  static const String mdblistMinePrefix = 'mdblistlist:mine:';
  static const String mdblistLikedPrefix = 'mdblistlist:liked:';
  static const String mdblistTopPrefix = 'mdblistlist:top:';
  static const String iptvPrefix = 'iptvlist:';

  /// `traktlist:watchlist` … — built-ins key off the API slug, which is
  /// stable across enum reorderings.
  static String traktBuiltin(TraktSeeAllList list) =>
      '$traktPrefix${list.apiValue}';

  static String traktUserList(TraktListChoice choice) => choice.liked
      ? '$traktLikedPrefix${choice.userListId}'
      : '$traktCustomPrefix${choice.userListId}';

  /// `simkllist:planToWatch` … — enum names are part of the storage contract;
  /// renaming a [SimklSeeAllList] value needs a migration.
  static String simkl(SimklSeeAllList list) => '$simklPrefix${list.name}';

  static String mdblistMine(MdblistListChoice list) =>
      '$mdblistMinePrefix${list.id}';
  static String mdblistLiked(MdblistListChoice list) =>
      '$mdblistLikedPrefix${list.id}';
  static String mdblistTop(MdblistListChoice list) =>
      '$mdblistTopPrefix${list.id}';

  static String iptvList(String listId) => '$iptvPrefix$listId';

  static bool isTracker(String id) =>
      id.startsWith(traktPrefix) ||
      id.startsWith(simklPrefix) ||
      id.startsWith(mdblistPrefix);

  static bool isMdblist(String id) => id.startsWith(mdblistPrefix);

  static bool isTraktUserList(String id) =>
      id.startsWith(traktCustomPrefix) || id.startsWith(traktLikedPrefix);

  static bool isIptv(String id) => id.startsWith(iptvPrefix);

  /// The `<listId>` of an `iptvlist:` id (null for anything else).
  static String? iptvListId(String id) =>
      isIptv(id) ? id.substring(iptvPrefix.length) : null;
}

/// A Home board row backed by a Trakt/Simkl list instead of an addon catalog.
///
/// Subclassing [CatalogSection] is the point: these rows flow through the
/// classic board ListView, all six TV stage layouts, `_rowNodes` focus
/// bookkeeping, hero seeding and the search-detour restore without any new
/// threading. The synthetic [addon] is a placeholder (same shape as
/// `_addonForContinue`'s fallback) — item opens must NOT route through it
/// (the board dispatches Trakt/Simkl items via their own handlers), and
/// [CatalogSection.exhausted] is latched true so the row never tries to page.
class HomeListSection extends CatalogSection {
  /// The row's `home_extra_rows_v1` id (`traktlist:…` / `simkllist:…`).
  final String rowId;

  /// Set for Trakt rows — the choice to reopen See-All on.
  final TraktListChoice? traktChoice;

  /// Set for Simkl rows — the list to reopen See-All on.
  final SimklSeeAllList? simklList;
  final MdblistListChoice? mdblistList;

  bool get isTrakt => traktChoice != null;
  bool get isMdblist => mdblistList != null;

  static final StremioAddon traktPlaceholderAddon = StremioAddon(
    id: 'debrify.home.trakt',
    name: 'Trakt',
    manifestUrl: '',
    baseUrl: '',
  );

  static final StremioAddon simklPlaceholderAddon = StremioAddon(
    id: 'debrify.home.simkl',
    name: 'Simkl',
    manifestUrl: '',
    baseUrl: '',
  );
  static final StremioAddon mdblistPlaceholderAddon = StremioAddon(
    id: 'debrify.home.mdblist',
    name: 'MDBList',
    manifestUrl: '',
    baseUrl: '',
  );

  // `title` cannot be a super parameter: it's also the synthetic catalog's
  // name, and super parameters aren't in scope in the initializer list.
  // ignore: use_super_parameters
  HomeListSection({
    required this.rowId,
    required String title,
    required super.items,
    this.traktChoice,
    this.simklList,
    this.mdblistList,
  }) : assert(
         [traktChoice, simklList, mdblistList].where((v) => v != null).length ==
             1,
       ),
       super(
         title: title,
         addon: traktChoice != null
             ? traktPlaceholderAddon
             : mdblistList != null
             ? mdblistPlaceholderAddon
             : simklPlaceholderAddon,
         catalog: StremioAddonCatalog(id: rowId, type: 'mixed', name: title),
         // Fully loaded in one shot — `_loadMoreRow` must never page these.
         exhausted: true,
       );
}

/// Loads the opted-in Trakt/Simkl list rows for the Home board.
///
/// Pure data logic, stateless. The board calls [resolve] with the stored
/// extras; IPTV rows are NOT handled here (different item type and render
/// family — the board loads them alongside its favourites rows).
class HomeListRowsService {
  HomeListRowsService({
    Future<({List<StremioMeta> items, bool failed})> Function(TraktListChoice)?
    traktLoad,
    Future<List<TraktListChoice>> Function()? traktUserLists,
    Future<({List<StremioMeta> items, bool failed})> Function(SimklSeeAllList)?
    simklLoad,
    Future<({List<StremioMeta> items, bool failed, bool complete})> Function(
      MdblistListChoice,
    )?
    mdblistLoad,
    Future<List<MdblistListChoice>> Function()? mdblistMine,
    Future<List<MdblistListChoice>> Function()? mdblistLiked,
    Future<List<MdblistListChoice>> Function()? mdblistTop,
  }) : _traktLoad = traktLoad ?? ((c) => TraktListSource.instance.loadList(c)),
       _traktUserLists =
           traktUserLists ?? TraktListSource.instance.loadUserLists,
       _simklLoad = simklLoad ?? SimklListSource.instance.loadList,
       _mdblistLoad = mdblistLoad ?? MdblistListSource.instance.loadListItems,
       _mdblistMine = mdblistMine ?? MdblistListSource.instance.loadUserLists,
       _mdblistLiked =
           mdblistLiked ?? MdblistListSource.instance.loadLikedLists,
       _mdblistTop = mdblistTop ?? MdblistListSource.instance.loadTopLists;

  static final HomeListRowsService instance = HomeListRowsService();

  final Future<({List<StremioMeta> items, bool failed})> Function(
    TraktListChoice,
  )
  _traktLoad;
  final Future<List<TraktListChoice>> Function() _traktUserLists;
  final Future<({List<StremioMeta> items, bool failed})> Function(
    SimklSeeAllList,
  )
  _simklLoad;
  final Future<({List<StremioMeta> items, bool failed, bool complete})>
  Function(MdblistListChoice)
  _mdblistLoad;
  final Future<List<MdblistListChoice>> Function() _mdblistMine;
  final Future<List<MdblistListChoice>> Function() _mdblistLiked;
  final Future<List<MdblistListChoice>> Function() _mdblistTop;

  /// At most this many list fetches in flight per provider — each Trakt
  /// built-in fans out 2 HTTP calls and a Simkl list up to 3, so an uncapped
  /// "everything enabled" config would fire ~30 concurrent requests and
  /// invite throttling.
  static const int _perProviderCap = 3;

  /// Resolve the enabled extras into board-ready sections, in canonical
  /// order: Trakt built-ins (enum order), Trakt custom lists (account
  /// order), Trakt liked lists (account order), then Simkl (enum order).
  ///
  /// Rows whose fetch failed or returned empty are dropped — a row simply
  /// doesn't appear, matching how empty addon catalogs are skipped. With a
  /// [deadline], returns the rows whose fetches HAVE completed by then and
  /// drops only the stragglers (their in-flight requests aren't cancelled;
  /// the results are discarded). Returns immediately when no tracker ids are
  /// enabled, so the default config costs nothing.
  Future<List<HomeListSection>> resolve(
    List<HomeExtraRow> enabled, {
    Duration? deadline,
  }) async {
    final byId = <String, HomeExtraRow>{
      for (final r in enabled)
        if (HomeExtraRowIds.isTracker(r.id)) r.id: r,
    };
    if (byId.isEmpty) return const [];

    final slots = <_Slot>[];
    final traktPool = _CappedPool(_perProviderCap);
    final simklPool = _CappedPool(_perProviderCap);
    final mdblistPool = _CappedPool(_perProviderCap);

    // Trakt built-ins, enum order.
    var rank = 0;
    for (final list in TraktSeeAllList.values) {
      if (list == TraktSeeAllList.continueWatching) continue;
      final id = HomeExtraRowIds.traktBuiltin(list);
      if (!byId.containsKey(id)) continue;
      final slot = _Slot(rank++, 0);
      slots.add(slot);
      traktPool.add(() async {
        final choice = TraktListChoice.builtin(list);
        final r = await _traktLoad(choice);
        final items = list.hidesWatched
            ? WatchedFilter.apply(List.of(r.items))
            : List.of(r.items);
        if (items.isEmpty) return;
        slot.section = HomeListSection(
          rowId: id,
          title: list.label,
          items: items,
          traktChoice: choice,
        );
      });
    }
    final customRankBase = rank;

    // Trakt custom/liked lists: one user-lists fetch re-resolves the raw
    // choices by id (a stored id alone can't reach the items endpoint —
    // liked lists need the owner/slug from the account payload). Vanished
    // (deleted/unliked) lists simply never fill their slot. The whole chain
    // runs inside the pool so the deadline covers it.
    final userListIds = byId.keys
        .where(HomeExtraRowIds.isTraktUserList)
        .toSet();
    if (userListIds.isNotEmpty) {
      final userSlots = <String, _Slot>{
        for (final id in userListIds)
          // Custom before liked; within a group, account order (assigned
          // when the fetch resolves — stored-title order until then is
          // irrelevant because unresolved slots are dropped).
          id: _Slot(
            customRankBase +
                (id.startsWith(HomeExtraRowIds.traktLikedPrefix) ? 1 : 0),
            0,
          ),
      };
      slots.addAll(userSlots.values);
      traktPool.add(() async {
        List<TraktListChoice> lists;
        try {
          lists = await _traktUserLists();
        } catch (_) {
          return;
        }
        var order = 0;
        for (final choice in lists) {
          if (choice.userListId == null) continue;
          final id = HomeExtraRowIds.traktUserList(choice);
          final slot = userSlots[id];
          final within = order++;
          if (slot == null) continue;
          slot.withinRank = within;
          traktPool.add(() async {
            final r = await _traktLoad(choice);
            if (r.items.isEmpty) return;
            slot.section = HomeListSection(
              rowId: id,
              title: byId[id]!.title.isNotEmpty
                  ? byId[id]!.title
                  : choice.label,
              items: List.of(r.items),
              traktChoice: choice,
            );
          });
        }
      });
    }
    rank = customRankBase + 2;

    // Simkl, enum order.
    for (final list in SimklSeeAllList.values) {
      if (list == SimklSeeAllList.continueWatching) continue;
      final id = HomeExtraRowIds.simkl(list);
      if (!byId.containsKey(id)) continue;
      final slot = _Slot(rank++, 0);
      slots.add(slot);
      simklPool.add(() async {
        final r = await _simklLoad(list);
        if (r.items.isEmpty) return;
        slot.section = HomeListSection(
          rowId: id,
          title: list.label,
          items: List.of(r.items),
          simklList: list,
        );
      });
    }

    final mdblistIds = byId.keys.where(HomeExtraRowIds.isMdblist).toSet();
    if (mdblistIds.isNotEmpty) {
      final mdblistRank = rank++;
      final mdblistSlots = <String, _Slot>{
        for (final id in mdblistIds) id: _Slot(mdblistRank, 0),
      };
      slots.addAll(mdblistSlots.values);
      mdblistPool.add(() async {
        // Only refresh directories represented by enabled rows. Previously a
        // single saved MDBList row fetched My, Liked, and Top on every Home
        // load even though two responses could not possibly resolve its id.
        final requestedGroups = <Future<Map<String, MdblistListChoice>>>[
          if (mdblistIds.any(
            (id) => id.startsWith(HomeExtraRowIds.mdblistMinePrefix),
          ))
            _mdblistMine().then(
              (choices) => {
                for (final choice in choices)
                  HomeExtraRowIds.mdblistMine(choice): choice,
              },
            ),
          if (mdblistIds.any(
            (id) => id.startsWith(HomeExtraRowIds.mdblistLikedPrefix),
          ))
            _mdblistLiked().then(
              (choices) => {
                for (final choice in choices)
                  HomeExtraRowIds.mdblistLiked(choice): choice,
              },
            ),
          if (mdblistIds.any(
            (id) => id.startsWith(HomeExtraRowIds.mdblistTopPrefix),
          ))
            _mdblistTop().then(
              (choices) => {
                for (final choice in choices)
                  HomeExtraRowIds.mdblistTop(choice): choice,
              },
            ),
        ];
        final choicesById = <String, MdblistListChoice>{};
        for (final group in await Future.wait(requestedGroups)) {
          choicesById.addAll(group);
        }
        var order = 0;
        for (final entry in choicesById.entries) {
          final slot = mdblistSlots[entry.key];
          if (slot == null) continue;
          slot.withinRank = order++;
          mdblistPool.add(() async {
            final result = await _mdblistLoad(entry.value);
            if (!result.complete) return;
            // Public "top" lists hide watched titles; the user's own and
            // liked lists never do.
            final items =
                entry.key.startsWith(HomeExtraRowIds.mdblistTopPrefix) &&
                    !entry.value.liked
                ? WatchedFilter.apply(List.of(result.items))
                : List.of(result.items);
            if (items.isEmpty) return;
            slot.section = HomeListSection(
              rowId: entry.key,
              title: byId[entry.key]!.title.isNotEmpty
                  ? byId[entry.key]!.title
                  : entry.value.label,
              items: items,
              mdblistList: entry.value,
            );
          });
        }
      });
    }

    final all = Future.wait([traktPool.idle, simklPool.idle, mdblistPool.idle]);
    if (deadline == null) {
      await all;
    } else {
      // Collect whatever has completed at the deadline — one slow list must
      // not discard every already-loaded row.
      await Future.any<void>([all, Future<void>.delayed(deadline)]);
    }

    final done =
        [
          for (final s in slots)
            if (s.section != null) s,
        ]..sort((a, b) {
          final byGroup = a.rank.compareTo(b.rank);
          return byGroup != 0 ? byGroup : a.withinRank.compareTo(b.withinRank);
        });
    return [for (final s in done) s.section!];
  }
}

/// An ordered result slot: [rank] fixes the canonical group position at
/// creation, [withinRank] orders user lists by account order once known.
class _Slot {
  _Slot(this.rank, this.withinRank);
  final int rank;
  int withinRank;
  HomeListSection? section;
}

/// A tiny worker pool: at most [cap] jobs run at once; jobs may [add] more
/// jobs while running (the user-lists chain does). [idle] completes when the
/// queue is empty AND nothing is in flight. Job errors are swallowed — a
/// failed fetch just leaves its slot unfilled.
class _CappedPool {
  _CappedPool(this.cap);
  final int cap;

  final List<Future<void> Function()> _queue = [];
  int _active = 0;
  Completer<void>? _idle;

  void add(Future<void> Function() job) {
    _queue.add(job);
    _pump();
  }

  Future<void> get idle {
    if (_active == 0 && _queue.isEmpty) return Future.value();
    return (_idle ??= Completer<void>()).future;
  }

  void _pump() {
    while (_active < cap && _queue.isNotEmpty) {
      final job = _queue.removeAt(0);
      _active++;
      Future<void>(job).catchError((_) {}).whenComplete(() {
        _active--;
        if (_active == 0 && _queue.isEmpty) {
          _idle?.complete();
          _idle = null;
        } else {
          _pump();
        }
      });
    }
  }
}
