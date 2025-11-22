import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    _loadEngines();
  }

  @override
  void dispose() {
    _remoteManager.dispose();
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
            onPressed: _isLoading ? null : _loadEngines,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _buildBody(),
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
              FilledButton.icon(
                onPressed: _loadEngines,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
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
          ..._importedEngines.map((engine) => _buildImportedEngineTile(engine)),
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
          ..._availableEngines.map((engine) => _buildAvailableEngineTile(engine)),
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

  Widget _buildImportedEngineTile(ImportedEngineMetadata engine) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.green.withValues(alpha: 0.1),
          child: Icon(
            _getIconForEngine(engine.icon),
            color: Colors.green,
          ),
        ),
        title: Text(engine.displayName),
        subtitle: Text(
          'Imported ${_formatDate(engine.importedAt)}',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
        trailing: IconButton(
          onPressed: () => _deleteEngine(engine),
          icon: const Icon(Icons.delete_outline),
          color: Colors.red,
          tooltip: 'Delete',
        ),
      ),
    );
  }

  Widget _buildAvailableEngineTile(RemoteEngineInfo engine) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Icon(
            _getIconForEngine(engine.icon),
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
        title: Text(engine.displayName),
        subtitle: engine.description != null
            ? Text(
                engine.description!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              )
            : null,
        trailing: FilledButton.tonal(
          onPressed: () => _importEngine(engine),
          child: const Text('Import'),
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
