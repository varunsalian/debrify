import 'dart:io';
import 'dart:typed_data';

import 'package:debrify/services/download_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory destination;

  setUp(() async {
    destination = await Directory.systemTemp.createTemp(
      'debrify-generated-download-',
    );
    DownloadService.instance.debugOverrideGeneratedFileDirectory(destination);
  });

  tearDown(() async {
    DownloadService.instance.debugOverrideGeneratedFileDirectory(null);
    if (await destination.exists()) {
      await destination.delete(recursive: true);
    }
  });

  test(
    'generated files are written through the download destination',
    () async {
      final bytes = Uint8List.fromList(<int>[0x50, 0x4b, 0x03, 0x04]);

      final saved = await DownloadService.instance.saveGeneratedFile(
        fileName: 'debrify-tv-channels.zip',
        bytes: bytes,
        mimeType: 'application/zip',
      );

      final file = File(saved.reference);
      expect(file.parent.path, destination.path);
      expect(saved.displayLocation, file.path);
      expect(await file.readAsBytes(), bytes);
    },
  );

  test('generated files do not overwrite an earlier export', () async {
    final first = await DownloadService.instance.saveGeneratedFile(
      fileName: 'debrify-profile.json',
      bytes: Uint8List.fromList(<int>[1]),
      mimeType: 'application/json',
    );
    final second = await DownloadService.instance.saveGeneratedFile(
      fileName: 'debrify-profile.json',
      bytes: Uint8List.fromList(<int>[2]),
      mimeType: 'application/json',
    );

    expect(first.reference, isNot(second.reference));
    expect(second.reference, endsWith('debrify-profile (1).json'));
    expect(await File(first.reference).readAsBytes(), <int>[1]);
    expect(await File(second.reference).readAsBytes(), <int>[2]);
  });

  test('generated filenames cannot escape the download destination', () async {
    final saved = await DownloadService.instance.saveGeneratedFile(
      fileName: '../channels.zip',
      bytes: Uint8List.fromList(<int>[3]),
    );

    expect(File(saved.reference).parent.path, destination.path);
    expect(await File(saved.reference).readAsBytes(), <int>[3]);
  });
}
