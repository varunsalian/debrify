import 'package:debrify/services/storage/stremio_catalog_storage.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/tv_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ─── Edit dialog ────────────────────────────────────────────────────────────

/// Dialog for reviewing a local catalog's items and removing entries.
class StremioTvLocalCatalogEditorDialog extends StatefulWidget {
  final String catalogId;
  final String catalogType;

  const StremioTvLocalCatalogEditorDialog({
    super.key,
    required this.catalogId,
    required this.catalogType,
  });

  /// Show the editor. Returns `true` if the catalog contents changed.
  static Future<bool?> show(
    BuildContext context, {
    required String catalogId,
    required String catalogType,
  }) {
    final editorKey = GlobalKey<_StremioTvLocalCatalogEditorDialogState>();
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () =>
            Navigator.of(context).pop(editorKey.currentState?._changed),
        child: Center(
          child: GestureDetector(
            onTap: () {},
            child: StremioTvLocalCatalogEditorDialog(
              key: editorKey,
              catalogId: catalogId,
              catalogType: catalogType,
            ),
          ),
        ),
      ),
    );
  }

  @override
  State<StremioTvLocalCatalogEditorDialog> createState() =>
      _StremioTvLocalCatalogEditorDialogState();
}

class _StremioTvLocalCatalogEditorDialogState
    extends State<StremioTvLocalCatalogEditorDialog> {
  Map<String, dynamic>? _catalog;
  bool _loading = true;
  bool _changed = false;

  final _closeFocusNode = FocusNode(debugLabel: 'localCatalogEditorClose');
  final List<FocusNode> _removeFocusNodes = [];
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  @override
  void dispose() {
    _closeFocusNode.dispose();
    _scrollController.dispose();
    for (final node in _removeFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _loadCatalog() async {
    final catalogs = await StremioCatalogStorage.getStremioTvLocalCatalogs();
    final match = catalogs.firstWhere(
      (candidate) =>
          candidate['id'] == widget.catalogId &&
          (candidate['type'] as String? ?? 'movie') == widget.catalogType,
      orElse: () => <String, dynamic>{},
    );

    if (!mounted) return;

    if (match.isEmpty) {
      _syncRemoveFocusNodes(0);
      setState(() {
        _catalog = null;
        _loading = false;
      });
      _requestInitialFocus();
      return;
    }

    final catalog = _normalizeCatalog(match);
    final items = _itemsFromCatalog(catalog);
    _syncRemoveFocusNodes(items.length);
    setState(() {
      _catalog = catalog;
      _loading = false;
    });
    _rebuildNavigation();
    _requestInitialFocus();
  }

  void _requestInitialFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = _closeFocusNode;
      if (!target.hasFocus) {
        target.requestFocus();
      }
      _scrollToNode(target);
    });
  }

  Map<String, dynamic> _normalizeCatalog(Map<String, dynamic> catalog) {
    final normalized = Map<String, dynamic>.from(catalog);
    normalized['items'] = _itemsFromCatalog(catalog);
    return normalized;
  }

  List<Map<String, dynamic>> _itemsFromCatalog(Map<String, dynamic> catalog) {
    final rawItems = catalog['items'] as List<dynamic>? ?? const [];
    return rawItems
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  void _syncRemoveFocusNodes(int count) {
    while (_removeFocusNodes.length < count) {
      _removeFocusNodes.add(
        FocusNode(
          debugLabel: 'localCatalogEditorRemove${_removeFocusNodes.length}',
        ),
      );
    }
    while (_removeFocusNodes.length > count) {
      _removeFocusNodes.removeLast().dispose();
    }
  }

  void _rebuildNavigation() {
    final order = <FocusNode>[_closeFocusNode, ..._removeFocusNodes];

    for (int i = 0; i < order.length; i++) {
      final node = order[i];
      final prev = i > 0 ? order[i - 1] : null;
      final next = i < order.length - 1 ? order[i + 1] : null;

      node.onKeyEvent = (n, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;

        if (key == LogicalKeyboardKey.arrowUp && prev != null) {
          prev.requestFocus();
          _scrollToNode(prev);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowDown && next != null) {
          next.requestFocus();
          _scrollToNode(next);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.escape ||
            key == LogicalKeyboardKey.goBack) {
          Navigator.of(context).pop(_changed);
          return KeyEventResult.handled;
        }
        if (isActivateKey(key)) {
          _handleActivate(node);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      };
    }
  }

  void _handleActivate(FocusNode node) {
    if (node == _closeFocusNode) {
      Navigator.of(context).pop(_changed);
      return;
    }

    final index = _removeFocusNodes.indexOf(node);
    final catalog = _catalog;
    if (catalog == null) return;
    final items = _itemsFromCatalog(catalog);
    if (index >= 0 && index < items.length) {
      _removeItem(index, items[index]);
    }
  }

  void _scrollToNode(FocusNode node) {
    final targetContext = node.context;
    if (targetContext == null) return;

    Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
    );
  }

  Future<void> _removeItem(int index, Map<String, dynamic> item) async {
    final itemName = item['name'] as String? ?? 'Unknown item';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Item'),
        content: Text('Remove "$itemName" from this local channel?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _catalog == null) return;

    final updatedCatalog = Map<String, dynamic>.from(_catalog!);
    final items = _itemsFromCatalog(updatedCatalog);
    if (index < 0 || index >= items.length) return;

    items.removeAt(index);
    if (items.isEmpty) {
      await StremioCatalogStorage.removeStremioTvLocalCatalog(widget.catalogId);
      _changed = true;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Channel removed because it no longer has any items'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop(true);
      return;
    }

    updatedCatalog['items'] = items;
    final saved = await StremioCatalogStorage.updateStremioTvLocalCatalog(
      updatedCatalog,
    );
    if (!mounted) return;

    if (!saved) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Local catalog could not be updated'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    _changed = true;
    _syncRemoveFocusNodes(items.length);
    setState(() {
      _catalog = updatedCatalog;
    });
    _rebuildNavigation();

    final nextIndex = index < items.length ? index : items.length - 1;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (nextIndex >= 0 && nextIndex < _removeFocusNodes.length) {
        _removeFocusNodes[nextIndex].requestFocus();
        _scrollToNode(_removeFocusNodes[nextIndex]);
      } else {
        _closeFocusNode.requestFocus();
      }
    });
  }

  Widget _buildPoster(Map<String, dynamic> item, bool compact) {
    final app = AppThemeScope.of(context);
    final posterUrl = item['poster'] as String?;
    final width = compact ? 52.0 : 60.0;
    final height = compact ? 74.0 : 86.0;

    return ClipRRect(
      borderRadius: app.shape.brImg(10),
      child: Container(
        width: width,
        height: height,
        color: app.core.tx.withValues(alpha: 0.05),
        child: posterUrl != null && posterUrl.isNotEmpty
            ? Image.network(
                posterUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _buildPosterFallback(compact),
              )
            : _buildPosterFallback(compact),
      ),
    );
  }

  Widget _buildPosterFallback(bool compact) {
    final app = AppThemeScope.of(context);
    return Center(
      child: Icon(
        widget.catalogType == 'series' ? Icons.tv_rounded : Icons.movie_rounded,
        size: compact ? 22 : 26,
        color: app.core.tx.withValues(alpha: 0.25),
      ),
    );
  }

  Widget _buildItemCard(
    BuildContext context,
    Map<String, dynamic> item,
    int index,
    bool compact,
  ) {
    final theme = Theme.of(context);
    final app = AppThemeScope.of(context);
    final itemName = item['name'] as String? ?? 'Unknown item';
    final yearValue = item['year'];
    final year = yearValue?.toString();
    final itemType = item['type'] as String? ?? widget.catalogType;
    final overview = (item['overview'] as String? ?? '').trim();
    final genres = (item['genres'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toList();
    final removeFocusNode = index < _removeFocusNodes.length
        ? _removeFocusNodes[index]
        : null;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: app.shape.br(16),
        color: app.stremioTv.surfaceFill,
        border: Border.all(color: app.core.tx.withValues(alpha: 0.08)),
      ),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildPoster(item, true),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildItemText(
                        theme,
                        itemName,
                        year,
                        itemType,
                        overview,
                        genres,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    focusNode: removeFocusNode,
                    onPressed: () => _removeItem(index, item),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('Remove'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                      side: BorderSide(color: theme.colorScheme.error),
                    ),
                  ),
                ),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPoster(item, false),
                const SizedBox(width: 14),
                Expanded(
                  child: _buildItemText(
                    theme,
                    itemName,
                    year,
                    itemType,
                    overview,
                    genres,
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  focusNode: removeFocusNode,
                  onPressed: () => _removeItem(index, item),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('Remove'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                    side: BorderSide(color: theme.colorScheme.error),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildItemText(
    ThemeData theme,
    String itemName,
    String? year,
    String itemType,
    String overview,
    List<String> genres,
  ) {
    final meta = <String>[
      if (year != null && year.isNotEmpty) year,
      itemType == 'series' ? 'Series' : 'Movie',
      if (genres.isNotEmpty) genres.take(2).join(' • '),
    ].where((value) => value.trim().isNotEmpty).join('  •  ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          itemName,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (meta.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            meta,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        if (overview.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            overview,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final dialogWidth = (media.size.width - 24).clamp(280.0, 920.0).toDouble();
    final dialogHeight = (media.size.height * 0.82)
        .clamp(320.0, 760.0)
        .toDouble();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          Navigator.of(context).pop(_changed);
        }
      },
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          width: dialogWidth,
          constraints: BoxConstraints(maxHeight: dialogHeight),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: _loading
                ? const Center(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : _catalog == null
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.edit_note_rounded,
                            size: 22,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Edit Local Channel',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            focusNode: _closeFocusNode,
                            onPressed: () =>
                                Navigator.of(context).pop(_changed),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'This local channel could not be found. It may have been deleted already.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final catalog = _catalog!;
                      final items = _itemsFromCatalog(catalog);
                      final compact = constraints.maxWidth < 700;
                      final catalogName =
                          catalog['name'] as String? ?? 'Local channel';
                      final catalogType =
                          catalog['type'] as String? ?? widget.catalogType;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.edit_note_rounded,
                                size: 22,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Edit Local Channel',
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '$catalogName • ${items.length} items • ${catalogType == 'series' ? 'Series' : 'Movies'}',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                focusNode: _closeFocusNode,
                                onPressed: () =>
                                    Navigator.of(context).pop(_changed),
                                icon: const Icon(Icons.close),
                                tooltip: 'Close',
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Review the titles in this local channel and remove any you no longer want in rotation.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Flexible(
                            child: Scrollbar(
                              controller: _scrollController,
                              thumbVisibility: items.length > 5,
                              child: ListView.separated(
                                controller: _scrollController,
                                itemCount: items.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 10),
                                itemBuilder: (context, index) => _buildItemCard(
                                  context,
                                  items[index],
                                  index,
                                  compact,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }
}
