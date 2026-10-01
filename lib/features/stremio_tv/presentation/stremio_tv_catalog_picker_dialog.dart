import 'stremio_tv_focus_frame.dart';
import 'stremio_tv_catalog_picker_views.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../utils/tv_keys.dart';
import '../../../models/stremio_addon.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/stremio_tv_providers.dart';
import '../data/stremio_tv_catalog_editor.dart';
import '../models/stremio_tv_catalog_picker_result.dart';
import '../models/stremio_tv_catalog_option.dart';
export '../models/stremio_tv_catalog_picker_result.dart';
import '../../../theme/app_theme_scope.dart';
import '../../../widgets/tv_text_field.dart';

class StremioTvCatalogPickerDialog extends StatefulWidget {
  final StremioMeta item;
  final StremioTvCatalogEditor editor;
  final bool Function()? isCurrent;

  const StremioTvCatalogPickerDialog({
    super.key,
    required this.item,
    required this.editor,
    this.isCurrent,
  });

  static Future<StremioTvCatalogPickerResult?> show(
    BuildContext context, {
    required StremioMeta item,
    bool Function()? isCurrent,
  }) {
    if (!context.mounted || isCurrent?.call() == false) return Future.value();
    final editor = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(stremioTvCatalogEditorFactoryProvider)();
    return showDialog<StremioTvCatalogPickerResult>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Center(
        child: StremioTvCatalogPickerDialog(
          item: item,
          editor: editor,
          isCurrent: isCurrent,
        ),
      ),
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

  List<StremioTvCatalogOption> _catalogs = [];
  bool get _current =>
      mounted &&
      widget.editor.isCurrent() &&
      (widget.isCurrent?.call() ?? true);
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
    final compatibleCatalogs = await widget.editor.load(widget.item.type);
    if (!_current || compatibleCatalogs == null) return;

    while (_catalogFocusNodes.length > compatibleCatalogs.length) {
      _catalogFocusNodes.removeLast().dispose();
    }
    while (_catalogFocusNodes.length < compatibleCatalogs.length) {
      _catalogFocusNodes.add(
        FocusNode(debugLabel: 'sttv-catalog-${_catalogFocusNodes.length}'),
      );
    }

    if (!mounted || !_current) return;
    setState(() {
      _catalogs = compatibleCatalogs;
      _loading = false;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_current && !_showCreateView) {
        _newChannelFocusNode.requestFocus();
      }
    });
  }

  Future<void> _appendToCatalog(StremioTvCatalogOption catalog) async {
    if (!_current || _saving) return;
    setState(() => _saving = true);

    final result = await widget.editor.addItemToCatalog(
      catalogId: catalog.id,
      item: widget.item,
      canContinue: () => _current,
    );

    if (!mounted) return;
    setState(() => _saving = false);
    if (!_current) return;

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

    _finish(result);
  }

  void _openCreateView() {
    if (!_current || _saving) return;
    setState(() => _showCreateView = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_current) {
        _nameFieldFocusNode.requestFocus();
      }
    });
  }

  void _closeCreateView() {
    if (!_current || _saving) return;
    setState(() {
      _showCreateView = false;
      _nameController.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_current) {
        _newChannelFocusNode.requestFocus();
      }
    });
  }

  Future<void> _createCatalog() async {
    if (!_current || _saving) return;
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

    if (!_current || _saving) return;
    setState(() => _saving = true);

    final result = await widget.editor.createCatalogWithItem(
      catalogName: name,
      item: widget.item,
      canContinue: () => _current,
    );

    if (!mounted) return;
    setState(() => _saving = false);
    if (!_current) return;

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

    _finish(result);
  }

  void _finish(StremioTvCatalogPickerResult? result) {
    final route = ModalRoute.of(context);
    final navigator = Navigator.of(context);
    if (route?.isCurrent ?? false) {
      navigator.pop(result);
    } else if (route?.isActive ?? false) {
      navigator.removeRoute(route!, result);
    }
  }

  void _dismissDialog() {
    if (_saving && _current) return;
    _finish(null);
  }

  List<int> get _filteredCatalogIndices {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return List<int>.generate(_catalogs.length, (index) => index);
    }
    return List<int>.generate(_catalogs.length, (index) => index).where((
      index,
    ) {
      final name = _catalogs[index].searchName.toLowerCase();
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
    if (isActivateKey(event.logicalKey)) {
      onActivate?.call();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Back/Escape from the search field moves focus to Cancel (instead of
  /// popping the dialog). Sits on an ancestor Focus of the TvTextField so it
  /// runs when the shell lets the key bubble; DPAD arrow exits live on the
  /// TvTextField itself (onUp/DownArrow).
  KeyEventResult _handleSearchFieldBack(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
      _cancelSelectionFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Back/Escape from the create-view name field moves focus to the Back
  /// button (instead of popping the whole dialog). Arrow exits live on the
  /// TvTextField itself (onUp/DownArrow).
  KeyEventResult _handleCreateFieldBack(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
      _createCancelFocusNode.requestFocus();
      return KeyEventResult.handled;
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
    if (isActivateKey(event.logicalKey)) {
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
                  ? buildStremioTvCatalogCreateView(
                      context,
                      theme,
                      itemName: widget.item.name,
                      saving: _saving,
                      nameController: _nameController,
                      nameFocus: _nameFieldFocusNode,
                      confirmFocus: _createConfirmFocusNode,
                      cancelFocus: _createCancelFocusNode,
                      onFieldKey: _handleCreateFieldBack,
                      onButtonKey: _handleCreateButtonKey,
                      onCreate: _createCatalog,
                      onBack: _closeCreateView,
                    )
                  : _buildSelectionView(theme),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectionView(ThemeData theme) {
    final app = AppThemeScope.of(context);
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
              child: buildStremioTvCatalogActionTile(
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
              StremioTvFocusFrame(
                focusNode: _searchFocusNode,
                child: Focus(
                  canRequestFocus: false,
                  skipTraversal: true,
                  onKeyEvent: _handleSearchFieldBack,
                  child: TvTextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    enabled: !_saving,
                    textInputAction: TextInputAction.search,
                    // Same chrome the rest of Stremio TV's fields already
                    // pass: the DPAD cursor role feeds TvTextField.accent, and
                    // the keyboard panel keeps its own ground and ink.
                    accent: app.youtube.focus,
                    keyboardGround: app.youtube.keyboardPanel,
                    keyboardInk: app.core.tx,
                    keyboardInkOnAccent: app.inkOn(app.youtube.focus),
                    onUpArrow: () => _newChannelFocusNode.requestFocus(),
                    onDownArrow: () {
                      final filtered = _filteredCatalogIndices;
                      if (filtered.isNotEmpty) {
                        _catalogFocusNodes[filtered.first].requestFocus();
                      } else {
                        _cancelSelectionFocusNode.requestFocus();
                      }
                    },
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
                    final itemCount = catalog.itemCount;

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
                        child: buildStremioTvCatalogActionTile(
                          theme,
                          focusNode: focusNode,
                          icon: widget.item.type == 'series'
                              ? Icons.tv_rounded
                              : Icons.movie_rounded,
                          title: catalog.name,
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
}
