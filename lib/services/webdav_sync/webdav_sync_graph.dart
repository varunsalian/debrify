import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import '../profiles/portable_profile_package.dart';
import '../profiles/profile_authorization.dart';
import '../profiles/profile_package_service.dart';
import 'webdav_sync_codec.dart';
import 'webdav_sync_graph_omissions.dart';
import 'webdav_sync_hot_merge.dart';
import 'webdav_sync_hot_models.dart';

enum WebDavSyncGraphKind {
  bootstrap('bootstrap'),
  graph('graph');

  const WebDavSyncGraphKind(this.logicalName);

  final String logicalName;
}

final class WebDavSyncGraphIdentityPlan {
  const WebDavSyncGraphIdentityPlan({required this.maps});

  final WebDavSyncIdentityMaps maps;
}

/// Reconciles durable circle identities with the local registry without ever
/// deriving identity from a display name or list position.
abstract final class WebDavSyncGraphIdentityPlanner {
  static WebDavSyncGraphIdentityPlan ensure({
    required Iterable<String> localProfileIds,
    required Iterable<String> localResourceIds,
    Map<String, String>? currentCircleToLocalProfiles,
    Map<String, String>? currentCircleToLocalResources,
    String Function(String kind)? mint,
  }) {
    final profiles = localProfileIds.toSet();
    final resources = localResourceIds.toSet();
    if (profiles.isEmpty || profiles.length != localProfileIds.length) {
      throw StateError('WebDAV sync requires a unique local profile set');
    }
    if (resources.length != localResourceIds.length) {
      throw StateError('WebDAV sync requires a unique local resource set');
    }
    final idFactory = mint ?? _mintCircleId;
    final profileMap = _retainAndMint(
      kind: 'profile',
      localIds: profiles,
      current: currentCircleToLocalProfiles,
      mint: idFactory,
    );
    final resourceMap = _retainAndMint(
      kind: 'resource',
      localIds: resources,
      current: currentCircleToLocalResources,
      mint: idFactory,
      forbiddenCircleIds: profileMap.keys.toSet(),
    );
    return WebDavSyncGraphIdentityPlan(
      maps: WebDavSyncIdentityMaps(
        circleToLocalProfiles: profileMap,
        circleToLocalResources: resourceMap,
      ),
    );
  }

  /// Extends an authenticated maps for live circle records first observed
  /// from another device. Existing mappings never move; local IDs are minted
  /// only for foreign circle IDs that need a registry row.
  static WebDavSyncGraphIdentityPlan ensureIncludingCircleIds({
    required Iterable<String> localProfileIds,
    required Iterable<String> localResourceIds,
    required Iterable<String> liveCircleProfileIds,
    required Iterable<String> liveCircleResourceIds,
    Map<String, String>? currentCircleToLocalProfiles,
    Map<String, String>? currentCircleToLocalResources,
    String Function(String kind)? mintCircle,
    String Function(String kind)? mintLocal,
  }) {
    final retainedLocalProfiles = <String>{
      ...localProfileIds,
      ...?currentCircleToLocalProfiles?.values,
    };
    final retainedLocalResources = <String>{
      ...localResourceIds,
      ...?currentCircleToLocalResources?.values,
    };
    final base = ensure(
      // Circle-record tombstones need their old local-to-circle identity even
      // after the SQL parent disappeared. Routine graph planning may drop a
      // deleted local row; circle sync retains that mapping indefinitely.
      localProfileIds: retainedLocalProfiles,
      localResourceIds: retainedLocalResources,
      currentCircleToLocalProfiles: currentCircleToLocalProfiles,
      currentCircleToLocalResources: currentCircleToLocalResources,
      mint: mintCircle,
    ).maps;
    final profiles = Map<String, String>.from(base.circleToLocalProfiles);
    final resources = Map<String, String>.from(base.circleToLocalResources);
    final localFactory = mintLocal ?? _mintLocalId;
    final claimedLocalIds = <String>{...profiles.values, ...resources.values};

    for (final circleId in liveCircleProfileIds.toSet()) {
      if (resources.containsKey(circleId)) {
        throw StateError('WebDAV sync circle identity kinds conflict');
      }
      if (profiles.containsKey(circleId)) continue;
      String localId;
      do {
        localId = localFactory('profile');
      } while (!claimedLocalIds.add(localId) ||
          profiles.containsKey(localId) ||
          resources.containsKey(localId));
      profiles[circleId] = localId;
    }
    for (final circleId in liveCircleResourceIds.toSet()) {
      if (profiles.containsKey(circleId)) {
        throw StateError('WebDAV sync circle identity kinds conflict');
      }
      if (resources.containsKey(circleId)) continue;
      String localId;
      do {
        localId = localFactory('resource');
      } while (!claimedLocalIds.add(localId) ||
          profiles.containsKey(localId) ||
          resources.containsKey(localId));
      resources[circleId] = localId;
    }
    return WebDavSyncGraphIdentityPlan(
      maps: WebDavSyncIdentityMaps(
        circleToLocalProfiles: profiles,
        circleToLocalResources: resources,
      ),
    );
  }

  static Map<String, String> _retainAndMint({
    required String kind,
    required Set<String> localIds,
    required Map<String, String>? current,
    required String Function(String kind) mint,
    Set<String> forbiddenCircleIds = const <String>{},
  }) {
    final result = <String, String>{};
    final claimedLocalIds = <String>{};
    for (final entry in (current ?? const <String, String>{}).entries) {
      if (!localIds.contains(entry.value)) continue;
      if (!claimedLocalIds.add(entry.value) ||
          forbiddenCircleIds.contains(entry.key) ||
          result.containsKey(entry.key)) {
        throw StateError('WebDAV sync $kind identity map is inconsistent');
      }
      result[entry.key] = entry.value;
    }
    for (final localId in localIds.where(
      (value) => !claimedLocalIds.contains(value),
    )) {
      String circleId;
      do {
        circleId = mint(kind);
      } while (result.containsKey(circleId) ||
          forbiddenCircleIds.contains(circleId));
      result[circleId] = localId;
    }
    return Map<String, String>.unmodifiable(result);
  }

  static String _mintCircleId(String kind) {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${kind == 'profile' ? 'p' : 'r'}-${hex.substring(0, 8)}-'
        '${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  static String _mintLocalId(String kind) {
    final random = Random.secure();
    final bytes = List<int>.generate(12, (_) => random.nextInt(256));
    return '${kind == 'profile' ? 'profile' : 'resource'}-'
        '${base64UrlEncode(bytes).replaceAll('=', '')}';
  }
}

final class WebDavSyncPreparedGraph {
  const WebDavSyncPreparedGraph({
    required this.kind,
    required this.package,
    required this.payload,
    required this.semanticDigest,
    required this.bootstrapDatabaseDigest,
    required this.profileMap,
    required this.resourceMap,
  });

  final WebDavSyncGraphKind kind;
  final PortableProfilePackage package;
  final String payload;
  final String semanticDigest;
  final String? bootstrapDatabaseDigest;
  final Map<String, String> profileMap;
  final Map<String, String> resourceMap;
}

/// Produces graph packages whose identities and semantic digest are stable
/// across devices even though every restore allocates new local IDs.
final class WebDavSyncGraphBuilder {
  const WebDavSyncGraphBuilder(this.packageService);

  static const int schemaVersion = 1;

  final ProfilePackageService packageService;

  Future<WebDavSyncPreparedGraph> build({
    required WebDavSyncGraphKind kind,
    required ProfileAuthorizationContext authorization,
    required WebDavSyncIdentityMaps identityMaps,
  }) async {
    final exported = await packageService.exportAllProfilesForSync(
      context: authorization,
      profileIdProjection: identityMaps.localToCircleProfiles,
      resourceIdProjection: identityMaps.localToCircleResources,
      includeDatabases: kind == WebDavSyncGraphKind.bootstrap,
      includePreferences: kind == WebDavSyncGraphKind.bootstrap,
    );
    _requireExactLocalSet(
      exported.profileBackupIdsByLocalId.keys,
      identityMaps.localToCircleProfiles.keys,
      'profile',
    );
    _requireExactLocalSet(
      exported.resourceBackupIdsByLocalId.keys,
      identityMaps.localToCircleResources.keys,
      'resource',
    );
    final profileMap = <String, String>{
      for (final entry in exported.profileBackupIdsByLocalId.entries)
        entry.value: identityMaps.localToCircleProfiles[entry.key]!,
    };
    final resourceMap = <String, String>{
      for (final entry in exported.resourceBackupIdsByLocalId.entries)
        entry.value: identityMaps.localToCircleResources[entry.key]!,
    };
    // Bootstrap packages can contain tens of megabytes of database state.
    // Keep projection, validation, canonical hashing, and JSON encoding
    // together on a worker so none of those CPU-heavy passes can starve
    // Flutter input.
    final processed = await Isolate.run(() async {
      final projected = await _projectPackage(exported.package, identityMaps);
      WebDavSyncGraphValidation.requireComplete(
        kind: kind,
        package: projected,
        profileMap: profileMap,
        resourceMap: resourceMap,
      );
      identityMaps.assertContainsNoLocalIds(projected.toJson());
      final projectedSemanticDigest = semanticDigest(projected);
      final projectedBootstrapDatabaseDigest =
          kind == WebDavSyncGraphKind.bootstrap
          ? bootstrapDatabaseDigest(projected)
          : null;
      // Encode last so the large returned String is not retained alongside
      // the temporary canonical byte buffers used by both digests.
      final payload = jsonEncode(
        await PortableProfilePackage.withIntegrity(projected),
      );
      return (
        package: projected,
        payload: payload,
        semanticDigest: projectedSemanticDigest,
        bootstrapDatabaseDigest: projectedBootstrapDatabaseDigest,
      );
    });
    return WebDavSyncPreparedGraph(
      kind: kind,
      package: processed.package,
      payload: processed.payload,
      semanticDigest: processed.semanticDigest,
      bootstrapDatabaseDigest: processed.bootstrapDatabaseDigest,
      profileMap: Map<String, String>.unmodifiable(profileMap),
      resourceMap: Map<String, String>.unmodifiable(resourceMap),
    );
  }

  static String semanticDigest(PortableProfilePackage package) {
    final semantic = Map<String, dynamic>.from(package.toJson())
      ..remove('createdAt');
    return semanticDigestOf(semantic);
  }

  /// Device-independent identity for a structure-only refresh graph.
  ///
  /// The encrypted document's [semanticDigest] remains a strict digest of its
  /// exact authenticated payload. This second digest is used only to decide
  /// whether two valid graph documents describe the same registry structure.
  /// Legacy v1 writers assigned `profile-0` / `resource-0` by local row order
  /// and engine metadata carries non-semantic timestamps, so bytewise
  /// semantic digests can differ after a restore even when the circle graph
  /// is equal.
  static String structureDigest(
    PortableProfilePackage package, {
    required Map<String, String> profileMap,
    required Map<String, String> resourceMap,
  }) {
    if (package.mode != 'deviceGraph') {
      throw const FormatException('Invalid WebDAV sync graph package');
    }
    final profiles = <Map<String, dynamic>>[];
    final sections = <String, dynamic>{};
    for (final source in package.profiles) {
      if (source['preferencesSection'] != null ||
          source['databasesSection'] != null) {
        throw const FormatException(
          'WebDAV sync refresh graph must be structure-only',
        );
      }
      final backupId = source['backupId'];
      final circleId = backupId is String ? profileMap[backupId] : null;
      if (circleId == null || circleId.isEmpty) {
        throw const FormatException('WebDAV sync profile map is incomplete');
      }
      final profile = Map<String, dynamic>.from(source)
        ..['backupId'] = circleId;
      final filesSectionId = source['filesSection'];
      if (filesSectionId != null) {
        if (filesSectionId is! String ||
            !package.sections.containsKey(filesSectionId)) {
          throw const FormatException(
            'WebDAV sync portable files are incomplete',
          );
        }
        final canonicalSectionId = '$circleId-files';
        profile['filesSection'] = canonicalSectionId;
        sections[canonicalSectionId] = _canonicalPortableFilesSection(
          package.sections[filesSectionId],
        );
      }
      profiles.add(profile);
    }
    profiles.sort(
      (left, right) =>
          (left['backupId'] as String).compareTo(right['backupId'] as String),
    );

    final resources = <Map<String, dynamic>>[];
    for (final source in package.resources) {
      final backupId = source['backupId'];
      final ownerBackupId = source['ownerProfileBackupId'];
      final circleId = backupId is String ? resourceMap[backupId] : null;
      final ownerCircleId = ownerBackupId is String
          ? profileMap[ownerBackupId]
          : null;
      if (circleId == null ||
          circleId.isEmpty ||
          ownerCircleId == null ||
          ownerCircleId.isEmpty) {
        throw const FormatException('WebDAV sync resource map is incomplete');
      }
      final resource = Map<String, dynamic>.from(source)
        ..['backupId'] = circleId
        ..['sourceResourceId'] = circleId
        ..['ownerProfileBackupId'] = ownerCircleId;
      for (final field in const <String>[
        'grants',
        'bindings',
        'profileSettings',
      ]) {
        resource[field] = _canonicalProfileReferences(
          resource[field],
          profileMap,
        );
      }
      resources.add(resource);
    }
    resources.sort(
      (left, right) =>
          (left['backupId'] as String).compareTo(right['backupId'] as String),
    );

    final semantic = Map<String, dynamic>.from(package.toJson())
      ..remove('createdAt')
      ..['profiles'] = profiles
      ..['resources'] = resources
      ..['sections'] = sections;
    return semanticDigestOf(semantic);
  }

  static Map<String, dynamic> _canonicalPortableFilesSection(Object? source) {
    if (source is! Map ||
        source['schemaVersion'] is! int ||
        source['values'] is! Map) {
      throw const FormatException('Invalid WebDAV sync portable files');
    }
    final values = <String, Object?>{};
    for (final entry in (source['values'] as Map).entries) {
      if (entry.key is! String || entry.value is! Map) {
        throw const FormatException('Invalid WebDAV sync portable file');
      }
      final fileName = entry.key as String;
      final record = entry.value as Map;
      final data = record['data'];
      if (data is! String) {
        throw const FormatException('Invalid WebDAV sync portable file');
      }
      if (fileName == 'engines/metadata.json') {
        try {
          final decoded = jsonDecode(utf8.decode(base64Decode(data)));
          if (decoded is! Map) {
            throw const FormatException('Invalid engine metadata');
          }
          final metadata = Map<String, dynamic>.from(decoded)
            ..remove('updatedAt');
          final rawEngines = metadata['engines'];
          if (rawEngines is! Map) {
            throw const FormatException('Invalid engine metadata');
          }
          final engines = <String, Object?>{};
          for (final engine in rawEngines.entries) {
            if (engine.key is! String || engine.value is! Map) {
              throw const FormatException('Invalid engine metadata');
            }
            engines[engine.key as String] = Map<String, dynamic>.from(
              engine.value as Map,
            )..remove('importedAt');
          }
          metadata['engines'] = engines;
          values[fileName] = metadata;
        } on FormatException {
          throw const FormatException('Invalid WebDAV sync engine metadata');
        }
      } else {
        // Attachment lengths and hashes are derived and were already checked
        // by package decoding. The bytes themselves are the file semantics.
        values[fileName] = data;
      }
    }
    return <String, dynamic>{
      'schemaVersion': source['schemaVersion'],
      'values': values,
    };
  }

  static List<Map<String, dynamic>> _canonicalProfileReferences(
    Object? source,
    Map<String, String> profileMap,
  ) {
    if (source is! List) {
      throw const FormatException('Invalid WebDAV sync profile references');
    }
    final result = <Map<String, dynamic>>[];
    for (final value in source) {
      if (value is! Map) {
        throw const FormatException('Invalid WebDAV sync profile reference');
      }
      final reference = Map<String, dynamic>.from(value);
      final backupId = reference['profileBackupId'];
      final circleId = backupId is String ? profileMap[backupId] : null;
      if (circleId == null || circleId.isEmpty) {
        throw const FormatException('WebDAV sync profile map is incomplete');
      }
      reference['profileBackupId'] = circleId;
      result.add(reference);
    }
    result.sort(
      (left, right) => WebDavSyncCodec.canonicalJson(
        left,
      ).compareTo(WebDavSyncCodec.canonicalJson(right)),
    );
    return result;
  }

  /// Stable fingerprint for the bootstrap-only database payload. Hot
  /// preferences intentionally do not participate: their ordinary changes
  /// must not cause a daily full-seed upload.
  static String bootstrapDatabaseDigest(PortableProfilePackage package) {
    if (package.mode != 'deviceGraph') {
      throw const FormatException('Invalid WebDAV sync bootstrap package');
    }
    final databases = <Map<String, Object?>>[];
    final profiles = package.profiles.toList(growable: false);
    for (final profile in profiles) {
      final backupId = profile['backupId'];
      if (backupId is! String || backupId.isEmpty) {
        throw const FormatException('Invalid WebDAV sync bootstrap profile');
      }
    }
    profiles.sort(
      (left, right) =>
          (left['backupId'] as String).compareTo(right['backupId'] as String),
    );
    for (final profile in profiles) {
      final backupId = profile['backupId'];
      final sectionId = profile['databasesSection'];
      if (sectionId != null &&
          (sectionId is! String || !package.sections.containsKey(sectionId))) {
        throw const FormatException('Invalid WebDAV sync database section');
      }
      databases.add(<String, Object?>{
        'profile': backupId,
        'databases': sectionId == null ? null : package.sections[sectionId],
      });
    }
    return semanticDigestOf(databases);
  }

  static Future<PortableProfilePackage> _projectPackage(
    PortableProfilePackage source,
    WebDavSyncIdentityMaps maps,
  ) async {
    final projected = Map<String, dynamic>.from(
      maps.toWire(source.toJson())! as Map,
    );
    final rawSections = Map<String, dynamic>.from(
      projected['sections']! as Map,
    );
    final sections = <String, dynamic>{};
    for (final entry in rawSections.entries) {
      final section = Map<String, dynamic>.from(entry.value! as Map);
      final values = Map<String, Object?>.from(section['values']! as Map);
      final schema = section['schemaVersion'];
      if (schema is! int || schema < 1) {
        throw const FormatException('Invalid projected graph section');
      }
      sections[entry.key] = await PortableProfilePackage.buildSection(
        values,
        schemaVersion: schema,
      );
    }
    return PortableProfilePackage(
      mode: projected['mode']! as String,
      createdAt: DateTime.parse(projected['createdAt']! as String).toUtc(),
      profiles: (projected['profiles']! as List)
          .map((value) => Map<String, dynamic>.from(value as Map))
          .toList(growable: false),
      resources: (projected['resources']! as List)
          .map((value) => Map<String, dynamic>.from(value as Map))
          .toList(growable: false),
      sections: sections,
      omissions: Map<String, dynamic>.from(projected['omissions']! as Map),
    );
  }

  static void _requireExactLocalSet(
    Iterable<String> exported,
    Iterable<String> mapped,
    String label,
  ) {
    final left = exported.toSet();
    final right = mapped.toSet();
    if (left.length != exported.length ||
        right.length != mapped.length ||
        left.length != right.length ||
        !left.containsAll(right)) {
      throw StateError('WebDAV sync $label export omitted an identity');
    }
  }
}

abstract final class WebDavSyncGraphValidation {
  static void requireComplete({
    required WebDavSyncGraphKind kind,
    required PortableProfilePackage package,
    required Map<String, String> profileMap,
    required Map<String, String> resourceMap,
  }) {
    if (package.mode != 'deviceGraph' || package.profiles.isEmpty) {
      throw const FormatException('WebDAV sync graph package is incomplete');
    }
    final profileIds = _backupIds(package.profiles, 'profile');
    final resourceIds = _backupIds(package.resources, 'resource');
    _requireExactMap(profileIds, profileMap, 'profile');
    _requireExactMap(resourceIds, resourceMap, 'resource');
    final circleIds = <String>{};
    if (!circleIds.addAllUnique(profileMap.values) ||
        !circleIds.addAllUnique(resourceMap.values)) {
      throw const FormatException('WebDAV sync graph identity map overlaps');
    }
    for (final profile in package.profiles) {
      final preferences = profile['preferencesSection'];
      final databases = profile['databasesSection'];
      if (kind == WebDavSyncGraphKind.bootstrap) {
        if (preferences is! String ||
            !package.sections.containsKey(preferences)) {
          throw const FormatException(
            'WebDAV sync bootstrap is missing profile preferences',
          );
        }
      } else if (preferences != null || databases != null) {
        throw const FormatException(
          'WebDAV sync refresh graph must be structure-only',
        );
      }
    }
    WebDavSyncGraphOmissionPolicy.requireSupported(package);
    for (final resource in package.resources) {
      final backupId = resource['backupId'];
      if (backupId is! String ||
          resource['sourceResourceId'] != resourceMap[backupId]) {
        throw const FormatException('WebDAV sync resource map is incomplete');
      }
    }
  }

  static Set<String> _backupIds(
    List<Map<String, dynamic>> records,
    String label,
  ) {
    final result = <String>{};
    for (final record in records) {
      final id = record['backupId'];
      if (id is! String || id.isEmpty || !result.add(id)) {
        throw FormatException('Invalid WebDAV sync $label backup ID');
      }
    }
    return result;
  }

  static void _requireExactMap(
    Set<String> expected,
    Map<String, String> actual,
    String label,
  ) {
    if (expected.length != actual.length ||
        !expected.containsAll(actual.keys) ||
        actual.values.any((value) => value.isEmpty)) {
      throw FormatException('WebDAV sync $label map is incomplete');
    }
  }
}

extension on Set<String> {
  bool addAllUnique(Iterable<String> values) {
    for (final value in values) {
      if (!add(value)) return false;
    }
    return true;
  }
}

final class OpenedWebDavSyncGraph {
  const OpenedWebDavSyncGraph({
    required this.kind,
    required this.package,
    required this.semanticDigest,
  });

  final WebDavSyncGraphKind kind;
  final PortableProfilePackage package;
  final String semanticDigest;
}

abstract final class WebDavSyncGraphReader {
  static Future<OpenedWebDavSyncGraph> open({
    required WebDavSyncCodec codec,
    required WebDavSyncCircleKey key,
    required String circleId,
    required String deviceId,
    required WebDavSyncGraphKind kind,
    required WebDavSyncSectionReference reference,
    required List<int> encoded,
    required Map<String, String> profileMap,
    required Map<String, String> resourceMap,
  }) async {
    if (reference.name != kind.logicalName ||
        reference.schemaVersion != WebDavSyncGraphBuilder.schemaVersion ||
        contentHashOf(encoded) != reference.contentHash) {
      throw const FormatException('WebDAV sync graph reference is invalid');
    }
    final clear = await codec.openDocument(
      key: key,
      encoded: encoded,
      circleId: circleId,
      deviceId: deviceId,
      logicalName: kind.logicalName,
      schemaVersion: reference.schemaVersion,
      maxBytes: WebDavSyncLimits.maxGraphDocumentBytes,
      runInBackground: true,
    );
    if (clear is! String) {
      throw const FormatException('WebDAV sync graph payload is invalid');
    }
    final package = await PortableProfilePackage.decodeAuthenticatedJson(
      clear,
      allowMissingPreferences: kind == WebDavSyncGraphKind.graph,
    );
    WebDavSyncGraphValidation.requireComplete(
      kind: kind,
      package: package,
      profileMap: profileMap,
      resourceMap: resourceMap,
    );
    final digest = WebDavSyncGraphBuilder.semanticDigest(package);
    if (digest != reference.semanticDigest) {
      throw const FormatException('WebDAV sync graph semantic digest mismatch');
    }
    return OpenedWebDavSyncGraph(
      kind: kind,
      package: package,
      semanticDigest: digest,
    );
  }
}

final class WebDavSyncGraphCandidate {
  const WebDavSyncGraphCandidate({
    required this.manifest,
    required this.reference,
  });

  final WebDavSyncManifest manifest;
  final WebDavSyncSectionReference reference;
}

final class WebDavSyncGraphSelection {
  const WebDavSyncGraphSelection({
    required this.schemaRatchet,
    required this.candidates,
  });

  final int schemaRatchet;
  final List<WebDavSyncGraphCandidate> candidates;

  WebDavSyncGraphCandidate? get winner => candidates.firstOrNull;
}

abstract final class WebDavSyncGraphArbitration {
  static const Duration staleManifestCutoff = Duration(days: 30);

  /// Bootstrap recovery intentionally considers authentic dormant manifests.
  static List<WebDavSyncGraphCandidate> bootstrapCandidates(
    Iterable<WebDavSyncManifest> manifests,
  ) {
    final result = <WebDavSyncGraphCandidate>[];
    for (final manifest in manifests) {
      final reference = manifest.section(
        WebDavSyncGraphKind.bootstrap.logicalName,
      );
      if (reference == null || manifest.profileMap.isEmpty) continue;
      result.add(
        WebDavSyncGraphCandidate(manifest: manifest, reference: reference),
      );
    }
    result.sort(_newestFirst);
    return List<WebDavSyncGraphCandidate>.unmodifiable(result);
  }

  static WebDavSyncGraphSelection selectGraph({
    required Iterable<WebDavSyncManifest> manifests,
    required int serverNowMs,
    required int persistedSchemaRatchet,
  }) {
    final live = manifests
        .where(
          (manifest) =>
              serverNowMs - manifest.updatedAtMs <=
              staleManifestCutoff.inMilliseconds,
        )
        .toList(growable: false);
    var ratchet = persistedSchemaRatchet;
    for (final manifest in live) {
      ratchet = max(ratchet, manifest.graphSchemaClaim);
    }
    final candidates = <WebDavSyncGraphCandidate>[];
    for (final manifest in live) {
      final reference = manifest.section(WebDavSyncGraphKind.graph.logicalName);
      if (reference == null ||
          manifest.graphSchemaClaim != ratchet ||
          reference.schemaVersion != ratchet) {
        continue;
      }
      candidates.add(
        WebDavSyncGraphCandidate(manifest: manifest, reference: reference),
      );
    }
    candidates.sort(_newestFirst);
    return WebDavSyncGraphSelection(
      schemaRatchet: ratchet,
      candidates: List<WebDavSyncGraphCandidate>.unmodifiable(candidates),
    );
  }

  static int _newestFirst(
    WebDavSyncGraphCandidate left,
    WebDavSyncGraphCandidate right,
  ) {
    final byTime = right.reference.updatedAtMs.compareTo(
      left.reference.updatedAtMs,
    );
    if (byTime != 0) return byTime;
    return right.manifest.deviceId.compareTo(left.manifest.deviceId);
  }
}
