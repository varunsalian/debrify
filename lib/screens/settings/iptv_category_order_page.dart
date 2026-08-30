import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/iptv_playlist.dart';
import '../../services/iptv_catalog_db.dart';
import '../../services/iptv_catalog_key.dart';
import '../../services/profiles/profile_async_authorization.dart';
import '../../services/profiles/profile_runtime.dart';
import '../../theme/app_theme_scope.dart';
import '../../utils/m3u_parser.dart';
import '../../utils/platform_util.dart';
import '../../utils/tv_keys.dart';
import '../../utils/tv_reveal.dart';
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
  final Map<Object, FocusNode> _rowNodes = {};
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
  String? _pickedName;

  _CatalogTab? get _tab => _tabs.isEmpty ? null : _tabs[_selectedTab];
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
    for (final node in _rowNodes.values) {
      node.dispose();
    }
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
        _pickedName = null;
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
    if (_itemsByCatalog.containsKey(tab.key)) {
      setState(() => _loading = false);
      _focusFirstRow();
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
    _focusFirstRow();
  }

  FocusNode _nodeFor(String catalogKey, String name) {
    final id = (catalogKey, name);
    return _rowNodes.putIfAbsent(
      id,
      () => FocusNode(
        debugLabel: 'iptv-category-order-${Object.hash(catalogKey, name)}',
      ),
    );
  }

  void _focusFirstRow() {
    if (!PlatformUtil.isTelevision || _items.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final tab = _tab;
      if (!mounted || tab == null || _items.isEmpty) return;
      _nodeFor(tab.key, _items.first.name).requestFocus();
    });
  }

  void _selectTab(int index) {
    if (index == _selectedTab || _saving || _closingForProfileChange) return;
    setState(() {
      _selectedTab = index;
      _pickedName = null;
    });
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final node = _rowNodes[(tab.key, item.name)];
      if (!mounted || node == null) return;
      node.requestFocus();
      final rowContext = node.context;
      if (rowContext != null) tvRevealMinimal(rowContext);
    });
  }

  void _reset() {
    if (_saving || _closingForProfileChange) return;
    final tab = _tab;
    final provider = _providerOrderByCatalog[tab?.key];
    if (tab == null || provider == null) return;
    setState(() {
      _itemsByCatalog[tab.key] = List<_CategoryItem>.of(provider);
      _dirtyCatalogs.add(tab.key);
      _resetCatalogs.add(tab.key);
      _pickedName = null;
    });
    _focusFirstRow();
  }

  KeyEventResult _onRowKey(int buildIndex, KeyEvent event) {
    if (_saving || _closingForProfileChange) return KeyEventResult.handled;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final items = _items;
    final key = event.logicalKey;
    final pickedIndex = _pickedName == null
        ? -1
        : items.indexWhere((item) => item.name == _pickedName);
    final picked = pickedIndex >= 0;
    if (event is KeyDownEvent && isActivateOrSpaceKey(key)) {
      final name = items[buildIndex].name;
      setState(() => _pickedName = _pickedName == name ? null : name);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      final from = picked ? pickedIndex : buildIndex;
      final target = key == LogicalKeyboardKey.arrowUp ? from - 1 : from + 1;
      if (target < 0 || target >= items.length) {
        if (!picked && target < 0) _resetNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (picked) {
        _move(pickedIndex, target);
      } else {
        final tab = _tab!;
        _nodeFor(tab.key, items[target].name).requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (!picked) return KeyEventResult.ignored;
    if (event is KeyDownEvent &&
        (key == LogicalKeyboardKey.escape ||
            key == LogicalKeyboardKey.goBack ||
            key == LogicalKeyboardKey.arrowLeft)) {
      setState(() => _pickedName = null);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) return KeyEventResult.handled;
    return KeyEventResult.ignored;
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
    setState(() {
      _saving = true;
      _pickedName = null;
    });
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
        if (_pickedName != null) {
          setState(() => _pickedName = null);
        } else {
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
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: SettingsInfoBanner(
                        text: items.length < 2
                            ? 'This catalog needs at least two categories.'
                            : PlatformUtil.isTelevision
                            ? 'Press OK to pick up a category, move it with '
                                  '▲▼, then press OK to drop.'
                            : PlatformUtil.isPhone
                            ? 'Drag a category or use its arrows.'
                            : 'Use the arrows, or press Enter to pick up a '
                                  'category and move it with ↑↓.',
                      ),
                    ),
                    const SizedBox(width: 12),
                    TextButton.icon(
                      focusNode: _resetNode,
                      onPressed: items.isEmpty || _saving ? null : _reset,
                      icon: const Icon(Icons.restart_alt_rounded),
                      label: const Text('Provider order'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: items.isEmpty
                  ? const Center(child: Text('No categories in this catalog.'))
                  : ReorderableListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 48),
                      buildDefaultDragHandles: false,
                      itemCount: items.length,
                      onReorderItem: _saving ? (_, _) {} : _move,
                      itemBuilder: (context, index) => _CategoryOrderRow(
                        key: ValueKey('${tab.key}\u0000${items[index].name}'),
                        item: items[index],
                        index: index,
                        node: _nodeFor(tab.key, items[index].name),
                        enabled: !_saving,
                        picked: _pickedName == items[index].name,
                        onKey: (event) => _onRowKey(index, event),
                        onTap: () {
                          if (_saving) return;
                          setState(() {
                            final name = items[index].name;
                            _pickedName = _pickedName == name ? null : name;
                          });
                        },
                        onMoveUp: !_saving && index > 0
                            ? () => _move(index, index - 1)
                            : null,
                        onMoveDown: !_saving && index < items.length - 1
                            ? () => _move(index, index + 1)
                            : null,
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CategoryOrderRow extends StatefulWidget {
  const _CategoryOrderRow({
    super.key,
    required this.item,
    required this.index,
    required this.node,
    required this.enabled,
    required this.picked,
    required this.onKey,
    required this.onTap,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final _CategoryItem item;
  final int index;
  final FocusNode node;
  final bool enabled;
  final bool picked;
  final KeyEventResult Function(KeyEvent) onKey;
  final VoidCallback onTap;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  @override
  State<_CategoryOrderRow> createState() => _CategoryOrderRowState();
}

class _CategoryOrderRowState extends State<_CategoryOrderRow> {
  bool get _focused => widget.node.hasFocus;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    final active = widget.picked || _focused;
    final item = widget.item;
    return Focus(
      focusNode: widget.node,
      onFocusChange: (focused) {
        if (focused && PlatformUtil.isTelevision) tvRevealMinimal(context);
        setState(() {});
      },
      onKeyEvent: (_, event) => widget.onKey(event),
      child: InkWell(
        canRequestFocus: false,
        onTap: widget.enabled ? widget.onTap : null,
        borderRadius: app.shape.br(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: active ? t.panel2 : t.panel,
            borderRadius: app.shape.br(12),
            border: Border.all(color: active ? t.accent : t.line),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 44,
                child: Text(
                  '${widget.index + 1}',
                  style: TextStyle(
                    color: active ? t.accent2 : t.dim,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Icon(
                item.hidden
                    ? Icons.visibility_off_rounded
                    : Icons.folder_rounded,
                size: 22,
                color: item.hidden ? t.dim2 : t.dim,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      '${item.count} channel${item.count == 1 ? '' : 's'}'
                      '${item.hidden ? ' · Hidden' : ''}',
                      style: TextStyle(color: t.dim, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (widget.picked)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    'Moving…',
                    style: TextStyle(
                      color: t.accent2,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              if (!PlatformUtil.isTelevision)
                ExcludeFocus(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Move up',
                        onPressed: widget.onMoveUp,
                        icon: const Icon(Icons.keyboard_arrow_up_rounded),
                      ),
                      IconButton(
                        tooltip: 'Move down',
                        onPressed: widget.onMoveDown,
                        icon: const Icon(Icons.keyboard_arrow_down_rounded),
                      ),
                    ],
                  ),
                ),
              if (PlatformUtil.isPhone && widget.enabled)
                ReorderableDragStartListener(
                  index: widget.index,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(Icons.drag_indicator_rounded, color: t.dim),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
