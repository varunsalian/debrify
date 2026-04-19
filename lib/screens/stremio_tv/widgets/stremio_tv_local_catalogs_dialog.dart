import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../../services/storage_service.dart';
import '../../../services/trakt/trakt_item_transformer.dart';
import '../../../services/trakt/trakt_service.dart';
import 'stremio_tv_repo_browser_dialog.dart';

class LocalCatalogExportPayload {
  final String name;
  final String json;

  const LocalCatalogExportPayload({required this.name, required this.json});
}

class LocalCatalogExporter {
  LocalCatalogExporter._();

  static Future<LocalCatalogExportPayload?> loadCatalog({
    required String catalogId,
    required String catalogType,
  }) async {
    final catalogs = await StorageService.getStremioTvLocalCatalogs();
    Map<String, dynamic>? catalog;
    for (final candidate in catalogs) {
      if (candidate['id'] == catalogId &&
          (candidate['type'] as String? ?? 'movie') == catalogType) {
        catalog = candidate;
        break;
      }
    }
    if (catalog == null) return null;

    final rawName = (catalog['name'] as String? ?? '').trim();
    final name = rawName.isEmpty ? 'local_catalog' : rawName;

    return LocalCatalogExportPayload(
      name: name,
      json: const JsonEncoder.withIndent('  ').convert(catalog),
    );
  }
}

// ─── Import helper ──────────────────────────────────────────────────────────

/// Shared validation and save logic for local catalog imports.
/// Supports both the native format and Trakt list JSON.
class LocalCatalogImporter {
  LocalCatalogImporter._();

  static const Set<String> _portableTraktSources = <String>{
    'trending',
    'popular',
    'anticipated',
    'liked',
  };

  /// Generate a unique catalog ID from the name.
  static String generateId(String name) {
    final sanitized = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final ts = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    return '${sanitized}_$ts';
  }

  static Map<String, dynamic> _portableImportMetadata(
    Map<String, dynamic> parsed,
  ) {
    final source = parsed['traktSource'] as String?;
    if (source == null || !_portableTraktSources.contains(source)) {
      return const <String, dynamic>{};
    }

    if (source == 'liked') {
      final slug = parsed['traktSlug'] as String?;
      final owner = parsed['traktOwner'] as String?;
      if (slug == null || slug.isEmpty || owner == null || owner.isEmpty) {
        return const <String, dynamic>{};
      }
      return <String, dynamic>{
        'traktSource': source,
        'traktSlug': slug,
        'traktOwner': owner,
      };
    }

    return <String, dynamic>{'traktSource': source};
  }

  /// Check if parsed JSON looks like a Trakt list export.
  /// Trakt lists are top-level arrays where items have nested movie/show objects.
  static bool isTrakt(dynamic parsed) {
    if (parsed is! List || parsed.isEmpty) return false;
    final first = parsed.first;
    if (first is! Map<String, dynamic>) return false;
    return first.containsKey('movie') || first.containsKey('show');
  }

  /// Transform a Trakt list array into the native catalog format.
  /// Returns the catalog map with 'name', 'type', and 'items'.
  static Map<String, dynamic> transformTrakt(List items, String catalogName) {
    final metas = TraktItemTransformer.transformList(items);

    int movieCount = 0;
    int seriesCount = 0;
    final transformed = <Map<String, dynamic>>[];

    for (final meta in metas) {
      if (meta.type == 'series') {
        seriesCount++;
      } else {
        movieCount++;
      }
      transformed.add({
        'id': meta.id,
        'name': meta.name,
        'type': meta.type,
        if (meta.year != null) 'year': int.tryParse(meta.year!) ?? meta.year,
        if (meta.description != null) 'overview': meta.description,
        if (meta.imdbRating != null) 'rating': meta.imdbRating,
        if (meta.poster != null) 'poster': meta.poster,
        if (meta.background != null) 'fanart': meta.background,
        if (meta.genres != null && meta.genres!.isNotEmpty)
          'genres': meta.genres,
      });
    }

    final catalogType = seriesCount > movieCount ? 'series' : 'movie';

    return {'name': catalogName, 'type': catalogType, 'items': transformed};
  }

  /// Validate JSON catalog content. Returns error message or null if valid.
  static String? validate(String content) {
    final dynamic parsed;
    try {
      parsed = jsonDecode(content);
    } catch (e) {
      return 'Invalid JSON: $e';
    }
    if (parsed is! Map<String, dynamic>) return 'Expected a JSON object';
    final name = parsed['name'] as String?;
    if (name == null || name.trim().isEmpty) return 'Missing "name" field';
    final items = parsed['items'] as List<dynamic>?;
    if (items == null || items.isEmpty) return '"items" is missing or empty';
    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      if (item is! Map<String, dynamic>) return 'Item $i: not an object';
      if ((item['id'] as String?)?.isEmpty ?? true) {
        return 'Item $i: missing "id"';
      }
      if ((item['name'] as String?)?.isEmpty ?? true) {
        return 'Item $i: missing "name"';
      }
    }
    return null;
  }

  /// Refresh a Trakt-sourced catalog by re-fetching its items.
  /// Returns error message or null on success.
  static Future<String?> refreshTraktCatalog(
    Map<String, dynamic> catalog,
  ) async {
    final source = catalog['traktSource'] as String?;
    final slug = catalog['traktSlug'] as String?;
    final owner = catalog['traktOwner'] as String?;
    if (source == null) return 'Not a Trakt catalog';

    final traktService = TraktService.instance;
    final List<dynamic> rawItems;

    // Direct sources (watchlist, trending, etc.)
    const directSources = [
      'watchlist',
      'history',
      'collection',
      'ratings',
      'trending',
      'popular',
      'anticipated',
      'recommendations',
    ];
    if (directSources.contains(source)) {
      final movies = await traktService.fetchList(source, 'movies');
      final shows = await traktService.fetchList(source, 'shows');
      rawItems = [...movies, ...shows];
    } else if (source == 'custom') {
      if (slug == null || slug.isEmpty) return 'Missing list slug';
      final movies = await traktService.fetchCustomListItems(slug, 'movies');
      final shows = await traktService.fetchCustomListItems(slug, 'shows');
      rawItems = [...movies, ...shows];
    } else if (source == 'liked' && owner != null && owner.isNotEmpty) {
      if (slug == null || slug.isEmpty) return 'Missing list slug';
      final movies = await traktService.fetchLikedListItems(
        owner,
        slug,
        'movies',
      );
      final shows = await traktService.fetchLikedListItems(
        owner,
        slug,
        'shows',
      );
      rawItems = [...movies, ...shows];
    } else {
      return 'Unknown Trakt source: $source';
    }

    final metas = TraktItemTransformer.transformList(rawItems);
    if (metas.isEmpty) return 'No items found in list';

    final catalogType = catalog['type'] as String? ?? 'movie';
    final items = <Map<String, dynamic>>[];
    for (final meta in metas) {
      // Filter by catalog type (movie catalogs only get movies, series only get series)
      if (catalogType == 'series' && meta.type != 'series') continue;
      if (catalogType == 'movie' && meta.type == 'series') continue;
      items.add({
        'id': meta.id,
        'name': meta.name,
        'type': meta.type,
        if (meta.year != null) 'year': int.tryParse(meta.year!) ?? meta.year,
        if (meta.description != null) 'overview': meta.description,
        if (meta.imdbRating != null) 'rating': meta.imdbRating,
        if (meta.poster != null) 'poster': meta.poster,
        if (meta.background != null) 'fanart': meta.background,
        if (meta.genres != null && meta.genres!.isNotEmpty)
          'genres': meta.genres,
      });
    }

    final updated = Map<String, dynamic>.from(catalog);
    updated['items'] = items;
    updated['addedAt'] = DateTime.now().toIso8601String();
    if (items.isEmpty) return 'No matching items after filtering by type';
    final ok = await StorageService.updateStremioTvLocalCatalog(updated);
    if (!ok) return 'Catalog not found — it may have been deleted';
    return null;
  }

  /// Validate and save JSON content as a local catalog.
  /// Pass [catalogName] for Trakt lists (which lack a root name).
  /// Returns error message or null on success.
  static Future<String?> import(String content, {String? catalogName}) async {
    // Detect and transform Trakt format before validation
    dynamic raw;
    try {
      raw = jsonDecode(content);
    } catch (e) {
      return 'Invalid JSON: $e';
    }

    if (isTrakt(raw)) {
      final name = catalogName?.trim() ?? '';
      if (name.isEmpty) {
        return 'Trakt list detected — please enter a catalog name';
      }
      final transformed = transformTrakt(raw as List, name);
      final allItems = transformed['items'] as List<Map<String, dynamic>>;
      if (allItems.isEmpty) {
        return 'No items with IMDB IDs found in Trakt list';
      }

      // Split mixed lists into separate movie and series catalogs
      final movies = allItems.where((i) => i['type'] != 'series').toList();
      final series = allItems.where((i) => i['type'] == 'series').toList();
      final existing = await StorageService.getStremioTvLocalCatalogs();

      if (movies.isNotEmpty && series.isNotEmpty) {
        // Mixed list — create two catalogs
        for (final entry in [
          (items: movies, type: 'movie', suffix: 'Movies'),
          (items: series, type: 'series', suffix: 'Series'),
        ]) {
          final catName = '$name — ${entry.suffix}';
          if (existing.any((c) => c['name'] == catName)) continue;
          await StorageService.addStremioTvLocalCatalog({
            'id': generateId(catName),
            'name': catName,
            'type': entry.type,
            'addedAt': DateTime.now().toIso8601String(),
            'items': entry.items,
          });
        }
        return null;
      }

      // Single-type list — use as-is
      content = jsonEncode(transformed);
    }

    final err = validate(content);
    if (err != null) return err;

    final parsed = jsonDecode(content) as Map<String, dynamic>;
    final name = (parsed['name'] as String).trim();

    final existing = await StorageService.getStremioTvLocalCatalogs();
    if (existing.any((c) => c['name'] == name)) {
      return 'Catalog "$name" already exists';
    }

    final catalog = <String, dynamic>{
      'id': generateId(name),
      'name': name,
      'type': parsed['type'] as String? ?? 'movie',
      'addedAt': DateTime.now().toIso8601String(),
      'items': parsed['items'],
      ..._portableImportMetadata(parsed),
    };

    await StorageService.addStremioTvLocalCatalog(catalog);
    return null;
  }
}

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
    final catalogs = await StorageService.getStremioTvLocalCatalogs();
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
        if (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.select) {
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
      await StorageService.removeStremioTvLocalCatalog(widget.catalogId);
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
    final saved = await StorageService.updateStremioTvLocalCatalog(
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
    final posterUrl = item['poster'] as String?;
    final width = compact ? 52.0 : 60.0;
    final height = compact ? 74.0 : 86.0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: width,
        height: height,
        color: Colors.white.withValues(alpha: 0.05),
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
    return Center(
      child: Icon(
        widget.catalogType == 'series' ? Icons.tv_rounded : Icons.movie_rounded,
        size: compact ? 22 : 26,
        color: Colors.white.withValues(alpha: 0.25),
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
        borderRadius: BorderRadius.circular(16),
        color: Colors.white.withValues(alpha: 0.04),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
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

// ─── Manage dialog ──────────────────────────────────────────────────────────

/// Dialog for viewing and deleting local catalogs (manage only).
class StremioTvLocalCatalogsDialog extends StatefulWidget {
  const StremioTvLocalCatalogsDialog({super.key});

  /// Show the manage dialog. Returns `true` if catalogs were changed.
  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) => const Center(child: StremioTvLocalCatalogsDialog()),
    );
  }

  /// Pick and import a JSON file. Returns true if imported.
  static Future<bool> importFromFile(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return false;

      final bytes = result.files.first.bytes;
      if (bytes == null) {
        if (context.mounted) {
          _showSnackBar(context, 'Could not read file', true);
        }
        return false;
      }

      final content = utf8.decode(bytes);
      // Use filename (without extension) as catalog name for Trakt lists
      final fileName = result.files.first.name.replaceAll(
        RegExp(r'\.json$', caseSensitive: false),
        '',
      );
      final err = await LocalCatalogImporter.import(
        content,
        catalogName: fileName,
      );
      if (err != null) {
        if (context.mounted) _showSnackBar(context, err, true);
        return false;
      }
      if (context.mounted) _showSnackBar(context, 'Catalog imported', false);
      return true;
    } catch (e) {
      if (context.mounted) _showSnackBar(context, 'Failed: $e', true);
      return false;
    }
  }

  /// Show URL input dialog. Returns true if imported.
  static Future<bool> importFromUrl(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => const _ImportUrlDialog(),
    );
    return result == true;
  }

  /// Show JSON paste dialog. Returns true if imported.
  static Future<bool> importFromJson(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => const _ImportJsonDialog(),
    );
    return result == true;
  }

  /// Open repository browser. Returns true if imported.
  static Future<bool> importFromRepo(BuildContext context) async {
    final result = await StremioTvRepoBrowserDialog.show(context);
    return result == true;
  }

  /// Show Trakt list picker dialog. Returns true if imported.
  static Future<bool> importFromTrakt(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => const _ImportTraktDialog(),
    );
    return result == true;
  }

  static void _showSnackBar(
    BuildContext context,
    String message,
    bool isError,
  ) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : null,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: isError ? 4 : 2),
      ),
    );
  }

  @override
  State<StremioTvLocalCatalogsDialog> createState() =>
      _StremioTvLocalCatalogsDialogState();
}

class _StremioTvLocalCatalogsDialogState
    extends State<StremioTvLocalCatalogsDialog> {
  List<Map<String, dynamic>> _catalogs = [];
  bool _loadingCatalogs = true;
  bool _changed = false;
  String? _refreshingCatalogId;

  final _closeFocusNode = FocusNode(debugLabel: 'close');
  final List<FocusNode> _deleteFocusNodes = [];
  final _listScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadCatalogs();
  }

  @override
  void dispose() {
    _listScrollController.dispose();
    _closeFocusNode.dispose();
    for (final n in _deleteFocusNodes) {
      n.dispose();
    }
    super.dispose();
  }

  Future<void> _loadCatalogs() async {
    final catalogs = await StorageService.getStremioTvLocalCatalogs();
    if (!mounted) return;
    _syncDeleteFocusNodes(catalogs.length);
    setState(() {
      _catalogs = catalogs;
      _loadingCatalogs = false;
    });
    _rebuildNavigation();
  }

  void _syncDeleteFocusNodes(int count) {
    while (_deleteFocusNodes.length < count) {
      _deleteFocusNodes.add(
        FocusNode(debugLabel: 'del${_deleteFocusNodes.length}'),
      );
    }
    while (_deleteFocusNodes.length > count) {
      _deleteFocusNodes.removeLast().dispose();
    }
  }

  void _rebuildNavigation() {
    final order = <FocusNode>[_closeFocusNode, ..._deleteFocusNodes];

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
        if (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.select) {
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
    } else {
      final idx = _deleteFocusNodes.indexOf(node);
      if (idx >= 0 && idx < _catalogs.length) {
        _deleteLocalCatalog(_catalogs[idx]);
      }
    }
  }

  void _scrollToNode(FocusNode node) {
    final idx = _deleteFocusNodes.indexOf(node);
    if (idx < 0 || !_listScrollController.hasClients) return;
    const itemHeight = 56.0;
    final targetOffset = idx * itemHeight;
    _listScrollController.animateTo(
      targetOffset.clamp(0.0, _listScrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  Future<void> _refreshTraktCatalog(Map<String, dynamic> catalog) async {
    final id = catalog['id'] as String? ?? '';
    final name = catalog['name'] as String? ?? 'Unknown';
    setState(() => _refreshingCatalogId = id);
    final err = await LocalCatalogImporter.refreshTraktCatalog(catalog);
    if (!mounted) return;
    setState(() => _refreshingCatalogId = null);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Refresh failed: $err'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } else {
      _changed = true;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('"$name" refreshed')));
      await _loadCatalogs();
    }
  }

  Future<void> _deleteLocalCatalog(Map<String, dynamic> catalog) async {
    final name = catalog['name'] as String? ?? 'Unknown';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Catalog'),
        content: Text('Remove "$name" and all its items?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final id = catalog['id'] as String? ?? '';
    await StorageService.removeStremioTvLocalCatalog(id);
    _changed = true;
    if (!mounted) return;
    await _loadCatalogs();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenHeight = MediaQuery.of(context).size.height;

    return Material(
      type: MaterialType.transparency,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 500,
          maxHeight: screenHeight * 0.7,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header ──
              Row(
                children: [
                  Icon(
                    Icons.playlist_add_rounded,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Local Catalogs',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    focusNode: _closeFocusNode,
                    onPressed: () => Navigator.of(context).pop(_changed),
                    icon: const Icon(Icons.close),
                    tooltip: 'Close',
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // ── Catalog list ──
              if (_loadingCatalogs)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else if (_catalogs.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'No local catalogs yet.\nUse the menu to import catalogs.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    controller: _listScrollController,
                    shrinkWrap: true,
                    itemCount: _catalogs.length,
                    itemBuilder: (context, index) {
                      final catalog = _catalogs[index];
                      final name = catalog['name'] as String? ?? 'Unknown';
                      final type = catalog['type'] as String? ?? 'movie';
                      final items = catalog['items'] as List<dynamic>? ?? [];
                      final deleteFocus = index < _deleteFocusNodes.length
                          ? _deleteFocusNodes[index]
                          : null;
                      final isTrakt = catalog['traktSource'] != null;

                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          type == 'series'
                              ? Icons.tv_rounded
                              : Icons.movie_rounded,
                          color: theme.colorScheme.primary,
                          size: 20,
                        ),
                        title: Text(name, style: theme.textTheme.bodyMedium),
                        subtitle: Text(
                          '${items.length} items${isTrakt ? ' · Trakt' : ''}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isTrakt)
                              _refreshingCatalogId == catalog['id']
                                  ? const Padding(
                                      padding: EdgeInsets.all(12),
                                      child: SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    )
                                  : IconButton(
                                      icon: Icon(
                                        Icons.refresh_rounded,
                                        color: theme.colorScheme.primary,
                                        size: 20,
                                      ),
                                      onPressed: _refreshingCatalogId != null
                                          ? null
                                          : () => _refreshTraktCatalog(catalog),
                                      tooltip: 'Refresh from Trakt',
                                    ),
                            IconButton(
                              focusNode: deleteFocus,
                              icon: Icon(
                                Icons.delete_outline,
                                color: theme.colorScheme.error,
                                size: 20,
                              ),
                              onPressed: () => _deleteLocalCatalog(catalog),
                              tooltip: 'Delete catalog',
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Import from URL dialog ─────────────────────────────────────────────────

class _ImportUrlDialog extends StatefulWidget {
  const _ImportUrlDialog();

  @override
  State<_ImportUrlDialog> createState() => _ImportUrlDialogState();
}

class _ImportUrlDialogState extends State<_ImportUrlDialog> {
  final _urlController = TextEditingController();
  final _nameController = TextEditingController();
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _urlController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() => _error = 'Enter a URL');
      return;
    }

    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      setState(() => _error = 'Invalid URL');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final resp = await http.get(uri).timeout(const Duration(seconds: 15));
      if (!mounted) return;

      if (resp.statusCode != 200) {
        setState(() {
          _error = 'HTTP ${resp.statusCode}';
          _loading = false;
        });
        return;
      }

      final err = await LocalCatalogImporter.import(
        resp.body,
        catalogName: _nameController.text,
      );
      if (!mounted) return;

      if (err != null) {
        setState(() {
          _error = err;
          _loading = false;
        });
        return;
      }

      Navigator.of(context).pop(true);
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _error = 'Request timed out';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Import from URL'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              hintText: 'Catalog name (required for Trakt lists)',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _urlController,
            decoration: InputDecoration(
              hintText: 'https://example.com/catalog.json',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              errorText: _error,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
            autofocus: true,
            onSubmitted: (_) {
              if (!_loading) _import();
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _loading ? null : _import,
          child: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Import'),
        ),
      ],
    );
  }
}

// ─── Paste JSON dialog ──────────────────────────────────────────────────────

class _ImportJsonDialog extends StatefulWidget {
  const _ImportJsonDialog();

  @override
  State<_ImportJsonDialog> createState() => _ImportJsonDialogState();
}

class _ImportJsonDialogState extends State<_ImportJsonDialog> {
  final _jsonController = TextEditingController();
  final _nameController = TextEditingController();
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _jsonController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    final content = _jsonController.text.trim();
    if (content.isEmpty) {
      setState(() => _error = 'Paste JSON content');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final err = await LocalCatalogImporter.import(
      content,
      catalogName: _nameController.text,
    );
    if (!mounted) return;

    if (err != null) {
      setState(() {
        _error = err;
        _loading = false;
      });
      return;
    }

    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Paste JSON'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              hintText: 'Catalog name (required for Trakt lists)',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _jsonController,
            maxLines: 6,
            decoration: InputDecoration(
              hintText:
                  '{"name": "My Catalog", "items": [...]}\nor paste Trakt list JSON',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              errorText: _error,
              contentPadding: const EdgeInsets.all(12),
            ),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            autofocus: true,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _loading ? null : _import,
          child: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Import'),
        ),
      ],
    );
  }
}

// ─── Import from Trakt dialog ────────────────────────────────────────────────

enum _TraktListSource {
  watchlist,
  history,
  collection,
  ratings,
  trending,
  popular,
  anticipated,
  recommendations,
  customLists,
  likedLists,
}

extension _TraktListSourceExt on _TraktListSource {
  String get label {
    switch (this) {
      case _TraktListSource.watchlist:
        return 'Watchlist';
      case _TraktListSource.history:
        return 'History';
      case _TraktListSource.collection:
        return 'Collection';
      case _TraktListSource.ratings:
        return 'Ratings';
      case _TraktListSource.trending:
        return 'Trending';
      case _TraktListSource.popular:
        return 'Popular';
      case _TraktListSource.anticipated:
        return 'Anticipated';
      case _TraktListSource.recommendations:
        return 'Recommendations';
      case _TraktListSource.customLists:
        return 'Custom Lists';
      case _TraktListSource.likedLists:
        return 'Liked Lists';
    }
  }

  /// Whether this source requires picking a specific list before importing.
  bool get needsListPicker =>
      this == _TraktListSource.customLists ||
      this == _TraktListSource.likedLists;

  /// The API list type value for direct-fetch sources.
  String get apiValue {
    switch (this) {
      case _TraktListSource.watchlist:
        return 'watchlist';
      case _TraktListSource.history:
        return 'history';
      case _TraktListSource.collection:
        return 'collection';
      case _TraktListSource.ratings:
        return 'ratings';
      case _TraktListSource.trending:
        return 'trending';
      case _TraktListSource.popular:
        return 'popular';
      case _TraktListSource.anticipated:
        return 'anticipated';
      case _TraktListSource.recommendations:
        return 'recommendations';
      default:
        return '';
    }
  }
}

class _ImportTraktDialog extends StatefulWidget {
  const _ImportTraktDialog();

  @override
  State<_ImportTraktDialog> createState() => _ImportTraktDialogState();
}

class _ImportTraktDialogState extends State<_ImportTraktDialog> {
  final TraktService _traktService = TraktService.instance;
  _TraktListSource _source = _TraktListSource.watchlist;
  List<Map<String, dynamic>> _lists = [];
  bool _loading = false;
  bool _importing = false;
  String? _error;
  bool _authenticated = false;
  bool _authChecked = false;

  @override
  void initState() {
    super.initState();
    _checkAuthAndLoad();
  }

  Future<void> _checkAuthAndLoad() async {
    final auth = await _traktService.isAuthenticated();
    if (!mounted) return;
    setState(() {
      _authenticated = auth;
      _authChecked = true;
    });
    if (auth && _source.needsListPicker) _fetchLists();
  }

  Future<void> _onSourceChanged(_TraktListSource source) {
    setState(() {
      _source = source;
      _error = null;
      _lists = [];
    });
    if (source.needsListPicker) {
      return _fetchLists();
    }
    return Future.value();
  }

  Future<void> _fetchLists() async {
    setState(() {
      _loading = true;
      _error = null;
      _lists = [];
    });

    try {
      final List<Map<String, dynamic>> lists;
      if (_source == _TraktListSource.customLists) {
        lists = await _traktService.fetchCustomLists();
      } else {
        lists = await _traktService.fetchLikedLists();
      }
      if (!mounted) return;
      setState(() {
        _lists = lists;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load lists: $e';
        _loading = false;
      });
    }
  }

  /// Import a direct list type (watchlist, trending, etc.) — no list picker needed.
  Future<void> _importDirect() async {
    final name = 'Trakt ${_source.label}';

    setState(() {
      _importing = true;
      _error = null;
    });

    try {
      // Check for duplicates
      final existing = await StorageService.getStremioTvLocalCatalogs();
      if (existing.any(
        (c) =>
            c['name'] == name ||
            c['name'] == '$name — Movies' ||
            c['name'] == '$name — Series',
      )) {
        setState(() {
          _error = '"$name" already imported';
          _importing = false;
        });
        return;
      }

      final movies = await _traktService.fetchList(_source.apiValue, 'movies');
      final shows = await _traktService.fetchList(_source.apiValue, 'shows');
      final rawItems = [...movies, ...shows];

      if (!mounted) return;
      await _saveAsCatalog(
        rawItems,
        name,
        traktMeta: {'traktSource': _source.apiValue},
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to import: $e';
        _importing = false;
      });
    }
  }

  /// Import a specific custom/liked list.
  Future<void> _importList(Map<String, dynamic> list) async {
    final name = list['name'] as String? ?? 'Unknown';
    final slug = list['ids']?['slug'] as String? ?? '';
    if (slug.isEmpty) return;

    setState(() {
      _importing = true;
      _error = null;
    });

    try {
      // Check for duplicates
      final existing = await StorageService.getStremioTvLocalCatalogs();
      if (existing.any(
        (c) =>
            c['name'] == name ||
            c['name'] == '$name — Movies' ||
            c['name'] == '$name — Series',
      )) {
        setState(() {
          _error = '"$name" already imported';
          _importing = false;
        });
        return;
      }

      final List<dynamic> rawItems;
      if (_source == _TraktListSource.customLists) {
        final movies = await _traktService.fetchCustomListItems(slug, 'movies');
        final shows = await _traktService.fetchCustomListItems(slug, 'shows');
        rawItems = [...movies, ...shows];
      } else {
        final owner =
            (list['user'] as Map<String, dynamic>?)?['username'] as String? ??
            '';
        if (owner.isEmpty) {
          setState(() {
            _error = 'Missing list owner';
            _importing = false;
          });
          return;
        }
        final movies = await _traktService.fetchLikedListItems(
          owner,
          slug,
          'movies',
        );
        final shows = await _traktService.fetchLikedListItems(
          owner,
          slug,
          'shows',
        );
        rawItems = [...movies, ...shows];
      }

      if (!mounted) return;

      final owner =
          (list['user'] as Map<String, dynamic>?)?['username'] as String?;
      await _saveAsCatalog(
        rawItems,
        name,
        traktMeta: {
          'traktSource': _source == _TraktListSource.customLists
              ? 'custom'
              : 'liked',
          'traktSlug': slug,
          if (owner != null) 'traktOwner': owner,
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to import: $e';
        _importing = false;
      });
    }
  }

  /// Shared logic: transform raw items, split by type, save as catalog(s).
  Future<void> _saveAsCatalog(
    List<dynamic> rawItems,
    String name, {
    required Map<String, dynamic> traktMeta,
  }) async {
    if (rawItems.isEmpty) {
      setState(() {
        _error = '"$name" is empty';
        _importing = false;
      });
      return;
    }

    final metas = TraktItemTransformer.transformList(rawItems);
    if (metas.isEmpty) {
      setState(() {
        _error = 'No items with IMDB IDs found';
        _importing = false;
      });
      return;
    }

    final catalogItems = <Map<String, dynamic>>[];
    for (final meta in metas) {
      catalogItems.add({
        'id': meta.id,
        'name': meta.name,
        'type': meta.type,
        if (meta.year != null) 'year': int.tryParse(meta.year!) ?? meta.year,
        if (meta.description != null) 'overview': meta.description,
        if (meta.imdbRating != null) 'rating': meta.imdbRating,
        if (meta.poster != null) 'poster': meta.poster,
        if (meta.background != null) 'fanart': meta.background,
        if (meta.genres != null && meta.genres!.isNotEmpty)
          'genres': meta.genres,
      });
    }

    final movies = catalogItems.where((i) => i['type'] != 'series').toList();
    final series = catalogItems.where((i) => i['type'] == 'series').toList();

    if (movies.isNotEmpty && series.isNotEmpty) {
      for (final entry in [
        (items: movies, type: 'movie', suffix: 'Movies'),
        (items: series, type: 'series', suffix: 'Series'),
      ]) {
        final catName = '$name — ${entry.suffix}';
        await StorageService.addStremioTvLocalCatalog({
          'id': LocalCatalogImporter.generateId(catName),
          'name': catName,
          'type': entry.type,
          'addedAt': DateTime.now().toIso8601String(),
          'items': entry.items,
          ...traktMeta,
        });
      }
    } else {
      final catalogType = series.length > movies.length ? 'series' : 'movie';
      await StorageService.addStremioTvLocalCatalog({
        'id': LocalCatalogImporter.generateId(name),
        'name': name,
        'type': catalogType,
        'addedAt': DateTime.now().toIso8601String(),
        'items': catalogItems,
        ...traktMeta,
      });
    }

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!_authChecked) {
      return const AlertDialog(
        content: Center(heightFactor: 1, child: CircularProgressIndicator()),
      );
    }

    if (!_authenticated) {
      return AlertDialog(
        title: const Text('Import from Trakt'),
        content: const Text('Sign in to Trakt first in Settings.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      );
    }

    return AlertDialog(
      title: const Text('Import from Trakt'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Source dropdown
            DropdownButtonFormField<_TraktListSource>(
              isExpanded: true,
              value: _source,
              decoration: InputDecoration(
                labelText: 'List Type',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              items: _TraktListSource.values
                  .map((s) => DropdownMenuItem(value: s, child: Text(s.label)))
                  .toList(),
              onChanged: (value) {
                if (value != null) _onSourceChanged(value);
              },
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: theme.colorScheme.error,
                    fontSize: 13,
                  ),
                ),
              ),
            // Direct import sources — just show an import button
            if (!_source.needsListPicker) ...[
              if (_importing)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                FilledButton.icon(
                  onPressed: _importDirect,
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: Text('Import ${_source.label}'),
                ),
            ],
            // List picker sources — show list of lists
            if (_source.needsListPicker) ...[
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_lists.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    _source == _TraktListSource.customLists
                        ? 'No custom lists found.'
                        : 'No liked lists found.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _lists.length,
                    itemBuilder: (context, index) {
                      final list = _lists[index];
                      final name = list['name'] as String? ?? 'Unknown';
                      final itemCount = list['item_count'] as int?;
                      final owner =
                          (list['user'] as Map<String, dynamic>?)?['username']
                              as String?;

                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          Icons.playlist_play_rounded,
                          color: theme.colorScheme.primary,
                          size: 20,
                        ),
                        title: Text(name, style: theme.textTheme.bodyMedium),
                        subtitle: Text(
                          [
                            if (owner != null &&
                                _source == _TraktListSource.likedLists)
                              'by $owner',
                            if (itemCount != null) '$itemCount items',
                          ].join(' · '),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        trailing: _importing
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.add_rounded, size: 20),
                        onTap: _importing ? null : () => _importList(list),
                      );
                    },
                  ),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
