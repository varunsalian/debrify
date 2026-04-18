import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/stremio_addon.dart';
import '../../../services/storage_service.dart';

class StremioTvCatalogPickerResult {
  final String message;
  final bool createdNew;
  final bool duplicate;

  const StremioTvCatalogPickerResult({
    required this.message,
    this.createdNew = false,
    this.duplicate = false,
  });
}

class StremioTvCatalogPickerDialog extends StatefulWidget {
  final StremioMeta item;

  const StremioTvCatalogPickerDialog({super.key, required this.item});

  static Future<StremioTvCatalogPickerResult?> show(
    BuildContext context, {
    required StremioMeta item,
  }) {
    return showDialog<StremioTvCatalogPickerResult>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) =>
          Center(child: StremioTvCatalogPickerDialog(item: item)),
    );
  }

  @override
  State<StremioTvCatalogPickerDialog> createState() =>
      _StremioTvCatalogPickerDialogState();
}

class _StremioTvCatalogPickerDialogState
    extends State<StremioTvCatalogPickerDialog> {
  final FocusNode _newChannelFocusNode = FocusNode(debugLabel: 'sttv-new');
  final FocusNode _cancelSelectionFocusNode = FocusNode(
    debugLabel: 'sttv-cancel-selection',
  );
  final FocusNode _searchFocusNode = FocusNode(debugLabel: 'sttv-search');
  final FocusNode _nameFieldFocusNode = FocusNode(debugLabel: 'sttv-name');
  final FocusNode _createConfirmFocusNode = FocusNode(
    debugLabel: 'sttv-create-confirm',
  );
  final FocusNode _createCancelFocusNode = FocusNode(
    debugLabel: 'sttv-create-cancel',
  );
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final List<FocusNode> _catalogFocusNodes = [];

  List<Map<String, dynamic>> _catalogs = [];
  bool _loading = true;
  bool _saving = false;
  bool _showCreateView = false;

  @override
  void initState() {
    super.initState();
    _loadCatalogs();
  }

  @override
  void dispose() {
    _newChannelFocusNode.dispose();
    _cancelSelectionFocusNode.dispose();
    _searchFocusNode.dispose();
    _nameFieldFocusNode.dispose();
    _createConfirmFocusNode.dispose();
    _createCancelFocusNode.dispose();
    _nameController.dispose();
    _searchController.dispose();
    for (final node in _catalogFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _loadCatalogs() async {
    final allCatalogs = await StorageService.getStremioTvLocalCatalogs();
    final compatibleCatalogs =
        allCatalogs.where((catalog) {
          final type = catalog['type'] as String? ?? 'movie';
          return type == widget.item.type;
        }).toList()..sort((a, b) {
          final aName = (a['name'] as String? ?? '').toLowerCase();
          final bName = (b['name'] as String? ?? '').toLowerCase();
          return aName.compareTo(bName);
        });

    while (_catalogFocusNodes.length > compatibleCatalogs.length) {
      _catalogFocusNodes.removeLast().dispose();
    }
    while (_catalogFocusNodes.length < compatibleCatalogs.length) {
      _catalogFocusNodes.add(
        FocusNode(debugLabel: 'sttv-catalog-${_catalogFocusNodes.length}'),
      );
    }

    if (!mounted) return;
    setState(() {
      _catalogs = compatibleCatalogs;
      _loading = false;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_showCreateView) {
        _newChannelFocusNode.requestFocus();
      }
    });
  }

  Future<void> _appendToCatalog(Map<String, dynamic> catalog) async {
    if (_saving) return;
    setState(() => _saving = true);

    final result = await _StremioTvLocalCatalogEditor.addItemToCatalog(
      catalogId: catalog['id'] as String? ?? '',
      item: widget.item,
    );

    if (!mounted) return;
    setState(() => _saving = false);

    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Failed to update channel'),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }

    if (result.duplicate) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: Colors.orange.shade700,
        ),
      );
      return;
    }

    Navigator.of(context).pop(result);
  }

  void _openCreateView() {
    if (_saving) return;
    setState(() => _showCreateView = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _nameFieldFocusNode.requestFocus();
      }
    });
  }

  void _closeCreateView() {
    if (_saving) return;
    setState(() {
      _showCreateView = false;
      _nameController.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _newChannelFocusNode.requestFocus();
      }
    });
  }

  Future<void> _createCatalog() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Channel name cannot be empty'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_saving) return;
    setState(() => _saving = true);

    final result = await _StremioTvLocalCatalogEditor.createCatalogWithItem(
      catalogName: name,
      item: widget.item,
    );

    if (!mounted) return;
    setState(() => _saving = false);

    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Failed to create channel'),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }

    if (result.duplicate) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: Colors.orange.shade700,
        ),
      );
      return;
    }

    Navigator.of(context).pop(result);
  }

  void _dismissDialog() {
    if (_saving) return;
    Navigator.of(context).pop();
  }

  List<int> get _filteredCatalogIndices {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return List<int>.generate(_catalogs.length, (index) => index);
    }
    return List<int>.generate(_catalogs.length, (index) => index).where((
      index,
    ) {
      final name = (_catalogs[index]['name'] as String? ?? '').toLowerCase();
      return name.contains(query);
    }).toList();
  }

  KeyEventResult _handleSelectionKey(
    KeyEvent event, {
    required FocusNode? previous,
    required FocusNode? next,
    VoidCallback? onActivate,
  }) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowUp && previous != null) {
      previous.requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown && next != null) {
      next.requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.select) {
      onActivate?.call();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleSearchFieldKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;
    final text = _searchController.text;
    final selection = _searchController.selection;
    final textLength = text.length;
    final isTextEmpty = textLength == 0;
    final filteredIndices = _filteredCatalogIndices;

    final isSelectionValid = selection.isValid && selection.baseOffset >= 0;
    final isAtStart =
        !isSelectionValid ||
        (selection.baseOffset == 0 && selection.extentOffset == 0);
    final isAtEnd =
        !isSelectionValid ||
        (selection.baseOffset == textLength &&
            selection.extentOffset == textLength);

    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
      _cancelSelectionFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      if (isTextEmpty || isAtStart) {
        _newChannelFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
    }
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.select) {
      if (isTextEmpty || isAtEnd) {
        if (filteredIndices.isNotEmpty) {
          _catalogFocusNodes[filteredIndices.first].requestFocus();
        } else {
          _cancelSelectionFocusNode.requestFocus();
        }
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleCreateFieldKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;
    final text = _nameController.text;
    final selection = _nameController.selection;
    final textLength = text.length;
    final isTextEmpty = textLength == 0;

    final isSelectionValid = selection.isValid && selection.baseOffset >= 0;
    final isAtStart =
        !isSelectionValid ||
        (selection.baseOffset == 0 && selection.extentOffset == 0);
    final isAtEnd =
        !isSelectionValid ||
        (selection.baseOffset == textLength &&
            selection.extentOffset == textLength);

    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
      _createCancelFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      if (isTextEmpty || isAtStart) {
        _createCancelFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
    }
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.select) {
      if (isTextEmpty || isAtEnd) {
        _createConfirmFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleCreateButtonKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _nameFieldFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
        node == _createCancelFocusNode) {
      _createConfirmFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight &&
        node == _createConfirmFocusNode) {
      _createCancelFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.select) {
      if (node == _createConfirmFocusNode) {
        _createCatalog();
      } else {
        _closeCreateView();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.goBack) {
      _closeCreateView();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      type: MaterialType.transparency,
      child: PopScope(
        canPop: !_saving,
        child: SafeArea(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 620),
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(24),
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: _showCreateView
                  ? _buildCreateView(theme)
                  : _buildSelectionView(theme),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectionView(ThemeData theme) {
    final filteredIndices = _filteredCatalogIndices;

    return Padding(
      key: const ValueKey('selection'),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Add to Stremio TV',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            widget.item.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            Focus(
              focusNode: _newChannelFocusNode,
              onKeyEvent: (_, event) => _handleSelectionKey(
                event,
                previous: null,
                next: _catalogs.isNotEmpty
                    ? _searchFocusNode
                    : _cancelSelectionFocusNode,
                onActivate: _saving ? null : _openCreateView,
              ),
              child: _buildActionTile(
                theme,
                focusNode: _newChannelFocusNode,
                icon: Icons.add_circle_outline_rounded,
                title: 'New Channel',
                subtitle: 'Create a new local channel from this item',
                enabled: !_saving,
                onTap: _openCreateView,
              ),
            ),
            const SizedBox(height: 12),
            if (_catalogs.isNotEmpty) ...[
              Text(
                'Add to Existing Channel',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              _buildFocusedTextField(
                focusNode: _searchFocusNode,
                child: Focus(
                  onKeyEvent: _handleSearchFieldKey,
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    enabled: !_saving,
                    textInputAction: TextInputAction.search,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) {
                      if (filteredIndices.isNotEmpty) {
                        _catalogFocusNodes[filteredIndices.first]
                            .requestFocus();
                      }
                    },
                    decoration: InputDecoration(
                      labelText: 'Search channels',
                      hintText: 'Filter by channel name',
                      prefixIcon: const Icon(Icons.search_rounded),
                      border: const OutlineInputBorder(),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              onPressed: _saving
                                  ? null
                                  : () {
                                      setState(() {
                                        _searchController.clear();
                                      });
                                      _searchFocusNode.requestFocus();
                                    },
                              icon: const Icon(Icons.close_rounded),
                              tooltip: 'Clear search',
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: filteredIndices.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final catalogIndex = filteredIndices[index];
                    final catalog = _catalogs[catalogIndex];
                    final focusNode = _catalogFocusNodes[catalogIndex];
                    final previous = index == 0
                        ? _searchFocusNode
                        : _catalogFocusNodes[filteredIndices[index - 1]];
                    final next = index + 1 < filteredIndices.length
                        ? _catalogFocusNodes[filteredIndices[index + 1]]
                        : _cancelSelectionFocusNode;
                    final itemCount =
                        (catalog['items'] as List<dynamic>? ?? []).length;

                    return Builder(
                      builder: (itemContext) => Focus(
                        focusNode: focusNode,
                        onFocusChange: (focused) {
                          if (focused) {
                            Scrollable.ensureVisible(
                              itemContext,
                              alignment: 0.5,
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeOut,
                            );
                          }
                        },
                        onKeyEvent: (_, event) => _handleSelectionKey(
                          event,
                          previous: previous,
                          next: next,
                          onActivate: _saving
                              ? null
                              : () => _appendToCatalog(catalog),
                        ),
                        child: _buildActionTile(
                          theme,
                          focusNode: focusNode,
                          icon: widget.item.type == 'series'
                              ? Icons.tv_rounded
                              : Icons.movie_rounded,
                          title: catalog['name'] as String? ?? 'Unknown',
                          subtitle:
                              '$itemCount item${itemCount == 1 ? '' : 's'}',
                          enabled: !_saving,
                          onTap: () => _appendToCatalog(catalog),
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (filteredIndices.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'No matching channels found.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
            ] else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'No existing ${widget.item.type} channels yet.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Focus(
              focusNode: _cancelSelectionFocusNode,
              onKeyEvent: (_, event) => _handleSelectionKey(
                event,
                previous: filteredIndices.isNotEmpty
                    ? _catalogFocusNodes[filteredIndices.last]
                    : (_catalogs.isNotEmpty
                          ? _searchFocusNode
                          : _newChannelFocusNode),
                next: null,
                onActivate: _dismissDialog,
              ),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _saving ? null : _dismissDialog,
                  child: const Text('Cancel'),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCreateView(ThemeData theme) {
    return Padding(
      key: const ValueKey('create'),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'New Channel',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Create a local Stremio TV channel for "${widget.item.name}"',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          _buildFocusedTextField(
            focusNode: _nameFieldFocusNode,
            child: Focus(
              onKeyEvent: _handleCreateFieldKey,
              child: TextField(
                controller: _nameController,
                focusNode: _nameFieldFocusNode,
                autofocus: true,
                textInputAction: TextInputAction.done,
                enabled: !_saving,
                onSubmitted: (_) {
                  if (_nameController.text.trim().isNotEmpty) {
                    _createConfirmFocusNode.requestFocus();
                  }
                },
                decoration: const InputDecoration(
                  labelText: 'Channel name',
                  hintText: 'My Weekend Picks',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Focus(
                  focusNode: _createConfirmFocusNode,
                  onKeyEvent: _handleCreateButtonKey,
                  child: _buildCreateButton(
                    focusNode: _createConfirmFocusNode,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _createCatalog,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check_rounded),
                      label: Text(_saving ? 'Creating...' : 'Create'),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Focus(
                  focusNode: _createCancelFocusNode,
                  onKeyEvent: _handleCreateButtonKey,
                  child: _buildCreateButton(
                    focusNode: _createCancelFocusNode,
                    child: OutlinedButton(
                      onPressed: _saving ? null : _closeCreateView,
                      child: const Text('Back'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionTile(
    ThemeData theme, {
    required FocusNode focusNode,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    return ListenableBuilder(
      listenable: focusNode,
      builder: (context, _) {
        final isFocused = focusNode.hasFocus;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onTap : null,
            canRequestFocus: false,
            borderRadius: BorderRadius.circular(16),
            child: Ink(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isFocused
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outlineVariant,
                  width: isFocused ? 2 : 1,
                ),
                color: isFocused
                    ? theme.colorScheme.primary.withValues(alpha: 0.08)
                    : theme.colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.35,
                      ),
              ),
              child: Row(
                children: [
                  Icon(
                    icon,
                    color: enabled
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCreateButton({
    required FocusNode focusNode,
    required Widget child,
  }) {
    return ListenableBuilder(
      listenable: focusNode,
      builder: (context, _) {
        final isFocused = focusNode.hasFocus;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: isFocused
                ? Border.all(color: Colors.white, width: 2)
                : null,
            boxShadow: isFocused
                ? [
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.18),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: child,
        );
      },
    );
  }

  Widget _buildFocusedTextField({
    required FocusNode focusNode,
    required Widget child,
  }) {
    return ListenableBuilder(
      listenable: focusNode,
      builder: (context, _) {
        final isFocused = focusNode.hasFocus;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: isFocused
                ? Border.all(color: Colors.white, width: 2)
                : null,
            boxShadow: isFocused
                ? [
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.18),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: child,
        );
      },
    );
  }
}

class _StremioTvLocalCatalogEditor {
  static Future<StremioTvCatalogPickerResult?> createCatalogWithItem({
    required String catalogName,
    required StremioMeta item,
  }) async {
    final trimmedName = catalogName.trim();
    if (trimmedName.isEmpty) return null;

    final existing = await StorageService.getStremioTvLocalCatalogs();
    if (existing.any(
      (catalog) => (catalog['name'] as String?) == trimmedName,
    )) {
      return const StremioTvCatalogPickerResult(
        message: 'A channel with that name already exists',
        duplicate: true,
      );
    }

    await StorageService.addStremioTvLocalCatalog({
      'id': _generateId(trimmedName),
      'name': trimmedName,
      'type': item.type,
      'addedAt': DateTime.now().toIso8601String(),
      'items': [item.toJson()],
    });

    return StremioTvCatalogPickerResult(
      message: 'Created "$trimmedName" in Stremio TV',
      createdNew: true,
    );
  }

  static Future<StremioTvCatalogPickerResult?> addItemToCatalog({
    required String catalogId,
    required StremioMeta item,
  }) async {
    if (catalogId.isEmpty) return null;

    final existing = await StorageService.getStremioTvLocalCatalogs();
    final index = existing.indexWhere((catalog) => catalog['id'] == catalogId);
    if (index < 0) return null;

    final catalog = Map<String, dynamic>.from(existing[index]);
    final catalogName = catalog['name'] as String? ?? 'Unknown';
    final items = List<Map<String, dynamic>>.from(
      (catalog['items'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>(),
    );

    if (_containsItem(items, item)) {
      return StremioTvCatalogPickerResult(
        message: '"${item.name}" is already in "$catalogName"',
        duplicate: true,
      );
    }

    items.add(item.toJson());
    catalog['items'] = items;
    catalog['updatedAt'] = DateTime.now().toIso8601String();

    final updated = await StorageService.updateStremioTvLocalCatalog(catalog);
    if (!updated) return null;

    return StremioTvCatalogPickerResult(
      message: 'Added "${item.name}" to "$catalogName"',
    );
  }

  static bool _containsItem(
    List<Map<String, dynamic>> items,
    StremioMeta target,
  ) {
    final targetKey = _identityKeyForMeta(target);
    if (targetKey == null) return false;

    for (final item in items) {
      final existingMeta = StremioMeta.fromJson({
        ...item,
        if (!item.containsKey('type')) 'type': target.type,
      });
      final existingKey = _identityKeyForMeta(existingMeta);
      if (existingKey == targetKey) {
        return true;
      }
    }
    return false;
  }

  static String? _identityKeyForMeta(StremioMeta item) {
    return item.effectiveImdbId ?? (item.id.isNotEmpty ? item.id : null);
  }

  static String _generateId(String name) {
    final sanitized = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final ts = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    return '${sanitized}_$ts';
  }
}
