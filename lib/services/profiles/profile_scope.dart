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
        normalized.startsWith('../')) {
      throw ArgumentError.value(relativePath, 'relativePath', 'Unsafe path');
    }
    return File(p.join(storageDirectory(root, area).path, normalized));
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
