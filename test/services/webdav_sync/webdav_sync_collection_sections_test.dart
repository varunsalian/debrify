import 'package:debrify/models/home_collection.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_collection_sections.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_hot_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    '513 large collections fit a readable manifest without losing records',
    () {
      final source = _source('profile', 513);
      final parts = WebDavSyncCollectionSections.split(source);
      final references = [
        for (final name in [
          'bootstrap',
          'profiles',
          'resources',
          'tombstones/profile',
          ...parts.keys,
        ])
          _reference(name),
      ];
      final manifest = WebDavSyncManifest(
        circleId: 'circle',
        deviceId: 'device',
        updatedAtMs: 1,
        clockOffsetMs: 0,
        graphSchemaClaim: 2,
        profileMap: const {'backup': 'profile'},
        resourceMap: const {},
        sections: references,
      );
      expect(
        WebDavSyncManifest.fromJson(manifest.toJson()).sections.length,
        lessThanOrEqualTo(WebDavSyncLimits.maxSectionsPerManifest),
      );
      expect(parts.length, lessThan(513));
      final records = {
        for (final part in parts.values) ...part.watchState.records,
      };
      expect(records.keys.toSet(), source.watchState.records.keys.toSet());
      for (final entry in records.entries) {
        expect(entry.value, same(source.watchState.records[entry.key]));
      }
      expect(
        parts['collections-v2/profile/0']!.watchState.orders,
        source.watchState.orders,
      );
    },
  );

  test(
    'all profiles and retained references share one section budget',
    () async {
      final sources = [_source('one', 4), _source('two', 4)];
      final retained = [
        for (var i = 0; i < 496; i++) _reference('reserved/$i'),
        _reference('collections-v2/one/0'),
        _reference('hot/one'),
        _reference('graph'),
      ];
      final reserved = WebDavSyncCollectionSections.reservedSectionCount(
        sources.map((s) => s.circleProfileId),
        retained: retained,
      );
      expect(reserved, 507); // 3 shared + 4 per profile + 496 retained.
      final plan = await WebDavSyncCollectionSections.plan(
        sources,
        reservedSections: reserved,
      );
      final parts = {
        for (final source in sources)
          ...WebDavSyncCollectionSections.split(
            source,
            targetBytes: plan.targetBytes,
          ),
      };
      final count = parts.keys
          .where((name) => name.startsWith(WebDavSyncCollectionSections.prefix))
          .length;
      expect(
        count + reserved,
        lessThanOrEqualTo(WebDavSyncLimits.maxSectionsPerManifest),
      );
      expect(count, 4);
    },
  );

  test(
    'unchanged shard counts skip sizing until the shared budget shrinks',
    () async {
      final source = _source('profile', 3);
      final reused = await WebDavSyncCollectionSections.plan(
        [source],
        reservedSections: 510,
        unchangedSectionCounts: const {'profile': 2},
      );
      expect(reused.targetBytes, 512 * 1024);
      expect(reused.sectionCounts['profile'], 2);
      final repacked = await WebDavSyncCollectionSections.plan(
        [source],
        reservedSections: 511,
        unchangedSectionCounts: const {'profile': 2},
      );
      expect(repacked.sectionCounts['profile'], 1);
      expect(
        WebDavSyncCollectionSections.split(
          source,
          targetBytes: repacked.targetBytes,
        ),
        hasLength(2),
      );
    },
  );

  test('small inventories retain the 512 KiB target', () async {
    final source = _source('profile', 3);
    final plan = await WebDavSyncCollectionSections.plan([
      source,
    ], reservedSections: 7);
    expect(plan.targetBytes, 512 * 1024);
    expect(
      WebDavSyncCollectionSections.split(source, targetBytes: plan.targetBytes),
      hasLength(4),
    );
  });

  test(
    'capacity exhaustion rejects instead of exceeding the 32 MiB shard bound',
    () async {
      final source = _source('profile', 2, payloadBytes: 20 * 1024 * 1024);
      await expectLater(
        WebDavSyncCollectionSections.plan([source], reservedSections: 511),
        throwsFormatException,
      );
    },
  );
}

WebDavSyncHotDocument _source(
  String profile,
  int count, {
  int payloadBytes = 382 * 1024,
}) {
  const stamp = WebDavSyncStamp(normalizedTimeMs: 1, originDeviceId: 'device');
  final padding = 'x' * payloadBytes;
  return WebDavSyncHotDocument(
    circleProfileId: profile,
    scalars: WebDavSyncScalarPart(
      semanticDigest: semanticDigestOf({}),
      entries: const {},
    ),
    watchState: WebDavSyncWatchPart(
      stamp: stamp,
      semanticDigest: 'a' * 64,
      records: {
        for (var i = 0; i < count; i++)
          'homecollection/$i': WebDavSyncStampedValue(
            stamp: stamp,
            value: HomeCollection(id: '$i', title: padding).toJson(),
          ),
      },
      orders: {
        'homecollections/items': WebDavSyncOrderValue(
          stamp: stamp,
          keys: [for (var i = 0; i < count; i++) '$i'],
        ),
      },
    ),
  );
}

WebDavSyncSectionReference _reference(String name) =>
    WebDavSyncSectionReference(
      name: name,
      contentHash: 'b' * 64,
      semanticDigest: 'c' * 64,
      updatedAtMs: 1,
      schemaVersion: 1,
      size: 100,
    );
