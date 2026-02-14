import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../../services/storage_service.dart';
import 'stremio_tv_repo_browser_dialog.dart';

// ─── Import helper ──────────────────────────────────────────────────────────

/// Shared validation and save logic for local catalog imports.
class LocalCatalogImporter {
  LocalCatalogImporter._();

  /// Generate a unique catalog ID from the name.
  static String generateId(String name) {
    final sanitized = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final ts = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    return '${sanitized}_$ts';
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

  /// Validate and save JSON content as a local catalog.
  /// Returns error message or null on success.
  static Future<String?> import(String content) async {
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
    };

    await StorageService.addStremioTvLocalCatalog(catalog);
    return null;
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
      builder: (context) => const Center(
        child: StremioTvLocalCatalogsDialog(),
      ),
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
        if (context.mounted) _showSnackBar(context, 'Could not read file', true);
        return false;
      }

      final content = utf8.decode(bytes);
      final err = await LocalCatalogImporter.import(content);
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

  static void _showSnackBar(BuildContext context, String message, bool isError) {
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
      _deleteFocusNodes
          .add(FocusNode(debugLabel: 'del${_deleteFocusNodes.length}'));
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
                      final name =
                          catalog['name'] as String? ?? 'Unknown';
                      final type =
                          catalog['type'] as String? ?? 'movie';
                      final items =
                          catalog['items'] as List<dynamic>? ?? [];
                      final deleteFocus =
                          index < _deleteFocusNodes.length
                              ? _deleteFocusNodes[index]
                              : null;

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
                        title: Text(
                          name,
                          style: theme.textTheme.bodyMedium,
                        ),
                        subtitle: Text(
                          '${items.length} items',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        trailing: IconButton(
                          focusNode: deleteFocus,
                          icon: Icon(
                            Icons.delete_outline,
                            color: theme.colorScheme.error,
                            size: 20,
                          ),
                          onPressed: () => _deleteLocalCatalog(catalog),
                          tooltip: 'Delete catalog',
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
  final _controller = TextEditingController();
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    final url = _controller.text.trim();
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
      final resp =
          await http.get(uri).timeout(const Duration(seconds: 15));
      if (!mounted) return;

      if (resp.statusCode != 200) {
        setState(() {
          _error = 'HTTP ${resp.statusCode}';
          _loading = false;
        });
        return;
      }

      final err = await LocalCatalogImporter.import(resp.body);
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
      content: TextField(
        controller: _controller,
        decoration: InputDecoration(
          hintText: 'https://example.com/catalog.json',
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          errorText: _error,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        autofocus: true,
        onSubmitted: (_) {
          if (!_loading) _import();
        },
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
  final _controller = TextEditingController();
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    final content = _controller.text.trim();
    if (content.isEmpty) {
      setState(() => _error = 'Paste JSON content');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final err = await LocalCatalogImporter.import(content);
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
      content: TextField(
        controller: _controller,
        maxLines: 6,
        decoration: InputDecoration(
          hintText: '{"name": "My Catalog", "items": [...]}',
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          errorText: _error,
          contentPadding: const EdgeInsets.all(12),
        ),
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        autofocus: true,
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
