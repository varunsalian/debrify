import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../utils/app_storage.dart';

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

/// One engine prepared for a batch import.
class LocalEngineWrite {
  const LocalEngineWrite({
    required this.engineId,
    required this.fileName,
    required this.yamlContent,
    required this.displayName,
    this.icon,
  });

  final String engineId;
  final String fileName;
  final String yamlContent;
  final String displayName;
  final String? icon;
}

/// Keeps a completed batch reversible until its caller has refreshed runtime
/// state. This closes the small window between disk commit and registry reload.
class LocalEngineTransaction {
  LocalEngineTransaction._(
    this._storage,
    this._previousMetadata,
    this._previousFiles,
  );

  final LocalEngineStorage _storage;
  final Map<String, ImportedEngineMetadata?> _previousMetadata;
  final Map<String, List<int>?> _previousFiles;
  bool _closed = false;

  void commit() => _closed = true;

  Future<void> rollback() async {
    if (_closed) return;
    _closed = true;
    await _storage._restoreBatch(_previousMetadata, _previousFiles);
  }
}

class _EngineBatchCanceled implements Exception {
  const _EngineBatchCanceled();
}

/// Manages local storage of imported engine YAML files
class LocalEngineStorage {
  static const String _enginesDirName = 'engines';
  static const String _metadataFileName = 'metadata.json';

  static LocalEngineStorage? _instance;
  static LocalEngineStorage get instance =>
      _instance ??= LocalEngineStorage._();

  LocalEngineStorage._();

  Directory? _enginesDir;
  Map<String, ImportedEngineMetadata>? _metadata;

  /// Initialize the storage directory
  Future<void> initialize() async {
    if (_enginesDir != null) return;

    final appDir = await AppStorage.documents();
    _enginesDir = Directory('${appDir.path}/$_enginesDirName');

    if (!await _enginesDir!.exists()) {
      await _enginesDir!.create(recursive: true);
      debugPrint('LocalEngineStorage: Created engines directory');
    }

    await _loadMetadata();
    debugPrint(
      'LocalEngineStorage: Initialized with ${_metadata?.length ?? 0} engines',
    );
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
          _metadata![key] = ImportedEngineMetadata.fromJson(
            value as Map<String, dynamic>,
          );
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
  /// [fileName] - Original filename (e.g., "example_indexer.yaml")
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

  /// Writes a prepared batch as one reversible operation.
  ///
  /// If [isCanceled] becomes true after any file write, every affected file and
  /// metadata entry are restored before this returns `null`. On
  /// success the caller owns the returned transaction until it either commits
  /// after refreshing runtime state or rolls back.
  Future<LocalEngineTransaction?> saveEnginesAtomically(
    List<LocalEngineWrite> engines, {
    bool Function()? isCanceled,
  }) async {
    await initialize();
    if (engines.isEmpty) return null;

    final previousMetadata = <String, ImportedEngineMetadata?>{
      for (final engine in engines)
        engine.engineId: _metadata![engine.engineId],
    };
    final affectedFileNames = <String>{
      for (final engine in engines) engine.fileName,
      for (final engine in engines)
        if (previousMetadata[engine.engineId] != null)
          previousMetadata[engine.engineId]!.fileName,
    };
    final previousFiles = <String, List<int>?>{};
    for (final fileName in affectedFileNames) {
      final file = File('${_enginesDir!.path}/$fileName');
      previousFiles[fileName] = await file.exists()
          ? await file.readAsBytes()
          : null;
    }

    final transaction = LocalEngineTransaction._(
      this,
      previousMetadata,
      previousFiles,
    );
    try {
      for (final engine in engines) {
        if (isCanceled?.call() ?? false) {
          throw const _EngineBatchCanceled();
        }
        final file = File('${_enginesDir!.path}/${engine.fileName}');
        await file.writeAsString(engine.yamlContent, flush: true);
        _metadata![engine.engineId] = ImportedEngineMetadata(
          id: engine.engineId,
          fileName: engine.fileName,
          displayName: engine.displayName,
          importedAt: DateTime.now(),
          icon: engine.icon,
        );
        if (isCanceled?.call() ?? false) {
          throw const _EngineBatchCanceled();
        }
      }
      await _saveMetadata();
      if (isCanceled?.call() ?? false) {
        throw const _EngineBatchCanceled();
      }
      return transaction;
    } on _EngineBatchCanceled {
      await transaction.rollback();
      return null;
    } catch (_) {
      await transaction.rollback();
      rethrow;
    }
  }

  Future<void> _restoreBatch(
    Map<String, ImportedEngineMetadata?> previousMetadata,
    Map<String, List<int>?> previousFiles,
  ) async {
    for (final entry in previousFiles.entries) {
      final file = File('${_enginesDir!.path}/${entry.key}');
      final bytes = entry.value;
      if (bytes == null) {
        if (await file.exists()) await file.delete();
      } else {
        await file.writeAsBytes(bytes, flush: true);
      }
    }
    for (final entry in previousMetadata.entries) {
      final metadata = entry.value;
      if (metadata == null) {
        _metadata!.remove(entry.key);
      } else {
        _metadata![entry.key] = metadata;
      }
    }
    await _saveMetadata();
    debugPrint('LocalEngineStorage: Rolled back engine batch');
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
