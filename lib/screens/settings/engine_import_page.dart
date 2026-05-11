import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:yaml/yaml.dart';
import '../../services/engine/remote_engine_manager.dart';
import '../../services/engine/local_engine_storage.dart';
import '../../services/engine/config_loader.dart';
import '../../services/engine/engine_registry.dart';

/// Page for importing and managing torrent search engines (with Scaffold wrapper)
class EngineImportPage extends StatefulWidget {
  const EngineImportPage({super.key});

  @override
  State<EngineImportPage> createState() => _EngineImportPageState();
}

/// Content widget for embedding in tabs (without Scaffold)
class EngineImportPageContent extends StatefulWidget {
  const EngineImportPageContent({super.key});

  @override
  State<EngineImportPageContent> createState() => _EngineImportPageContentState();
}

class _EngineImportPageContentState extends State<EngineImportPageContent> {
  final RemoteEngineManager _remoteManager = RemoteEngineManager();
  final LocalEngineStorage _localStorage = LocalEngineStorage.instance;

  bool _isLoading = true;
  String? _error;

  List<ImportedEngineMetadata> _importedEngines = [];
  List<RemoteEngineInfo> _availableEngines = [];

  final FocusNode _retryButtonFocusNode = FocusNode(debugLabel: 'retry-button-content');
  final FocusNode _importLocalButtonFocusNode = FocusNode(debugLabel: 'import-local-button-content');
  final FocusNode _refreshButtonFocusNode = FocusNode(debugLabel: 'refresh-button-content');
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
    _retryButtonFocusNode.dispose();
    _importLocalButtonFocusNode.dispose();
    _refreshButtonFocusNode.dispose();
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
      _importedEngines = await _localStorage.getImportedEngines();
      final remoteEngines = await _remoteManager.fetchAvailableEngines();
      final importedIds = _importedEngines.map((e) => e.id).toSet();
      _availableEngines = remoteEngines.where((e) => !importedIds.contains(e.id)).toList();

      for (final node in _importedEngineFocusNodes.values) {
        node.dispose();
      }
      for (final node in _availableEngineFocusNodes.values) {
        node.dispose();
      }
      _importedEngineFocusNodes.clear();
      _availableEngineFocusNodes.clear();

      for (final engine in _importedEngines) {
        _importedEngineFocusNodes[engine.id] = FocusNode(debugLabel: 'imported-${engine.id}');
      }
      for (final engine in _availableEngines) {
        _availableEngineFocusNodes[engine.id] = FocusNode(debugLabel: 'available-${engine.id}');
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

  Future<void> _importEngine(RemoteEngineInfo engine) async {
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
      final yamlContent = await _remoteManager.downloadEngineYaml(engine.fileName);
      if (yamlContent == null) {
        throw Exception('Failed to download engine configuration');
      }

      await _localStorage.saveEngine(
        engineId: engine.id,
        fileName: engine.fileName,
        yamlContent: yamlContent,
        displayName: engine.displayName,
        icon: engine.icon,
      );

      ConfigLoader().clearCache();
      await EngineRegistry.instance.reload();

      if (mounted) Navigator.of(context).pop();
      await _loadEngines();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${engine.displayName} imported successfully')),
        );
      }
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to import: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteEngine(ImportedEngineMetadata engine) async {
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
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _localStorage.deleteEngine(engine.id);
      ConfigLoader().clearCache();
      await EngineRegistry.instance.reload();
      await _loadEngines();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${engine.displayName} deleted')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _importFromLocalFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        return;
      }

      final file = result.files.first;

      final fileName = file.name.toLowerCase();
      if (!fileName.endsWith('.yaml') && !fileName.endsWith('.yml')) {
        throw Exception('Please select a YAML file (.yaml or .yml)');
      }

      final String yamlContent;
      if (file.bytes != null) {
        yamlContent = String.fromCharCodes(file.bytes!);
      } else if (file.path != null) {
        final fileBytes = await file.xFile.readAsBytes();
        yamlContent = String.fromCharCodes(fileBytes);
      } else {
        throw Exception('Could not read file content');
      }

      final yaml = loadYaml(yamlContent);
      if (yaml == null) {
        throw Exception('Invalid YAML file');
      }

      final engineId = yaml['id'] as String?;
      final displayName = yaml['display_name'] as String?;
      final icon = yaml['icon'] as String?;

      if (engineId == null || engineId.isEmpty) {
        throw Exception('YAML file must contain an "id" field');
      }

      if (displayName == null || displayName.isEmpty) {
        throw Exception('YAML file must contain a "display_name" field');
      }

      final existingEngines = await _localStorage.getImportedEngines();
      final alreadyExists = existingEngines.any((e) => e.id == engineId);

      if (alreadyExists) {
        if (!mounted) return;

        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Engine Already Exists'),
            content: Text('An engine with ID "$engineId" already exists. Do you want to replace it?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Replace'),
              ),
            ],
          ),
        );

        if (confirmed != true) return;
      }

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            content: Row(
              children: [
                const CircularProgressIndicator(),
                const SizedBox(width: 16),
                Text('Importing $displayName...'),
              ],
            ),
          ),
        );
      }

      await _localStorage.saveEngine(
        engineId: engineId,
        fileName: file.name,
        yamlContent: yamlContent,
        displayName: displayName,
        icon: icon,
      );

      ConfigLoader().clearCache();
      await EngineRegistry.instance.reload();

      if (mounted) Navigator.of(context).pop();

      await _loadEngines();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$displayName imported successfully')),
        );
      }
    } catch (e) {
      if (mounted && Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to import: $e'), backgroundColor: Colors.red),
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
      case 'movie_creation':
        return Icons.movie;
      case 'tv':
        return Icons.tv;
      case 'cloud':
        return Icons.cloud;
      case 'search':
        return Icons.search;
      case 'database':
        return Icons.storage;
      case 'public':
        return Icons.public;
      default:
        return Icons.extension;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: Stack(
        children: [
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
          _buildBody(),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFFED1C24)),
            SizedBox(height: 16),
            Text(
              'Loading engines...',
              style: TextStyle(color: Colors.white70),
            ),
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
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                size: 56,
                color: Color(0xFFED1C24),
              ),
              const SizedBox(height: 12),
              const Text(
                'Failed to load engines',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
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
              _EnginePillButton(
                focusNode: _retryButtonFocusNode,
                onPressed: _loadEngines,
                icon: Icons.refresh_rounded,
                label: 'Retry',
                filled: true,
              ),
            ],
          ),
        ),
      );
    }

    final showEmpty = _importedEngines.isEmpty && _availableEngines.isEmpty;

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          sliver: SliverToBoxAdapter(child: _buildActionButtonsHeader()),
        ),
        if (showEmpty)
          SliverToBoxAdapter(child: _buildEmptyState())
        else ...[
          if (_importedEngines.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              sliver: SliverToBoxAdapter(
                child: _buildSectionHeader(
                  'Imported Engines',
                  const Color(0xFF34D399),
                  _importedEngines.length,
                ),
              ),
            ),
          if (_importedEngines.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              sliver: SliverList.builder(
                itemCount: _importedEngines.length,
                itemBuilder: (context, i) =>
                    _buildImportedEngineTile(_importedEngines[i], i),
              ),
            ),
          if (_availableEngines.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              sliver: SliverToBoxAdapter(
                child: _buildSectionHeader(
                  'Available to Import',
                  const Color(0xFFED1C24),
                  _availableEngines.length,
                ),
              ),
            ),
          if (_availableEngines.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              sliver: SliverList.builder(
                itemCount: _availableEngines.length,
                itemBuilder: (context, i) =>
                    _buildAvailableEngineTile(_availableEngines[i], i),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildEmptyState() {
    return Padding(
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
              Icons.inbox_outlined,
              size: 40,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'No engines available',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Check your internet connection and try again,\nor import an engine YAML manually.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtonsHeader() {
    return Row(
      children: [
        Expanded(
          child: _EnginePillButton(
            focusNode: _importLocalButtonFocusNode,
            onPressed: _importFromLocalFile,
            icon: Icons.folder_open_rounded,
            label: 'Import from File',
            filled: true,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _EnginePillButton(
            focusNode: _refreshButtonFocusNode,
            onPressed: _loadEngines,
            icon: Icons.refresh_rounded,
            label: 'Refresh',
            filled: false,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, Color color, int count) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 10),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 22,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  color,
                  color.withValues(alpha: 0.6),
                ],
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: const TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: color.withValues(alpha: 0.3),
              ),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 11.5,
              ),
            ),
          ),
        ],
      ),
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
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF34D399), Color(0xFF10B981)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF34D399).withValues(alpha: 0.3),
                      blurRadius: 14,
                      spreadRadius: -3,
                    ),
                  ],
                ),
                child: Icon(
                  _getIconForEngine(engine.icon),
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      engine.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.1,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Imported ${_formatDate(engine.importedAt)}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFED1C24).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFFED1C24).withValues(alpha: 0.3),
                  ),
                ),
                child: const Icon(
                  Icons.delete_outline_rounded,
                  color: Color(0xFFED1C24),
                  size: 18,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvailableEngineTile(RemoteEngineInfo engine, int index) {
    final focusNode = _availableEngineFocusNodes[engine.id];
    final orderIndex = _importedEngines.length + index;
    return FocusTraversalOrder(
      order: NumericFocusOrder(orderIndex.toDouble()),
      child: _TvFocusableCard(
        focusNode: focusNode,
        onPressed: () => _importEngine(engine),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFED1C24), Color(0xFFB81D24)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFED1C24).withValues(alpha: 0.3),
                      blurRadius: 14,
                      spreadRadius: -3,
                    ),
                  ],
                ),
                child: Icon(
                  _getIconForEngine(engine.icon),
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      engine.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.1,
                      ),
                    ),
                    if (engine.description != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        engine.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFED1C24), Color(0xFFB81D24)],
                  ),
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFED1C24).withValues(alpha: 0.4),
                      blurRadius: 12,
                      spreadRadius: -2,
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.download_rounded,
                      color: Colors.white,
                      size: 14,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Import',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
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
    if (diff.inDays == 0) return 'today';
    if (diff.inDays == 1) return 'yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${date.day}/${date.month}/${date.year}';
  }
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
  final FocusNode _importLocalButtonFocusNode = FocusNode(debugLabel: 'import-local-button');
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
    _importLocalButtonFocusNode.dispose();
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

  Future<void> _importFromLocalFile() async {
    try {
      // Pick YAML file - use FileType.any for better Android compatibility
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
        withData: true, // Loads file bytes directly (works better on Android)
      );

      if (result == null || result.files.isEmpty) {
        return; // User cancelled
      }

      final file = result.files.first;

      // Validate file extension
      final fileName = file.name.toLowerCase();
      if (!fileName.endsWith('.yaml') && !fileName.endsWith('.yml')) {
        throw Exception('Please select a YAML file (.yaml or .yml)');
      }

      // Read file contents (prefer bytes if available, otherwise read from path)
      final String yamlContent;
      if (file.bytes != null) {
        yamlContent = String.fromCharCodes(file.bytes!);
      } else if (file.path != null) {
        final fileBytes = await file.xFile.readAsBytes();
        yamlContent = String.fromCharCodes(fileBytes);
      } else {
        throw Exception('Could not read file content');
      }

      // Parse YAML to extract metadata
      final yaml = loadYaml(yamlContent);
      if (yaml == null) {
        throw Exception('Invalid YAML file');
      }

      final engineId = yaml['id'] as String?;
      final displayName = yaml['display_name'] as String?;
      final icon = yaml['icon'] as String?;

      if (engineId == null || engineId.isEmpty) {
        throw Exception('YAML file must contain an "id" field');
      }

      if (displayName == null || displayName.isEmpty) {
        throw Exception('YAML file must contain a "display_name" field');
      }

      // Check if engine already exists
      final existingEngines = await _localStorage.getImportedEngines();
      final alreadyExists = existingEngines.any((e) => e.id == engineId);

      if (alreadyExists) {
        if (!mounted) return;

        // Confirm overwrite
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Engine Already Exists'),
            content: Text('An engine with ID "$engineId" already exists. Do you want to replace it?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Replace'),
              ),
            ],
          ),
        );

        if (confirmed != true) return;
      }

      // Show loading indicator
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            content: Row(
              children: [
                const CircularProgressIndicator(),
                const SizedBox(width: 16),
                Text('Importing $displayName...'),
              ],
            ),
          ),
        );
      }

      // Save to local storage
      await _localStorage.saveEngine(
        engineId: engineId,
        fileName: file.name,
        yamlContent: yamlContent,
        displayName: displayName,
        icon: icon,
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
          SnackBar(content: Text('$displayName imported successfully')),
        );
      }
    } catch (e) {
      // Close loading dialog if open
      if (mounted && Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }

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

  IconData _getIconForEngine(String? iconName) {
    switch (iconName) {
      case 'sailing':
        return Icons.sailing;
      case 'storage':
        return Icons.storage;
      case 'movie':
      case 'movie_creation':
        return Icons.movie;
      case 'tv':
        return Icons.tv;
      case 'cloud':
        return Icons.cloud;
      case 'search':
        return Icons.search;
      case 'database':
        return Icons.storage;
      case 'public':
        return Icons.public;
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
            focusNode: _importLocalButtonFocusNode,
            onPressed: _isLoading ? null : _importFromLocalFile,
            icon: const Icon(Icons.folder_open),
            tooltip: 'Import from Local File',
          ),
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
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              transform: Matrix4.identity()..scale(_isFocused ? 1.015 : 1.0),
              transformAlignment: Alignment.center,
              margin: const EdgeInsets.only(bottom: 10),
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
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Pill-shaped action button with focus glow used in the engine page header.
class _EnginePillButton extends StatefulWidget {
  final FocusNode focusNode;
  final VoidCallback onPressed;
  final IconData icon;
  final String label;
  final bool filled;

  const _EnginePillButton({
    required this.focusNode,
    required this.onPressed,
    required this.icon,
    required this.label,
    required this.filled,
  });

  @override
  State<_EnginePillButton> createState() => _EnginePillButtonState();
}

class _EnginePillButtonState extends State<_EnginePillButton> {
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
    const accent = Color(0xFFED1C24);
    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.select) {
          widget.onPressed();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          gradient: widget.filled
              ? const LinearGradient(
                  colors: [accent, Color(0xFFB81D24)],
                )
              : null,
          color: widget.filled ? null : Colors.white.withValues(alpha: 0.04),
          border: Border.all(
            color: _focused
                ? Colors.white.withValues(alpha: 0.95)
                : (widget.filled
                      ? Colors.transparent
                      : accent.withValues(alpha: 0.55)),
            width: _focused ? 2 : 1.2,
          ),
          boxShadow: _focused || widget.filled
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: _focused ? 0.55 : 0.3),
                    blurRadius: _focused ? 20 : 14,
                    spreadRadius: _focused ? -2 : -3,
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onPressed,
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    widget.icon,
                    size: 18,
                    color: widget.filled ? Colors.white : accent,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: widget.filled ? Colors.white : accent,
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                        letterSpacing: 0.1,
                      ),
                    ),
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
