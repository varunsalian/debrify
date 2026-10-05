import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/stremio_tv/stremio_tv_channel.dart';
import '../../services/storage_service.dart';
import '../../utils/platform_util.dart';
import '../stremio_tv/stremio_tv_service.dart';
import 'widgets/manual_order_list.dart';
import 'widgets/settings_widgets.dart';

class StremioTvChannelOrderPage extends StatefulWidget {
  const StremioTvChannelOrderPage({super.key});

  @override
  State<StremioTvChannelOrderPage> createState() =>
      _StremioTvChannelOrderPageState();
}

class _StremioTvChannelOrderPageState extends State<StremioTvChannelOrderPage> {
  final GlobalKey<ManualOrderListState> _listKey = GlobalKey();
  final FocusNode _doneNode = FocusNode(debugLabel: 'stremio-tv-order-done');
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  bool _allowPop = false;
  List<StremioTvChannel> _channels = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _doneNode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final channels = await StremioTvService.instance.discoverChannels();
    if (!mounted) return;
    setState(() {
      _channels = List.of(channels);
      _loading = false;
    });
  }

  void _move(int from, int to) {
    if (from < 0 ||
        from >= _channels.length ||
        to < 0 ||
        to >= _channels.length) {
      return;
    }
    final channel = _channels.removeAt(from);
    _channels.insert(to, channel);
    setState(() => _dirty = true);
  }

  Future<void> _saveAndClose() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      if (_dirty) {
        await StorageService.setStremioTvChannelOrder([
          for (final channel in _channels) channel.id,
        ]);
      }
      if (!mounted) return;
      setState(() => _allowPop = true);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      Navigator.of(context).pop(_dirty);
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
        title: 'Channel order',
        actions: [
          TextButton(
            focusNode: _doneNode,
            onPressed: _saving ? null : _saveAndClose,
            child: Text(_saving ? 'Saving…' : 'Done'),
          ),
          const SizedBox(width: 8),
        ],
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: ManualOrderList(
                      key: _listKey,
                      items: [
                        for (final channel in _channels)
                          ManualOrderItem(
                            id: channel.id,
                            title: channel.displayName,
                            subtitle: 'CH ${channel.channelNumber}',
                            icon: channel.isFavorite
                                ? Icons.star_rounded
                                : Icons.live_tv_rounded,
                          ),
                      ],
                      onMove: _move,
                      enabled: !_saving,
                      description:
                          'Arrange Stremio TV channels. The order persists across restarts and refreshes; newly discovered channels are added at the end.',
                      emptyText: 'No Stremio TV channels available.',
                      focusLabelPrefix: 'stremio-tv-channel-order-',
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
