import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/models/profiles/user_profile.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_circle_merge.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_circle_models.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_codec.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_hot_models.dart';
import 'package:flutter_test/flutter_test.dart';

const _digest1 =
    '1111111111111111111111111111111111111111111111111111111111111111';
const _digest2 =
    '2222222222222222222222222222222222222222222222222222222222222222';

void main() {
  const a = WebDavSyncStamp(normalizedTimeMs: 100, originDeviceId: 'device-a');
  const b = WebDavSyncStamp(normalizedTimeMs: 100, originDeviceId: 'device-b');
  const newer = WebDavSyncStamp(
    normalizedTimeMs: 200,
    originDeviceId: 'device-a',
  );

  test('concurrent profile and resource adds union across devices', () {
    final profiles = WebDavSyncCircleMerge.mergeProfiles(<
      WebDavSyncProfilesDocument
    >[
      _profiles({'p-a': WebDavSyncCircleLeaf(stamp: a, value: _profile('A'))}),
      _profiles({'p-b': WebDavSyncCircleLeaf(stamp: b, value: _profile('B'))}),
    ]);
    final resources = WebDavSyncCircleMerge.mergeResources(
      <WebDavSyncResourcesDocument>[
        _resources({'r-a': _resourceEntry(a, 'p-a', 'A')}),
        _resources({'r-b': _resourceEntry(b, 'p-b', 'B')}),
      ],
    );

    expect(profiles.profiles.keys, unorderedEquals(<String>['p-a', 'p-b']));
    expect(resources.resources.keys, unorderedEquals(<String>['r-a', 'r-b']));
  });

  test('same-record LWW is deterministic in every input order', () {
    final values = <WebDavSyncProfilesDocument>[
      _profiles({'p-a': WebDavSyncCircleLeaf(stamp: a, value: _profile('A'))}),
      _profiles({'p-a': WebDavSyncCircleLeaf(stamp: b, value: _profile('B'))}),
      _profiles({
        'p-a': WebDavSyncCircleLeaf(stamp: newer, value: _profile('newest')),
      }),
    ];
    for (final order in <List<int>>[
      [0, 1, 2],
      [0, 2, 1],
      [1, 0, 2],
      [1, 2, 0],
      [2, 0, 1],
      [2, 1, 0],
    ]) {
      final merged = WebDavSyncCircleMerge.mergeProfiles(
        order.map((index) => values[index]),
      );
      expect(merged.profiles['p-a']!.value!.name, 'newest');
      expect(merged.profiles['p-a']!.stamp.normalizedTimeMs, 200);
    }
  });

  test('newer null never resurrects from a stale peer', () {
    final live = _profiles({
      'p-a': WebDavSyncCircleLeaf(stamp: a, value: _profile('A')),
    });
    final deleted = _profiles({
      'p-a': const WebDavSyncCircleLeaf<WebDavSyncProfileValue>(
        stamp: newer,
        value: null,
      ),
    });
    final first = WebDavSyncCircleMerge.mergeProfiles([live, deleted]);
    final afterStaleReturns = WebDavSyncCircleMerge.mergeProfiles([
      first,
      live,
    ]);
    expect(afterStaleReturns.profiles['p-a']!.value, isNull);
    expect(afterStaleReturns.profiles['p-a']!.stamp.normalizedTimeMs, 200);
  });

  test('resource metadata and secret leaves merge independently', () {
    final olderSecret = WebDavSyncCircleLeaf<WebDavSyncResourceSecretConfig>(
      stamp: a,
      value: _secret(_digest1, 'old-envelope'),
    );
    final newerSecret = WebDavSyncCircleLeaf<WebDavSyncResourceSecretConfig>(
      stamp: newer,
      value: _secret(_digest2, 'new-envelope'),
    );
    final newerMetadata = WebDavSyncCircleLeaf<WebDavSyncResourceMetadata>(
      stamp: newer,
      value: _metadata('p-a', 'new metadata'),
    );
    final olderMetadata = WebDavSyncCircleLeaf<WebDavSyncResourceMetadata>(
      stamp: a,
      value: _metadata('p-a', 'old metadata'),
    );

    final merged = WebDavSyncCircleMerge.mergeResources([
      _resources({
        'r-a': WebDavSyncResourceEntry(
          metadata: newerMetadata,
          secretConfig: olderSecret,
        ),
      }),
      _resources({
        'r-a': WebDavSyncResourceEntry(
          metadata: olderMetadata,
          secretConfig: newerSecret,
        ),
      }),
    ]);
    expect(merged.resources['r-a']!.metadata.value!.label, 'new metadata');
    expect(
      merged.resources['r-a']!.secretConfig!.value!.semanticDigest,
      _digest2,
    );
  });

  test(
    'unchanged rebuilt values preserve exact stamps and secret envelope',
    () {
      final baselineProfiles = _profiles({
        'p-a': WebDavSyncCircleLeaf(stamp: a, value: _profile('A')),
      });
      final baselineResources = _resources({
        'r-a': WebDavSyncResourceEntry(
          metadata: WebDavSyncCircleLeaf(
            stamp: a,
            value: _metadata('p-a', 'A'),
          ),
          secretConfig: WebDavSyncCircleLeaf(
            stamp: b,
            value: _secret(_digest1, 'cHJldmlvdXM='),
          ),
        ),
      });
      final rebuiltProfiles = WebDavSyncCircleMerge.rebuildProfiles(
        WebDavSyncProfilesBuildInput(
          deviceId: 'device-new',
          localNowMs: 999,
          clockOffsetMs: 0,
          serverNowMs: 999,
          profiles: {
            'p-a': WebDavSyncLocalCircleValue(
              value: _profile('A'),
              updatedAtMs: 900,
            ),
          },
          previous: baselineProfiles,
        ),
      );
      final rebuiltResources = WebDavSyncCircleMerge.rebuildResources(
        WebDavSyncResourcesBuildInput(
          deviceId: 'device-new',
          localNowMs: 999,
          clockOffsetMs: 0,
          serverNowMs: 999,
          resources: {
            'r-a': WebDavSyncLocalCircleValue(
              value: _metadata('p-a', 'A'),
              updatedAtMs: 900,
            ),
          },
          secrets: {
            'r-a': WebDavSyncLocalCircleValue(
              value: _secret(_digest1, 'bmV3LXJhbmRvbQ=='),
              updatedAtMs: 900,
            ),
          },
          grants: const {},
          settings: const {},
          bindings: const {},
          previous: baselineResources,
        ),
      );

      expect(rebuiltProfiles.profiles['p-a']!.stamp, same(a));
      expect(rebuiltResources.resources['r-a']!.metadata.stamp, same(a));
      expect(rebuiltResources.resources['r-a']!.secretConfig!.stamp, same(b));
      expect(
        rebuiltResources.resources['r-a']!.secretConfig!.value!.envelope,
        'cHJldmlvdXM=',
      );
    },
  );

  test('admin wire merge is associative and defers the same local admin', () {
    final oldX = WebDavSyncCircleLeaf<WebDavSyncProfileValue>(
      stamp: a,
      value: _managingAdmin('X'),
    );
    final oldY = WebDavSyncCircleLeaf<WebDavSyncProfileValue>(
      stamp: a,
      value: _managingAdmin('Y'),
    );
    final demotedX = WebDavSyncCircleLeaf<WebDavSyncProfileValue>(
      stamp: newer,
      value: _member('X'),
    );
    final demotedY = WebDavSyncCircleLeaf<WebDavSyncProfileValue>(
      stamp: newer,
      value: _member('Y'),
    );
    final documents = <WebDavSyncProfilesDocument>[
      _profiles({'x-admin': oldX}),
      _profiles({'y-admin': oldY}),
      _profiles({'y-admin': demotedY}),
      _profiles({'x-admin': demotedX}),
    ];
    String? expected;
    for (final order in _permutations(<int>[0, 1, 2, 3])) {
      final left = WebDavSyncCircleMerge.mergeProfiles(
        <WebDavSyncProfilesDocument>[
          WebDavSyncCircleMerge.mergeProfiles(<WebDavSyncProfilesDocument>[
            WebDavSyncCircleMerge.mergeProfiles(<WebDavSyncProfilesDocument>[
              documents[order[0]],
              documents[order[1]],
            ]),
            documents[order[2]],
          ]),
          documents[order[3]],
        ],
      );
      final paired = WebDavSyncCircleMerge.mergeProfiles(
        <WebDavSyncProfilesDocument>[
          WebDavSyncCircleMerge.mergeProfiles(<WebDavSyncProfilesDocument>[
            documents[order[0]],
            documents[order[1]],
          ]),
          WebDavSyncCircleMerge.mergeProfiles(<WebDavSyncProfilesDocument>[
            documents[order[2]],
            documents[order[3]],
          ]),
        ],
      );
      final encoded = WebDavSyncCodec.canonicalJson(left.toJson());
      expected ??= encoded;
      expect(encoded, expected);
      expect(WebDavSyncCodec.canonicalJson(paired.toJson()), expected);
      expect(left.profiles['x-admin'], same(demotedX));
      expect(left.profiles['y-admin'], same(demotedY));
      expect(
        WebDavSyncCircleMerge.selectAdminSafetyDeferral(
          profiles: left,
          localManagingAdminCircleProfileIds: const <String>{
            'x-admin',
            'y-admin',
          },
        ),
        'y-admin',
      );
      WebDavSyncCircleMerge.validateApplicableState(
        profiles: left,
        resources: _resources(const <String, WebDavSyncResourceEntry>{}),
        localManagingAdminCircleProfileIds: const <String>{
          'x-admin',
          'y-admin',
        },
      );
    }
  });

  test('live setting accepts a grant that exists only in local inventory', () {
    final winners = WebDavSyncResourcesDocument(
      resources: const <String, WebDavSyncResourceEntry>{},
      grants:
          const <
            String,
            Map<String, WebDavSyncCircleLeaf<WebDavSyncGrantValue>>
          >{},
      settings:
          <String, Map<String, WebDavSyncCircleLeaf<WebDavSyncSettingsValue>>>{
            'p-local': <String, WebDavSyncCircleLeaf<WebDavSyncSettingsValue>>{
              'r-local': WebDavSyncCircleLeaf<WebDavSyncSettingsValue>(
                stamp: newer,
                value: const WebDavSyncSettingsValue(
                  enabled: true,
                  settings: <String, Object?>{'mode': 'pending'},
                ),
              ),
            },
          },
      bindings:
          const <
            String,
            Map<String, WebDavSyncCircleLeaf<WebDavSyncBindingValue>>
          >{},
    );
    const localGrant = (
      circleProfileId: 'p-local',
      circleResourceId: 'r-local',
    );

    final applicable = WebDavSyncCircleMerge.deriveApplicableResources(
      profiles: _profiles(const {}),
      resources: winners,
      localCircleProfileIds: const <String>{'p-local'},
      localCircleResourceIds: const <String>{'r-local'},
      localCircleGrantIds: const <WebDavSyncCircleGrantId>{localGrant},
    );

    expect(applicable.settings['p-local']!['r-local']!.value, isNotNull);
    WebDavSyncCircleMerge.validateApplicableState(
      profiles: _profiles(const {}),
      resources: applicable,
      localCircleProfileIds: const <String>{'p-local'},
      localCircleResourceIds: const <String>{'r-local'},
      localCircleGrantIds: const <WebDavSyncCircleGrantId>{localGrant},
      localManagingAdminCircleProfileIds: const <String>{'p-local'},
    );
  });

  test(
    'an absent parent defers its live child without manufacturing tombstones',
    () {
      final deferred = <String>[];
      final winners = _resources(<String, WebDavSyncResourceEntry>{
        'r-orphan': WebDavSyncResourceEntry(
          metadata: WebDavSyncCircleLeaf<WebDavSyncResourceMetadata>(
            stamp: newer,
            value: _metadata('p-missing', 'Still live'),
          ),
          secretConfig: WebDavSyncCircleLeaf<WebDavSyncResourceSecretConfig>(
            stamp: newer,
            value: _secret(_digest1, 'c2VjcmV0'),
          ),
        ),
      });

      final applicable = WebDavSyncCircleMerge.deriveApplicableResources(
        profiles: _profiles(const {}),
        resources: winners,
        onDeferred: deferred.add,
      );

      expect(applicable.resources, isNot(contains('r-orphan')));
      expect(winners.resources['r-orphan']!.metadata.value, isNotNull);
      expect(winners.resources['r-orphan']!.secretConfig!.value, isNotNull);
      expect(
        WebDavSyncCodec.canonicalJson(applicable.toJson()),
        isNot(contains('"value":null')),
      );
      expect(deferred, isNotEmpty);
    },
  );

  test(
    'resource tombstone suppresses a newer offline grant in every order',
    () {
      final live = WebDavSyncResourcesDocument(
        resources: <String, WebDavSyncResourceEntry>{
          'r-a': _resourceEntry(a, 'p-a', 'A'),
        },
        grants:
            <String, Map<String, WebDavSyncCircleLeaf<WebDavSyncGrantValue>>>{
              'p-a': <String, WebDavSyncCircleLeaf<WebDavSyncGrantValue>>{
                'r-a': WebDavSyncCircleLeaf<WebDavSyncGrantValue>(
                  stamp: newer,
                  value: const WebDavSyncGrantValue(permissions: 1),
                ),
              },
            },
        settings: const {},
        bindings: const {},
      );
      final deleted = _resources(<String, WebDavSyncResourceEntry>{
        'r-a': const WebDavSyncResourceEntry(
          metadata: WebDavSyncCircleLeaf<WebDavSyncResourceMetadata>(
            stamp: WebDavSyncStamp(
              normalizedTimeMs: 150,
              originDeviceId: 'device-a',
            ),
            value: null,
          ),
        ),
      });
      final profiles =
          _profiles(<String, WebDavSyncCircleLeaf<WebDavSyncProfileValue>>{
            'p-a': WebDavSyncCircleLeaf<WebDavSyncProfileValue>(
              stamp: a,
              value: _managingAdmin('A'),
            ),
          });

      String? expectedDigest;
      for (final documents in <List<WebDavSyncResourcesDocument>>[
        <WebDavSyncResourcesDocument>[live, deleted],
        <WebDavSyncResourcesDocument>[deleted, live],
      ]) {
        final applicable = WebDavSyncCircleMerge.deriveApplicableResources(
          profiles: profiles,
          resources: WebDavSyncCircleMerge.mergeResources(documents),
        );
        expect(applicable.resources['r-a']!.metadata.value, isNull);
        expect(applicable.grants['p-a'], isNull);
        WebDavSyncCircleMerge.validateApplicableState(
          profiles: profiles,
          resources: applicable,
        );
        expectedDigest ??= applicable.semanticDigest;
        expect(applicable.semanticDigest, expectedDigest);
      }
    },
  );

  test(
    'a frozen registry deletion neither restamps nor defeats a newer re-grant',
    () {
      const deletion = WebDavSyncCircleDeletion(
        kind: WebDavSyncCircleDeletionKind.grant,
        timeMs: 150,
        originDeviceId: 'device-a',
        normalizedTimeFrozen: true,
        circleProfileId: 'p-a',
        circleResourceId: 'r-a',
      );
      final first = WebDavSyncCircleMerge.rebuildResources(
        WebDavSyncResourcesBuildInput(
          deviceId: 'device-a',
          localNowMs: 200,
          clockOffsetMs: 0,
          serverNowMs: 3000,
          resources: const {},
          secrets: const {},
          grants:
              <
                String,
                Map<String, WebDavSyncLocalCircleValue<WebDavSyncGrantValue>>
              >{
                'p-a':
                    <String, WebDavSyncLocalCircleValue<WebDavSyncGrantValue>>{
                      'r-a':
                          const WebDavSyncLocalCircleValue<
                            WebDavSyncGrantValue
                          >(
                            value: WebDavSyncGrantValue(permissions: 1),
                            updatedAtMs: 200,
                          ),
                    },
              },
          settings: const {},
          bindings: const {},
          deletions: const <WebDavSyncCircleDeletion>[deletion],
        ),
      );
      final second = WebDavSyncCircleMerge.rebuildResources(
        WebDavSyncResourcesBuildInput(
          deviceId: 'device-a',
          localNowMs: 1200,
          clockOffsetMs: 1000,
          serverNowMs: 3000,
          resources: const {},
          secrets: const {},
          grants:
              <
                String,
                Map<String, WebDavSyncLocalCircleValue<WebDavSyncGrantValue>>
              >{
                'p-a':
                    <String, WebDavSyncLocalCircleValue<WebDavSyncGrantValue>>{
                      'r-a':
                          const WebDavSyncLocalCircleValue<
                            WebDavSyncGrantValue
                          >(
                            value: WebDavSyncGrantValue(permissions: 1),
                            updatedAtMs: 200,
                          ),
                    },
              },
          settings: const {},
          bindings: const {},
          deletions: const <WebDavSyncCircleDeletion>[deletion],
          previous: first,
        ),
      );

      expect(first.grants['p-a']!['r-a']!.value, isNotNull);
      expect(first.grants['p-a']!['r-a']!.stamp.normalizedTimeMs, 200);
      expect(second.semanticDigest, first.semanticDigest);
      expect(second.grants['p-a']!['r-a']!.value, isNotNull);
      expect(second.grants['p-a']!['r-a']!.stamp.normalizedTimeMs, 200);
    },
  );

  test('strict decoders require exact keys and enforce profile bounds', () {
    expect(
      () => WebDavSyncProfilesDocument.fromJson({
        'version': 1,
        'profiles': const {},
        'extra': true,
      }),
      throwsFormatException,
    );
    expect(
      () => WebDavSyncProfilesDocument.fromJson({'version': 1}),
      throwsFormatException,
    );
    expect(
      () => WebDavSyncProfilesDocument.fromJson({
        'version': 1,
        'profiles': {
          'p-a': {
            'stamp': {'time': 1, 'origin': 'device-a'},
          },
        },
      }),
      throwsFormatException,
    );
    expect(
      () => WebDavSyncProfilesDocument.fromJson({
        'version': 1,
        'profiles': {
          for (var index = 0; index < 4097; index++)
            'p-$index': {
              'stamp': {'time': 1, 'origin': 'device-a'},
              'value': null,
            },
        },
      }),
      throwsFormatException,
    );
  });
}

WebDavSyncProfilesDocument _profiles(
  Map<String, WebDavSyncCircleLeaf<WebDavSyncProfileValue>> profiles,
) => WebDavSyncProfilesDocument(profiles: profiles);

WebDavSyncResourcesDocument _resources(
  Map<String, WebDavSyncResourceEntry> resources,
) => WebDavSyncResourcesDocument(
  resources: resources,
  grants: const {},
  settings: const {},
  bindings: const {},
);

WebDavSyncResourceEntry _resourceEntry(
  WebDavSyncStamp stamp,
  String owner,
  String label,
) => WebDavSyncResourceEntry(
  metadata: WebDavSyncCircleLeaf(stamp: stamp, value: _metadata(owner, label)),
);

WebDavSyncResourceMetadata _metadata(String owner, String label) =>
    WebDavSyncResourceMetadata(
      type: ConnectionResourceType.realDebrid,
      label: label,
      ownerCircleProfileId: owner,
      publicConfig: const {'schemaVersion': 1},
      publicSchemaVersion: 1,
      enabled: true,
    );

WebDavSyncResourceSecretConfig _secret(String digest, String envelope) =>
    WebDavSyncResourceSecretConfig(
      semanticDigest: digest,
      type: ConnectionResourceType.realDebrid,
      ownerCircleProfileId: 'p-a',
      publicSchemaVersion: 1,
      payloadVersion: 1,
      envelope: envelope,
    );

WebDavSyncProfileValue _profile(String name) => WebDavSyncProfileValue(
  name: name,
  role: UserProfileRole.admin,
  policy: const {
    'schemaVersion': ProfilePolicy.currentSchemaVersion,
    'enabled': <String>[],
  },
  enabled: true,
  lockOnResume: false,
  setupComplete: true,
  lifecycle: UserProfileLifecycle.active,
  pin: const WebDavSyncProfilePin(resetRequired: false),
);

WebDavSyncProfileValue _managingAdmin(String name) => WebDavSyncProfileValue(
  name: name,
  role: UserProfileRole.admin,
  policy: const <String, Object?>{
    'schemaVersion': ProfilePolicy.currentSchemaVersion,
    'enabled': <String>['manageProfiles'],
  },
  enabled: true,
  lockOnResume: false,
  setupComplete: true,
  lifecycle: UserProfileLifecycle.active,
  pin: const WebDavSyncProfilePin(resetRequired: false),
);

WebDavSyncProfileValue _member(String name) => WebDavSyncProfileValue(
  name: name,
  role: UserProfileRole.member,
  policy: const <String, Object?>{
    'schemaVersion': ProfilePolicy.currentSchemaVersion,
    'enabled': <String>[],
  },
  enabled: true,
  lockOnResume: false,
  setupComplete: true,
  lifecycle: UserProfileLifecycle.active,
  pin: const WebDavSyncProfilePin(resetRequired: false),
);

Iterable<List<T>> _permutations<T>(List<T> values) sync* {
  if (values.length <= 1) {
    yield List<T>.from(values);
    return;
  }
  for (var index = 0; index < values.length; index++) {
    final head = values[index];
    final rest = List<T>.from(values)..removeAt(index);
    for (final tail in _permutations(rest)) {
      yield <T>[head, ...tail];
    }
  }
}
