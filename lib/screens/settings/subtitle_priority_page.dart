import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/subtitle_source_priority.dart';
import '../../services/storage_service.dart';
import '../../services/stremio_subtitle_service.dart';
import '../../theme/app_theme_scope.dart';
import '../../utils/platform_util.dart';
import '../../utils/tv_keys.dart';
import 'widgets/settings_widgets.dart';

class SubtitlePriorityPage extends StatefulWidget {
  const SubtitlePriorityPage({super.key});

  @override
  State<SubtitlePriorityPage> createState() => _SubtitlePriorityPageState();
}

class _SubtitlePriorityPageState extends State<SubtitlePriorityPage> {
  final _names = <String, String>{
    SubtitleSourcePriority.embedded: 'Embedded subtitles',
  };
  final _nodes = <String, FocusNode>{};
  List<String> _saved = [], _order = [];
  String? _moving;
  bool _loading = true, _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final order = await StorageService.getSubtitleSourcePriority();
      final addons = await StremioSubtitleService.instance.getSubtitleAddons();
      if (!mounted) return;
      for (final a in addons) {
        _names[SubtitleSourcePriority.addon(a.portableConfigurationKey)] =
            a.name;
      }
      _saved = order;
      _order = SubtitleSourcePriority.effective(
        order,
        addons.map((a) => a.portableConfigurationKey),
      );
      for (final id in _order) {
        _nodes[id] = FocusNode(debugLabel: 'subtitle-priority-$id');
      }
      setState(() => _loading = false);
      if (PlatformUtil.isTelevision) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _nodes[_order.first]?.requestFocus();
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load subtitle sources.';
        });
      }
    }
  }

  Future<void> _select(String id) async {
    if (_saving) return;
    if (_moving == null) {
      setState(() => _moving = id);
      return;
    }
    if (_moving != id) return;
    setState(() => _saving = true);
    try {
      // Keep dormant addon IDs so temporary disablement does not erase them.
      final saved = [..._order, ..._saved.where((s) => !_order.contains(s))];
      await StorageService.setSubtitleSourcePriority(saved);
      if (!mounted) return;
      setState(() {
        _saved = saved;
        _moving = null;
        _saving = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save subtitle priority. Try again.'),
          ),
        );
      }
    }
  }

  void _move(String id, int delta) {
    if (_saving || _moving != id) return;
    final from = _order.indexOf(id), to = _order.indexOf(id) + delta;
    if (to < 0 || to >= _order.length) return;
    setState(() {
      _order.removeAt(from);
      _order.insert(to, id);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final node = _nodes[id]!;
      node.requestFocus();
      if (node.context != null) {
        Scrollable.ensureVisible(node.context!, alignment: .5);
      }
    });
  }

  void _cancel() {
    if (_saving) return;
    setState(() {
      _order = SubtitleSourcePriority.effective(
        _saved,
        _names.keys
            .where((k) => k != SubtitleSourcePriority.embedded)
            .map((k) => k.substring(6)),
      );
      _moving = null;
    });
  }

  @override
  void dispose() {
    for (final node in _nodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
    return PopScope(
      canPop: _moving == null && !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: SettingsPageScaffold(
        title: 'Subtitle priority',
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: kSettingsMaxWidth,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SettingsPageHeader(
                          icon: Icons.low_priority_rounded,
                          title: 'Subtitle priority',
                          subtitle:
                              'Try sources from top to bottom for your subtitle language. No Preference tries English first, then another available track within each source.',
                        ),
                        const SizedBox(height: 20),
                        if (_error != null)
                          Text(_error!)
                        else ...[
                          SettingsInfoBanner(
                            text: _moving == null
                                ? 'Select a source to move it. Use Up / Down, then select again to save. Back cancels the move.'
                                : _saving
                                ? 'Saving priority…'
                                : 'Moving ${_names[_moving]}. Up / Down moves it; select saves; Back cancels.',
                          ),
                          const SizedBox(height: 16),
                          for (final id in _order)
                            Padding(
                              key: ValueKey(id),
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Focus(
                                focusNode: _nodes[id],
                                onFocusChange: (_) {
                                  if (mounted) setState(() {});
                                },
                                onKeyEvent: (_, event) {
                                  final key = event.logicalKey;
                                  if (isActivateKey(key)) {
                                    if (event is KeyDownEvent) _select(id);
                                    return KeyEventResult.handled;
                                  }
                                  if (_moving != null &&
                                      (key == LogicalKeyboardKey.arrowUp ||
                                          key ==
                                              LogicalKeyboardKey.arrowDown)) {
                                    if (event is KeyDownEvent ||
                                        event is KeyRepeatEvent) {
                                      _move(
                                        _moving!,
                                        key == LogicalKeyboardKey.arrowUp
                                            ? -1
                                            : 1,
                                      );
                                    }
                                    return KeyEventResult.handled;
                                  }
                                  if (_moving != null &&
                                      key == LogicalKeyboardKey.escape) {
                                    if (event is KeyDownEvent) _cancel();
                                    return KeyEventResult.handled;
                                  }
                                  return KeyEventResult.ignored;
                                },
                                child: InkWell(
                                  canRequestFocus: false,
                                  onTap: () => _select(id),
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: t.panel,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color:
                                            _nodes[id]!.hasFocus ||
                                                _moving == id
                                            ? t.accent
                                            : t.line,
                                        width: 2,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Text(
                                          '${_order.indexOf(id) + 1}',
                                          style: TextStyle(color: t.dim),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: Text(
                                            _names[id]!,
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodyLarge,
                                          ),
                                        ),
                                        if (_moving == id) ...[
                                          IconButton(
                                            tooltip: 'Move up',
                                            onPressed:
                                                _saving || _order.first == id
                                                ? null
                                                : () => _move(id, -1),
                                            icon: const Icon(
                                              Icons.arrow_upward,
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: 'Move down',
                                            onPressed:
                                                _saving || _order.last == id
                                                ? null
                                                : () => _move(id, 1),
                                            icon: const Icon(
                                              Icons.arrow_downward,
                                            ),
                                          ),
                                          TextButton(
                                            onPressed: _saving
                                                ? null
                                                : () => _select(id),
                                            child: const Text('Done'),
                                          ),
                                        ] else
                                          const Icon(Icons.drag_handle),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(height: 12),
                          Text(
                            'Only enabled subtitle addons are shown. Unavailable sources are skipped. New addons are added at the end. Manual selections and Subtitles Off always take precedence.',
                            style: TextStyle(color: t.dim),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
