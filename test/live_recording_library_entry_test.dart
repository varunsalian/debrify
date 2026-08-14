import 'package:debrify/services/live_recording_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recording library rows preserve native ownership provenance', () {
    final owned = RecordingLibraryEntry.fromMap(<String, dynamic>{
      'taskId': 'task-a',
      'uri': 'content://recordings/a',
      'ownerProfileId': 'profile-a',
      'ownershipState': 'assigned',
    });
    final orphan = RecordingLibraryEntry.fromMap(<String, dynamic>{
      'taskId': null,
      'uri': 'content://recordings/orphan',
      'ownerProfileId': null,
      'ownershipState': 'unassigned',
    });

    expect(owned.ownerProfileId, 'profile-a');
    expect(owned.isUnassigned, isFalse);
    expect(orphan.ownerProfileId, isNull);
    expect(orphan.isUnassigned, isTrue);
  });

  test('Admin recovery visibility excludes another profile ownership', () {
    RecordingLibraryEntry entry(String uri, String? owner) =>
        RecordingLibraryEntry.fromMap(<String, dynamic>{
          'taskId': owner == null ? null : 'task-$owner',
          'uri': uri,
          'ownerProfileId': owner,
          'ownershipState': owner == null ? 'unassigned' : 'assigned',
        });

    final visible = selectVisibleRecordingLibraryEntries(
      entries: <RecordingLibraryEntry>[
        entry('content://recordings/a', 'profile-a'),
        entry('content://recordings/b', 'profile-b'),
        entry('content://recordings/orphan', null),
      ],
      ownerProfileId: 'profile-a',
      includeUnassigned: true,
    );

    expect(visible.map((entry) => entry.uri), <String>[
      'content://recordings/a',
      'content://recordings/orphan',
    ]);
  });
}
