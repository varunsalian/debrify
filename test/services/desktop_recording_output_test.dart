// Step 2: the desktop custom-recording folder and the padded desktop
// capture window. Folder behaviour runs against a real temp directory; the
// padding maths goes straight through paddedRecordingWindow.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/features/recordings/data/recording_output_store.dart';
import 'package:debrify/features/recordings/models/recording_output_settings.dart';
import 'package:debrify/services/desktop_recording_service.dart';

void main() {
  tearDown(() {
    RecordingOutputStore.cached = const RecordingOutputSettings();
  });

  group('customRecordingsDir', () {
    late Directory temp;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('debrify_output_test');
    });

    tearDown(() {
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });

    test('writable folder resolves to that directory', () async {
      final dir = await DesktopRecordingService.customRecordingsDir(temp.path);
      expect(dir, isNotNull);
      expect(dir!.path, temp.path);
      // The write probe is removed again — the folder listing stays clean.
      expect(
        File(
          '${temp.path}${Platform.pathSeparator}.debrify_write_probe',
        ).existsSync(),
        isFalse,
      );
    });

    test('missing folder yields null', () async {
      final missing = Directory(
        '${temp.path}${Platform.pathSeparator}never-created',
      );
      expect(
        await DesktopRecordingService.customRecordingsDir(missing.path),
        isNull,
      );
    });

    test('null or empty path yields null', () async {
      expect(await DesktopRecordingService.customRecordingsDir(null), isNull);
      expect(await DesktopRecordingService.customRecordingsDir(''), isNull);
    });

    test('a plain file yields null instead of throwing', () async {
      final file = File('${temp.path}${Platform.pathSeparator}plain.txt')
        ..createSync();
      expect(
        await DesktopRecordingService.customRecordingsDir(file.path),
        isNull,
      );
    });

    test('recordingsDir uses the writable custom folder', () async {
      // A primed custom folder short-circuits before the path_provider
      // lookup, so recordingsDir() returns exactly that directory.
      RecordingOutputStore.cached = RecordingOutputSettings(
        directoryPath: temp.path,
      );
      final dir = await DesktopRecordingService.recordingsDir();
      expect(dir.path, temp.path);
    });
  });

  group('paddedRecordingWindow (desktop)', () {
    const start = 2 * 60000;
    const end = 5 * 60000;

    test('desktop default settings capture the literal window', () {
      final window = paddedRecordingWindow(
        startMs: start,
        endMs: end,
        settings: const RecordingOutputSettings(),
        platform: RecordingPlatform.desktop,
      );
      expect(window.startMs, start);
      expect(window.endMs, end);
    });

    test('explicit pads fire early and stop late', () {
      final window = paddedRecordingWindow(
        startMs: start,
        endMs: end,
        settings: const RecordingOutputSettings(
          startPadMinutes: 2,
          endPadMinutes: 5,
        ),
        platform: RecordingPlatform.desktop,
      );
      expect(window.startMs, start - 2 * 60000);
      expect(window.endMs, end + 5 * 60000);
    });

    test('pads clamp to 15 minutes', () {
      final window = paddedRecordingWindow(
        startMs: start,
        endMs: end,
        settings: const RecordingOutputSettings(
          startPadMinutes: 120,
          endPadMinutes: 120,
        ),
        platform: RecordingPlatform.desktop,
      );
      expect(window.startMs, start - 15 * 60000);
      expect(window.endMs, end + 15 * 60000);
    });
  });
}
