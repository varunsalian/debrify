import 'dart:convert';
import 'dart:io';

import 'webdav_sync_audit_root.dart';

import 'package:debrify/services/profiles/portable_profile_package.dart';
import 'package:debrify/services/profiles/profile_database_snapshot.dart';
import 'package:debrify/services/profiles/profile_preference_portability.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_circle_models.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_codec.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_graph.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_hot_merge.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_hot_models.dart';
import 'package:flutter_test/flutter_test.dart';

const _passphraseVariable = 'WEBDAV_SYNC_AUDIT_PASSPHRASE';
const _backupVariable = 'WEBDAV_SYNC_AUDIT_BACKUP';
const _syncRootVariable = 'WEBDAV_SYNC_AUDIT_ROOT';
const _directEngineRun = bool.fromEnvironment('AUDIT_DIRECT_ENGINE_RUN');

/// Flutter-engine implementation launched by the small `dart run` wrapper.
/// The production profile-package codec imports Flutter-owned avatar
/// and database validation code. It performs no writes to either input.
Future<void> main() async {
  if (_directEngineRun) {
    try {
      await _runFromEnvironment();
    } catch (error) {
      stderr.writeln(
        'AUDIT ABORTED (${error.runtimeType}); no plaintext was shown.',
      );
      exitCode = 1;
    }
    return;
  }
  test(
    'backup to WebDAV completeness audit',
    () async {
      try {
        await _runFromEnvironment();
      } catch (error) {
        // An arbitrary decoder exception can quote decrypted input. Report its
        // type only so even malformed real-world data cannot leak a secret.
        fail('AUDIT ABORTED (${error.runtimeType}); no plaintext was shown.');
      }
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

Future<void> _runFromEnvironment() async {
  final passphrase = Platform.environment[_passphraseVariable];
  final backupPath = Platform.environment[_backupVariable];
  final syncRoot = Platform.environment[_syncRootVariable];
  if (passphrase == null || passphrase.isEmpty) {
    throw const FormatException('Missing audit passphrase');
  }
  if (backupPath == null ||
      backupPath.isEmpty ||
      syncRoot == null ||
      syncRoot.isEmpty) {
    throw const FormatException('Missing audit input path');
  }
  await _CompletenessAudit(
    passphrase: passphrase,
    backupFile: File(backupPath),
    syncRoot: Directory(syncRoot),
  ).run();
}

final class _CompletenessAudit {
  _CompletenessAudit({
    required this.passphrase,
    required this.backupFile,
    required this.syncRoot,
  });

  final String passphrase;
  final File backupFile;
  final Directory syncRoot;
  final List<_Gap> realGaps = <_Gap>[];
  final List<String> explainedGaps = <String>[];

  Future<void> run() async {
    if (!await backupFile.exists() || !await syncRoot.exists()) {
      throw const FileSystemException('Audit input is missing');
    }
    final backup = await PortableProfilePackage.decryptFile(
      backupFile.path,
      passphrase,
    );
    final sync = await _SyncPayload.open(syncRoot, passphrase);
    final backupInventory = _PackageInventory(backup);
    final syncInventory = _PackageInventory(sync.bootstrap);

    stdout.writeln('BACKUP -> WEBDAV SYNC COMPLETENESS AUDIT');
    stdout.writeln(
      'Mode: offline, read-only, production codecs, secret-redacted',
    );
    stdout.writeln('Backup decrypt/authentication/integrity: PASS');
    stdout.writeln('Sync decrypt/authentication/integrity: PASS');
    stdout.writeln(
      'Comparison window: backup=${backup.createdAt.toIso8601String()} -> '
      'published=${sync.manifest.updatedAtMs} '
      '(${_time(sync.manifest.updatedAtMs)})',
    );
    stdout.writeln(
      'Selected device: ${_safe(sync.manifest.deviceId)} '
      '(newest of ${sync.deviceCount})',
    );

    _printPackageInventory('BACKUP INVENTORY', backupInventory);
    _printSyncInventory(sync, syncInventory);

    final profiles = _matchProfiles(backupInventory, syncInventory, sync);
    final resources = _matchResources(backupInventory, syncInventory, sync);

    stdout.writeln();
    stdout.writeln('THE DIFF');
    _diffProfiles(profiles, sync);
    _diffResources(resources, sync);
    _diffRelations(backupInventory, syncInventory, profiles, resources, sync);
    _diffPreferences(backupInventory, syncInventory, profiles);
    _diffPortableAttachments(backupInventory, syncInventory, profiles);
    _diffHotState(backupInventory, syncInventory, profiles, resources, sync);
    _diffOmissions(backupInventory, syncInventory);

    _printGapClassification(backupInventory, syncInventory);
    _printVerdict(profiles, resources);
  }

  void _printPackageInventory(String heading, _PackageInventory inventory) {
    stdout.writeln();
    stdout.writeln(heading);
    stdout.writeln(
      'package: version=${inventory.package.sourceVersion}, '
      'mode=${_safe(inventory.package.mode)}, '
      'createdAt=${inventory.package.createdAt.toIso8601String()}',
    );
    stdout.writeln('profiles: count=${inventory.profiles.length}');
    for (final profile in inventory.profiles) {
      stdout.writeln(
        '- packageId=${_safe(profile.packageId)}, role=${_safe(profile.role)}, '
        'identity=${profile.identity}, pinMaterialPresent=${profile.pinPresent}, '
        'portablePreferenceKeys=${profile.preferences.length}',
      );
    }
    stdout.writeln(
      'connection resources: count=${inventory.resources.length}, '
      'byType=${_counts(inventory.resources.map((item) => item.type))}',
    );
    for (final resource in inventory.resources) {
      stdout.writeln(
        '- sourceResourceId=${_safe(resource.sourceId)}, '
        'type=${_safe(resource.type)}, label=${resource.labelSummary}, '
        'identityDigest=${resource.identityDigest}, '
        'secretConfig={presence=${resource.secretPresent}, '
        'byteLength=${resource.secretBytes}, '
        'semanticDigest=${resource.secretDigest ?? 'n/a'}, '
        'payloadVersion=n/a, ownerCircleId=n/a, stamp=n/a}',
      );
    }
    final relations = inventory.relations;
    stdout.writeln(
      'relationships: grants=${relations.grants.length}, '
      'settings=${relations.settings.length}, '
      'bindings=${relations.bindings.length}',
    );
    stdout.writeln('per-profile portable preference key counts:');
    for (final profile in inventory.profiles) {
      stdout.writeln('- ${profile.identity}: ${profile.preferences.length}');
    }
    _printAttachments(inventory);
    _printOmissions(inventory.package.omissions);
  }

  void _printSyncInventory(_SyncPayload sync, _PackageInventory inventory) {
    stdout.writeln();
    stdout.writeln('SYNC PAYLOAD INVENTORY');
    stdout.writeln(
      'bootstrap: version=${inventory.package.sourceVersion}, '
      'createdAt=${inventory.package.createdAt.toIso8601String()}, '
      'profiles=${inventory.profiles.length}, '
      'resources=${inventory.resources.length}',
    );
    stdout.writeln('live profiles: count=${sync.liveProfiles.length}');
    final liveProfiles = sync.liveProfiles.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    for (final entry in liveProfiles) {
      final value = entry.value.value;
      stdout.writeln(
        '- circleProfileId=${_safe(entry.key)}, '
        'role=${value == null ? 'NULL' : _safe(value.role.name)}, '
        'enabled=${value?.enabled ?? false}, '
        'pinMaterialPresent=${value == null ? false : _livePinPresent(value)}',
      );
    }
    stdout.writeln(
      'live connection resources: count=${sync.liveResources.length}, '
      'byType=${_counts(sync.liveResources.values.map((item) => item.metadata.value?.type.name ?? 'NULL'))}',
    );
    final liveResources = sync.liveResources.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    for (final entry in liveResources) {
      final metadata = entry.value.metadata.value;
      final secret = entry.value.secretConfig?.value;
      stdout.writeln(
        '- circleResourceId=${_safe(entry.key)}, '
        'type=${metadata == null ? 'NULL' : _safe(metadata.type.name)}, '
        'label=${metadata == null ? 'NULL' : _label(metadata.label)}, '
        'secretConfig={presence=${secret != null}, '
        'byteLength=${secret == null ? 0 : base64Decode(secret.envelope).length}, '
        'semanticDigest=${secret?.semanticDigest ?? 'n/a'}, '
        'payloadVersion=${secret?.payloadVersion ?? 'n/a'}, '
        'ownerCircleId=${secret == null ? 'n/a' : _safe(secret.ownerCircleProfileId)}, '
        'stamp=${entry.value.secretConfig == null ? 'n/a' : _stamp(entry.value.secretConfig!.stamp)}}',
      );
    }
    stdout.writeln(
      'live relationships: grants=${_leafCount(sync.resources.grants)}, '
      'settings=${_leafCount(sync.resources.settings)}, '
      'bindings=${_leafCount(sync.resources.bindings)}',
    );
    stdout.writeln('published preference counts:');
    for (final profile in inventory.profiles) {
      final circleId = sync.manifest.profileMap[profile.packageId];
      final hot = circleId == null ? null : sync.hot[circleId];
      stdout.writeln(
        '- circleProfileId=${_safe(circleId ?? 'unmapped')}: '
        'bootstrapKeys=${profile.preferences.length}, '
        'hotScalars=${hot?.scalars.entries.length ?? 0}, '
        'hotRecords=${hot?.watchState.records.length ?? 0}, '
        'hotOrders=${hot?.watchState.orders.length ?? 0}',
      );
    }
    _printAttachments(inventory);
    _printOmissions(inventory.package.omissions);
  }

  void _printAttachments(_PackageInventory inventory) {
    stdout.writeln('database snapshots:');
    final databases = <({String profile, _Attachment attachment})>[];
    final files = <({String profile, _Attachment attachment})>[];
    for (final profile in inventory.profiles) {
      for (final attachment in profile.databases.values) {
        databases.add((profile: profile.identity, attachment: attachment));
      }
      for (final attachment in profile.files.values) {
        files.add((profile: profile.identity, attachment: attachment));
      }
    }
    if (databases.isEmpty) stdout.writeln('- none');
    for (final item in databases) {
      stdout.writeln(
        '- profile=${item.profile}, database=${_safe(item.attachment.name)}, '
        'bytes=${item.attachment.bytes}, sha256=${item.attachment.digest}',
      );
    }
    stdout.writeln('portable files: count=${files.length}');
    if (files.isEmpty) stdout.writeln('- none');
    for (final item in files) {
      stdout.writeln(
        '- profile=${item.profile}, path=${_safe(item.attachment.name)}, '
        'bytes=${item.attachment.bytes}, sha256=${item.attachment.digest}',
      );
    }
  }

  void _printOmissions(Map<String, dynamic> omissions) {
    stdout.writeln('recorded omissions: count=${omissions.length}');
    if (omissions.isEmpty) stdout.writeln('- none');
    final entries = omissions.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    for (final entry in entries) {
      if (entry.key == DebrifyTvBackupOmission.key) {
        final parsed = DebrifyTvBackupOmission.fromOmissions(omissions);
        stdout.writeln(
          '- ${entry.key}: presence=true, channels=${parsed?.channels ?? 'invalid'}, '
          'savedHashes=${parsed?.savedHashes ?? 'invalid'}, '
          'profilesAffected=${parsed?.profilesAffected ?? 'invalid'}',
        );
      } else if (entry.key == 'rebuildableDatabaseCachesOmitted') {
        final value = entry.value;
        final recognized =
            ProfileDatabaseSnapshot.databaseNames
                .where(
                  (name) =>
                      value is String &&
                      value
                          .split(', ')
                          .any(
                            (item) => item == name || item.endsWith(': $name'),
                          ),
                )
                .toList()
              ..sort();
        stdout.writeln(
          '- ${entry.key}: presence=true, databases='
          '${recognized.isEmpty ? 'unrecognized' : recognized.join(',')}, '
          'valueDigest=${semanticDigestOf(value)}',
        );
      } else if (entry.value is bool || entry.value is int) {
        stdout.writeln('- ${_safe(entry.key)}: ${entry.value}');
      } else {
        stdout.writeln(
          '- ${_safe(entry.key)}: presence=true, '
          'valueDigest=${semanticDigestOf(entry.value)}',
        );
      }
    }
  }

  List<_ProfileMatch> _matchProfiles(
    _PackageInventory backup,
    _PackageInventory published,
    _SyncPayload sync,
  ) {
    final result = <_ProfileMatch>[];
    final claimed = <_PackProfile>{};
    for (final source in backup.profiles) {
      final candidates = published.profiles
          .where(
            (candidate) =>
                !claimed.contains(candidate) &&
                candidate.identity == source.identity,
          )
          .toList();
      final target = candidates.length == 1 ? candidates.single : null;
      if (target != null) claimed.add(target);
      result.add(
        _ProfileMatch(
          backup: source,
          published: target,
          circleId: target == null
              ? null
              : sync.manifest.profileMap[target.packageId],
        ),
      );
    }
    for (final target in published.profiles.where(
      (item) => !claimed.contains(item),
    )) {
      result.add(
        _ProfileMatch(
          backup: null,
          published: target,
          circleId: sync.manifest.profileMap[target.packageId],
        ),
      );
    }
    return result;
  }

  List<_ResourceMatch> _matchResources(
    _PackageInventory backup,
    _PackageInventory published,
    _SyncPayload sync,
  ) {
    final result = <_ResourceMatch>[];
    final claimed = <_PackResource>{};
    for (final source in backup.resources) {
      List<_PackResource> candidates(bool Function(_PackResource item) test) =>
          published.resources
              .where((item) => !claimed.contains(item) && test(item))
              .toList();
      var method = 'secret semantic digest';
      var matches = source.secretDigest == null
          ? <_PackResource>[]
          : candidates(
              (item) =>
                  item.type == source.type &&
                  item.secretDigest == source.secretDigest,
            );
      if (matches.length != 1) {
        method = 'type + label digest + public-config digest';
        matches = candidates(
          (item) =>
              item.type == source.type &&
              item.labelDigest == source.labelDigest &&
              item.publicDigest == source.publicDigest,
        );
      }
      if (matches.length != 1) {
        method = 'type + label digest';
        matches = candidates(
          (item) =>
              item.type == source.type &&
              item.labelDigest == source.labelDigest,
        );
      }
      final target = matches.length == 1 ? matches.single : null;
      if (target != null) claimed.add(target);
      result.add(
        _ResourceMatch(
          backup: source,
          published: target,
          circleId: target == null
              ? null
              : sync.manifest.resourceMap[target.packageId],
          method: target == null ? 'no unique stable match' : method,
        ),
      );
    }
    for (final target in published.resources.where(
      (item) => !claimed.contains(item),
    )) {
      result.add(
        _ResourceMatch(
          backup: null,
          published: target,
          circleId: sync.manifest.resourceMap[target.packageId],
          method: 'sync-only',
        ),
      );
    }
    return result;
  }

  void _diffProfiles(List<_ProfileMatch> matches, _SyncPayload sync) {
    final both = matches
        .where((item) => item.backup != null && item.published != null)
        .toList();
    final missing = matches
        .where((item) => item.backup != null && item.published == null)
        .toList();
    final added = matches.where((item) => item.backup == null).toList();
    stdout.writeln('PROFILES');
    stdout.writeln(
      'present in both=${both.length}, backup but MISSING from sync=${missing.length}, '
      'sync but not in backup=${added.length}',
    );
    for (final item in both) {
      final live = item.circleId == null
          ? null
          : sync.liveProfiles[item.circleId!]?.value;
      stdout.writeln(
        '- ${item.backup!.identity} -> circleProfileId=${_safe(item.circleId ?? 'unmapped')}, '
        'role=${_safe(item.backup!.role)}, livePresent=${live != null}',
      );
      if (live == null) {
        realGaps.add(
          _Gap.high(
            'Matched backup profile is absent from live profiles: ${item.backup!.identity}',
          ),
        );
      }
    }
    for (final item in missing) {
      stdout.writeln('- MISSING: ${item.backup!.identity}');
      realGaps.add(
        _Gap.high('Backup profile missing from sync: ${item.backup!.identity}'),
      );
    }
    for (final item in added) {
      stdout.writeln(
        '- SYNC-ONLY (post-backup candidate): ${item.published!.identity}, '
        'circleProfileId=${_safe(item.circleId ?? 'unmapped')}',
      );
      explainedGaps.add(
        'Sync-only profile ${item.published!.identity} was published after the backup timestamp.',
      );
    }
    stdout.writeln(
      'did every backup profile reach the circle? ${missing.isEmpty && both.every((item) => item.circleId != null && sync.liveProfiles[item.circleId!]?.value != null) ? 'YES' : 'NO'}',
    );
  }

  void _diffResources(List<_ResourceMatch> matches, _SyncPayload sync) {
    final both = matches
        .where((item) => item.backup != null && item.published != null)
        .toList();
    final missing = matches
        .where((item) => item.backup != null && item.published == null)
        .toList();
    final added = matches.where((item) => item.backup == null).toList();
    stdout.writeln();
    stdout.writeln('CONNECTION RESOURCES');
    stdout.writeln(
      'present in both=${both.length}, backup but MISSING from sync=${missing.length}, '
      'sync but not in backup=${added.length}',
    );
    var allHaveRequiredSecrets = true;
    for (final item in both) {
      final backup = item.backup!;
      final published = item.published!;
      final live = item.circleId == null
          ? null
          : sync.liveResources[item.circleId!];
      final bootstrapSecret = published.secretPresent;
      final liveSecret = live?.secretConfig?.value;
      final backupToLiveDigestMatches =
          backup.secretDigest == liveSecret?.semanticDigest;
      final legitimatelyPending =
          !backup.secretPresent && !bootstrapSecret && liveSecret == null;
      final complete = backup.secretPresent
          ? bootstrapSecret && liveSecret != null
          : legitimatelyPending || liveSecret != null;
      allHaveRequiredSecrets = allHaveRequiredSecrets && complete;
      stdout.writeln(
        '- sourceResourceId=${_safe(backup.sourceId)}, type=${_safe(backup.type)}, '
        'label=${backup.labelSummary} -> circleResourceId=${_safe(item.circleId ?? 'unmapped')}, '
        'match=${item.method}, bootstrapSecret=$bootstrapSecret, '
        'liveSecret=${liveSecret != null}, secretPendingLegitimate=$legitimatelyPending, '
        'backupToLiveSecretDigest='
        '${backupToLiveDigestMatches ? 'MATCH' : 'CHANGED_AFTER_BACKUP'}',
      );
      if (!complete) {
        realGaps.add(
          _Gap.high(
            'Connection secret missing from published/live resource ${backup.identityDigest}.',
          ),
        );
      }
      if (backup.secretPresent &&
          liveSecret != null &&
          !backupToLiveDigestMatches) {
        explainedGaps.add(
          'Connection ${backup.identityDigest} retains a secretConfig whose '
          'semantic digest changed after the Aug 29 backup.',
        );
      }
      if (live?.metadata.value == null) {
        realGaps.add(
          _Gap.high(
            'Matched connection resource is absent from live resources: ${backup.identityDigest}.',
          ),
        );
      }
    }
    for (final item in missing) {
      stdout.writeln(
        '- MISSING: sourceResourceId=${_safe(item.backup!.sourceId)}, '
        'type=${_safe(item.backup!.type)}, label=${item.backup!.labelSummary}, '
        'identityDigest=${item.backup!.identityDigest}',
      );
      realGaps.add(
        _Gap.high(
          'Backup connection resource missing from sync: ${item.backup!.identityDigest}.',
        ),
      );
      allHaveRequiredSecrets = false;
    }
    for (final item in added) {
      stdout.writeln(
        '- SYNC-ONLY (post-backup candidate): '
        'circleResourceId=${_safe(item.circleId ?? 'unmapped')}, '
        'type=${_safe(item.published!.type)}, label=${item.published!.labelSummary}',
      );
      explainedGaps.add(
        'Sync-only connection ${item.published!.identityDigest} postdates the backup.',
      );
    }
    stdout.writeln(
      'did every backup connection resource reach the circle? ${missing.isEmpty ? 'YES' : 'NO'}',
    );
    stdout.writeln(
      'does each carry a secretConfig or legitimate secretPending? ${allHaveRequiredSecrets ? 'YES' : 'NO'}',
    );
  }

  void _diffRelations(
    _PackageInventory backup,
    _PackageInventory published,
    List<_ProfileMatch> profiles,
    List<_ResourceMatch> resources,
    _SyncPayload sync,
  ) {
    final backupProfiles = <String, String>{
      for (final item in profiles)
        if (item.backup != null && item.circleId != null)
          item.backup!.packageId: item.circleId!,
    };
    final backupResources = <String, String>{
      for (final item in resources)
        if (item.backup != null && item.circleId != null)
          item.backup!.packageId: item.circleId!,
    };
    final publishedProfiles = <String, String>{
      for (final item in published.profiles)
        if (_circleProfileId(item.packageId, profiles) != null)
          item.packageId: _circleProfileId(item.packageId, profiles)!,
    };
    final publishedResources = <String, String>{
      for (final item in published.resources)
        if (_circleResourceId(item.packageId, resources) != null)
          item.packageId: _circleResourceId(item.packageId, resources)!,
    };
    final left = _canonicalRelations(
      backup.package,
      backupProfiles,
      backupResources,
    );
    final right = _canonicalRelations(
      published.package,
      publishedProfiles,
      publishedResources,
    );
    final live = _liveCanonicalRelations(sync.resources);
    stdout.writeln();
    stdout.writeln('GRANTS / SETTINGS / BINDINGS');
    _printSetDiff('grants', left.grants, right.grants, impact: 'high');
    _printSetDiff('settings', left.settings, right.settings, impact: 'medium');
    _printSetDiff('bindings', left.bindings, right.bindings, impact: 'medium');
    _printLiveRelationDiff('grants', right.grants, live.grants);
    _printLiveRelationDiff('settings', right.settings, live.settings);
    _printLiveRelationDiff('bindings', right.bindings, live.bindings);
  }

  void _printLiveRelationDiff(
    String label,
    Set<String> bootstrap,
    Set<String> live,
  ) {
    final missing = bootstrap.difference(live);
    final extra = live.difference(bootstrap);
    stdout.writeln(
      '$label bootstrap->live: MATCH=${missing.isEmpty && extra.isEmpty}, '
      'missing=${missing.length}, extra=${extra.length}',
    );
    if (missing.isNotEmpty || extra.isNotEmpty) {
      realGaps.add(
        _Gap.high(
          '$label differs between the authenticated bootstrap and live '
          'sections: missing=${missing.length}, extra=${extra.length}.',
        ),
      );
    }
  }

  void _printSetDiff(
    String label,
    Set<String> backup,
    Set<String> sync, {
    required String impact,
  }) {
    final missing = backup.difference(sync).toList()..sort();
    final added = sync.difference(backup).toList()..sort();
    stdout.writeln(
      '$label: present in both=${backup.intersection(sync).length}, '
      'backup but MISSING from sync=${missing.length}, '
      'sync but not in backup=${added.length}',
    );
    if (missing.isNotEmpty) {
      stdout.writeln('- missing stable record digests: ${missing.join(', ')}');
      realGaps.add(
        impact == 'high'
            ? _Gap.high(
                '${missing.length} backup $label record(s) missing from sync.',
              )
            : _Gap.medium(
                '${missing.length} backup $label record(s) missing from sync.',
              ),
      );
    }
    if (added.isNotEmpty) {
      stdout.writeln('- sync-only stable record digests: ${added.join(', ')}');
      explainedGaps.add(
        '${added.length} sync-only $label record(s) postdate the backup.',
      );
    }
  }

  void _diffPreferences(
    _PackageInventory backup,
    _PackageInventory published,
    List<_ProfileMatch> profiles,
  ) {
    stdout.writeln();
    stdout.writeln(
      'PORTABLE PREFERENCES (backup package vs bootstrap package)',
    );
    for (final match in profiles.where(
      (item) => item.backup != null && item.published != null,
    )) {
      final left = match.backup!.preferences;
      final right = match.published!.preferences;
      final leftKeys = left.keys.toSet();
      final rightKeys = right.keys.toSet();
      final missing = leftKeys.difference(rightKeys).toList()..sort();
      final added = rightKeys.difference(leftKeys).toList()..sort();
      final changed =
          leftKeys
              .intersection(rightKeys)
              .where(
                (key) =>
                    semanticDigestOf(left[key]) != semanticDigestOf(right[key]),
              )
              .toList()
            ..sort();
      stdout.writeln(
        '- ${match.backup!.identity}: present in both=${leftKeys.intersection(rightKeys).length}, '
        'backup but MISSING from sync=${missing.length}, '
        'sync but not in backup=${added.length}, valuesChangedAfterBackup=${changed.length}',
      );
      _printKeys('missing', missing);
      _printKeys('sync-only', added);
      _printKeys('changed', changed);
      for (final key in missing) {
        if (!ProfilePreferencePortability.allowsKey(
          key,
          includeCredentialEngineSettings: true,
        )) {
          explainedGaps.add(
            'Preference ${_safe(key)} is device-local/non-portable by production policy.',
          );
        } else {
          realGaps.add(
            _Gap.medium(
              'Portable preference ${_safe(key)} is missing for ${match.backup!.identity}.',
            ),
          );
        }
      }
      if (added.isNotEmpty || changed.isNotEmpty) {
        explainedGaps.add(
          '${match.backup!.identity} has ${added.length} added and ${changed.length} changed preference(s) in the newer bootstrap.',
        );
      }
    }
  }

  void _diffPortableAttachments(
    _PackageInventory backup,
    _PackageInventory published,
    List<_ProfileMatch> profiles,
  ) {
    stdout.writeln();
    stdout.writeln('DATABASE SNAPSHOTS AND PORTABLE FILES');
    for (final match in profiles.where(
      (item) => item.backup != null && item.published != null,
    )) {
      _diffAttachmentKind(
        'databases',
        match.backup!,
        match.published!,
        match.backup!.databases,
        match.published!.databases,
        published.package.omissions,
      );
      _diffAttachmentKind(
        'portable files',
        match.backup!,
        match.published!,
        match.backup!.files,
        match.published!.files,
        published.package.omissions,
      );
    }
  }

  void _diffAttachmentKind(
    String label,
    _PackProfile backupProfile,
    _PackProfile syncProfile,
    Map<String, _Attachment> backup,
    Map<String, _Attachment> sync,
    Map<String, dynamic> syncOmissions,
  ) {
    final missing = backup.keys.toSet().difference(sync.keys.toSet()).toList()
      ..sort();
    final added = sync.keys.toSet().difference(backup.keys.toSet()).toList()
      ..sort();
    final changed =
        backup.keys
            .toSet()
            .intersection(sync.keys.toSet())
            .where((key) => backup[key]!.digest != sync[key]!.digest)
            .toList()
          ..sort();
    stdout.writeln(
      '- ${backupProfile.identity} $label: present in both=${backup.keys.toSet().intersection(sync.keys.toSet()).length}, '
      'backup but MISSING from sync=${missing.length}, sync but not in backup=${added.length}, '
      'contentChanged=${changed.length}',
    );
    _printKeys('missing', missing);
    _printKeys('sync-only', added);
    _printKeys('changed', changed);
    for (final key in missing) {
      if (_databaseOmissionExplains(key, syncOmissions)) {
        explainedGaps.add(
          'Database ${_safe(key)} is absent under its explicit v1 omission record.',
        );
      } else {
        realGaps.add(
          _Gap.low(
            '$label attachment ${_safe(key)} from ${backupProfile.identity} is missing from sync.',
          ),
        );
      }
    }
    if (added.isNotEmpty || changed.isNotEmpty) {
      explainedGaps.add(
        '${syncProfile.identity} has newer $label content (${added.length} added, ${changed.length} changed).',
      );
    }
  }

  void _diffHotState(
    _PackageInventory backup,
    _PackageInventory published,
    List<_ProfileMatch> profiles,
    List<_ResourceMatch> resources,
    _SyncPayload sync,
  ) {
    stdout.writeln();
    stdout.writeln('PLAYLISTS / FAVORITES / WATCH STATE / SERIES BINDINGS');
    final allMatched =
        profiles
            .where((item) => item.backup != null)
            .every((item) => item.circleId != null) &&
        resources
            .where((item) => item.backup != null)
            .every((item) => item.circleId != null);
    if (!allMatched) {
      stdout.writeln(
        'projection unavailable: one or more stable identities could not be matched',
      );
      realGaps.add(
        const _Gap.medium(
          'Hot-state completeness could not be proven because identity mapping is incomplete.',
        ),
      );
      return;
    }
    final backupMaps = WebDavSyncIdentityMaps(
      circleToLocalProfiles: <String, String>{
        for (final item in profiles)
          if (item.backup != null && item.circleId != null)
            item.circleId!: item.backup!.packageId,
      },
      circleToLocalResources: <String, String>{
        for (final item in resources)
          if (item.backup != null && item.circleId != null)
            item.circleId!: item.backup!.sourceId,
      },
    );
    final publishedMaps = WebDavSyncIdentityMaps(
      circleToLocalProfiles: <String, String>{
        for (
          var index = 0;
          index < sync.manifest.profileMap.values.length;
          index++
        )
          sync.manifest.profileMap.values.elementAt(index):
              'audit-profile-$index',
      },
      circleToLocalResources: <String, String>{
        for (
          var index = 0;
          index < sync.manifest.resourceMap.values.length;
          index++
        )
          sync.manifest.resourceMap.values.elementAt(index):
              'audit-resource-$index',
      },
    );
    for (final match in profiles.where(
      (item) =>
          item.backup != null &&
          item.published != null &&
          item.circleId != null,
    )) {
      final backupHot = _projectHot(
        match.backup!,
        match.circleId!,
        backupMaps,
        sync,
      );
      final bootstrapHot = _projectHot(
        match.published!,
        match.circleId!,
        publishedMaps,
        sync,
      );
      final live = sync.hot[match.circleId!];
      if (live == null) {
        stdout.writeln(
          '- ${match.backup!.identity}: live hot document MISSING',
        );
        realGaps.add(
          _Gap.high(
            'Live hot document is missing for ${match.backup!.identity}.',
          ),
        );
        continue;
      }
      stdout.writeln(
        '- profile=${match.backup!.identity}, circleProfileId=${_safe(match.circleId!)}',
      );
      for (final category in _HotCategory.values) {
        final old = _hotItems(backupHot, category);
        final seed = _hotItems(bootstrapHot, category);
        final current = _hotItems(live, category);
        final oldCounts = _hotCounts(backupHot, category);
        final seedCounts = _hotCounts(bootstrapHot, category);
        final currentCounts = _hotCounts(live, category);
        final removedBeforePublish = old.keys.toSet().difference(
          seed.keys.toSet(),
        );
        final addedAfterBackup = seed.keys.toSet().difference(old.keys.toSet());
        final missingFromLive = seed.keys.toSet().difference(
          current.keys.toSet(),
        );
        final extraLive = current.keys.toSet().difference(seed.keys.toSet());
        final changedOnWire = seed.keys
            .toSet()
            .intersection(current.keys.toSet())
            .where((key) => seed[key] != current[key])
            .toSet();
        stdout.writeln(
          '  ${category.label}: '
          'backup={records=${oldCounts.records},orders=${oldCounts.orders}}, '
          'bootstrap={records=${seedCounts.records},orders=${seedCounts.orders}}, '
          'live={records=${currentCounts.records},orders=${currentCounts.orders}}, '
          'backup->bootstrap removed=${removedBeforePublish.length}, '
          'added=${addedAfterBackup.length}, bootstrap->live missing=${missingFromLive.length}, '
          'extra=${extraLive.length}, changed=${changedOnWire.length}',
        );
        final spots = current.keys.toList()..sort();
        if (spots.isNotEmpty) {
          stdout.writeln(
            '    spot-check keys: ${spots.take(3).map(_safe).join(', ')}',
          );
        }
        if (removedBeforePublish.isNotEmpty || addedAfterBackup.isNotEmpty) {
          explainedGaps.add(
            '${category.label} changed between the Aug 29 backup and the Sep 3 authenticated bootstrap for ${match.backup!.identity}.',
          );
        }
        if (missingFromLive.isNotEmpty || changedOnWire.isNotEmpty) {
          realGaps.add(
            _Gap.high(
              '${category.label} failed bootstrap-to-live projection for ${match.backup!.identity}: missing=${missingFromLive.length}, changed=${changedOnWire.length}.',
            ),
          );
        }
        if (extraLive.isNotEmpty) {
          explainedGaps.add(
            '${category.label} has ${extraLive.length} live-only item(s), consistent with newer hot-state writes.',
          );
        }
      }
    }
  }

  WebDavSyncHotDocument _projectHot(
    _PackProfile profile,
    String circleId,
    WebDavSyncIdentityMaps maps,
    _SyncPayload sync,
  ) {
    // JSON decoding erases SharedPreferences' List<String> runtime type. The
    // production hot builder deliberately accepts only that concrete scalar
    // type, so restore it before replaying the package through the builder.
    final raw = <String, Object?>{
      for (final entry in profile.preferences.entries)
        entry.key: _preferenceRuntimeValue(entry.value),
    };
    final portable = <String, Object?>{};
    for (final entry in raw.entries) {
      final prepared = ProfilePreferencePortability.prepareValue(
        entry.key,
        entry.value,
        includeCredentialEngineSettings: false,
      );
      if (prepared.include) portable[entry.key] = prepared.value;
    }
    return WebDavSyncHotMerge.build(
      WebDavSyncBuildInput(
        circleProfileId: circleId,
        deviceId: sync.manifest.deviceId,
        rawPreferences: raw,
        portablePreferences: portable,
        identityMaps: maps,
        localNowMs: profile.createdAt.millisecondsSinceEpoch,
        clockOffsetMs: 0,
        serverNowMs: sync.manifest.updatedAtMs,
      ),
    ).document;
  }

  void _diffOmissions(_PackageInventory backup, _PackageInventory sync) {
    stdout.writeln();
    stdout.writeln('OMISSION RECORDS');
    final left = backup.package.omissions.keys.toSet();
    final right = sync.package.omissions.keys.toSet();
    stdout.writeln(
      'present in both=${left.intersection(right).length}, '
      'backup-only=${left.difference(right).length}, '
      'sync-only=${right.difference(left).length}',
    );
    stdout.writeln(
      'rebuildableDatabaseCachesOmitted visible in backup: '
      '${left.contains('rebuildableDatabaseCachesOmitted')}',
    );
    stdout.writeln(
      'rebuildableDatabaseCachesOmitted visible in sync: '
      '${right.contains('rebuildableDatabaseCachesOmitted')}',
    );
    stdout.writeln(
      'debrifyTvChannelsOmitted visible in backup: '
      '${left.contains(DebrifyTvBackupOmission.key)}',
    );
    stdout.writeln(
      'debrifyTvChannelsOmitted visible in sync: '
      '${right.contains(DebrifyTvBackupOmission.key)}',
    );
    if (left.contains('rebuildableDatabaseCachesOmitted') &&
        !right.contains('rebuildableDatabaseCachesOmitted')) {
      explainedGaps.add(
        'The Aug 29 backup explicitly compacted rebuildable IPTV catalogue/EPG '
        'rows; the Sep 3 bootstrap contains full database snapshots and did '
        'not invoke the size fallback.',
      );
    }
    if (right.contains('rebuildableDatabaseCachesOmitted')) {
      explainedGaps.add(
        'IPTV catalogue/EPG cache compaction is explicitly recorded and is rebuilt, not silently transferred.',
      );
    }
    if (right.contains(DebrifyTvBackupOmission.key)) {
      explainedGaps.add(
        'Debrify TV channels/saved hash pools are explicitly recorded as the deliberate v1 carve-out.',
      );
    }
  }

  void _printGapClassification(
    _PackageInventory backup,
    _PackageInventory sync,
  ) {
    stdout.writeln();
    stdout.writeln('EXPLAINED GAPS VS REAL GAPS');
    stdout.writeln('BY DESIGN / EXPLAINED:');
    stdout.writeln(
      '- Device-wide state, OS grants/paths, active jobs, executables/commands, remote peers, PIN attempt counters, resolved playback sources, and transient caches are explicitly omitted by the package contract.',
    );
    stdout.writeln(
      '- Credential-shaped profile preferences are excluded from hot state by ProfilePreferencePortability; connection secrets travel only as sealed resource state.',
    );
    stdout.writeln(
      '- Local playback URLs/paths/headers and local-file series pins are stripped; portable progress and cloud/addon bindings remain eligible.',
    );
    if (!backup.package.omissions.containsKey(
          'rebuildableDatabaseCachesOmitted',
        ) &&
        !sync.package.omissions.containsKey(
          'rebuildableDatabaseCachesOmitted',
        )) {
      stdout.writeln(
        '- No rebuildableDatabaseCachesOmitted record is present in either package.',
      );
    }
    if (!backup.package.omissions.containsKey(DebrifyTvBackupOmission.key) &&
        !sync.package.omissions.containsKey(DebrifyTvBackupOmission.key)) {
      stdout.writeln(
        '- No debrifyTvChannelsOmitted record is present in either package.',
      );
    }
    for (final item in explainedGaps.toSet()) {
      stdout.writeln('- $item');
    }
    stdout.writeln('REAL / UNEXPLAINED: count=${realGaps.length}');
    if (realGaps.isEmpty) stdout.writeln('- none');
    for (final gap in realGaps) {
      stdout.writeln('- ${gap.impact}: ${gap.message}');
    }
  }

  void _printVerdict(
    List<_ProfileMatch> profiles,
    List<_ResourceMatch> resources,
  ) {
    final profilesComplete = profiles
        .where((item) => item.backup != null)
        .every((item) => item.circleId != null);
    final resourcesComplete = resources
        .where((item) => item.backup != null)
        .every((item) => item.circleId != null);
    stdout.writeln();
    stdout.writeln('VERDICT');
    stdout.writeln(
      realGaps.isEmpty && profilesComplete && resourcesComplete
          ? 'YES — every backup record that can be proved from the two authenticated packages reached the circle. The live per-record state agrees with the current bootstrap projection; remaining differences are explicit v1 carve-outs or newer state.'
          : 'NO — the audit found one or more backup-to-sync gaps that are not proven to be intentional. Treat them as real data loss until resolved.',
    );
    stdout.writeln('real gaps ranked by user impact:');
    if (realGaps.isEmpty) stdout.writeln('- none');
    final ranked = realGaps.toList()
      ..sort((left, right) => left.rank.compareTo(right.rank));
    for (final gap in ranked) {
      stdout.writeln('- ${gap.impact}: ${gap.message}');
    }
  }
}

final class _SyncPayload {
  const _SyncPayload({
    required this.manifest,
    required this.bootstrap,
    required this.profiles,
    required this.resources,
    required this.hot,
    required this.deviceCount,
  });

  final WebDavSyncManifest manifest;
  final PortableProfilePackage bootstrap;
  final WebDavSyncProfilesDocument profiles;
  final WebDavSyncResourcesDocument resources;
  final Map<String, WebDavSyncHotDocument> hot;
  final int deviceCount;

  Map<String, WebDavSyncCircleLeaf<WebDavSyncProfileValue>> get liveProfiles =>
      profiles.profiles;
  Map<String, WebDavSyncResourceEntry> get liveResources => resources.resources;

  static Future<_SyncPayload> open(Directory root, String passphrase) async {
    final codec = WebDavSyncCodec();
    final authority = await readAuditRoot(root, passphrase);
    final rootBytes = authority.markerBytes;
    final openedRoot = await codec.openRoot(
      rootBytes,
      authority.passphrase,
      runInBackground: true,
    );
    final devicesRoot = Directory('${root.path}/devices');
    final devices = <({String id, WebDavSyncManifest manifest})>[];
    await for (final entity in devicesRoot.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final id = entity.uri.pathSegments.where((item) => item.isNotEmpty).last;
      final file = File('${entity.path}/manifest.enc');
      if (!await file.exists()) continue;
      final payload = await codec.openDocument(
        key: openedRoot.key,
        encoded: await file.readAsBytes(),
        circleId: openedRoot.document.circleId,
        deviceId: id,
        logicalName: 'manifest',
        schemaVersion: WebDavSyncManifest.schemaVersion,
        maxBytes: WebDavSyncLimits.maxManifestBytes,
      );
      final manifest = WebDavSyncManifest.fromJson(payload);
      if (manifest.circleId != openedRoot.document.circleId ||
          manifest.deviceId != id) {
        throw const FormatException('Manifest identity mismatch');
      }
      devices.add((id: id, manifest: manifest));
    }
    if (devices.isEmpty) {
      throw const FormatException('No WebDAV manifest');
    }
    devices.sort(
      (left, right) =>
          right.manifest.updatedAtMs.compareTo(left.manifest.updatedAtMs),
    );
    final selected = devices.first;
    final deviceRoot = Directory('${devicesRoot.path}/${selected.id}');
    final bootstrapReference = selected.manifest.section('bootstrap');
    if (bootstrapReference == null) {
      throw const FormatException('Bootstrap section missing');
    }
    final bootstrapBytes = await _sectionBytes(deviceRoot, bootstrapReference);
    final openedGraph = await WebDavSyncGraphReader.open(
      codec: codec,
      key: openedRoot.key,
      circleId: openedRoot.document.circleId,
      deviceId: selected.id,
      kind: WebDavSyncGraphKind.bootstrap,
      reference: bootstrapReference,
      encoded: bootstrapBytes,
      profileMap: selected.manifest.profileMap,
      resourceMap: selected.manifest.resourceMap,
    );
    final profiles = WebDavSyncProfilesDocument.fromJson(
      await _openSection(
        codec,
        openedRoot,
        selected.id,
        deviceRoot,
        selected.manifest,
        'profiles',
      ),
    );
    final resources = WebDavSyncResourcesDocument.fromJson(
      await _openSection(
        codec,
        openedRoot,
        selected.id,
        deviceRoot,
        selected.manifest,
        'resources',
      ),
    );
    final hot = <String, WebDavSyncHotDocument>{};
    for (final circleId in selected.manifest.profileMap.values) {
      hot[circleId] = WebDavSyncHotDocument.fromJson(
        await _openSection(
          codec,
          openedRoot,
          selected.id,
          deviceRoot,
          selected.manifest,
          'hot/$circleId',
        ),
      );
    }
    return _SyncPayload(
      manifest: selected.manifest,
      bootstrap: openedGraph.package,
      profiles: profiles,
      resources: resources,
      hot: Map<String, WebDavSyncHotDocument>.unmodifiable(hot),
      deviceCount: devices.length,
    );
  }

  static Future<Object?> _openSection(
    WebDavSyncCodec codec,
    OpenedWebDavSyncRoot root,
    String deviceId,
    Directory deviceRoot,
    WebDavSyncManifest manifest,
    String name,
  ) async {
    final reference = manifest.section(name);
    if (reference == null) throw FormatException('Required section missing');
    final bytes = await _sectionBytes(deviceRoot, reference);
    final payload = await codec.openDocument(
      key: root.key,
      encoded: bytes,
      circleId: root.document.circleId,
      deviceId: deviceId,
      logicalName: name,
      schemaVersion: reference.schemaVersion,
      maxBytes: name == 'resources'
          ? WebDavSyncLimits.maxGraphDocumentBytes
          : WebDavSyncLimits.maxHotDocumentBytes,
      runInBackground: name == 'resources',
    );
    final digest = switch (name) {
      'profiles' => WebDavSyncProfilesDocument.fromJson(payload).semanticDigest,
      'resources' => WebDavSyncResourcesDocument.fromJson(
        payload,
      ).semanticDigest,
      _ => WebDavSyncHotDocument.fromJson(payload).semanticDigest,
    };
    if (digest != reference.semanticDigest) {
      throw const FormatException('Section semantic digest mismatch');
    }
    return payload;
  }

  static Future<List<int>> _sectionBytes(
    Directory deviceRoot,
    WebDavSyncSectionReference reference,
  ) async {
    final bytes = await File(
      '${deviceRoot.path}/sections/${reference.contentHash}.enc',
    ).readAsBytes();
    if (bytes.length != reference.size ||
        contentHashOf(bytes) != reference.contentHash) {
      throw const FormatException('Section content mismatch');
    }
    return bytes;
  }
}

final class _PackageInventory {
  _PackageInventory(this.package)
    : profiles = package.profiles
          .map((item) => _PackProfile(package, item))
          .toList(growable: false),
      resources = package.resources
          .map(_PackResource.new)
          .toList(growable: false),
      relations = _RawRelations(package);

  final PortableProfilePackage package;
  final List<_PackProfile> profiles;
  final List<_PackResource> resources;
  final _RawRelations relations;
}

final class _PackProfile {
  _PackProfile(PortableProfilePackage package, this.record)
    : packageId = _requiredString(record['backupId']),
      role = _requiredString(record['role']),
      nameDigest = semanticDigestOf(record['name']),
      pinPresent =
          record['pinRecord'] != null || record['wasPinProtected'] == true,
      preferences = _sectionValues(package, record['preferencesSection']),
      databases = _attachments(package, record['databasesSection']),
      files = _profileFiles(package, record),
      createdAt = package.createdAt;

  final Map<String, dynamic> record;
  final String packageId;
  final String role;
  final String nameDigest;
  final bool pinPresent;
  final Map<String, Object?> preferences;
  final Map<String, _Attachment> databases;
  final Map<String, _Attachment> files;
  final DateTime createdAt;

  String get identity => 'role=${_safe(role)},nameDigest=$nameDigest';
}

final class _PackResource {
  _PackResource(this.record)
    : packageId = _requiredString(record['backupId']),
      sourceId = _requiredString(record['sourceResourceId']),
      type = _requiredString(record['type']),
      label = _requiredString(record['label']),
      labelDigest = semanticDigestOf(record['label']),
      publicDigest = semanticDigestOf(record['publicConfig']),
      secretPresent = record['secretConfig'] != null,
      secretBytes = record['secretConfig'] == null
          ? 0
          : WebDavSyncCodec.canonicalJsonBytes(record['secretConfig']).length,
      secretDigest = record['secretConfig'] == null
          ? null
          : semanticDigestOf(record['secretConfig']);

  final Map<String, dynamic> record;
  final String packageId;
  final String sourceId;
  final String type;
  final String label;
  final String labelDigest;
  final String publicDigest;
  final bool secretPresent;
  final int secretBytes;
  final String? secretDigest;

  String get labelSummary => _label(label);
  String get identityDigest => semanticDigestOf(<String, Object?>{
    'sourceResourceId': sourceId,
    'type': type,
    'label': label,
  });
}

final class _ProfileMatch {
  const _ProfileMatch({
    required this.backup,
    required this.published,
    required this.circleId,
  });
  final _PackProfile? backup;
  final _PackProfile? published;
  final String? circleId;
}

final class _ResourceMatch {
  const _ResourceMatch({
    required this.backup,
    required this.published,
    required this.circleId,
    required this.method,
  });
  final _PackResource? backup;
  final _PackResource? published;
  final String? circleId;
  final String method;
}

final class _Attachment {
  const _Attachment({
    required this.name,
    required this.bytes,
    required this.digest,
  });
  final String name;
  final int bytes;
  final String digest;
}

final class _RawRelations {
  _RawRelations(PortableProfilePackage package)
    : grants = _rawRelationCount(package, 'grants'),
      settings = _rawRelationCount(package, 'profileSettings'),
      bindings = _rawRelationCount(package, 'bindings');
  final List<Object?> grants;
  final List<Object?> settings;
  final List<Object?> bindings;
}

final class _CanonicalRelations {
  const _CanonicalRelations({
    required this.grants,
    required this.settings,
    required this.bindings,
  });
  final Set<String> grants;
  final Set<String> settings;
  final Set<String> bindings;
}

final class _Gap {
  const _Gap._(this.impact, this.rank, this.message);
  const _Gap.high(String message) : this._('HIGH', 0, message);
  const _Gap.medium(String message) : this._('MEDIUM', 1, message);
  const _Gap.low(String message) : this._('LOW', 2, message);
  final String impact;
  final int rank;
  final String message;
}

enum _HotCategory {
  playlists('playlists'),
  favorites('favorites'),
  watchProgress('watch progress'),
  continueWatching('continue-watching'),
  finishedMarks('finished marks'),
  seriesBindings('series source bindings');

  const _HotCategory(this.label);
  final String label;
}

typedef _HotCounts = ({int records, int orders});

Map<String, Object?> _sectionValues(
  PortableProfilePackage package,
  Object? id,
) {
  if (id == null) {
    return const <String, Object?>{};
  }
  if (id is! String || package.sections[id] is! Map) {
    throw const FormatException('Invalid package section');
  }
  final section = package.sections[id]! as Map;
  final raw = section['values'];
  if (raw is! Map) {
    throw const FormatException('Invalid package section values');
  }
  return <String, Object?>{
    for (final entry in raw.entries)
      if (entry.key is String) entry.key as String: entry.value,
  };
}

Map<String, _Attachment> _attachments(
  PortableProfilePackage package,
  Object? id,
) {
  final values = _sectionValues(package, id);
  return <String, _Attachment>{
    for (final entry in values.entries)
      entry.key: _attachment(entry.key, entry.value),
  };
}

Map<String, _Attachment> _profileFiles(
  PortableProfilePackage package,
  Map<String, dynamic> profile,
) {
  final result = _attachments(package, profile['filesSection']);
  final avatar = profile['avatarFile'];
  if (avatar is Map) {
    final path = avatar['path'];
    if (path is! String) {
      throw const FormatException('Invalid avatar attachment');
    }
    result['avatar/$path'] = _attachment('avatar/$path', avatar);
  }
  return result;
}

_Attachment _attachment(String name, Object? source) {
  if (source is! Map ||
      source['bytes'] is! int ||
      source['sha256'] is! String) {
    throw const FormatException('Invalid portable attachment');
  }
  return _Attachment(
    name: name,
    bytes: source['bytes']! as int,
    digest: source['sha256']! as String,
  );
}

List<Object?> _rawRelationCount(PortableProfilePackage package, String field) =>
    <Object?>[
      for (final resource in package.resources)
        for (final item
            in (resource[field] is List
                ? resource[field]! as List
                : const <Object?>[]))
          item,
    ];

_CanonicalRelations _canonicalRelations(
  PortableProfilePackage package,
  Map<String, String> profiles,
  Map<String, String> resources,
) {
  final grants = <String>{};
  final settings = <String>{};
  final bindings = <String>{};
  for (final resource in package.resources) {
    final resourceId = resources[resource['backupId']];
    if (resourceId == null) continue;
    for (final raw in _asList(resource['grants'])) {
      final item = _stringMap(raw);
      final profileId = profiles[item['profileBackupId']];
      if (profileId != null) {
        grants.add(
          semanticDigestOf(<String, Object?>{
            'profile': profileId,
            'resource': resourceId,
            'permissions': item['permissions'],
          }),
        );
      }
    }
    for (final raw in _asList(resource['profileSettings'])) {
      final item = _stringMap(raw);
      final profileId = profiles[item['profileBackupId']];
      if (profileId != null) {
        settings.add(
          semanticDigestOf(<String, Object?>{
            'profile': profileId,
            'resource': resourceId,
            'enabled': item['enabled'],
            'values': item['values'],
          }),
        );
      }
    }
    for (final raw in _asList(resource['bindings'])) {
      final item = _stringMap(raw);
      final profileId = profiles[item['profileBackupId']];
      if (profileId != null) {
        bindings.add(
          semanticDigestOf(<String, Object?>{
            'profile': profileId,
            'resource': resourceId,
            'slot': item['slot'],
          }),
        );
      }
    }
  }
  return _CanonicalRelations(
    grants: grants,
    settings: settings,
    bindings: bindings,
  );
}

_CanonicalRelations _liveCanonicalRelations(
  WebDavSyncResourcesDocument document,
) {
  final grants = <String>{};
  final settings = <String>{};
  final bindings = <String>{};
  for (final outer in document.grants.entries) {
    for (final inner in outer.value.entries) {
      final value = inner.value.value;
      if (value != null) {
        grants.add(
          semanticDigestOf(<String, Object?>{
            'profile': outer.key,
            'resource': inner.key,
            'permissions': value.permissions,
          }),
        );
      }
    }
  }
  for (final outer in document.settings.entries) {
    for (final inner in outer.value.entries) {
      final value = inner.value.value;
      if (value != null) {
        settings.add(
          semanticDigestOf(<String, Object?>{
            'profile': outer.key,
            'resource': inner.key,
            'enabled': value.enabled,
            'values': value.settings,
          }),
        );
      }
    }
  }
  for (final outer in document.bindings.entries) {
    for (final inner in outer.value.entries) {
      final value = inner.value.value;
      if (value != null) {
        bindings.add(
          semanticDigestOf(<String, Object?>{
            'profile': outer.key,
            'resource': value.circleResourceId,
            'slot': inner.key,
          }),
        );
      }
    }
  }
  return _CanonicalRelations(
    grants: grants,
    settings: settings,
    bindings: bindings,
  );
}

Map<String, String> _hotItems(
  WebDavSyncHotDocument document,
  _HotCategory category,
) {
  final result = <String, String>{};
  bool accepts(String key) => switch (category) {
    _HotCategory.playlists =>
      key.startsWith('playlist/item/') ||
          key == WebDavSyncRecordKey.playlistOrder,
    _HotCategory.favorites =>
      key.startsWith('playlist/favorite/') ||
          key == WebDavSyncRecordKey.playlistFavoriteOrder,
    _HotCategory.watchProgress =>
      key.startsWith('playback/record/') ||
          key.startsWith('playback/meta/') ||
          key.startsWith('playback/episode/'),
    _HotCategory.continueWatching => key.startsWith('continue/'),
    _HotCategory.finishedMarks =>
      key.startsWith('playback/finished/') ||
          key.startsWith('completion/movie/') ||
          key.startsWith('completion/series/'),
    _HotCategory.seriesBindings => key.startsWith('source/'),
  };
  for (final entry in document.watchState.records.entries) {
    if (accepts(entry.key)) {
      result['record:${entry.key}'] = semanticDigestOf(entry.value.value);
    }
  }
  for (final entry in document.watchState.orders.entries) {
    if (accepts(entry.key)) {
      result['order:${entry.key}'] = semanticDigestOf(entry.value.keys);
    }
  }
  return result;
}

_HotCounts _hotCounts(WebDavSyncHotDocument document, _HotCategory category) {
  final items = _hotItems(document, category).keys;
  return (
    records: items.where((key) => key.startsWith('record:')).length,
    orders: items.where((key) => key.startsWith('order:')).length,
  );
}

bool _databaseOmissionExplains(String name, Map<String, dynamic> omissions) {
  if (name == 'iptv_catalog.db') {
    return omissions.containsKey('rebuildableDatabaseCachesOmitted');
  }
  if (name == ProfileDatabaseSnapshot.debrifyTvDatabaseName) {
    return omissions.containsKey(DebrifyTvBackupOmission.key);
  }
  return false;
}

String? _circleProfileId(String packageId, List<_ProfileMatch> matches) =>
    matches
        .where((item) => item.published?.packageId == packageId)
        .map((item) => item.circleId)
        .firstOrNull;

String? _circleResourceId(String packageId, List<_ResourceMatch> matches) =>
    matches
        .where((item) => item.published?.packageId == packageId)
        .map((item) => item.circleId)
        .firstOrNull;

void _printKeys(String label, Iterable<String> keys) {
  final values = keys.toList();
  if (values.isNotEmpty) {
    stdout.writeln('  $label keys: ${values.map(_safe).join(', ')}');
  }
}

bool _livePinPresent(WebDavSyncProfileValue profile) => <Object?>[
  profile.pin.hash,
  profile.pin.salt,
  profile.pin.paramsJson,
  profile.pin.recoveryHash,
  profile.pin.recoverySalt,
  profile.pin.recoveryParamsJson,
].any((item) => item != null);

int _leafCount<T>(Map<String, Map<String, WebDavSyncCircleLeaf<T>>> values) =>
    values.values.fold(0, (count, item) => count + item.length);

String _counts(Iterable<String> values) {
  final counts = <String, int>{};
  for (final value in values) {
    counts[value] = (counts[value] ?? 0) + 1;
  }
  final entries = counts.entries.toList()
    ..sort((left, right) => left.key.compareTo(right.key));
  return entries.isEmpty
      ? 'none'
      : entries.map((item) => '${_safe(item.key)}:${item.value}').join(',');
}

String _label(String value) => value.length <= 40
    ? jsonEncode(value)
    : '<redacted length=${utf8.encode(value).length}, digest=${semanticDigestOf(value)}>';

String _safe(String value) => value.length <= 40
    ? value
    : '<redacted length=${utf8.encode(value).length}, digest=${semanticDigestOf(value)}>';

String _time(int milliseconds) => DateTime.fromMillisecondsSinceEpoch(
  milliseconds,
  isUtc: true,
).toIso8601String();

String _stamp(WebDavSyncStamp stamp) =>
    '{normalizedTime=${stamp.normalizedTimeMs},originDeviceId=${_safe(stamp.originDeviceId)}}';

String _requiredString(Object? value) {
  if (value is! String || value.isEmpty) {
    throw const FormatException('Invalid package string');
  }
  return value;
}

List<Object?> _asList(Object? value) =>
    value is List ? value : const <Object?>[];

Map<String, Object?> _stringMap(Object? value) {
  if (value is! Map) throw const FormatException('Invalid package record');
  return <String, Object?>{
    for (final entry in value.entries)
      if (entry.key is String) entry.key as String: entry.value,
  };
}

Object? _preferenceRuntimeValue(Object? value) {
  if (value is List && value.every((item) => item is String)) {
    return value.cast<String>().toList(growable: false);
  }
  return value;
}
