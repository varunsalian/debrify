enum WebDavSyncAdoptionMode { firstJoin, refresh }

enum WebDavSyncAdoptionPhase {
  restoring,
  restored,
  copyingDatabases,
  remappingDatabases,
  carryingLocalState,
  handingOff,
  pruning,
  complete,
}

final class WebDavSyncAdoptionRecord {
  const WebDavSyncAdoptionRecord({
    required this.adoptionId,
    required this.mode,
    required this.phase,
    required this.graphSemanticDigest,
    required this.preRestoreProfileIds,
    required this.backupPath,
    required this.backupSha256,
    required this.backupVerified,
    this.completeOnboarding = false,
    this.safetyBackupRetained = true,
    this.circleProfileToNewLocal = const <String, String>{},
    this.circleResourceToNewLocal = const <String, String>{},
    this.oldToNewProfiles = const <String, String>{},
    this.oldToNewResources = const <String, String>{},
    this.unmappedOldResourceIds = const <String>{},
    this.databaseCopiesComplete = const <String>{},
    this.databaseRemapsComplete = const <String>{},
    this.localCarryComplete = const <String>{},
    this.prunedProfileIds = const <String>{},
    this.prunePendingProfileIds = const <String>{},
    this.targetAdminProfileId,
  });

  final String adoptionId;
  final WebDavSyncAdoptionMode mode;
  final WebDavSyncAdoptionPhase phase;
  final String graphSemanticDigest;
  final Set<String> preRestoreProfileIds;
  final String backupPath;
  final String backupSha256;
  final bool backupVerified;
  final bool completeOnboarding;
  final bool safetyBackupRetained;
  final Map<String, String> circleProfileToNewLocal;
  final Map<String, String> circleResourceToNewLocal;
  final Map<String, String> oldToNewProfiles;
  final Map<String, String> oldToNewResources;
  final Set<String> unmappedOldResourceIds;
  final Set<String> databaseCopiesComplete;
  final Set<String> databaseRemapsComplete;
  final Set<String> localCarryComplete;
  final Set<String> prunedProfileIds;
  final Set<String> prunePendingProfileIds;
  final String? targetAdminProfileId;

  bool get blocksPushes => phase != WebDavSyncAdoptionPhase.complete;

  WebDavSyncAdoptionRecord copyWith({
    WebDavSyncAdoptionPhase? phase,
    Map<String, String>? circleProfileToNewLocal,
    Map<String, String>? circleResourceToNewLocal,
    Map<String, String>? oldToNewProfiles,
    Map<String, String>? oldToNewResources,
    Set<String>? unmappedOldResourceIds,
    Set<String>? databaseCopiesComplete,
    Set<String>? databaseRemapsComplete,
    Set<String>? localCarryComplete,
    Set<String>? prunedProfileIds,
    Set<String>? prunePendingProfileIds,
    String? targetAdminProfileId,
    bool? safetyBackupRetained,
  }) => WebDavSyncAdoptionRecord(
    adoptionId: adoptionId,
    mode: mode,
    phase: phase ?? this.phase,
    graphSemanticDigest: graphSemanticDigest,
    preRestoreProfileIds: preRestoreProfileIds,
    backupPath: backupPath,
    backupSha256: backupSha256,
    backupVerified: backupVerified,
    completeOnboarding: completeOnboarding,
    safetyBackupRetained: safetyBackupRetained ?? this.safetyBackupRetained,
    circleProfileToNewLocal:
        circleProfileToNewLocal ?? this.circleProfileToNewLocal,
    circleResourceToNewLocal:
        circleResourceToNewLocal ?? this.circleResourceToNewLocal,
    oldToNewProfiles: oldToNewProfiles ?? this.oldToNewProfiles,
    oldToNewResources: oldToNewResources ?? this.oldToNewResources,
    unmappedOldResourceIds:
        unmappedOldResourceIds ?? this.unmappedOldResourceIds,
    databaseCopiesComplete:
        databaseCopiesComplete ?? this.databaseCopiesComplete,
    databaseRemapsComplete:
        databaseRemapsComplete ?? this.databaseRemapsComplete,
    localCarryComplete: localCarryComplete ?? this.localCarryComplete,
    prunedProfileIds: prunedProfileIds ?? this.prunedProfileIds,
    prunePendingProfileIds:
        prunePendingProfileIds ?? this.prunePendingProfileIds,
    targetAdminProfileId: targetAdminProfileId ?? this.targetAdminProfileId,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'version': 1,
    'adoptionId': adoptionId,
    'mode': mode.name,
    'phase': phase.name,
    'graphSemanticDigest': graphSemanticDigest,
    'preRestoreProfileIds': preRestoreProfileIds.toList()..sort(),
    'backupPath': backupPath,
    'backupSha256': backupSha256,
    'backupVerified': backupVerified,
    if (completeOnboarding) 'completeOnboarding': true,
    if (!safetyBackupRetained) 'safetyBackupRetained': false,
    'circleProfileToNewLocal': circleProfileToNewLocal,
    'circleResourceToNewLocal': circleResourceToNewLocal,
    'oldToNewProfiles': oldToNewProfiles,
    'oldToNewResources': oldToNewResources,
    'unmappedOldResourceIds': unmappedOldResourceIds.toList()..sort(),
    'databaseCopiesComplete': databaseCopiesComplete.toList()..sort(),
    'databaseRemapsComplete': databaseRemapsComplete.toList()..sort(),
    'localCarryComplete': localCarryComplete.toList()..sort(),
    'prunedProfileIds': prunedProfileIds.toList()..sort(),
    'prunePendingProfileIds': prunePendingProfileIds.toList()..sort(),
    if (targetAdminProfileId != null)
      'targetAdminProfileId': targetAdminProfileId,
  };

  factory WebDavSyncAdoptionRecord.fromJson(Object? source) {
    if (source is! Map) {
      throw const FormatException('Invalid WebDAV sync adoption record');
    }
    final json = Map<String, dynamic>.from(source);
    if (json['version'] != 1 ||
        json['adoptionId'] is! String ||
        json['graphSemanticDigest'] is! String ||
        json['backupPath'] is! String ||
        json['backupSha256'] is! String ||
        json['backupVerified'] is! bool ||
        (json['completeOnboarding'] ?? false) is! bool ||
        (json['safetyBackupRetained'] ?? true) is! bool) {
      throw const FormatException('Invalid WebDAV sync adoption record');
    }
    final adoptionId = json['adoptionId'] as String;
    final digest = json['graphSemanticDigest'] as String;
    final backupHash = json['backupSha256'] as String;
    if (!_id.hasMatch(adoptionId) ||
        !_digest.hasMatch(digest) ||
        !_digest.hasMatch(backupHash)) {
      throw const FormatException('Invalid WebDAV sync adoption identity');
    }
    final mode = WebDavSyncAdoptionMode.values
        .where((value) => value.name == json['mode'])
        .firstOrNull;
    final phase = WebDavSyncAdoptionPhase.values
        .where((value) => value.name == json['phase'])
        .firstOrNull;
    if (mode == null || phase == null) {
      throw const FormatException('Invalid WebDAV sync adoption phase');
    }
    final rawTargetAdminProfileId = json['targetAdminProfileId'];
    if (rawTargetAdminProfileId != null &&
        (rawTargetAdminProfileId is! String ||
            !_id.hasMatch(rawTargetAdminProfileId))) {
      throw const FormatException('Invalid WebDAV sync adoption target');
    }
    final record = WebDavSyncAdoptionRecord(
      adoptionId: adoptionId,
      mode: mode,
      phase: phase,
      graphSemanticDigest: digest,
      preRestoreProfileIds: _stringSet(
        json['preRestoreProfileIds'],
        'pre-restore profiles',
      ),
      backupPath: json['backupPath'] as String,
      backupSha256: backupHash,
      backupVerified: json['backupVerified'] as bool,
      completeOnboarding: (json['completeOnboarding'] ?? false) as bool,
      safetyBackupRetained: (json['safetyBackupRetained'] ?? true) as bool,
      circleProfileToNewLocal: _stringMap(
        json['circleProfileToNewLocal'],
        'profile map',
      ),
      circleResourceToNewLocal: _stringMap(
        json['circleResourceToNewLocal'],
        'resource map',
      ),
      oldToNewProfiles: _stringMap(
        json['oldToNewProfiles'],
        'predecessor profile map',
      ),
      oldToNewResources: _stringMap(
        json['oldToNewResources'],
        'predecessor resource map',
      ),
      unmappedOldResourceIds: _stringSet(
        json['unmappedOldResourceIds'] ?? const <Object?>[],
        'unmapped predecessor resources',
      ),
      databaseCopiesComplete: _stringSet(
        json['databaseCopiesComplete'],
        'database copies',
      ),
      databaseRemapsComplete: _stringSet(
        json['databaseRemapsComplete'],
        'database remaps',
      ),
      localCarryComplete: _stringSet(json['localCarryComplete'], 'local carry'),
      prunedProfileIds: _stringSet(json['prunedProfileIds'], 'pruned profiles'),
      prunePendingProfileIds: _stringSet(
        json['prunePendingProfileIds'],
        'prune-pending profiles',
      ),
      targetAdminProfileId: rawTargetAdminProfileId as String?,
    );
    if (!record.backupVerified || record.preRestoreProfileIds.isEmpty) {
      throw const FormatException('Incomplete WebDAV sync adoption guard');
    }
    return record;
  }

  static Map<String, String> _stringMap(Object? source, String label) {
    if (source is! Map || source.length > 4096) {
      throw FormatException('Invalid WebDAV sync adoption $label');
    }
    final result = <String, String>{};
    for (final entry in source.entries) {
      if (entry.key is! String ||
          entry.value is! String ||
          !_id.hasMatch(entry.key as String) ||
          !_id.hasMatch(entry.value as String)) {
        throw FormatException('Invalid WebDAV sync adoption $label');
      }
      result[entry.key as String] = entry.value as String;
    }
    return Map<String, String>.unmodifiable(result);
  }

  static Set<String> _stringSet(Object? source, String label) {
    if (source is! List || source.length > 4096) {
      throw FormatException('Invalid WebDAV sync adoption $label');
    }
    final result = <String>{};
    for (final value in source) {
      if (value is! String || !_id.hasMatch(value) || !result.add(value)) {
        throw FormatException('Invalid WebDAV sync adoption $label');
      }
    }
    return Set<String>.unmodifiable(result);
  }
}

final RegExp _id = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$');
final RegExp _digest = RegExp(r'^[0-9a-f]{64}$');
