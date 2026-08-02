import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/iptv_playlist.dart';
import '../../services/iptv_catalog_db.dart';
import '../../services/iptv_catalog_key.dart';
import '../../utils/platform_util.dart';
import '../../utils/tv_keys.dart';
import '../../widgets/tv_text_field.dart';
import 'widgets/settings_widgets.dart';

/// Manager for the categories a source no longer shows.
///
/// Hiding itself happens on the IPTV page (hold OK / long-press a category);
/// this is where the user sees what they hid and brings it back. It is also
/// the only screen that lists a hidden category at all — everywhere else, the
/// whole point is that it isn't there.
///
/// Scoped to CATALOGS, not playlists: an Xtream login stores its live, movie
/// and series catalogs separately and hides categories separately in each, so
/// the page offers one tab per catalog the source has actually ingested.
class IptvHiddenCategoriesPage extends StatefulWidget {
  const IptvHiddenCategoriesPage({super.key, required this.playlist});

  final IptvPlaylist playlist;

  @override
  State<IptvHiddenCategoriesPage> createState() =>
      _IptvHiddenCategoriesPageState();
}

/// One ingested catalog belonging to this source.
class _CatalogTab {
  const _CatalogTab(this.key, this.label);
  final String key;
  final String label;
}

/// One row: a category, how many channels it holds, and whether it's hidden.
class _CategoryRow {
  const _CategoryRow({
    required this.name,
    required this.count,
    required this.hidden,
    required this.stale,
  });

  final String name;
  final int count;
  final bool hidden;

  /// Hidden, but no longer present in the catalog — the provider renamed or
  /// dropped it. Kept visible so a rule the user can't otherwise see (and
  /// that would silently reattach if the name ever came back) can be cleared.
  final bool stale;
}

class _IptvHiddenCategoriesPageState extends State<IptvHiddenCategoriesPage> {
  late final bool _isTv = PlatformUtil.isAndroidTvCached;

  List<_CatalogTab> _tabs = const [];
  int _selectedTab = 0;
  List<_CategoryRow> _rows = const [];
  bool _loading = true;
  String _query = '';

  /// Bumped by every load. A tab switch starts a new one while the previous
  /// GROUP BY may still be running on its worker, and the two can land out of
  /// order — an older result reaching setState would leave the page showing
  /// one catalog's categories while [_selectedTab] points at another, and a
  /// toggle would then write the rule into the WRONG catalog.
  int _loadTicket = 0;

  final TextEditingController _searchController = TextEditingController();

  /// Created per row index on demand: a provider catalog can carry hundreds
  /// of categories, and building a node for every one of them up front is
  /// what made the old category sheet stall on open. DPAD only ever asks for
  /// a neighbour of a built row, which the list's cache extent has built too.
  final Map<int, FocusNode> _rowNodes = {};
  final FocusNode _showAllNode = FocusNode(debugLabel: 'iptv-hidden-show-all');
  final List<FocusNode> _tabNodes = [];

  @override
  void initState() {
    super.initState();
    _tabs = _availableCatalogs();
    for (var i = 0; i < _tabs.length; i++) {
      _tabNodes.add(FocusNode(debugLabel: 'iptv-hidden-tab-$i'));
    }
    _load();
  }

  @override
  void dispose() {
    for (final node in _rowNodes.values) {
      node.dispose();
    }
    for (final node in _tabNodes) {
      node.dispose();
    }
    _showAllNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  FocusNode _rowNode(int index) => _rowNodes.putIfAbsent(
    index,
    () => FocusNode(debugLabel: 'iptv-hidden-row-$index'),
  );

  /// The catalogs this source has actually ingested. An Xtream login can
  /// offer three; a source never opened in IPTV offers none, and the page
  /// says so rather than showing an empty list that looks like "nothing is
  /// hidden".
  List<_CatalogTab> _availableCatalogs() {
    const labels = {
      'live': 'Live TV',
      'vod': 'Movies',
      'series': 'Series',
    };
    final out = <_CatalogTab>[];
    if (widget.playlist.isXtreamCodes) {
      for (final type in IptvCatalogKey.xtreamContentTypes) {
        final key = IptvCatalogKey.forPlaylist(widget.playlist, type);
        if (key == null) continue;
        if (IptvCatalogDb.snapshot(key) == null) continue;
        out.add(_CatalogTab(key, labels[type] ?? type));
      }
      return out;
    }
    final key = IptvCatalogKey.forPlaylist(widget.playlist, 'live');
    if (key == null || IptvCatalogDb.snapshot(key) == null) return const [];
    return [_CatalogTab(key, 'Channels')];
  }

  Future<void> _load() async {
    final ticket = ++_loadTicket;
    if (_tabs.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    final tab = _tabs[_selectedTab];
    final snap = IptvCatalogDb.snapshot(tab.key);
    if (snap == null) {
      setState(() {
        _rows = const [];
        _loading = false;
      });
      return;
    }
    // includeHidden: this is the one screen that has to see past the
    // exclusion every other reader applies.
    final groups = await IptvCatalogDb.groupsAsync(snap, includeHidden: true);
    // Superseded by a newer tab selection while this GROUP BY ran — drop it.
    if (!mounted || ticket != _loadTicket) return;
    final hidden = IptvCatalogDb.hiddenGroups(tab.key);
    final counts = <String, int>{
      for (final g in groups)
        if (g.name != null && g.name!.isNotEmpty) g.name!: g.count,
    };
    // Provider order where there is one (it's the order the page shows), the
    // catalog's own group order otherwise.
    final names = snap.categories.isNotEmpty
        ? snap.categories
        : [
            for (final g in groups)
              if (g.name != null && g.name!.isNotEmpty) g.name!,
          ];
    final seen = names.toSet();
    setState(() {
      _rows = [
        for (final name in names)
          _CategoryRow(
            name: name,
            count: counts[name] ?? 0,
            hidden: hidden.contains(name),
            stale: false,
          ),
        for (final name in hidden)
          if (!seen.contains(name))
            _CategoryRow(name: name, count: 0, hidden: true, stale: true),
      ];
      _loading = false;
    });
  }

  List<_CategoryRow> get _visibleRows {
    if (_query.isEmpty) return _rows;
    final q = _query.toLowerCase();
    return [
      for (final row in _rows)
        if (row.name.toLowerCase().contains(q)) row,
    ];
  }

  int get _hiddenCount => _rows.where((r) => r.hidden).length;

  void _toggle(_CategoryRow row) {
    final tab = _tabs[_selectedTab];
    final revealing = row.hidden;
    IptvCatalogDb.setGroupHidden(tab.key, row.name, !row.hidden);
    final next = <_CategoryRow>[];
    for (final r in _rows) {
      if (r.name != row.name) {
        next.add(r);
        continue;
      }
      // A stale row exists ONLY to carry a rule for a category this catalog
      // no longer has. Revealing it deletes that rule, leaving the row with
      // nothing to represent — keeping it would show a zero-channel entry on
      // a page that now reads "Nothing hidden", still captioned "turn on to
      // clear the rule" for a rule that is already gone.
      if (r.stale && revealing) continue;
      next.add(
        _CategoryRow(
          name: r.name,
          count: r.count,
          hidden: !revealing,
          stale: r.stale,
        ),
      );
    }
    setState(() => _rows = next);
  }

  Future<void> _showAll() async {
    final tab = _tabs[_selectedTab];
    IptvCatalogDb.showAllGroups(tab.key);
    // Reload rather than flip every row in place: the stale entries drop out
    // entirely, and only a re-read knows which those were.
    await _load();
  }

  void _selectTab(int index) {
    if (index == _selectedTab) return;
    setState(() {
      _selectedTab = index;
      _query = '';
      _searchController.clear();
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return SettingsPageScaffold(
      title: 'Hidden categories',
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(),
    );
  }

  /// Header + lazily built rows.
  ///
  /// The rows are a sliver, not a Column: a provider catalog can carry the
  /// better part of a thousand categories, and building a tile (and its focus
  /// node) for every one of them up front is exactly what made the old
  /// category picker stall on open — on the TV boxes these playlists live on,
  /// that is a visible freeze.
  Widget _buildBody() {
    final rows = _visibleRows;
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          sliver: SliverToBoxAdapter(child: _buildHeader(rows)),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          sliver: SliverList.builder(
            itemCount: rows.length,
            itemBuilder: (context, i) => _CategoryTile(
              focusNode: _rowNode(i),
              row: rows[i],
              onToggle: () => _toggle(rows[i]),
              onUp: i == 0 ? _focusAbove : () => _rowNode(i - 1).requestFocus(),
              onDown: i == rows.length - 1
                  ? null
                  : () => _rowNode(i + 1).requestFocus(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(List<_CategoryRow> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsPageHeader(
          icon: Icons.visibility_off_rounded,
          title: widget.playlist.name,
          subtitle: _tabs.isEmpty
              ? 'This source has not been loaded yet.'
              : 'Categories you hide stop showing up in IPTV — in the list, '
                    'in search and in the player\'s guide. Nothing is deleted.',
        ),
        const SizedBox(height: 20),
        if (_tabs.isEmpty)
          const SettingsInfoBanner(
            text:
                'Open this source in IPTV once so its channels are stored, '
                'then come back here to manage its categories.',
            icon: Icons.cloud_off_rounded,
          )
        else ...[
          if (_tabs.length > 1) ...[
            _buildTabs(),
            const SizedBox(height: 16),
          ],
          Row(
            children: [
              Expanded(
                child: Text(
                  _hiddenCount == 0
                      ? 'Nothing hidden'
                      : '$_hiddenCount hidden of ${_rows.length}',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: kSettingsDim,
                  ),
                ),
              ),
              if (_hiddenCount > 0)
                _FocusableTextButton(
                  focusNode: _showAllNode,
                  label: 'Show all',
                  onTap: _showAll,
                ),
            ],
          ),
          const SizedBox(height: 10),
          // TV skips the filter field for the same reason the category picker
          // does: it drags the on-screen keyboard over the page, and holding
          // DPAD down a list is faster than typing on a remote.
          if (!_isTv && _rows.length > 20) ...[
            TvTextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v.trim()),
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Filter categories…',
                prefixIcon: Icon(Icons.search_rounded, size: 18),
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  _query.isEmpty
                      ? 'This catalog has no categories.'
                      : 'No category matches "$_query".',
                  style: TextStyle(fontSize: 13, color: kSettingsDim),
                ),
              ),
            ),
        ],
      ],
    );
  }

  /// UP off the first row: the Show-all action when it exists, otherwise the
  /// catalog tabs — never nothing, which on a remote is a dead end.
  void _focusAbove() {
    if (_hiddenCount > 0) {
      _showAllNode.requestFocus();
    } else if (_tabNodes.length > 1) {
      _tabNodes[_selectedTab].requestFocus();
    }
  }

  Widget _buildTabs() {
    return Row(
      children: [
        for (var i = 0; i < _tabs.length; i++)
          Padding(
            padding: EdgeInsets.only(right: i == _tabs.length - 1 ? 0 : 8),
            child: _CatalogTabChip(
              focusNode: _tabNodes[i],
              label: _tabs[i].label,
              selected: i == _selectedTab,
              onTap: () => _selectTab(i),
            ),
          ),
      ],
    );
  }
}

/// One category row: name, channel count, and a switch that means SHOWN.
///
/// Phrased as "shown" rather than "hidden" on purpose — a switch the user
/// turns OFF to make something go away matches what every other visibility
/// control in the app does.
class _CategoryTile extends StatefulWidget {
  const _CategoryTile({
    required this.focusNode,
    required this.row,
    required this.onToggle,
    required this.onUp,
    required this.onDown,
  });

  final FocusNode focusNode;
  final _CategoryRow row;
  final VoidCallback onToggle;
  final VoidCallback? onUp;
  final VoidCallback? onDown;

  @override
  State<_CategoryTile> createState() => _CategoryTileState();
}

class _CategoryTileState extends State<_CategoryTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final shown = !row.hidden;
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        final key = event.logicalKey;
        if (isActivateKey(key) || key == LogicalKeyboardKey.space) {
          if (event is KeyDownEvent) widget.onToggle();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowUp) {
          widget.onUp?.call();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowDown) {
          if (widget.onDown == null) return KeyEventResult.handled;
          widget.onDown!();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Container(
        decoration: BoxDecoration(
          color: _focused
              ? kSettingsAccent.withValues(alpha: 0.16)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: ListTile(
          leading: Icon(
            shown ? Icons.visibility_rounded : Icons.visibility_off_rounded,
            color: shown ? kSettingsAccent : kSettingsDim2,
          ),
          title: Text(
            row.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: shown ? Colors.white : kSettingsDim,
            ),
          ),
          subtitle: Text(
            row.stale
                ? 'Not in this list any more — turn on to clear the rule'
                : '${row.count} channel${row.count == 1 ? '' : 's'}',
            style: TextStyle(fontSize: 12, color: kSettingsDim2),
          ),
          trailing: Switch(
            value: shown,
            onChanged: (_) => widget.onToggle(),
          ),
          onTap: widget.onToggle,
        ),
      ),
    );
  }
}

/// Focusable catalog selector chip (Live TV / Movies / Series).
class _CatalogTabChip extends StatefulWidget {
  const _CatalogTabChip({
    required this.focusNode,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final FocusNode focusNode;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_CatalogTabChip> createState() => _CatalogTabChipState();
}

class _CatalogTabChipState extends State<_CatalogTabChip> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selected;
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (isActivateKey(event.logicalKey) ||
            event.logicalKey == LogicalKeyboardKey.space) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: active
                ? kSettingsAccent.withValues(alpha: 0.22)
                : kSettingsPanel2,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _focused
                  ? kSettingsAccent
                  : (active
                        ? kSettingsAccent.withValues(alpha: 0.5)
                        : Colors.transparent),
              width: _focused ? 2 : 1,
            ),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: active ? Colors.white : kSettingsDim,
            ),
          ),
        ),
      ),
    );
  }
}

/// Small focusable text action (the header's "Show all").
class _FocusableTextButton extends StatefulWidget {
  const _FocusableTextButton({
    required this.focusNode,
    required this.label,
    required this.onTap,
  });

  final FocusNode focusNode;
  final String label;
  final VoidCallback onTap;

  @override
  State<_FocusableTextButton> createState() => _FocusableTextButtonState();
}

class _FocusableTextButtonState extends State<_FocusableTextButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (isActivateKey(event.logicalKey) ||
            event.logicalKey == LogicalKeyboardKey.space) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: _focused
                ? kSettingsAccent.withValues(alpha: 0.24)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _focused ? kSettingsAccent : kSettingsAccent2,
              width: _focused ? 2 : 1,
            ),
          ),
          child: Text(
            widget.label,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: kSettingsAccent2,
            ),
          ),
        ),
      ),
    );
  }
}
