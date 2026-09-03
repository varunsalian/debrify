import 'package:flutter/material.dart';
import '../../utils/tv_reveal.dart';
import 'package:flutter/services.dart';

import '../../models/home_collection.dart';
import '../../models/stremio_addon.dart';
import '../../services/home_collections_store.dart';
import '../../services/home_list_rows.dart';
import '../../services/home_row_order.dart';
import '../../services/iptv_media_store.dart' show IptvListMeta;
import '../../services/simkl/simkl_list_source.dart';
import '../../services/mdblist/mdblist_service.dart';
import '../../services/mdblist/mdblist_list_source.dart';
import '../../services/storage_service.dart';
import '../../services/trakt/trakt_list_source.dart';
import '../../services/analytics_service.dart';
import '../../utils/tv_keys.dart';
import '../../widgets/home/home_theme.dart';
import '../../models/tracking_source.dart';

/// Full-screen DPAD-first Home-row manager — a two-pane "group → item" filter,
/// modelled on the Stremio TV channel filter's grammar but 2 levels deep (no
/// genre wall). The left rail lists groups (Continue Watching, Trakt, Simkl,
/// IPTV Lists, Favorites, then each catalog addon); the right pane lists that
/// group's rows as on/off toggles. Header actions: All on / All off / Invert.
///
/// Three stores back the leaves. Default-ON rows persist the same disabled-id
/// set the Home board reads ([StorageService.setHomeDisabledSections]): fixed
/// leaves like `cw:movies`, `trakt:shows`, `fav:iptv`, and catalog leaves
/// `addonId:type:catalogId` — only OFF rows are stored. OPT-IN rows (Trakt/
/// Simkl list rows, IPTV custom-list rows — default off) persist the enabled
/// entries instead ([StorageService.setHomeExtraRows], id + display title).
/// Their global position is saved separately with
/// [StorageService.setHomeRowOrder].
///
/// An enabled opt-in row whose backing data didn't load (Trakt outage, a
/// vanished list) is still materialized as an "unavailable" leaf from its
/// stored title, so a save can never silently delete it — selections survive
/// an outage and come back with it.
class HomeSectionsFilterPage extends StatefulWidget {
  /// The board's catalog addons with their browsable catalogs, in board order.
  final List<({StremioAddon addon, List<StremioAddonCatalog> catalogs})>
  catalogTree;
  final Set<String> disabled;

  /// The currently opted-in extra rows (`home_extra_rows_v1`).
  final List<HomeExtraRow> extraRows;

  /// The global row order (`home_row_order_v1`). Unknown ids are preserved
  /// when this page saves so temporarily unavailable rows keep their slot.
  final List<String> rowOrder;

  /// The account's Trakt custom + liked lists, pre-fetched by the opener
  /// (empty when unauthenticated or the fetch failed — enabled entries then
  /// surface as unavailable leaves).
  final List<TraktListChoice> traktUserLists;
  final List<MdblistListChoice> mdblistMine;
  final List<MdblistListChoice> mdblistLiked;
  final List<MdblistListChoice> mdblistTop;

  /// The user's IPTV lists (incl. Favorites, which is filtered out here — it
  /// already has the `fav:iptv` leaf).
  final List<IptvListMeta> iptvLists;

  /// Imported collections (each is one default-on `collection:<id>` row).
  final List<HomeCollection> collections;

  final bool isTelevision;

  const HomeSectionsFilterPage({
    super.key,
    required this.catalogTree,
    required this.disabled,
    this.extraRows = const [],
    this.rowOrder = const [],
    this.traktUserLists = const [],
    this.mdblistMine = const [],
    this.mdblistLiked = const [],
    this.mdblistTop = const [],
    this.iptvLists = const [],
    this.collections = const [],
    required this.isTelevision,
  });

  @override
  State<HomeSectionsFilterPage> createState() => _HomeSectionsFilterPageState();
}

/// One toggleable Home row. [defaultOn] rows persist to the disabled set when
/// OFF; opt-in rows ([defaultOn] false) persist to the extras store when ON,
/// carrying [extraTitle] as the row's display name. [unavailable] marks an
/// enabled opt-in leaf whose backing data didn't load this visit.
class _Item {
  final String id;
  final String label;
  final String? badge; // catalog type badge (MOVIE/SERIES/…); null for fixed
  final bool defaultOn;
  final String? extraTitle;
  final bool unavailable;

  /// False for leaves toggled here that are not Home rows (the lists inside
  /// a collection folder), so they never enter the row order or Arrange view.
  final bool arrangeable;
  bool on;
  _Item(
    this.id,
    this.label,
    this.on, {
    this.badge,
    this.defaultOn = true,
    this.extraTitle,
    this.unavailable = false,
    this.arrangeable = true,
  });
}

/// A rail group whose items are the rows shown under it.
class _Group {
  final String name;
  final List<_Item> items;
  _Group(this.name, this.items);

  int get onCount => items.where((it) => it.on).length;
  int get total => items.length;
}

class _ArrangeEntry {
  final _Item item;
  final String group;
  const _ArrangeEntry(this.item, this.group);
}

class _HomeSectionsFilterPageState extends State<HomeSectionsFilterPage> {
  static const Color _onColor = Color(0xFF34D399);
  static const Color _offColor = Color(0xFF4B465F);

  late final List<_Group> _groups;
  int _selectedGroup = 0;
  int _selectedItem = 0;
  bool _changed = false;
  bool _saved = false;

  final List<FocusNode> _headerNodes = List.generate(
    4,
    (i) => FocusNode(debugLabel: 'homeHeader$i'),
  );
  List<FocusNode> _railNodes = [];
  List<FocusNode> _listNodes = [];
  final List<FocusNode> _arrangeNodes = [];

  late List<String> _orderIds;
  bool _arranging = false;
  String? _pickedArrangeId;

  /// Where a down-press from the header should land back.
  (String, int) _headerReturn = ('rail', 0);
  String _area = 'rail';

  /// Narrow (phone) layout: one pane at a time.
  bool _narrow = false;
  bool _narrowList = false;

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('home_sections_filter');
    _groups = _buildModel();
    final seededOrder = HomeRowOrder.insertMissingAfter(
      widget.rowOrder,
      additions: const ['mdblist:movies', 'mdblist:shows'],
      anchors: const ['simkl:movies', 'simkl:shows'],
    );
    _orderIds = HomeRowOrder.reconcile(seededOrder, _canonicalOrderIds());
    _railNodes = List.generate(
      _groups.length,
      (i) => FocusNode(debugLabel: 'homeRail$i'),
    );
    _rebuildListNodes();
    _syncArrangeNodes();
    // Land focus on the first rail group so DPAD works the moment the page
    // opens (this post-frame fires — the first build schedules a frame).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_railNodes.isNotEmpty) {
        _railNodes.first.requestFocus();
      } else {
        _headerNodes.first.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    for (final n in _headerNodes) {
      n.dispose();
    }
    for (final n in _railNodes) {
      n.dispose();
    }
    for (final n in _listNodes) {
      n.dispose();
    }
    for (final n in _arrangeNodes) {
      n.dispose();
    }
    super.dispose();
  }

  List<_Group> _buildModel() {
    final d = widget.disabled;
    bool on(String id) => !d.contains(id);
    final extraById = {for (final r in widget.extraRows) r.id: r};
    bool extraOn(String id) => extraById.containsKey(id);
    _Item cw(String id, String label, TrackingSource source, {String? badge}) =>
        _Item(id, label, on(id), badge: badge);

    // Opt-in leaf factory: ON = present in the extras store.
    _Item opt(String id, String label, {String? badge}) => _Item(
      id,
      label,
      extraOn(id),
      badge: badge,
      defaultOn: false,
      extraTitle: label,
    );

    final customLists = [
      for (final c in widget.traktUserLists)
        if (!c.liked && c.userListId != null) c,
    ];
    final likedLists = [
      for (final c in widget.traktUserLists)
        if (c.liked && c.userListId != null) c,
    ];

    final groups = <_Group>[
      _Group('Continue Watching', [
        cw('cw:movies', 'Movies', TrackingSource.local),
        cw('cw:series', 'Series', TrackingSource.local),
      ]),
      _Group('Trakt', [
        cw('trakt:movies', 'Movies', TrackingSource.trakt, badge: 'CW'),
        cw('trakt:shows', 'Shows', TrackingSource.trakt, badge: 'CW'),
        for (final l in TraktSeeAllList.values)
          if (l != TraktSeeAllList.continueWatching)
            opt(HomeExtraRowIds.traktBuiltin(l), l.label, badge: 'LIST'),
        for (final c in customLists)
          opt(HomeExtraRowIds.traktUserList(c), c.label, badge: 'CUSTOM'),
        for (final c in likedLists)
          opt(HomeExtraRowIds.traktUserList(c), c.label, badge: 'LIKED'),
      ]),
      _Group('Simkl', [
        cw('simkl:movies', 'Movies', TrackingSource.simkl, badge: 'CW'),
        cw('simkl:shows', 'Shows', TrackingSource.simkl, badge: 'CW'),
        for (final l in SimklSeeAllList.values)
          if (l != SimklSeeAllList.continueWatching)
            opt(HomeExtraRowIds.simkl(l), l.label, badge: 'LIST'),
      ]),
      if (kMdblistEnabled)
        _Group('MDBList', [
          cw('mdblist:movies', 'Movies', TrackingSource.mdblist, badge: 'CW'),
          cw('mdblist:shows', 'Shows', TrackingSource.mdblist, badge: 'CW'),
          for (final l in widget.mdblistMine)
            opt(HomeExtraRowIds.mdblistMine(l), l.label, badge: 'MINE'),
          for (final l in widget.mdblistLiked)
            opt(HomeExtraRowIds.mdblistLiked(l), l.label, badge: 'LIKED'),
          for (final l in widget.mdblistTop)
            opt(HomeExtraRowIds.mdblistTop(l), l.label, badge: 'TOP'),
        ]),
      _Group('IPTV Continue Watching', [
        _Item('iptv:movies', 'Movies', on('iptv:movies')),
        _Item('iptv:series', 'Series', on('iptv:series')),
      ]),
      if (widget.iptvLists.any((m) => !m.isFavorites))
        _Group('IPTV Lists', [
          for (final m in widget.iptvLists)
            if (!m.isFavorites)
              opt(HomeExtraRowIds.iptvList(m.id), m.name, badge: 'LIST'),
        ]),
      if (widget.collections.isNotEmpty)
        _Group('Collections', [
          for (final c in widget.collections)
            _Item(
              c.rowId,
              c.title,
              on(c.rowId),
              badge: c.pinToTop ? 'PINNED' : 'FOLDERS',
            ),
        ]),
      // Each folder's catalog lists: toggled here like any addon catalog but
      // never arranged, since they live inside the folder, not on the board.
      for (final c in widget.collections)
        for (final f in c.folders)
          if (f.sources.isNotEmpty)
            _Group('${c.title} › ${f.title}', [
              for (final s in f.sources)
                _Item(
                  HomeCollectionRowIds.folderList(c.id, f.id, s),
                  _folderListLabel(s),
                  on(HomeCollectionRowIds.folderList(c.id, f.id, s)),
                  badge: s.type,
                  arrangeable: false,
                ),
            ]),
      _Group('My Watchlist', [
        _Item('watchlist:movies', 'Movies', on('watchlist:movies')),
        _Item('watchlist:series', 'Series', on('watchlist:series')),
      ]),
      _Group('Favorites', [
        _Item('fav:playlist', 'Playlist', on('fav:playlist')),
        _Item('fav:debrify', 'Debrify TV', on('fav:debrify')),
        _Item('fav:stremio', 'Stremio TV', on('fav:stremio')),
        _Item('fav:iptv', 'IPTV', on('fav:iptv')),
      ]),
    ];

    // Enabled opt-in rows the groups above couldn't represent (Trakt outage,
    // a deleted list, an unmatched id): materialize each as an UNAVAILABLE
    // leaf from its stored title so it stays visible, survives a save
    // verbatim, and can still be deliberately turned off.
    final represented = <String>{
      for (final g in groups)
        for (final it in g.items) it.id,
    };
    _Item stray(HomeExtraRow r) => _Item(
      r.id,
      r.title.isNotEmpty ? r.title : r.id,
      true,
      defaultOn: false,
      extraTitle: r.title,
      unavailable: true,
    );
    for (final r in widget.extraRows) {
      if (represented.contains(r.id)) continue;
      final String groupName;
      if (r.id.startsWith(HomeExtraRowIds.traktPrefix)) {
        groupName = 'Trakt';
      } else if (r.id.startsWith(HomeExtraRowIds.simklPrefix)) {
        groupName = 'Simkl';
      } else if (r.id.startsWith(HomeExtraRowIds.mdblistPrefix)) {
        groupName = 'MDBList';
      } else if (r.id.startsWith(HomeExtraRowIds.iptvPrefix)) {
        groupName = 'IPTV Lists';
      } else {
        continue; // unknown grammar — preserved by _persist, not shown
      }
      final target = groups.cast<_Group?>().firstWhere(
        (g) => g!.name == groupName,
        orElse: () => null,
      );
      if (target != null) {
        target.items.add(stray(r));
      } else {
        groups.add(_Group(groupName, [stray(r)]));
      }
    }

    // Catalogs claimed by a collection folder are listed under that folder
    // above, not under their addon (the board skips them too).
    final claimed = HomeCollectionsStore.claimedCatalogKeys(
      widget.collections,
      [for (final e in widget.catalogTree) e.addon],
    );
    for (final entry in widget.catalogTree) {
      final addon = entry.addon;
      final items = [
        for (final c in entry.catalogs)
          if (!claimed.contains('${addon.id}:${c.type}:${c.id}'))
            _Item(
              '${addon.id}:${c.type}:${c.id}',
              c.name,
              on('${addon.id}:${c.type}:${c.id}'),
              badge: c.type,
            ),
      ];
      if (items.isEmpty) continue;
      groups.add(_Group(addon.name, items));
    }
    return groups;
  }

  /// "Popular Movies · Action" for a folder list, resolved against the
  /// installed addons. Falls back to the raw catalog id when nothing serves
  /// it, so the list can still be switched off deliberately.
  String _folderListLabel(CollectionCatalogSource s) {
    final addons = [for (final e in widget.catalogTree) e.addon];
    final addon = HomeCollectionsStore.resolveAddon(s, addons);
    final catalog = addon == null
        ? null
        : HomeCollectionsStore.resolveCatalog(s, addon);
    final base = catalog == null
        ? '${s.catalogId} (${s.type})'
        : CatalogSection.rowTitle(catalog);
    return s.genre == null ? base : '$base · ${s.genre}';
  }

  /// The board's pre-customization order. Keep this aligned with Home's row
  /// assembly: Continue Watching, favourites/IPTV lists, tracker list rows,
  /// then addon catalogs. The settings page groups rows by provider for
  /// toggling, so simply flattening [_groups] would produce a different order.
  List<String> _canonicalOrderIds() {
    final items = <String, _Item>{
      for (final group in _groups)
        for (final item in group.items) item.id: item,
    };
    final out = <String>[];
    final seen = <String>{};
    void add(String id) {
      if (items.containsKey(id) && seen.add(id)) out.add(id);
    }

    for (final id in const [
      'cw:movies',
      'cw:series',
      'trakt:movies',
      'trakt:shows',
      'simkl:movies',
      'simkl:shows',
      'mdblist:movies',
      'mdblist:shows',
      'iptv:movies',
      'iptv:series',
      'watchlist:movies',
      'watchlist:series',
      'fav:playlist',
      'fav:debrify',
      'fav:stremio',
      'fav:iptv',
    ]) {
      add(id);
    }
    for (final group in _groups) {
      for (final item in group.items) {
        if (HomeExtraRowIds.isIptv(item.id)) add(item.id);
      }
    }
    for (final group in _groups) {
      for (final item in group.items) {
        if (HomeExtraRowIds.isTracker(item.id)) add(item.id);
      }
    }
    // Collection rows follow the tracker lists and lead the addon catalogs,
    // matching the board's placement of unpinned collections.
    for (final group in _groups) {
      for (final item in group.items) {
        if (HomeCollectionRowIds.isCollection(item.id)) add(item.id);
      }
    }
    // Anything left is an addon catalog (or a future row family unknown to
    // this version). Stable group/item order is the safest default for both.
    for (final group in _groups) {
      for (final item in group.items) {
        if (item.arrangeable) add(item.id);
      }
    }
    return out;
  }

  List<_ArrangeEntry> get _arrangeEntries {
    final entries = [
      for (final group in _groups)
        for (final item in group.items)
          if (item.on && item.arrangeable) _ArrangeEntry(item, group.name),
    ];
    return HomeRowOrder.apply(entries, _orderIds, (entry) => entry.item.id);
  }

  void _syncArrangeNodes() {
    final count = _arrangeEntries.length;
    while (_arrangeNodes.length < count) {
      _arrangeNodes.add(
        FocusNode(debugLabel: 'homeArrange${_arrangeNodes.length}'),
      );
    }
    while (_arrangeNodes.length > count) {
      _arrangeNodes.removeLast().dispose();
    }
  }

  /// Reorder only the enabled rows while leaving disabled and unknown ids in
  /// their saved slots. Re-enabling one later therefore restores its position.
  void _moveArrangeEntry(int from, int to) {
    final entries = _arrangeEntries;
    if (from < 0 || from >= entries.length || to < 0 || to >= entries.length) {
      return;
    }
    if (from == to) return;
    final enabledIds = [for (final entry in entries) entry.item.id];
    final moved = enabledIds.removeAt(from);
    enabledIds.insert(to, moved);
    final enabledSet = enabledIds.toSet();
    var cursor = 0;
    _mutate(() {
      _orderIds = [
        for (final id in _orderIds)
          if (enabledSet.contains(id)) enabledIds[cursor++] else id,
      ];
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _arrangeNodes.isEmpty) return;
      final target = to.clamp(0, _arrangeNodes.length - 1);
      _arrangeNodes[target].requestFocus();
      _ensureVisible(_arrangeNodes[target]);
    });
  }

  (int, int) get _totals {
    var on = 0, total = 0;
    for (final g in _groups) {
      on += g.onCount;
      total += g.total;
    }
    return (on, total);
  }

  Future<void> _persist() async {
    if (!_changed || _saved) return;
    _saved = true;
    // Default-on rows: store only the OFF ids (empty set = everything shown
    // → key removed). Opt-in rows: store the ON entries with their display
    // titles.
    final out = <String>{};
    final extras = <HomeExtraRow>[];
    final modelIds = <String>{};
    for (final g in _groups) {
      for (final it in g.items) {
        modelIds.add(it.id);
        if (it.defaultOn) {
          if (!it.on) out.add(it.id);
        } else if (it.on) {
          extras.add((id: it.id, title: it.extraTitle ?? it.label));
        }
      }
    }
    // Never destroy what the model couldn't see: any stored extra whose id
    // built no leaf at all (unknown grammar, future version) survives a save
    // verbatim. Unavailable leaves are already IN the model, so a deliberate
    // toggle-off still removes those.
    for (final r in widget.extraRows) {
      if (!modelIds.contains(r.id)) extras.add(r);
    }
    await StorageService.setHomeDisabledSections(out);
    await StorageService.setHomeExtraRows(extras);
    await StorageService.setHomeRowOrder(_orderIds);
  }

  // ── Mutations ──────────────────────────────────────────────────────────────
  void _mutate(VoidCallback fn) {
    setState(() {
      _changed = true;
      _saved = false;
      fn();
    });
  }

  // Header actions target the SELECTED group's rows (the 2nd pane), not every
  // group — scoped so "All off" clears just the group you're looking at.
  void _setCurrentGroup(bool v) => _mutate(() {
    for (final it in _groups[_selectedGroup].items) {
      it.on = v;
    }
  });

  void _invertCurrentGroup() => _mutate(() {
    for (final it in _groups[_selectedGroup].items) {
      it.on = !it.on;
    }
  });

  /// Not-all-on → all on; all-on → all off (matches the TV filter).
  void _toggleGroup(int i) => _mutate(() {
    final g = _groups[i];
    final v = g.onCount != g.total;
    for (final it in g.items) {
      it.on = v;
    }
  });

  void _toggleItem(_Item it) => _mutate(() => it.on = !it.on);

  void _setArrangeMode(bool value) {
    if (_arranging == value) return;
    setState(() {
      _arranging = value;
      _pickedArrangeId = null;
      if (value) _syncArrangeNodes();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (value && _arrangeNodes.isNotEmpty) {
        _arrangeNodes.first.requestFocus();
      } else if (!value && _railNodes.isNotEmpty) {
        _railNodes[_selectedGroup].requestFocus();
      }
    });
  }

  // ── Focus plumbing ───────────────────────────────────────────────────────
  void _rebuildListNodes() {
    for (final n in _listNodes) {
      n.dispose();
    }
    _listNodes = List.generate(
      _groups.isEmpty ? 0 : _groups[_selectedGroup].items.length,
      (i) => FocusNode(debugLabel: 'homeList$i'),
    );
  }

  void _selectGroup(int i) {
    if (i == _selectedGroup) return;
    setState(() {
      _selectedGroup = i;
      _selectedItem = 0;
      _rebuildListNodes();
    });
  }

  void _focusAfterFrame(FocusNode node) {
    // Focus NOW if the node is already mounted (wide layout builds both panes);
    // a bare post-frame callback never fires when switching panes schedules no
    // rebuild, stranding DPAD focus on the current pane. Narrow mode setState()s
    // to build the target pane first, so defer to post-frame until it mounts.
    if (node.context != null) {
      node.requestFocus();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) node.requestFocus();
    });
  }

  void _showListPane({int? focusIndex}) {
    if (_narrow && !_narrowList) setState(() => _narrowList = true);
    if (focusIndex != null && _listNodes.isNotEmpty) {
      _focusAfterFrame(_listNodes[focusIndex.clamp(0, _listNodes.length - 1)]);
    }
  }

  void _showRailPane() {
    if (_narrow && _narrowList) setState(() => _narrowList = false);
    if (_railNodes.isNotEmpty) _focusAfterFrame(_railNodes[_selectedGroup]);
  }

  void _ensureVisible(FocusNode node) {
    final ctx = node.context;
    if (ctx == null) return;
    tvRevealMinimal(ctx, duration: const Duration(milliseconds: 120));
  }

  // ── DPAD handlers ────────────────────────────────────────────────────────
  KeyEventResult _headerKey(int i, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (_arranging) {
      if (k == LogicalKeyboardKey.arrowDown) {
        if (_arrangeNodes.isNotEmpty) _arrangeNodes.first.requestFocus();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowUp ||
          k == LogicalKeyboardKey.arrowLeft ||
          k == LogicalKeyboardKey.arrowRight) {
        return KeyEventResult.handled;
      }
      if (isActivateKey(k)) {
        _setArrangeMode(false);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (k == LogicalKeyboardKey.arrowLeft) {
      if (i > 0) _headerNodes[i - 1].requestFocus();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight) {
      if (i < _headerNodes.length - 1) _headerNodes[i + 1].requestFocus();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown) {
      if (_narrow) {
        if (_narrowList && _listNodes.isNotEmpty) {
          _listNodes[_selectedItem.clamp(0, _listNodes.length - 1)]
              .requestFocus();
        } else if (_railNodes.isNotEmpty) {
          _railNodes[_selectedGroup].requestFocus();
        }
        return KeyEventResult.handled;
      }
      final (area, index) = _headerReturn;
      if (area == 'list' && index < _listNodes.length) {
        _listNodes[index].requestFocus();
      } else if (_railNodes.isNotEmpty) {
        _railNodes[index.clamp(0, _railNodes.length - 1)].requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp) return KeyEventResult.handled;
    if (isActivateKey(k)) {
      switch (i) {
        case 0:
          _setCurrentGroup(true);
        case 1:
          _setCurrentGroup(false);
        case 2:
          _invertCurrentGroup();
        case 3:
          _setArrangeMode(true);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _railKey(int i, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowDown) {
      if (i < _railNodes.length - 1) {
        _selectGroup(i + 1);
        _railNodes[i + 1].requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp) {
      if (i == 0) {
        if (e is KeyDownEvent) {
          _headerReturn = ('rail', 0);
          _headerNodes.first.requestFocus();
        }
      } else {
        _selectGroup(i - 1);
        _railNodes[i - 1].requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (e is! KeyDownEvent) return KeyEventResult.handled;
    if (k == LogicalKeyboardKey.arrowRight) {
      _showListPane(focusIndex: _selectedItem);
      return KeyEventResult.handled;
    }
    if (isActivateKey(k)) {
      _toggleGroup(i);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _listKey(int i, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;
    final items = _groups[_selectedGroup].items;
    if (k == LogicalKeyboardKey.arrowDown) {
      if (i < items.length - 1) {
        _selectedItem = i + 1;
        _listNodes[i + 1].requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp) {
      if (i == 0) {
        if (e is KeyDownEvent) {
          _headerReturn = ('list', 0);
          _headerNodes.first.requestFocus();
        }
      } else {
        _selectedItem = i - 1;
        _listNodes[i - 1].requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (e is! KeyDownEvent) return KeyEventResult.handled;
    if (k == LogicalKeyboardKey.arrowLeft ||
        k == LogicalKeyboardKey.escape ||
        k == LogicalKeyboardKey.goBack) {
      _showRailPane();
      return KeyEventResult.handled;
    }
    if (isActivateKey(k)) {
      _toggleItem(items[i]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _arrangeKey(int i, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final entries = _arrangeEntries;
    if (i < 0 || i >= entries.length) return KeyEventResult.ignored;
    final id = entries[i].item.id;
    final picked = _pickedArrangeId == id;
    final key = e.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp) {
      if (picked && i > 0) {
        _moveArrangeEntry(i, i - 1);
      } else if (i == 0) {
        if (e is KeyDownEvent) _headerNodes[3].requestFocus();
      } else {
        _arrangeNodes[i - 1].requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (picked && i < entries.length - 1) {
        _moveArrangeEntry(i, i + 1);
      } else if (i < entries.length - 1) {
        _arrangeNodes[i + 1].requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (e is! KeyDownEvent) return KeyEventResult.handled;
    if (isActivateKey(key)) {
      setState(() => _pickedArrangeId = picked ? null : id);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.arrowLeft) {
      if (_pickedArrangeId != null) {
        setState(() => _pickedArrangeId = null);
      } else {
        _setArrangeMode(false);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ── Build ────────────────────────────────────────────────────────────────
  Future<void> _saveAndClose() async {
    await _persist();
    if (mounted) Navigator.of(context).pop(_changed);
  }

  @override
  Widget build(BuildContext context) {
    final (on, total) = _totals;
    _narrow = MediaQuery.sizeOf(context).width < 640;
    if (!_narrow) _narrowList = false;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_arranging) {
          _setArrangeMode(false);
        } else if ((_narrowList || _area == 'list') && _railNodes.isNotEmpty) {
          _showRailPane();
        } else {
          _saveAndClose();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Container(
          decoration: HomeTheme.pageBackground,
          child: SafeArea(
            child: Column(
              children: [
                _buildHeader(on, total),
                Expanded(child: _buildPanes()),
                if (widget.isTelevision) _buildHintBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(int on, int total) {
    final backButton = IconButton(
      onPressed: _arranging ? () => _setArrangeMode(false) : _saveAndClose,
      icon: Icon(
        Icons.arrow_back_rounded,
        color: Colors.white.withValues(alpha: 0.7),
      ),
    );
    final title = Text(
      _arranging ? 'Arrange Home Rows' : 'Home Screen',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 19,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.2,
      ),
    );
    final countPill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$on',
              style: const TextStyle(
                color: _onColor,
                fontWeight: FontWeight.w800,
              ),
            ),
            TextSpan(text: _narrow ? ' / $total on' : ' / $total rows on'),
          ],
        ),
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.65),
          fontSize: 12.5,
        ),
      ),
    );
    if (_narrow) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [backButton, const SizedBox(width: 4), title]),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  countPill,
                  if (_arranging)
                    _actionButton(3, 'Done')
                  else ...[
                    _actionButton(0, 'All on'),
                    _actionButton(1, 'All off'),
                    _actionButton(2, 'Invert'),
                    _actionButton(3, 'Arrange'),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
      child: Row(
        children: [
          backButton,
          const SizedBox(width: 4),
          title,
          const SizedBox(width: 14),
          countPill,
          const Spacer(),
          if (_arranging)
            _actionButton(3, 'Done')
          else ...[
            _actionButton(0, 'All on'),
            const SizedBox(width: 8),
            _actionButton(1, 'All off'),
            const SizedBox(width: 8),
            _actionButton(2, 'Invert'),
            const SizedBox(width: 8),
            _actionButton(3, 'Arrange'),
          ],
        ],
      ),
    );
  }

  Widget _actionButton(int i, String label) {
    final node = _headerNodes[i];
    return Focus(
      focusNode: node,
      onFocusChange: (f) {
        if (f) {
          _area = 'header';
          _ensureVisible(node);
        }
      },
      onKeyEvent: (_, e) => _headerKey(i, e),
      child: ListenableBuilder(
        listenable: node,
        builder: (context, _) {
          final focused = node.hasFocus;
          return GestureDetector(
            onTap: () {
              switch (i) {
                case 0:
                  _setCurrentGroup(true);
                case 1:
                  _setCurrentGroup(false);
                case 2:
                  _invertCurrentGroup();
                case 3:
                  _setArrangeMode(!_arranging);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(99),
                border: Border.all(
                  color: focused
                      ? HomeTheme.focusGold
                      : Colors.white.withValues(alpha: 0.16),
                  width: focused ? 2 : 1,
                ),
                // Bloom only off-TV — an animated/static blur shadow re-rasters
                // on every focus move and janks weak TV GPUs (perf playbook).
                boxShadow: focused && !widget.isTelevision
                    ? [
                        BoxShadow(
                          color: HomeTheme.focusGoldDeep.withValues(alpha: 0.4),
                          blurRadius: 12,
                        ),
                      ]
                    : null,
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: focused
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.7),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPanes() {
    if (_arranging) return _buildArrangeList();
    if (_narrow) {
      if (!_narrowList) return _buildRail();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildNarrowBreadcrumb(),
          Expanded(child: _buildItemList()),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 300, child: _buildRail()),
        Container(width: 0.5, color: Colors.white.withValues(alpha: 0.07)),
        Expanded(child: _buildItemList()),
      ],
    );
  }

  Widget _buildArrangeList() {
    final entries = _arrangeEntries;
    if (entries.isEmpty) {
      return Center(
        child: Text(
          'Turn on at least one row before arranging.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 6, 24, 10),
          child: Text(
            widget.isTelevision
                ? 'Press OK to pick up a row, move it with ↑↓, then press OK to drop.'
                : 'Drag rows into the order you want. Hidden rows keep their saved positions.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 12.5,
            ),
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            buildDefaultDragHandles: false,
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
            itemCount: entries.length,
            onReorderItem: _moveArrangeEntry,
            itemBuilder: (context, i) {
              final entry = entries[i];
              final node = _arrangeNodes[i];
              final picked = _pickedArrangeId == entry.item.id;
              return Focus(
                key: ValueKey('arrange:${entry.item.id}'),
                focusNode: node,
                onFocusChange: (focused) {
                  if (!focused) return;
                  _area = 'arrange';
                  _ensureVisible(node);
                },
                onKeyEvent: (_, event) => _arrangeKey(i, event),
                child: ListenableBuilder(
                  listenable: node,
                  builder: (context, _) {
                    final focused = node.hasFocus;
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        node.requestFocus();
                        if (widget.isTelevision) {
                          setState(
                            () => _pickedArrangeId = picked
                                ? null
                                : entry.item.id,
                          );
                        }
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: picked
                              ? HomeTheme.chromeAccent.withValues(alpha: 0.16)
                              : Colors.white.withValues(alpha: 0.025),
                          borderRadius: BorderRadius.circular(13),
                          border: Border.all(
                            color: focused || picked
                                ? HomeTheme.focusGold
                                : Colors.white.withValues(alpha: 0.05),
                            width: focused || picked ? 2 : 1.5,
                          ),
                        ),
                        child: Row(
                          children: [
                            ReorderableDragStartListener(
                              index: i,
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Icon(
                                  Icons.drag_indicator_rounded,
                                  color: Colors.white.withValues(alpha: 0.45),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            SizedBox(
                              width: 28,
                              child: Text(
                                '${i + 1}',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.42),
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    entry.item.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    entry.group,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.45,
                                      ),
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (picked) ...[
                              const SizedBox(width: 8),
                              _typeBadge('MOVING'),
                            ],
                            const SizedBox(width: 8),
                            _arrangeMoveButton(
                              icon: Icons.arrow_upward_rounded,
                              enabled: i > 0,
                              onTap: () => _moveArrangeEntry(i, i - 1),
                            ),
                            _arrangeMoveButton(
                              icon: Icons.arrow_downward_rounded,
                              enabled: i < entries.length - 1,
                              onTap: () => _moveArrangeEntry(i, i + 1),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _arrangeMoveButton({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(
          icon,
          size: 19,
          color: Colors.white.withValues(alpha: enabled ? 0.72 : 0.18),
        ),
      ),
    );
  }

  Widget _buildNarrowBreadcrumb() {
    final g = _groups[_selectedGroup];
    return GestureDetector(
      onTap: _showRailPane,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 2, 14, 6),
        child: Row(
          children: [
            Icon(
              Icons.chevron_left_rounded,
              size: 18,
              color: Colors.white.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 2),
            Flexible(
              child: Text(
                g.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRail() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 10, 12),
      itemCount: _groups.length,
      itemBuilder: (context, i) {
        final g = _groups[i];
        final node = _railNodes[i];
        return Focus(
          focusNode: node,
          onFocusChange: (f) {
            if (f) {
              _area = 'rail';
              _ensureVisible(node);
            }
          },
          onKeyEvent: (_, e) => _railKey(i, e),
          child: ListenableBuilder(
            listenable: node,
            builder: (context, _) {
              final focused = node.hasFocus;
              final selected = i == _selectedGroup;
              return GestureDetector(
                onTap: () {
                  _selectGroup(i);
                  if (_narrow) {
                    _showListPane(focusIndex: 0);
                  } else {
                    node.requestFocus();
                  }
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? HomeTheme.chromeAccent.withValues(alpha: 0.10)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: focused ? HomeTheme.focusGold : Colors.transparent,
                      width: focused ? 2 : 1.5,
                    ),
                    boxShadow: focused && !widget.isTelevision
                        ? [
                            BoxShadow(
                              color: HomeTheme.focusGoldDeep.withValues(
                                alpha: 0.4,
                              ),
                              blurRadius: 12,
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    children: [
                      _stateDot(g.onCount, g.total),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          g.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: focused || selected
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.72),
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${g.onCount}/${g.total}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.42),
                          fontSize: 11,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      if (focused || _narrow) ...[
                        const SizedBox(width: 4),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 16,
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildItemList() {
    final items = _groups[_selectedGroup].items;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 4, 18, 12),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final it = items[i];
        final node = _listNodes[i];
        return Focus(
          focusNode: node,
          onFocusChange: (f) {
            if (f) {
              _area = 'list';
              _ensureVisible(node);
            }
          },
          onKeyEvent: (_, e) => _listKey(i, e),
          child: ListenableBuilder(
            listenable: node,
            builder: (context, _) {
              final focused = node.hasFocus;
              return GestureDetector(
                onTap: () {
                  _selectedItem = i;
                  node.requestFocus();
                  _toggleItem(it);
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.025),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(
                      color: focused
                          ? HomeTheme.focusGold
                          : Colors.white.withValues(alpha: 0.05),
                      width: focused ? 2 : 1.5,
                    ),
                    boxShadow: focused && !widget.isTelevision
                        ? [
                            BoxShadow(
                              color: HomeTheme.focusGoldDeep.withValues(
                                alpha: 0.4,
                              ),
                              blurRadius: 12,
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                it.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  // Unavailable = enabled but its backing
                                  // data didn't load (outage / deleted list)
                                  // — dimmed, still toggleable off.
                                  color: it.unavailable
                                      ? Colors.white.withValues(alpha: 0.45)
                                      : Colors.white,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (it.unavailable) ...[
                              const SizedBox(width: 8),
                              _typeBadge('UNAVAILABLE'),
                            ] else if (it.badge != null) ...[
                              const SizedBox(width: 8),
                              _typeBadge(it.badge!),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      _switchPill(it.on),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _stateDot(int on, int total) {
    final Color color;
    Gradient? gradient;
    if (on == 0) {
      color = _offColor;
    } else if (on == total) {
      color = _onColor;
    } else {
      color = Colors.transparent;
      gradient = const LinearGradient(
        colors: [_onColor, _offColor],
        stops: [0.5, 0.5],
      );
    }
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        color: color,
        gradient: gradient,
        shape: BoxShape.circle,
      ),
    );
  }

  Widget _switchPill(bool isOn) {
    return Container(
      width: 38,
      height: 21,
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        color: isOn ? HomeTheme.chromeAccent : _offColor,
        borderRadius: BorderRadius.circular(99),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 120),
        alignment: isOn ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 16,
          height: 16,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }

  Widget _typeBadge(String type) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: HomeTheme.chromeAccent.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        type.toUpperCase(),
        style: TextStyle(
          color: HomeTheme.chromeAccent.withValues(alpha: 0.95),
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildHintBar() {
    final hints = _arranging
        ? const [
            ('↑↓', 'navigate · move when picked up'),
            ('OK', 'pick up / drop'),
            ('BACK', 'finish arranging'),
          ]
        : const [
            ('↑↓', 'move'),
            ('←→', 'switch pane'),
            ('OK', 'toggle'),
            ('BACK', 'back a level · saves & closes from groups'),
          ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.07),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final (key, label) in hints) ...[
            Container(
              margin: const EdgeInsets.only(left: 18),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                key,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.38),
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
