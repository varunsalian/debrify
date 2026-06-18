import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/stremio_addon.dart';
import '../../services/main_page_bridge.dart';
import '../../services/stremio_service.dart';
import '../addons_screen.dart';
import '../../utils/tv_keys.dart';

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
  final FocusNode _updateAllButtonFocusNode = FocusNode(
    debugLabel: 'update-all-stremio-addons-content',
  );

  bool _isLoading = true;
  bool _isAdding = false;
  bool _isImporting = false;
  bool _isDeletingAll = false;
  bool _isUpdatingAll = false;
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
    _updateAllButtonFocusNode.dispose();
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

  Future<void> _updateAddon(StremioAddon addon) async {
    final messenger = ScaffoldMessenger.of(context);
    final refreshed = await _stremioService.refreshAddon(addon.manifestUrl);
    if (!mounted) return;
    if (refreshed == null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Failed to update ${addon.name}'),
          backgroundColor: Colors.red,
        ),
      );
    } else if (refreshed.version != addon.version) {
      final from = addon.version;
      final to = refreshed.version;
      final detail = (from != null && to != null) ? ' (v$from → v$to)' : '';
      messenger.showSnackBar(
        SnackBar(content: Text('${addon.name} updated$detail')),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(content: Text('${addon.name} is already up to date')),
      );
    }
  }

  Future<void> _updateAllAddons() async {
    if (_addons.isEmpty || _isUpdatingAll) return;

    setState(() => _isUpdatingAll = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await _stremioService.refreshAllAddons();
      if (!mounted) return;
      final parts = <String>[];
      if (result.updated > 0) parts.add('${result.updated} updated');
      if (result.unchanged > 0) parts.add('${result.unchanged} up to date');
      if (result.failed > 0) parts.add('${result.failed} failed');
      messenger.showSnackBar(
        SnackBar(
          content: Text(parts.isEmpty ? 'No addons to update' : parts.join('  ·  ')),
          backgroundColor: result.failed > 0 ? Colors.orange.shade800 : null,
        ),
      );
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Update failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdatingAll = false);
    }
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
      child: Stack(
        children: [
          // Cinematic gradient backdrop
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF14101C),
                    Color(0xFF0A0810),
                    Color(0xFF030305),
                  ],
                  stops: [0.0, 0.35, 1.0],
                ),
              ),
            ),
          ),
          // Indigo ambient glow (top-center)
          Positioned(
            top: -200,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: Container(
                  width: 560,
                  height: 380,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFFED1C24).withValues(alpha: 0.22),
                        const Color(0xFFED1C24).withValues(alpha: 0.06),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Content
          CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                sliver: SliverToBoxAdapter(child: _buildHeroCard()),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                sliver: SliverToBoxAdapter(child: _buildImportActionsCard()),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                sliver: _buildAddonsSliver(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeroCard() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.06),
            Colors.white.withValues(alpha: 0.02),
          ],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFED1C24).withValues(alpha: 0.08),
            blurRadius: 32,
            spreadRadius: -8,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFED1C24), Color(0xFFB81D24)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFED1C24).withValues(alpha: 0.4),
                      blurRadius: 14,
                      spreadRadius: -2,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.add_link_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Add Stremio Addon',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Paste a manifest URL to install',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final stack = constraints.maxWidth < 460;
              final input = FocusTraversalOrder(
                order: const NumericFocusOrder(0),
                child: _buildUrlField(),
              );
              final addBtn = FocusTraversalOrder(
                order: const NumericFocusOrder(1),
                child: _buildAddButton(),
              );

              if (stack) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [input, const SizedBox(height: 10), addBtn],
                );
              }
              return Row(
                children: [
                  Expanded(child: input),
                  const SizedBox(width: 10),
                  addBtn,
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildUrlField() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: _urlFieldFocused ? 0.45 : 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _urlFieldFocused
              ? const Color(0xFFED1C24).withValues(alpha: 0.9)
              : Colors.white.withValues(alpha: 0.1),
          width: _urlFieldFocused ? 2 : 1,
        ),
        boxShadow: _urlFieldFocused
            ? [
                BoxShadow(
                  color: const Color(0xFFED1C24).withValues(alpha: 0.25),
                  blurRadius: 16,
                  spreadRadius: -2,
                ),
              ]
            : null,
      ),
      child: Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.arrowDown): NextFocusIntent(),
          SingleActivator(LogicalKeyboardKey.arrowUp): PreviousFocusIntent(),
          SingleActivator(LogicalKeyboardKey.arrowRight):
              _MoveToAddButtonIntent(),
          SingleActivator(LogicalKeyboardKey.arrowLeft): _MoveToSidebarIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            NextFocusIntent: CallbackAction<NextFocusIntent>(
              onInvoke: (intent) {
                _importButtonFocusNode.requestFocus();
                return null;
              },
            ),
            PreviousFocusIntent: CallbackAction<PreviousFocusIntent>(
              onInvoke: (intent) {
                if (AddonsScreen.focusCurrentTab != null) {
                  AddonsScreen.focusCurrentTab!();
                }
                return null;
              },
            ),
            _MoveToAddButtonIntent: CallbackAction<_MoveToAddButtonIntent>(
              onInvoke: (intent) {
                _addButtonFocusNode.requestFocus();
                return null;
              },
            ),
            _MoveToSidebarIntent: CallbackAction<_MoveToSidebarIntent>(
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
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: 'https://addon.example.com/manifest.json',
              hintStyle: TextStyle(
                color: Colors.white.withValues(alpha: 0.35),
                fontSize: 13.5,
              ),
              border: InputBorder.none,
              focusedBorder: InputBorder.none,
              enabledBorder: InputBorder.none,
              prefixIcon: Icon(
                Icons.link_rounded,
                size: 18,
                color: Colors.white.withValues(alpha: 0.5),
              ),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 38,
                minHeight: 38,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 4,
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
    );
  }

  Widget _buildAddButton() {
    return _GlowFocusButton(
      focusNode: _addButtonFocusNode,
      onPressed: _isAdding ? null : _addAddon,
      gradient: const LinearGradient(
        colors: [Color(0xFFED1C24), Color(0xFFB81D24)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isAdding)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          else
            const Icon(Icons.add_rounded, color: Colors.white, size: 20),
          const SizedBox(width: 6),
          Text(
            _isAdding ? 'Adding' : 'Add',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 14,
              letterSpacing: 0.2,
              shadows: [
                Shadow(
                  color: const Color(0xFFED1C24).withValues(alpha: 0.6),
                  blurRadius: 8,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImportActionsCard() {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.04),
            Colors.white.withValues(alpha: 0.015),
          ],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.06),
          width: 1,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 560;
          final header = Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFFED1C24).withValues(alpha: 0.25),
                      const Color(0xFFB81D24).withValues(alpha: 0.15),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFFED1C24).withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Icon(
                  Icons.upload_file_rounded,
                  color: const Color(0xFFED1C24),
                  size: 22,
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
                        letterSpacing: -0.1,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Bulk-import from a Stremio JSON export, or clear all installed addons.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );

          final importBtn = FocusTraversalOrder(
            order: const NumericFocusOrder(2),
            child: _GlowFocusButton(
              focusNode: _importButtonFocusNode,
              onPressed: _isImporting ? null : _importFromJsonFile,
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFED1C24).withValues(alpha: 0.85),
                  const Color(0xFFB81D24).withValues(alpha: 0.85),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isImporting)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  else
                    const Icon(
                      Icons.file_open_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  const SizedBox(width: 6),
                  Text(
                    _isImporting ? 'Importing' : 'Import JSON',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                    ),
                  ),
                ],
              ),
            ),
          );

          final updateAllBtn = FocusTraversalOrder(
            order: const NumericFocusOrder(3),
            child: _GlowFocusButton(
              focusNode: _updateAllButtonFocusNode,
              onPressed: _addons.isEmpty || _isUpdatingAll
                  ? null
                  : _updateAllAddons,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isUpdatingAll)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFFED1C24),
                      ),
                    )
                  else
                    const Icon(
                      Icons.refresh,
                      color: Color(0xFFED1C24),
                      size: 18,
                    ),
                  const SizedBox(width: 6),
                  Text(
                    _isUpdatingAll ? 'Updating' : 'Update all',
                    style: const TextStyle(
                      color: Color(0xFFED1C24),
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                    ),
                  ),
                ],
              ),
            ),
          );

          final deleteBtn = FocusTraversalOrder(
            order: const NumericFocusOrder(4),
            child: _GlowFocusButton(
              focusNode: _deleteAllButtonFocusNode,
              onPressed: _addons.isEmpty || _isDeletingAll
                  ? null
                  : _deleteAllAddons,
              outlineColor: theme.colorScheme.error,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isDeletingAll)
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.error,
                      ),
                    )
                  else
                    Icon(
                      Icons.delete_sweep_outlined,
                      color: theme.colorScheme.error,
                      size: 18,
                    ),
                  const SizedBox(width: 6),
                  Text(
                    _isDeletingAll ? 'Deleting' : 'Delete all',
                    style: TextStyle(
                      color: theme.colorScheme.error,
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                    ),
                  ),
                ],
              ),
            ),
          );

          final actions = Wrap(
            spacing: 10,
            runSpacing: 8,
            alignment: compact ? WrapAlignment.start : WrapAlignment.end,
            children: [importBtn, updateAllBtn, deleteBtn],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [header, const SizedBox(height: 14), actions],
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

  Widget _buildAddonsSliver() {
    if (_isLoading) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(48),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Loading addons...'),
              ],
            ),
          ),
        ),
      );
    }

    if (_error != null) {
      final theme = Theme.of(context);
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 56, color: theme.colorScheme.error),
                const SizedBox(height: 12),
                Text('Failed to load addons', style: theme.textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _loadAddons,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_addons.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 36, 8, 24),
          child: Column(
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFFED1C24).withValues(alpha: 0.22),
                      const Color(0xFFED1C24).withValues(alpha: 0.04),
                    ],
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Icon(
                  Icons.extension_outlined,
                  size: 40,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'No addons yet',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Add a manifest URL above, or import\nyour Stremio JSON export to get started.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(child: _buildSectionHeader()),
        SliverList.builder(
          itemCount: _addons.length,
          itemBuilder: (context, index) {
            final addon = _addons[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _AddonTile(
                addon: addon,
                index: index,
                focusNode: _addonFocusNodes[addon.manifestUrl]!,
                onTap: () => _showAddonDetails(addon),
                onToggle: () => _toggleAddon(addon),
                onUpdate: () => _updateAddon(addon),
                onDelete: () => _deleteAddon(addon),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildSectionHeader() {
    final theme = Theme.of(context);
    final enabledCount = _addons.where((a) => a.enabled).length;
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 12),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 22,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFED1C24), Color(0xFFB81D24)],
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'Your Addons',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFED1C24).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFFED1C24).withValues(alpha: 0.25),
              ),
            ),
            child: Text(
              '${_addons.length}',
              style: TextStyle(
                color: const Color(0xFFED1C24),
                fontWeight: FontWeight.w700,
                fontSize: 11.5,
              ),
            ),
          ),
          const Spacer(),
          if (_addons.isNotEmpty)
            Text(
              '$enabledCount / ${_addons.length} active',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
              ),
            ),
        ],
      ),
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
  bool _isUpdatingAll = false;
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

  Future<void> _updateAddon(StremioAddon addon) async {
    final messenger = ScaffoldMessenger.of(context);
    final refreshed = await _stremioService.refreshAddon(addon.manifestUrl);
    if (!mounted) return;
    if (refreshed == null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Failed to update ${addon.name}'),
          backgroundColor: Colors.red,
        ),
      );
    } else if (refreshed.version != addon.version) {
      final from = addon.version;
      final to = refreshed.version;
      final detail = (from != null && to != null) ? ' (v$from → v$to)' : '';
      messenger.showSnackBar(
        SnackBar(content: Text('${addon.name} updated$detail')),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(content: Text('${addon.name} is already up to date')),
      );
    }
  }

  Future<void> _updateAllAddons() async {
    if (_addons.isEmpty || _isUpdatingAll) return;

    setState(() => _isUpdatingAll = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await _stremioService.refreshAllAddons();
      if (!mounted) return;
      final parts = <String>[];
      if (result.updated > 0) parts.add('${result.updated} updated');
      if (result.unchanged > 0) parts.add('${result.unchanged} up to date');
      if (result.failed > 0) parts.add('${result.failed} failed');
      messenger.showSnackBar(
        SnackBar(
          content: Text(parts.isEmpty ? 'No addons to update' : parts.join('  ·  ')),
          backgroundColor: result.failed > 0 ? Colors.orange.shade800 : null,
        ),
      );
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Update failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdatingAll = false);
    }
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
            onPressed: _addons.isEmpty || _isUpdatingAll
                ? null
                : _updateAllAddons,
            icon: _isUpdatingAll
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.system_update_alt),
            tooltip: 'Update all addons',
          ),
          IconButton(
            onPressed: _isLoading ? null : _loadAddons,
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload',
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
                  color: const Color(0xFFED1C24),
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
                  color: const Color(0xFFED1C24),
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
                    color: const Color(0xFFED1C24).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_addons.length}',
                    style: TextStyle(
                      color: const Color(0xFFED1C24),
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
          onUpdate: () => _updateAddon(addon),
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
  final VoidCallback onUpdate;
  final VoidCallback onDelete;

  const _AddonTile({
    required this.addon,
    required this.index,
    required this.focusNode,
    required this.onTap,
    required this.onToggle,
    required this.onUpdate,
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
        onUpdate: () {
          Navigator.of(context).pop();
          widget.onUpdate();
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
    final enabled = widget.addon.enabled;

    return FocusTraversalOrder(
      order: NumericFocusOrder((widget.index + 3).toDouble()),
      child: Focus(
        focusNode: widget.focusNode,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          if (isActivateKey(event.logicalKey)) {
            _showOptionsSheet();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          transform: Matrix4.identity()..scale(_isFocused ? 1.015 : 1.0),
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: _isFocused
                  ? [
                      const Color(0xFFED1C24).withValues(alpha: 0.18),
                      const Color(0xFFED1C24).withValues(alpha: 0.06),
                    ]
                  : [
                      Colors.white.withValues(alpha: 0.05),
                      Colors.white.withValues(alpha: 0.02),
                    ],
            ),
            border: Border.all(
              color: _isFocused
                  ? const Color(0xFFED1C24).withValues(alpha: 0.9)
                  : Colors.white.withValues(alpha: 0.07),
              width: _isFocused ? 2 : 1,
            ),
            boxShadow: _isFocused
                ? [
                    BoxShadow(
                      color: const Color(0xFFED1C24).withValues(alpha: 0.3),
                      blurRadius: 22,
                      spreadRadius: -4,
                    ),
                  ]
                : null,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _showOptionsSheet,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    // Icon avatar with gradient
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: enabled
                            ? const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color(0xFFED1C24),
                                  Color(0xFFB81D24),
                                ],
                              )
                            : LinearGradient(
                                colors: [
                                  Colors.white.withValues(alpha: 0.08),
                                  Colors.white.withValues(alpha: 0.04),
                                ],
                              ),
                        boxShadow: enabled
                            ? [
                                BoxShadow(
                                  color: const Color(
                                    0xFFED1C24,
                                  ).withValues(alpha: 0.3),
                                  blurRadius: 14,
                                  spreadRadius: -3,
                                ),
                              ]
                            : null,
                      ),
                      child: Icon(
                        Icons.extension_rounded,
                        color: enabled
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.45),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    // Info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.addon.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.1,
                              color: enabled
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.6),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _getAddonSubtitle(widget.addon),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.5),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Status pill
                    _StatusPill(enabled: enabled),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: Colors.white.withValues(alpha: 0.35),
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final bool enabled;
  const _StatusPill({required this.enabled});

  @override
  Widget build(BuildContext context) {
    final color = enabled
        ? const Color(0xFF34D399)
        : Colors.white.withValues(alpha: 0.35);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: enabled
            ? const Color(0xFF34D399).withValues(alpha: 0.14)
            : Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: enabled
              ? const Color(0xFF34D399).withValues(alpha: 0.35)
              : Colors.white.withValues(alpha: 0.12),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: enabled
                  ? [BoxShadow(color: color, blurRadius: 6)]
                  : null,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            enabled ? 'ON' : 'OFF',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: color,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet for addon options - DPAD friendly
class _AddonOptionsSheet extends StatefulWidget {
  final StremioAddon addon;
  final VoidCallback onToggle;
  final VoidCallback onUpdate;
  final VoidCallback onDetails;
  final VoidCallback onDelete;

  const _AddonOptionsSheet({
    required this.addon,
    required this.onToggle,
    required this.onUpdate,
    required this.onDetails,
    required this.onDelete,
  });

  @override
  State<_AddonOptionsSheet> createState() => _AddonOptionsSheetState();
}

class _AddonOptionsSheetState extends State<_AddonOptionsSheet> {
  final FocusNode _toggleFocusNode = FocusNode(debugLabel: 'toggle-option');
  final FocusNode _updateFocusNode = FocusNode(debugLabel: 'update-option');
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
    _updateFocusNode.dispose();
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
                        ? const Color(0xFFED1C24).withValues(alpha: 0.2)
                        : theme.colorScheme.onSurface.withValues(alpha: 0.1),
                    child: Icon(
                      Icons.extension,
                      color: widget.addon.enabled
                          ? const Color(0xFFED1C24)
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
                focusNode: _updateFocusNode,
                icon: Icons.refresh,
                label: 'Update',
                onTap: widget.onUpdate,
              ),
            ),
            FocusTraversalOrder(
              order: const NumericFocusOrder(2),
              child: _OptionTile(
                focusNode: _detailsFocusNode,
                icon: Icons.info_outline,
                label: 'View Details',
                onTap: widget.onDetails,
              ),
            ),
            FocusTraversalOrder(
              order: const NumericFocusOrder(3),
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

        if (isActivateKey(event.logicalKey)) {
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
              ? Border.all(color: const Color(0xFFED1C24), width: 2)
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

/// Pill-shaped button with focus glow used in the addons hero/import cards.
class _GlowFocusButton extends StatefulWidget {
  final FocusNode focusNode;
  final VoidCallback? onPressed;
  final Widget child;
  final Gradient? gradient;
  final Color? outlineColor;

  const _GlowFocusButton({
    required this.focusNode,
    required this.onPressed,
    required this.child,
    this.gradient,
    this.outlineColor,
  });

  @override
  State<_GlowFocusButton> createState() => _GlowFocusButtonState();
}

class _GlowFocusButtonState extends State<_GlowFocusButton> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocus);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocus);
    super.dispose();
  }

  void _onFocus() => setState(() => _focused = widget.focusNode.hasFocus);

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onPressed == null;
    final accent = widget.outlineColor ?? const Color(0xFFED1C24);

    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (isActivateKey(event.logicalKey)) {
          if (!disabled) widget.onPressed!();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          gradient: widget.gradient != null && !disabled
              ? widget.gradient
              : null,
          color: widget.gradient == null
              ? Colors.white.withValues(alpha: disabled ? 0.04 : 0.06)
              : null,
          border: Border.all(
            color: _focused
                ? accent
                : (widget.gradient != null
                      ? Colors.white.withValues(alpha: 0.0)
                      : accent.withValues(alpha: disabled ? 0.25 : 0.55)),
            width: _focused ? 2 : 1.2,
          ),
          boxShadow: _focused && !disabled
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.45),
                    blurRadius: 18,
                    spreadRadius: -2,
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: disabled ? null : widget.onPressed,
            borderRadius: BorderRadius.circular(999),
            child: Opacity(
              opacity: disabled ? 0.5 : 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 11,
                ),
                child: widget.child,
              ),
            ),
          ),
        ),
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
