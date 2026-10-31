// Decoding the native drive list, and the space line the chooser shows.

import 'package:debrify/features/recording_output/models/storage_volume_choice.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StorageVolumeChoice.fromMap', () {
    test('reads a full entry', () {
      final volume = StorageVolumeChoice.fromMap({
        'path': '/storage/ABCD/Android/data/com.debrify.app/files/Recordings',
        'label': ' SanDisk USB ',
        'freeBytes': 5 * 1024 * 1024 * 1024,
        'totalBytes': 64 * 1024 * 1024 * 1024,
      });
      expect(
        volume,
        const StorageVolumeChoice(
          path: '/storage/ABCD/Android/data/com.debrify.app/files/Recordings',
          label: 'SanDisk USB',
          freeBytes: 5 * 1024 * 1024 * 1024,
          totalBytes: 64 * 1024 * 1024 * 1024,
        ),
      );
      expect(volume!.name, 'SanDisk USB');
    });

    test('an entry without a path is dropped', () {
      expect(StorageVolumeChoice.fromMap({'label': 'USB'}), isNull);
      expect(StorageVolumeChoice.fromMap({'path': ''}), isNull);
      expect(StorageVolumeChoice.fromMap('not a map'), isNull);
    });

    test('a blank label and unknown space fall back', () {
      final volume = StorageVolumeChoice.fromMap({
        'path': '/storage/X/Recordings',
        'label': '  ',
        'freeBytes': -1,
        'totalBytes': null,
      })!;
      expect(volume.label, isNull);
      expect(volume.name, 'USB drive');
      expect(volume.freeBytes, isNull);
      expect(storageVolumeSpaceText(volume), isNull);
    });
  });

  group('storageVolumeSpaceText', () {
    test('free of total in GB', () {
      expect(
        storageVolumeSpaceText(
          const StorageVolumeChoice(
            path: '/p',
            freeBytes: 12 * 1024 * 1024 * 1024 + 300 * 1024 * 1024,
            totalBytes: 64 * 1024 * 1024 * 1024,
          ),
        ),
        '12.3 GB free of 64.0 GB',
      );
    });

    test('under a gigabyte in MB, total optional', () {
      expect(
        storageVolumeSpaceText(
          const StorageVolumeChoice(path: '/p', freeBytes: 512 * 1024 * 1024),
        ),
        '512 MB free',
      );
    });
  });
}
