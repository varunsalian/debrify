import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/debrify_tv_channel_record.dart';
import '../../../theme/app_theme_scope.dart';
import '../../../utils/platform_util.dart';
import '../../../utils/tv_keys.dart';
import 'spotlight_dialog.dart';

/// Selects the channels to place in a portable ZIP. Every channel starts
/// selected so the safe/default action captures the complete library.
class ExportChannelsDialog extends StatefulWidget {
  const ExportChannelsDialog({
    super.key,
    required this.channels,
    required this.savedHashCounts,
  });

  final List<DebrifyTvChannelRecord> channels;
  final Map<String, int> savedHashCounts;

  @override
  State<ExportChannelsDialog> createState() => _ExportChannelsDialogState();
}

class _ExportChannelsDialogState extends State<ExportChannelsDialog> {
  final FocusNode _selectAllNode = FocusNode(
    debugLabel: 'channel-export-select-all',
  );
  final FocusNode _cancelNode = FocusNode(debugLabel: 'channel-export-cancel');
  final FocusNode _exportNode = FocusNode(debugLabel: 'channel-export-save');
  late final Map<String, FocusNode> _channelNodes;
  late final Set<String> _selectedIds;

  @override
  void initState() {
    super.initState();
    _selectedIds = widget.channels.map((channel) => channel.channelId).toSet();
    _channelNodes = <String, FocusNode>{
      for (final channel in widget.channels)
        channel.channelId: FocusNode(
          debugLabel: 'channel-export-${channel.channelId}',
        ),
    };
  }

  @override
  void dispose() {
    _selectAllNode.dispose();
    _cancelNode.dispose();
    _exportNode.dispose();
    for (final node in _channelNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  bool get _allSelected =>
      widget.channels.isNotEmpty &&
      _selectedIds.length == widget.channels.length;

  void _toggleAll() {
    HapticFeedback.selectionClick();
    setState(() {
      if (_allSelected) {
        _selectedIds.clear();
      } else {
        _selectedIds.addAll(
          widget.channels.map((channel) => channel.channelId),
        );
      }
    });
  }

  void _toggleChannel(String channelId) {
    HapticFeedback.selectionClick();
    setState(() {
      if (!_selectedIds.remove(channelId)) {
        _selectedIds.add(channelId);
      }
    });
  }

  void _finish() {
    if (_selectedIds.isEmpty) return;
    Navigator.of(context).pop(Set<String>.unmodifiable(_selectedIds));
  }

  @override
  Widget build(BuildContext context) {
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.5;
    final selectedHashes = widget.channels
        .where((channel) => _selectedIds.contains(channel.channelId))
        .fold<int>(
          0,
          (sum, channel) =>
              sum + (widget.savedHashCounts[channel.channelId] ?? 0),
        );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop();
      },
      child: DebrifyTvSpotlightDialog(
        eyebrow: 'Portable channel archive',
        title: largeText ? 'Export' : 'Export channels',
        subtitle: largeText
            ? 'Includes each channel’s keywords and complete saved pool.'
            : 'Choose what to include. Each channel is saved with its '
                  'keywords and complete playable pool.',
        icon: Icons.folder_zip_rounded,
        maxWidth: 720,
        maxHeightFactor: .98,
        scrollable: false,
        actions: <Widget>[
          DebrifyTvDialogButton(
            focusNode: _cancelNode,
            label: 'Cancel',
            icon: Icons.close_rounded,
            onPressed: () => Navigator.of(context).pop(),
          ),
          DebrifyTvDialogButton(
            focusNode: _exportNode,
            label: largeText
                ? 'Export ${_selectedIds.length}'
                : 'Export ${_selectedIds.length} channel${_selectedIds.length == 1 ? '' : 's'}',
            icon: Icons.download_rounded,
            tone: DebrifyTvDialogButtonTone.primary,
            onPressed: _selectedIds.isEmpty ? null : _finish,
          ),
        ],
        // Keep every row mounted. A lazily built ListView can hand DPAD focus
        // from its last visible child straight to the dialog actions, skipping
        // channels that have not been built yet. Keeping Select all in the
        // same scroller also lets the dialog survive very large phone text.
        child: SingleChildScrollView(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _ExportSelectionRow(
                focusNode: _selectAllNode,
                autofocus: true,
                selected: _allSelected,
                title: 'Select all channels',
                subtitle:
                    '${_selectedIds.length} selected · $selectedHashes saved hash${selectedHashes == 1 ? '' : 'es'}',
                trailing: '${_selectedIds.length}/${widget.channels.length}',
                onPressed: _toggleAll,
              ),
              const SizedBox(height: 12),
              for (
                var index = 0;
                index < widget.channels.length;
                index++
              ) ...<Widget>[
                if (index > 0) const SizedBox(height: 8),
                _channelRow(widget.channels[index]),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _channelRow(DebrifyTvChannelRecord channel) {
    final hashes = widget.savedHashCounts[channel.channelId] ?? 0;
    return _ExportSelectionRow(
      focusNode: _channelNodes[channel.channelId]!,
      selected: _selectedIds.contains(channel.channelId),
      title: channel.name,
      subtitle:
          '${channel.keywords.length} keyword${channel.keywords.length == 1 ? '' : 's'}',
      trailing: '$hashes hash${hashes == 1 ? '' : 'es'}',
      onPressed: () => _toggleChannel(channel.channelId),
    );
  }
}

class _ExportSelectionRow extends StatefulWidget {
  const _ExportSelectionRow({
    required this.focusNode,
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.onPressed,
    this.autofocus = false,
  });

  final FocusNode focusNode;
  final bool selected;
  final String title;
  final String subtitle;
  final String trailing;
  final VoidCallback onPressed;
  final bool autofocus;

  @override
  State<_ExportSelectionRow> createState() => _ExportSelectionRowState();
}

class _ExportSelectionRowState extends State<_ExportSelectionRow> {
  bool _focused = false;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowLeft) {
      node.previousFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowRight) {
      node.nextFocus();
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent && isActivateOrSpaceKey(key)) {
      widget.onPressed();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _onFocusChange(bool focused) {
    setState(() => _focused = focused);
    if (focused) {
      Scrollable.ensureVisible(
        context,
        duration: PlatformUtil.isTelevision
            ? Duration.zero
            : const Duration(milliseconds: 160),
        alignment: .5,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final tv = app.debrifyTv;
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.5;
    final focused = _focused;
    final foreground = focused ? app.inkOn(app.core.tx) : app.core.tx;
    final secondary = focused
        ? app.inkOn(app.core.tx).withValues(alpha: .6)
        : tv.textDim;
    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: _onFocusChange,
      onKeyEvent: _onKey,
      child: Semantics(
        button: true,
        checked: widget.selected,
        label: '${widget.title}, ${widget.trailing}',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: PlatformUtil.isTelevision
                ? Duration.zero
                : const Duration(milliseconds: 150),
            constraints: const BoxConstraints(minHeight: 68),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: focused ? app.core.tx : tv.fillWeak,
              borderRadius: app.shape.br(16),
              border: Border.all(color: focused ? app.core.tx : tv.hairline),
              boxShadow: focused
                  ? const <BoxShadow>[
                      BoxShadow(
                        color: Color(0x66000000),
                        blurRadius: 22,
                        offset: Offset(0, 10),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  widget.selected
                      ? Icons.check_box_rounded
                      : Icons.check_box_outline_blank_rounded,
                  color: focused
                      ? foreground
                      : widget.selected
                      ? tv.accent
                      : tv.textFaint,
                  size: 24,
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: foreground,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        largeText
                            ? '${widget.trailing} · ${widget.subtitle}'
                            : widget.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: secondary, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                if (!largeText) ...<Widget>[
                  const SizedBox(width: 12),
                  Text(
                    widget.trailing,
                    style: TextStyle(
                      color: secondary,
                      fontFamily: 'JetBrainsMono',
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Non-dismissible progress surface used while channel rows are read and the
/// ZIP is compressed. It closes through its own route when [done] flips, so a
/// profile switch cannot strand a modal over the replacement screen.
class ChannelExportProgressDialog extends StatefulWidget {
  const ChannelExportProgressDialog({
    super.key,
    required this.stage,
    required this.done,
  });

  final ValueNotifier<String> stage;
  final ValueNotifier<bool> done;

  @override
  State<ChannelExportProgressDialog> createState() =>
      _ChannelExportProgressDialogState();
}

class _ChannelExportProgressDialogState
    extends State<ChannelExportProgressDialog> {
  @override
  void initState() {
    super.initState();
    widget.done.addListener(_maybeClose);
    if (widget.done.value) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeClose());
    }
  }

  @override
  void dispose() {
    widget.done.removeListener(_maybeClose);
    super.dispose();
  }

  void _maybeClose() {
    if (widget.done.value && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: DebrifyTvSpotlightDialog(
        eyebrow: 'Portable channel archive',
        title: 'Building ZIP',
        subtitle: 'Keeping every selected channel and its saved pool together.',
        icon: Icons.folder_zip_rounded,
        maxWidth: 560,
        scrollable: false,
        child: Row(
          children: <Widget>[
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: ValueListenableBuilder<String>(
                valueListenable: widget.stage,
                builder: (_, value, _) => Text(value),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
