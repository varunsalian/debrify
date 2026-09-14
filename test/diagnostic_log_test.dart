import 'dart:convert';
import 'dart:io';

import 'package:debrify/services/diagnostic_log.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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
    'critical lifecycle events are queued and become durable on flush',
    () async {
      log.recordEvent(
        source: 'profile_gate',
        event: 'gate_created',
        durable: true,
        fields: const {'privateTitle': 'PRIVATE_SENTINEL', 'count': 3},
      );
      expect(
        Directory('${root.path}/diagnostics').listSync().whereType<File>(),
        isEmpty,
      );
      await log.flush();
      final files = Directory('${root.path}/diagnostics')
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('-dart-critical.jsonl'))
          .toList();
      expect(files, hasLength(1));
      final text = files.single.readAsStringSync();
      expect(text, contains('gate_created'));
      expect(text, isNot(contains('PRIVATE_SENTINEL')));
      // Re-open after the async flush has completed.
      final reopened = DiagnosticLog(clock: () => now);
      await reopened.initialize(directoryOverride: root);
      expect(
        utf8.decode((await reopened.exportLastWindow()).bytes),
        contains('gate_created'),
      );
      await reopened.dispose();
    },
  );

  test(
    'immediate error bursts share a bounded writer and report loss',
    () async {
      for (var i = 0; i < 2500; i++) {
        log.recordEvent(
          source: 'test',
          event: 'burst',
          flushImmediately: true,
          fields: {'index': i},
        );
      }
      await Future.wait([log.flush(), log.flush()]);
      log.recordEvent(
        source: 'test',
        event: 'after_burst',
        flushImmediately: true,
      );
      final text = utf8.decode((await log.exportLastWindow()).bytes);
      expect(text, contains('entries_dropped'));
      expect(text, contains('after_burst'));
    },
  );

  test(
    'bounded export retains newest records across out-of-order files',
    () async {
      final dir = Directory('${root.path}/diagnostics');
      for (var group = 0; group < 3; group++) {
        final lines = List.generate(
          100,
          (i) => jsonEncode({
            'timestamp': now
                .subtract(Duration(seconds: 300 - group * 100 - i))
                .toIso8601String(),
            'event': 'record_${group * 100 + i}',
            'padding': 'x' * 150,
          }),
        );
        await File(
          '${dir.path}/debrify-diagnostics-${now.millisecondsSinceEpoch}-${2 - group}-android.jsonl',
        ).writeAsString('${lines.join('\n')}\n');
      }
      final exported = await log.exportLastWindow(maxBytes: 8192);
      expect(exported.bytes.length, lessThanOrEqualTo(8192));
      expect(exported.truncated, isTrue);
      final text = utf8.decode(exported.bytes);
      expect(text, contains('record_299'));
      expect(text, isNot(contains('"event":"record_0"')));
      expect(
        const LineSplitter().convert(text).map(jsonDecode).toList(),
        isNotEmpty,
      );
    },
  );

  test(
    'critical history outlives a long movie but expires after 24 hours',
    () async {
      log.recordEvent(
        source: 'android_main_activity',
        event: 'critical_start',
        durable: true,
      );
      log.recordEvent(source: 'test', event: 'ordinary_start');
      await log.flush();
      now = now.add(const Duration(hours: 3));
      var text = utf8.decode((await log.exportLastWindow()).bytes);
      expect(text, contains('critical_start'));
      expect(text, isNot(contains('ordinary_start')));
      now = now.add(const Duration(hours: 22));
      text = utf8.decode((await log.exportLastWindow()).bytes);
      expect(text, isNot(contains('critical_start')));
    },
  );

  test('corrupt lines do not hide later native or Dart records', () async {
    final segment =
        now.millisecondsSinceEpoch -
        now.millisecondsSinceEpoch % const Duration(minutes: 15).inMilliseconds;
    final file = File(
      '${root.path}/diagnostics/debrify-diagnostics-$segment-android-critical.jsonl',
    );
    final record = jsonEncode({
      'timestamp': now.toIso8601String(),
      'event': 'after_corruption',
    });
    await file.writeAsBytes(
      utf8
          .encode('{"partial":\n')
          .followedBy([0xff, 0x0a])
          .followedBy(utf8.encode('$record\n'))
          .toList(),
    );
    final text = utf8.decode((await log.exportLastWindow()).bytes);
    expect(text, contains('after_corruption'));
    final header = jsonDecode(const LineSplitter().convert(text).first) as Map;
    expect(header['fields']['malformedLineCount'], 2);
  });

  test('a torn critical tail cannot swallow the next appended event', () async {
    log.recordEvent(source: 'test', event: 'before', durable: true);
    await log.flush();
    final file = Directory('${root.path}/diagnostics')
        .listSync()
        .whereType<File>()
        .singleWhere((file) => file.path.endsWith('-dart-critical.jsonl'));
    file.writeAsStringSync('{"torn":', mode: FileMode.append);
    log.recordEvent(source: 'test', event: 'after', durable: true);
    final text = utf8.decode((await log.exportLastWindow()).bytes);
    expect(text, contains('"event":"before"'));
    expect(text, contains('"event":"after"'));
  });

  test('critical files stay bounded and device reset clears them', () async {
    for (var i = 0; i < 100; i++) {
      log.recordEvent(
        source: 'test',
        event: 'critical',
        durable: true,
        fields: {'index': i},
      );
    }
    await log.flush();
    final file = Directory('${root.path}/diagnostics')
        .listSync()
        .whereType<File>()
        .singleWhere((file) => file.path.endsWith('-dart-critical.jsonl'));
    expect(file.lengthSync(), lessThanOrEqualTo(2048));
    expect(file.readAsStringSync(), contains('"index":99'));
    await log.clearForDeviceReset();
    log.recordEvent(source: 'test', event: 'must_not_reappear', durable: true);
    expect(Directory('${root.path}/diagnostics').existsSync(), isFalse);
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

  test('a missing plugin error names its channel and method', () async {
    // The message is Flutter's fixed format naming code constants; keeping
    // the channel is what lets a platform gap be located from the log.
    log.recordFlutterError(
      FlutterErrorDetails(
        exception: MissingPluginException(
          'No implementation found for method listen on channel '
          'com.example.app/some_events',
        ),
        stack: StackTrace.current,
      ),
    );
    final exported = await log.exportLastWindow();
    final events = const LineSplitter()
        .convert(utf8.decode(exported.bytes))
        .map((line) => jsonDecode(line) as Map<String, dynamic>)
        .where((entry) => entry['event'] == 'framework_error')
        .toList(growable: false);
    expect(events, hasLength(1));
    final fields = events.single['fields'] as Map<String, dynamic>;
    expect(fields['errorType'], 'MissingPluginException');
    // Labels pass through the log's sanitizer, which maps '/' to '_'; the
    // result still names the channel unambiguously.
    expect(fields['channel'], 'com.example.app_some_events');
    expect(fields['method'], 'listen');

    // Any other framework error stays exactly as before: no channel field.
    log.recordFlutterError(
      FlutterErrorDetails(
        exception: StateError('unrelated'),
        stack: StackTrace.current,
      ),
    );
    final again = await log.exportLastWindow();
    final second =
        const LineSplitter()
                .convert(utf8.decode(again.bytes))
                .map((line) => jsonDecode(line) as Map<String, dynamic>)
                .where((entry) => entry['event'] == 'framework_error')
                .last['fields']
            as Map<String, dynamic>;
    expect(second.containsKey('channel'), isFalse);
    expect(second.containsKey('method'), isFalse);
  });
}
