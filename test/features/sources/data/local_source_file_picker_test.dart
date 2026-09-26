import 'dart:async';
import 'dart:io';

import 'package:debrify/features/sources/data/local_source_file_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';

class Picker extends FilePicker {
  final response = Completer<FilePickerResult?>();
  FileType? requestedType;
  List<String>? extensions;
  bool? multiple;
  bool? data;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) {
    requestedType = type;
    extensions = allowedExtensions;
    multiple = allowMultiple;
    data = withData;
    return response.future;
  }
}

void main() {
  late Picker picker;
  setUpAll(() => FilePicker.platform = Picker());
  setUp(() {
    final previous = FilePicker.platform;
    picker = Picker();
    FilePicker.platform = picker;
    addTearDown(() => FilePicker.platform = previous);
  });

  test(
    'single-file options are preserved and retirement precedes result access',
    () async {
      var active = true;
      final pending = pickLocalVideoSource(canContinue: () => active);
      expect(picker.requestedType, FileType.custom);
      expect(picker.multiple, isFalse);
      expect(picker.data, isFalse);
      expect(picker.extensions, [
        'mp4',
        'avi',
        'mkv',
        'mov',
        'wmv',
        'flv',
        'webm',
        'm4v',
        '3gp',
        'ts',
        'mts',
        'm2ts',
      ]);
      active = false;
      // This result would throw on .single if the retired operation inspected it.
      picker.response.complete(FilePickerResult([]));
      expect(await pending, isNull);
    },
  );

  for (final mode in ['cancel', 'pathless', 'blank']) {
    test('$mode selection creates no source', () async {
      final pending = pickLocalVideoSource();
      picker.response.complete(
        mode == 'cancel'
            ? null
            : FilePickerResult([
                PlatformFile(
                  name: 'Fixture.mkv',
                  size: 1,
                  path: mode == 'pathless' ? null : '  ',
                ),
              ]),
      );
      expect(await pending, isNull);
    });
  }

  test(
    'selected file uses real metadata rather than picker metadata',
    () async {
      final root = await Directory.systemTemp.createTemp('file-picker-data-');
      addTearDown(() => root.delete(recursive: true));
      final file = await File('${root.path}/Movie.mkv').writeAsBytes([1, 2, 3]);
      final pending = pickLocalVideoSource();
      picker.response.complete(
        FilePickerResult([
          PlatformFile(name: 'Different name.mkv', size: 999, path: file.path),
        ]),
      );
      final source = await pending;
      expect(source!.torrentName, 'Movie.mkv');
      expect(source.localPath, file.path);
      expect(source.localUri, Uri.file(file.path).toString());
      expect(source.localSizeBytes, 3);
      expect(source.isLocalMovieFile, isTrue);
    },
  );
}
