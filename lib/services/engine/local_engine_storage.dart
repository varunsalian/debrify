import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart' as crypto;
import 'package:collection/collection.dart';
import '../profiles/profile_scope.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:synchronized/synchronized.dart';
import 'package:yaml/yaml.dart';
import '../profiles/profile_storage_paths.dart';
import '../profiles/profile_preferences.dart';
import '../profiles/profile_runtime.dart';

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

/// An ordinary mutation remains registered until this transaction settles.
/// WebDAV snapshots therefore cannot publish an onboarding batch that rolls back.
class LocalEngineTransaction {
  LocalEngineTransaction._(
    this._storage,
    this._previous,
    this._deleted,
    this._settled,
    this._finished,
  );
  final LocalEngineStorage _storage;
  final Map<String, ImportedEngineMetadata> _previous;
  final Set<String> _deleted;
  final Completer<bool?> _settled;
  final Future<void> _finished;
  bool _closed = false;

  Future<void> commit() async {
    if (_closed) return;
    _closed = true;
    _settled.complete(true);
    await _finished;
  }

  Future<void> rollback() async {
    if (_closed) return;
    _closed = true;
    try {
      _storage._metadata = _previous;
      _storage._deleted = _deleted;
      await _storage._saveMetadata();
      _settled.complete(false);
    } catch (_) {
      // Keep all files if rollback could not republish the prior metadata.
      _settled.complete(null);
      rethrow;
    }
    await _finished;
  }
}

/// The atomic metadata file is the authority. YAML files are immutable and
/// content-addressed: interruption before metadata publication leaves only an
/// unused file, never a partial engine or a changed previously committed file.
class LocalEngineStorage {
  static const definitionPrefix = 'engine_definition_v1_';
  static const maxDefinitionBytes = 256 * 1024;
  static final changes = ValueNotifier<int>(0);
  static final Lock _writeLock = Lock();
  static final instance = LocalEngineStorage._();
  LocalEngineStorage._();
  LocalEngineStorage.forDirectory(Directory directory)
    : _enginesDir = directory,
      _fixedDirectory = true;
  bool _fixedDirectory = false;

  Directory? _enginesDir;
  Map<String, ImportedEngineMetadata>? _metadata;
  Set<String> _deleted = {};
  ProfileScope? _mutationScope;
  ProfileScope? _authorityScope;
  LocalEngineStorage? _cacheOwner;

  static String definitionKey(String id) =>
      '$definitionPrefix${crypto.sha256.convert(utf8.encode(id))}';

  Future<void> initialize() async {
    _enginesDir ??= Directory(
      '${await ProfileStoragePaths.documentsDirectory()}/engines',
    );
    if (_metadata != null) return;
    await _loadMetadata();
  }

  Future<void> _loadMetadata() async {
    final file = File('${_enginesDir!.path}/metadata.json');
    if (!await file.exists()) {
      _metadata = {};
      _deleted = {};
      return;
    }
    // A corrupt inventory is an error, not an empty collection to publish.
    final value = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final engines = value['engines'] as Map<String, dynamic>? ?? {};
    final metadata = {
      for (final entry in engines.entries)
        entry.key: ImportedEngineMetadata.fromJson(
          Map<String, dynamic>.from(entry.value as Map),
        ),
    };
    final deleted = Set<String>.from(value['deletedEngineIds'] as List? ?? []);
    if (metadata.entries.any((entry) => entry.key != entry.value.id) ||
        deleted.any(metadata.containsKey)) {
      throw const FormatException('Inconsistent engine inventory');
    }
    _metadata = metadata;
    _deleted = deleted;
  }

  Future<void> _saveMetadata() async {
    await _enginesDir!.create(recursive: true);
    final target = File('${_enginesDir!.path}/metadata.json');
    final temporary = File('${target.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({
        'version': '1.0',
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
        'engines': {
          for (final e in _metadata!.entries) e.key: e.value.toJson(),
        },
        'deletedEngineIds': _deleted.toList()..sort(),
      }),
      flush: true,
    );
    await temporary.rename(target.path);
    _cacheOwner?._metadata = null;
    if (!identical(this, instance) &&
        instance._enginesDir?.path == _enginesDir!.path) {
      instance._metadata = null;
    }
  }

  Future<void> _pruneUnusedFiles() async {
    final retained = _metadata!.values.map((e) => e.fileName).toSet();
    try {
      await for (final file in _enginesDir!.list(followLinks: false)) {
        if (file is File &&
            !retained.contains(p.basename(file.path)) &&
            const {
              '.yaml',
              '.yml',
            }.contains(p.extension(file.path).toLowerCase())) {
          await file.delete();
        }
      }
    } on FileSystemException {
      // A failed cleanup does not roll back an already-published inventory.
    }
  }

  void resetProfileScope() {
    _enginesDir = null;
    _metadata = null;
    _deleted = {};
  }

  Future<LocalEngineStorage> _pinned() async {
    if (_fixedDirectory) {
      return LocalEngineStorage.forDirectory(_enginesDir!).._cacheOwner = this;
    }
    // Bind the path before the first await; a profile switch must never move
    // an already-started write into the next profile's directory.
    final scope =
        ProfileRuntime.isInitialized && ProfileRuntime.isProfileCommitted
        ? ProfileRuntime.capture()
        : null;
    final authorityScope = ProfileRuntime.scope.value;
    final String path;
    if (scope != null) {
      path = await ProfileRuntime.withCapturedScope(
        scope,
        ProfileStoragePaths.documentsDirectory,
      );
    } else {
      path = await ProfileStoragePaths.documentsDirectory();
    }
    final store = LocalEngineStorage.forDirectory(Directory('$path/engines'));
    store._mutationScope = scope;
    store._authorityScope = authorityScope;
    store._cacheOwner = this;
    store._validateMutationScope();
    await store.initialize();
    return store;
  }

  void _validateMutationScope() {
    if (_mutationScope != null &&
        ProfileRuntime.scope.value != _authorityScope) {
      throw StateError('Profile changed during engine mutation');
    }
  }

  Future<String> getEnginesDirectoryPath() async {
    await initialize();
    return _enginesDir!.path;
  }

  Future<List<String>> getImportedEngineIds() async {
    await initialize();
    return _metadata!.keys.toList();
  }

  Future<List<ImportedEngineMetadata>> getImportedEngines() async {
    await initialize();
    return _metadata!.values.toList();
  }

  Future<bool> isEngineImported(String engineId) async {
    await initialize();
    return _metadata!.containsKey(engineId);
  }

  Future<bool> hasImportedEngines() async {
    await initialize();
    return _metadata!.isNotEmpty;
  }

  static void _checkId(String id) {
    if (id.isEmpty || id.length > 256 || id.trim() != id) {
      throw const FormatException('Invalid engine identity');
    }
  }

  Future<ImportedEngineMetadata> _write(LocalEngineWrite engine) async {
    _checkId(engine.engineId);
    final bytes = utf8.encode(engine.yamlContent);
    if (bytes.length > maxDefinitionBytes) {
      throw const FormatException('Engine definition exceeds 256 KiB');
    }
    final name = '${crypto.sha256.convert(bytes)}.yaml';
    await _enginesDir!.create(recursive: true);
    final file = File('${_enginesDir!.path}/$name');
    if (!await file.exists()) {
      final temp = File('${file.path}.tmp');
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(file.path);
    }
    return ImportedEngineMetadata(
      id: engine.engineId,
      fileName: name,
      displayName: engine.displayName,
      importedAt: DateTime.now().toUtc(),
      icon: engine.icon,
    );
  }

  Future<void> saveEngine({
    required String engineId,
    required String fileName,
    required String yamlContent,
    required String displayName,
    String? icon,
  }) async {
    final transaction = await saveEnginesAtomically([
      LocalEngineWrite(
        engineId: engineId,
        fileName: fileName,
        yamlContent: yamlContent,
        displayName: displayName,
        icon: icon,
      ),
    ]);
    await transaction?.commit();
  }

  Future<LocalEngineTransaction?> saveEnginesAtomically(
    List<LocalEngineWrite> engines, {
    bool Function()? isCanceled,
  }) async {
    if (engines.isEmpty) return null;
    final store = await _pinned();
    final profileId = store._mutationScope?.profileId;
    final ready = Completer<LocalEngineTransaction?>();
    final finished = Completer<void>();
    unawaited(
      ProfilePreferences.synchronizeExternalMutation(
        () => _writeLock.synchronized(() async {
          store._validateMutationScope();
          await store._loadMetadata();
          final previous = Map<String, ImportedEngineMetadata>.of(
            store._metadata!,
          );
          final deleted = Set<String>.of(store._deleted);
          try {
            for (final engine in engines) {
              if (isCanceled?.call() ?? false) {
                store._metadata = previous;
                store._deleted = deleted;
                await store._pruneUnusedFiles();
                ready.complete(null);
                return;
              }
              store._metadata![engine.engineId] = await store._write(engine);
              store._deleted.remove(engine.engineId);
              if (isCanceled?.call() ?? false) {
                store._metadata = previous;
                store._deleted = deleted;
                await store._pruneUnusedFiles();
                ready.complete(null);
                return;
              }
            }
            store._validateMutationScope();
            await store._saveMetadata();
            final settled = Completer<bool?>();
            ready.complete(
              LocalEngineTransaction._(
                store,
                previous,
                deleted,
                settled,
                finished.future,
              ),
            );
            final committed = await settled.future;
            if (committed != null) await store._pruneUnusedFiles();
            if (committed == true) _notify(profileId);
          } catch (error, stack) {
            store._metadata = previous;
            store._deleted = deleted;
            if (!ready.isCompleted) ready.completeError(error, stack);
            rethrow;
          }
        }),
        marksMutation: true,
      ).then(
        (_) {
          finished.complete();
        },
        onError: (Object e, StackTrace st) {
          if (!ready.isCompleted) ready.completeError(e, st);
          // Preparation failures are delivered through ready. Always release
          // a transaction owner waiting for the mutation barrier to drain.
          if (!finished.isCompleted) finished.complete();
        },
      ),
    );
    return ready.future;
  }

  static void _notify(String? profileId) {
    if (profileId != null) {
      ProfilePreferences.notifyWebDavSyncLocalChange(
        profileId,
        'engine_definitions_changed',
      );
    }
  }

  Future<void> _delete(Set<String>? ids) async {
    final store = await _pinned();
    final profileId = store._mutationScope?.profileId;
    await ProfilePreferences.synchronizeExternalMutation(
      () => _writeLock.synchronized(() async {
        store._validateMutationScope();
        await store._loadMetadata();
        final selected = ids ?? store._metadata!.keys.toSet();
        var changed = false;
        for (final id in selected) {
          if (store._metadata!.remove(id) != null) {
            store._deleted.add(id);
            changed = true;
          }
        }
        if (changed) {
          store._validateMutationScope();
          await store._saveMetadata();
          await store._pruneUnusedFiles();
          _notify(profileId);
        }
      }),
      marksMutation: true,
    );
  }

  Future<void> deleteEngine(String engineId) => _delete({engineId});
  Future<void> clearAll() => _delete(null);

  Future<String?> getEngineFilePath(String engineId) async {
    await initialize();
    final item = _metadata![engineId];
    if (item == null) return null;
    if (p.basename(item.fileName) != item.fileName ||
        item.fileName == '.' ||
        item.fileName == '..') {
      throw const FormatException('Invalid engine file path');
    }
    return p.join(_enginesDir!.path, item.fileName);
  }

  Future<String?> readEngineYaml(String engineId) async {
    final path = await getEngineFilePath(engineId);
    if (path == null) return null;
    return File(path).readAsString();
  }

  Future<List<String>> getAllEngineFilePaths() async {
    final ids = await getImportedEngineIds();
    return [for (final id in ids) (await getEngineFilePath(id))!];
  }

  /// Called under the profile snapshot barrier, including inactive profiles.
  Future<Map<String, Object>> exportSyncDefinitions() async {
    await initialize();
    final values = <String, Object>{};
    for (final item in _metadata!.values) {
      final yaml = (await readEngineYaml(item.id))!;
      if (utf8.encode(yaml).length > maxDefinitionBytes) {
        throw const FormatException('Engine definition exceeds sync limit');
      }
      values[definitionKey(item.id)] = jsonEncode({
        'id': item.id,
        'deleted': false,
        'name': item.displayName,
        'icon': item.icon,
        'yaml': yaml,
      });
    }
    for (final id in _deleted) {
      values[definitionKey(id)] = jsonEncode({'id': id, 'deleted': true});
    }
    return values;
  }

  static bool _sameDefinition(Object? left, Object? right) =>
      left is String &&
      right is String &&
      const DeepCollectionEquality().equals(
        jsonDecode(left),
        jsonDecode(right),
      );

  /// Caller holds the profile commit barrier and has persisted its replay target.
  /// Validate the entire batch before publishing the new atomic inventory.
  Future<Set<String>> applySyncDefinitions(Map<String, Object> values) async {
    if (values.isEmpty) return {};
    return _writeLock.synchronized(() async {
      await initialize();
      final previous = await exportSyncDefinitions();
      final next = Map<String, ImportedEngineMetadata>.of(_metadata!);
      final deleted = Set<String>.of(_deleted);
      final writes = <String, LocalEngineWrite>{};
      final removals = <String, String>{};
      for (final entry in values.entries) {
        if (entry.value is! String) {
          throw const FormatException('Invalid engine definition');
        }
        final v = jsonDecode(entry.value as String) as Map<String, dynamic>;
        final id = v['id'] as String;
        _checkId(id);
        final allowed = v['deleted'] == true
            ? const {'id', 'deleted'}
            : const {'id', 'deleted', 'name', 'icon', 'yaml'};
        if (v.keys.any((key) => !allowed.contains(key))) {
          throw const FormatException('Unknown engine definition field');
        }
        if (definitionKey(id) != entry.key || v['deleted'] is! bool) {
          throw const FormatException('Invalid engine definition identity');
        }
        if (v['deleted'] == true) {
          removals[entry.key] = id;
          continue;
        }
        final yaml = v['yaml'] as String;
        if (utf8.encode(yaml).length > maxDefinitionBytes) {
          throw const FormatException('Engine definition exceeds sync limit');
        }
        final parsed = loadYaml(yaml);
        if (parsed is! YamlMap || parsed['id'] != id) {
          throw const FormatException('Engine YAML identity mismatch');
        }
        final name = v['name'] as String;
        if (name.isEmpty || name.length > 512) {
          throw const FormatException('Invalid engine name');
        }
        writes[entry.key] = LocalEngineWrite(
          engineId: id,
          fileName: '',
          yamlContent: yaml,
          displayName: name,
          icon: v['icon'] as String?,
        );
      }
      final changed = <String>{};
      for (final entry in removals.entries) {
        if (_sameDefinition(previous[entry.key], values[entry.key])) continue;
        next.remove(entry.value);
        deleted.add(entry.value);
        changed.add(entry.key);
      }
      for (final entry in writes.entries) {
        if (_sameDefinition(previous[entry.key], values[entry.key])) continue;
        next[entry.value.engineId] = await _write(entry.value);
        deleted.remove(entry.value.engineId);
        changed.add(entry.key);
      }
      if (changed.isNotEmpty) {
        _metadata = next;
        _deleted = deleted;
        await _saveMetadata();
        await _pruneUnusedFiles();
      }
      return changed;
    });
  }
}
