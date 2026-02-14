import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/stremio_addon.dart';
import '../../../services/storage_service.dart';

/// Internal tree node for the filter UI.
class _FilterNode {
  final String id;
  final String label;
  final int depth; // 0 = addon, 1 = catalog, 2 = genre
  final bool isExpandable;
  bool isExpanded;
  final List<_FilterNode> children;

  _FilterNode({
    required this.id,
    required this.label,
    required this.depth,
    this.isExpandable = false,
    bool expanded = false,
    this.children = const [],
  }) : isExpanded = expanded;
}

/// Bottom sheet that lets users enable/disable Stremio TV channels
/// at the addon, catalog, and genre level using a collapsible tree.
class StremioTvChannelFilterSheet extends StatefulWidget {
  final List<({StremioAddon addon, List<StremioAddonCatalog> catalogs})>
      filterTree;
  final Set<String> disabledFilters;

  const StremioTvChannelFilterSheet({
    super.key,
    required this.filterTree,
    required this.disabledFilters,
  });

  /// Show as a centered dialog. Returns true if filters changed.
  static Future<bool?> show(
    BuildContext context, {
    required List<({StremioAddon addon, List<StremioAddonCatalog> catalogs})>
        filterTree,
    required Set<String> disabledFilters,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => Center(
        child: StremioTvChannelFilterSheet(
          filterTree: filterTree,
          disabledFilters: Set.of(disabledFilters),
        ),
      ),
    );
  }

  @override
  State<StremioTvChannelFilterSheet> createState() =>
      _StremioTvChannelFilterSheetState();
}

class _StremioTvChannelFilterSheetState
    extends State<StremioTvChannelFilterSheet> {
  late Set<String> _disabled;
  late List<_FilterNode> _tree;
  List<_FilterNode> _flatList = [];
  final Map<String, FocusNode> _focusNodeMap = {};
  bool _changed = false;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _disabled = widget.disabledFilters;
    _tree = _buildTree();
    _rebuildFlatList();
  }

  @override
  void dispose() {
    for (final node in _focusNodeMap.values) {
      node.dispose();
    }
    super.dispose();
  }

  FocusNode _focusNodeFor(String id) {
    return _focusNodeMap.putIfAbsent(
      id,
      () => FocusNode(debugLabel: 'filter_$id'),
    );
  }

  List<_FilterNode> _buildTree() {
    return widget.filterTree.map((entry) {
      final addon = entry.addon;
      final catalogNodes = entry.catalogs.map((catalog) {
        final catalogId = '${addon.id}:${catalog.id}:${catalog.type}';
        final genres = catalog.genreOptions;

        final genreNodes = genres
            .map((genre) => _FilterNode(
                  id: '$catalogId:$genre',
                  label: genre,
                  depth: 2,
                ))
            .toList();

        return _FilterNode(
          id: catalogId,
          label: '${catalog.name} (${catalog.type})',
          depth: 1,
          isExpandable: genreNodes.isNotEmpty,
          children: genreNodes,
        );
      }).toList();

      return _FilterNode(
        id: addon.id,
        label: addon.name,
        depth: 0,
        isExpandable: true,
        children: catalogNodes,
      );
    }).toList();
  }

  void _rebuildFlatList() {
    final flat = <_FilterNode>[];
    void walk(List<_FilterNode> nodes) {
      for (final node in nodes) {
        flat.add(node);
        if (node.isExpanded && node.children.isNotEmpty) {
          walk(node.children);
        }
      }
    }

    walk(_tree);
    _flatList = flat;
  }

  // ========================================================================
  // Checkbox state logic
  // ========================================================================

  /// Tri-state for parent nodes: true = all on, false = all off, null = mixed.
  /// Parent state is always derived from children.
  bool? _checkState(_FilterNode node) {
    if (node.children.isEmpty) {
      return !_disabled.contains(node.id);
    }

    final allEnabled = node.children.every((c) => _checkState(c) == true);
    final allDisabled = node.children.every((c) => _checkState(c) == false);
    if (allEnabled) return true;
    if (allDisabled) return false;
    return null; // indeterminate
  }

  void _toggle(_FilterNode node) {
    setState(() {
      _changed = true;
      final state = _checkState(node);
      if (state == true) {
        // Disable this node and all descendants
        _disableAll(node);
      } else {
        // Enable this node and all descendants, and clear ancestor disabled flags
        _enableAll(node);
        _enableAncestors(node);
      }
    });
  }

  void _disableAll(_FilterNode node) {
    _disabled.add(node.id);
    for (final child in node.children) {
      _disableAll(child);
    }
  }

  void _enableAll(_FilterNode node) {
    _disabled.remove(node.id);
    for (final child in node.children) {
      _enableAll(child);
    }
  }

  /// Remove ancestor IDs from the disabled set so a re-enabled child
  /// isn't blocked by a parent-level disable in discoverChannels().
  void _enableAncestors(_FilterNode target) {
    for (final addon in _tree) {
      if (addon.id == target.id) return;
      for (final catalog in addon.children) {
        if (catalog.id == target.id) {
          _disabled.remove(addon.id);
          return;
        }
        for (final genre in catalog.children) {
          if (genre.id == target.id) {
            _disabled.remove(catalog.id);
            _disabled.remove(addon.id);
            return;
          }
        }
      }
    }
  }

  void _enableAllNodes() {
    setState(() {
      _changed = true;
      _disabled.clear();
    });
  }

  void _disableAllNodes() {
    setState(() {
      _changed = true;
      void disableRecursive(List<_FilterNode> nodes) {
        for (final node in nodes) {
          _disabled.add(node.id);
          disableRecursive(node.children);
        }
      }

      disableRecursive(_tree);
    });
  }

  void _toggleExpand(_FilterNode node) {
    if (!node.isExpandable) return;
    setState(() {
      node.isExpanded = !node.isExpanded;
      _rebuildFlatList();
    });
  }

  Future<void> _saveAndClose() async {
    await _persist();
    if (mounted) Navigator.of(context).pop(_changed);
  }

  Future<void> _persist() async {
    if (_changed && !_saved) {
      _saved = true;
      await StorageService.setStremioTvDisabledFilters(_disabled);
    }
  }

  // ========================================================================
  // DPAD key handling
  // ========================================================================

  void _scrollToNode(String nodeId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final focusNode = _focusNodeFor(nodeId);
      if (focusNode.context != null) {
        Scrollable.ensureVisible(
          focusNode.context!,
          alignment: 0.5,
          duration: const Duration(milliseconds: 150),
        );
      }
    });
  }

  KeyEventResult _handleRowKey(int index, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final node = _flatList[index];

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (index > 0) {
        final targetId = _flatList[index - 1].id;
        _focusNodeFor(targetId).requestFocus();
        _scrollToNode(targetId);
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (index < _flatList.length - 1) {
        final targetId = _flatList[index + 1].id;
        _focusNodeFor(targetId).requestFocus();
        _scrollToNode(targetId);
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (node.isExpandable && !node.isExpanded) {
        _toggleExpand(node);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _focusNodeFor(node.id).requestFocus();
        });
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (node.isExpandable && node.isExpanded) {
        _toggleExpand(node);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _focusNodeFor(node.id).requestFocus();
        });
      } else if (node.depth > 0) {
        // Move focus to parent
        final parentDepth = node.depth - 1;
        for (int i = index - 1; i >= 0; i--) {
          if (_flatList[i].depth == parentDepth) {
            final parentId = _flatList[i].id;
            _focusNodeFor(parentId).requestFocus();
            _scrollToNode(parentId);
            break;
          }
        }
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.enter) {
      _toggle(node);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  // ========================================================================
  // Build
  // ========================================================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenHeight = MediaQuery.of(context).size.height;
    final maxHeight = screenHeight * 0.8;

    return PopScope(
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) await _persist();
      },
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: 500,
            maxHeight: maxHeight,
          ),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
                child: Row(
                  children: [
                    Icon(
                      Icons.tune_rounded,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Channel Filters',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _enableAllNodes,
                      child: const Text('All On'),
                    ),
                    TextButton(
                      onPressed: _disableAllNodes,
                      child: const Text('All Off'),
                    ),
                    IconButton(
                      onPressed: _saveAndClose,
                      icon: const Icon(Icons.close),
                      tooltip: 'Close',
                    ),
                  ],
                ),
              ),
              // Hint text
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'Use left/right arrow keys to collapse/expand',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.6),
                  ),
                ),
              ),
              const Divider(),
              // Tree list
              Flexible(
                child: _flatList.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            'No addons with catalogs found.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 16),
                        itemCount: _flatList.length,
                        itemBuilder: (context, index) {
                          final node = _flatList[index];
                          return _buildRow(node, index, theme);
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRow(_FilterNode node, int index, ThemeData theme) {
    final indent = node.depth * 24.0;
    final state = _checkState(node);
    final focusNode = _focusNodeFor(node.id);

    return Focus(
      focusNode: focusNode,
      onKeyEvent: (_, event) => _handleRowKey(index, event),
      child: ListenableBuilder(
        listenable: focusNode,
        builder: (context, _) {
          final hasFocus = focusNode.hasFocus;
          return Container(
            color: hasFocus
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
                : null,
            child: InkWell(
              onTap: () => _toggle(node),
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16 + indent,
                  right: 12,
                  top: 6,
                  bottom: 6,
                ),
                child: Row(
                  children: [
                    // Expand/collapse icon
                    SizedBox(
                      width: 28,
                      child: node.isExpandable
                          ? GestureDetector(
                              onTap: () => _toggleExpand(node),
                              child: Icon(
                                node.isExpanded
                                    ? Icons.expand_more
                                    : Icons.chevron_right,
                                size: 20,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            )
                          : null,
                    ),
                    // Checkbox
                    SizedBox(
                      width: 32,
                      height: 32,
                      child: Checkbox(
                        value: state,
                        tristate: true,
                        onChanged: (_) => _toggle(node),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Label
                    Expanded(
                      child: Text(
                        node.label,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight:
                              node.depth == 0 ? FontWeight.w600 : null,
                          color: state == false
                              ? theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.5)
                              : null,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
