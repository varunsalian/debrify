import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/engine/remote_engine_manager.dart';
import '../../services/engine/local_engine_storage.dart';
import '../../services/engine/config_loader.dart';
import '../../services/engine/engine_registry.dart';

/// Page for importing and managing torrent search engines
class EngineImportPage extends StatefulWidget {
  const EngineImportPage({super.key});

  @override
  State<EngineImportPage> createState() => _EngineImportPageState();
}

class _EngineImportPageState extends State<EngineImportPage> {
  final RemoteEngineManager _remoteManager = RemoteEngineManager();
  final LocalEngineStorage _localStorage = LocalEngineStorage.instance;

  bool _isLoading = true;
  String? _error;

  List<ImportedEngineMetadata> _importedEngines = [];
  List<RemoteEngineInfo> _availableEngines = [];

  // Focus nodes for TV/DPAD navigation
  final FocusNode _refreshButtonFocusNode = FocusNode(debugLabel: 'refresh-button');
  final FocusNode _retryButtonFocusNode = FocusNode(debugLabel: 'retry-button');
  final Map<String, FocusNode> _importedEngineFocusNodes = {};
  final Map<String, FocusNode> _availableEngineFocusNodes = {};

  @override
  void initState() {
    super.initState();
    _loadEngines();
  }

  @override
  void dispose() {
    _remoteManager.dispose();
    _refreshButtonFocusNode.dispose();
    _retryButtonFocusNode.dispose();
    for (final node in _importedEngineFocusNodes.values) {
      node.dispose();
    }
    for (final node in _availableEngineFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _loadEngines() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Load imported engines from local storage
      _importedEngines = await _localStorage.getImportedEngines();

      // Fetch available engines from GitLab
      final remoteEngines = await _remoteManager.fetchAvailableEngines();

      // Filter out already imported engines
      final importedIds = _importedEngines.map((e) => e.id).toSet();
      _availableEngines = remoteEngines
          .where((e) => !importedIds.contains(e.id))
          .toList();

      // Clean up old focus nodes
      for (final node in _importedEngineFocusNodes.values) {
        node.dispose();
      }
      for (final node in _availableEngineFocusNodes.values) {
        node.dispose();
      }
      _importedEngineFocusNodes.clear();
      _availableEngineFocusNodes.clear();

      // Create focus nodes for each engine
      for (final engine in _importedEngines) {
        _importedEngineFocusNodes[engine.id] = FocusNode(debugLabel: 'imported-${engine.id}');
      }
      for (final engine in _availableEngines) {
        _availableEngineFocusNodes[engine.id] = FocusNode(debugLabel: 'available-${engine.id}');
      }

      setState(() {
        _isLoading = false;
      });

      // Auto-focus first item after load
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          if (_importedEngines.isNotEmpty) {
            _importedEngineFocusNodes[_importedEngines.first.id]?.requestFocus();
          } else if (_availableEngines.isNotEmpty) {
            _availableEngineFocusNodes[_availableEngines.first.id]?.requestFocus();
          }
        }
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
      // Auto-focus retry button on error
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _retryButtonFocusNode.requestFocus();
        }
      });
    }
  }

  Future<void> _importEngine(RemoteEngineInfo engine) async {
    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Text('Importing ${engine.displayName}...'),
          ],
        ),
      ),
    );

    try {
      // Download YAML from GitLab
      final yamlContent = await _remoteManager.downloadEngineYaml(engine.fileName);

      if (yamlContent == null) {
        throw Exception('Failed to download engine configuration');
      }

      // Save to local storage
      await _localStorage.saveEngine(
        engineId: engine.id,
        fileName: engine.fileName,
        yamlContent: yamlContent,
        displayName: engine.displayName,
        icon: engine.icon,
      );

      // Reload ConfigLoader to pick up new engine
      ConfigLoader().clearCache();
      await EngineRegistry.instance.reload();

      // Close loading dialog
      if (mounted) Navigator.of(context).pop();

      // Refresh the list
      await _loadEngines();

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${engine.displayName} imported successfully')),
        );
      }
    } catch (e) {
      // Close loading dialog
      if (mounted) Navigator.of(context).pop();

      // Show error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to import: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteEngine(ImportedEngineMetadata engine) async {
    // Confirm deletion
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Engine'),
        content: Text('Are you sure you want to delete ${engine.displayName}?'),
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
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _localStorage.deleteEngine(engine.id);

      // Reload ConfigLoader to reflect deletion
      ConfigLoader().clearCache();
      await EngineRegistry.instance.reload();

      // Refresh the list
      await _loadEngines();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${engine.displayName} deleted')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  IconData _getIconForEngine(String? iconName) {
    switch (iconName) {
      case 'sailing':
        return Icons.sailing;
      case 'storage':
        return Icons.storage;
      case 'movie':
        return Icons.movie;
      case 'tv':
        return Icons.tv;
      case 'cloud':
        return Icons.cloud;
      case 'search':
        return Icons.search;
      case 'database':
        return Icons.storage;
      default:
        return Icons.extension;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Import Engines'),
        actions: [
          IconButton(
            focusNode: _refreshButtonFocusNode,
            onPressed: _isLoading ? null : _loadEngines,
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
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading engines...'),
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
                'Failed to load engines',
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
              FocusTraversalOrder(
                order: const NumericFocusOrder(0),
                child: FilledButton.icon(
                  focusNode: _retryButtonFocusNode,
                  onPressed: _loadEngines,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Imported engines section
        if (_importedEngines.isNotEmpty) ...[
          _buildSectionHeader(
            'Imported Engines',
            Icons.check_circle,
            Colors.green,
          ),
          const SizedBox(height: 8),
          for (int i = 0; i < _importedEngines.length; i++)
            _buildImportedEngineTile(_importedEngines[i], i),
          const SizedBox(height: 24),
        ],

        // Available engines section
        if (_availableEngines.isNotEmpty) ...[
          _buildSectionHeader(
            'Available to Import',
            Icons.download,
            Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 8),
          for (int i = 0; i < _availableEngines.length; i++)
            _buildAvailableEngineTile(_availableEngines[i], i),
        ],

        // Empty state
        if (_importedEngines.isEmpty && _availableEngines.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(48),
              child: Column(
                children: [
                  Icon(
                    Icons.inbox_outlined,
                    size: 64,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No engines available',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Check your internet connection and try again',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            title.contains('Imported')
                ? '${_importedEngines.length}'
                : '${_availableEngines.length}',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildImportedEngineTile(ImportedEngineMetadata engine, int index) {
    final focusNode = _importedEngineFocusNodes[engine.id];
    return FocusTraversalOrder(
      order: NumericFocusOrder(index.toDouble()),
      child: _TvFocusableCard(
        focusNode: focusNode,
        onPressed: () => _deleteEngine(engine),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: Colors.green.withValues(alpha: 0.1),
                child: Icon(
                  _getIconForEngine(engine.icon),
                  color: Colors.green,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      engine.displayName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Imported ${_formatDate(engine.importedAt)}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.delete_outline,
                color: Colors.red.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvailableEngineTile(RemoteEngineInfo engine, int index) {
    final focusNode = _availableEngineFocusNodes[engine.id];
    // Offset by imported engines count for proper traversal order
    final orderIndex = _importedEngines.length + index;
    return FocusTraversalOrder(
      order: NumericFocusOrder(orderIndex.toDouble()),
      child: _TvFocusableCard(
        focusNode: focusNode,
        onPressed: () => _importEngine(engine),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Icon(
                  _getIconForEngine(engine.icon),
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      engine.displayName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (engine.description != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        engine.description!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Import',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return 'today';
    } else if (diff.inDays == 1) {
      return 'yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}

/// A TV-friendly focusable card widget with visual focus indication
class _TvFocusableCard extends StatefulWidget {
  const _TvFocusableCard({
    required this.focusNode,
    required this.onPressed,
    required this.child,
  });

  final FocusNode? focusNode;
  final VoidCallback onPressed;
  final Widget child;

  @override
  State<_TvFocusableCard> createState() => _TvFocusableCardState();
}

class _TvFocusableCardState extends State<_TvFocusableCard> {
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode?.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    widget.focusNode?.removeListener(_handleFocusChange);
    super.dispose();
  }

  @override
  void didUpdateWidget(_TvFocusableCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode?.removeListener(_handleFocusChange);
      widget.focusNode?.addListener(_handleFocusChange);
    }
  }

  void _handleFocusChange() {
    if (mounted) {
      setState(() {
        _isFocused = widget.focusNode?.hasFocus ?? false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              HapticFeedback.lightImpact();
              widget.onPressed();
              return null;
            },
          ),
        },
        child: Focus(
          focusNode: widget.focusNode,
          child: GestureDetector(
            onTap: widget.onPressed,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _isFocused
                      ? theme.colorScheme.primary
                      : Colors.transparent,
                  width: 2,
                ),
                boxShadow: _isFocused
                    ? [
                        BoxShadow(
                          color: theme.colorScheme.primary.withValues(alpha: 0.3),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}
