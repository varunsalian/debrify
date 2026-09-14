import 'dart:convert';
import 'dart:io';

import 'src/webdav_sync_audit_root.dart';

import 'package:debrify/services/webdav_sync/webdav_sync_circle_merge.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_circle_models.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_codec.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_hot_models.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_library_models.dart';

const _passphraseEnvironmentVariable = 'WEBDAV_SYNC_AUDIT_PASSPHRASE';
const _currentGraphSchemaVersion = 1;

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln(
      'Usage: WEBDAV_SYNC_AUDIT_PASSPHRASE=<redacted> '
      'dart run tool/webdav_sync_audit.dart <sync-folder>',
    );
    exitCode = 64;
    return;
  }
  final passphrase = Platform.environment[_passphraseEnvironmentVariable];
  if (passphrase == null || passphrase.isEmpty) {
    stderr.writeln(
      'Missing $_passphraseEnvironmentVariable (its value is never printed).',
    );
    exitCode = 64;
    return;
  }

  try {
    final audit = _WebDavSyncAudit(
      root: Directory(arguments.single),
      passphrase: passphrase,
    );
    await audit.run();
  } catch (error) {
    // Do not interpolate an arbitrary exception: it could contain decrypted
    // input supplied by an untrusted sync folder.
    stderr.writeln(
      'AUDIT ABORTED (${error.runtimeType}); no secret was shown.',
    );
    exitCode = 1;
  }
}

final class _WebDavSyncAudit {
  _WebDavSyncAudit({required this.root, required this.passphrase});

  final Directory root;
  final String passphrase;
  final WebDavSyncCodec codec = WebDavSyncCodec();
  final List<_Finding> findings = <_Finding>[];
  int futureStampViolations = 0;

  Future<void> run() async {
    if (!await root.exists()) throw const FileSystemException('Missing root');
    final authority = await readAuditRoot(root, passphrase);
    final rootBytes = authority.markerBytes;
    final kdf = _readKdfHeader(rootBytes);
    final openedRoot = await codec.openRoot(
      rootBytes,
      authority.passphrase,
      runInBackground: true,
    );

    stdout.writeln('WEBDAV SYNC WIRE AUDIT');
    stdout.writeln('Mode: offline, read-only, secret-redacted');
    stdout.writeln();
    stdout.writeln('ROOT');
    stdout.writeln('circleId: ${openedRoot.document.circleId}');
    stdout.writeln(
      'createdAt: ${openedRoot.document.createdAt.toIso8601String()}',
    );
    stdout.writeln('schemaFloor: ${openedRoot.document.schemaFloor}');
    stdout.writeln(
      'KDF: algorithm=${kdf.algorithm}, memoryKiB=${kdf.memoryKiB}, '
      'iterations=${kdf.iterations}, parallelism=${kdf.parallelism}, '
      'saltBytes=${kdf.saltBytes}',
    );
    stdout.writeln('keyCheck: PASS');

    final devicesRoot = Directory('${root.path}/devices');
    final deviceIds = await _deviceIds(devicesRoot);
    if (deviceIds.isEmpty) {
      findings.add(const _Finding.critical('No device manifests found'));
    }
    for (final deviceId in deviceIds) {
      await _auditDevice(openedRoot, deviceId);
    }

    stdout.writeln();
    stdout.writeln('ANOMALIES');
    stdout.writeln(
      'future stamp violations relative to manifest: $futureStampViolations',
    );
    if (findings.isEmpty) {
      stdout.writeln('none');
    } else {
      for (final finding in findings) {
        stdout.writeln('- ${finding.severity}: ${finding.message}');
      }
    }
    final critical = findings.where((item) => item.isCritical).length;
    final warnings = findings
        .where((item) => item.severity == 'WARNING')
        .length;
    final info = findings.where((item) => item.severity == 'INFO').length;
    stdout.writeln(
      'SUMMARY: critical=$critical, warnings=$warnings, info=$info',
    );
    if (critical != 0) exitCode = 2;
  }

  Future<void> _auditDevice(
    OpenedWebDavSyncRoot openedRoot,
    String deviceId,
  ) async {
    stdout.writeln();
    stdout.writeln('DEVICE $deviceId');
    final deviceRoot = Directory('${root.path}/devices/$deviceId');
    final manifestFile = File('${deviceRoot.path}/manifest.enc');
    if (!await manifestFile.exists()) {
      findings.add(_Finding.critical('$deviceId: manifest.enc is missing'));
      return;
    }
    final manifestBytes = await manifestFile.readAsBytes();
    if (manifestBytes.length > WebDavSyncLimits.maxManifestBytes) {
      findings.add(_Finding.critical('$deviceId: manifest is oversized'));
      return;
    }
    final manifestPayload = await codec.openDocument(
      key: openedRoot.key,
      encoded: manifestBytes,
      circleId: openedRoot.document.circleId,
      deviceId: deviceId,
      logicalName: 'manifest',
      schemaVersion: WebDavSyncManifest.schemaVersion,
      maxBytes: WebDavSyncLimits.maxManifestBytes,
    );
    final manifest = WebDavSyncManifest.fromJson(manifestPayload);
    if (manifest.circleId != openedRoot.document.circleId ||
        manifest.deviceId != deviceId) {
      findings.add(
        _Finding.critical(
          '$deviceId: manifest identity does not match path/root',
        ),
      );
    }

    stdout.writeln(
      'manifest.updatedAtMs: ${manifest.updatedAtMs} '
      '(${_humanTime(manifest.updatedAtMs)})',
    );
    stdout.writeln(
      'manifest.schemaVersion: ${WebDavSyncManifest.schemaVersion}',
    );
    stdout.writeln('manifest.graphSchemaClaim: ${manifest.graphSchemaClaim}');
    if (manifest.graphSchemaClaim != _currentGraphSchemaVersion) {
      findings.add(
        _Finding.critical(
          '$deviceId: graph schema claim ${manifest.graphSchemaClaim} is not '
          'the current $_currentGraphSchemaVersion',
        ),
      );
    }
    stdout.writeln('manifest section count: ${manifest.sections.length}');
    stdout.writeln('FULL SECTION LIST');
    for (final section in manifest.sections) {
      stdout.writeln(
        '- name=${_quoted(section.name)}, '
        'schemaVersion=${section.schemaVersion}, size=${section.size}, '
        'updatedAtMs=${section.updatedAtMs} '
        '(${_humanTime(section.updatedAtMs)}), '
        'contentHash=${section.contentHash}, '
        'semanticDigest=${section.semanticDigest}',
      );
      if (section.updatedAtMs > manifest.updatedAtMs) {
        findings.add(
          _Finding.critical(
            '$deviceId/${section.name}: section timestamp is newer than manifest',
          ),
        );
      }
    }

    final duplicateNames = _duplicates(
      manifest.sections.map((section) => section.name),
    );
    final duplicateHashes = _duplicates(
      manifest.sections.map((section) => section.contentHash),
    );
    stdout.writeln(
      'duplicate section names: '
      '${duplicateNames.isEmpty ? 'none' : duplicateNames.join(', ')}',
    );
    stdout.writeln(
      'content hashes referenced by multiple sections: '
      '${duplicateHashes.isEmpty ? 'none' : duplicateHashes.join(', ')}',
    );
    final oversized = manifest.sections
        .where((section) => section.size > _maxBytesFor(section.name))
        .map((section) => section.name)
        .toList();
    stdout.writeln(
      'oversized section references: '
      '${oversized.isEmpty ? 'none' : oversized.join(', ')}',
    );
    if (duplicateNames.isNotEmpty) {
      findings.add(_Finding.critical('$deviceId: duplicate section names'));
    }
    if (duplicateHashes.isNotEmpty) {
      findings.add(
        _Finding.warning('$deviceId: multiple sections reference one blob'),
      );
    }

    _reportSectionSet(deviceId, manifest);
    final decoded = <String, _DecodedSection>{};
    stdout.writeln();
    stdout.writeln('INTEGRITY');
    for (final section in manifest.sections) {
      final result = await _auditSection(
        openedRoot: openedRoot,
        deviceId: deviceId,
        deviceRoot: deviceRoot,
        manifest: manifest,
        reference: section,
      );
      if (result != null) decoded[section.name] = result;
    }
    await _auditUnreferencedBlobs(deviceId, deviceRoot, manifest);
    _reportDecodedDocuments(deviceId, manifest, decoded);
  }

  void _reportSectionSet(String deviceId, WebDavSyncManifest manifest) {
    final names = manifest.sections.map((section) => section.name).toSet();
    stdout.writeln();
    stdout.writeln('SECTION SET CHECK');
    stdout.writeln(
      'graph: ${names.contains('graph') ? 'PRESENT (INVALID)' : 'ABSENT (correct)'}',
    );
    if (names.contains('graph')) {
      findings.add(
        _Finding.critical(
          '$deviceId: graph section is present; tier is bootstrap-only',
        ),
      );
    }
    for (final name in const <String>['bootstrap', 'resources', 'profiles']) {
      final present = names.contains(name);
      stdout.writeln('$name: ${present ? 'present' : 'MISSING'}');
      if (!present) {
        findings.add(
          _Finding.critical('$deviceId: required $name section missing'),
        );
      }
    }
    final profileIds = manifest.profileMap.values.toSet().toList()..sort();
    for (final profileId in profileIds) {
      for (final prefix in const <String>['hot', 'tombstones']) {
        final name = '$prefix/$profileId';
        final present = names.contains(name);
        stdout.writeln('$name: ${present ? 'present' : 'MISSING'}');
        if (!present) {
          findings.add(
            _Finding.critical('$deviceId: required $name section missing'),
          );
        }
      }
      final libraryName = 'library/$profileId';
      stdout.writeln(
        '$libraryName: '
        '${names.contains(libraryName) ? 'present' : 'absent (compatible legacy publisher)'}',
      );
    }
  }

  Future<_DecodedSection?> _auditSection({
    required OpenedWebDavSyncRoot openedRoot,
    required String deviceId,
    required Directory deviceRoot,
    required WebDavSyncManifest manifest,
    required WebDavSyncSectionReference reference,
  }) async {
    final path = '${deviceRoot.path}/sections/${reference.contentHash}.enc';
    final file = File(path);
    if (!await file.exists()) {
      stdout.writeln(
        '- ${reference.name}: file=MISSING, contentHash=MISMATCH, semantic=NOT CHECKED',
      );
      findings.add(
        _Finding.critical(
          '$deviceId/${reference.name}: referenced blob is missing',
        ),
      );
      return null;
    }
    final length = await file.length();
    final maxBytes = _maxBytesFor(reference.name);
    if (length > maxBytes || reference.size > maxBytes) {
      stdout.writeln(
        '- ${reference.name}: size=MISMATCH/OVERSIZED, contentHash=NOT CHECKED, '
        'semantic=NOT CHECKED',
      );
      findings.add(
        _Finding.critical(
          '$deviceId/${reference.name}: oversized '
          '(file=$length, reference=${reference.size}, max=$maxBytes)',
        ),
      );
      return null;
    }
    final bytes = await file.readAsBytes();
    final actualHash = contentHashOf(bytes);
    final hashMatches = actualHash == reference.contentHash;
    final sizeMatches = bytes.length == reference.size;
    if (!hashMatches) {
      findings.add(
        _Finding.critical('$deviceId/${reference.name}: content hash mismatch'),
      );
    }
    if (!sizeMatches) {
      findings.add(
        _Finding.critical('$deviceId/${reference.name}: byte size mismatch'),
      );
    }

    try {
      final payload = await codec.openDocument(
        key: openedRoot.key,
        encoded: bytes,
        circleId: openedRoot.document.circleId,
        deviceId: deviceId,
        logicalName: reference.name,
        schemaVersion: reference.schemaVersion,
        maxBytes: maxBytes,
        runInBackground:
            reference.name == 'bootstrap' ||
            reference.name == 'graph' ||
            reference.name == 'resources' ||
            reference.name.startsWith('library/'),
      );
      final result = await _decodeSection(reference, manifest, payload);
      final semanticMatches = result.semanticDigest == reference.semanticDigest;
      stdout.writeln(
        '- ${reference.name}: size=${sizeMatches ? 'MATCH' : 'MISMATCH'}, '
        'contentHash=${hashMatches ? 'MATCH' : 'MISMATCH'}, '
        'semanticDigest=${semanticMatches ? 'MATCH' : 'MISMATCH'}',
      );
      if (!semanticMatches) {
        findings.add(
          _Finding.critical(
            '$deviceId/${reference.name}: semantic digest mismatch '
            '(actual=${result.semanticDigest})',
          ),
        );
      }
      _checkSchema(deviceId, reference, result.payloadVersion);
      return result;
    } catch (error) {
      stdout.writeln(
        '- ${reference.name}: size=${sizeMatches ? 'MATCH' : 'MISMATCH'}, '
        'contentHash=${hashMatches ? 'MATCH' : 'MISMATCH'}, '
        'semanticDigest=ERROR(${error.runtimeType})',
      );
      findings.add(
        _Finding.critical(
          '$deviceId/${reference.name}: decrypt/decode/semantic verification failed '
          '(${error.runtimeType})',
        ),
      );
      return null;
    }
  }

  Future<_DecodedSection> _decodeSection(
    WebDavSyncSectionReference reference,
    WebDavSyncManifest manifest,
    Object? payload,
  ) async {
    final rawVersion = _payloadVersion(payload);
    if (reference.name == 'bootstrap' || reference.name == 'graph') {
      if (payload is! String) throw const FormatException('Invalid graph');
      final package = _decodeGraphPayload(payload, reference.name);
      return _DecodedSection(
        document: package,
        semanticDigest: semanticDigestOf(
          Map<String, Object?>.from(package)..remove('createdAt'),
        ),
        payloadVersion: reference.schemaVersion,
        empty: (package['profiles']! as List).isEmpty,
      );
    }
    if (reference.name == 'resources') {
      final document = WebDavSyncResourcesDocument.fromJson(payload);
      return _DecodedSection(
        document: document,
        semanticDigest: document.semanticDigest,
        payloadVersion: rawVersion,
        empty:
            document.resources.isEmpty &&
            document.grants.isEmpty &&
            document.settings.isEmpty &&
            document.bindings.isEmpty,
      );
    }
    if (reference.name == 'profiles') {
      final document = WebDavSyncProfilesDocument.fromJson(payload);
      return _DecodedSection(
        document: document,
        semanticDigest: document.semanticDigest,
        payloadVersion: rawVersion,
        empty: document.profiles.isEmpty,
      );
    }
    if (reference.name.startsWith('hot/')) {
      final document = WebDavSyncHotDocument.fromJson(payload);
      return _DecodedSection(
        document: document,
        semanticDigest: document.semanticDigest,
        payloadVersion: rawVersion,
        empty:
            document.scalars.entries.isEmpty &&
            document.watchState.records.isEmpty &&
            document.watchState.orders.isEmpty,
      );
    }
    if (reference.name.startsWith('tombstones/')) {
      final document = WebDavSyncTombstoneDocument.fromJson(payload);
      return _DecodedSection(
        document: document,
        semanticDigest: document.semanticDigest,
        payloadVersion: rawVersion,
        empty: document.items.isEmpty,
      );
    }
    if (reference.name.startsWith('library/')) {
      final document = WebDavSyncLibraryDocument.fromJson(payload);
      return _DecodedSection(
        document: document,
        semanticDigest: document.semanticDigest,
        payloadVersion: rawVersion,
        empty: document.records.isEmpty,
      );
    }
    return _DecodedSection(
      document: null,
      semanticDigest: semanticDigestOf(payload),
      payloadVersion: rawVersion,
      empty: _isEmptyJson(payload),
    );
  }

  void _checkSchema(
    String deviceId,
    WebDavSyncSectionReference reference,
    int? rawVersion,
  ) {
    final expected = _expectedSchema(reference.name);
    if (expected == null) {
      findings.add(
        _Finding.warning('$deviceId/${reference.name}: unknown section type'),
      );
      return;
    }
    if (reference.schemaVersion != expected ||
        rawVersion != null && rawVersion != expected) {
      findings.add(
        _Finding.critical(
          '$deviceId/${reference.name}: schema outside expected range '
          '(reference=${reference.schemaVersion}, payload=${rawVersion ?? 'n/a'}, '
          'expected=$expected)',
        ),
      );
    }
  }

  Future<void> _auditUnreferencedBlobs(
    String deviceId,
    Directory deviceRoot,
    WebDavSyncManifest manifest,
  ) async {
    final sectionsRoot = Directory('${deviceRoot.path}/sections');
    final referenced = manifest.sections
        .map((item) => item.contentHash)
        .toSet();
    final unreferenced = <String>[];
    if (await sectionsRoot.exists()) {
      await for (final entity in sectionsRoot.list(followLinks: false)) {
        if (entity is! File || !entity.path.endsWith('.enc')) continue;
        final name = entity.uri.pathSegments.last;
        final hash = name.substring(0, name.length - 4);
        if (!referenced.contains(hash)) unreferenced.add(hash);
      }
    }
    unreferenced.sort();
    stdout.writeln(
      'unreferenced section blobs: '
      '${unreferenced.isEmpty ? 'none' : unreferenced.join(', ')}',
    );
    if (unreferenced.isNotEmpty) {
      findings.add(
        _Finding.warning(
          '$deviceId: ${unreferenced.length} unreferenced section blob(s)',
        ),
      );
    }
  }

  void _reportDecodedDocuments(
    String deviceId,
    WebDavSyncManifest manifest,
    Map<String, _DecodedSection> decoded,
  ) {
    WebDavSyncProfilesDocument? profiles;
    WebDavSyncResourcesDocument? resources;
    for (final entry in decoded.entries) {
      if (entry.value.empty) {
        final expectedEmpty =
            entry.key.startsWith('tombstones/') ||
            entry.key.startsWith('library/');
        findings.add(
          expectedEmpty
              ? _Finding.info(
                  '$deviceId/${entry.key}: empty document (normal with no deletions)',
                )
              : _Finding.warning('$deviceId/${entry.key}: empty document'),
        );
      }
      final document = entry.value.document;
      if (document is WebDavSyncProfilesDocument) profiles = document;
      if (document is WebDavSyncResourcesDocument) resources = document;
    }

    stdout.writeln();
    stdout.writeln('HOT DOCUMENTS');
    final hotNames =
        decoded.keys.where((name) => name.startsWith('hot/')).toList()..sort();
    if (hotNames.isEmpty) stdout.writeln('none');
    for (final name in hotNames) {
      final document = decoded[name]!.document as WebDavSyncHotDocument;
      _reportHot(deviceId, manifest, name, decoded[name]!, document);
    }

    stdout.writeln();
    stdout.writeln('LIBRARY DOCUMENTS');
    final libraryNames =
        decoded.keys.where((name) => name.startsWith('library/')).toList()
          ..sort();
    if (libraryNames.isEmpty) stdout.writeln('none');
    for (final name in libraryNames) {
      final document = decoded[name]!.document as WebDavSyncLibraryDocument;
      _reportLibrary(deviceId, manifest, name, decoded[name]!, document);
    }

    stdout.writeln();
    stdout.writeln('CIRCLE SECTIONS');
    if (resources == null) {
      stdout.writeln('resources: unavailable');
    } else {
      _reportResources(deviceId, manifest, resources);
    }
    if (profiles == null) {
      stdout.writeln('profiles: unavailable');
    } else {
      _reportProfiles(deviceId, manifest, profiles);
    }
    if (profiles != null && resources != null) {
      try {
        WebDavSyncCircleMerge.validateApplicableState(
          profiles: profiles,
          resources: resources,
        );
        stdout.writeln('circle relational validation: PASS');
      } catch (error) {
        stdout.writeln(
          'circle relational validation: FAIL(${error.runtimeType})',
        );
        findings.add(
          _Finding.critical(
            '$deviceId: circle relational validation failed (${error.runtimeType})',
          ),
        );
      }
    }

    stdout.writeln();
    stdout.writeln('TOMBSTONES');
    final tombstoneNames =
        decoded.keys.where((name) => name.startsWith('tombstones/')).toList()
          ..sort();
    if (tombstoneNames.isEmpty) stdout.writeln('none');
    for (final name in tombstoneNames) {
      final document = decoded[name]!.document as WebDavSyncTombstoneDocument;
      _reportTombstones(deviceId, manifest, name, document);
    }
  }

  void _reportHot(
    String deviceId,
    WebDavSyncManifest manifest,
    String name,
    _DecodedSection decoded,
    WebDavSyncHotDocument document,
  ) {
    stdout.writeln('$name:');
    stdout.writeln(
      '  circleProfileId=${document.circleProfileId}, '
      'schemaVersion=${decoded.payloadVersion} (expected 2)',
    );
    if (name != 'hot/${document.circleProfileId}') {
      findings.add(
        _Finding.critical('$deviceId/$name: profile identity mismatch'),
      );
    }
    stdout.writeln(
      '  scalar key | value summary | normalizedTime | originDeviceId',
    );
    final entries = document.scalars.entries.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    for (final entry in entries) {
      final key = entry.key;
      final value = entry.value;
      stdout.writeln(
        '  ${_quoted(key)} | '
        '${_preferenceSummary(key, value.value, document.circleProfileId, value.stamp)} | '
        '${value.stamp.normalizedTimeMs} | ${value.stamp.originDeviceId}',
      );
      _checkStamp(
        '$deviceId/$name scalar $key',
        value.stamp,
        manifest.updatedAtMs,
      );
    }
    final distinctStamps = entries
        .map((entry) => _stampIdentity(entry.value.stamp))
        .toSet();
    final stampVerdict = entries.isEmpty
        ? 'NO SCALAR KEYS'
        : distinctStamps.length == entries.length
        ? 'all stamp coordinates are distinct'
        : 'stamp coordinates are shared '
              '(${distinctStamps.length} distinct stamps for ${entries.length} keys)';
    stdout.writeln(
      '  per-key stamp structure: YES — every scalar key carries its own '
      'stamped entry (schema v2)',
    );
    stdout.writeln('  stamp coordinate uniqueness: $stampVerdict');
    final defaultProvider =
        document.scalars.entries['default_torrent_provider_v1'];
    stdout.writeln(
      '  default_torrent_provider_v1 stamp: '
      '${defaultProvider == null ? 'ABSENT' : _stamp(defaultProvider.stamp)}',
    );

    final watch = document.watchState;
    stdout.writeln(
      '  watchState: records=${watch.records.length}, orders=${watch.orders.length}, '
      'documentStamp=${_stamp(watch.stamp)}',
    );
    stdout.writeln(
      '  watch record stamp range: ${_stampRange(watch.records.values.map((item) => item.stamp))}',
    );
    stdout.writeln(
      '  watch order stamp range: ${_stampRange(watch.orders.values.map((item) => item.stamp))}',
    );
    _checkStamp(
      '$deviceId/$name watch document',
      watch.stamp,
      manifest.updatedAtMs,
    );
    for (final entry in watch.records.entries) {
      _checkStamp(
        '$deviceId/$name watch record ${entry.key}',
        entry.value.stamp,
        manifest.updatedAtMs,
      );
    }
    for (final entry in watch.orders.entries) {
      _checkStamp(
        '$deviceId/$name watch order ${entry.key}',
        entry.value.stamp,
        manifest.updatedAtMs,
      );
    }
  }

  void _reportLibrary(
    String deviceId,
    WebDavSyncManifest manifest,
    String name,
    _DecodedSection decoded,
    WebDavSyncLibraryDocument document,
  ) {
    stdout.writeln('$name:');
    stdout.writeln(
      '  circleProfileId=${document.circleProfileId}, '
      'schemaVersion=${decoded.payloadVersion} (expected 1), '
      'records=${document.records.length}',
    );
    if (name != 'library/${document.circleProfileId}') {
      findings.add(
        _Finding.critical('$deviceId/$name: profile identity mismatch'),
      );
    }
    final byNamespace =
        <String, List<WebDavSyncCircleLeaf<Map<String, Object?>>>>{};
    final entries = document.records.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    for (final entry in entries) {
      final namespace = _libraryNamespace(entry.key);
      byNamespace
          .putIfAbsent(
            namespace,
            () => <WebDavSyncCircleLeaf<Map<String, Object?>>>[],
          )
          .add(entry.value);
      _checkStamp(
        '$deviceId/$name ${entry.key}',
        entry.value.stamp,
        manifest.updatedAtMs,
      );
      if (namespace != 'tv/pool') {
        stdout.writeln(
          '  ${_quoted(entry.key)} | stamp=${_stamp(entry.value.stamp)} | '
          '${_libraryValueSummary(entry.key, entry.value.value)}',
        );
      }
    }
    stdout.writeln('  namespace counts/stamps:');
    final namespaces = byNamespace.keys.toList()..sort();
    for (final namespace in namespaces) {
      final leaves = byNamespace[namespace]!;
      stdout.writeln(
        '  - $namespace: count=${leaves.length}, '
        'live=${leaves.where((leaf) => leaf.value != null).length}, '
        'tombstones=${leaves.where((leaf) => leaf.value == null).length}, '
        'stampRange=${_stampRange(leaves.map((leaf) => leaf.stamp))}',
      );
    }
    final generationIds =
        entries
            .where((entry) => _libraryNamespace(entry.key) == 'tv/pool-gen')
            .map((entry) => entry.value.value?['generationId'])
            .whereType<String>()
            .toList()
          ..sort();
    stdout.writeln(
      '  pool generation ids: '
      '${generationIds.isEmpty ? 'none' : generationIds.map(_quoted).join(', ')}',
    );
  }

  void _reportResources(
    String deviceId,
    WebDavSyncManifest manifest,
    WebDavSyncResourcesDocument document,
  ) {
    stdout.writeln('resources: count=${document.resources.length}');
    final entries = document.resources.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    for (final item in entries) {
      final resourceId = item.key;
      final entry = item.value;
      final metadata = entry.metadata.value;
      _checkStamp(
        '$deviceId/resources metadata $resourceId',
        entry.metadata.stamp,
        manifest.updatedAtMs,
      );
      if (metadata == null) {
        stdout.writeln(
          '- circleId=$resourceId, metadata=NULL (tombstone), '
          'stamp=${_stamp(entry.metadata.stamp)}',
        );
      } else {
        stdout.writeln(
          '- circleId=$resourceId, type=${metadata.type.name}, '
          'label=${_label(metadata.label)}, '
          'ownerCircleProfileId=${metadata.ownerCircleProfileId}, '
          'enabled=${metadata.enabled}, metadataStamp=${_stamp(entry.metadata.stamp)}',
        );
      }
      final secretLeaf = entry.secretConfig;
      if (secretLeaf == null) {
        stdout.writeln('  secretConfig: presence=false');
      } else {
        _checkStamp(
          '$deviceId/resources secret $resourceId',
          secretLeaf.stamp,
          manifest.updatedAtMs,
        );
        final secret = secretLeaf.value;
        if (secret == null) {
          stdout.writeln(
            '  secretConfig: presence=false, byteLength=0, '
            'semanticDigest=n/a, payloadVersion=n/a, ownerCircleId=n/a, '
            'stamp=${_stamp(secretLeaf.stamp)}',
          );
        } else {
          stdout.writeln(
            '  secretConfig: presence=true, '
            'byteLength=${base64Decode(secret.envelope).length}, '
            'semanticDigest=${secret.semanticDigest}, '
            'payloadVersion=${secret.payloadVersion}, '
            'ownerCircleId=${secret.ownerCircleProfileId}, '
            'stamp=${_stamp(secretLeaf.stamp)}',
          );
          if (metadata != null &&
              (secret.type != metadata.type ||
                  secret.ownerCircleProfileId !=
                      metadata.ownerCircleProfileId ||
                  secret.publicSchemaVersion != metadata.publicSchemaVersion)) {
            findings.add(
              _Finding.critical(
                '$deviceId/resources $resourceId: secret metadata binding mismatch',
              ),
            );
          }
        }
      }
    }
    final nullMetadata = entries
        .where((item) => item.value.metadata.value == null)
        .map((item) => item.key)
        .toList();
    final nullSecrets = entries
        .where(
          (item) =>
              item.value.secretConfig != null &&
              item.value.secretConfig!.value == null,
        )
        .map((item) => item.key)
        .toList();
    stdout.writeln(
      'null resource metadata leaves: '
      '${nullMetadata.isEmpty ? 'none' : nullMetadata.join(', ')}',
    );
    stdout.writeln(
      'null resource secret leaves: '
      '${nullSecrets.isEmpty ? 'none' : nullSecrets.join(', ')}',
    );
    _reportNested('grants', deviceId, manifest, document.grants);
    _reportNested('settings', deviceId, manifest, document.settings);
    _reportNested('bindings', deviceId, manifest, document.bindings);
  }

  void _reportNested<T>(
    String label,
    String deviceId,
    WebDavSyncManifest manifest,
    Map<String, Map<String, WebDavSyncCircleLeaf<T>>> values,
  ) {
    final entries =
        <({String outer, String inner, WebDavSyncCircleLeaf<T> leaf})>[];
    for (final outer in values.entries) {
      for (final inner in outer.value.entries) {
        entries.add((outer: outer.key, inner: inner.key, leaf: inner.value));
      }
    }
    entries.sort((left, right) {
      final outer = left.outer.compareTo(right.outer);
      return outer != 0 ? outer : left.inner.compareTo(right.inner);
    });
    final nullCount = entries.where((item) => item.leaf.value == null).length;
    stdout.writeln('$label: count=${entries.length}, nullLeaves=$nullCount');
    for (final entry in entries) {
      stdout.writeln(
        '- ${_quoted(entry.outer)} -> ${_quoted(entry.inner)}: '
        'stamp=${_stamp(entry.leaf.stamp)}, '
        'value=${entry.leaf.value == null ? 'NULL (tombstone)' : 'present'}',
      );
      _checkStamp(
        '$deviceId/resources $label ${entry.outer}/${entry.inner}',
        entry.leaf.stamp,
        manifest.updatedAtMs,
      );
    }
  }

  void _reportProfiles(
    String deviceId,
    WebDavSyncManifest manifest,
    WebDavSyncProfilesDocument document,
  ) {
    stdout.writeln('profiles: count=${document.profiles.length}');
    final entries = document.profiles.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    for (final item in entries) {
      final leaf = item.value;
      _checkStamp(
        '$deviceId/profiles ${item.key}',
        leaf.stamp,
        manifest.updatedAtMs,
      );
      final profile = leaf.value;
      if (profile == null) {
        stdout.writeln(
          '- circleId=${item.key}, value=NULL (tombstone), '
          'stamp=${_stamp(leaf.stamp)}, pinMaterialPresent=false',
        );
        continue;
      }
      final pin = profile.pin;
      final pinMaterialPresent = <Object?>[
        pin.hash,
        pin.salt,
        pin.paramsJson,
        pin.recoveryHash,
        pin.recoverySalt,
        pin.recoveryParamsJson,
      ].any((value) => value != null);
      stdout.writeln(
        '- circleId=${item.key}, role=${profile.role.name}, '
        'enabled=${profile.enabled}, lifecycle=${profile.lifecycle.name}, '
        'stamp=${_stamp(leaf.stamp)}, '
        'pinMaterialPresent=$pinMaterialPresent',
      );
    }
    stdout.writeln(
      'null profile leaves: '
      '${entries.where((item) => item.value.value == null).map((item) => item.key).join(', ').nullIfEmpty ?? 'none'}',
    );
  }

  void _reportTombstones(
    String deviceId,
    WebDavSyncManifest manifest,
    String name,
    WebDavSyncTombstoneDocument document,
  ) {
    stdout.writeln(
      '$name: circleProfileId=${document.circleProfileId}, count=${document.items.length}',
    );
    if (name != 'tombstones/${document.circleProfileId}') {
      findings.add(
        _Finding.critical('$deviceId/$name: profile identity mismatch'),
      );
    }
    final items = document.items.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    if (items.isEmpty) stdout.writeln('- keys: none');
    for (final item in items) {
      final tombstone = item.value;
      stdout.writeln(
        '- key=${_quoted(item.key)}, stamp=${_stamp(tombstone.stamp)}, '
        'firstPublishedAt=${tombstone.firstPublishedAtMs} '
        '(${_humanTime(tombstone.firstPublishedAtMs!)})',
      );
      _checkStamp(
        '$deviceId/$name tombstone ${item.key}',
        tombstone.stamp,
        manifest.updatedAtMs,
      );
      if (tombstone.firstPublishedAtMs! > manifest.updatedAtMs) {
        findings.add(
          _Finding.critical(
            '$deviceId/$name ${item.key}: firstPublishedAt is newer than manifest',
          ),
        );
      }
    }
  }

  void _checkStamp(String label, WebDavSyncStamp stamp, int manifestTime) {
    if (stamp.normalizedTimeMs > manifestTime) {
      futureStampViolations += 1;
      findings.add(
        _Finding.critical(
          '$label: stamp ${stamp.normalizedTimeMs} is newer than manifest $manifestTime',
        ),
      );
    }
  }

  static _KdfHeader _readKdfHeader(List<int> rootBytes) {
    final envelope = Map<String, dynamic>.from(
      jsonDecode(utf8.decode(rootBytes)) as Map,
    );
    final header = Map<String, dynamic>.from(envelope['header'] as Map);
    final kdf = Map<String, dynamic>.from(header['kdf'] as Map);
    return _KdfHeader(
      algorithm: kdf['algorithm']! as String,
      memoryKiB: kdf['memoryKiB']! as int,
      iterations: kdf['iterations']! as int,
      parallelism: kdf['parallelism']! as int,
      saltBytes: base64Decode(kdf['salt']! as String).length,
    );
  }

  static Future<List<String>> _deviceIds(Directory devicesRoot) async {
    if (!await devicesRoot.exists()) return <String>[];
    final result = <String>[];
    await for (final entity in devicesRoot.list(followLinks: false)) {
      if (entity is Directory) {
        result.add(
          entity.uri.pathSegments.where((part) => part.isNotEmpty).last,
        );
      }
    }
    return result..sort();
  }
}

final class _DecodedSection {
  const _DecodedSection({
    required this.document,
    required this.semanticDigest,
    required this.payloadVersion,
    required this.empty,
  });

  final Object? document;
  final String semanticDigest;
  final int? payloadVersion;
  final bool empty;
}

final class _KdfHeader {
  const _KdfHeader({
    required this.algorithm,
    required this.memoryKiB,
    required this.iterations,
    required this.parallelism,
    required this.saltBytes,
  });

  final String algorithm;
  final int memoryKiB;
  final int iterations;
  final int parallelism;
  final int saltBytes;
}

final class _Finding {
  const _Finding._(this.severity, this.message);

  const _Finding.critical(String message) : this._('CRITICAL', message);
  const _Finding.warning(String message) : this._('WARNING', message);
  const _Finding.info(String message) : this._('INFO', message);

  final String severity;
  final String message;

  bool get isCritical => severity == 'CRITICAL';
}

int _maxBytesFor(String name) {
  if (name == 'bootstrap' || name == 'graph' || name == 'resources') {
    return WebDavSyncLimits.maxGraphDocumentBytes;
  }
  if (name.startsWith('tombstones/')) {
    return WebDavSyncLimits.maxTombstoneDocumentBytes;
  }
  if (name.startsWith('library/')) {
    return WebDavSyncLibraryDocument.maxEncodedBytes;
  }
  return WebDavSyncLimits.maxHotDocumentBytes;
}

int? _expectedSchema(String name) {
  if (name == 'bootstrap' || name == 'graph') {
    return _currentGraphSchemaVersion;
  }
  if (name == 'resources') return WebDavSyncResourcesDocument.schemaVersion;
  if (name == 'profiles') return WebDavSyncProfilesDocument.schemaVersion;
  if (name.startsWith('hot/')) return WebDavSyncHotDocument.schemaVersion;
  if (name.startsWith('tombstones/')) {
    return WebDavSyncTombstoneDocument.schemaVersion;
  }
  if (name.startsWith('library/')) {
    return WebDavSyncLibraryDocument.schemaVersion;
  }
  return null;
}

String _libraryNamespace(String key) {
  if (key.startsWith('tv/ch/')) return 'tv/ch';
  if (key.startsWith('tv/pool-gen/')) return 'tv/pool-gen';
  if (key.startsWith('tv/pool/')) return 'tv/pool';
  if (key.startsWith('iptv/order/')) return 'iptv/order';
  if (key.startsWith('iptv/watch/')) return 'iptv/watch';
  if (key.startsWith('resume/')) return 'resume';
  if (key.startsWith('catalog/hidden/')) return 'catalog/hidden';
  if (key.startsWith('catalog/category-order/')) {
    return 'catalog/category-order';
  }
  return 'unknown';
}

String _libraryValueSummary(String key, Map<String, Object?>? value) {
  if (value == null) return 'value=NULL (tombstone)';
  final namespace = _libraryNamespace(key);
  switch (namespace) {
    case 'tv/ch':
      return 'value={nameDigest=${semanticDigestOf(value['name'])}, '
          'avoidNsfw=${value['avoidNsfw']}, '
          'channelNumber=${value['channelNumber']}, '
          'createdAt=${value['createdAt']}, '
          'keywordCount=${(value['keywords'] as List?)?.length ?? 0}, '
          'keywordsDigest=${semanticDigestOf(value['keywords'])}}';
    case 'tv/pool-gen':
      return 'value={generationId=${_quoted(_stringOrEmpty(value['generationId']))}}';
    case 'tv/pool':
      return 'value={generationId=${_quoted(_stringOrEmpty(value['generationId']))}, '
          'nameDigest=${semanticDigestOf(value['name'])}, '
          'sizeBytes=${value['sizeBytes']}, rank=${value['rank']}, '
          'keywordCount=${(value['keywords'] as List?)?.length ?? 0}, '
          'keywordsDigest=${semanticDigestOf(value['keywords'])}}';
    case 'iptv/watch':
      return 'value={url=[REDACTED digest=${semanticDigestOf(value['url'])}], '
          'headers=[REDACTED digest=${semanticDigestOf(value['headers'])}], '
          'payloadDigest=${semanticDigestOf(value)}}';
    case 'iptv/order':
      final items = value['items'] is List ? value['items']! as List : const [];
      final urlDigests = <String>[
        for (final item in items)
          if (item is Map) semanticDigestOf(item['url']),
      ];
      return 'value={groupDigest=${semanticDigestOf(value['group'])}, '
          'itemCount=${items.length}, urlDigests=[REDACTED ${urlDigests.join(',')}], '
          'payloadDigest=${semanticDigestOf(value)}}';
    case 'resume':
      return 'value={resumeKey=[REDACTED digest=${semanticDigestOf(value['resumeKey'])}], '
          'position=${value['position']}, duration=${value['duration']}, '
          'speed=${value['speed']}, aspectRatio=${value['aspectRatio']}}';
    case 'catalog/hidden':
      return 'value={groupDigest=${semanticDigestOf(value['group'])}}';
    case 'catalog/category-order':
      return 'value={groupCount=${(value['groups'] as List?)?.length ?? 0}, '
          'groupsDigest=${semanticDigestOf(value['groups'])}}';
    default:
      return 'value=[REDACTED byteLength=${_valueByteLength(value)}, '
          'digest=${semanticDigestOf(value)}]';
  }
}

String _stringOrEmpty(Object? value) => value is String ? value : '';

/// The bootstrap payload is a profile-package envelope. Importing the app's
/// full package reader pulls in `dart:ui`, so a `dart run` tool cannot load it.
/// This keeps only the authenticated wire body used by the production graph
/// semantic digest; the outer WebDAV document has already been opened by the
/// production codec.
Map<String, Object?> _decodeGraphPayload(String payload, String kind) {
  final decoded = jsonDecode(payload);
  if (decoded is! Map) throw const FormatException('Invalid graph payload');
  final envelope = Map<String, Object?>.from(decoded);
  const bodyKeys = <String>{
    'format',
    'version',
    'mode',
    'createdAt',
    'profiles',
    'resources',
    'sections',
    'omissions',
  };
  if (envelope.keys.toSet().difference(<String>{
        ...bodyKeys,
        'integrity',
      }).isNotEmpty ||
      bodyKeys.any((key) => !envelope.containsKey(key)) ||
      envelope['format'] != 'debrify-profile-package' ||
      envelope['version'] != 4 ||
      envelope['mode'] != 'deviceGraph' ||
      envelope['profiles'] is! List ||
      envelope['resources'] is! List ||
      envelope['sections'] is! Map ||
      envelope['omissions'] is! Map ||
      envelope['createdAt'] is! String ||
      envelope['integrity'] is! Map) {
    throw const FormatException('Invalid graph payload');
  }
  final profiles = envelope['profiles']! as List;
  if (profiles.isEmpty) throw const FormatException('Empty graph payload');
  for (final rawProfile in profiles) {
    if (rawProfile is! Map || rawProfile['backupId'] is! String) {
      throw const FormatException('Invalid graph profile');
    }
    if (kind == 'bootstrap') {
      final preferences = rawProfile['preferencesSection'];
      if (preferences is! String ||
          !(envelope['sections']! as Map).containsKey(preferences)) {
        throw const FormatException('Incomplete bootstrap preferences');
      }
    }
  }
  return <String, Object?>{for (final key in bodyKeys) key: envelope[key]};
}

int? _payloadVersion(Object? payload) {
  if (payload is Map && payload['version'] is int) {
    return payload['version'] as int;
  }
  return null;
}

bool _isEmptyJson(Object? value) {
  if (value == null) return true;
  if (value is String) return value.isEmpty;
  if (value is List) return value.isEmpty;
  if (value is Map) return value.isEmpty;
  return false;
}

Set<String> _duplicates(Iterable<String> values) {
  final seen = <String>{};
  final duplicates = <String>{};
  for (final value in values) {
    if (!seen.add(value)) duplicates.add(value);
  }
  return duplicates;
}

String _humanTime(int milliseconds) => DateTime.fromMillisecondsSinceEpoch(
  milliseconds,
  isUtc: true,
).toIso8601String();

String _stamp(WebDavSyncStamp stamp) =>
    '{normalizedTime=${stamp.normalizedTimeMs} '
    '(${_humanTime(stamp.normalizedTimeMs)}), '
    'originDeviceId=${stamp.originDeviceId}}';

String _stampIdentity(WebDavSyncStamp stamp) =>
    '${stamp.normalizedTimeMs}\n${stamp.originDeviceId}';

String _stampRange(Iterable<WebDavSyncStamp> stamps) {
  final values = stamps.toList();
  if (values.isEmpty) return 'none';
  values.sort(
    (left, right) => left.normalizedTimeMs.compareTo(right.normalizedTimeMs),
  );
  return '${_stamp(values.first)} .. ${_stamp(values.last)}';
}

String _preferenceSummary(
  String key,
  Object? value,
  String circleProfileId,
  WebDavSyncStamp stamp,
) {
  if (_credentialShapedKey.hasMatch(key)) {
    return 'credential/unsafe={presence=${value != null}, '
        'byteLength=${_valueByteLength(value)}, '
        'semanticDigest=${semanticDigestOf(value)}, payloadVersion=n/a, '
        'ownerCircleId=$circleProfileId, stamp=${_stamp(stamp)}}';
  }
  if (value is bool || value is int) return value.toString();
  if (value is String &&
      value.length <= 40 &&
      _obviousEnumKey.hasMatch(key) &&
      _enumValue.hasMatch(value)) {
    return _quoted(value);
  }
  return '[REDACTED type=${value.runtimeType}, byteLength=${_valueByteLength(value)}, '
      'digest=${semanticDigestOf(value)}]';
}

int _valueByteLength(Object? value) {
  if (value is String) return utf8.encode(value).length;
  return WebDavSyncCodec.canonicalJsonBytes(value).length;
}

String _label(String value) => value.length <= 40
    ? _quoted(value)
    : '[REDACTED byteLength=${utf8.encode(value).length}, '
          'digest=${semanticDigestOf(value)}]';

String _quoted(String value) => jsonEncode(value);

final RegExp _obviousEnumKey = RegExp(
  r'(mode|style|layout|sort|theme|quality|language|provider|preferred|behavior|strategy|direction|view|codec|renderer)',
  caseSensitive: false,
);
final RegExp _enumValue = RegExp(r'^[A-Za-z0-9._-]{1,40}$');
final RegExp _credentialShapedKey = RegExp(
  r'(api.?key|password|access.?token|refresh.?token|credential|secret|username|email|user.?id|device.?id|base.?url)',
  caseSensitive: false,
);

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}
