import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/stremio_addon.dart';
import '../../services/main_page_bridge.dart';
import '../../services/stremio_service.dart';
import '../addons_screen.dart';

/// Page for managing Stremio addons (with Scaffold wrapper)
class StremioAddonsPage extends StatefulWidget {
  const StremioAddonsPage({super.key});

  @override
  State<StremioAddonsPage> createState() => _StremioAddonsPageState();
}

/// Content widget for embedding in tabs (without Scaffold)
class StremioAddonsPageContent extends StatefulWidget {
  const StremioAddonsPageContent({super.key});

  @override
  State<StremioAddonsPageContent> createState() =>
      _StremioAddonsPageContentState();
}

class _StremioAddonsPageContentState extends State<StremioAddonsPageContent> {
  final StremioService _stremioService = StremioService.instance;
  final TextEditingController _urlController = TextEditingController();
  final FocusNode _urlFieldFocusNode = FocusNode(
    debugLabel: 'url-field-content',
  );
  final FocusNode _addButtonFocusNode = FocusNode(
    debugLabel: 'add-button-content',
  );
  final FocusNode _importButtonFocusNode = FocusNode(
    debugLabel: 'import-stremio-json-content',
  );
  final FocusNode _deleteAllButtonFocusNode = FocusNode(
    debugLabel: 'delete-all-stremio-addons-content',
  );

  bool _isLoading = true;
  bool _isAdding = false;
  bool _isImporting = false;
  bool _isDeletingAll = false;
  String? _error;
  List<StremioAddon> _addons = [];
  final Map<String, FocusNode> _addonFocusNodes = {};
  bool _urlFieldFocused = false;

  @override
  void initState() {
    super.initState();
    _urlFieldFocusNode.addListener(_onUrlFieldFocusChanged);
    _stremioService.addAddonsChangedListener(_onAddonsChanged);
    _loadAddons();
  }

  void _onAddonsChanged() {
    if (mounted) _loadAddons();
  }

  void _onUrlFieldFocusChanged() {
    setState(() {
      _urlFieldFocused = _urlFieldFocusNode.hasFocus;
    });
  }

  @override
  void dispose() {
    _stremioService.removeAddonsChangedListener(_onAddonsChanged);
    _urlController.dispose();
    _urlFieldFocusNode.removeListener(_onUrlFieldFocusChanged);
    _urlFieldFocusNode.dispose();
    _addButtonFocusNode.dispose();
    _importButtonFocusNode.dispose();
    _deleteAllButtonFocusNode.dispose();
    for (final node in _addonFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _loadAddons() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      _addons = await _stremioService.getAddons();
      for (final node in _addonFocusNodes.values) {
        node.dispose();
      }
      _addonFocusNodes.clear();
      for (final addon in _addons) {
        _addonFocusNodes[addon.manifestUrl] = FocusNode(
          debugLabel: 'addon-${addon.id}',
        );
      }
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _addAddon() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an addon URL')),
      );
      return;
    }

    setState(() {
      _isAdding = true;
    });

    try {
      final addon = await _stremioService.addAddon(url);
      _urlController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${addon.name} added successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        final errorMessage = e.toString().replaceFirst('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAdding = false;
        });
      }
    }
  }

  Future<void> _importFromJsonFile() async {
    if (_isImporting) return;

    setState(() {
      _isImporting = true;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (!file.name.toLowerCase().endsWith('.json')) {
        throw Exception('Please select the Stremio addon JSON export.');
      }

      final List<int> bytes;
      if (file.bytes != null) {
        bytes = file.bytes!;
      } else if (file.path != null) {
        bytes = await file.xFile.readAsBytes();
      } else {
        throw Exception('Could not read the selected file.');
      }

      final importResult = await _stremioService.importAddonsFromJson(
        utf8.decode(bytes),
      );
      if (!mounted) return;

      await _loadAddons();
      if (!mounted) return;

      await _showImportResult(importResult);
    } catch (e) {
      if (mounted) {
        final errorMessage = e.toString().replaceFirst('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isImporting = false;
        });
      }
    }
  }

  Future<void> _showImportResult(StremioAddonImportResult result) {
    final theme = Theme.of(context);
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stremio import complete'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ImportResultRow(
              icon: Icons.inventory_2_outlined,
              label: 'Found',
              value: '${result.discovered}',
            ),
            _ImportResultRow(
              icon: Icons.check_circle_outline,
              label: 'Imported',
              value: '${result.imported}',
            ),
            _ImportResultRow(
              icon: Icons.copy_all_outlined,
              label: 'Already installed',
              value: '${result.skippedDuplicates}',
            ),
            if (result.skippedUnsupported > 0)
              _ImportResultRow(
                icon: Icons.block_outlined,
                label: 'Unsupported',
                value: '${result.skippedUnsupported}',
              ),
            if (result.failed > 0)
              _ImportResultRow(
                icon: Icons.error_outline,
                label: 'Failed',
                value: '${result.failed}',
                color: theme.colorScheme.error,
              ),
            if (result.errors.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                result.errors.take(3).join('\n'),
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAllAddons() async {
    if (_addons.isEmpty || _isDeletingAll) return;

    final count = _addons.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete all addons?'),
        content: Text(
          'This will remove all $count installed Stremio addon${count == 1 ? '' : 's'} from Debrify.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete all'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isDeletingAll = true;
    });

    try {
      await _stremioService.clearAllAddons();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Deleted $count Stremio addon${count == 1 ? '' : 's'}'),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete addons: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDeletingAll = false;
        });
      }
    }
  }

  Future<void> _toggleAddon(StremioAddon addon) async {
    await _stremioService.setAddonEnabled(addon.manifestUrl, !addon.enabled);
  }

  Future<void> _deleteAddon(StremioAddon addon) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Addon'),
        content: Text('Remove "${addon.name}" from your addons?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _stremioService.removeAddon(addon.manifestUrl);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${addon.name} removed')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to remove addon: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showAddonDetails(StremioAddon addon) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(addon.name),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (addon.description != null) ...[
                Text(addon.description!),
                const SizedBox(height: 16),
              ],
              _DetailRow(label: 'ID', value: addon.id),
              if (addon.version != null)
                _DetailRow(label: 'Version', value: addon.version!),
              _DetailRow(
                label: 'Types',
                value: addon.types.isEmpty ? 'None' : addon.types.join(', '),
              ),
              _DetailRow(
                label: 'Resources',
                value: addon.resources.isEmpty
                    ? 'None'
                    : addon.resources.join(', '),
              ),
              if (addon.idPrefixes != null && addon.idPrefixes!.isNotEmpty)
                _DetailRow(
                  label: 'ID Prefixes',
                  value: addon.idPrefixes!.join(', '),
                ),
              _DetailRow(label: 'Added', value: _formatDate(addon.addedAt)),
              if (addon.lastChecked != null)
                _DetailRow(
                  label: 'Last Checked',
                  value: _formatDate(addon.lastChecked!),
                ),
              const SizedBox(height: 16),
              const Text(
                'Manifest URL:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              SelectableText(
                addon.manifestUrl,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: addon.manifestUrl));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('URL copied to clipboard')),
              );
            },
            child: const Text('Copy URL'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: Column(
        children: [
          _buildAddSection(),
          const Divider(height: 1),
          Expanded(child: _buildAddonsList()),
        ],
      ),
    );
  }

  Widget _buildAddSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Add Stremio Addon',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Paste one manifest URL, or import a JSON export from Stremio Web.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FocusTraversalOrder(
                  order: const NumericFocusOrder(0),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: _urlFieldFocused
                          ? Border.all(
                              color: Theme.of(context).colorScheme.primary,
                              width: 2,
                            )
                          : null,
                    ),
                    child: Shortcuts(
                      shortcuts: const <ShortcutActivator, Intent>{
                        SingleActivator(LogicalKeyboardKey.arrowDown):
                            NextFocusIntent(),
                        SingleActivator(LogicalKeyboardKey.arrowUp):
                            PreviousFocusIntent(),
                        SingleActivator(LogicalKeyboardKey.arrowRight):
                            _MoveToAddButtonIntent(),
                        SingleActivator(LogicalKeyboardKey.arrowLeft):
                            _MoveToSidebarIntent(),
                      },
                      child: Actions(
                        actions: <Type, Action<Intent>>{
                          NextFocusIntent: CallbackAction<NextFocusIntent>(
                            onInvoke: (intent) {
                              _importButtonFocusNode.requestFocus();
                              return null;
                            },
                          ),
                          PreviousFocusIntent:
                              CallbackAction<PreviousFocusIntent>(
                                onInvoke: (intent) {
                                  // Move to tab bar if available
                                  if (AddonsScreen.focusCurrentTab != null) {
                                    AddonsScreen.focusCurrentTab!();
                                  }
                                  return null;
                                },
                              ),
                          _MoveToAddButtonIntent:
                              CallbackAction<_MoveToAddButtonIntent>(
                                onInvoke: (intent) {
                                  _addButtonFocusNode.requestFocus();
                                  return null;
                                },
                              ),
                          _MoveToSidebarIntent:
                              CallbackAction<_MoveToSidebarIntent>(
                                onInvoke: (intent) {
                                  if (MainPageBridge.focusTvSidebar != null) {
                                    MainPageBridge.focusTvSidebar!();
                                  }
                                  return null;
                                },
                              ),
                        },
                        child: TextField(
                          controller: _urlController,
                          focusNode: _urlFieldFocusNode,
                          decoration: const InputDecoration(
                            hintText: 'https://addon.example.com/manifest.json',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 14,
                            ),
                          ),
                          keyboardType: TextInputType.url,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _addAddon(),
                          enabled: !_isAdding,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FocusTraversalOrder(
                order: const NumericFocusOrder(1),
                child: FilledButton.icon(
                  focusNode: _addButtonFocusNode,
                  onPressed: _isAdding ? null : _addAddon,
                  icon: _isAdding
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.add),
                  label: const Text('Add'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildImportActionsCard(),
        ],
      ),
    );
  }

  Widget _buildImportActionsCard() {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.55,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.8),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 620;
          final header = Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.upload_file_rounded,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Import Stremio export',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Select a Stremio addon JSON export, or clear the installed addon list.',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );

          final actions = Wrap(
            spacing: 10,
            runSpacing: 8,
            alignment: compact ? WrapAlignment.start : WrapAlignment.end,
            children: [
              FocusTraversalOrder(
                order: const NumericFocusOrder(2),
                child: FilledButton.icon(
                  focusNode: _importButtonFocusNode,
                  onPressed: _isImporting ? null : _importFromJsonFile,
                  icon: _isImporting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.file_open_rounded),
                  label: Text(_isImporting ? 'Importing' : 'Import JSON'),
                ),
              ),
              FocusTraversalOrder(
                order: const NumericFocusOrder(3),
                child: OutlinedButton.icon(
                  focusNode: _deleteAllButtonFocusNode,
                  onPressed: _addons.isEmpty || _isDeletingAll
                      ? null
                      : _deleteAllAddons,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                    side: BorderSide(color: theme.colorScheme.error),
                  ),
                  icon: _isDeletingAll
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.error,
                          ),
                        )
                      : const Icon(Icons.delete_sweep_outlined),
                  label: Text(_isDeletingAll ? 'Deleting' : 'Delete all'),
                ),
              ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [header, const SizedBox(height: 12), actions],
            );
          }

          return Row(
            children: [
              Expanded(child: header),
              const SizedBox(width: 12),
              actions,
            ],
          );
        },
      ),
    );
  }

  Widget _buildAddonsList() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading addons...'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                'Failed to load addons',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _loadAddons,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_addons.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(48),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.extension_outlined,
                size: 64,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                'No addons configured',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Add a manifest URL above or import your Stremio JSON export',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _addons.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Icon(
                  Icons.extension,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Your Addons',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_addons.length}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        final addon = _addons[index - 1];
        return _AddonTile(
          addon: addon,
          index: index - 1,
          focusNode: _addonFocusNodes[addon.manifestUrl]!,
          onTap: () => _showAddonDetails(addon),
          onToggle: () => _toggleAddon(addon),
          onDelete: () => _deleteAddon(addon),
        );
      },
    );
  }
}

class _StremioAddonsPageState extends State<StremioAddonsPage> {
  final StremioService _stremioService = StremioService.instance;
  final TextEditingController _urlController = TextEditingController();
  final FocusNode _urlFieldFocusNode = FocusNode(debugLabel: 'url-field');
  final FocusNode _addButtonFocusNode = FocusNode(debugLabel: 'add-button');

  bool _isLoading = true;
  bool _isAdding = false;
  String? _error;
  List<StremioAddon> _addons = [];

  // Focus nodes for addon tiles
  final Map<String, FocusNode> _addonFocusNodes = {};

  // Track focus state for URL field
  bool _urlFieldFocused = false;

  @override
  void initState() {
    super.initState();
    _urlFieldFocusNode.addListener(_onUrlFieldFocusChanged);
    _stremioService.addAddonsChangedListener(_onAddonsChanged);
    _loadAddons();
  }

  void _onAddonsChanged() {
    // Reload addons when they change (e.g., added via deep link)
    if (mounted) {
      _loadAddons();
    }
  }

  void _onUrlFieldFocusChanged() {
    setState(() {
      _urlFieldFocused = _urlFieldFocusNode.hasFocus;
    });
  }

  @override
  void dispose() {
    _stremioService.removeAddonsChangedListener(_onAddonsChanged);
    _urlController.dispose();
    _urlFieldFocusNode.removeListener(_onUrlFieldFocusChanged);
    _urlFieldFocusNode.dispose();
    _addButtonFocusNode.dispose();
    for (final node in _addonFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _loadAddons() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      _addons = await _stremioService.getAddons();

      // Clean up old focus nodes
      for (final node in _addonFocusNodes.values) {
        node.dispose();
      }
      _addonFocusNodes.clear();

      // Create focus nodes for each addon
      for (final addon in _addons) {
        _addonFocusNodes[addon.manifestUrl] = FocusNode(
          debugLabel: 'addon-${addon.id}',
        );
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _addAddon() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an addon URL')),
      );
      return;
    }

    setState(() {
      _isAdding = true;
    });

    try {
      final addon = await _stremioService.addAddon(url);

      _urlController.clear();
      // Note: _loadAddons() is called automatically via the addons changed listener

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${addon.name} added successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        // Clean up error message - remove "Exception: " prefix
        final errorMessage = e.toString().replaceFirst('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAdding = false;
        });
      }
    }
  }

  Future<void> _toggleAddon(StremioAddon addon) async {
    await _stremioService.setAddonEnabled(addon.manifestUrl, !addon.enabled);
    // Note: _loadAddons() is called automatically via the addons changed listener
  }

  Future<void> _deleteAddon(StremioAddon addon) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Addon'),
        content: Text('Remove "${addon.name}" from your addons?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _stremioService.removeAddon(addon.manifestUrl);
      // Note: _loadAddons() is called automatically via the addons changed listener

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${addon.name} removed')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to remove addon: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showAddonDetails(StremioAddon addon) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(addon.name),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (addon.description != null) ...[
                Text(addon.description!),
                const SizedBox(height: 16),
              ],
              _DetailRow(label: 'ID', value: addon.id),
              if (addon.version != null)
                _DetailRow(label: 'Version', value: addon.version!),
              _DetailRow(
                label: 'Types',
                value: addon.types.isEmpty ? 'None' : addon.types.join(', '),
              ),
              _DetailRow(
                label: 'Resources',
                value: addon.resources.isEmpty
                    ? 'None'
                    : addon.resources.join(', '),
              ),
              if (addon.idPrefixes != null && addon.idPrefixes!.isNotEmpty)
                _DetailRow(
                  label: 'ID Prefixes',
                  value: addon.idPrefixes!.join(', '),
                ),
              _DetailRow(label: 'Added', value: _formatDate(addon.addedAt)),
              if (addon.lastChecked != null)
                _DetailRow(
                  label: 'Last Checked',
                  value: _formatDate(addon.lastChecked!),
                ),
              const SizedBox(height: 16),
              const Text(
                'Manifest URL:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              SelectableText(
                addon.manifestUrl,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: addon.manifestUrl));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('URL copied to clipboard')),
              );
            },
            child: const Text('Copy URL'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stremio Addons'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _loadAddons,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    return Column(
      children: [
        // Add addon section
        _buildAddSection(),
        const Divider(height: 1),
        // Addons list
        Expanded(child: _buildAddonsList()),
      ],
    );
  }

  Widget _buildAddSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Add Stremio Addon',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Paste the addon manifest URL. Configure the addon on its website first, then paste the personalized URL here.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildUrlTextField()),
              const SizedBox(width: 12),
              FocusTraversalOrder(
                order: const NumericFocusOrder(1),
                child: FilledButton.icon(
                  focusNode: _addButtonFocusNode,
                  onPressed: _isAdding ? null : _addAddon,
                  icon: _isAdding
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.add),
                  label: const Text('Add'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUrlTextField() {
    return FocusTraversalOrder(
      order: const NumericFocusOrder(0),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: _urlFieldFocused
              ? Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                )
              : null,
        ),
        child: Shortcuts(
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.arrowDown): NextFocusIntent(),
            SingleActivator(LogicalKeyboardKey.arrowUp): PreviousFocusIntent(),
          },
          child: Actions(
            actions: <Type, Action<Intent>>{
              NextFocusIntent: CallbackAction<NextFocusIntent>(
                onInvoke: (intent) {
                  _addButtonFocusNode.requestFocus();
                  return null;
                },
              ),
              PreviousFocusIntent: CallbackAction<PreviousFocusIntent>(
                onInvoke: (intent) {
                  FocusScope.of(context).previousFocus();
                  return null;
                },
              ),
            },
            child: TextField(
              controller: _urlController,
              focusNode: _urlFieldFocusNode,
              decoration: const InputDecoration(
                hintText: 'https://addon.example.com/manifest.json',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
              ),
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _addAddon(),
              enabled: !_isAdding,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAddonsList() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading addons...'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                'Failed to load addons',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _loadAddons,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_addons.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(48),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.extension_outlined,
                size: 64,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                'No addons configured',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Add a Stremio addon URL above to get started',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _addons.length + 1, // +1 for header
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Icon(
                  Icons.extension,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Your Addons',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_addons.length}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        final addon = _addons[index - 1];
        return _AddonTile(
          addon: addon,
          index: index - 1,
          focusNode: _addonFocusNodes[addon.manifestUrl]!,
          onTap: () => _showAddonDetails(addon),
          onToggle: () => _toggleAddon(addon),
          onDelete: () => _deleteAddon(addon),
        );
      },
    );
  }
}

class _ImportResultRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? color;

  const _ImportResultRow({
    required this.icon,
    required this.label,
    required this.value,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveColor = color ?? theme.colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: effectiveColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              color: effectiveColor,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// Addon tile with DPAD focus support
class _AddonTile extends StatefulWidget {
  final StremioAddon addon;
  final int index;
  final FocusNode focusNode;
  final VoidCallback onTap;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const _AddonTile({
    required this.addon,
    required this.index,
    required this.focusNode,
    required this.onTap,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  State<_AddonTile> createState() => _AddonTileState();
}

class _AddonTileState extends State<_AddonTile> {
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChanged);
    super.dispose();
  }

  void _onFocusChanged() {
    setState(() {
      _isFocused = widget.focusNode.hasFocus;
    });
  }

  String _getAddonSubtitle(StremioAddon addon) {
    final parts = <String>[];

    if (addon.types.isNotEmpty) {
      parts.add(addon.types.join(', '));
    }

    if (addon.version != null) {
      parts.add('v${addon.version}');
    }

    if (parts.isEmpty) {
      return addon.enabled ? 'Enabled' : 'Disabled';
    }

    return parts.join(' - ');
  }

  void _showOptionsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _AddonOptionsSheet(
        addon: widget.addon,
        onToggle: () {
          Navigator.of(context).pop();
          widget.onToggle();
        },
        onDetails: () {
          Navigator.of(context).pop();
          widget.onTap();
        },
        onDelete: () {
          Navigator.of(context).pop();
          widget.onDelete();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FocusTraversalOrder(
      order: NumericFocusOrder((widget.index + 3).toDouble()),
      child: Focus(
        focusNode: widget.focusNode,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;

          // Handle Enter/Select to show options
          if (event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.select) {
            _showOptionsSheet();
            return KeyEventResult.handled;
          }

          return KeyEventResult.ignored;
        },
        child: Card(
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: _isFocused
                ? BorderSide(color: theme.colorScheme.primary, width: 2)
                : BorderSide.none,
          ),
          elevation: _isFocused ? 8 : 1,
          child: InkWell(
            onTap: _showOptionsSheet,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              decoration: _isFocused
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: theme.colorScheme.primary.withValues(alpha: 0.1),
                    )
                  : null,
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // Icon
                  CircleAvatar(
                    backgroundColor: widget.addon.enabled
                        ? theme.colorScheme.primaryContainer
                        : theme.colorScheme.surfaceContainerHighest,
                    child: Icon(
                      Icons.extension,
                      color: widget.addon.enabled
                          ? theme.colorScheme.onPrimaryContainer
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.addon.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: widget.addon.enabled
                                ? null
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _getAddonSubtitle(widget.addon),
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Status indicator
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: widget.addon.enabled
                          ? Colors.green.withValues(alpha: 0.1)
                          : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      widget.addon.enabled ? 'ON' : 'OFF',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: widget.addon.enabled
                            ? Colors.green
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet for addon options - DPAD friendly
class _AddonOptionsSheet extends StatefulWidget {
  final StremioAddon addon;
  final VoidCallback onToggle;
  final VoidCallback onDetails;
  final VoidCallback onDelete;

  const _AddonOptionsSheet({
    required this.addon,
    required this.onToggle,
    required this.onDetails,
    required this.onDelete,
  });

  @override
  State<_AddonOptionsSheet> createState() => _AddonOptionsSheetState();
}

class _AddonOptionsSheetState extends State<_AddonOptionsSheet> {
  final FocusNode _toggleFocusNode = FocusNode(debugLabel: 'toggle-option');
  final FocusNode _detailsFocusNode = FocusNode(debugLabel: 'details-option');
  final FocusNode _deleteFocusNode = FocusNode(debugLabel: 'delete-option');

  @override
  void initState() {
    super.initState();
    // Auto-focus the first option after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _toggleFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _toggleFocusNode.dispose();
    _detailsFocusNode.dispose();
    _deleteFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: widget.addon.enabled
                        ? theme.colorScheme.primary.withValues(alpha: 0.2)
                        : theme.colorScheme.onSurface.withValues(alpha: 0.1),
                    child: Icon(
                      Icons.extension,
                      color: widget.addon.enabled
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.addon.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Divider(
              height: 1,
              color: theme.dividerColor.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 8),
            // Options
            FocusTraversalOrder(
              order: const NumericFocusOrder(0),
              child: _OptionTile(
                focusNode: _toggleFocusNode,
                icon: widget.addon.enabled
                    ? Icons.toggle_off_outlined
                    : Icons.toggle_on_outlined,
                label: widget.addon.enabled ? 'Disable' : 'Enable',
                onTap: widget.onToggle,
              ),
            ),
            FocusTraversalOrder(
              order: const NumericFocusOrder(1),
              child: _OptionTile(
                focusNode: _detailsFocusNode,
                icon: Icons.info_outline,
                label: 'View Details',
                onTap: widget.onDetails,
              ),
            ),
            FocusTraversalOrder(
              order: const NumericFocusOrder(2),
              child: _OptionTile(
                focusNode: _deleteFocusNode,
                icon: Icons.delete_outline,
                label: 'Remove',
                isDestructive: true,
                onTap: widget.onDelete,
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Single option tile for the bottom sheet
class _OptionTile extends StatefulWidget {
  final FocusNode focusNode;
  final IconData icon;
  final String label;
  final bool isDestructive;
  final VoidCallback onTap;

  const _OptionTile({
    required this.focusNode,
    required this.icon,
    required this.label,
    this.isDestructive = false,
    required this.onTap,
  });

  @override
  State<_OptionTile> createState() => _OptionTileState();
}

class _OptionTileState extends State<_OptionTile> {
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChanged);
    super.dispose();
  }

  void _onFocusChanged() {
    setState(() {
      _isFocused = widget.focusNode.hasFocus;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = widget.isDestructive
        ? Colors.red.shade400
        : theme.colorScheme.onSurface;

    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;

        if (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.select) {
          widget.onTap();
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: _isFocused
              ? theme.colorScheme.onSurface.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: _isFocused
              ? Border.all(color: theme.colorScheme.primary, width: 2)
              : null,
        ),
        child: ListTile(
          leading: Icon(widget.icon, color: color),
          title: Text(widget.label, style: TextStyle(color: color)),
          onTap: widget.onTap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

/// Custom intent for moving focus to Add button
class _MoveToAddButtonIntent extends Intent {
  const _MoveToAddButtonIntent();
}

/// Custom intent for moving focus to sidebar
class _MoveToSidebarIntent extends Intent {
  const _MoveToSidebarIntent();
}
