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

  test('leaf bound fails closed instead of truncating', () {
    final records = <String, WebDavSyncCircleLeaf<Map<String, Object?>>>{
      for (var index = 0; index <= WebDavSyncLibraryDocument.maxLeaves; index++)
        'future/$index': leaf(index, 'device-a', const <String, Object?>{}),
    };
    final document = WebDavSyncLibraryDocument(
      circleProfileId: 'profile-circle',
      records: records,
    );

    expect(document.toJson, throwsFormatException);
  });

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
