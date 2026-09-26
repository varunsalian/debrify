import 'package:debrify/features/sources/data/pikpak_source_preparation.dart';
import 'package:debrify/features/sources/models/pikpak_prepared_source.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> video(String id, {String? name}) => {
  'id': id,
  'name': name ?? '$id.mkv',
  'mime_type': 'video/x-matroska',
  'phase': 'PHASE_TYPE_COMPLETE',
  'size': '1024',
};

class Fixture {
  final calls = <String>[];
  final waits = <Duration>[];
  var active = true;
  String? retireAt;
  Map<String, dynamic> added = {
    'task': {'file_id': 'root', 'id': 'task'},
  };
  Map<String, dynamic> Function(int) task = (_) => {
    'phase': 'PHASE_TYPE_COMPLETE',
  };
  Map<String, dynamic> Function(int) file = (_) => video('root');
  List<Map<String, dynamic>> Function(String) folder = (_) => [];
  var taskCalls = 0;
  var fileCalls = 0;

  void record(String call) {
    calls.add(call);
    if (call == retireAt) active = false;
  }

  Future<PikPakPreparedSource> run({bool guarded = true}) =>
      preparePikPakSource(
        magnet: 'fixture-magnet',
        canContinue: guarded ? () => active : null,
        addDownload: (magnet) async {
          record('add:$magnet');
          return added;
        },
        readTask: (id) async {
          record('task:$id');
          return task(taskCalls++);
        },
        readFile: (id) async {
          record('file:$id');
          return file(fileCalls++);
        },
        listFolder: (id) async {
          record('folder:$id');
          return folder(id);
        },
        delay: (duration) async {
          waits.add(duration);
          record('wait');
        },
      );
}

void main() {
  test('ready task proceeds directly to immutable video snapshot', () async {
    final raw = video('root')..['_fullPath'] = 'Season/root.mkv';
    final fixture = Fixture();
    fixture.file = (_) => raw;
    final result = await fixture.run();
    expect(fixture.calls, ['add:fixture-magnet', 'task:task', 'file:root']);
    expect(result.fileId, 'root');
    expect(result.videos.single.id, 'root');
    expect(result.videos.single.relativePath, 'Season/root.mkv');
    expect(result.videos.single.sizeBytes, 1024);
    raw['name'] = 'changed';
    expect(result.videos.single.name, 'root.mkv');
    expect(() => result.videos.clear(), throwsUnsupportedError);
  });

  for (final added in [
    {
      'file': {'id': 'root'},
      'task': {'id': 'ignored'},
    },
    {'id': 'root'},
  ]) {
    test('direct add response $added waits before checking file', () async {
      final fixture = Fixture();
      fixture.added = added;
      await fixture.run();
      expect(fixture.calls, ['add:fixture-magnet', 'wait', 'file:root']);
      expect(fixture.waits, [const Duration(seconds: 2)]);
    });
  }

  for (final progress in [90, '91']) {
    test('task progress $progress skips initial detail delay', () async {
      final fixture = Fixture();
      fixture.task = (_) => {'progress': progress};
      await fixture.run();
      expect(fixture.waits, isEmpty);
      expect(fixture.taskCalls, 1);
    });
  }

  test(
    'task and detail exhaustion retain seven/five attempts and waits',
    () async {
      final fixture = Fixture();
      fixture.task = (_) => {'progress': 'invalid'};
      fixture.file = (_) => {'phase': 'PHASE_TYPE_RUNNING'};
      await expectLater(
        fixture.run(),
        throwsA(isA<PikPakSourceStillProcessing>()),
      );
      expect(fixture.taskCalls, 7);
      expect(fixture.fileCalls, 5);
      expect(fixture.waits, List.filled(11, const Duration(seconds: 2)));
    },
  );

  test('task read error falls through to delayed file checks', () async {
    final fixture = Fixture();
    fixture.task = (_) => throw StateError('fixture');
    await fixture.run();
    expect(fixture.calls, [
      'add:fixture-magnet',
      'task:task',
      'wait',
      'file:root',
    ]);
  });

  test('transient file read error retries with original delay', () async {
    final fixture = Fixture();
    fixture.file = (attempt) {
      if (attempt == 0) throw StateError('fixture');
      return video('root');
    };
    await fixture.run();
    expect(fixture.fileCalls, 2);
    expect(fixture.waits, [const Duration(seconds: 2)]);
  });

  for (final failure in ['task', 'file']) {
    test('$failure hard failure stops immediately', () async {
      final fixture = Fixture();
      if (failure == 'task') {
        fixture.task = (_) => {'phase': 'PHASE_TYPE_ERROR', 'progress': 100};
      } else {
        fixture.file = (_) => {'phase': 'PHASE_TYPE_ERROR'};
      }
      await expectLater(fixture.run(), throwsA(isA<PikPakSourceFailed>()));
      expect(fixture.fileCalls, failure == 'task' ? 0 : 1);
      expect(fixture.waits, isEmpty);
    });
  }

  test('non-video completion reports processing without retrying', () async {
    final fixture = Fixture();
    fixture.file = (_) => {
      'phase': 'PHASE_TYPE_COMPLETE',
      'mime_type': 'text/plain',
    };
    await expectLater(
      fixture.run(),
      throwsA(isA<PikPakSourceStillProcessing>()),
    );
    expect(fixture.fileCalls, 1);
  });

  test('missing add file id fails before polling', () async {
    final fixture = Fixture();
    fixture.added = {};
    await expectLater(
      fixture.run(),
      throwsA(
        predicate<Object>(
          (error) => error.toString().contains('PikPak: no file id returned'),
        ),
      ),
    );
    expect(fixture.calls, ['add:fixture-magnet']);
  });

  test(
    'folder traversal preserves paths, case-insensitive ordering and partial results',
    () async {
      final original = video('nested', name: 'B.mkv');
      final fixture = Fixture();
      fixture.file = (_) => {
        'phase': 'PHASE_TYPE_COMPLETE',
        'kind': 'drive#folder',
      };
      fixture.folder = (id) => switch (id) {
        'root' => [
          video('z', name: 'z.mkv'),
          {'id': 'sub', 'kind': 'drive#folder', 'name': 'Season'},
          {'id': 'broken', 'kind': 'drive#folder', 'name': 'Broken'},
          video('a', name: 'A.mkv'),
          {'id': 'text', 'mime_type': 'text/plain', 'name': 'ignored.mkv'},
        ],
        'sub' => [original],
        _ => throw StateError('fixture'),
      };
      final result = await fixture.run();
      expect(result.videos.map((v) => v.name), [
        'A.mkv',
        'Season/B.mkv',
        'z.mkv',
      ]);
      expect(original['name'], 'B.mkv');
      expect(fixture.calls.where((c) => c.startsWith('folder:')), [
        'folder:root',
        'folder:sub',
        'folder:broken',
      ]);
    },
  );

  test('folder recursion stops before depth five', () async {
    final fixture = Fixture();
    fixture.file = (_) => {
      'phase': 'PHASE_TYPE_COMPLETE',
      'kind': 'drive#folder',
    };
    fixture.folder = (id) => [
      video(id),
      {'id': '${id}x', 'kind': 'drive#folder', 'name': id},
    ];
    final result = await fixture.run();
    expect(result.videos, hasLength(5));
    expect(fixture.calls.where((c) => c.startsWith('folder:')), hasLength(5));
  });

  for (final boundary in [
    'before',
    'add:fixture-magnet',
    'task:task',
    'wait',
    'file:root',
    'folder:root',
    'folder:sub',
  ]) {
    test('retirement at $boundary prevents the next operation', () async {
      final fixture = Fixture();
      fixture.active = boundary != 'before';
      fixture.retireAt = boundary;
      fixture.task = (_) => {'progress': 0};
      fixture.file = (_) => {
        'phase': 'PHASE_TYPE_COMPLETE',
        'kind': 'drive#folder',
      };
      fixture.folder = (id) => id == 'root'
          ? [
              {'id': 'sub', 'kind': 'drive#folder', 'name': 'Sub'},
              {'id': 'other', 'kind': 'drive#folder', 'name': 'Other'},
            ]
          : [video(id)];
      await expectLater(fixture.run(), throwsA(isA<PikPakSourceRetired>()));
      if (boundary == 'before') {
        expect(fixture.calls, isEmpty);
      } else {
        expect(fixture.calls.last, boundary);
      }
    });
  }

  test(
    'retirement during a failing reader is not swallowed by retry handling',
    () async {
      final fixture = Fixture();
      fixture.file = (_) {
        fixture.active = false;
        throw StateError('fixture');
      };
      await expectLater(fixture.run(), throwsA(isA<PikPakSourceRetired>()));
      expect(fixture.fileCalls, 1);
      expect(fixture.waits, isEmpty);
    },
  );

  test('automatic caller without guard retains its full preparation', () async {
    final fixture = Fixture();
    fixture.active = false;
    final result = await fixture.run(guarded: false);
    expect(result.videos, hasLength(1));
    expect(fixture.calls, ['add:fixture-magnet', 'task:task', 'file:root']);
  });
}
