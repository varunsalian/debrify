import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../services/storage_service.dart';

/// Dialog for importing a local JSON catalog into Stremio TV.
/// Supports pasting JSON directly or picking a .json file.
class StremioTvImportCatalogDialog extends StatefulWidget {
  const StremioTvImportCatalogDialog({super.key});

  /// Show the import dialog. Returns `true` if a catalog was imported.
  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) => const Center(
        child: StremioTvImportCatalogDialog(),
      ),
    );
  }

  @override
  State<StremioTvImportCatalogDialog> createState() =>
      _StremioTvImportCatalogDialogState();
}

class _StremioTvImportCatalogDialogState
    extends State<StremioTvImportCatalogDialog> {
  final TextEditingController _jsonController = TextEditingController();
  String? _error;
  bool _importing = false;

  @override
  void dispose() {
    _jsonController.dispose();
    super.dispose();
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

      final added = await StorageService.addStremioTvLocalCatalog(catalog);
      if (!added) {
        setState(() {
          _error = 'A catalog with this name already exists';
          _importing = false;
        });
        return;
      }

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to import: $e';
        _importing = false;
      });
    }
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
                      'Import Local Catalog',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    tooltip: 'Close',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Paste JSON
              TextField(
                controller: _jsonController,
                maxLines: 8,
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
                onPressed: _importing ? null : _importFromFile,
                icon: const Icon(Icons.file_upload_outlined, size: 18),
                label: const Text('Import File'),
              ),
              const SizedBox(height: 16),
              // Import button
              FilledButton(
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
