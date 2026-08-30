import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/iptv_playlist.dart' show IptvChannel;
import '../../services/iptv_media_store.dart' show IptvListMeta;
import '../../services/storage_service.dart';
import '../../theme/app_theme_scope.dart';
import '../../utils/platform_util.dart';
import '../../utils/tv_keys.dart';
import '../../utils/tv_reveal.dart';
import 'widgets/settings_widgets.dart';

/// Entry point for manually arranging channels inside Favorites and custom
/// lists. Source-category channel ordering is intentionally not exposed.
class IptvChannelOrderPage extends StatefulWidget {
  const IptvChannelOrderPage({super.key});

  @override
  State<IptvChannelOrderPage> createState() => _IptvChannelOrderPageState();
}

class _IptvChannelOrderPageState extends State<IptvChannelOrderPage> {
  final FocusNode _firstTargetNode = FocusNode(
    debugLabel: 'iptv-channel-order-first-target',
  );
  bool _loading = true;
  List<IptvListMeta> _lists = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _firstTargetNode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final lists = await StorageService.getIptvLists();
    if (!mounted) return;
    setState(() {
      _lists = lists;
      _loading = false;
    });
    if (PlatformUtil.isTelevision) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _firstTargetNode.requestFocus();
      });
    }
  }

  Future<void> _openList(IptvListMeta list) async {
    final stored = await StorageService.getIptvListChannels(list.id);
    if (!mounted) return;
    final items = <_OrderItem>[
      for (final entry in stored.entries)
        _OrderItem(
          id: entry.key,
          channel: _channelFromList(entry.key, entry.value),
        ),
    ];
    await pushSettingsPage<void>(
      context,
      _ChannelOrderEditor(
        title: list.name,
        description: 'This order is used on the IPTV page and Home.',
        items: items,
        onSave: (ordered) => StorageService.reorderIptvListChannels(list.id, [
          for (final item in ordered) item.channel.url,
        ]),
      ),
    );
  }

  IptvChannel _channelFromList(String url, Map<String, dynamic> metadata) {
    final name = (metadata['name'] as String?) ?? '';
    final logoUrl = (metadata['logoUrl'] as String?) ?? '';
    final group = (metadata['group'] as String?) ?? '';
    return IptvChannel(
      channelNumber: (metadata['channelNumber'] as num?)?.toInt(),
      name: name.isEmpty ? 'Unknown Channel' : name,
      url: url,
      logoUrl: logoUrl.isEmpty ? null : logoUrl,
      group: group.isEmpty ? null : group,
      duration: (metadata['duration'] as num?)?.toInt() ?? -1,
      contentType: metadata['contentType'] as String?,
      httpHeaders: StorageService.iptvFavoriteHeaders(metadata),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SettingsPageScaffold(
        title: 'Channel order',
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return SettingsPageScaffold(
      title: 'Channel order',
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          PlatformUtil.isTelevision ? 36 : 16,
          18,
          PlatformUtil.isTelevision ? 36 : 16,
          64,
        ),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SettingsPageHeader(
                    icon: Icons.reorder_rounded,
                    title: 'Channel order',
                    subtitle:
                        'Choose Favorites or a saved list, then put its '
                        'channels in the order you want.',
                  ),
                  const SizedBox(height: 24),
                  const SettingsSectionLabel('Favorites and lists'),
                  SettingsSection(
                    title: '',
                    children: [
                      for (var index = 0; index < _lists.length; index++)
                        SettingsTile(
                          icon: _lists[index].isFavorites
                              ? Icons.star_rounded
                              : Icons.bookmark_border_rounded,
                          title: _lists[index].name,
                          subtitle:
                              '${_lists[index].channelCount} channel'
                              '${_lists[index].channelCount == 1 ? '' : 's'}',
                          focusNode: index == 0 ? _firstTargetNode : null,
                          onTap: () => _openList(_lists[index]),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderItem {
  const _OrderItem({required this.id, required this.channel});

  final Object id;
  final IptvChannel channel;
}

class _ChannelOrderEditor extends StatefulWidget {
  const _ChannelOrderEditor({
    required this.title,
    required this.description,
    required this.items,
    required this.onSave,
  });

  final String title;
  final String description;
  final List<_OrderItem> items;
  final Future<void> Function(List<_OrderItem>) onSave;

  @override
  State<_ChannelOrderEditor> createState() => _ChannelOrderEditorState();
}

class _ChannelOrderEditorState extends State<_ChannelOrderEditor> {
  late final List<_OrderItem> _items = List.of(widget.items);
  final Map<Object, FocusNode> _nodes = {};
  final FocusNode _doneNode = FocusNode(debugLabel: 'iptv-channel-order-done');
  Object? _pickedId;
  bool _dirty = false;
  bool _saving = false;
  bool _allowPop = false;

  @override
  void initState() {
    super.initState();
    if (PlatformUtil.isTelevision && _items.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _nodeFor(_items.first.id).requestFocus();
      });
    }
  }

  @override
  void dispose() {
    for (final node in _nodes.values) {
      node.dispose();
    }
    _doneNode.dispose();
    super.dispose();
  }

  FocusNode _nodeFor(Object id) => _nodes.putIfAbsent(
    id,
    () => FocusNode(debugLabel: 'iptv-channel-order-${id.hashCode}'),
  );

  void _move(int from, int to) {
    if (from < 0 || from >= _items.length || to < 0 || to >= _items.length) {
      return;
    }
    final item = _items.removeAt(from);
    _items.insert(to, item);
    setState(() => _dirty = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final node = _nodes[item.id];
      if (!mounted || node == null) return;
      node.requestFocus();
      final rowContext = node.context;
      if (rowContext != null) tvRevealMinimal(rowContext);
    });
  }

  KeyEventResult _onRowKey(int buildIndex, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final pickedIndex = _pickedId == null
        ? -1
        : _items.indexWhere((item) => item.id == _pickedId);
    final picked = pickedIndex >= 0;

    if (event is KeyDownEvent && isActivateOrSpaceKey(key)) {
      final currentId = _items[buildIndex].id;
      setState(() => _pickedId = _pickedId == currentId ? null : currentId);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      final from = picked ? pickedIndex : buildIndex;
      final target = key == LogicalKeyboardKey.arrowUp ? from - 1 : from + 1;
      if (target < 0 || target >= _items.length) {
        if (!picked && target < 0) {
          _doneNode.requestFocus();
          return KeyEventResult.handled;
        }
        return picked ? KeyEventResult.handled : KeyEventResult.ignored;
      }
      if (picked) {
        _move(pickedIndex, target);
      } else {
        final node = _nodeFor(_items[target].id);
        node.requestFocus();
        final rowContext = node.context;
        if (rowContext != null) tvRevealMinimal(rowContext);
      }
      return KeyEventResult.handled;
    }
    if (!picked) return KeyEventResult.ignored;
    if (event is KeyDownEvent &&
        (key == LogicalKeyboardKey.escape ||
            key == LogicalKeyboardKey.goBack ||
            key == LogicalKeyboardKey.arrowLeft)) {
      setState(() => _pickedId = null);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) return KeyEventResult.handled;
    return KeyEventResult.ignored;
  }

  Future<void> _saveAndClose() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _pickedId = null;
    });
    try {
      if (_dirty) await widget.onSave(List.unmodifiable(_items));
      if (!mounted) return;
      setState(() => _allowPop = true);
      // PopScope publishes canPop during the next build. Popping in the same
      // turn as setState is still vetoed by the old PopEntry and leaves the
      // Done button apparently inert.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Couldn\'t save channel order. Try again.'),
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
        if (_pickedId != null) {
          setState(() => _pickedId = null);
        } else {
          unawaited(_saveAndClose());
        }
      },
      child: SettingsPageScaffold(
        title: widget.title,
        actions: [
          TextButton(
            focusNode: _doneNode,
            onPressed: _saving ? null : _saveAndClose,
            child: Text(_saving ? 'Saving…' : 'Done'),
          ),
          const SizedBox(width: 8),
        ],
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: SettingsInfoBanner(
                  text: _items.length < 2
                      ? 'Add at least two channels before changing the order.'
                      : PlatformUtil.isTelevision
                      ? '${widget.description} Press OK to pick up a row, '
                            'move it with ▲▼, then press OK to drop.'
                      : PlatformUtil.isPhone
                      ? '${widget.description} Drag a row or use its arrows.'
                      : '${widget.description} Use the arrows, or press Enter '
                            'to pick up a row and move it with ↑↓.',
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  child: _items.isEmpty
                      ? const Center(child: Text('No channels in this list.'))
                      : ReorderableListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 48),
                          buildDefaultDragHandles: false,
                          itemCount: _items.length,
                          onReorderItem: _move,
                          itemBuilder: (context, index) => _OrderRow(
                            key: ValueKey(_items[index].id),
                            item: _items[index],
                            index: index,
                            node: _nodeFor(_items[index].id),
                            picked: _pickedId == _items[index].id,
                            onKey: (event) => _onRowKey(index, event),
                            onTap: () => setState(() {
                              final id = _items[index].id;
                              _pickedId = _pickedId == id ? null : id;
                            }),
                            onMoveUp: index > 0
                                ? () => _move(index, index - 1)
                                : null,
                            onMoveDown: index < _items.length - 1
                                ? () => _move(index, index + 1)
                                : null,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderRow extends StatefulWidget {
  const _OrderRow({
    super.key,
    required this.item,
    required this.index,
    required this.node,
    required this.picked,
    required this.onKey,
    required this.onTap,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final _OrderItem item;
  final int index;
  final FocusNode node;
  final bool picked;
  final KeyEventResult Function(KeyEvent) onKey;
  final VoidCallback onTap;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  @override
  State<_OrderRow> createState() => _OrderRowState();
}

class _OrderRowState extends State<_OrderRow> {
  bool get _focused => widget.node.hasFocus;

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
    final active = widget.picked || _focused;
    final channel = widget.item.channel;
    return Focus(
      focusNode: widget.node,
      onFocusChange: (focused) {
        if (focused && PlatformUtil.isTelevision) tvRevealMinimal(context);
        setState(() {});
      },
      onKeyEvent: (_, event) => widget.onKey(event),
      child: InkWell(
        canRequestFocus: false,
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: active ? t.panel2 : t.panel,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: active ? t.accent : t.line),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 40,
                child: Text(
                  '${widget.index + 1}',
                  style: TextStyle(
                    color: active ? t.accent2 : t.dim,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Icon(Icons.live_tv_rounded, size: 22, color: t.dim),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      channel.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (channel.channelNumber != null || channel.group != null)
                      Text(
                        [
                          if (channel.channelNumber != null)
                            'CH ${channel.channelNumber}',
                          if (channel.group != null) channel.group!,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
              if (PlatformUtil.isPhone)
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
