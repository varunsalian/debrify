import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/sidebar_configuration.dart';
import '../../services/analytics_service.dart';
import '../../services/main_page_bridge.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme_scope.dart';
import '../../utils/platform_util.dart';
import '../../utils/tv_keys.dart';
import '../../widgets/tv_text_field.dart';
import 'widgets/settings_widgets.dart';

/// Shared Android TV + desktop editor for sidebar order and display names.
/// Destination visibility is intentionally absent: integrations and profile
/// policy remain the only authorities allowed to hide app surfaces.
class SidebarCustomizationPage extends StatefulWidget {
  const SidebarCustomizationPage({super.key});

  static const Key listKey = ValueKey('sidebar-customization-list');
  static const Key resetKey = ValueKey('sidebar-customization-reset');

  @override
  State<SidebarCustomizationPage> createState() =>
      _SidebarCustomizationPageState();
}

class _SidebarCustomizationPageState extends State<SidebarCustomizationPage> {
  bool _loading = true;
  SidebarConfiguration _configuration = SidebarConfiguration.defaults();
  final Map<String, FocusNode> _rowNodes = <String, FocusNode>{};
  final FocusNode _resetNode = FocusNode(
    debugLabel: 'sidebar-customization-reset',
  );
  String? _pickedId;

  Future<void> _saveTail = Future<void>.value();
  int _saveRevision = 0;

  bool get _isTelevision => PlatformUtil.isTelevision;

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('sidebar_customization_settings');
    _load();
  }

  @override
  void dispose() {
    for (final node in _rowNodes.values) {
      node.dispose();
    }
    _resetNode.dispose();
    super.dispose();
  }

  FocusNode _nodeFor(String id) => _rowNodes.putIfAbsent(
    id,
    () => FocusNode(debugLabel: 'sidebar-customization-$id'),
  );

  void _focusRow(String id) {
    final node = _nodeFor(id);
    final rowContext = node.context;
    if (rowContext != null) {
      Scrollable.ensureVisible(
        rowContext,
        duration: Duration.zero,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    }
    node.requestFocus();
  }

  Future<void> _load() async {
    final configuration = await StorageService.getSidebarConfiguration();
    if (!mounted) return;
    setState(() {
      _configuration = configuration;
      _loading = false;
    });
    if (_isTelevision) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _configuration.order.isEmpty) return;
        _focusRow(_configuration.order.first);
      });
    }
  }

  void _moveTo(int from, int to) {
    final order = List<String>.of(_configuration.order);
    if (from < 0 || from >= order.length || to < 0 || to >= order.length) {
      return;
    }
    if (from == to) return;
    final moved = order.removeAt(from);
    order.insert(to, moved);
    setState(() {
      _configuration = _configuration.copyWith(order: order);
    });
    _schedulePersist();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusRow(moved);
    });
  }

  void _schedulePersist({bool reset = false}) {
    final snapshot = _configuration;
    final revision = ++_saveRevision;
    _saveTail = _saveTail
        .then((_) async {
          if (revision != _saveRevision) return;
          final saved = reset
              ? await StorageService.resetSidebarConfiguration()
              : await StorageService.setSidebarConfiguration(snapshot);
          if (!saved) throw StateError('Sidebar preference write was refused');
          if (revision != _saveRevision) return;
          MainPageBridge.sidebarConfigurationChanged?.call();
        })
        .catchError((Object error, StackTrace stackTrace) {
          if (!mounted || revision != _saveRevision) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not save sidebar changes')),
          );
        });
  }

  Future<void> _rename(String id) async {
    final destination = sidebarDestinationById[id];
    if (destination == null) return;
    final result = await showDialog<_SidebarLabelEdit>(
      context: context,
      builder: (_) => _SidebarLabelDialog(
        destination: destination,
        initialValue: _configuration.labelForId(id),
        canReset: _configuration.labels.containsKey(id),
      ),
    );
    if (result == null || !mounted) {
      _restoreRowFocus(id);
      return;
    }

    final labels = Map<String, String>.of(_configuration.labels);
    switch (result) {
      case _SidebarLabelReset():
        labels.remove(id);
      case _SidebarLabelSave(:final label):
        if (label == destination.defaultLabel) {
          labels.remove(id);
        } else {
          labels[id] = label;
        }
    }
    setState(() {
      _configuration = _configuration.copyWith(labels: labels);
    });
    _schedulePersist();
    _restoreRowFocus(id);
  }

  void _restoreRowFocus(String id) {
    if (!_isTelevision) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusRow(id);
    });
  }

  Future<void> _reset() async {
    if (_configuration.isDefault) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset sidebar?'),
        content: const Text(
          'This restores the original order and every default name on both '
          'TV and desktop.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _configuration = SidebarConfiguration.defaults();
      _pickedId = null;
    });
    _schedulePersist(reset: true);
    if (_isTelevision) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _configuration.order.isNotEmpty) {
          _focusRow(_configuration.order.first);
        }
      });
    }
  }

  KeyEventResult _handleRowKey(int index, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (index < 0 || index >= _configuration.order.length) {
      return KeyEventResult.ignored;
    }
    final id = _configuration.order[index];
    final picked = _pickedId == id;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp) {
      if (picked && index > 0) {
        _moveTo(index, index - 1);
      } else if (!picked && index > 0) {
        _focusRow(_configuration.order[index - 1]);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (picked && index < _configuration.order.length - 1) {
        _moveTo(index, index + 1);
      } else if (!picked && index < _configuration.order.length - 1) {
        _focusRow(_configuration.order[index + 1]);
      } else if (!picked && event is KeyDownEvent) {
        _resetNode.requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent) return KeyEventResult.handled;
    if (isActivateKey(key)) {
      setState(() => _pickedId = picked ? null : id);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      unawaited(_rename(id));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.browserBack ||
        key == LogicalKeyboardKey.arrowLeft) {
      if (picked) {
        setState(() => _pickedId = null);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SettingsPageScaffold(
        title: 'Sidebar Items',
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final t = AppThemeScope.of(context).settings;
    return SettingsPageScaffold(
      title: 'Sidebar Items',
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: kSettingsMaxWidth),
              child: Focus(
                canRequestFocus: false,
                skipTraversal: true,
                onKeyEvent: (_, event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.arrowUp &&
                      _configuration.order.isNotEmpty) {
                    _focusRow(_configuration.order.last);
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: OutlinedButton.icon(
                  key: SidebarCustomizationPage.resetKey,
                  focusNode: _resetNode,
                  onPressed: _configuration.isDefault ? null : _reset,
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: const Text('Restore default order and names'),
                ),
              ),
            ),
          ),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) => Center(
          child: SizedBox(
            width: constraints.maxWidth.clamp(0, kSettingsMaxWidth),
            height: constraints.maxHeight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: SettingsPageHeader(
                    icon: Icons.low_priority_rounded,
                    title: 'Make the sidebar yours',
                    subtitle:
                        'Order and names are shared by TV and desktop for '
                        'this profile. Availability still follows connections '
                        'and profile access.',
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: SettingsInfoBanner(
                    icon: _isTelevision
                        ? Icons.gamepad_rounded
                        : Icons.drag_indicator_rounded,
                    text: _isTelevision
                        ? 'Press OK to pick up a row, move it with ↑/↓, then '
                              'press OK to drop. Press RIGHT to rename.'
                        : 'Drag rows into place. Click a row to rename it.',
                  ),
                ),
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final list = ReorderableListView.builder(
                        key: SidebarCustomizationPage.listKey,
                        buildDefaultDragHandles: false,
                        shrinkWrap: _isTelevision,
                        physics: _isTelevision
                            ? const NeverScrollableScrollPhysics()
                            : null,
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        itemCount: _configuration.order.length,
                        onReorderItem: _moveTo,
                        itemBuilder: (context, index) {
                          final id = _configuration.order[index];
                          final destination = sidebarDestinationById[id]!;
                          final label = _configuration.labelForId(id);
                          final customized = _configuration.labels.containsKey(
                            id,
                          );
                          final picked = _pickedId == id;
                          final node = _nodeFor(id);
                          return Focus(
                            key: ValueKey('sidebar-item-$id'),
                            focusNode: node,
                            onFocusChange: (focused) {
                              if (!focused && picked && mounted) {
                                setState(() => _pickedId = null);
                              }
                            },
                            onKeyEvent: (_, event) =>
                                _handleRowKey(index, event),
                            child: ListenableBuilder(
                              listenable: node,
                              builder: (context, _) => Semantics(
                                button: true,
                                label: '$label, position ${index + 1}',
                                hint: _isTelevision
                                    ? 'Press OK to move or RIGHT to rename'
                                    : 'Click to rename or drag to reorder',
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    canRequestFocus: false,
                                    onTap: () => unawaited(_rename(id)),
                                    borderRadius: BorderRadius.circular(14),
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 120,
                                      ),
                                      margin: const EdgeInsets.symmetric(
                                        vertical: 4,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: picked
                                            ? t.accent.withValues(alpha: 0.16)
                                            : t.panel,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: node.hasFocus || picked
                                              ? t.accent2
                                              : t.line,
                                          width: node.hasFocus || picked
                                              ? 2
                                              : 1,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          ReorderableDragStartListener(
                                            index: index,
                                            child: Padding(
                                              padding: const EdgeInsets.all(6),
                                              child: Icon(
                                                Icons.drag_indicator_rounded,
                                                color: t.dim,
                                              ),
                                            ),
                                          ),
                                          SizedBox(
                                            width: 30,
                                            child: Text(
                                              '${index + 1}',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                color: t.dim,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Icon(
                                            destination.icon,
                                            color: t.accent2,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  label,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  customized
                                                      ? 'Default: ${destination.defaultLabel}'
                                                      : destination.section,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color: t.dim,
                                                    fontSize: 11.5,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (picked)
                                            _StatusBadge(
                                              label: 'MOVING',
                                              color: t.accent2,
                                            )
                                          else if (customized)
                                            _StatusBadge(
                                              label: 'RENAMED',
                                              color: t.accent2,
                                            ),
                                          const SizedBox(width: 8),
                                          Icon(
                                            Icons.edit_rounded,
                                            size: 19,
                                            color: t.dim,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      );
                      if (!_isTelevision) return list;
                      return SingleChildScrollView(child: list);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withValues(alpha: 0.35)),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: color,
        fontSize: 9,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.6,
      ),
    ),
  );
}

sealed class _SidebarLabelEdit {
  const _SidebarLabelEdit();
}

class _SidebarLabelSave extends _SidebarLabelEdit {
  final String label;
  const _SidebarLabelSave(this.label);
}

class _SidebarLabelReset extends _SidebarLabelEdit {
  const _SidebarLabelReset();
}

class _SidebarLabelDialog extends StatefulWidget {
  final SidebarDestination destination;
  final String initialValue;
  final bool canReset;

  const _SidebarLabelDialog({
    required this.destination,
    required this.initialValue,
    required this.canReset,
  });

  @override
  State<_SidebarLabelDialog> createState() => _SidebarLabelDialogState();
}

class _SidebarLabelDialogState extends State<_SidebarLabelDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );
  final FocusNode _fieldNode = FocusNode(debugLabel: 'sidebar-label-field');
  final FocusNode _saveNode = FocusNode(debugLabel: 'sidebar-label-save');
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fieldNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _fieldNode.dispose();
    _saveNode.dispose();
    super.dispose();
  }

  void _save() {
    final label = SidebarConfiguration.normalizeLabel(_controller.text);
    if (label == null) {
      setState(() {
        _error = 'Use 1–${SidebarConfiguration.maxLabelRunes} characters';
      });
      return;
    }
    Navigator.of(context).pop<_SidebarLabelEdit>(_SidebarLabelSave(label));
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return AlertDialog(
      title: Text('Rename ${widget.destination.defaultLabel}'),
      content: SizedBox(
        width: 380,
        child: TvTextField(
          controller: _controller,
          focusNode: _fieldNode,
          autofocus: !_isTv,
          inputFormatters: <TextInputFormatter>[
            LengthLimitingTextInputFormatter(
              SidebarConfiguration.maxLabelRunes,
            ),
          ],
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _save(),
          onDownArrow: () => _saveNode.requestFocus(),
          accent: app.settings.accent,
          keyboardGround: app.youtube.keyboardPanel,
          keyboardInk: app.core.tx,
          keyboardInkOnAccent: app.inkOn(app.settings.accent),
          decoration: InputDecoration(
            labelText: 'Sidebar name',
            helperText: 'Default: ${widget.destination.defaultLabel}',
            errorText: _error,
          ),
        ),
      ),
      actions: [
        if (widget.canReset)
          TextButton(
            onPressed: () => Navigator.of(
              context,
            ).pop<_SidebarLabelEdit>(const _SidebarLabelReset()),
            child: const Text('Use default'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          focusNode: _saveNode,
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }

  bool get _isTv => PlatformUtil.isTelevision;
}
