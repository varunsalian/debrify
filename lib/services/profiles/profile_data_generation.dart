import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/app_storage.dart';
import 'profile_registry.dart';
import 'profile_scope.dart';

class StagedProfileGeneration {
  final String operationId;
  final String profileId;
  final int baseGeneration;
  final int generation;
  final Map<String, dynamic> manifest;

  const StagedProfileGeneration({
    required this.operationId,
    required this.profileId,
    required this.baseGeneration,
    required this.generation,
    required this.manifest,
  });
}

/// Builds complete invisible generations. Visibility is granted only by the
/// registry transaction; directory discovery is never an authority.
class ProfileDataGenerationManager {
  final ProfileRegistry registry;

  const ProfileDataGenerationManager(this.registry);

  static Future<void> deleteAllProfileData(String profileId) async {
    if (!ProfileScope.isValidProfileId(profileId)) {
      throw ArgumentError.value(profileId, 'profileId');
    }
    final prefs = await SharedPreferences.getInstance();
    final prefix = 'p.$profileId.g.';
    for (final key in prefs.getKeys().where((key) => key.startsWith(prefix))) {
      if (!await prefs.remove(key)) {
        throw StateError('Could not delete private profile preferences');
      }
    }
    final roots = <Directory>[
      await AppStorage.documents(),
      await AppStorage.support(),
      await AppStorage.cache(),
    ];
    final seen = <String>{};
    for (final root in roots) {
      final path = p.normalize(
        p.join(root.absolute.path, 'profiles', profileId),
      );
      if (!seen.add(path)) continue;
      final directory = Directory(path);
      if (await directory.exists()) await directory.delete(recursive: true);
    }
  }

  static Future<void> deleteGenerationData(
    String profileId,
    int generation,
  ) async {
    final scope = ProfileScope(
      profileId: profileId,
      dataGeneration: generation,
      sessionEpoch: 0,
    );
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().where(
      (key) => key.startsWith(scope.preferencePrefix),
    )) {
      await prefs.remove(key);
    }
    final roots = <Directory>[
      await AppStorage.documents(),
      await AppStorage.support(),
      await AppStorage.cache(),
    ];
    final seen = <String>{};
    for (final root in roots) {
      final directory = scope.generationDirectory(root);
      final path = p.normalize(directory.absolute.path);
      if (seen.add(path) && await directory.exists()) {
        await directory.delete(recursive: true);
      }
    }
  }

  Future<StagedProfileGeneration> stage({
    required String operationId,
    required String profileId,
    required Map<String, Object?> preferenceOverlay,
    bool replacePreferences = false,
    bool copyDurableAreas = true,
  }) async {
    final profile = await registry.getProfile(profileId);
    if (profile == null || !profile.isEnabled) {
      throw StateError('Destination profile is unavailable');
    }
    final base = profile.visibleDataGeneration;
    final next = await registry.reserveDataGeneration(
      profileId: profileId,
      operationId: operationId,
      mode: 'merge',
    );
    final from = ProfileScope(
      profileId: profileId,
      dataGeneration: base,
      sessionEpoch: 0,
    );
    final to = ProfileScope(
      profileId: profileId,
      dataGeneration: next,
      sessionEpoch: 0,
    );
    final preferenceCount = await _stagePreferences(
      from,
      to,
      preferenceOverlay,
      replace: replacePreferences,
    );
    final files = copyDurableAreas
        ? await _cloneDurableAreas(from, to)
        : const <Map<String, Object?>>[];
    final manifest = <String, dynamic>{
      'version': 1,
      'profileId': profileId,
      'baseGeneration': base,
      'generation': next,
      'preferenceCount': preferenceCount,
      'files': files,
    };
    final canonical = jsonEncode(manifest);
    final hash = base64UrlEncode(
      (await Sha256().hash(utf8.encode(canonical))).bytes,
    ).replaceAll('=', '');
    await registry.updateStagedGenerationManifest(
      profileId: profileId,
      generation: next,
      operationId: operationId,
      manifest: manifest,
      manifestHash: hash,
    );
    return StagedProfileGeneration(
      operationId: operationId,
      profileId: profileId,
      baseGeneration: base,
      generation: next,
      manifest: manifest,
    );
  }

  /// Recomputes the manifest from the final staged bytes after every restore
  /// overlay. Publication must never rely on the pre-overlay clone manifest.
  Future<StagedProfileGeneration> finalize(
    StagedProfileGeneration staged,
  ) async {
    final scope = ProfileScope(
      profileId: staged.profileId,
      dataGeneration: staged.generation,
      sessionEpoch: 0,
    );
    final prefs = await SharedPreferences.getInstance();
    final preferenceCount = prefs
        .getKeys()
        .where((key) => key.startsWith(scope.preferencePrefix))
        .length;
    final files = await _manifestDurableAreas(scope);
    final manifest = <String, dynamic>{
      'version': 1,
      'profileId': staged.profileId,
      'baseGeneration': staged.baseGeneration,
      'generation': staged.generation,
      'preferenceCount': preferenceCount,
      'files': files,
    };
    final canonical = jsonEncode(manifest);
    final hash = base64UrlEncode(
      (await Sha256().hash(utf8.encode(canonical))).bytes,
    ).replaceAll('=', '');
    await registry.updateStagedGenerationManifest(
      profileId: staged.profileId,
      generation: staged.generation,
      operationId: staged.operationId,
      manifest: manifest,
      manifestHash: hash,
    );
    return StagedProfileGeneration(
      operationId: staged.operationId,
      profileId: staged.profileId,
      baseGeneration: staged.baseGeneration,
      generation: staged.generation,
      manifest: manifest,
    );
  }

  /// Finalizes generation 1 for a profile staged by a device-graph restore.
  /// The profile lifecycle keeps it invisible even though generation 1 is
  /// represented as `visible` inside that isolated staging profile.
  Future<void> finalizeGraphProfile({
    required String operationId,
    required String profileId,
  }) async {
    final scope = ProfileScope(
      profileId: profileId,
      dataGeneration: 1,
      sessionEpoch: 0,
    );
    final manifest = await _graphManifest(scope);
    final canonical = jsonEncode(manifest);
    final hash = base64UrlEncode(
      (await Sha256().hash(utf8.encode(canonical))).bytes,
    ).replaceAll('=', '');
    await registry.finalizeGraphProfileGeneration(
      operationId: operationId,
      profileId: profileId,
      manifest: manifest,
      manifestHash: hash,
    );
  }

  /// Recomputes the staged generation immediately before graph publication.
  /// The registry's non-empty check proves a manifest was written; this check
  /// proves the bytes and preference count still match that manifest.
  Future<void> verifyGraphProfile({
    required String operationId,
    required String profileId,
  }) async {
    final expected = await registry.stagedGraphProfileGeneration(
      operationId: operationId,
      profileId: profileId,
    );
    final actual = await _graphManifest(
      ProfileScope(profileId: profileId, dataGeneration: 1, sessionEpoch: 0),
    );
    final actualCanonical = jsonEncode(actual);
    final actualHash = base64UrlEncode(
      (await Sha256().hash(utf8.encode(actualCanonical))).bytes,
    ).replaceAll('=', '');
    if (actualHash != expected.hash ||
        actualCanonical != jsonEncode(expected.manifest)) {
      throw StateError('Graph profile generation changed after finalization');
    }
  }

  Future<Map<String, dynamic>> _graphManifest(ProfileScope scope) async {
    final prefs = await SharedPreferences.getInstance();
    return <String, dynamic>{
      'version': 1,
      'profileId': scope.profileId,
      'baseGeneration': 0,
      'generation': scope.dataGeneration,
      'preferenceCount': prefs
          .getKeys()
          .where((key) => key.startsWith(scope.preferencePrefix))
          .length,
      'files': await _manifestDurableAreas(scope),
    };
  }

  Future<int> _stagePreferences(
    ProfileScope from,
    ProfileScope to,
    Map<String, Object?> overlay, {
    required bool replace,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    var count = 0;
    if (!replace) {
      for (final physical in prefs.getKeys().toList(growable: false)) {
        if (!physical.startsWith(from.preferencePrefix)) continue;
        final logical = physical.substring(from.preferencePrefix.length);
        await _writeValue(
          prefs,
          to.preferenceKey(logical),
          prefs.get(physical),
        );
        count++;
      }
    }
    for (final entry in overlay.entries) {
      if (entry.key.isEmpty || entry.key.length > 256) {
        throw ArgumentError.value(entry.key, 'preferenceOverlay');
      }
      await _writeValue(prefs, to.preferenceKey(entry.key), entry.value);
      count++;
    }
    return count;
  }

  Future<List<Map<String, Object?>>> _cloneDurableAreas(
    ProfileScope from,
    ProfileScope to,
  ) async {
    final roots = <Directory>[
      await AppStorage.documents(),
      await AppStorage.support(),
      await AppStorage.cache(),
    ];
    final seen = <String>{};
    final manifest = <Map<String, Object?>>[];
    for (final root in roots) {
      final canonicalRoot = p.normalize(root.absolute.path);
      if (!seen.add(canonicalRoot)) continue;
      final source = from.generationDirectory(root);
      if (!await source.exists()) continue;
      final destination = to.generationDirectory(root);
      await for (final entity in source.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is Link) throw StateError('Scoped data contains a symlink');
        if (entity is! File) continue;
        final relative = p.relative(entity.path, from: source.path);
        if (_isSqliteSidecar(relative) || _isTransientRestoreFile(relative)) {
          continue;
        }
        final target = File(p.join(destination.path, relative));
        await target.parent.create(recursive: true);
        final sourceLength = await entity.length();
        final sourceHash = await _hashFile(entity);
        await entity.copy(target.path);
        final handle = await target.open(mode: FileMode.append);
        try {
          await handle.flush();
        } finally {
          await handle.close();
        }
        final targetHash = await _hashFile(target);
        if (sourceHash != targetHash || await target.length() != sourceLength) {
          throw StateError('Staged file hash mismatch');
        }
        manifest.add(<String, Object?>{
          'areaRoot': canonicalRoot,
          'path': relative,
          'bytes': sourceLength,
          'sha256': targetHash,
        });
      }
    }
    manifest.sort(
      (a, b) => '${a['areaRoot']}/${a['path']}'.compareTo(
        '${b['areaRoot']}/${b['path']}',
      ),
    );
    return manifest;
  }

  Future<List<Map<String, Object?>>> _manifestDurableAreas(
    ProfileScope scope,
  ) async {
    final roots = <Directory>[
      await AppStorage.documents(),
      await AppStorage.support(),
      await AppStorage.cache(),
    ];
    final seen = <String>{};
    final manifest = <Map<String, Object?>>[];
    for (final root in roots) {
      final canonicalRoot = p.normalize(root.absolute.path);
      if (!seen.add(canonicalRoot)) continue;
      final directory = scope.generationDirectory(root);
      if (!await directory.exists()) continue;
      await for (final entity in directory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is Link) throw StateError('Scoped data contains a symlink');
        if (entity is! File) continue;
        final relative = p.relative(entity.path, from: directory.path);
        if (_isTransientRestoreFile(relative)) continue;
        if (_isSqliteSidecar(relative)) {
          throw StateError('Staged generation contains a SQLite sidecar');
        }
        manifest.add(<String, Object?>{
          'areaRoot': canonicalRoot,
          'path': relative,
          'bytes': await entity.length(),
          'sha256': await _hashFile(entity),
        });
      }
    }
    manifest.sort(
      (a, b) => '${a['areaRoot']}/${a['path']}'.compareTo(
        '${b['areaRoot']}/${b['path']}',
      ),
    );
    return manifest;
  }

  static bool _isSqliteSidecar(String path) =>
      path.endsWith('-wal') ||
      path.endsWith('-shm') ||
      path.endsWith('-journal');

  static bool _isTransientRestoreFile(String path) {
    final normalized = path.replaceAll(r'\', '/');
    return normalized == '.avatar-restore' ||
        normalized.startsWith('.avatar-restore/');
  }

  static Future<void> _writeValue(
    SharedPreferences prefs,
    String key,
    Object? value,
  ) async {
    final success = switch (value) {
      bool value => await prefs.setBool(key, value),
      int value => await prefs.setInt(key, value),
      double value => await prefs.setDouble(key, value),
      String value when value.length <= 4 * 1024 * 1024 =>
        await prefs.setString(key, value),
      List<String> value => await prefs.setStringList(key, value),
      null => await prefs.remove(key),
      _ => throw FormatException('Unsupported preference value for $key'),
    };
    if (!success) throw StateError('Could not stage preference $key');
  }

  static Future<String> _hashFile(File file) async {
    final sink = Sha256().newHashSink();
    await for (final chunk in file.openRead()) {
      sink.add(chunk);
    }
    sink.close();
    return base64UrlEncode((await sink.hash()).bytes).replaceAll('=', '');
  }
}
