import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/storage_service.dart';

/// Dialog for managing local JSON catalogs in Stremio TV.
/// Shows existing catalogs (with delete) and an import section.
class StremioTvLocalCatalogsDialog extends StatefulWidget {
  const StremioTvLocalCatalogsDialog({super.key});

  /// Show the dialog. Returns `true` if catalogs were changed.
  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) => const Center(
        child: StremioTvLocalCatalogsDialog(),
      ),
    );
  }

  @override
  State<StremioTvLocalCatalogsDialog> createState() =>
      _StremioTvLocalCatalogsDialogState();
}

class _StremioTvLocalCatalogsDialogState
    extends State<StremioTvLocalCatalogsDialog> {
  final TextEditingController _jsonController = TextEditingController();
  final FocusNode _closeFocusNode = FocusNode(debugLabel: 'closeBtn');
  final FocusNode _jsonFocusNode = FocusNode(debugLabel: 'jsonField');
  final FocusNode _fileButtonFocusNode = FocusNode(debugLabel: 'fileBtn');
  final FocusNode _importButtonFocusNode = FocusNode(debugLabel: 'importBtn');
  final ScrollController _listScrollController = ScrollController();
  final List<FocusNode> _deleteFocusNodes = [];
  String? _error;
  bool _importing = false;
  bool _changed = false;
  List<Map<String, dynamic>> _catalogs = [];
  bool _loadingCatalogs = true;

  @override
  void initState() {
    super.initState();
    _loadCatalogs();
    _setupFocusNavigation();
  }

  @override
  void dispose() {
    _jsonController.dispose();
    _closeFocusNode.dispose();
    _jsonFocusNode.dispose();
    _fileButtonFocusNode.dispose();
    _importButtonFocusNode.dispose();
    _listScrollController.dispose();
    for (final node in _deleteFocusNodes) {
      node.dispose();
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
  }

  void _syncDeleteFocusNodes(int count) {
    while (_deleteFocusNodes.length < count) {
      final idx = _deleteFocusNodes.length;
      final node = FocusNode(debugLabel: 'deleteBtn$idx');
      _deleteFocusNodes.add(node);
    }
    while (_deleteFocusNodes.length > count) {
      _deleteFocusNodes.removeLast().dispose();
    }
    // Re-setup navigation since nodes changed
    _setupDeleteNodeNavigation();
  }

  void _setupDeleteNodeNavigation() {
    for (int i = 0; i < _deleteFocusNodes.length; i++) {
      final node = _deleteFocusNodes[i];
      node.onKeyEvent = (n, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.arrowUp) {
          if (i == 0) {
            _closeFocusNode.requestFocus();
          } else {
            _deleteFocusNodes[i - 1].requestFocus();
          }
          // Scroll to keep focused item visible
          _scrollToDeleteButton(i > 0 ? i - 1 : 0);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowDown) {
          if (i < _deleteFocusNodes.length - 1) {
            _deleteFocusNodes[i + 1].requestFocus();
            _scrollToDeleteButton(i + 1);
          } else {
            _jsonFocusNode.requestFocus();
          }
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter) {
          if (i < _catalogs.length) {
            _deleteLocalCatalog(_catalogs[i]);
          }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      };
    }
  }

  void _scrollToDeleteButton(int index) {
    if (!_listScrollController.hasClients) return;
    // Each list tile is roughly 56px tall
    const itemHeight = 56.0;
    final targetOffset = index * itemHeight;
    final maxOffset = _listScrollController.position.maxScrollExtent;
    _listScrollController.animateTo(
      targetOffset.clamp(0.0, maxOffset),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  void _setupFocusNavigation() {
    // Close button
    _closeFocusNode.onKeyEvent = (node, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.arrowDown) {
        // Go to first delete button if catalogs exist, otherwise JSON field
        if (_deleteFocusNodes.isNotEmpty) {
          _deleteFocusNodes.first.requestFocus();
        } else {
          _jsonFocusNode.requestFocus();
        }
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.select ||
          key == LogicalKeyboardKey.enter) {
        Navigator.of(context).pop(_changed);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };

    // JSON text field
    _jsonFocusNode.onKeyEvent = (node, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      final key = event.logicalKey;
      final text = _jsonController.text;
      final selection = _jsonController.selection;
      final isAtStart = !selection.isValid ||
          (selection.baseOffset == 0 && selection.extentOffset == 0);
      final isAtEnd = !selection.isValid ||
          (selection.baseOffset == text.length &&
              selection.extentOffset == text.length);

      if (key == LogicalKeyboardKey.arrowUp) {
        if (text.isEmpty || isAtStart) {
          if (_deleteFocusNodes.isNotEmpty) {
            _deleteFocusNodes.last.requestFocus();
          } else {
            _closeFocusNode.requestFocus();
          }
          return KeyEventResult.handled;
        }
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        if (text.isEmpty || isAtEnd) {
          _fileButtonFocusNode.requestFocus();
          return KeyEventResult.handled;
        }
      }
      return KeyEventResult.ignored;
    };

    // Import File button
    _fileButtonFocusNode.onKeyEvent = (node, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.arrowUp) {
        _jsonFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        _importButtonFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.select ||
          key == LogicalKeyboardKey.enter) {
        if (!_importing) _importFromFile();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };

    // Import button
    _importButtonFocusNode.onKeyEvent = (node, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.arrowUp) {
        _fileButtonFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.select ||
          key == LogicalKeyboardKey.enter) {
        if (!_importing) _import();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };
  }

  /// Generate a unique catalog ID from the name.
  String _generateCatalogId(String name) {
    final sanitized = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final ts = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    return '${sanitized}_$ts';
  }

  /// Validate and import JSON content. Returns error message or null on success.
  String? _processJson(String content) {
    final dynamic parsed;
    try {
      parsed = jsonDecode(content);
    } catch (e) {
      return 'Invalid JSON: $e';
    }

    if (parsed is! Map<String, dynamic>) {
      return 'Invalid JSON: expected an object';
    }

    final name = parsed['name'] as String?;
    if (name == null || name.trim().isEmpty) {
      return 'Invalid catalog: missing "name"';
    }

    final rawItems = parsed['items'] as List<dynamic>?;
    if (rawItems == null || rawItems.isEmpty) {
      return 'Invalid catalog: "items" is missing or empty';
    }

    for (int i = 0; i < rawItems.length; i++) {
      final item = rawItems[i];
      if (item is! Map<String, dynamic>) {
        return 'Invalid item at index $i: not an object';
      }
      final itemId = item['id'] as String?;
      final itemName = item['name'] as String?;
      if (itemId == null ||
          itemId.isEmpty ||
          itemName == null ||
          itemName.isEmpty) {
        return 'Invalid item at index $i: missing "id" or "name"';
      }
    }

    return null; // valid
  }

  Future<void> _importFromFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) {
        setState(() => _error = 'Could not read file data');
        return;
      }

      final content = utf8.decode(bytes);
      setState(() {
        _jsonController.text = content;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = 'Failed to read file: $e');
    }
  }

  Future<void> _import() async {
    final content = _jsonController.text.trim();
    if (content.isEmpty) {
      setState(() => _error = 'Please paste JSON or import a file');
      return;
    }

    final validationError = _processJson(content);
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }

    setState(() {
      _importing = true;
      _error = null;
    });

    try {
      final parsed = jsonDecode(content) as Map<String, dynamic>;
      final name = (parsed['name'] as String).trim();
      final rawItems = parsed['items'] as List<dynamic>;
      final type = parsed['type'] as String? ?? 'movie';
      final catalogId = _generateCatalogId(name);

      final catalog = <String, dynamic>{
        'id': catalogId,
        'name': name,
        'type': type,
        'addedAt': DateTime.now().toIso8601String(),
        'items': rawItems,
      };

      // Check for duplicate name
      if (_catalogs.any((c) => c['name'] == name)) {
        setState(() {
          _error = 'A catalog with this name already exists';
          _importing = false;
        });
        return;
      }

      await StorageService.addStremioTvLocalCatalog(catalog);

      _changed = true;
      _jsonController.clear();
      await _loadCatalogs();
      if (mounted) {
        setState(() {
          _importing = false;
          _error = null;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to import: $e';
        _importing = false;
      });
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
    final maxHeight = screenHeight * 0.8;

    return Material(
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
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
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
              // Catalog list
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
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'No local catalogs yet.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
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
                          onPressed: () =>
                              _deleteLocalCatalog(catalog),
                          tooltip: 'Delete catalog',
                        ),
                      );
                    },
                  ),
                ),
              const Divider(height: 24),
              // Import section
              Text(
                'Import',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              // Paste JSON
              TextField(
                controller: _jsonController,
                focusNode: _jsonFocusNode,
                maxLines: 6,
                decoration: InputDecoration(
                  hintText: 'Paste JSON here...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                ),
              ),
              // Error text
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              // OR divider
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'or',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 12),
              // Import file button
              OutlinedButton.icon(
                focusNode: _fileButtonFocusNode,
                onPressed: _importing ? null : _importFromFile,
                icon: const Icon(Icons.file_upload_outlined, size: 18),
                label: const Text('Import File'),
              ),
              const SizedBox(height: 16),
              // Import button
              FilledButton(
                focusNode: _importButtonFocusNode,
                onPressed: _importing ? null : _import,
                child: _importing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Import'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
