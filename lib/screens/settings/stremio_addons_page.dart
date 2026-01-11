import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/stremio_addon.dart';
import '../../services/stremio_service.dart';

/// Page for managing Stremio addons
class StremioAddonsPage extends StatefulWidget {
  const StremioAddonsPage({super.key});

  @override
  State<StremioAddonsPage> createState() => _StremioAddonsPageState();
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

  @override
  void initState() {
    super.initState();
    _loadAddons();
  }

  @override
  void dispose() {
    _urlController.dispose();
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
        _addonFocusNodes[addon.manifestUrl] =
            FocusNode(debugLabel: 'addon-${addon.id}');
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
      await _loadAddons();

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
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
          ),
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
    await _loadAddons();
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
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _stremioService.removeAddon(addon.manifestUrl);
      await _loadAddons();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${addon.name} removed')),
        );
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

  Future<void> _refreshAddon(StremioAddon addon) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Text('Refreshing ${addon.name}...'),
          ],
        ),
      ),
    );

    try {
      final updated = await _stremioService.refreshAddon(addon.manifestUrl);
      if (mounted) Navigator.of(context).pop();

      if (updated != null) {
        await _loadAddons();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${updated.name} refreshed')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to refresh addon'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
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
              _DetailRow(
                label: 'Added',
                value: _formatDate(addon.addedAt),
              ),
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
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
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
              Expanded(
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
              const SizedBox(width: 12),
              FilledButton.icon(
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
            ],
          ),
          const SizedBox(height: 12),
          // Quick add buttons for popular addons
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _QuickAddChip(
                label: 'Torrentio',
                onTap: () => _openQuickAddInfo(
                  'Torrentio',
                  'https://torrentio.strem.fun/configure',
                  'Configure your debrid service and preferences, then copy the manifest URL.',
                ),
              ),
              _QuickAddChip(
                label: 'ThePirateBay+',
                onTap: () {
                  _urlController.text =
                      'https://thepiratebay-plus.strem.fun/manifest.json';
                },
              ),
              _QuickAddChip(
                label: 'Comet',
                onTap: () => _openQuickAddInfo(
                  'Comet',
                  'https://comet.elfhosted.com/configure',
                  'Configure your debrid service, then copy the manifest URL.',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _openQuickAddInfo(String name, String configUrl, String instructions) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add $name'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(instructions),
            const SizedBox(height: 16),
            const Text(
              'Configuration URL:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            SelectableText(
              configUrl,
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: configUrl));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('URL copied to clipboard')),
              );
            },
            child: const Text('Copy URL'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it'),
          ),
        ],
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
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.1),
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
        return _buildAddonTile(addon, index - 1);
      },
    );
  }

  Widget _buildAddonTile(StremioAddon addon, int index) {
    final focusNode = _addonFocusNodes[addon.manifestUrl];
    final theme = Theme.of(context);

    return FocusTraversalOrder(
      order: NumericFocusOrder(index.toDouble()),
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: InkWell(
          focusNode: focusNode,
          onTap: () => _showAddonDetails(addon),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Icon
                CircleAvatar(
                  backgroundColor: addon.enabled
                      ? theme.colorScheme.primaryContainer
                      : theme.colorScheme.surfaceContainerHighest,
                  child: Icon(
                    _getIconForAddon(addon),
                    color: addon.enabled
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
                        addon.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: addon.enabled
                              ? null
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _getAddonSubtitle(addon),
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                // Actions
                IconButton(
                  onPressed: () => _refreshAddon(addon),
                  icon: const Icon(Icons.refresh, size: 20),
                  tooltip: 'Refresh',
                ),
                Switch(
                  value: addon.enabled,
                  onChanged: (_) => _toggleAddon(addon),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'delete') {
                      _deleteAddon(addon);
                    } else if (value == 'details') {
                      _showAddonDetails(addon);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'details',
                      child: ListTile(
                        leading: Icon(Icons.info_outline),
                        title: Text('Details'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        leading: Icon(Icons.delete_outline, color: Colors.red),
                        title: Text('Remove', style: TextStyle(color: Colors.red)),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _getIconForAddon(StremioAddon addon) {
    final name = addon.name.toLowerCase();
    if (name.contains('torrentio')) return Icons.tornado;
    if (name.contains('piratebay') || name.contains('pirate')) return Icons.sailing;
    if (name.contains('comet')) return Icons.rocket_launch;
    if (name.contains('mediafusion')) return Icons.merge;
    if (name.contains('aio')) return Icons.all_inclusive;
    return Icons.extension;
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
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }
}

class _QuickAddChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _QuickAddChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      avatar: const Icon(Icons.add, size: 16),
      onPressed: onTap,
    );
  }
}
