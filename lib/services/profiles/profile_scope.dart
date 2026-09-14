import 'dart:io';

import 'package:path/path.dart' as p;

final RegExp _safeProfileId = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,95}$');

class ProfileScope {
  final String profileId;
  final int dataGeneration;
  final int sessionEpoch;

  static bool isValidProfileId(String value) => _safeProfileId.hasMatch(value);

  ProfileScope({
    required this.profileId,
    required this.dataGeneration,
    required this.sessionEpoch,
  }) {
    if (!isValidProfileId(profileId)) {
      throw ArgumentError.value(profileId, 'profileId', 'Unsafe profile ID');
    }
    if (dataGeneration < 1) {
      throw ArgumentError.value(dataGeneration, 'dataGeneration');
    }
    if (sessionEpoch < 0) {
      throw ArgumentError.value(sessionEpoch, 'sessionEpoch');
    }
  }

  String preferenceKey(String logicalKey) {
    if (logicalKey.isEmpty) throw ArgumentError.value(logicalKey, 'logicalKey');
    return '$preferencePrefix$logicalKey';
  }

  String get preferencePrefix => 'p.$profileId.g.$dataGeneration.';

  /// Canonical identity of this scope *including* the session epoch, for
  /// process-global caches that must prove which scope they were warmed for.
  ///
  /// Unlike [preferencePrefix] this includes [sessionEpoch], because a cache
  /// warmed before a switch and one warmed after are different even when the
  /// profile and generation are identical.
  ///
  /// Defined here rather than on each consumer because it previously was not:
  /// `EngineRegistry` and `ProfileCacheLedger` each grew their own format
  /// (`profile:<id>:g:N:e:N` versus `p.<id>.g.N.e.N`) while the ledger's
  /// documentation claimed they matched. They were compared with `==`, so the
  /// engines row could never match the active scope and the dev audit screen
  /// reported it as a stale cache permanently — a false positive on the one
  /// cache that has actually leaked in the past.
  String get cacheKey => 'p.$profileId.g.$dataGeneration.e.$sessionEpoch';

  Directory generationDirectory(Directory root) => Directory(
    p.join(root.path, 'profiles', profileId, 'g', '$dataGeneration'),
  );

  Directory storageDirectory(Directory root, String area) {
    if (!_safeArea.hasMatch(area)) throw ArgumentError.value(area, 'area');
    return Directory(p.join(generationDirectory(root).path, area));
  }

  File file(Directory root, String relativePath) {
    return fileIn(root, 'data', relativePath);
  }

  File fileIn(Directory root, String area, String relativePath) {
    final normalized = p.normalize(relativePath);
    if (p.isAbsolute(normalized) ||
        normalized == '..' ||
        normalized.startsWith('../') ||
        // package:path considers Windows drive-relative paths (C:file) relative.
        (Platform.isWindows && RegExp(r'^[A-Za-z]:').hasMatch(normalized))) {
      throw ArgumentError.value(relativePath, 'relativePath', 'Unsafe path');
    }
    final scopedRoot = storageDirectory(root, area).path;
    final target = p.join(scopedRoot, normalized);
    final absoluteRoot = p.normalize(p.absolute(scopedRoot));
    final absoluteTarget = p.normalize(p.absolute(target));
    // Compare components, not a prefix that also matches sibling names.
    // This is lexical containment; it does not resolve filesystem links.
    if (!p.equals(absoluteRoot, absoluteTarget) &&
        !p.isWithin(absoluteRoot, absoluteTarget)) {
      throw ArgumentError.value(relativePath, 'relativePath', 'Unsafe path');
    }
    return File(target);
  }

  @override
  bool operator ==(Object other) =>
      other is ProfileScope &&
      other.profileId == profileId &&
      other.dataGeneration == dataGeneration &&
      other.sessionEpoch == sessionEpoch;

  @override
  int get hashCode => Object.hash(profileId, dataGeneration, sessionEpoch);
}

final RegExp _safeArea = RegExp(r'^[a-z][a-z0-9_-]{0,31}$');
