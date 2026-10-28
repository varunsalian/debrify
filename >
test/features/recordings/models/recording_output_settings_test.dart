// Behaviour for the recording-output preference: the JSON contract shared
// with native Kotlin, the tolerant decode a corrupted store must never break
// on, the platform padding defaults, and the store round-trip.

import 'package:debrify/features/recordings/data/recording_output_store.dart';
import 'package:debrify/features/recordings/models/recording_output_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    RecordingOutputStore.cached = const RecordingOutputSettings();
  });

  group('RecordingOutputSettings JSON', () {
    test('round-trips every field', () {
      const settings = RecordingOutputSettings(
        treeUri: 'content://com.android.externalstorage.documents/tree/primary',
        treeDisplayName: 'USB Drive',
        directoryPath: r'D:\Recordings',
        startPadMinutes: 5,
        endPadMinutes: 10,
      );

      final decoded = RecordingOutputSettings.decode(settings.encode());

      expect(decoded, settings);
      expect(decoded.hashCode, settings.hashCode);
      expect(decoded.treeUri, settings.treeUri);
      expect(decoded.treeDisplayName, settings.treeDisplayName);
      expect(decoded.directoryPath, settings.directoryPath);
      expect(decoded.startPadMinutes, settings.startPadMinutes);
      expect(decoded.endPadMinutes, settings.endPadMinutes);
    });

    test('toJson omits null fields', () {
      const settings = RecordingOutputSettings(directoryPath: '/mnt/share');

      expect(settings.toJson(), {'directoryPath': '/mnt/share'});
      expect(const RecordingOutputSettings().toJson(), isEmpty);
    });

    test('decode and fromJson tolerate garbage instead of throwing', () {
      const defaults = RecordingOutputSettings();

      expect(RecordingOutputSettings.decode(null), defaults);
      expect(RecordingOutputSettings.decode(''), defaults);
      expect(RecordingOutputSettings.decode('not json'), defaults);
      expect(RecordingOutputSettings.decode('"a string"'), defaults);
      expect(RecordingOutputSettings.decode('[1,2]'), defaults);
      expect(RecordingOutputSettings.fromJson(null), defaults);
      // Wrong-typed fields fall back to nulls, not to half-parsed garbage.
      expect(
        RecordingOutputSettings.decode(
          '{"treeUri": 42, "startPadMinutes": "x", "endPadMinutes": 3.5}',
        ),
        defaults,
      );
    });
  });

  group('padding', () {
    test('defaults keep today\'s behaviour per platform', () {
      const settings = RecordingOutputSettings();

      expect(settings.startPadFor(RecordingPlatform.android), 0);
      expect(settings.startPadFor(RecordingPlatform.desktop), 0);
      expect(settings.endPadFor(RecordingPlatform.android), 2);
      expect(settings.endPadFor(RecordingPlatform.desktop), 0);
    });

    test('explicit padding is clamped to 0..15 on both edges', () {
      const huge = RecordingOutputSettings(startPadMinutes: 99, endPadMinutes: 99);
      expect(huge.startPadFor(RecordingPlatform.desktop), 15);
      expect(huge.endPadFor(RecordingPlatform.android), 15);

      const negative = RecordingOutputSettings(
        startPadMinutes: -4,
        endPadMinutes: -1,
      );
      expect(negative.startPadFor(RecordingPlatform.android), 0);
      expect(negative.endPadFor(RecordingPlatform.desktop), 0);

      const explicit = RecordingOutputSettings(
        startPadMinutes: 1,
        endPadMinutes: 3,
      );
      expect(explicit.startPadFor(RecordingPlatform.android), 1);
      expect(explicit.endPadFor(RecordingPlatform.desktop), 3);
    });

    test('paddedRecordingWindow moves only the capture window', () {
      const startMs = 600000;
      const endMs = 1200000;

      final androidDefaults = paddedRecordingWindow(
        startMs: startMs,
        endMs: endMs,
        settings: const RecordingOutputSettings(),
        platform: RecordingPlatform.android,
      );
      expect(androidDefaults.startMs, startMs);
      expect(androidDefaults.endMs, endMs + 2 * 60000);

      final desktopDefaults = paddedRecordingWindow(
        startMs: startMs,
        endMs: endMs,
        settings: const RecordingOutputSettings(),
        platform: RecordingPlatform.desktop,
      );
      expect(desktopDefaults.startMs, startMs);
      expect(desktopDefaults.endMs, endMs);

      final custom = paddedRecordingWindow(
        startMs: startMs,
        endMs: endMs,
        settings: const RecordingOutputSettings(
          startPadMinutes: 5,
          endPadMinutes: 10,
        ),
        platform: RecordingPlatform.desktop,
      );
      expect(custom.startMs, startMs - 5 * 60000);
      expect(custom.endMs, endMs + 10 * 60000);
    });
  });

  group('folder selection', () {
    test('hasCustomFolder ignores null and empty folder fields', () {
      expect(const RecordingOutputSettings().hasCustomFolder, isFalse);
      expect(const RecordingOutputSettings(treeUri: '').hasCustomFolder, isFalse);
      expect(
        const RecordingOutputSettings(directoryPath: '').hasCustomFolder,
        isFalse,
      );
      expect(
        const RecordingOutputSettings(treeUri: 'content://tree').hasCustomFolder,
        isTrue,
      );
      expect(
        const RecordingOutputSettings(directoryPath: '/mnt/share').hasCustomFolder,
        isTrue,
      );
    });

    test('copyWith(clearFolder: true) clears all three folder fields', () {
      const picked = RecordingOutputSettings(
        treeUri: 'content://tree',
        treeDisplayName: 'USB Drive',
        directoryPath: '/mnt/share',
        startPadMinutes: 2,
        endPadMinutes: 5,
      );

      final cleared = picked.copyWith(clearFolder: true);

      expect(cleared.treeUri, isNull);
      expect(cleared.treeDisplayName, isNull);
      expect(cleared.directoryPath, isNull);
      expect(cleared.hasCustomFolder, isFalse);
      // Padding is a separate decision and survives the folder reset.
      expect(cleared.startPadMinutes, 2);
      expect(cleared.endPadMinutes, 5);
    });

    test('copyWith keeps untouched fields and replaces the given ones', () {
      const settings = RecordingOutputSettings(
        treeUri: 'content://tree',
        directoryPath: '/mnt/share',
      );

      final updated = settings.copyWith(directoryPath: '/elsewhere');

      expect(updated.treeUri, 'content://tree');
      expect(updated.directoryPath, '/elsewhere');
      expect(updated.startPadMinutes, isNull);
    });

    test('recordingLocationLabel names the chosen folder or the default', () {
      expect(
        recordingLocationLabel(const RecordingOutputSettings()),
        'Downloads/Debrify/Recordings',
      );
      expect(
        recordingLocationLabel(
          const RecordingOutputSettings(
            treeUri: 'content://tree',
            treeDisplayName: 'USB Drive',
          ),
        ),
        'USB Drive',
      );
      expect(
        recordingLocationLabel(
          const RecordingOutputSettings(treeUri: 'content://tree'),
        ),
        'Chosen folder',
      );
      expect(
        recordingLocationLabel(
          const RecordingOutputSettings(directoryPath: r'D:\Recordings'),
        ),
        r'D:\Recordings',
      );
    });
  });

  group('RecordingOutputStore', () {
    test('read on an empty device yields defaults and primes cached', () async {
      final settings = await RecordingOutputStore.read();

      expect(settings, const RecordingOutputSettings());
      expect(RecordingOutputStore.cached, const RecordingOutputSettings());
    });

    test('write then read round-trips and keeps cached in step', () async {
      const settings = RecordingOutputSettings(
        directoryPath: '/mnt/share/Recordings',
        endPadMinutes: 3,
      );

      await RecordingOutputStore.write(settings);
      expect(RecordingOutputStore.cached, settings);

      RecordingOutputStore.cached = const RecordingOutputSettings();
      final readBack = await RecordingOutputStore.read();

      expect(readBack, settings);
      expect(RecordingOutputStore.cached, settings);
    });

    test('a corrupted stored value decodes to defaults', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        RecordingOutputStore.key: '{definitely not json',
      });

      final settings = await RecordingOutputStore.read();

      expect(settings, const RecordingOutputSettings());
      expect(RecordingOutputStore.cached, const RecordingOutputSettings());
    });
  });
}
