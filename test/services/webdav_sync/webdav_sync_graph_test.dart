import 'dart:typed_data';
import 'dart:convert';

import 'package:debrify/services/profiles/portable_profile_package.dart';
import 'package:debrify/services/profiles/profile_database_snapshot.dart';
import 'package:debrify/services/profiles/profile_package_service.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_codec.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_graph.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_hot_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('graph identity planning', () {
    test(
      'retains mapped identities, drops deleted ones, and mints missing',
      () {
        final minted = <String>['p-new', 'r-new'].iterator;
        final plan = WebDavSyncGraphIdentityPlanner.ensure(
          localProfileIds: const <String>['local-profile', 'new-profile'],
          localResourceIds: const <String>['local-resource'],
          currentCircleToLocalProfiles: const <String, String>{
            'p-existing': 'local-profile',
            'p-deleted': 'deleted-profile',
          },
          currentCircleToLocalResources: const <String, String>{},
          mint: (_) {
            minted.moveNext();
            return minted.current;
          },
        );

        expect(plan.maps.circleToLocalProfiles, <String, String>{
          'p-existing': 'local-profile',
          'p-new': 'new-profile',
        });
        expect(plan.maps.circleToLocalResources, <String, String>{
          'r-new': 'local-resource',
        });
      },
    );

    test('refuses inconsistent retained maps', () {
      expect(
        () => WebDavSyncGraphIdentityPlanner.ensure(
          localProfileIds: const <String>['local-profile'],
          localResourceIds: const <String>[],
          currentCircleToLocalProfiles: const <String, String>{
            'p-one': 'local-profile',
            'p-two': 'local-profile',
          },
        ),
        throwsStateError,
      );
    });

    test('mints foreign local IDs and retains deleted circle mappings', () {
      var localIndex = 0;
      final plan = WebDavSyncGraphIdentityPlanner.ensureIncludingCircleIds(
        localProfileIds: const <String>['local-profile'],
        localResourceIds: const <String>[],
        liveCircleProfileIds: const <String>['p-existing', 'p-foreign'],
        liveCircleResourceIds: const <String>['r-foreign'],
        currentCircleToLocalProfiles: const <String, String>{
          'p-existing': 'local-profile',
          'p-deleted': 'deleted-local-profile',
        },
        currentCircleToLocalResources: const <String, String>{
          'r-deleted': 'deleted-local-resource',
        },
        mintLocal: (kind) => 'minted-$kind-${localIndex++}',
      );

      expect(
        plan.maps.circleToLocalProfiles['p-deleted'],
        'deleted-local-profile',
      );
      expect(
        plan.maps.circleToLocalResources['r-deleted'],
        'deleted-local-resource',
      );
      expect(plan.maps.circleToLocalProfiles['p-foreign'], 'minted-profile-0');
      expect(
        plan.maps.circleToLocalResources['r-foreign'],
        'minted-resource-1',
      );
    });
  });

  test('graph semantic digest excludes package creation time', () async {
    final first = await _package(
      kind: WebDavSyncGraphKind.bootstrap,
      createdAt: DateTime.utc(2026, 1, 1),
    );
    final second = PortableProfilePackage(
      mode: first.mode,
      createdAt: DateTime.utc(2026, 8, 1),
      profiles: first.profiles,
      resources: first.resources,
      sections: first.sections,
      omissions: first.omissions,
    );

    expect(
      WebDavSyncGraphBuilder.semanticDigest(first),
      WebDavSyncGraphBuilder.semanticDigest(second),
    );
  });

  test(
    'structure digest ignores restored row order and engine timestamps',
    () async {
      Map<String, Object?> metadata(
        String timestamp, {
        String displayName = 'Torrentio',
      }) => <String, Object?>{
        'data': base64Encode(
          utf8.encode(
            jsonEncode(<String, Object?>{
              'version': '1.0',
              'updatedAt': timestamp,
              'engines': <String, Object?>{
                'torrentio': <String, Object?>{
                  'id': 'torrentio',
                  'fileName': 'assigned-torrentio.yaml',
                  'displayName': displayName,
                  'importedAt': timestamp,
                  'icon': null,
                },
              },
            }),
          ),
        ),
      };
      final firstFileSection = await PortableProfilePackage.buildSection(
        <String, Object?>{
          'engines/metadata.json': metadata('2026-09-01T00:00:00Z'),
        },
      );
      final secondFileSection = await PortableProfilePackage.buildSection(
        <String, Object?>{
          'engines/metadata.json': metadata('2026-09-02T00:00:00Z'),
        },
      );
      final changedFileSection =
          await PortableProfilePackage.buildSection(<String, Object?>{
            'engines/metadata.json': metadata(
              '2026-09-02T00:00:00Z',
              displayName: 'Torrentio Changed',
            ),
          });
      final first = PortableProfilePackage(
        mode: 'deviceGraph',
        createdAt: DateTime.utc(2026, 9, 1),
        profiles: const <Map<String, dynamic>>[
          <String, dynamic>{
            'backupId': 'profile-0',
            'name': 'Admin',
            'filesSection': 'profile-0-files',
          },
          <String, dynamic>{'backupId': 'profile-1', 'name': 'Kid'},
        ],
        resources: const <Map<String, dynamic>>[
          <String, dynamic>{
            'backupId': 'resource-0',
            'sourceResourceId': 'circle-resource',
            'ownerProfileBackupId': 'profile-0',
            'type': 'realDebrid',
            'grants': <Map<String, dynamic>>[
              <String, dynamic>{
                'profileBackupId': 'profile-1',
                'permissions': 1,
              },
              <String, dynamic>{
                'profileBackupId': 'profile-0',
                'permissions': 1,
              },
            ],
            'bindings': <Map<String, dynamic>>[],
            'profileSettings': <Map<String, dynamic>>[],
          },
        ],
        sections: <String, dynamic>{'profile-0-files': firstFileSection},
      );
      final second = PortableProfilePackage(
        mode: 'deviceGraph',
        createdAt: DateTime.utc(2026, 9, 2),
        profiles: const <Map<String, dynamic>>[
          <String, dynamic>{'backupId': 'local-kid', 'name': 'Kid'},
          <String, dynamic>{
            'backupId': 'local-admin',
            'name': 'Admin',
            'filesSection': 'local-admin-files',
          },
        ],
        resources: const <Map<String, dynamic>>[
          <String, dynamic>{
            'backupId': 'local-resource',
            'sourceResourceId': 'different-local-source',
            'ownerProfileBackupId': 'local-admin',
            'type': 'realDebrid',
            'grants': <Map<String, dynamic>>[
              <String, dynamic>{
                'profileBackupId': 'local-admin',
                'permissions': 1,
              },
              <String, dynamic>{
                'profileBackupId': 'local-kid',
                'permissions': 1,
              },
            ],
            'bindings': <Map<String, dynamic>>[],
            'profileSettings': <Map<String, dynamic>>[],
          },
        ],
        sections: <String, dynamic>{'local-admin-files': secondFileSection},
      );
      final changed = PortableProfilePackage(
        mode: second.mode,
        createdAt: second.createdAt,
        profiles: second.profiles,
        resources: second.resources,
        sections: <String, dynamic>{'local-admin-files': changedFileSection},
      );

      expect(
        WebDavSyncGraphBuilder.semanticDigest(first),
        isNot(WebDavSyncGraphBuilder.semanticDigest(second)),
      );
      final firstStructure = WebDavSyncGraphBuilder.structureDigest(
        first,
        profileMap: const <String, String>{
          'profile-0': 'circle-admin',
          'profile-1': 'circle-kid',
        },
        resourceMap: const <String, String>{'resource-0': 'circle-resource'},
      );
      final secondStructure = WebDavSyncGraphBuilder.structureDigest(
        second,
        profileMap: const <String, String>{
          'local-admin': 'circle-admin',
          'local-kid': 'circle-kid',
        },
        resourceMap: const <String, String>{
          'local-resource': 'circle-resource',
        },
      );
      final changedStructure = WebDavSyncGraphBuilder.structureDigest(
        changed,
        profileMap: const <String, String>{
          'local-admin': 'circle-admin',
          'local-kid': 'circle-kid',
        },
        resourceMap: const <String, String>{
          'local-resource': 'circle-resource',
        },
      );
      expect(secondStructure, firstStructure);
      expect(changedStructure, isNot(firstStructure));
    },
  );

  test('portable preference export has deterministic key order', () async {
    final scope = ProfileScope(
      profileId: 'local-profile',
      dataGeneration: 1,
      sessionEpoch: 1,
    );
    SharedPreferences.setMockInitialValues(<String, Object>{
      scope.preferenceKey('z-last'): 'z',
      scope.preferenceKey('a-first'): 'a',
      scope.preferenceKey('m-middle'): 'm',
    });

    final exported = await ProfilePackageService.exportPortablePreferences(
      scope,
    );

    expect(exported.keys, <String>['a-first', 'm-middle', 'z-last']);
  });

  test(
    'bootstrap database digest ignores preferences but detects DB bytes',
    () async {
      final preferencesA = await PortableProfilePackage.buildSection(
        const <String, Object?>{'theme_mode': 'dark'},
      );
      final preferencesB = await PortableProfilePackage.buildSection(
        const <String, Object?>{'theme_mode': 'light'},
      );
      final databaseA = await PortableProfilePackage.buildSection(
        const <String, Object?>{'debrify_tv.db': 'bytes-a'},
      );
      final databaseB = await PortableProfilePackage.buildSection(
        const <String, Object?>{'debrify_tv.db': 'bytes-b'},
      );
      PortableProfilePackage package(Object preferences, Object database) =>
          PortableProfilePackage(
            mode: 'deviceGraph',
            createdAt: DateTime.utc(2026, 9, 1),
            profiles: const <Map<String, dynamic>>[
              <String, dynamic>{
                'backupId': 'profile-0',
                'preferencesSection': 'profile-0-preferences',
                'databasesSection': 'profile-0-databases',
              },
            ],
            resources: const <Map<String, dynamic>>[],
            sections: <String, dynamic>{
              'profile-0-preferences': preferences,
              'profile-0-databases': database,
            },
          );

      final first = WebDavSyncGraphBuilder.bootstrapDatabaseDigest(
        package(preferencesA, databaseA),
      );
      final preferenceOnly = WebDavSyncGraphBuilder.bootstrapDatabaseDigest(
        package(preferencesB, databaseA),
      );
      final databaseChanged = WebDavSyncGraphBuilder.bootstrapDatabaseDigest(
        package(preferencesB, databaseB),
      );

      expect(preferenceOnly, first);
      expect(databaseChanged, isNot(first));
    },
  );

  test(
    'authenticated graph reader verifies hash, package, and semantic digest',
    () async {
      final codec = WebDavSyncCodec(
        randomBytes: (length) => Uint8List.fromList(
          List<int>.generate(length, (index) => index + 1),
        ),
      );
      final marker = await codec.sealRoot(
        passphrase: 'graph-passphrase',
        circleId: 'circle-one',
        createdAt: DateTime.utc(2026, 1, 1),
        memoryKiB: 64,
        iterations: 1,
      );
      final root = await codec.openRoot(marker, 'graph-passphrase');
      final package = await _package(
        kind: WebDavSyncGraphKind.bootstrap,
        createdAt: DateTime.utc(2026, 1, 2),
      );
      final payload = jsonEncode(
        await PortableProfilePackage.withIntegrity(package),
      );
      final encoded = await codec.sealDocument(
        key: root.key,
        circleId: 'circle-one',
        deviceId: 'device-one',
        logicalName: 'bootstrap',
        schemaVersion: 1,
        payload: payload,
        maxBytes: WebDavSyncLimits.maxGraphDocumentBytes,
      );
      final reference = WebDavSyncSectionReference(
        name: 'bootstrap',
        contentHash: contentHashOf(encoded),
        semanticDigest: WebDavSyncGraphBuilder.semanticDigest(package),
        updatedAtMs: DateTime.utc(2026, 1, 2).millisecondsSinceEpoch,
        schemaVersion: 1,
        size: encoded.length,
      );

      final opened = await WebDavSyncGraphReader.open(
        codec: codec,
        key: root.key,
        circleId: 'circle-one',
        deviceId: 'device-one',
        kind: WebDavSyncGraphKind.bootstrap,
        reference: reference,
        encoded: encoded,
        profileMap: const <String, String>{'profile-0': 'p-circle'},
        resourceMap: const <String, String>{},
      );

      expect(opened.package.profiles.single['name'], 'Admin');
      expect(opened.semanticDigest, reference.semanticDigest);
      await expectLater(
        WebDavSyncGraphReader.open(
          codec: codec,
          key: root.key,
          circleId: 'circle-one',
          deviceId: 'device-one',
          kind: WebDavSyncGraphKind.bootstrap,
          reference: WebDavSyncSectionReference(
            name: reference.name,
            contentHash: reference.contentHash,
            semanticDigest: '0' * 64,
            updatedAtMs: reference.updatedAtMs,
            schemaVersion: reference.schemaVersion,
            size: reference.size,
          ),
          encoded: encoded,
          profileMap: const <String, String>{'profile-0': 'p-circle'},
          resourceMap: const <String, String>{},
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'bootstrap discovery includes dormant manifests and uses section time',
    () {
      final now = DateTime.utc(2026, 9, 1).millisecondsSinceEpoch;
      final oldHeartbeat = now - const Duration(days: 60).inMilliseconds;
      final candidates =
          WebDavSyncGraphArbitration.bootstrapCandidates(<WebDavSyncManifest>[
            _manifest(
              deviceId: 'device-a',
              manifestTime: now,
              bootstrapTime: oldHeartbeat - 1000,
            ),
            _manifest(
              deviceId: 'device-z',
              manifestTime: oldHeartbeat,
              bootstrapTime: oldHeartbeat,
            ),
          ]);

      expect(candidates.map((value) => value.manifest.deviceId), <String>[
        'device-z',
        'device-a',
      ]);
    },
  );

  test('manifest decoding rejects sections dated after their manifest', () {
    final manifest = _manifest(
      deviceId: 'device-one',
      manifestTime: 1000,
      graphTime: 1000,
    ).toJson();
    final sections = manifest['sections']! as List<Object?>;
    final graph = Map<String, Object?>.from(sections.single! as Map);
    graph['updatedAt'] = 1001;
    manifest['sections'] = <Object?>[graph];

    expect(() => WebDavSyncManifest.fromJson(manifest), throwsFormatException);
  });

  test(
    'graph arbitration excludes stale heartbeats and honors schema ratchet',
    () {
      final now = DateTime.utc(2026, 9, 1).millisecondsSinceEpoch;
      final selected = WebDavSyncGraphArbitration.selectGraph(
        manifests: <WebDavSyncManifest>[
          _manifest(
            deviceId: 'stale-new-section',
            manifestTime: now - const Duration(days: 31).inMilliseconds,
            graphTime: now + 1000,
            graphSchema: 2,
          ),
          _manifest(
            deviceId: 'live-old-schema',
            manifestTime: now,
            graphTime: now + 2000,
            graphSchema: 1,
          ),
          _manifest(
            deviceId: 'live-ratchet',
            manifestTime: now - 5000,
            graphTime: now - 1000,
            graphSchema: 2,
          ),
        ],
        serverNowMs: now,
        persistedSchemaRatchet: 1,
      );

      expect(selected.schemaRatchet, 2);
      expect(selected.winner?.manifest.deviceId, 'live-ratchet');
    },
  );

  test(
    'refresh graph validation rejects preference or database sections',
    () async {
      final bootstrap = await _package(
        kind: WebDavSyncGraphKind.bootstrap,
        createdAt: DateTime.utc(2026, 1, 1),
      );
      expect(
        () => WebDavSyncGraphValidation.requireComplete(
          kind: WebDavSyncGraphKind.graph,
          package: bootstrap,
          profileMap: const <String, String>{'profile-0': 'p-circle'},
          resourceMap: const <String, String>{},
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'bootstrap accepts only the bounded database fallback and keeps IPTV credentials',
    () async {
      final preferences = await PortableProfilePackage.buildSection(
        const <String, Object?>{'theme_mode': 'dark'},
      );
      final databases = await PortableProfilePackage.buildSection(
        const <String, Object?>{'iptv_catalog.db': 'compacted-snapshot'},
      );
      final package = PortableProfilePackage(
        mode: 'deviceGraph',
        createdAt: DateTime.utc(2026, 9, 2),
        profiles: const <Map<String, dynamic>>[
          <String, dynamic>{
            'backupId': 'profile-0',
            'preferencesSection': 'profile-0-preferences',
            'databasesSection': 'profile-0-databases',
          },
        ],
        resources: const <Map<String, dynamic>>[
          <String, dynamic>{
            'backupId': 'resource-0',
            'sourceResourceId': 'r-circle',
            'type': 'iptvXtream',
            'secretConfig': <String, dynamic>{
              'serverUrl': 'https://iptv.invalid',
              'username': 'alice',
              'password': 'secret',
            },
          },
        ],
        sections: <String, dynamic>{
          'profile-0-preferences': preferences,
          'profile-0-databases': databases,
        },
        omissions: <String, dynamic>{
          'rebuildableDatabaseCachesOmitted': 'Admin: iptv_catalog.db',
          DebrifyTvBackupOmission.key: const DebrifyTvBackupOmission(
            channels: 37,
            savedHashes: 0,
            profilesAffected: 1,
          ).toJson(),
        },
      );

      expect(
        () => WebDavSyncGraphValidation.requireComplete(
          kind: WebDavSyncGraphKind.bootstrap,
          package: package,
          profileMap: const <String, String>{'profile-0': 'p-circle'},
          resourceMap: const <String, String>{'resource-0': 'r-circle'},
        ),
        returnsNormally,
      );
      expect(
        (package.resources.single['secretConfig'] as Map)['password'],
        'secret',
      );
    },
  );

  test(
    'graph omission policy remains fail-closed for future categories',
    () async {
      final base = await _package(
        kind: WebDavSyncGraphKind.bootstrap,
        createdAt: DateTime.utc(2026, 9, 2),
      );
      final package = PortableProfilePackage(
        mode: base.mode,
        createdAt: base.createdAt,
        profiles: base.profiles,
        resources: base.resources,
        sections: base.sections,
        omissions: const <String, dynamic>{
          'futureDurableDatabaseRowsOmitted': true,
        },
      );

      expect(
        () => WebDavSyncGraphValidation.requireComplete(
          kind: WebDavSyncGraphKind.bootstrap,
          package: package,
          profileMap: const <String, String>{'profile-0': 'p-circle'},
          resourceMap: const <String, String>{},
        ),
        throwsFormatException,
      );
    },
  );

  test('graph omission policy rejects malformed known categories', () async {
    final base = await _package(
      kind: WebDavSyncGraphKind.bootstrap,
      createdAt: DateTime.utc(2026, 9, 2),
    );
    for (final omissions in <Map<String, dynamic>>[
      <String, dynamic>{'rebuildableDatabaseCachesOmitted': true},
      <String, dynamic>{
        DebrifyTvBackupOmission.key: <String, Object?>{
          'channels': 'thirty-seven',
          'savedHashes': 0,
          'profilesAffected': 1,
        },
      },
    ]) {
      final package = PortableProfilePackage(
        mode: base.mode,
        createdAt: base.createdAt,
        profiles: base.profiles,
        resources: base.resources,
        sections: base.sections,
        omissions: omissions,
      );

      expect(
        () => WebDavSyncGraphValidation.requireComplete(
          kind: WebDavSyncGraphKind.bootstrap,
          package: package,
          profileMap: const <String, String>{'profile-0': 'p-circle'},
          resourceMap: const <String, String>{},
        ),
        throwsFormatException,
      );
    }
  });
}

Future<PortableProfilePackage> _package({
  required WebDavSyncGraphKind kind,
  required DateTime createdAt,
}) async {
  final includePreferences = kind == WebDavSyncGraphKind.bootstrap;
  final section = await PortableProfilePackage.buildSection(
    const <String, Object?>{'theme_mode': 'dark'},
  );
  return PortableProfilePackage(
    mode: 'deviceGraph',
    createdAt: createdAt,
    profiles: <Map<String, dynamic>>[
      <String, dynamic>{
        'backupId': 'profile-0',
        'name': 'Admin',
        'role': 'admin',
        'policy': 'manageProfiles,backupRestore',
        if (includePreferences) 'preferencesSection': 'profile-0-preferences',
      },
    ],
    resources: const <Map<String, dynamic>>[],
    sections: <String, dynamic>{
      if (includePreferences) 'profile-0-preferences': section,
    },
  );
}

WebDavSyncManifest _manifest({
  required String deviceId,
  required int manifestTime,
  int? bootstrapTime,
  int? graphTime,
  int graphSchema = 1,
}) => WebDavSyncManifest(
  circleId: 'circle-one',
  deviceId: deviceId,
  updatedAtMs: manifestTime,
  clockOffsetMs: 0,
  graphSchemaClaim: graphSchema,
  profileMap: const <String, String>{'profile-0': 'p-circle'},
  resourceMap: const <String, String>{},
  sections: <WebDavSyncSectionReference>[
    if (bootstrapTime != null)
      _reference('bootstrap', bootstrapTime, schema: 1),
    if (graphTime != null) _reference('graph', graphTime, schema: graphSchema),
  ],
);

WebDavSyncSectionReference _reference(
  String name,
  int updatedAt, {
  required int schema,
}) => WebDavSyncSectionReference(
  name: name,
  contentHash: '1' * 64,
  semanticDigest: '2' * 64,
  updatedAtMs: updatedAt,
  schemaVersion: schema,
  size: 100,
);
