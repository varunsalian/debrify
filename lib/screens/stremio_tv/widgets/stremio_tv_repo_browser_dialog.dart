import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/catalog_repo_service.dart';
import '../../../services/storage_service.dart';

/// Single-view accordion dialog for browsing catalog repositories.
/// Repos expand inline to show files for selective import.
class StremioTvRepoBrowserDialog extends StatefulWidget {
  const StremioTvRepoBrowserDialog({super.key});

  /// Show the dialog. Returns `true` if any catalogs were imported.
  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) => const Center(
        child: StremioTvRepoBrowserDialog(),
      ),
    );
  }

  @override
  State<StremioTvRepoBrowserDialog> createState() =>
      _StremioTvRepoBrowserDialogState();
}

class _StremioTvRepoBrowserDialogState
    extends State<StremioTvRepoBrowserDialog> {
  // ─── State ──────────────────────────────────────────────────────────────
  bool _changed = false;
  String? _error;

  // Repos
  List<String> _repoUrls = [];
  bool _loadingRepos = true;
  int? _expandedIndex;

  // Files (for expanded repo)
  List<RepoFileEntry> _files = [];
  final Set<String> _selectedPaths = {};
  bool _loadingFiles = false;
  bool _importing = false;
  String? _importStatus;

  /// Per-file import state: null=pending, 'importing', 'done', or error msg.
  final Map<String, String?> _fileImportStates = {};

  // ─── Controllers ────────────────────────────────────────────────────────
  final _urlController = TextEditingController();
  final _scrollController = ScrollController();

  // ─── Focus nodes (fixed) ────────────────────────────────────────────────
  final _closeFocusNode = FocusNode(debugLabel: 'close');
  final _urlFocusNode = FocusNode(debugLabel: 'url');
  final _addBtnFocusNode = FocusNode(debugLabel: 'add');
  final _selectAllFocusNode = FocusNode(debugLabel: 'selectAll');
  final _importBtnFocusNode = FocusNode(debugLabel: 'import');
  final _removeBtnFocusNode = FocusNode(debugLabel: 'remove');

  // ─── Focus nodes (dynamic) ─────────────────────────────────────────────
  final List<FocusNode> _repoFocusNodes = [];
  final List<FocusNode> _fileFocusNodes = [];

  // ─── Lifecycle ──────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadRepos();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _scrollController.dispose();
    _closeFocusNode.dispose();
    _urlFocusNode.dispose();
    _addBtnFocusNode.dispose();
    _selectAllFocusNode.dispose();
    _importBtnFocusNode.dispose();
    _removeBtnFocusNode.dispose();
    for (final n in _repoFocusNodes) {
      n.dispose();
    }
    for (final n in _fileFocusNodes) {
      n.dispose();
    }
    super.dispose();
  }

  // ─── Data loading ───────────────────────────────────────────────────────

  Future<void> _loadRepos() async {
    final urls = await StorageService.getStremioTvCatalogRepoUrls();
    if (!mounted) return;
    _syncRepoFocusNodes(urls.length);
    setState(() {
      _repoUrls = urls;
      _loadingRepos = false;
    });
    _rebuildNavigation();
  }

  Future<void> _fetchFiles(RepoRef ref, int expandIndex) async {
    try {
      final files = await CatalogRepoService.listJsonFiles(ref);
      if (!mounted || _expandedIndex != expandIndex) return;
      _syncFileFocusNodes(files.length);
      setState(() {
        _files = files;
        _loadingFiles = false;
        // Pre-select all
        _selectedPaths
          ..clear()
          ..addAll(files.map((f) => f.path));
        if (files.isEmpty) _error = 'No .json files found';
      });
      _rebuildNavigation();
      // Auto-focus first file or import button
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_fileFocusNodes.isNotEmpty) {
          _fileFocusNodes.first.requestFocus();
          _scrollToFocusNode(_fileFocusNodes.first);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingFiles = false;
        _error = 'Failed to load files: $e';
      });
      _rebuildNavigation();
    }
  }

  // ─── Focus node management ─────────────────────────────────────────────

  void _syncRepoFocusNodes(int count) {
    while (_repoFocusNodes.length < count) {
      _repoFocusNodes
          .add(FocusNode(debugLabel: 'repo${_repoFocusNodes.length}'));
    }
    while (_repoFocusNodes.length > count) {
      _repoFocusNodes.removeLast().dispose();
    }
  }

  void _syncFileFocusNodes(int count) {
    while (_fileFocusNodes.length < count) {
      _fileFocusNodes
          .add(FocusNode(debugLabel: 'file${_fileFocusNodes.length}'));
    }
    while (_fileFocusNodes.length > count) {
      _fileFocusNodes.removeLast().dispose();
    }
  }

  /// Build flat DPAD focus order and wire up all key handlers.
  void _rebuildNavigation() {
    final order = <FocusNode>[
      _closeFocusNode,
      _urlFocusNode,
      _addBtnFocusNode,
    ];

    for (int i = 0; i < _repoUrls.length; i++) {
      if (i < _repoFocusNodes.length) {
        order.add(_repoFocusNodes[i]);
      }
      if (i == _expandedIndex) {
        if (!_loadingFiles) {
          for (int j = 0;
              j < _fileFocusNodes.length && j < _files.length;
              j++) {
            order.add(_fileFocusNodes[j]);
          }
          if (_files.isNotEmpty) {
            order.add(_selectAllFocusNode);
            order.add(_importBtnFocusNode);
          }
        }
        // Remove always accessible when expanded
        order.add(_removeBtnFocusNode);
      }
    }

    for (int idx = 0; idx < order.length; idx++) {
      final node = order[idx];
      final prev = idx > 0 ? order[idx - 1] : null;
      final next = idx < order.length - 1 ? order[idx + 1] : null;

      node.onKeyEvent = (n, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;

        // URL field: allow cursor movement
        if (node == _urlFocusNode) {
          return _handleUrlFieldKey(key, prev, next);
        }

        if (key == LogicalKeyboardKey.arrowUp && prev != null) {
          prev.requestFocus();
          _scrollToFocusNode(prev);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowDown && next != null) {
          next.requestFocus();
          _scrollToFocusNode(next);
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

  KeyEventResult _handleUrlFieldKey(
      LogicalKeyboardKey key, FocusNode? prev, FocusNode? next) {
    final text = _urlController.text;
    final sel = _urlController.selection;
    final atStart =
        !sel.isValid || (sel.baseOffset == 0 && sel.extentOffset == 0);
    final atEnd = !sel.isValid ||
        (sel.baseOffset == text.length && sel.extentOffset == text.length);

    if (key == LogicalKeyboardKey.arrowUp &&
        (text.isEmpty || atStart) &&
        prev != null) {
      prev.requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown &&
        (text.isEmpty || atEnd) &&
        next != null) {
      next.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _handleActivate(FocusNode node) {
    if (node == _closeFocusNode) {
      Navigator.of(context).pop(_changed);
    } else if (node == _addBtnFocusNode) {
      _addRepo();
    } else if (node == _selectAllFocusNode) {
      if (!_importing) _toggleSelectAll();
    } else if (node == _importBtnFocusNode) {
      if (!_importing && _selectedPaths.isNotEmpty) _importSelected();
    } else if (node == _removeBtnFocusNode) {
      if (!_importing && _expandedIndex != null) {
        _confirmDeleteRepo(_expandedIndex!);
      }
    } else {
      final repoIdx = _repoFocusNodes.indexOf(node);
      if (repoIdx >= 0) {
        _toggleExpand(repoIdx);
        return;
      }
      final fileIdx = _fileFocusNodes.indexOf(node);
      if (fileIdx >= 0 && fileIdx < _files.length && !_importing) {
        _toggleFile(_files[fileIdx].path);
      }
    }
  }

  void _scrollToFocusNode(FocusNode node) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = node.context;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ─── Actions ────────────────────────────────────────────────────────────

  Future<void> _addRepo() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() => _error = 'Please enter a repository URL');
      return;
    }

    final ref = CatalogRepoService.parseRepoUrl(url);
    if (ref == null) {
      setState(() => _error = 'Invalid GitHub or GitLab URL');
      return;
    }

    final canonicalUrl = ref.canonicalUrl;

    // Already saved? Just expand it.
    final existingIdx = _repoUrls.indexOf(canonicalUrl);
    if (existingIdx >= 0) {
      _urlController.clear();
      setState(() => _error = null);
      _toggleExpand(existingIdx);
      return;
    }

    final added =
        await StorageService.addStremioTvCatalogRepoUrl(canonicalUrl);
    if (!mounted) return;
    if (!added) {
      setState(() => _error = 'Repository already added');
      return;
    }

    _urlController.clear();
    setState(() => _error = null);
    await _loadRepos();
    if (!mounted) return;

    // Auto-expand the newly added repo
    final newIdx = _repoUrls.indexOf(canonicalUrl);
    if (newIdx >= 0) {
      _toggleExpand(newIdx);
    }
  }

  void _toggleExpand(int index) {
    if (_expandedIndex == index) {
      // Collapse
      setState(() {
        _expandedIndex = null;
        _files = [];
        _selectedPaths.clear();
        _error = null;
        _importStatus = null;
        _fileImportStates.clear();
      });
      _rebuildNavigation();
      if (index < _repoFocusNodes.length) {
        _repoFocusNodes[index].requestFocus();
      }
    } else {
      // Expand
      final url = _repoUrls[index];
      final ref = CatalogRepoService.parseRepoUrl(url);
      if (ref == null) {
        setState(() => _error = 'Could not parse repo URL');
        return;
      }
      setState(() {
        _expandedIndex = index;
        _files = [];
        _selectedPaths.clear();
        _loadingFiles = true;
        _error = null;
        _importStatus = null;
        _fileImportStates.clear();
      });
      _rebuildNavigation();
      _fetchFiles(ref, index);
    }
  }

  void _toggleFile(String path) {
    setState(() {
      if (_selectedPaths.contains(path)) {
        _selectedPaths.remove(path);
      } else {
        _selectedPaths.add(path);
      }
    });
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectedPaths.length == _files.length) {
        _selectedPaths.clear();
      } else {
        _selectedPaths
          ..clear()
          ..addAll(_files.map((f) => f.path));
      }
    });
  }

  Future<void> _importSelected() async {
    final selected =
        _files.where((f) => _selectedPaths.contains(f.path)).toList();
    if (selected.isEmpty) return;

    setState(() {
      _importing = true;
      _error = null;
      _importStatus = null;
      _fileImportStates.clear();
      for (final f in selected) {
        _fileImportStates[f.path] = null;
      }
    });

    int imported = 0;
    final errors = <String>[];

    for (final file in selected) {
      if (!mounted) return;
      setState(() => _fileImportStates[file.path] = 'importing');

      try {
        final content =
            await CatalogRepoService.fetchFileContent(file.downloadUrl);
        if (!mounted) return;
        final validationError = _processJson(content);
        if (validationError != null) {
          errors.add('${file.name}: $validationError');
          if (mounted) {
            setState(() => _fileImportStates[file.path] = validationError);
          }
          continue;
        }

        final parsed = jsonDecode(content) as Map<String, dynamic>;
        final name = (parsed['name'] as String).trim();
        final rawItems = parsed['items'] as List<dynamic>;
        final type = parsed['type'] as String? ?? 'movie';

        // Check for duplicate name
        final existing = await StorageService.getStremioTvLocalCatalogs();
        if (existing.any((c) => c['name'] == name)) {
          errors.add('${file.name}: "$name" already exists');
          if (mounted) {
            setState(
                () => _fileImportStates[file.path] = '"$name" already exists');
          }
          continue;
        }

        final catalogId = _generateCatalogId(name);
        final catalog = <String, dynamic>{
          'id': catalogId,
          'name': name,
          'type': type,
          'addedAt': DateTime.now().toIso8601String(),
          'items': rawItems,
        };

        await StorageService.addStremioTvLocalCatalog(catalog);
        imported++;
        _changed = true;
        if (mounted) setState(() => _fileImportStates[file.path] = 'done');
      } catch (e) {
        errors.add('${file.name}: $e');
        if (mounted) setState(() => _fileImportStates[file.path] = '$e');
      }
    }

    if (!mounted) return;

    final parts = <String>[];
    if (imported > 0) parts.add('$imported imported');
    if (errors.isNotEmpty) parts.add('${errors.length} failed');

    setState(() {
      _importing = false;
      _importStatus = parts.join(', ');
      if (errors.isNotEmpty) _error = errors.join('\n');
    });
  }

  Future<void> _confirmDeleteRepo(int index) async {
    if (index >= _repoUrls.length) return;
    final url = _repoUrls[index];
    final ref = CatalogRepoService.parseRepoUrl(url);
    final label = ref?.displayUrl ?? url;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Repository'),
        content: Text('Remove "$label" from saved repos?'),
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
    if (confirmed != true || !mounted) return;

    // Adjust expanded index
    if (_expandedIndex == index) {
      _expandedIndex = null;
      _files = [];
      _selectedPaths.clear();
      _fileImportStates.clear();
    } else if (_expandedIndex != null && _expandedIndex! > index) {
      _expandedIndex = _expandedIndex! - 1;
    }

    await StorageService.removeStremioTvCatalogRepoUrl(url);
    if (!mounted) return;
    await _loadRepos();
    if (!mounted) return;

    // Focus next available item
    final focusIdx = min(index, _repoFocusNodes.length - 1);
    if (focusIdx >= 0) {
      _repoFocusNodes[focusIdx].requestFocus();
    } else {
      _addBtnFocusNode.requestFocus();
    }
  }

  // ─── Helpers ────────────────────────────────────────────────────────────

  String _generateCatalogId(String name) {
    final sanitized = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final ts = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    return '${sanitized}_$ts';
  }

  String? _processJson(String content) {
    final dynamic parsed;
    try {
      parsed = jsonDecode(content);
    } catch (e) {
      return 'Invalid JSON: $e';
    }
    if (parsed is! Map<String, dynamic>) return 'expected an object';
    final name = parsed['name'] as String?;
    if (name == null || name.trim().isEmpty) return 'missing "name"';
    final rawItems = parsed['items'] as List<dynamic>?;
    if (rawItems == null || rawItems.isEmpty) {
      return '"items" is missing or empty';
    }
    for (int i = 0; i < rawItems.length; i++) {
      final item = rawItems[i];
      if (item is! Map<String, dynamic>) return 'item $i: not an object';
      final itemId = item['id'] as String?;
      final itemName = item['name'] as String?;
      if (itemId == null ||
          itemId.isEmpty ||
          itemName == null ||
          itemName.isEmpty) {
        return 'item $i: missing "id" or "name"';
      }
    }
    return null;
  }

  // ─── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenHeight = MediaQuery.of(context).size.height;

    return Material(
      type: MaterialType.transparency,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 500,
          maxHeight: screenHeight * 0.85,
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
                  Icon(Icons.source_rounded,
                      size: 20, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Catalog Repos',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
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

              // ── URL input ──
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _urlController,
                      focusNode: _urlFocusNode,
                      decoration: InputDecoration(
                        hintText: 'https://github.com/user/repo',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        isDense: true,
                      ),
                      style: theme.textTheme.bodySmall,
                      onSubmitted: (_) => _addRepo(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 40,
                    child: FilledButton.tonalIcon(
                      focusNode: _addBtnFocusNode,
                      onPressed: _addRepo,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add'),
                    ),
                  ),
                ],
              ),

              // ── Top-level error (only when no repo is expanded) ──
              if (_error != null && _expandedIndex == null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error),
                  ),
                ),

              const Divider(height: 20),

              // ── Repo list ──
              if (_loadingRepos)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                )
              else if (_repoUrls.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Column(
                    children: [
                      Icon(Icons.folder_open_rounded,
                          size: 36,
                          color: theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.35)),
                      const SizedBox(height: 8),
                      Text(
                        'No repos added yet',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Paste a GitHub or GitLab repo URL above',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.6),
                          fontSize: 11,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              else
                Flexible(
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (int i = 0; i < _repoUrls.length; i++) ...[
                          _buildRepoRow(i, theme),
                          _buildExpandedContent(i, theme),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Repo Row ────────────────────────────────────────────────────────────

  Widget _buildRepoRow(int index, ThemeData theme) {
    final url = _repoUrls[index];
    final ref = CatalogRepoService.parseRepoUrl(url);
    final label = ref?.displayUrl ?? url;
    final expanded = _expandedIndex == index;
    final focusNode =
        index < _repoFocusNodes.length ? _repoFocusNodes[index] : null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: expanded
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.25)
            : Colors.transparent,
        borderRadius: expanded
            ? const BorderRadius.vertical(top: Radius.circular(12))
            : BorderRadius.circular(12),
        child: InkWell(
          focusNode: focusNode,
          focusColor: theme.colorScheme.primary.withValues(alpha: 0.12),
          borderRadius: expanded
              ? const BorderRadius.vertical(top: Radius.circular(12))
              : BorderRadius.circular(12),
          onTap: () => _toggleExpand(index),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                AnimatedRotation(
                  turns: expanded ? 0.25 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.chevron_right_rounded,
                      size: 20, color: theme.colorScheme.primary),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: expanded ? FontWeight.w600 : null,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!expanded)
                  IconButton(
                    icon: Icon(Icons.close_rounded,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.4)),
                    onPressed: () => _confirmDeleteRepo(index),
                    tooltip: 'Remove',
                    visualDensity: VisualDensity.compact,
                    constraints:
                        const BoxConstraints(minWidth: 28, minHeight: 28),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Expanded Content ────────────────────────────────────────────────────

  Widget _buildExpandedContent(int index, ThemeData theme) {
    if (_expandedIndex != index) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.10),
        borderRadius:
            const BorderRadius.vertical(bottom: Radius.circular(12)),
        border: Border(
          left: BorderSide(
              color: theme.colorScheme.primary.withValues(alpha: 0.5), width: 3),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Loading
          if (_loadingFiles)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            )
          else ...[
            // Files
            if (_files.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'No .json files found',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              )
            else
              for (int j = 0; j < _files.length; j++)
                _buildFileRow(j, theme),

            // Import status
            if (_importStatus != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _importStatus!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),

            // Error (inside expanded section)
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _error!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

            const SizedBox(height: 10),

            // Action buttons
            ..._buildActionButtons(theme),
          ],
        ],
      ),
    );
  }

  // ── File Row ────────────────────────────────────────────────────────────

  Widget _buildFileRow(int index, ThemeData theme) {
    final file = _files[index];
    final selected = _selectedPaths.contains(file.path);
    final focusNode =
        index < _fileFocusNodes.length ? _fileFocusNodes[index] : null;
    final importState = _fileImportStates[file.path];

    Widget? trailing;
    if (importState == 'importing') {
      trailing = const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2));
    } else if (importState == 'done') {
      trailing =
          Icon(Icons.check_circle_rounded, size: 18, color: Colors.green[400]);
    } else if (importState != null) {
      trailing = Tooltip(
        message: importState,
        child:
            Icon(Icons.error_rounded, size: 18, color: theme.colorScheme.error),
      );
    }

    return InkWell(
      focusNode: focusNode,
      focusColor: theme.colorScheme.primary.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(8),
      onTap: _importing ? null : () => _toggleFile(file.path),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: selected,
                onChanged: _importing ? null : (_) => _toggleFile(file.path),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.description_outlined,
                size: 16, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                file.name,
                style: theme.textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing],
          ],
        ),
      ),
    );
  }

  // ── Action Buttons ─────────────────────────────────────────────────────

  List<Widget> _buildActionButtons(ThemeData theme) {
    final allSelected =
        _files.isNotEmpty && _selectedPaths.length == _files.length;

    return [
      if (_files.isNotEmpty) ...[
        // Select All
        SizedBox(
          width: double.infinity,
          child: TextButton.icon(
            focusNode: _selectAllFocusNode,
            onPressed: _importing ? null : _toggleSelectAll,
            icon: Icon(
              allSelected
                  ? Icons.deselect_rounded
                  : Icons.select_all_rounded,
              size: 16,
            ),
            label: Text(allSelected ? 'Deselect All' : 'Select All'),
          ),
        ),
        const SizedBox(height: 4),
        // Import
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            focusNode: _importBtnFocusNode,
            onPressed:
                _importing || _selectedPaths.isEmpty ? null : _importSelected,
            icon: _importing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.download_rounded, size: 18),
            label: Text(_importing
                ? 'Importing...'
                : 'Import ${_selectedPaths.length} catalog${_selectedPaths.length == 1 ? '' : 's'}'),
          ),
        ),
        const SizedBox(height: 4),
      ],
      // Remove repo
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          focusNode: _removeBtnFocusNode,
          onPressed: _importing
              ? null
              : () {
                  if (_expandedIndex != null) {
                    _confirmDeleteRepo(_expandedIndex!);
                  }
                },
          icon: Icon(Icons.delete_outline_rounded,
              size: 16, color: theme.colorScheme.error),
          label: Text('Remove Repository',
              style: TextStyle(color: theme.colorScheme.error)),
          style: OutlinedButton.styleFrom(
            side: BorderSide(
                color: theme.colorScheme.error.withValues(alpha: 0.3)),
          ),
        ),
      ),
    ];
  }
}
