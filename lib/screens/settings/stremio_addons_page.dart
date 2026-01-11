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

  // Quick add chip focus nodes
  final FocusNode _torrentioChipFocusNode = FocusNode(debugLabel: 'torrentio-chip');
  final FocusNode _piratebayChipFocusNode = FocusNode(debugLabel: 'piratebay-chip');
  final FocusNode _cometChipFocusNode = FocusNode(debugLabel: 'comet-chip');

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
    _loadAddons();
  }

  void _onUrlFieldFocusChanged() {
    setState(() {
      _urlFieldFocused = _urlFieldFocusNode.hasFocus;
    });
  }

  @override
  void dispose() {
    _urlController.dispose();
    _urlFieldFocusNode.removeListener(_onUrlFieldFocusChanged);
    _urlFieldFocusNode.dispose();
    _addButtonFocusNode.dispose();
    _torrentioChipFocusNode.dispose();
    _piratebayChipFocusNode.dispose();
    _cometChipFocusNode.dispose();
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
                child: _buildUrlTextField(),
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
          // Quick add buttons for popular addons
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FocusTraversalOrder(
                order: const NumericFocusOrder(2),
                child: _QuickAddChip(
                  label: 'Torrentio',
                  focusNode: _torrentioChipFocusNode,
                  onTap: () => _openQuickAddInfo(
                    'Torrentio',
                    'https://torrentio.strem.fun/configure',
                    'Configure your debrid service and preferences, then copy the manifest URL.',
                  ),
                ),
              ),
              FocusTraversalOrder(
                order: const NumericFocusOrder(3),
                child: _QuickAddChip(
                  label: 'ThePirateBay+',
                  focusNode: _piratebayChipFocusNode,
                  onTap: () {
                    _urlController.text =
                        'https://thepiratebay-plus.strem.fun/manifest.json';
                    _urlFieldFocusNode.requestFocus();
                  },
                ),
              ),
              FocusTraversalOrder(
                order: const NumericFocusOrder(4),
                child: _QuickAddChip(
                  label: 'Comet',
                  focusNode: _cometChipFocusNode,
                  onTap: () => _openQuickAddInfo(
                    'Comet',
                    'https://comet.elfhosted.com/configure',
                    'Configure your debrid service, then copy the manifest URL.',
                  ),
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
        return _AddonTile(
          addon: addon,
          index: index - 1,
          focusNode: _addonFocusNodes[addon.manifestUrl]!,
          onTap: () => _showAddonDetails(addon),
          onToggle: () => _toggleAddon(addon),
          onRefresh: () => _refreshAddon(addon),
          onDelete: () => _deleteAddon(addon),
        );
      },
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
  final VoidCallback onRefresh;
  final VoidCallback onDelete;

  const _AddonTile({
    required this.addon,
    required this.index,
    required this.focusNode,
    required this.onTap,
    required this.onToggle,
    required this.onRefresh,
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FocusTraversalOrder(
      order: NumericFocusOrder((widget.index + 5).toDouble()), // Start after chips
      child: Focus(
        focusNode: widget.focusNode,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;

          // Handle Enter/Select to show details
          if (event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.select) {
            widget.onTap();
            return KeyEventResult.handled;
          }

          return KeyEventResult.ignored;
        },
        child: Card(
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: _isFocused
                ? BorderSide(
                    color: theme.colorScheme.primary,
                    width: 2,
                  )
                : BorderSide.none,
          ),
          elevation: _isFocused ? 8 : 1,
          child: InkWell(
            onTap: widget.onTap,
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
                      _getIconForAddon(widget.addon),
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
                  // Actions
                  IconButton(
                    onPressed: widget.onRefresh,
                    icon: const Icon(Icons.refresh, size: 20),
                    tooltip: 'Refresh',
                  ),
                  Switch(
                    value: widget.addon.enabled,
                    onChanged: (_) => widget.onToggle(),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'delete') {
                        widget.onDelete();
                      } else if (value == 'details') {
                        widget.onTap();
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
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }
}

class _QuickAddChip extends StatefulWidget {
  final String label;
  final FocusNode focusNode;
  final VoidCallback onTap;

  const _QuickAddChip({
    required this.label,
    required this.focusNode,
    required this.onTap,
  });

  @override
  State<_QuickAddChip> createState() => _QuickAddChipState();
}

class _QuickAddChipState extends State<_QuickAddChip> {
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
      child: ActionChip(
        label: Text(widget.label),
        avatar: const Icon(Icons.add, size: 16),
        onPressed: widget.onTap,
        side: _isFocused
            ? BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 2,
              )
            : null,
        backgroundColor: _isFocused
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
            : null,
      ),
    );
  }
}
