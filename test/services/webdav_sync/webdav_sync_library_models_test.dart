import 'package:debrify/services/webdav_sync/webdav_sync_circle_models.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_engine_state.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_hot_models.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_library_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  WebDavSyncCircleLeaf<Map<String, Object?>> leaf(
    int time,
    String origin,
    Map<String, Object?>? value,
  ) => WebDavSyncCircleLeaf<Map<String, Object?>>(
    stamp: WebDavSyncStamp(normalizedTimeMs: time, originDeviceId: origin),
    value: value,
  );

  test('library round-trips unknown namespaces and nullable leaves', () {
    final document = WebDavSyncLibraryDocument(
      circleProfileId: 'profile-circle',
      records: <String, WebDavSyncCircleLeaf<Map<String, Object?>>>{
        'future/family/item': leaf(20, 'device-b', <String, Object?>{
          'rawUrl': 'https://sealed.example/private',
          'headers': <String, Object?>{'Authorization': 'secret'},
        }),
        'future/family/deleted': leaf(21, 'device-b', null),
      },
    );

    final decoded = WebDavSyncLibraryDocument.fromJson(document.toJson());

    expect(decoded.toJson(), document.toJson());
    expect(decoded.records['future/family/deleted']!.value, isNull);
  });

  test('merge orders winners by time, origin, then semantic digest', () {
    const key = 'future/item';
    final merged = WebDavSyncLibraryMerge.merge(
      circleProfileId: 'profile-circle',
      documents: <WebDavSyncLibraryDocument>[
        WebDavSyncLibraryDocument(
          circleProfileId: 'profile-circle',
          records: <String, WebDavSyncCircleLeaf<Map<String, Object?>>>{
            key: leaf(10, 'device-a', const <String, Object?>{'value': 9}),
          },
        ),
        WebDavSyncLibraryDocument(
          circleProfileId: 'profile-circle',
          records: <String, WebDavSyncCircleLeaf<Map<String, Object?>>>{
            key: leaf(10, 'device-b', null),
          },
        ),
      ],
    );

    expect(merged.records[key]!.stamp.originDeviceId, 'device-b');
    expect(merged.records[key]!.value, isNull);
  });

  test('TV pools above the leaf bound fail closed instead of truncating', () {
    final records = <String, WebDavSyncCircleLeaf<Map<String, Object?>>>{
      for (var index = 0; index <= WebDavSyncLibraryDocument.maxLeaves; index++)
        'tv/pool/Y2hhbm5lbA/hash$index': leaf(
          index,
          'device-a',
          const <String, Object?>{'generationId': 'generation-a'},
        ),
    };
    final document = WebDavSyncLibraryDocument(
      circleProfileId: 'profile-circle',
      records: records,
    );

    expect(document.toJson, throwsFormatException);
  });

  test(
    'clear-and-rescrape on A drops stale B hashes by generation in every merge order',
    () {
      const channel = 'Y2hhbm5lbA';
      final a = WebDavSyncLibraryDocument(
        circleProfileId: 'profile-circle',
        records: <String, WebDavSyncCircleLeaf<Map<String, Object?>>>{
          'tv/ch/$channel': leaf(1, 'device-a', const <String, Object?>{
            'name': 'Channel',
          }),
          'tv/pool-gen/$channel': leaf(2, 'device-a', const <String, Object?>{
            'generationId': 'generation-a',
          }),
          'tv/pool/$channel/oldhash': leaf(
            2,
            'device-a',
            const <String, Object?>{'generationId': 'generation-a'},
          ),
        },
      );
      final b = WebDavSyncLibraryDocument(
        circleProfileId: 'profile-circle',
        records: <String, WebDavSyncCircleLeaf<Map<String, Object?>>>{
          'tv/pool-gen/$channel': leaf(3, 'device-b', const <String, Object?>{
            'generationId': 'generation-b',
          }),
          'tv/pool/$channel/newhash': leaf(
            3,
            'device-b',
            const <String, Object?>{'generationId': 'generation-b'},
          ),
        },
      );

      for (final documents in <List<WebDavSyncLibraryDocument>>[
        <WebDavSyncLibraryDocument>[a, b],
        <WebDavSyncLibraryDocument>[b, a],
      ]) {
        final merged = WebDavSyncLibraryMerge.merge(
          circleProfileId: 'profile-circle',
          documents: documents,
        );
        expect(merged.records, isNot(contains('tv/pool/$channel/oldhash')));
        expect(merged.records, contains('tv/pool/$channel/newhash'));
      }
    },
  );

  test('channel tombstone suppresses its generation and pool children', () {
    const channel = 'Y2hhbm5lbA';
    final merged = WebDavSyncLibraryMerge.merge(
      circleProfileId: 'profile-circle',
      documents: <WebDavSyncLibraryDocument>[
        WebDavSyncLibraryDocument(
          circleProfileId: 'profile-circle',
          records: <String, WebDavSyncCircleLeaf<Map<String, Object?>>>{
            'tv/ch/$channel': leaf(2, 'device-b', null),
            'tv/pool-gen/$channel': leaf(1, 'device-a', const {
              'generationId': 'generation-a',
            }),
            'tv/pool/$channel/hash': leaf(1, 'device-a', const {
              'generationId': 'generation-a',
            }),
          },
        ),
      ],
    );

    expect(merged.records.keys, <String>['tv/ch/$channel']);
  });

  test('concurrent same-channel edits converge independent of merge order', () {
    const key = 'tv/ch/Y2hhbm5lbA';
    WebDavSyncLibraryDocument document(String origin, String name) =>
        WebDavSyncLibraryDocument(
          circleProfileId: 'profile-circle',
          records: <String, WebDavSyncCircleLeaf<Map<String, Object?>>>{
            key: leaf(10, origin, <String, Object?>{'name': name}),
          },
        );
    final a = document('device-a', 'A');
    final b = document('device-b', 'B');
    final ab = WebDavSyncLibraryMerge.merge(
      circleProfileId: 'profile-circle',
      documents: <WebDavSyncLibraryDocument>[a, b],
    );
    final ba = WebDavSyncLibraryMerge.merge(
      circleProfileId: 'profile-circle',
      documents: <WebDavSyncLibraryDocument>[b, a],
    );

    expect(ab.toJson(), ba.toJson());
    expect(ab.records[key]!.value!['name'], 'B');
  });

  test('TV desired numbers survive ordered and replayed merges verbatim', () {
    WebDavSyncLibraryDocument document(
      String key,
      String origin,
      String name,
    ) => WebDavSyncLibraryDocument(
      circleProfileId: 'profile-circle',
      records: <String, WebDavSyncCircleLeaf<Map<String, Object?>>>{
        key: leaf(10, origin, <String, Object?>{
          'name': name,
          'channelNumber': 1,
        }),
      },
    );
    final a = document('tv/ch/YQ', 'device-a', 'A');
    final b = document('tv/ch/Yg', 'device-b', 'B');
    final c = document('tv/ch/Yw', 'device-c', 'C');

    for (final documents in <List<WebDavSyncLibraryDocument>>[
      <WebDavSyncLibraryDocument>[a, b, c],
      <WebDavSyncLibraryDocument>[a, c, b],
      <WebDavSyncLibraryDocument>[b, a, c],
      <WebDavSyncLibraryDocument>[b, c, a],
      <WebDavSyncLibraryDocument>[c, a, b],
      <WebDavSyncLibraryDocument>[c, b, a],
    ]) {
      final merged = WebDavSyncLibraryMerge.merge(
        circleProfileId: 'profile-circle',
        documents: documents,
      );
      for (final replayed in documents) {
        final replay = WebDavSyncLibraryMerge.merge(
          circleProfileId: 'profile-circle',
          documents: <WebDavSyncLibraryDocument>[merged, replayed],
        );
        expect(replay.semanticDigest, merged.semanticDigest);
      }
      expect(
        merged.records.values.map((item) => item.value!['channelNumber']),
        everyElement(1),
      );
    }
  });

  test(
    'IPTV desired positions survive ordered and replayed merges verbatim',
    () {
      WebDavSyncLibraryDocument document(
        String key,
        String origin,
        String name,
        int position,
        int createdAt,
      ) => WebDavSyncLibraryDocument(
        circleProfileId: 'profile-circle',
        records: <String, WebDavSyncCircleLeaf<Map<String, Object?>>>{
          key: leaf(10, origin, <String, Object?>{
            'name': name,
            'position': position,
            'createdAt': createdAt,
          }),
        },
      );
      final a = document('iptv/list/YQ', 'device-a', 'A', 0, 0);
      final b = document('iptv/list/Yg', 'device-b', 'B', 0, 1);
      final c = document('iptv/list/Yw', 'device-c', 'C', 1, 2);

      for (final documents in <List<WebDavSyncLibraryDocument>>[
        <WebDavSyncLibraryDocument>[a, b, c],
        <WebDavSyncLibraryDocument>[a, c, b],
        <WebDavSyncLibraryDocument>[b, a, c],
        <WebDavSyncLibraryDocument>[b, c, a],
        <WebDavSyncLibraryDocument>[c, a, b],
        <WebDavSyncLibraryDocument>[c, b, a],
      ]) {
        final merged = WebDavSyncLibraryMerge.merge(
          circleProfileId: 'profile-circle',
          documents: documents,
        );
        for (final replayed in documents) {
          final replay = WebDavSyncLibraryMerge.merge(
            circleProfileId: 'profile-circle',
            documents: <WebDavSyncLibraryDocument>[merged, replayed],
          );
          expect(replay.semanticDigest, merged.semanticDigest);
        }
        expect(merged.records['iptv/list/YQ']!.value!['position'], 0);
        expect(merged.records['iptv/list/Yg']!.value!['position'], 0);
        expect(merged.records['iptv/list/Yw']!.value!['position'], 1);
      }
    },
  );

  test('pending apply journals and verifies digest plus both revisions', () {
    final target = WebDavSyncLibraryDocument(
      circleProfileId: 'profile-circle',
      records: <String, WebDavSyncCircleLeaf<Map<String, Object?>>>{
        'future/item': leaf(10, 'device-a', const <String, Object?>{'v': 1}),
      },
    );
    final pending = WebDavSyncPendingLibraryApply(
      localProfileId: 'local-profile',
      target: target,
      observedRevisions: const WebDavSyncDatabaseRevisions(
        debrifyTv: 4,
        iptvCatalog: 9,
      ),
    );

    final json = pending.toJson();
    final decoded = WebDavSyncPendingLibraryApply.fromJson(json);
    expect(json['targetDigest'], target.semanticDigest);
    expect(decoded.observedRevisions.debrifyTv, 4);
    expect(decoded.observedRevisions.iptvCatalog, 9);
    expect(decoded.target.toJson(), target.toJson());

    expect(
      () => WebDavSyncPendingLibraryApply.fromJson(<String, Object?>{
        ...json,
        'targetDigest': '0' * 64,
      }),
      throwsFormatException,
    );
  });
}
