import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/iptv_playlist.dart';
import '../../services/iptv_catalog_db.dart';
import '../../services/iptv_catalog_key.dart';
import '../../services/profiles/profile_async_authorization.dart';
import '../../services/profiles/profile_runtime.dart';
import '../../utils/m3u_parser.dart';
import '../../utils/platform_util.dart';
import 'widgets/manual_order_list.dart';
import 'widgets/settings_widgets.dart';

({List<String> names, Map<String, int> counts}) _localCategorySummary(
  String content,
) {
  final parsed = M3uParser.parse(content);
  final counts = <String, int>{};
  for (final channel in parsed.channels) {
    final group = channel.group;
    if (group != null && group.isNotEmpty) {
      counts.update(group, (value) => value + 1, ifAbsent: () => 1);
    }
  }
  return (names: parsed.categories, counts: counts);
}

/// Reorders the category list for one catalog-backed IPTV source.
///
/// Xtream live, movie and series catalogs are independent, so each is edited
/// on its own tab. This moves category chips/guide sections only; it never
/// changes the provider's order of channels inside a category.
class IptvCategoryOrderPage extends StatefulWidget {
  const IptvCategoryOrderPage({
    super.key,
    required this.playlist,
    this.authorization,
    this.debugSaveCategoryOrder,
  });

  final IptvPlaylist playlist;

  /// Revocable capability captured immediately before this settings route was
  /// opened. Null preserves the legacy, unscoped runtime used by older installs
  /// and focused widget tests.
  final ProfileAsyncAuthorization? authorization;

  @visibleForTesting
  final Future<void> Function(String, Iterable<String>)? debugSaveCategoryOrder;

  @override
  State<IptvCategoryOrderPage> createState() => _IptvCategoryOrderPageState();
}

class _CatalogTab {
  const _CatalogTab(this.key, this.label, {this.isLocal = false});

  final String key;
  final String label;
  final bool isLocal;
}

class _CategoryItem {
  const _CategoryItem({
    required this.name,
    required this.count,
    required this.hidden,
  });

  final String name;
  final int count;
  final bool hidden;
}

class _IptvCategoryOrderPageState extends State<IptvCategoryOrderPage> {
  late final List<_CatalogTab> _tabs;
  final Map<String, List<_CategoryItem>> _itemsByCatalog = {};
  final Map<String, List<_CategoryItem>> _providerOrderByCatalog = {};
  final Set<String> _dirtyCatalogs = {};
  final Set<String> _resetCatalogs = {};
  final Map<String, GlobalKey<ManualOrderListState>> _listKeys = {};
  final List<FocusNode> _tabNodes = [];
  final FocusNode _doneNode = FocusNode(debugLabel: 'iptv-category-order-done');
  final FocusNode _resetNode = FocusNode(
    debugLabel: 'iptv-category-order-reset',
  );

  int _selectedTab = 0;
  int _loadTicket = 0;
  bool _loading = true;
  bool _saving = false;
  bool _allowPop = false;
  bool _closingForProfileChange = false;

  _CatalogTab? get _tab => _tabs.isEmpty ? null : _tabs[_selectedTab];
  GlobalKey<ManualOrderListState> _listKeyFor(String catalogKey) =>
      _listKeys.putIfAbsent(catalogKey, GlobalKey.new);
  List<_CategoryItem> get _items =>
      _itemsByCatalog[_tab?.key] ?? const <_CategoryItem>[];

  @override
  void initState() {
    super.initState();
    ProfileRuntime.scope.addListener(_onProfileScopeChanged);
    if (widget.authorization?.isCurrentlyActive == false) {
      _tabs = const [];
      _closeForProfileChange();
      return;
    }
    _tabs = _availableCatalogs();
    for (var i = 0; i < _tabs.length; i++) {
      _tabNodes.add(FocusNode(debugLabel: 'iptv-category-order-tab-$i'));
    }
    unawaited(_loadSelected());
  }

  @override
  void dispose() {
    ProfileRuntime.scope.removeListener(_onProfileScopeChanged);
    for (final node in _tabNodes) {
      node.dispose();
    }
    _doneNode.dispose();
    _resetNode.dispose();
    super.dispose();
  }

  void _onProfileScopeChanged() {
    if (widget.authorization?.isCurrentlyActive == false) {
      _closeForProfileChange();
    }
  }

  Future<bool> _validateCurrentProfile() async {
    final authorization = widget.authorization;
    if (authorization == null) return true;
    try {
      await authorization.runIfCurrent(() async {});
      return true;
    } on StateError {
      _closeForProfileChange();
      return false;
    }
  }

  void _closeForProfileChange() {
    if (_closingForProfileChange) return;
    _closingForProfileChange = true;
    _loadTicket++;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _allowPop = true;
        _saving = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The active profile changed. Nothing was saved.'),
        ),
      );
      // PopScope reads its registered canPop value from the completed build.
      // Give the `_allowPop` rebuild one frame before asking the route to pop.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  List<_CatalogTab> _availableCatalogs() {
    if (widget.playlist.isLocalFile) {
      return [
        _CatalogTab(
          IptvCatalogKey.forLocalCategoryOrder(widget.playlist.id),
          'Channels',
          isLocal: true,
        ),
      ];
    }
    if (!IptvCatalogDb.isOpen) return const [];
    const labels = {'live': 'Live TV', 'vod': 'Movies', 'series': 'Series'};
    final out = <_CatalogTab>[];
    if (widget.playlist.isXtreamCodes) {
      for (final type in IptvCatalogKey.xtreamContentTypes) {
        final key = IptvCatalogKey.forPlaylist(widget.playlist, type);
        if (key != null && IptvCatalogDb.snapshot(key) != null) {
          out.add(_CatalogTab(key, labels[type] ?? type));
        }
      }
      return out;
    }
    final key = IptvCatalogKey.forPlaylist(widget.playlist, 'live');
    if (key != null && IptvCatalogDb.snapshot(key) != null) {
      out.add(_CatalogTab(key, 'Channels'));
    }
    return out;
  }

  Future<void> _loadSelected() async {
    final ticket = ++_loadTicket;
    if (!await _validateCurrentProfile()) return;
    final tab = _tab;
    if (tab == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (!mounted || ticket != _loadTicket) return;
    if (_itemsByCatalog.containsKey(tab.key)) {
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    late final List<String> rawNames;
    late final Map<String, int> counts;
    late final Set<String> hidden;
    if (tab.isLocal) {
      final summary = await compute(
        _localCategorySummary,
        widget.playlist.content!,
        debugLabel: 'iptv-local-category-summary',
      );
      if (!mounted ||
          ticket != _loadTicket ||
          !await _validateCurrentProfile()) {
        return;
      }
      rawNames = summary.names;
      counts = summary.counts;
      hidden = const {};
    } else {
      final snap = IptvCatalogDb.isOpen
          ? IptvCatalogDb.snapshot(tab.key)
          : null;
      if (snap == null) {
        if (mounted && ticket == _loadTicket) {
          setState(() => _loading = false);
        }
        return;
      }
      final groups = await IptvCatalogDb.groupsAsync(snap, includeHidden: true);
      if (!mounted ||
          ticket != _loadTicket ||
          !await _validateCurrentProfile()) {
        return;
      }
      counts = <String, int>{
        for (final group in groups)
          if (group.name?.isNotEmpty == true) group.name!: group.count,
      };
      hidden = IptvCatalogDb.hiddenGroups(tab.key);
      rawNames = snap.categories.isNotEmpty
          ? snap.categories
          : [
              for (final group in groups)
                if (group.name?.isNotEmpty == true) group.name!,
            ];
    }
    final seen = <String>{};
    final providerNames = [
      for (final name in rawNames)
        if (name.isNotEmpty && seen.add(name)) name,
    ];
    _CategoryItem itemFor(String name) => _CategoryItem(
      name: name,
      count: counts[name] ?? 0,
      hidden: hidden.contains(name),
    );
    final providerItems = [for (final name in providerNames) itemFor(name)];
    final orderedNames = IptvCatalogDb.applyCategoryOrder(
      tab.key,
      providerNames,
    );
    setState(() {
      _providerOrderByCatalog[tab.key] = providerItems;
      _itemsByCatalog[tab.key] = [
        for (final name in orderedNames) itemFor(name),
      ];
      _loading = false;
    });
  }

  void _selectTab(int index) {
    if (index == _selectedTab || _saving || _closingForProfileChange) return;
    setState(() => _selectedTab = index);
    unawaited(_loadSelected());
  }

  void _move(int from, int to) {
    if (_saving || _closingForProfileChange) return;
    final tab = _tab;
    final items = _itemsByCatalog[tab?.key];
    if (tab == null ||
        items == null ||
        from < 0 ||
        from >= items.length ||
        to < 0 ||
        to >= items.length ||
        from == to) {
      return;
    }
    final item = items.removeAt(from);
    items.insert(to, item);
    setState(() {
      _dirtyCatalogs.add(tab.key);
      _resetCatalogs.remove(tab.key);
    });
  }

  void _reset() {
    if (_saving || _closingForProfileChange) return;
    final tab = _tab;
    final provider = _providerOrderByCatalog[tab?.key];
    if (tab == null || provider == null) return;
    // The reset keeps every item id, so the list's orphan sweep won't clear
    // an active selection — left alive, the next tap would place it and
    // silently demote the reset back to a custom order.
    _listKeys[tab.key]?.currentState?.cancelPick();
    setState(() {
      _itemsByCatalog[tab.key] = List<_CategoryItem>.of(provider);
      _dirtyCatalogs.add(tab.key);
      _resetCatalogs.add(tab.key);
    });
  }

  Future<void> _saveAndClose() async {
    if (_saving || _closingForProfileChange) return;
    if (!await _validateCurrentProfile()) return;
    final pending = <({String key, List<String> ordered})>[
      for (final tab in _tabs)
        if (_dirtyCatalogs.contains(tab.key))
          (
            key: tab.key,
            ordered: _resetCatalogs.contains(tab.key)
                ? const <String>[]
                : [for (final item in _itemsByCatalog[tab.key]!) item.name],
          ),
    ];
    setState(() => _saving = true);
    try {
      final saveCategoryOrder =
          widget.debugSaveCategoryOrder ?? IptvCatalogDb.setCategoryOrder;
      for (final save in pending) {
        final authorization = widget.authorization;
        if (authorization == null) {
          await saveCategoryOrder(save.key, save.ordered);
        } else {
          await authorization.runIfCurrent(
            () => saveCategoryOrder(save.key, save.ordered),
          );
        }
      }
      if (!await _validateCurrentProfile()) return;
      if (!mounted) return;
      setState(() => _allowPop = true);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!await _validateCurrentProfile()) return;
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Couldn\'t save category order. Try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final list = _listKeys[_tab?.key]?.currentState;
        if (list?.handleBack() != true) {
          unawaited(_saveAndClose());
        }
      },
      child: SettingsPageScaffold(
        title: 'Category order',
        actions: [
          TextButton(
            focusNode: _doneNode,
            onPressed: _saving ? null : _saveAndClose,
            child: Text(_saving ? 'Saving…' : 'Done'),
          ),
          const SizedBox(width: 8),
        ],
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_tabs.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SettingsPageHeader(
            icon: Icons.swap_vert_rounded,
            title: widget.playlist.name,
            subtitle: 'Arrange this source\'s category list.',
          ),
          const SizedBox(height: 20),
          const SettingsInfoBanner(
            text:
                'Open this source in IPTV once so its categories are stored, '
                'then come back here to arrange them.',
            icon: Icons.cloud_off_rounded,
          ),
        ],
      );
    }
    if (_loading) return const Center(child: CircularProgressIndicator());
    final tab = _tab!;
    final items = _items;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SettingsPageHeader(
                  icon: Icons.swap_vert_rounded,
                  title: widget.playlist.name,
                  subtitle:
                      'Arrange category chips and guide sections. Channel '
                      'order inside each category stays unchanged.',
                ),
                if (_tabs.length > 1) ...[
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < _tabs.length; i++)
                        ChoiceChip(
                          focusNode: _tabNodes[i],
                          label: Text(_tabs[i].label),
                          selected: i == _selectedTab,
                          onSelected: _saving ? null : (_) => _selectTab(i),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: ManualOrderList(
                // Keyed per catalog: switching tabs resets selection and
                // search and re-runs the TV first-row autofocus.
                key: _listKeyFor(tab.key),
                items: [
                  for (final item in items)
                    ManualOrderItem(
                      id: (tab.key, item.name),
                      title: item.name,
                      subtitle:
                          '${item.count} channel${item.count == 1 ? '' : 's'}'
                          '${item.hidden ? ' · Hidden' : ''}',
                      icon: item.hidden
                          ? Icons.visibility_off_rounded
                          : Icons.folder_rounded,
                      mutedIcon: item.hidden,
                    ),
                ],
                onMove: _move,
                enabled: !_saving,
                description: '',
                emptyText: 'No categories in this catalog.',
                focusLabelPrefix: 'iptv-category-order-',
                onFocusAboveList: _resetNode.requestFocus,
                autofocusFirstRow: PlatformUtil.isTelevision,
                bannerTrailing: TextButton.icon(
                  focusNode: _resetNode,
                  onPressed: items.isEmpty || _saving ? null : _reset,
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: const Text('Provider order'),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
