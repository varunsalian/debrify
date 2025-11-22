import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Metadata for an imported engine
class ImportedEngineMetadata {
  final String id;
  final String fileName;
  final String displayName;
  final DateTime importedAt;
  final String? icon;

  const ImportedEngineMetadata({
    required this.id,
    required this.fileName,
    required this.displayName,
    required this.importedAt,
    this.icon,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'fileName': fileName,
        'displayName': displayName,
        'importedAt': importedAt.toIso8601String(),
        'icon': icon,
      };

  factory ImportedEngineMetadata.fromJson(Map<String, dynamic> json) {
    return ImportedEngineMetadata(
      id: json['id'] as String,
      fileName: json['fileName'] as String,
      displayName: json['displayName'] as String,
      importedAt: DateTime.parse(json['importedAt'] as String),
      icon: json['icon'] as String?,
    );
  }
}

/// Manages local storage of imported engine YAML files
class LocalEngineStorage {
  static const String _enginesDirName = 'engines';
  static const String _metadataFileName = 'metadata.json';

  static LocalEngineStorage? _instance;
  static LocalEngineStorage get instance => _instance ??= LocalEngineStorage._();

  LocalEngineStorage._();

  Directory? _enginesDir;
  Map<String, ImportedEngineMetadata>? _metadata;

  /// Initialize the storage directory
  Future<void> initialize() async {
    if (_enginesDir != null) return;

    final appDir = await getApplicationDocumentsDirectory();
    _enginesDir = Directory('${appDir.path}/$_enginesDirName');

    if (!await _enginesDir!.exists()) {
      await _enginesDir!.create(recursive: true);
      debugPrint('LocalEngineStorage: Created engines directory');
    }

    await _loadMetadata();
    debugPrint('LocalEngineStorage: Initialized with ${_metadata?.length ?? 0} engines');
  }

  /// Get the engines directory path
  Future<String> getEnginesDirectoryPath() async {
    await initialize();
    return _enginesDir!.path;
  }

  /// Load metadata from disk
  Future<void> _loadMetadata() async {
    final metadataFile = File('${_enginesDir!.path}/$_metadataFileName');

    if (await metadataFile.exists()) {
      try {
        final content = await metadataFile.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        final enginesJson = json['engines'] as Map<String, dynamic>? ?? {};

        _metadata = {};
        enginesJson.forEach((key, value) {
          _metadata![key] = ImportedEngineMetadata.fromJson(value as Map<String, dynamic>);
        });
      } catch (e) {
        debugPrint('LocalEngineStorage: Failed to load metadata: $e');
        _metadata = {};
      }
    } else {
      _metadata = {};
    }
  }

  /// Save metadata to disk
  Future<void> _saveMetadata() async {
    final metadataFile = File('${_enginesDir!.path}/$_metadataFileName');

    final enginesJson = <String, dynamic>{};
    _metadata?.forEach((key, value) {
      enginesJson[key] = value.toJson();
    });

    final json = {
      'version': '1.0',
      'updatedAt': DateTime.now().toIso8601String(),
      'engines': enginesJson,
    };

    await metadataFile.writeAsString(jsonEncode(json));
  }

  /// Get list of imported engine IDs
  Future<List<String>> getImportedEngineIds() async {
    await initialize();
    return _metadata?.keys.toList() ?? [];
  }

  /// Get metadata for all imported engines
  Future<List<ImportedEngineMetadata>> getImportedEngines() async {
    await initialize();
    return _metadata?.values.toList() ?? [];
  }

  /// Check if an engine is imported
  Future<bool> isEngineImported(String engineId) async {
    await initialize();
    return _metadata?.containsKey(engineId) ?? false;
  }

  /// Save an engine YAML file to local storage
  ///
  /// [engineId] - Unique identifier for the engine
  /// [fileName] - Original filename (e.g., "pirate_bay.yaml")
  /// [yamlContent] - The YAML content to save
  /// [displayName] - Display name for the engine
  /// [icon] - Optional icon name
  Future<void> saveEngine({
    required String engineId,
    required String fileName,
    required String yamlContent,
    required String displayName,
    String? icon,
  }) async {
    await initialize();

    // Save YAML file
    final engineFile = File('${_enginesDir!.path}/$fileName');
    await engineFile.writeAsString(yamlContent);

    // Update metadata
    _metadata![engineId] = ImportedEngineMetadata(
      id: engineId,
      fileName: fileName,
      displayName: displayName,
      importedAt: DateTime.now(),
      icon: icon,
    );

    await _saveMetadata();
    debugPrint('LocalEngineStorage: Saved engine $engineId');
  }

  /// Delete an imported engine
  Future<void> deleteEngine(String engineId) async {
    await initialize();

    final metadata = _metadata?[engineId];
    if (metadata == null) {
      debugPrint('LocalEngineStorage: Engine $engineId not found');
      return;
    }

    // Delete YAML file
    final engineFile = File('${_enginesDir!.path}/${metadata.fileName}');
    if (await engineFile.exists()) {
      await engineFile.delete();
    }

    // Remove from metadata
    _metadata?.remove(engineId);
    await _saveMetadata();

    debugPrint('LocalEngineStorage: Deleted engine $engineId');
  }

  /// Get the file path for an engine YAML
  Future<String?> getEngineFilePath(String engineId) async {
    await initialize();

    final metadata = _metadata?[engineId];
    if (metadata == null) return null;

    return '${_enginesDir!.path}/${metadata.fileName}';
  }

  /// Read engine YAML content
  Future<String?> readEngineYaml(String engineId) async {
    final filePath = await getEngineFilePath(engineId);
    if (filePath == null) return null;

    final file = File(filePath);
    if (!await file.exists()) return null;

    return file.readAsString();
  }

  /// Get all engine YAML file paths
  Future<List<String>> getAllEngineFilePaths() async {
    await initialize();

    final paths = <String>[];
    for (final metadata in _metadata?.values ?? <ImportedEngineMetadata>[]) {
      final path = '${_enginesDir!.path}/${metadata.fileName}';
      if (await File(path).exists()) {
        paths.add(path);
      }
    }

    return paths;
  }

  /// Clear all imported engines (for testing/reset)
  Future<void> clearAll() async {
    await initialize();

    // Delete all engine files
    for (final metadata in _metadata?.values ?? <ImportedEngineMetadata>[]) {
      final file = File('${_enginesDir!.path}/${metadata.fileName}');
      if (await file.exists()) {
        await file.delete();
      }
    }

    // Clear metadata
    _metadata?.clear();
    await _saveMetadata();

    debugPrint('LocalEngineStorage: Cleared all engines');
  }

  /// Check if any engines are imported
  Future<bool> hasImportedEngines() async {
    await initialize();
    return _metadata?.isNotEmpty ?? false;
  }
}
