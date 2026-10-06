import 'dart:convert';

import 'package:debrify/features/stremio_tv_catalogs/data/local_catalog_importer.dart';
import 'package:debrify/features/stremio_tv_catalogs/presentation/legacy_stremio_tv_catalogs/local_catalog_json_import_dialog.dart';
import 'package:debrify/features/stremio_tv_catalogs/presentation/legacy_stremio_tv_catalogs/local_catalog_mdblist_import_dialog.dart';
import 'package:debrify/features/stremio_tv_catalogs/presentation/legacy_stremio_tv_catalogs/local_catalog_trakt_import_dialog.dart';
import 'package:debrify/features/stremio_tv_catalogs/presentation/legacy_stremio_tv_catalogs/local_catalog_url_import_dialog.dart';
import 'package:debrify/screens/stremio_tv/widgets/stremio_tv_repo_browser_dialog.dart';
import 'package:debrify/services/storage/stremio_catalog_storage.dart';
import 'package:debrify/utils/tv_keys.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
      // FileType.any instead of custom: Android's MIME mapping for `json` is
      // unreliable and throws PlatformException("Unsupported filter"). The JSON
      // content is validated by LocalCatalogImporter.import below.
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return false;

      // Reject an implausibly large pick before buffering it (FileType.any +
      // withData would otherwise load the whole file into RAM).
      if (result.files.first.size > 20 * 1024 * 1024) {
        if (context.mounted) {
          _showSnackBar(
            context,
            'That file is too large to be a catalog',
            true,
          );
        }
        return false;
      }

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
      builder: (ctx) => const LcUrlDialog(),
    );
    return result == true;
  }

  /// Show JSON paste dialog. Returns true if imported.
  static Future<bool> importFromJson(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => const LcJsonDialog(),
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
      builder: (ctx) => const LcTraktDialog(),
    );
    return result == true;
  }

  /// Show MDBList list picker dialog. Returns true if imported.
  static Future<bool> importFromMdblist(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => const LcMdblistDialog(),
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
    final catalogs = await StremioCatalogStorage.getStremioTvLocalCatalogs();
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

  Future<void> _refreshMdblistCatalog(Map<String, dynamic> catalog) async {
    final id = catalog['id'] as String? ?? '';
    final name = catalog['name'] as String? ?? 'Unknown';
    setState(() => _refreshingCatalogId = id);
    final err = await LocalCatalogImporter.refreshMdblistCatalog(catalog);
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
    await StremioCatalogStorage.removeStremioTvLocalCatalog(id);
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
                      final isMdblist = catalog['mdblistListId'] != null;

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
                          '${items.length} items'
                          '${isTrakt
                              ? ' · Trakt'
                              : isMdblist
                              ? ' · MDBList'
                              : ''}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isTrakt || isMdblist)
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
                                          : () => isMdblist
                                                ? _refreshMdblistCatalog(
                                                    catalog,
                                                  )
                                                : _refreshTraktCatalog(catalog),
                                      tooltip: isMdblist
                                          ? 'Refresh from MDBList'
                                          : 'Refresh from Trakt',
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
