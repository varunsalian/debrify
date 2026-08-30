import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/iptv_playlist.dart' show IptvChannel;
import '../../services/iptv_media_store.dart' show IptvListMeta;
import '../../services/storage_service.dart';
import '../../utils/platform_util.dart';
import 'widgets/manual_order_list.dart';
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
  final GlobalKey<ManualOrderListState> _listKey = GlobalKey();
  final FocusNode _doneNode = FocusNode(debugLabel: 'iptv-channel-order-done');
  bool _dirty = false;
  bool _saving = false;
  bool _allowPop = false;

  @override
  void dispose() {
    _doneNode.dispose();
    super.dispose();
  }

  void _move(int from, int to) {
    if (from < 0 || from >= _items.length || to < 0 || to >= _items.length) {
      return;
    }
    final item = _items.removeAt(from);
    _items.insert(to, item);
    setState(() => _dirty = true);
  }

  Future<void> _saveAndClose() async {
    if (_saving) return;
    setState(() => _saving = true);
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
        if (_listKey.currentState?.handleBack() != true) {
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
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: ManualOrderList(
                key: _listKey,
                items: [
                  for (final item in _items)
                    ManualOrderItem(
                      id: item.id,
                      title: item.channel.name,
                      subtitle: [
                        if (item.channel.channelNumber != null)
                          'CH ${item.channel.channelNumber}',
                        if (item.channel.group != null) item.channel.group!,
                      ].join(' · '),
                      icon: Icons.live_tv_rounded,
                    ),
                ],
                onMove: _move,
                enabled: !_saving,
                description: widget.description,
                emptyText: 'No channels in this list.',
                focusLabelPrefix: 'iptv-channel-order-',
                onFocusAboveList: _doneNode.requestFocus,
                autofocusFirstRow: PlatformUtil.isTelevision,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
