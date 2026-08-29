import 'dart:convert';
import 'dart:io';

import 'package:debrify/services/diagnostic_log.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late DateTime now;
  late DiagnosticLog log;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('debrify-diagnostics-');
    now = DateTime.utc(2026, 8, 29, 12);
    log = DiagnosticLog(clock: () => now, maxSegmentBytes: 2048);
    await log.initialize(directoryOverride: root);
  });

  tearDown(() async {
    await log.dispose();
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'export omits exception bodies, content fields, and private stack paths',
    () async {
      const sentinel = 'PRIVATE_SENTINEL';
      log.recordEvent(
        source: 'test',
        event: 'structured_event',
        fields: const <String, Object?>{
          'count': 4,
          'state': DiagnosticLabel('ready'),
          'content': sentinel,
        },
      );
      log.recordError(
        source: 'test',
        event: 'sample_failure',
        error: StateError('failed while playing $sentinel'),
        stackTrace: StackTrace.fromString(
          '#0 /Users/private-user/project/lib/main.dart:10:2\n'
          '#1 package:debrify/main.dart:20:4',
        ),
        flushImmediately: false,
      );

      final exported = await log.exportLastWindow();
      final text = utf8.decode(exported.bytes);
      final records = const LineSplitter()
          .convert(text)
          .map((line) => jsonDecode(line) as Map<String, dynamic>)
          .toList();

      expect(exported.entryCount, greaterThanOrEqualTo(3));
      expect(text, isNot(contains(sentinel)));
      expect(text, isNot(contains('private-user')));
      expect(text, contains('/[private-home]/project/lib/main.dart'));
      final structured = records.singleWhere(
        (record) => record['event'] == 'structured_event',
      );
      expect(structured['fields'], <String, dynamic>{
        'count': 4,
        'state': 'ready',
      });
      final error = records.singleWhere(
        (record) => record['event'] == 'sample_failure',
      );
      final fields = error['fields'] as Map<String, dynamic>;
      expect(fields['errorType'], 'StateError');
      expect(fields, isNot(contains('error')));
      expect(fields['stack'], isA<List<dynamic>>());
      expect((fields['stack'] as List<dynamic>), hasLength(2));
    },
  );

  test(
    'Flutter error context and exception text never enter an export',
    () async {
      const sentinel = 'FLUTTER_PRIVATE_SENTINEL';
      log.recordFlutterError(
        FlutterErrorDetails(
          exception: FlutterError('widget title $sentinel'),
          stack: StackTrace.fromString('#0 package:debrify/main.dart:20:4'),
          context: ErrorDescription('while rendering $sentinel'),
          library: 'private library $sentinel',
        ),
      );

      final text = utf8.decode((await log.exportLastWindow()).bytes);

      expect(text, isNot(contains(sentinel)));
      expect(text, contains('framework_error'));
      expect(text, contains('FlutterError'));
    },
  );

  test('export excludes records older than two hours', () async {
    log.recordEvent(source: 'test', event: 'old_entry');
    await log.flush();

    now = now.add(const Duration(hours: 3));
    log.recordEvent(source: 'test', event: 'recent_entry');
    final exported = await log.exportLastWindow();
    final text = utf8.decode(exported.bytes);

    expect(text, contains('recent_entry'));
    expect(text, isNot(contains('old_entry')));
  });

  test('export merges native Android segments', () async {
    await log.flush();
    final segmentMs =
        now.millisecondsSinceEpoch -
        (now.millisecondsSinceEpoch %
            const Duration(minutes: 15).inMilliseconds);
    final directory = Directory('${root.path}/diagnostics');
    final nativeFile = File(
      '${directory.path}/debrify-diagnostics-$segmentMs-android.jsonl',
    );
    await nativeFile.writeAsString(
      '${jsonEncode(<String, Object?>{'timestamp': now.toIso8601String(), 'level': 'warning', 'source': 'android_process', 'event': 'previous_exit', 'message': 'reason=native_crash'})}\n',
    );

    final exported = await log.exportLastWindow();
    final text = utf8.decode(exported.bytes);

    expect(text, contains('previous_exit'));
    expect(text, contains('native_crash'));
  });

  test('a noisy time segment stays within its byte budget', () async {
    for (var index = 0; index < 200; index++) {
      log.recordEvent(
        source: 'test',
        event: 'bounded_line',
        fields: <String, Object?>{
          'index': index,
          'status': DiagnosticLabel('x' * 80),
        },
      );
    }
    await log.flush();

    final directory = Directory('${root.path}/diagnostics');
    final dartFiles = directory.listSync().whereType<File>().where(
      (file) => file.path.endsWith('-dart.jsonl'),
    );
    expect(dartFiles, isNotEmpty);
    for (final file in dartFiles) {
      expect(await file.length(), lessThanOrEqualTo(2048));
    }

    final exported = utf8.decode((await log.exportLastWindow()).bytes);
    expect(exported, contains('"index":199'));
    expect(exported, isNot(contains('"index":0,')));
  });

  test(
    'device reset deletes the store and permanently stops writers',
    () async {
      log.recordEvent(source: 'test', event: 'before_reset');
      await log.flush();
      final directory = Directory('${root.path}/diagnostics');
      expect(await directory.exists(), isTrue);

      for (var index = 0; index < 200; index++) {
        log.recordEvent(
          source: 'test',
          event: 'pending_before_reset',
          fields: <String, Object?>{'index': index},
        );
      }
      final inFlightFlush = log.flush();
      await log.clearForDeviceReset();
      await inFlightFlush;
      log.recordEvent(source: 'test', event: 'after_reset');
      await log.initialize(directoryOverride: root);
      await log.flush();

      expect(log.isAvailable, isFalse);
      expect(await directory.exists(), isFalse);
    },
  );
}
