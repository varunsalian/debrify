import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:debrify/services/playlist_dedupe_key.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_codec.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_engine_state.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_hot_merge.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_hot_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('profile and resource identity spaces may never overlap', () {
    expect(
      () => WebDavSyncIdentityMaps(
        circleToLocalProfiles: const <String, String>{
          'shared-circle': 'profile-local',
        },
        circleToLocalResources: const <String, String>{
          'shared-circle': 'resource-local',
        },
      ),
      throwsArgumentError,
    );
    expect(
      () => WebDavSyncIdentityMaps(
        circleToLocalProfiles: const <String, String>{
          'profile-circle': 'shared-local',
        },
        circleToLocalResources: const <String, String>{
          'resource-circle': 'shared-local',
        },
      ),
      throwsArgumentError,
    );
  });

  test('wire identities may never alias a local identity', () {
    expect(
      () => WebDavSyncIdentityMaps(
        circleToLocalProfiles: const <String, String>{
          'local-resource': 'local-profile',
        },
        circleToLocalResources: const <String, String>{
          'resource-circle': 'local-resource',
        },
      ),
      throwsArgumentError,
    );
  });

  final maps = WebDavSyncIdentityMaps(
    circleToLocalProfiles: const <String, String>{
      'profile-circle': 'local-profile',
    },
    circleToLocalResources: const <String, String>{
      'resource-circle': 'local-resource',
    },
  );

  test('identity leak guard checks nested values and composite map keys', () {
    expect(
      () => maps.assertContainsNoLocalIds(<String, Object?>{
        'nested': <Object?>['local-profile'],
      }),
      throwsStateError,
    );
    expect(
      () => maps.assertContainsNoLocalIds(<String, Object?>{
        'server:local-resource|path:%2Fshows': 'grid',
      }),
      throwsStateError,
    );
    expect(
      () => maps.assertContainsNoLocalIds(<String, Object?>{
        'binding': sha256.convert(utf8.encode('local-resource')).toString(),
      }),
      throwsStateError,
    );
    expect(
      () => maps.assertContainsNoLocalIds(<Object?, Object?>{1: 'safe'}),
      throwsFormatException,
    );
  });

  test(
    'identity leak guard does not rescan a large section for every ID',
    () {
      final manyMaps = WebDavSyncIdentityMaps(
        circleToLocalProfiles: const <String, String>{
          'profile-circle': 'local-profile',
        },
        circleToLocalResources: <String, String>{
          for (var index = 0; index < 256; index++)
            'resource-circle-$index': 'local-resource-$index',
        },
      );

      final attachment = 'A' * (8 * 1024 * 1024);
      final wire =
          manyMaps.toWire(<String, Object?>{'databaseAttachment': attachment})!
              as Map;
      expect(identical(wire['databaseAttachment'], attachment), isTrue);
      manyMaps.assertContainsNoLocalIds(wire);
    },
    timeout: const Timeout(Duration(seconds: 5)),
  );

  test('local-file source tombstones are never projected to the wire', () {
    const localPath = '/private/device/Movies/Secret.mkv';
    final key = WebDavSyncRecordKey.source('tt1', 'local:$localPath');

    expect(WebDavSyncRecordKey.projectLocalTombstoneKey(key, maps), isNull);
    expect(
      WebDavSyncRecordKey.projectLocalTombstoneKey(
        WebDavSyncRecordKey.source('tt1', 'hash:abc'),
        maps,
      ),
      WebDavSyncRecordKey.source('tt1', 'hash:abc'),
    );
  });

  test('scalar LWW retains keys missing from the newest document', () {
    final older = _document(
      device: 'device-a',
      scalarTime: 100,
      scalars: const <String, Object>{'theme': 'old', 'newSchemaKey': true},
    );
    final newer = _document(
      device: 'device-b',
      scalarTime: 200,
      scalars: const <String, Object>{'theme': 'new'},
    );

    final merged = WebDavSyncHotMerge.merge(
      local: older,
      peers: <WebDavSyncHotDocument>[newer],
      tombstoneDocuments: const <WebDavSyncTombstoneDocument>[],
      nowMs: 300,
    ).document;

    expect(merged.scalars.values, <String, Object>{
      'theme': 'new',
      'newSchemaKey': true,
    });
    expect(merged.scalars.entries['theme']!.stamp.originDeviceId, 'device-b');
  });

  test('different-key scalar edits survive every merge order and converge', () {
    final baseline = _buildWithPreferences(
      maps,
      'device-seed',
      const <String, Object?>{
        'default_torrent_provider_v1': 'none',
        'theme': 'dark',
      },
      now: 100,
    ).document;
    final deviceA = _buildWithPreferences(
      maps,
      'device-a',
      const <String, Object?>{
        'default_torrent_provider_v1': 'torbox',
        'theme': 'dark',
      },
      now: 200,
      previous: baseline,
    ).document;
    final deviceB = _buildWithPreferences(
      maps,
      'device-b',
      const <String, Object?>{
        'default_torrent_provider_v1': 'none',
        'theme': 'light',
      },
      now: 215,
      previous: baseline,
    ).document;

    final results = <WebDavSyncHotDocument>[
      WebDavSyncHotMerge.merge(
        local: baseline,
        peers: <WebDavSyncHotDocument>[deviceA, deviceB],
        tombstoneDocuments: const <WebDavSyncTombstoneDocument>[],
        nowMs: 300,
      ).document,
      WebDavSyncHotMerge.merge(
        local: baseline,
        peers: <WebDavSyncHotDocument>[deviceB, deviceA],
        tombstoneDocuments: const <WebDavSyncTombstoneDocument>[],
        nowMs: 300,
      ).document,
      WebDavSyncHotMerge.merge(
        local: deviceA,
        peers: <WebDavSyncHotDocument>[deviceB],
        tombstoneDocuments: const <WebDavSyncTombstoneDocument>[],
        nowMs: 300,
      ).document,
      WebDavSyncHotMerge.merge(
        local: deviceB,
        peers: <WebDavSyncHotDocument>[deviceA],
        tombstoneDocuments: const <WebDavSyncTombstoneDocument>[],
        nowMs: 300,
      ).document,
    ];

    for (final result in results) {
      expect(result.scalars.values, <String, Object>{
        'default_torrent_provider_v1': 'torbox',
        'theme': 'light',
      });
      expect(
        result
            .scalars
            .entries['default_torrent_provider_v1']!
            .stamp
            .originDeviceId,
        'device-a',
      );
      expect(result.scalars.entries['theme']!.stamp.originDeviceId, 'device-b');
    }
    expect(
      results.map((result) => result.semanticDigest).toSet(),
      hasLength(1),
    );
  });

  test('same-key scalar edits choose one winner under every merge order', () {
    final deviceA = _document(
      device: 'device-a',
      scalarTime: 200,
      scalars: const <String, Object>{'default_torrent_provider_v1': 'torbox'},
    );
    final deviceB = _document(
      device: 'device-b',
      scalarTime: 200,
      scalars: const <String, Object>{
        'default_torrent_provider_v1': 'premiumize',
      },
    );

    final results = <WebDavSyncHotDocument>[
      WebDavSyncHotMerge.merge(
        local: deviceA,
        peers: <WebDavSyncHotDocument>[deviceB],
        tombstoneDocuments: const <WebDavSyncTombstoneDocument>[],
        nowMs: 300,
      ).document,
      WebDavSyncHotMerge.merge(
        local: deviceB,
        peers: <WebDavSyncHotDocument>[deviceA],
        tombstoneDocuments: const <WebDavSyncTombstoneDocument>[],
        nowMs: 300,
      ).document,
    ];

    for (final result in results) {
      expect(
        result.scalars.values['default_torrent_provider_v1'],
        'premiumize',
      );
      expect(
        result
            .scalars
            .entries['default_torrent_provider_v1']!
            .stamp
            .originDeviceId,
        'device-b',
      );
    }
    expect(
      results.first.scalars.semanticDigest,
      results.last.scalars.semanticDigest,
    );

    final equalStampA = _document(
      device: 'same-origin',
      scalarTime: 200,
      scalars: const <String, Object>{'theme': 'dark'},
    );
    final equalStampB = _document(
      device: 'same-origin',
      scalarTime: 200,
      scalars: const <String, Object>{'theme': 'light'},
    );
    final expectedHashWinner =
        semanticDigestOf('dark').compareTo(semanticDigestOf('light')) > 0
        ? 'dark'
        : 'light';
    for (final pair in <List<WebDavSyncHotDocument>>[
      <WebDavSyncHotDocument>[equalStampA, equalStampB],
      <WebDavSyncHotDocument>[equalStampB, equalStampA],
    ]) {
      final result = WebDavSyncHotMerge.merge(
        local: pair.first,
        peers: <WebDavSyncHotDocument>[pair.last],
        tombstoneDocuments: const <WebDavSyncTombstoneDocument>[],
        nowMs: 300,
      ).document;
      expect(result.scalars.values['theme'], expectedHashWinner);
    }
  });

  test(
    'unchanged scalar stamps survive rebuild restart and peer rebroadcast',
    () {
      const initial = <String, Object?>{
        'default_torrent_provider_v1': 'none',
        'theme': 'dark',
        'favorite_genres': <String>['crime'],
      };
      const providerChanged = <String, Object?>{
        'default_torrent_provider_v1': 'torbox',
        'theme': 'dark',
        'favorite_genres': <String>['crime'],
      };
      final baseline = _buildWithPreferences(
        maps,
        'device-a',
        initial,
        now: 100,
      ).document;
      final changed = _buildWithPreferences(
        maps,
        'device-a',
        providerChanged,
        now: 200,
        previous: baseline,
      ).document;

      expect(
        changed.scalars.semanticDigest,
        isNot(baseline.scalars.semanticDigest),
      );
      expect(_stampBytes(changed, 'theme'), _stampBytes(baseline, 'theme'));
      expect(
        _stampBytes(changed, 'favorite_genres'),
        _stampBytes(baseline, 'favorite_genres'),
      );
      expect(
        changed
            .scalars
            .entries['default_torrent_provider_v1']!
            .stamp
            .normalizedTimeMs,
        200,
      );

      final restored = WebDavSyncProfileEngineState.fromJson(
        WebDavSyncProfileEngineState(baseline: changed).toJson(),
      ).baseline!;
      final rebuilt = _buildWithPreferences(
        maps,
        'device-a',
        providerChanged,
        now: 300,
        previous: restored,
      ).document;
      expect(
        WebDavSyncCodec.canonicalJson(rebuilt.toJson()),
        WebDavSyncCodec.canonicalJson(changed.toJson()),
      );

      final merged = WebDavSyncHotMerge.merge(
        local: rebuilt,
        peers: <WebDavSyncHotDocument>[changed],
        tombstoneDocuments: const <WebDavSyncTombstoneDocument>[],
        nowMs: 400,
      ).document;
      final rebroadcast = _buildWithPreferences(
        maps,
        'device-b',
        providerChanged,
        now: 400,
        previous: merged,
      ).document;
      for (final key in providerChanged.keys) {
        expect(_stampBytes(rebroadcast, key), _stampBytes(changed, key));
      }

      final listChanged = _buildWithPreferences(
        maps,
        'device-b',
        const <String, Object?>{
          'default_torrent_provider_v1': 'torbox',
          'theme': 'dark',
          'favorite_genres': <String>['crime', 'drama'],
        },
        now: 500,
        previous: rebroadcast,
      ).document;
      expect(
        _stampBytes(listChanged, 'default_torrent_provider_v1'),
        _stampBytes(changed, 'default_torrent_provider_v1'),
      );
      expect(_stampBytes(listChanged, 'theme'), _stampBytes(changed, 'theme'));
      expect(
        listChanged.scalars.entries['favorite_genres']!.stamp.toJson(),
        <String, Object?>{'time': 500, 'origin': 'device-b'},
      );
    },
  );

  test('v1 scalar fixture translates per key and converges with v2', () {
    final legacyJson = _legacyHotJson(
      device: 'legacy-device',
      scalarTime: 100,
      scalars: const <String, Object>{
        'default_torrent_provider_v1': 'none',
        'theme': 'dark',
      },
    );
    final legacyBytes = WebDavSyncCodec.canonicalJson(legacyJson);
    final migrated = WebDavSyncHotDocument.fromJson(jsonDecode(legacyBytes));

    expect(legacyJson['version'], 1);
    expect(WebDavSyncCodec.canonicalJson(legacyJson), legacyBytes);
    expect(migrated.toJson()['version'], WebDavSyncHotDocument.schemaVersion);
    for (final value in migrated.scalars.entries.values) {
      expect(value.stamp.toJson(), <String, Object?>{
        'time': 100,
        'origin': 'legacy-device',
      });
    }
    final scalarJson = migrated.toJson()['scalars']! as Map;
    expect(scalarJson, isNot(contains('stamp')));
    expect((scalarJson['values'] as Map)['theme'], contains('stamp'));

    final v2 = _buildWithPreferences(
      maps,
      'device-b',
      const <String, Object?>{
        'default_torrent_provider_v1': 'torbox',
        'theme': 'dark',
      },
      now: 200,
      previous: migrated,
    ).document;
    final forward = WebDavSyncHotMerge.merge(
      local: migrated,
      peers: <WebDavSyncHotDocument>[v2],
      tombstoneDocuments: const <WebDavSyncTombstoneDocument>[],
      nowMs: 300,
    ).document;
    final reverse = WebDavSyncHotMerge.merge(
      local: v2,
      peers: <WebDavSyncHotDocument>[migrated],
      tombstoneDocuments: const <WebDavSyncTombstoneDocument>[],
      nowMs: 300,
    ).document;

    expect(forward.scalars.values, <String, Object>{
      'default_torrent_provider_v1': 'torbox',
      'theme': 'dark',
    });
    expect(forward.semanticDigest, reverse.semanticDigest);
  });

  test('v3 and malformed stamped scalar documents fail closed', () {
    final valid = _document(
      device: 'device-a',
      scalarTime: 100,
      scalars: const <String, Object>{'theme': 'dark'},
    ).toJson();
    final v3 = Map<String, Object?>.from(valid)..['version'] = 3;
    final malformedScalars = Map<String, Object?>.from(valid);
    malformedScalars['scalars'] = <String, Object?>{
      'semanticDigest': semanticDigestOf(const <String, Object>{
        'theme': 'dark',
      }),
      'values': const <String, Object>{'theme': 'dark'},
    };
    final invalidType = Map<String, Object?>.from(valid);
    invalidType['scalars'] = <String, Object?>{
      'semanticDigest': semanticDigestOf(const <String, Object>{
        'favorite_genres': <Object>[1],
      }),
      'values': <String, Object?>{
        'favorite_genres': <String, Object?>{
          'stamp': _stamp(100, 'device-a').toJson(),
          'value': <Object>[1],
        },
      },
    };
    final oversizedV1 = _legacyHotJson(
      device: 'legacy-device',
      scalarTime: 100,
      scalars: <String, Object>{
        for (
          var index = 0;
          index <= WebDavSyncLimits.maxRecordsPerHotDocument;
          index++
        )
          'setting_$index': true,
      },
    );

    expect(() => WebDavSyncHotDocument.fromJson(v3), throwsFormatException);
    expect(
      () => WebDavSyncHotDocument.fromJson(malformedScalars),
      throwsFormatException,
    );
    expect(
      () => WebDavSyncHotDocument.fromJson(invalidType),
      throwsFormatException,
    );
    expect(
      () => WebDavSyncHotDocument.fromJson(oversizedV1),
      throwsFormatException,
    );
  });

  test('watch records union deeply and ties resolve deterministically', () {
    final firstKey = WebDavSyncRecordKey.playbackEpisode('alias', 1, 1);
    final secondKey = WebDavSyncRecordKey.playbackEpisode('alias', 1, 2);
    final local = _document(
      device: 'device-a',
      records: <String, WebDavSyncStampedValue>{
        firstKey: _value(100, 'device-a', <String, Object>{'positionMs': 10}),
        secondKey: _value(200, 'device-a', <String, Object>{'positionMs': 20}),
      },
    );
    final peer = _document(
      device: 'device-b',
      records: <String, WebDavSyncStampedValue>{
        firstKey: _value(300, 'device-b', <String, Object>{'positionMs': 30}),
        secondKey: _value(200, 'device-b', <String, Object>{'positionMs': 25}),
      },
    );

    final merged = WebDavSyncHotMerge.merge(
      local: local,
      peers: <WebDavSyncHotDocument>[peer],
      tombstoneDocuments: const <WebDavSyncTombstoneDocument>[],
      nowMs: 400,
    ).document;

    expect(
      (merged.watchState.records[firstKey]!.value as Map)['positionMs'],
      30,
    );
    expect(
      (merged.watchState.records[secondKey]!.value as Map)['positionMs'],
      25,
    );
  });

  test('newer tombstone removes a record and a later rewatch revives it', () {
    final key = WebDavSyncRecordKey.finishedMovie('tt1');
    final original = _document(
      device: 'device-a',
      records: <String, WebDavSyncStampedValue>{
        key: _value(100, 'device-a', true),
      },
    );
    final tombstones = WebDavSyncTombstoneDocument(
      circleProfileId: 'profile-circle',
      items: <String, WebDavSyncTombstone>{
        key: WebDavSyncTombstone(
          key: key,
          stamp: _stamp(200, 'device-b'),
          firstPublishedAtMs: 200,
        ),
      },
    );
    var merged = WebDavSyncHotMerge.merge(
      local: original,
      peers: const <WebDavSyncHotDocument>[],
      tombstoneDocuments: <WebDavSyncTombstoneDocument>[tombstones],
      nowMs: 300,
    );
    expect(merged.document.watchState.records, isNot(contains(key)));

    final rewatch = _document(
      device: 'device-a',
      records: <String, WebDavSyncStampedValue>{
        key: _value(400, 'device-a', true),
      },
    );
    merged = WebDavSyncHotMerge.merge(
      local: rewatch,
      peers: const <WebDavSyncHotDocument>[],
      tombstoneDocuments: <WebDavSyncTombstoneDocument>[tombstones],
      nowMs: 500,
    );
    expect(merged.document.watchState.records, contains(key));
  });

  test('tombstoning the final series source materializes an empty list', () {
    const preferenceKey = '${WebDavSyncHotMerge.seriesSourcePrefix}tt1';
    final built = _buildWithPreferences(maps, 'device-a', <String, Object?>{
      preferenceKey: jsonEncode(<Object>[
        <String, Object>{'torrentHash': 'hash-one', 'boundAt': 100},
      ]),
    }, now: 100);
    final recordKey = built.document.watchState.records.keys.single;
    final tombstones = WebDavSyncTombstoneDocument(
      circleProfileId: 'profile-circle',
      items: <String, WebDavSyncTombstone>{
        recordKey: WebDavSyncTombstone(
          key: recordKey,
          stamp: _stamp(200, 'device-b'),
          firstPublishedAtMs: 200,
        ),
      },
    );

    final merged = WebDavSyncHotMerge.merge(
      local: built.document,
      peers: const <WebDavSyncHotDocument>[],
      tombstoneDocuments: <WebDavSyncTombstoneDocument>[tombstones],
      nowMs: 300,
    ).document;
    final output = WebDavSyncHotMerge.materializePreferences(
      document: merged,
      identityMaps: maps,
    );

    expect(jsonDecode(output[preferenceKey]! as String), isEmpty);
  });

  test('an empty remote source list does not erase protected local data', () {
    const preferenceKey = '${WebDavSyncHotMerge.seriesSourcePrefix}tt1';
    final document = _document(
      device: 'device-a',
      orders: <String, WebDavSyncOrderValue>{
        WebDavSyncRecordKey.sourceOrder('tt1'): WebDavSyncOrderValue(
          stamp: _stamp(100, 'device-a'),
          keys: const <String>[],
        ),
      },
    );

    final output = WebDavSyncHotMerge.materializePreferences(
      document: document,
      identityMaps: maps,
      protectedPreferenceKeys: const <String>{preferenceKey},
    );

    expect(output, isNot(contains(preferenceKey)));
  });

  test('pending tombstones do not expire before first publication', () {
    final key = WebDavSyncRecordKey.finishedMovie('tt1');
    final document = WebDavSyncTombstoneDocument(
      circleProfileId: 'profile-circle',
      items: <String, WebDavSyncTombstone>{
        key: WebDavSyncTombstone(key: key, stamp: _stamp(1, 'device-a')),
      },
    );
    final merged = WebDavSyncHotMerge.merge(
      local: _document(device: 'device-a'),
      peers: const <WebDavSyncHotDocument>[],
      tombstoneDocuments: <WebDavSyncTombstoneDocument>[document],
      nowMs: const Duration(days: 365).inMilliseconds,
    );
    expect(merged.tombstones, contains(key));
  });

  test('continue watching is re-capped by recency without tombstones', () {
    final records = <String, WebDavSyncStampedValue>{
      for (var index = 0; index < 55; index++)
        WebDavSyncRecordKey.continueWatching('tt$index'): _value(
          index,
          'device-a',
          <String, Object>{'imdbId': 'tt$index'},
        ),
    };
    final merged = WebDavSyncHotMerge.merge(
      local: _document(device: 'device-a', records: records),
      peers: const <WebDavSyncHotDocument>[],
      tombstoneDocuments: const <WebDavSyncTombstoneDocument>[],
      nowMs: 100,
    );
    final remaining = merged.document.watchState.records.keys.where(
      (key) => key.startsWith('continue/'),
    );
    expect(remaining, hasLength(50));
    expect(
      remaining,
      isNot(contains(WebDavSyncRecordKey.continueWatching('tt0'))),
    );
    expect(merged.tombstones, isEmpty);
  });

  test('peer unions cannot exceed the bounded hot-document record count', () {
    final split = WebDavSyncLimits.maxRecordsPerHotDocument ~/ 2;
    Map<String, WebDavSyncStampedValue> records(int start, int count) =>
        <String, WebDavSyncStampedValue>{
          for (var index = start; index < start + count; index++)
            WebDavSyncRecordKey.finishedMovie('tt$index'): _value(
              index,
              'device-a',
              true,
            ),
        };

    expect(
      () => WebDavSyncHotMerge.merge(
        local: _document(device: 'device-a', records: records(0, split + 1)),
        peers: <WebDavSyncHotDocument>[
          _document(device: 'device-b', records: records(split + 1, split)),
        ],
        tombstoneDocuments: const <WebDavSyncTombstoneDocument>[],
        nowMs: WebDavSyncLimits.maxTimestampMs,
      ),
      throwsFormatException,
    );
  });

  test('builder drops nulls and never leaks local IDs', () {
    final built = WebDavSyncHotMerge.build(
      WebDavSyncBuildInput(
        circleProfileId: 'profile-circle',
        deviceId: 'device-a',
        rawPreferences: const <String, Object?>{
          'nullable': 'keep-locally',
          'resource_json': '{"id":"local-resource"}',
        },
        portablePreferences: const <String, Object?>{
          'nullable': null,
          'resource_json': '{"id":"local-resource"}',
        },
        identityMaps: maps,
        localNowMs: 100,
        clockOffsetMs: 10,
        serverNowMs: 105,
      ),
    );
    final encoded = jsonEncode(built.document.toJson());
    expect(built.document.scalars.values, isNot(contains('nullable')));
    expect(encoded, isNot(contains('local-resource')));
    expect(encoded, contains('resource-circle'));
    expect(built.protectedPreferenceKeys, contains('nullable'));

    final materialized = WebDavSyncHotMerge.materializePreferences(
      document: built.document,
      identityMaps: maps,
      protectedPreferenceKeys: built.protectedPreferenceKeys,
    );
    expect(materialized, isNot(contains('nullable')));
    expect(materialized['resource_json'], contains('local-resource'));
  });

  test('MDBList checkpoint stays local without restamping scalar settings', () {
    const checkpoint = WebDavSyncHotMerge.mdblistSyncCheckpointPreference;
    final previous = _document(
      device: 'device-a',
      scalarTime: 100,
      scalars: const <String, Object>{
        'default_torrent_provider_v1': 'torbox',
        checkpoint: '{"server_time":10}',
      },
    );
    final built = WebDavSyncHotMerge.build(
      WebDavSyncBuildInput(
        circleProfileId: 'profile-circle',
        deviceId: 'device-a',
        rawPreferences: const <String, Object?>{
          'default_torrent_provider_v1': 'torbox',
          checkpoint: '{"server_time":20}',
        },
        portablePreferences: const <String, Object?>{
          'default_torrent_provider_v1': 'torbox',
          checkpoint: '{"server_time":20}',
        },
        identityMaps: maps,
        localNowMs: 200,
        clockOffsetMs: 0,
        serverNowMs: 200,
        previous: previous,
      ),
    );

    expect(built.document.scalars.values, <String, Object>{
      'default_torrent_provider_v1': 'torbox',
    });
    expect(
      built.document.scalars.entries['default_torrent_provider_v1']!.stamp,
      previous.scalars.entries['default_torrent_provider_v1']!.stamp,
    );
    expect(built.protectedPreferenceKeys, contains(checkpoint));
    expect(jsonEncode(built.document.toJson()), isNot(contains(checkpoint)));
  });

  test('legacy hot documents cannot apply an MDBList checkpoint', () {
    const checkpoint = WebDavSyncHotMerge.mdblistSyncCheckpointPreference;
    final merged = WebDavSyncHotMerge.merge(
      local: _document(
        device: 'device-a',
        scalarTime: 100,
        scalars: const <String, Object>{'theme': 'dark'},
      ),
      peers: <WebDavSyncHotDocument>[
        _document(
          device: 'legacy-device',
          scalarTime: 200,
          scalars: const <String, Object>{checkpoint: '{"server_time":20}'},
        ),
      ],
      tombstoneDocuments: const <WebDavSyncTombstoneDocument>[],
      nowMs: 300,
    ).document;

    expect(merged.scalars.values, isNot(contains(checkpoint)));
    final materialized = WebDavSyncHotMerge.materializePreferences(
      document: _document(
        device: 'legacy-device',
        scalarTime: 200,
        scalars: const <String, Object>{checkpoint: '{"server_time":20}'},
      ),
      identityMaps: maps,
    );
    expect(materialized, isNot(contains(checkpoint)));
  });

  test('typed string-list preferences survive identity rewriting', () {
    final built = _buildWithPreferences(maps, 'device-a', <String, Object?>{
      'favorite_resources': <String>['local-resource', 'plain-value'],
    }, now: 100);

    final wire = built.document.scalars.values['favorite_resources'];
    expect(wire, isA<List<String>>());
    expect(wire, <String>['resource-circle', 'plain-value']);

    final materialized = WebDavSyncHotMerge.materializePreferences(
      document: built.document,
      identityMaps: maps,
    );
    expect(materialized['favorite_resources'], isA<List<String>>());
    expect(materialized['favorite_resources'], <String>[
      'local-resource',
      'plain-value',
    ]);
  });

  test('composite resource IDs in JSON keys round-trip without leaking', () {
    const preferenceKey = 'playlist_view_modes_v1';
    const localComposite = 'server:local-resource|path:%2Fshows';
    const circleComposite = 'server:resource-circle|path:%2Fshows';
    final built = _buildWithPreferences(maps, 'device-a', <String, Object?>{
      preferenceKey: jsonEncode(<String, String>{localComposite: 'grid'}),
    }, now: 100);

    final wire = built.document.scalars.values[preferenceKey]! as String;
    expect(wire, contains(circleComposite));
    expect(wire, isNot(contains('local-resource')));

    final materialized = WebDavSyncHotMerge.materializePreferences(
      document: built.document,
      identityMaps: maps,
    );
    final local = jsonDecode(materialized[preferenceKey]! as String) as Map;
    expect(local, <String, Object?>{localComposite: 'grid'});
  });

  test('null-protected completion lists are not cleared by an empty doc', () {
    final materialized = WebDavSyncHotMerge.materializePreferences(
      document: _document(device: 'device-a'),
      identityMaps: maps,
      protectedPreferenceKeys: const <String>{
        WebDavSyncHotMerge.finishedMoviesPreference,
        WebDavSyncHotMerge.explicitlyWatchedSeriesPreference,
      },
    );

    expect(
      materialized,
      isNot(contains(WebDavSyncHotMerge.finishedMoviesPreference)),
    );
    expect(
      materialized,
      isNot(contains(WebDavSyncHotMerge.explicitlyWatchedSeriesPreference)),
    );
  });

  test('builder refuses non-finite scalar values', () {
    expect(
      () => _buildWithPreferences(maps, 'device-a', <String, Object?>{
        'bad': double.nan,
      }, now: 100),
      throwsFormatException,
    );
  });

  test('lossy portable twin preserves the richer local playback record', () {
    const rawPlayback =
        '{"video_a":{"type":"video","imdbId":"tt1",'
        '"positionMs":20,"updatedAt":100,"url":"signed"}}';
    const portablePlayback =
        '{"video_a":{"type":"video","imdbId":"tt1",'
        '"positionMs":20,"updatedAt":100}}';
    final built = WebDavSyncHotMerge.build(
      WebDavSyncBuildInput(
        circleProfileId: 'profile-circle',
        deviceId: 'device-a',
        rawPreferences: const <String, Object?>{
          WebDavSyncHotMerge.playbackPreference: rawPlayback,
        },
        portablePreferences: const <String, Object?>{
          WebDavSyncHotMerge.playbackPreference: portablePlayback,
        },
        identityMaps: maps,
        localNowMs: 100,
        clockOffsetMs: 0,
        serverNowMs: 100,
      ),
    );
    final output = WebDavSyncHotMerge.materializePreferences(
      document: built.document,
      identityMaps: maps,
      localRichRecords: built.localRichRecords,
      localPortableRecords: built.document.watchState.records,
    );
    final playback =
        jsonDecode(output[WebDavSyncHotMerge.playbackPreference]! as String)
            as Map<String, dynamic>;
    expect(playback['video_a']['url'], 'signed');
  });

  test('playlist items union by the app dedupe key and retain order', () {
    final first = <String, dynamic>{
      'provider': 'webdav',
      'webdavServerId': 'server',
      'webdavPath': '/one',
      'title': 'One',
    };
    final second = <String, dynamic>{
      'provider': 'torbox',
      'torboxTorrentId': '2',
      'title': 'Two',
    };
    final local = _buildWithPreferences(maps, 'device-a', <String, Object?>{
      WebDavSyncHotMerge.playlistPreference: jsonEncode(<Object>[first]),
    }, now: 100);
    final peer = _buildWithPreferences(maps, 'device-b', <String, Object?>{
      WebDavSyncHotMerge.playlistPreference: jsonEncode(<Object>[second]),
    }, now: 200);
    final merged = WebDavSyncHotMerge.merge(
      local: local.document,
      peers: <WebDavSyncHotDocument>[peer.document],
      tombstoneDocuments: const <WebDavSyncTombstoneDocument>[],
      nowMs: 300,
    );
    final output = WebDavSyncHotMerge.materializePreferences(
      document: merged.document,
      identityMaps: maps,
    );
    final items =
        jsonDecode(output[WebDavSyncHotMerge.playlistPreference]! as String)
            as List;
    expect(items, hasLength(2));
    expect(
      PlaylistDedupeKey.compute(Map<String, dynamic>.from(items.first as Map)),
      PlaylistDedupeKey.compute(second),
    );
  });

  test('WebDAV playlist identity is stable across local resource IDs', () {
    final mapsA = WebDavSyncIdentityMaps(
      circleToLocalProfiles: const <String, String>{
        'profile-circle': 'local-profile-a',
      },
      circleToLocalResources: const <String, String>{
        'resource-circle': 'local-resource-a',
      },
    );
    final mapsB = WebDavSyncIdentityMaps(
      circleToLocalProfiles: const <String, String>{
        'profile-circle': 'local-profile-b',
      },
      circleToLocalResources: const <String, String>{
        'resource-circle': 'local-resource-b',
      },
    );
    Map<String, Object?> preferences(String localResource) {
      final item = <String, dynamic>{
        'provider': 'webdav',
        'webdavServerId': localResource,
        'webdavPath': '/Shows/One',
        'title': 'One',
      };
      return <String, Object?>{
        WebDavSyncHotMerge.playlistPreference: jsonEncode(<Object>[item]),
        WebDavSyncHotMerge.playlistFavoritesPreference: jsonEncode(
          <String, bool>{PlaylistDedupeKey.compute(item): true},
        ),
      };
    }

    final first = _buildWithPreferences(
      mapsA,
      'device-a',
      preferences('local-resource-a'),
      now: 100,
    );
    final second = _buildWithPreferences(
      mapsB,
      'device-b',
      preferences('local-resource-b'),
      now: 100,
    );
    final firstKeys = first.document.watchState.records.keys.toSet();
    final secondKeys = second.document.watchState.records.keys.toSet();

    expect(firstKeys, secondKeys);
    expect(
      first.document.watchState.orders[WebDavSyncRecordKey.playlistOrder]!.keys,
      second
          .document
          .watchState
          .orders[WebDavSyncRecordKey.playlistOrder]!
          .keys,
    );
    expect(
      jsonEncode(first.document.toJson()),
      isNot(contains('local-resource-a')),
    );
    expect(
      jsonEncode(second.document.toJson()),
      isNot(contains('local-resource-b')),
    );

    final materialized = WebDavSyncHotMerge.materializePreferences(
      document: second.document,
      identityMaps: mapsA,
    );
    final localItems =
        jsonDecode(
              materialized[WebDavSyncHotMerge.playlistPreference]! as String,
            )
            as List;
    final localItem = Map<String, dynamic>.from(localItems.single as Map);
    final localFavorites =
        jsonDecode(
              materialized[WebDavSyncHotMerge.playlistFavoritesPreference]!
                  as String,
            )
            as Map<String, dynamic>;
    expect(localItem['webdavServerId'], 'local-resource-a');
    expect(localFavorites[PlaylistDedupeKey.compute(localItem)], isTrue);
  });

  test('Stremio direct pins use circle-mapped configuration hashes', () {
    final mapsA = WebDavSyncIdentityMaps(
      circleToLocalProfiles: const <String, String>{
        'profile-circle': 'local-profile-a',
      },
      circleToLocalResources: const <String, String>{
        'resource-circle': 'local-addon-resource-a',
      },
    );
    final mapsB = WebDavSyncIdentityMaps(
      circleToLocalProfiles: const <String, String>{
        'profile-circle': 'local-profile-b',
      },
      circleToLocalResources: const <String, String>{
        'resource-circle': 'local-addon-resource-b',
      },
    );
    String digest(String value) =>
        sha256.convert(utf8.encode(value)).toString();
    Map<String, Object?> preferences(String localResource) => <String, Object?>{
      '${WebDavSyncHotMerge.seriesSourcePrefix}tt123': jsonEncode(<Object>[
        <String, Object?>{
          'torrentHash': '',
          'torrentName': 'Direct stream',
          'debridService': 'stremio_direct',
          'debridTorrentId': '',
          'boundAt': 100,
          'addonId': 'configured.addon',
          'addonKey': digest(localResource),
          'streamKey': 'stream-profile',
        },
      ]),
    };

    final first = _buildWithPreferences(
      mapsA,
      'device-a',
      preferences('local-addon-resource-a'),
      now: 100,
    );
    final second = _buildWithPreferences(
      mapsB,
      'device-b',
      preferences('local-addon-resource-b'),
      now: 100,
    );
    expect(
      first.document.watchState.records.keys,
      second.document.watchState.records.keys,
    );
    expect(
      jsonEncode(first.document.toJson()),
      isNot(contains(digest('local-addon-resource-a'))),
    );

    final materialized = WebDavSyncHotMerge.materializePreferences(
      document: first.document,
      identityMaps: mapsB,
    );
    final sources =
        jsonDecode(
              materialized['${WebDavSyncHotMerge.seriesSourcePrefix}tt123']!
                  as String,
            )
            as List;
    expect(
      (sources.single as Map<String, dynamic>)['addonKey'],
      digest('local-addon-resource-b'),
    );

    final localBinding =
        'direct:${digest('local-addon-resource-a')}:stream-profile';
    final projected = WebDavSyncRecordKey.projectLocalTombstoneKey(
      WebDavSyncRecordKey.source('tt123', localBinding),
      mapsA,
    )!;
    expect(
      WebDavSyncRecordKey.decodePart(projected.split('/').last),
      'direct:${digest('resource-circle')}:stream-profile',
    );
  });

  test('canonical document ordering retains nested playback episodes', () {
    const playback =
        '{"series-a":{"type":"series","imdbId":"tt1",'
        '"title":"Series","seasons":{"1":{"2":{'
        '"positionMs":25,"updatedAt":100}}}}}';
    final built = _buildWithPreferences(maps, 'device-a', <String, Object?>{
      WebDavSyncHotMerge.playbackPreference: playback,
    }, now: 100);
    final reopened = WebDavSyncHotDocument.fromJson(
      jsonDecode(WebDavSyncCodec.canonicalJson(built.document.toJson())),
    );

    final output = WebDavSyncHotMerge.materializePreferences(
      document: reopened,
      identityMaps: maps,
    );
    final materialized =
        jsonDecode(output[WebDavSyncHotMerge.playbackPreference]! as String)
            as Map<String, dynamic>;

    expect(materialized['series-a']['seasons']['1']['2']['positionMs'], 25);
  });

  test('dormant device overlays only records newer than last success', () {
    final oldKey = WebDavSyncRecordKey.finishedMovie('old');
    final newKey = WebDavSyncRecordKey.finishedMovie('new');
    final local = _document(
      device: 'device-a',
      records: <String, WebDavSyncStampedValue>{
        oldKey: _value(100, 'device-a', true),
        newKey: _value(300, 'device-a', true),
      },
    );
    final merged = WebDavSyncHotMerge.merge(
      local: local,
      peers: <WebDavSyncHotDocument>[_document(device: 'device-b')],
      tombstoneDocuments: const <WebDavSyncTombstoneDocument>[],
      nowMs: 400,
      dormantSinceMs: 200,
    );
    expect(merged.document.watchState.records, isNot(contains(oldKey)));
    expect(merged.document.watchState.records, contains(newKey));
  });

  test('dormant scalar suppression applies independently per entry', () {
    final baseline = _buildWithPreferences(
      maps,
      'device-a',
      const <String, Object?>{'theme': 'dark', 'language': 'en'},
      now: 100,
    ).document;
    final local = _buildWithPreferences(
      maps,
      'device-a',
      const <String, Object?>{'theme': 'dark', 'language': 'fr'},
      now: 300,
      previous: baseline,
    ).document;
    final peer = _document(
      device: 'device-b',
      scalarTime: 150,
      scalars: const <String, Object>{'theme': 'light', 'language': 'en'},
    );

    final merged = WebDavSyncHotMerge.merge(
      local: local,
      peers: <WebDavSyncHotDocument>[peer],
      tombstoneDocuments: const <WebDavSyncTombstoneDocument>[],
      nowMs: 400,
      dormantSinceMs: 200,
    ).document;

    expect(merged.scalars.values, <String, Object>{
      'theme': 'light',
      'language': 'fr',
    });
  });

  test('dormant device retains an order-only edit after last success', () {
    final firstKey = WebDavSyncRecordKey.playlistItem('first');
    final secondKey = WebDavSyncRecordKey.playlistItem('second');
    final records = <String, WebDavSyncStampedValue>{
      firstKey: _value(100, 'device-a', const <String, Object>{'title': 'A'}),
      secondKey: _value(100, 'device-a', const <String, Object>{'title': 'B'}),
    };
    final local = _document(
      device: 'device-a',
      records: records,
      orders: <String, WebDavSyncOrderValue>{
        WebDavSyncRecordKey.playlistOrder: WebDavSyncOrderValue(
          stamp: _stamp(300, 'device-a'),
          keys: const <String>['second', 'first'],
        ),
      },
    );
    final peer = _document(
      device: 'device-b',
      records: <String, WebDavSyncStampedValue>{
        firstKey: _value(100, 'device-b', const <String, Object>{'title': 'A'}),
        secondKey: _value(100, 'device-b', const <String, Object>{
          'title': 'B',
        }),
      },
      orders: <String, WebDavSyncOrderValue>{
        WebDavSyncRecordKey.playlistOrder: WebDavSyncOrderValue(
          stamp: _stamp(100, 'device-b'),
          keys: const <String>['first', 'second'],
        ),
      },
    );

    final merged = WebDavSyncHotMerge.merge(
      local: local,
      peers: <WebDavSyncHotDocument>[peer],
      tombstoneDocuments: const <WebDavSyncTombstoneDocument>[],
      nowMs: 400,
      dormantSinceMs: 200,
    );

    expect(
      merged
          .document
          .watchState
          .orders[WebDavSyncRecordKey.playlistOrder]!
          .keys,
      const <String>['second', 'first'],
    );
  });

  test('a dormant sole device does not erase its own state', () {
    final key = WebDavSyncRecordKey.finishedMovie('tt1');
    final local = _document(
      device: 'device-a',
      scalarTime: 100,
      scalars: const <String, Object>{'theme': 'dark'},
      records: <String, WebDavSyncStampedValue>{
        key: _value(100, 'device-a', true),
      },
    );

    final merged = WebDavSyncHotMerge.merge(
      local: local,
      peers: const <WebDavSyncHotDocument>[],
      tombstoneDocuments: const <WebDavSyncTombstoneDocument>[],
      nowMs: 400,
      dormantSinceMs: 200,
    ).document;

    expect(merged.scalars.values['theme'], 'dark');
    expect(merged.watchState.records, contains(key));
  });

  test('wire tombstone documents require a valid publication time', () {
    final key = WebDavSyncRecordKey.finishedMovie('tt1');
    Map<String, Object?> source(int? publication) =>
        WebDavSyncTombstoneDocument(
          circleProfileId: 'profile-circle',
          items: <String, WebDavSyncTombstone>{
            key: WebDavSyncTombstone(
              key: key,
              stamp: _stamp(200, 'device-a'),
              firstPublishedAtMs: publication,
            ),
          },
        ).toJson();

    expect(
      () => WebDavSyncTombstoneDocument.fromJson(source(null)),
      throwsFormatException,
    );
    expect(
      () => WebDavSyncTombstoneDocument.fromJson(source(100)),
      throwsFormatException,
    );
    expect(
      WebDavSyncTombstoneDocument.fromJson(source(200)).items,
      contains(key),
    );
  });

  test('publication clamps every inherited future stamp', () {
    const future = 900;
    const now = 500;
    final source = WebDavSyncMergeResult(
      document: WebDavSyncHotDocument(
        circleProfileId: 'profile-circle',
        scalars: WebDavSyncScalarPart(
          semanticDigest: semanticDigestOf(const <String, Object>{
            'theme': 'dark',
          }),
          entries: const <String, WebDavSyncStampedValue>{
            'theme': WebDavSyncStampedValue(
              stamp: WebDavSyncStamp(
                normalizedTimeMs: future,
                originDeviceId: 'device-a',
              ),
              value: 'dark',
            ),
          },
        ),
        watchState: WebDavSyncWatchPart(
          stamp: const WebDavSyncStamp(
            normalizedTimeMs: future,
            originDeviceId: 'device-a',
          ),
          semanticDigest: semanticDigestOf(<String, Object?>{
            'records': <String, Object?>{
              'completion/movie/a': <String, Object?>{
                'stamp': <String, Object?>{
                  'time': future,
                  'origin': 'device-a',
                },
                'value': true,
              },
            },
            'orders': const <String, Object?>{},
          }),
          records: const <String, WebDavSyncStampedValue>{
            'completion/movie/a': WebDavSyncStampedValue(
              stamp: WebDavSyncStamp(
                normalizedTimeMs: future,
                originDeviceId: 'device-a',
              ),
              value: true,
            ),
          },
          orders: const <String, WebDavSyncOrderValue>{},
        ),
      ),
      tombstones: const <String, WebDavSyncTombstone>{
        'completion/movie/b': WebDavSyncTombstone(
          key: 'completion/movie/b',
          stamp: WebDavSyncStamp(
            normalizedTimeMs: 800,
            originDeviceId: 'device-a',
          ),
          firstPublishedAtMs: future,
        ),
      },
    );

    final clamped = WebDavSyncHotMerge.clampForPublication(
      source,
      serverNowMs: now,
    );

    expect(
      clamped.document.scalars.entries['theme']!.stamp.normalizedTimeMs,
      now,
    );
    expect(clamped.document.watchState.stamp.normalizedTimeMs, now);
    expect(
      clamped.document.watchState.records.values.single.stamp.normalizedTimeMs,
      now,
    );
    expect(clamped.tombstones.values.single.stamp.normalizedTimeMs, now);
    expect(clamped.tombstones.values.single.firstPublishedAtMs, now);
    expect(
      clamped.document.watchState.semanticDigest,
      semanticDigestOf(clamped.document.watchState.semanticPayload),
    );
  });
}

WebDavSyncBuiltHotState _buildWithPreferences(
  WebDavSyncIdentityMaps maps,
  String device,
  Map<String, Object?> preferences, {
  required int now,
  WebDavSyncHotDocument? previous,
}) => WebDavSyncHotMerge.build(
  WebDavSyncBuildInput(
    circleProfileId: 'profile-circle',
    deviceId: device,
    rawPreferences: preferences,
    portablePreferences: preferences,
    identityMaps: maps,
    localNowMs: now,
    clockOffsetMs: 0,
    serverNowMs: now,
    previous: previous,
  ),
);

WebDavSyncHotDocument _document({
  required String device,
  int scalarTime = 0,
  Map<String, Object> scalars = const <String, Object>{},
  Map<String, WebDavSyncStampedValue> records =
      const <String, WebDavSyncStampedValue>{},
  Map<String, WebDavSyncOrderValue> orders =
      const <String, WebDavSyncOrderValue>{},
}) {
  final scalarDigest = semanticDigestOf(scalars);
  final watchPayload = <String, Object?>{
    'records': <String, Object?>{
      for (final entry in records.entries) entry.key: entry.value.toJson(),
    },
    'orders': <String, Object?>{
      for (final entry in orders.entries) entry.key: entry.value.toJson(),
    },
  };
  return WebDavSyncHotDocument(
    circleProfileId: 'profile-circle',
    scalars: WebDavSyncScalarPart(
      semanticDigest: scalarDigest,
      entries: <String, WebDavSyncStampedValue>{
        for (final entry in scalars.entries)
          entry.key: WebDavSyncStampedValue(
            stamp: _stamp(scalarTime, device),
            value: entry.value,
          ),
      },
    ),
    watchState: WebDavSyncWatchPart(
      stamp: _stamp(scalarTime, device),
      semanticDigest: semanticDigestOf(watchPayload),
      records: records,
      orders: orders,
    ),
  );
}

WebDavSyncStampedValue _value(int time, String device, Object? value) =>
    WebDavSyncStampedValue(stamp: _stamp(time, device), value: value);

WebDavSyncStamp _stamp(int time, String device) =>
    WebDavSyncStamp(normalizedTimeMs: time, originDeviceId: device);

String _stampBytes(WebDavSyncHotDocument document, String key) =>
    WebDavSyncCodec.canonicalJson(
      document.scalars.entries[key]!.stamp.toJson(),
    );

Map<String, Object?> _legacyHotJson({
  required String device,
  required int scalarTime,
  required Map<String, Object> scalars,
}) {
  final emptyWatch = _document(device: device).watchState;
  return <String, Object?>{
    'version': 1,
    'circleProfileId': 'profile-circle',
    'scalars': <String, Object?>{
      'stamp': _stamp(scalarTime, device).toJson(),
      'semanticDigest': semanticDigestOf(scalars),
      'values': scalars,
    },
    'watchState': emptyWatch.toJson(),
  };
}
